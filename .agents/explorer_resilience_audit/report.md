# تقرير التحقيق الجنائي والرقابي الشامل لسجلات التدقيق (Audit Logs & Forensics Survey)

<div dir="rtl">

## 1. الملخص التنفيذي (Executive Summary)

أجرى فريق التحقيق الجنائي والرقابي فحصاً عميقاً وشاملاً لمنظومة تسجيل الرقابة والتدقيق (Audit Trail & Operation Forensics) في نظام **SmartPower Utility ERP**، مغطياً طبقات قاعدة بيانات PostgreSQL 18، الخادم الخلفي بلغة Go Fiber (`server/`)، الإجراءات المخزنة (Stored Procedures)، واجهات العرض في React Desktop (`frontend/`)، بالإضافة إلى تحليل البيانات الحية في قاعدة البيانات النشطة `smartpower_db`.

### أبرز الحقائق المكتشفة باختصار:
1. **غياب تام لعناوين الـ IP (نسبة 100% مفقودة)**: على الرغم من وجود عمود `ip_address` في جدول قاعدة البيانات `audit_logs`، إلا أن نموذج GORM في Go (`models.AuditLog`) أسقطه تماماً، ولا يقوم خادم Go بتمرير أو حفظ عنوان IP أبداً، مما أدى إلى أن 100% من السجلات في قاعدة البيانات تحتوي على `ip_address = NULL`.
2. **غياب مصفوفة الفروقات (No Before/After Values)**: لا يحتوي جدول التدقيق ولا نماذج Go على حقول `old_values` أو `new_values`. يتم تخزين رسائل نصية عامة ومبهمة مثل `"تعديل فوري في الجدول للمشترك رقم [70]"` دون توثيق الحقل المعدل (هل تم تغيير القراءة؟ السعر؟ المديونية؟ الهاتف؟) ودون توثيق القيمة السابقة أو الجديدة.
3. **فقدان هوية المستخدم لـ 24% من السجلات الحية (38 من أصل 158)**: يتم تسجيل حركات هامة مثل تفعيل التراخيص، وإلغاء طوابير الواتساب، وإعادة المحاولة بقيمة `user_id = NULL` لعدم تفعيل وسيط المصادقة `AuthRequired` على مساراتها.
4. **عمليات تشغيلية ومالية حرجة غير مسجلة نهائياً (Bypassed Operations)**:
   - اعتماد وسندات التحصيل ورفضها (`ApprovePayment` / `RejectPayment`).
   - تعديل قراءات العدادات الفردية (`UpdateReading`).
   - استيراد القراءات المجمعة عبر ملفات إكسل (`ImportExcel`).
   - تصدير بيانات الدورات والفواتير (`ExportCycleExcel`).
   - إنشاء النسخ الاحتياطية اليدوية (`TriggerBackup`).
   - محاولات تسجيل الدخول الفاشلة (`LOGIN_FAILED`) أو تسجيل الخروج (`LOGOUT`).
   - كافة عمليات القراءة والاستعلام (Read / Query Operations).
5. **ابتلاع الأخطاء والإسقاط الصامت للسجلات عند التزامن العالي**: تستخدم الدالة المركزية `logAudit` التعبير `_ = h.db.Create(...).Error`، مما يؤدي إلى ابتلاع أي خطأ في قاعدة البيانات (مثل نفاد مسار الاتصالات `MaxOpenConns` تحت الضغط المتزامن) وإسقاط قيد التدقيق بصمت تام دون تنبيه أو تسجيل خطأ، مع إعادة كود نجاح HTTP 200 للمستخدم!
6. **خلل التوجيه والنسب في الفواتير (Entity Misattribution Bug)**: عند تعديل خلية فاتورة عبر مسار `/api/invoices/:id/cell-update`، يقوم المعالج بتسجيل المعرف كمعرف مشترك `Entity: CUSTOMER` وليس فاتورة، مما ينسب التعديل لمشترك خاطئ في السجل الرقابي!
7. **ثغرة التلاعب الزمني في الإجراءات المخزنة (Timestamp Tampering)**: يقبل إجراء `rpc_submit_meter_reading` و `rpc_submit_payment` تاريخ القراءة أو السداد من العميل ويمرره كـ `created_at` لسجل التدقيق بدلاً من استخدام التوقيت الحقيقي للخادم `CURRENT_TIMESTAMP`.
8. **انعدام الاختبارات الآلية (Zero Test Coverage)**: لا يوجد أي اختبار آلي واحد في كامل المستودع يفحص أو يتحقق من سلامة تسجيل قيود التدقيق.

