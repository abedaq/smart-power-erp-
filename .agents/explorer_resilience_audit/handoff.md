# Handoff Report — Audit Logs & Forensics Survey

<div dir="rtl">

## 1. Observation (الملاحظات المباشرة والأدلة المادية)

1. **بنية جدول `audit_logs` ومطابقتها**:
   - في `dist_portable/schema/init_schema.sql` (الأسطر 1532–1541) و `database/02_tables_and_constraints.sql` (الأسطر 350–359):
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
     ```
   - لا توجد أعمدة `old_values` أو `new_values`. اسم العمود هو `entity` وليس `entity_type`.
2. **نموذج Go GORM يُسقط حقل عنوان الـ IP كلياً**:
   - في `server/internal/models/models.go` (الأسطر 246–255):
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
     حقل `IPAddress` غائب تماماً.
3. **الدالة المركزية `logAudit` وابتلاع الأخطاء**:
   - في `server/internal/handlers/handlers.go` (الأسطر 1724–1738):
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
     يتم تجاهل الخطأ عبر `_ = ...` ولا يتم استخراج عنوان IP من `c.IP()`.
4. **فحص قاعدة البيانات الحية عبر `psql.exe`**:
   - الأمر: `& "d:\elctercity\dist_portable\pgsql\bin\psql.exe" -U postgres -d smartpower_db -p 5432 -c "SELECT COUNT(*) as total, COUNT(user_id) as with_user, COUNT(*) - COUNT(user_id) as null_user, COUNT(ip_address) as with_ip FROM audit_logs;"`
   - النتيجة:
     `total: 158 | with_user: 120 | null_user: 38 | with_ip: 0`
   - 100% من السجلات عنوان IP فيها هو `NULL`!
   - 24% من السجلات (38 حركة) مجهولة الفاعل (`user_id = NULL`).
5. **عمليات مالية وتشغيلية غير مسجلة (Bypassed)**:
   - `ApprovePayment` في `server/internal/handlers/handlers.go` (الأسطر 670–679): لا يستدعي `logAudit`.
   - `RejectPayment` في `server/internal/handlers/handlers.go` (الأسطر 681–694): لا يستدعي `logAudit`.
   - `UpdateReading` في `server/internal/handlers/handlers.go` (الأسطر 639–666): لا يستدعي `logAudit`.
   - `ImportExcel` في `server/internal/handlers/handlers.go` (الأسطر 448–469): لا يستدعي `logAudit`.
   - محاولة تسجيل الدخول الفاشلة في `server/internal/services/auth_service.go` (الأسطر 40–52): لا تسجل أي حركة في التدقيق.
6. **خلل التوجيه عند تعديل الفواتير (Entity Misattribution Bug)**:
   - في `server/cmd/server/main.go` الأسطر 522–523، يوجه المسار `/api/invoices/:id/cell-update` إلى `h.UpdateGridCell`.
   - وفي `server/internal/handlers/handlers.go` السطر 519، تسجل الدالة:
     `h.logAudit(c, "GRID_CELL_UPDATE", "CUSTOMER", strPtr(fmt.Sprintf("%d", id)), ...)`
     حيث يوثق معرف الفاتورة كمعرف مشترك!
7. **ثغرة التلاعب الزمني في الإجراءات المخزنة**:
   - في `dist_portable/schema/init_schema.sql` السطر 938:
     إجراء `rpc_submit_meter_reading` يمرر المعامل `p_reading_date` في عمود `created_at` لسجل التدقيق بدلاً من `CURRENT_TIMESTAMP`.
   - وفي السطر 1327: إجراء `rpc_submit_payment` يمرر `p_payment_date` في عمود `created_at`.
8. **انعدام تام للاختبارات الآلية**:
   - البحث عبر المستودع أظهر 0 اختبارات للتحقق من سلامة سجلات التدقيق في كامل المستودع.

---

## 2. Logic Chain (سلسلة الاستدلال المنطقي)

1. **من الملاحظة (2) والملاحظة (3)**: خادم Go في نموذج `AuditLog` لا يحتوي على تعريف لعمود `ip_address`، ودالة `logAudit` لا تقرأ `c.IP()` ولا تسند أي قيمة للحقل.
   - **الاستنتاج**: يستحيل على خادم Go تخزين عنوان IP للعميل، مما يفسر النتيجة المادية في الملاحظة (4) بأن جميع السجلات الحية (158 من 158) تمتلك `ip_address = NULL`.
2. **من الملاحظة (1) والملاحظة (3)**: جدول التدقيق لا يملك حقول `old_values` أو `new_values` كـ JSONB، والمعالج `UpdateGridCell` يكتفي بتمرير نص ثابت `"تعديل فوري في الجدول للمشترك رقم [%d]"` دون دمج مصفوفة الحقول المعدلة.
   - **الاستنتاج**: سجل التدقيق الحالي عاجز عن الإجابة على السؤال الجنائي: "ما هي القيمة السابقة واللاحقة للخلية المعدلة؟".
3. **من الملاحظة (3)**: استخدام `_ = h.db.Create(...).Error` يعني إسقاط أي خطأ ناتج عن قاعدة البيانات عمداً بصمت.
   - **الاستنتاج**: عند تعرض النظام لضغط متزامن مكثف وتجاوز سقف الـ 50 اتصالاً المحددة في `db.go`، ستسقط سجلات التدقيق دون علم النظام أو المستخدم، مع استمرار نجاح العمليات الأصلية ظاهرياً للمستخدم.
4. **من الملاحظة (5)**: معالجات `ApprovePayment` و `RejectPayment` و `UpdateReading` و `ImportExcel` لا تحتوي على استدعاءات `logAudit`.
   - **الاستنتاج**: العمليات الأكثر حساسية مالياً (اعتماد التحصيلات، ورفض السندات، وتعديل القراءات، واستيراد آلاف القراءات من ملفات خارجية) تجري خارج مظلة الرقابة والتدقيق تماماً.
5. **من الملاحظة (6)**: مسار تحديث الفاتورة يمرر معرف الفاتورة إلى `UpdateGridCell` التي تضعه في خانة الكيان `CUSTOMER`.
   - **الاستنتاج**: البيانات التاريخية للتدقيق تحتوي على تداخل خاطئ بين معرفات الفواتير والمشتركين، مما يضلل أي مراجعة رقابية لاحقة.
6. **من الملاحظة (7)**: تمرير تواريخ الإدخال (`p_reading_date` / `p_payment_date`) مباشرة إلى حقل `created_at` في إجراءات SQL يتيح إدراج قيود تدقيق بتاريخ ماضٍ أو مستقبل.
   - **الاستنتاج**: تسلسل السجلات الجنائي غير موثوق ولا يمكن الاعتماد عليه كدليل قاطع على وقت حدوث التعديل الفعلي.

---

## 3. Caveats (المحددات والافتراضات)

1. **الوضع الأحادي والتطبيق الأوفلاين**: النظام يعمل حالياً في بيئة سطح مكتب مدمجة (Standalone Desktop ERP) عبر خادم Go محلي على `localhost:3000`، مما يفسر سبب عدم التركيز الأولي على تسجيل الـ IP. ومع ذلك، وبما أن النظام يخدم واجهات شبكية ومزامنة عبر الشبكة المحلية (LAN) وواتساب، فإن توثيق IP والمستخدم أمر حيوي.
2. **الإجراءات المخزنة مقابل كود Go**: تم فحص نسختي الـ Overloads في SQL (التي تقبل `integer` والتي تقبل `bigint`)، وكلتاهما تحتويان على نفس منطق تسجيل التدقيق ونفس ثغرة تمرير التواريخ.
3. **لا توجد كتل كود تم تعديلها**: هذه المهمة اقتصرت على التحقيق والمسح الجنائي الصارم دون إدخال أي تعديلات على ملفات المشروع البرمجية.

---

## 4. Conclusion (الاستنتاج النهائي والتقييم)

منظومة التدقيق والرقابة (Audit Logs & Operation Forensics) في SmartPower Utility ERP تمتلك بنية تحتية أساسية وشاشة عرض ممتازة في واجهة المستخدم، **إلا أنها تعاني من 5 ثغرات هيكلية خطيرة تجعلها غير صالحة للاعتماد الجنائي والمالي الكامل في وضعها الراهن**:
1. **انعدام توثيق عناوين الـ IP بنسبة 100%**.
2. **انعدام تسجيل الفروقات والقيم السابقة واللاحقة (No Before/After Values)** في التعديلات الفورية.
3. **تجاوز رقابي للعمليات المالية الحرجة** (اعتماد ورفض السندات المالية، تعديل القراءات، استيراد الإكسل).
4. **فقدان صمود التدقيق تحت التزامن العالي** بسبب الابتلاع الصامت للأخطاء (`_ = h.db.Create(...).Error`).
5. **خلل تشويه الكيانات (Entity Misattribution)** عند تعديل خلايا الفواتير، وثغرة التلاعب بتاريخ التدقيق في إجراءات SQL.

---

## 5. Verification Method (طرق التحقق المستقلة)

يمكن لأي مهندس أو وكيل فحص وتأكيد كافة النتائج المذكورة عبر تنفيذ الأوامر التالية:

1. **التحقق من غياب IP ونسبة الـ NULL للمستخدمين في قاعدة البيانات الحية**:
   ```powershell
   & "d:\elctercity\dist_portable\pgsql\bin\psql.exe" -U postgres -d smartpower_db -p 5432 -c "SELECT COUNT(*) as total, COUNT(user_id) as with_user, COUNT(*) - COUNT(user_id) as null_user, COUNT(ip_address) as with_ip FROM audit_logs;"
   ```
   *النتيجة المتوقعة*: `with_ip = 0`، و `null_user = 38`.

2. **التحقق من نصوص التعديل المباشر المبهمة في السجلات الحية**:
   ```powershell
   & "d:\elctercity\dist_portable\pgsql\bin\psql.exe" -U postgres -d smartpower_db -p 5432 -c "SELECT id, user_id, action, entity, entity_id, details FROM audit_logs WHERE action = 'GRID_CELL_UPDATE' LIMIT 5;"
   ```
   *النتيجة المتوقعة*: نصوص عامة `"تعديل فوري في الجدول للمشترك رقم [...]"` دون تفاصيل الحقول والقيم.

3. **التحقق من غياب `ip_address` في استجابة الخادم الحية**:
   ```powershell
   Invoke-RestMethod -Uri "http://localhost:3000/api/audit-logs?page=1&limit=1" -Method Get | ConvertTo-Json -Depth 5
   ```
   *النتيجة المتوقعة*: كائن الـ JSON المسترجع لا يحتوي على مفتاح `ip_address` أو `old_values` أو `new_values`.

4. **التحقق من خلو معالجات السداد والقراءات من `logAudit`**:
   فحص الملف `server/internal/handlers/handlers.go` في الدوال `ApprovePayment` (السطر 670)، `RejectPayment` (السطر 681)، `UpdateReading` (السطر 639)، و `ImportExcel` (السطر 448).

</div>