---

## 2. فحص هيكل جدول التدقيق في PostgreSQL (Schema Investigation)

### 2.1 بنية الجدول والحقول
تم فحص ملف التهيئة الأساسي `dist_portable/schema/init_schema.sql` (الأسطر 1529–1560) وملف التعريف `database/02_tables_and_constraints.sql` (الأسطر 348–365). بنية الجدول المعرفة هي:

```sql
CREATE TABLE public.audit_logs (
    id bigint NOT NULL,
    user_id bigint,
    action character varying(50) NOT NULL,
    entity character varying(50) NOT NULL,
    entity_id character varying(100),
    details text,
    ip_address character varying(50),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);

CREATE SEQUENCE public.audit_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.audit_logs_id_seq OWNED BY public.audit_logs.id;
ALTER TABLE ONLY public.audit_logs ALTER COLUMN id SET DEFAULT nextval('public.audit_logs_id_seq'::regclass);
```

### 2.2 الفهارس والقيود (Indexes & Constraints)
- **المفتاح الأساسي**: `audit_logs_pkey PRIMARY KEY (id)`.
- **المفتاح الأجنبي**:
  ```sql
  ALTER TABLE ONLY public.audit_logs
      ADD CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;
  ```
  *ملاحظة رقابية*: عند حذف أي مستخدم من جدول `users`، يقوم القيد تلقائياً بتصفير هوية المستخدم `user_id = NULL` في جميع السجلات التاريخية السابقة التي أنجزها، مما يمسح الأثر الجنائي لذلك المستخدم في حال الحذف الصلب (Hard Delete).
- **الفهارس المنشأة**:
  1. `CREATE INDEX idx_audit_logs_created_at ON public.audit_logs USING btree (created_at DESC);`
  2. `CREATE INDEX idx_audit_logs_entity ON public.audit_logs USING btree (entity, entity_id);`
  3. `CREATE INDEX idx_audit_logs_user_id ON public.audit_logs USING btree (user_id);`

### 2.3 الانحرافات المعمارية في الهيكل مقارنة بالمعايير الجنائية:
1. **اسم العمود**: تم تسمية العمود `entity` بدلاً من `entity_type`.
2. **انعدام أعمدة الفروقات المنظمة (JSONB Diffs)**: لا توجد أعمدة `old_values` أو `new_values`. البديل الحالي هو عمود نصي غير منظم `details text`.
3. **غياب فهرس على عمود `action`**: على الرغم من أن واجهة المستخدم وفلتر الاستعلام يتيحان التصفية بنوع الحركة (`action`)، لا يوجد B-tree index على حقل `action`.
4. **غياب فهرس البحث بالنص (Full-Text / Trigram Index)**: معالج استعلام السجلات ينفذ `ILIKE %search%` على 4 حقول مجتمعة، مما يؤدي إلى مسح متسلسل كامل (Full Table Scan) عند تزايد حجم البيانات.

---

## 3. تتبع آليات التسجيل في كود Go الخلفي والإجراءات المخزنة

### 3.1 نموذج GORM في خادم Go
في ملف `server/internal/models/models.go` (الأسطر 246–259):

```go
type AuditLog struct {
	ID        int64      `gorm:"primaryKey;autoIncrement;column:id" json:"id"`
	UserID    *int64     `gorm:"column:user_id" json:"user_id,omitempty"`
	User      *User      `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Action    string     `gorm:"type:varchar(50);not null;column:action" json:"action"`
	Entity    string     `gorm:"type:varchar(50);not null;column:entity" json:"entity"`
	EntityID  *string    `gorm:"type:varchar(50);column:entity_id" json:"entity_id,omitempty"`
	Details   *string    `gorm:"type:text;column:details" json:"details,omitempty"`
	CreatedAt *time.Time `gorm:"default:now();column:created_at" json:"created_at"`
}
```
**الملاحظة الجنائية**: حقل `IPAddress` غائب كلياً عن بنية الـ Struct. وبما أن النموذج لا يعرّف هذا الحقل، فإن مكتبة GORM لا تقرأ ولا تكتب هذا العمود في أي عملية استعلام أو إدخال إطلاقاً.

### 3.2 دالة التسجيل المركزية `logAudit`
في ملف `server/internal/handlers/handlers.go` (الأسطر 1724–1738):

```go
func (h *Handlers) logAudit(c *fiber.Ctx, action, entity string, entityID *string, details string) {
	var userID *int64
	if claims, ok := c.Locals("user").(*services.JWTClaims); ok && claims != nil {
		userID = &claims.UserID
	}
	now := time.Now().UTC()
	_ = h.db.Create(&models.AuditLog{
		UserID:    userID,
		Action:    action,
		Entity:    entity,
		EntityID:  entityID,
		Details:   &details,
		CreatedAt: &now,
	}).Error
}
```
**نقاط القصور التقنية في `logAudit`**:
1. تجاهل تام للعنوان الرقمي للعميل: لم يتم استدعاء `c.IP()` أو قراءة ترويسات `X-Forwarded-For`.
2. الإسقاط الصامت للأخطاء: استخدام `_ = h.db.Create(...).Error` يبتلع أي فشل اتصال دون حتى كتابة سطر في ملف `log.Printf`.
3. التشغيل المنفصل عن المعاملة (Out-of-Transaction): تعمل الدالة على اتصال `h.db` العام خارج سياق المعاملات المالية المفتوحة.

### 3.3 تسجيل التدقيق في الإجراءات المخزنة (PostgreSQL Stored Procedures)
تم التأكد عبر فحص شامل لكافة ملفات SQL من **عدم وجود أي مشغلات قواعد بيانات (Triggers)** تسجل في جدول `audit_logs`. المشغلات الوحيدة الموجودة في النظام هي `trg_invoices_set_invoice_number` و `trg_meter_readings_monotonic`.

التسجيل عبر قاعدة البيانات محصور فقط في 3 دوال مخزنة (Stored Functions):
1. **`rpc_recalculate_customer_cascade`** (`init_schema.sql`: الأسطر 456 و 715):
   تسجل الحركة `RECALCULATE_CASCADE` عند إعادة الاحتساب التراجعي لدورات المشترك. هذا الإجراء هو الوحيد في كامل النظام الذي ينشئ كائن JSONB تفصيلياً داخل حقل `details`:
   ```sql
   jsonb_build_object(
     'trigger_invoice_id', p_trigger_invoice_id,
     'trigger_reading_id', p_trigger_reading_id,
     'affected_cycles', to_jsonb(v_affected_cycles),
     'affected_count', array_length(v_affected_cycles, 1),
     'final_customer_balance', v_cascade_arrears,
     'is_meter_reset', p_is_meter_reset
   )::TEXT
   ```
2. **`rpc_submit_meter_reading`** (`init_schema.sql`: الأسطر 930 و 1141):
   تسجل الحركة `READING_CREATE_RPC` للكيان `MeterReading`.
   *خلل جنائي*: تمرر المعامل `p_reading_date` (تاريخ القراءة المدخل من الكلاينت) كقيمة لعمود `created_at` بدلاً من توقيت السيرفر الفعلي `CURRENT_TIMESTAMP`.
3. **`rpc_submit_payment`** (`init_schema.sql`: الأسطر 1319 و 1498):
   تسجل الحركة `PAYMENT_SUBMIT_FIFO` للكيان `Payment`.
   *خلل جنائي*: تمرر المعامل `p_payment_date` كقيمة لعمود `created_at`.

---

## 4. مصفوفة تغطية العمليات (Operation Coverage Matrix)

يوضح الجدول التالي نتائج الفحص الدقيق لكل عملية في النظام ومدى توثيقها رقابياً:

| تصنيف العملية | نوع الإجراء | مسار الـ API | حالة التوثيق | كود الإجراء (Action) | الكيان (Entity) | التفاصيل المسجلة والعيوب الجنائية |
|---|---|---|---|---|---|---|
| **المصادقة (Auth)** | تسجيل دخول ناجح | `POST /api/auth/login` | **موثق** | `LOGIN` | `USER` | "تسجيل دخول ناجح لمستخدم النظام" - يوثق المعرف دون IP |
| **المصادقة (Auth)** | تسجيل دخول فاشل | `POST /api/auth/login` | **غير موثق** | - | - | **ثغرة أمنية**: محاولات التخمين والاختراق لا تترك أي أثر |
| **المصادقة (Auth)** | تسجيل خروج | - | **غير موثق** | - | - | لا يوجد مسار تسجيل خروج موثق في السيرفر |
| **المستخدمون (Users)** | إضافة مستخدم | `POST /api/users` | **موثق** | `CREATE_USER` | `USER` | يوثق الاسم الكامل والرتبة |
| **المستخدمون (Users)** | تعديل مستخدم | `PUT /api/users/:id` | **موثق** | `UPDATE_USER` | `USER` | يوثق الاسم الكامل دون تفاصيل الصلاحيات المعدلة |
| **المستخدمون (Users)** | تصفير كلمة المرور | `POST /api/users/:id/reset-password` | **موثق** | `RESET_PASSWORD` | `USER` | يوثق معرف المستخدم فقط |
| **المشتركون (Customers)** | إضافة مشترك جديد | `POST /api/customers` | **موثق** | `CUSTOMER_CREATE` | `CUSTOMER` | يوثق الاسم ورقم الاشتراك دون الرصيد الافتتاحي أو العداد |
| **المشتركون (Customers)** | تعديل بيانات مشترك | `PUT /api/customers/:id` | **موثق** | `CUSTOMER_UPDATE` | `CUSTOMER` | يوثق الاسم ورقم الاشتراك دون ذكر الحقول المعدلة فعلياً |
| **المشتركون (Customers)** | حذف مشترك (Soft) | `DELETE /api/customers/:id` | **موثق** | `CUSTOMER_DELETE` | `CUSTOMER` | يوثق المعرف فقط: "تم حذف المشترك رقم [10]" دون الاسم |
| **جدول البيانات (Grid)** | تعديل مباشر في الخلية | `PATCH /customers/:id/grid-cell` | **موثق جزئياً** | `GRID_CELL_UPDATE` | `CUSTOMER` | نص مبهم: "تعديل فوري في الجدول للمشترك رقم [X]" بدون الفروقات |
| **جدول البيانات (Grid)** | تعديل خلية فاتورة | `PATCH /invoices/:id/cell-update` | **مشوه (Bug)** | `GRID_CELL_UPDATE` | `CUSTOMER` | **خلل**: يوثق معرف الفاتورة على أنه معرف مشترك! |
| **القراءات (Readings)** | تسجيل قراءة جديدة | `POST /api/readings` | **موثق** | `READING_CREATE` | `READING` | يوثق رقم المشترك وقيمة القراءة |
| **القراءات (Readings)** | تعديل قراءة عداد | `PUT /api/readings/:id` | **غير موثق** | - | - | **تجاوز رقابي**: المعالج `UpdateReading` لا يستدعي `logAudit` |
| **القراءات (Readings)** | اعتماد قراءة وفاتورة | `POST /api/readings/approve/:id` | **موثق** | `READING_APPROVE` | `READING` | يوثق معرف القراءة |
| **القراءات (Readings)** | رفض قراءة عداد | `POST /api/readings/reject/:id` | **موثق** | `READING_REJECT` | `READING` | يوثق معرف القراءة وسبب الرفض |
| **القراءات (Readings)** | اعتماد شامل للقراءات | `POST /api/readings/approve-all` | **موثق** | `READING_APPROVE_ALL`| `READING` | رسالة عامة دون تحديد قائمة المعرفات المعتمدة |
| **القراءات (Readings)** | اعتماد وإرسال واتساب | `POST /readings/:id/approve-and-whatsapp` | **موثق** | `READING_APPROVE_AND_WHATSAPP` | `READING` | يوثق المعرف فقط |
| **التحصيل (Payments)** | إنشاء سند قبض وسداد | `POST /api/payments` | **موثق** | `CREATE_PAYMENT` | `PAYMENT` | يوثق رقم السند والمبلغ وعدد الفواتير الموزع عليها |
| **التحصيل (Payments)** | اعتماد سند قبض | `POST /api/payments/approve/:id` | **غير موثق** | - | - | **تجاوز مالي خطير**: لا يوجد أي قيد تدقيق لاعتماد السند! |
| **التحصيل (Payments)** | رفض سند قبض | `POST /api/payments/reject/:id` | **غير موثق** | - | - | **تجاوز مالي خطير**: لا يوجد أي قيد تدقيق لرفض السند! |
| **التحصيل (Payments)** | إرسال سند بالواتساب | `POST /payments/:id/send-whatsapp` | **موثق** | `WHATSAPP_SEND_PAYMENT` | `PAYMENT` | يوثق رقم السند واسم المشترك |
| **الفواتير (Invoices)** | إرسال فاتورة بالواتساب | `POST /whatsapp/send-invoice` | **موثق** | `WHATSAPP_SEND_INVOICE` | `INVOICE` | يوثق رقم الفاتورة واسم المشترك |
| **الإنذارات (Warnings)**| إرسال إنذار فصل | `POST /whatsapp/send-warning` | **موثق** | `WHATSAPP_SEND_WARNING` | `CUSTOMER` | يوثق اسم المشترك والمبلغ المستحق |
| **الإنذارات (Warnings)**| إنذار فصل جماعي | `POST /whatsapp/send-bulk-warnings` | **موثق** | `WHATSAPP_SEND_BULK_WARNINGS` | `WHATSAPP` | يوثق عدد الرسائل المدرجة في الطابور |
| **طابور الواتساب** | إلغاء الطابور وتفريغه | `DELETE /whatsapp/queue/pending` | **موثق بدون مستخدم** | `WHATSAPP_CANCEL_QUEUE` | `WHATSAPP` | **مجهول الفاعل**: لا يوجد `AuthRequired` -> `user_id = NULL` |
| **طابور الواتساب** | حذف رسالة | `DELETE /whatsapp/messages/:id` | **موثق بدون مستخدم** | `WHATSAPP_DELETE_MESSAGE` | `WHATSAPP` | **مجهول الفاعل**: لا يوجد `AuthRequired` -> `user_id = NULL` |
| **طابور الواتساب** | إعادة إرسال رسالة | `POST /whatsapp/messages/:id/retry` | **موثق بدون مستخدم** | `WHATSAPP_RETRY_MESSAGE` | `WHATSAPP` | **مجهول الفاعل**: لا يوجد `AuthRequired` -> `user_id = NULL` |
| **طابور الواتساب** | تفريغ السجل بالكامل | `DELETE /whatsapp/messages` | **موثق بدون مستخدم** | `WHATSAPP_CLEAR_ALL` | `WHATSAPP` | **مجهول الفاعل**: مسح شامل بدون معرف المستخدم الفاعل! |
| **الإعدادات (Settings)**| تحديث التعرفة والرسوم | `PUT /api/settings` | **موثق** | `UPDATE_SETTINGS` | `SETTINGS` | رسالة عامة دون بيان التعرفة القديمة والجديدة |
| **الترخيص (License)** | تفعيل ترخيص | `POST /api/license/activate` | **موثق بدون مستخدم** | `LICENSE_ACTIVATE` | `LICENSE` | يوثق المفتاح واسم العميل (المسار عام بدون مصادقة) |
| **الترخيص (License)** | كود طوارئ أوفلاين | `POST /api/license/emergency-code` | **موثق بدون مستخدم** | `LICENSE_EMERGENCY_UNLOCK` | `LICENSE` | يوثق كود الطوارئ (المسار عام بدون مصادقة) |
| **استيراد إكسل (Excel)**| استيراد قراءات مجمعة | `POST /api/import/readings` | **غير موثق** | - | - | **تجاوز خطير**: إدخال مئات القراءات لا يسجل قيد تدقيق واحد! |
| **تصدير إكسل (Excel)**| تصدير كشوفات الدورات | `GET /api/export/cycle` | **غير موثق** | - | - | تصدير كامل البيانات المالية لا يترك أي أثر رقابي |
| **النسخ الاحتياطي** | إنشاء نسخة فورية | `POST /api/backup/now` | **غير موثق** | - | - | تفريغ قاعدة البيانات يدوياً لا يسجل في التدقيق |
| **عمليات القراءة (Read)**| استعلام المشتركين والفواتير | `GET /customers`, `GET /invoices` | **غير موثق** | - | - | انعدام تام لسجلات الوصول والاستعلام للبيانات الحساسة |

---

## 5. التحليل الجنائي الميداني للبيانات الحية (Live Forensics Inspection)

تم الاتصال بقاعدة البيانات الحية `smartpower_db` على المنفذ 5432 وتنفيذ استعلامات رقابية على جدول `audit_logs`، وجاءت النتائج كالتالي:

### 5.1 إحصائية السجلات والنسب:
- **إجمالي السجلات المسجلة**: 158 سجلاً.
- **السجلات ذات مستخدم معروف (`user_id IS NOT NULL`)**: 120 سجلاً (75.9%).
- **السجلات مجهولة المستخدم (`user_id IS NULL`)**: 38 سجلاً (24.1%).
- **السجلات التي تحتوي على عنوان IP (`ip_address IS NOT NULL`)**: 0 سجل (0.00%!).

### 5.2 تفصيل السجلات مجهولة الفاعل (38 سجلاً):
1. `LICENSE_ACTIVATE`: 22 حركة (تفعيل تراخيص عبر واجهة بدون جلسة مسجلة).
2. `LICENSE_EMERGENCY_UNLOCK`: 6 حركات (أكواد طوارئ بدون جلسة).
3. `READING_CREATE_RPC`: 5 حركات (قراءات تم إدخالها عبر الاستدعاء المباشر للإجراء دون تمرير معرف المحصل).
4. `WHATSAPP_CANCEL_QUEUE`: 2 حركات (إلغاء طابور الواتساب بدون مصادقة).
5. `WHATSAPP_RETRY_MESSAGE`: حركة واحدة.
6. `WHATSAPP_RETRY_ALL`: حركة واحدة.
7. `WHATSAPP_DELETE_MESSAGE`: حركة واحدة.

### 5.3 عينة حية من قيود التعديل المباشر `GRID_CELL_UPDATE`:
```text
 id | user_id |      action      |  entity  | entity_id |                details                 |          created_at           
----+---------+------------------+----------+-----------+----------------------------------------+-------------------------------
 33 |       1 | GRID_CELL_UPDATE | CUSTOMER | 70        | تعديل فوري في الجدول للمشترك رقم [70]  | 2026-09-07 09:29:16.903724+03
 35 |       1 | GRID_CELL_UPDATE | CUSTOMER | 71        | تعديل فوري في الجدول للمشترك رقم [71]  | 2026-09-07 09:29:20.663346+03
 37 |       1 | GRID_CELL_UPDATE | CUSTOMER | 70        | تعديل فوري في الجدول للمشترك رقم [70]  | 2026-09-07 09:29:24.606609+03
 38 |       1 | GRID_CELL_UPDATE | CUSTOMER | 71        | تعديل فوري في الجدول للمشترك رقم [71]  | 2026-09-07 09:29:24.621025+03
 41 |       1 | GRID_CELL_UPDATE | CUSTOMER | 175       | تعديل فوري في الجدول للمشترك رقم [175] | 2026-09-07 10:07:44.56329+03
```
**الاستنتاج الجنائي**: القيود أعلاه تثبت استحالة قيام أي مدقق مالي أو أمني بتحديد ما تم تغييره داخل الخلية! لا توجد أسماء حقول، ولا قيم سابقة، ولا قيم لاحقة.

---

## 6. صمود النظام تحت العمليات المتزامنة والحدود المعاملاتية (Concurrency & Resilience)

### 6.1 ابتلاع أخطاء الاتصال وفقدان السجلات (Error Swallowing)
في ملف `server/internal/database/db.go` تم ضبط الحد الأقصى للاتصالات المفتوحة:
```go
sqlDB.SetMaxOpenConns(50)
```
عندما يتعرض النظام لضغط متزامن مكثف (أكثر من 50 طلباً متزامناً يقومون بعمليات كتابة وتعديل)، تنتظر الطلبات الجديدة دورها. وإذا انقضت مهلة الاتصال (Timeout) أو حدث تعليق، تعيد عملية `h.db.Create(&models.AuditLog{...})` خطأً برمجياً.
وبما أن الكود يستخدم:
```go
_ = h.db.Create(&models.AuditLog{...}).Error
```
فإن الخطأ يتم تجاهله تماماً؛ الطلب ينتهي بنجاح HTTP 200 أو HTTP 201 للمستخدم، بينما يسقط سجل التدقيق في الهاوية دون أن يوثق في قاعدة البيانات!

### 6.2 تباين الحدود المعاملاتية (Transaction Boundary Inconsistency)
هناك عدم اتساق منهجي حاد بين عمليتي الفوترة والتحصيل:
1. في **التحصيل (`CreatePayment`)**: قيد التدقيق مدرج داخل نفس المعاملة المالية (`tx.Create(&models.AuditLog{...})` في `payment_service.go:342`).
   - *النتيجة*: إذا فشلت المعاملة أو تم التراجع عنها (Rollback) بسبب قيد مالي، يلغى قيد التدقيق أيضاً، وبالتالي لا تترك محاولات السداد الفاشلة أو الاحتيالية أي أثر في السجل.
2. في **القراءات والمشتركين والجدول (`CreateReading`, `CreateCustomer`, `UpdateGridCell`)**: قيد التدقيق ينفذ خارج المعاملة في المعالج (`handlers.go`).
   - *النتيجة*: إذا نجحت المعاملة المالية ولكن انهار الخادم أو حدث انقطاع مفاجئ للتيار الكهربائي قبل سطر `h.logAudit`، تبقى التغييرات المالية محفوظة في قاعدة البيانات بينما ينعدم قيد التدقيق المرتبط بها كلياً!

### 6.3 ثغرة تزوير توقيت التدقيق عبر الإجراءات المخزنة (Timestamp Backdating)
في الإجراء المخزن `rpc_submit_meter_reading`:
```sql
INSERT INTO public.audit_logs (
    action, entity, entity_id, user_id, details, created_at
) VALUES (
    'READING_CREATE_RPC', 'MeterReading', v_reading_id::TEXT, p_collector_user_id,
    ...,
    p_reading_date  -- <--- ثغرة: اعتماد تاريخ الإدخال بدلاً من توقيت الخادم الحقيقي
);
```
إذا قام مستخدم أو تطبيق موبايل بإرسال قراءة بتاريخ قديم (مثلاً 2025-01-01)، سيظهر قيد التدقيق في السجلات بتاريخ 2025 بدلاً من توقيت التنفيذ الفعلي في 2026، مما يدمر خط الزمن الجنائي (Forensic Timeline) ويعطل القدرة على كشف التلاعبات اللاحقة.

---

## 7. فحص واجهة المستخدم للتدقيق (Frontend UI & API Gap Analysis)

### 7.1 شاشة سجل العمليات والتدقيق الشامل (`AuditLogs.tsx`)
عند فحص `frontend/src/pages/AuditLogs.tsx` تبين ما يلي:
- الواجهة مصممة بشكل احترافي وجاهزة للتعامل مع أكثر من 20 نوع حركة وكيان (مثل شارات `PAYMENT_APPROVE`, `PAYMENT_REJECT`, `IMPORT_READINGS`, `EXPORT_EXCEL`, `LOGOUT`).
- ومع ذلك، فإن هذه الشارات لا تظهر أبداً للمستخدم لأن الخادم الخلفي لا يرسل هذه الأكواد إطلاقاً.
- دالة `logActivityApi` المعرفة في `frontend/src/services/audit.service.ts` غير مستدعاة في أي مكون في التطبيق.

### 7.2 استجابة الـ API الحالية ومقارنتها بالمتطلبات الرقابية:
استجابة مسار `GET /api/audit-logs`:
```json
{
  "id": 174,
  "user_id": 1,
  "user": {
    "id": 1,
    "username": "admin",
    "full_name": "مدير النظام",
    "role": "ADMIN"
  },
  "action": "CREATE_PAYMENT",
  "entity": "PAYMENT",
  "entity_id": "REC-2026-000018",
  "details": "تم تحصيل سند قبض وسداد بمبلغ 93000.00 ريال وتوزيعه آلياً على 1 فاتورة مستحقة",
  "created_at": "2026-09-09T13:58:24.338507+03:00"
}
```
**العناصر المفقودة من الاستجابة**:
- `ip_address`: مفقود تماماً.
- `old_values`: مفقود تماماً.
- `new_values`: مفقود تماماً.

---

## 8. التوصيات الفنية المقترحة للتحصين الجنائي (Actionable Hardening Roadmap)

بناءً على نتائج هذا الفحص الشامل، نوصي بالإصلاحات التالية قبل الانتقال لمرحلة الاعتماد النهائي:

### أ. على مستوى قاعدة بيانات PostgreSQL:
1. إضافة عمودين بصيغة JSONB إلى جدول `audit_logs`:
   ```sql
   ALTER TABLE public.audit_logs 
   ADD COLUMN IF NOT EXISTS old_values JSONB,
   ADD COLUMN IF NOT EXISTS new_values JSONB;
   ```
2. فرض التوقيت التلقائي غير القابل للتعديل:
   تعديل الإجراءات المخزنة (`rpc_submit_meter_reading` و `rpc_submit_payment`) لتستخدم دائماً `CURRENT_TIMESTAMP` في حقل `created_at`.
3. إضافة فهارس لتسريع البحث والاستعلام:
   ```sql
   CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON public.audit_logs(action);
   CREATE EXTENSION IF NOT EXISTS pg_trgm;
   CREATE INDEX IF NOT EXISTS idx_audit_logs_details_trgm ON public.audit_logs USING gin (details gin_trgm_ops);
   ```

### ب. على مستوى خادم Go (`server/`):
1. تحديث نموذج `models.AuditLog` ليشمل `IPAddress`, `OldValues`, `NewValues`:
   ```go
   type AuditLog struct {
       ID        int64           `gorm:"primaryKey;autoIncrement;column:id" json:"id"`
       UserID    *int64          `gorm:"column:user_id" json:"user_id,omitempty"`
       User      *User           `gorm:"foreignKey:UserID" json:"user,omitempty"`
       Action    string          `gorm:"type:varchar(50);not null;column:action" json:"action"`
       Entity    string          `gorm:"type:varchar(50);not null;column:entity" json:"entity"`
       EntityID  *string         `gorm:"type:varchar(100);column:entity_id" json:"entity_id,omitempty"`
       Details   *string         `gorm:"type:text;column:details" json:"details,omitempty"`
       IPAddress *string         `gorm:"type:varchar(50);column:ip_address" json:"ip_address,omitempty"`
       OldValues *datatypes.JSON `gorm:"type:jsonb;column:old_values" json:"old_values,omitempty"`
       NewValues *datatypes.JSON `gorm:"type:jsonb;column:new_values" json:"new_values,omitempty"`
       CreatedAt *time.Time      `gorm:"default:now();column:created_at" json:"created_at"`
   }
   ```
2. استخراج عنوان الـ IP الحقيقي في `logAudit`:
   ```go
   clientIP := c.IP()
   if fwd := c.Get("X-Forwarded-For"); fwd != "" {
       clientIP = strings.Split(fwd, ",")[0]
   }
   ```
3. تسجيل العمليات المفقودة فوراً:
   - إضافة قيود تدقيق في `ApprovePayment` و `RejectPayment` و `UpdateReading` و `ImportExcel`.
   - تسجيل محاولات تسجيل الدخول الفاشلة `LOGIN_FAILED` في `auth_service.go` لتتبع محاولات الاختراق.
4. إصلاح خطأ التوجيه في تعديل خلايا الفواتير:
   في `handlers.go`: التحقق مما إذا كان المعرف المستهدف يتبع فاتورة أو مشترك وتحديد نوع الكيان `Entity: INVOICE` بشكل صحيح.
5. استبدال الابتلاع الصامت للأخطاء (`_ = ...`) بنظام معالجة موثوق يكتب تحذيراً صريحاً في سجلات السيرفر أو يدرج الحركة في طابور محلي عند تعذر الاتصال الفوري.

</div>
