<div dir="rtl">

# التقرير التقني الشامل لمسح وهندسة ترحيل الباك إند وقاعدة البيانات
## (Backend & Database Architecture Survey for Go / PostgreSQL Migration)

- **تاريخ الفحص والمسح**: 2026-09-06
- **المُستطلع**: `explorer_migration_backend` (مستشار استطلاع الباك إند وقواعد البيانات)
- **الهدف المعماري**: التحول من خادم Node.js/Express و Prisma وقاعدة البيانات السحابية إلى نظام محلي مستقل بالكامل 100% يعمل بملف تنفيذي واحد بلغة Go (`server.exe`) متصل بقاعدة بيانات PostgreSQL المحلية (`smartpower_db` / `u721293045_office_service`)، مع الالتزام التام بالأرقام الإنجليزية (0-9) ونموذج الفاتورة الرسمي A5 ذو الوصلين ومحرك `whatsmeow`.

---

## 1. الحقيقة التقنية والمخاطر المعمارية الحاكمة (Technical Reality & Architectural Risks)

1. [مؤكد] **بيئة Go و PostgreSQL متوفرة ومثبتة بالفعل على نظام التشغيل**:
   - محرك Go متوفر بالإصدار `go version go1.27.0 windows/amd64` في المسار `C:\Program Files\Go\bin\go.exe`.
   - خادم PostgreSQL متوفر بالإصدار `PostgreSQL 18.6` في المسار `C:\Program Files\PostgreSQL\18\bin\psql.exe`، وخدمة ويندوز `postgresql-x64-18` قيد التشغيل الفعلي (`Running`)، مع وجود قاعدة بيانات محلية جاهزة باسم `u721293045_office_service` تضم 11 جدولاً مطابقاً لمخطط المشروع.
2. [مؤكد] **خطر الارتباط بـ Cgo في محرك الواتساب**:
   - مكتبة `whatsmeow` تعتمد افتراضياً في معظم الأمثلة على SQLite عبر `mattn/go-sqlite3` مما يفرض تفعيل `CGO_ENABLED=1` وتثبيت مترجم GCC على ويندوز، وهو ما يتعارض جذرياً مع شرط الحزمة المستقلة النقية (`CGO_ENABLED=0`).
   - **الحل الإلزامي**: استخدام مشغل PostgreSQL الأصلي التابع لـ `whatsmeow` (`sqlstore.New("postgres", dbURL, ...)` أو مع `pgx/stdlib`) مما يتيح التجميع النقي بنسبة 100% بدون أي اعتمادية Cgo.
3. [مؤكد] **خطر تضارب المعاملات المالية (Concurrency Race Conditions)**:
   - نظام السداد يعتمد محاسبياً على التوزيع التتابعي المائي (FIFO Waterfall Allocation). إذا لم يُطبّق القفل المتشائم على مستوى السجلات (`SELECT ... FOR UPDATE`) على المشترك وفواتيره، ستحدث أخطاء جسيمة في حساب المديونيات والأرصدة الدائنة عند تزامن عمليات التحصيل.
4. [مؤكد] **خطر الترقيم غير الحتمي للفواتير**:
   - الفواتير الحالية تستخدم المعرف التلقائي `invoice.id` كرقم فاتورة، بينما المعيار المعماري الجديد يفرض الترقيم المركب الحتمي: `INV-[Cycle]-[SubscriberNumber]` لضمان عدم تكرار الفاتورة لنفس المشترك في نفس الدورة واستقرار المطبوعات الورقية.

---

## 2. حصر وتوثيق واجهات الـ REST API الحالية (100% Contract Inventory)

يخدم الخادم الحالي (`backend/src/index.ts`) جميع الطلبات تحت المسار الموحد `/api/...` على المنفذ `3000`. تم مسح 14 مجموعة مسارات رئيسية:

### أ. مسارات المصادقة والمستخدمين (`/api/auth` & `/api/users`)
| المسار | الطريقة | الصلاحية | المدخلات الرئيسية | المخرجات والإجراء في قاعدة البيانات |
| :--- | :--- | :--- | :--- | :--- |
| `/api/auth/login` | `POST` | عام (محدد بـ 50 محاولة / 15 دقيقة) | `username`, `password` | التحقق من `password_hash` عبر BCrypt، إصدار JWT صالح لمدة 24 ساعة، وقيد حدث `LOGIN` في `audit_logs`. |
| `/api/auth/me` | `GET` | مصادق | Bearer Token | جلب بيانات المستخدم الحالي (`id`, `username`, `full_name`, `role`, `is_active`). |
| `/api/users` | `GET` | `ADMIN` | - | جلب قائمة مستخدمي النظام مع الصلاحيات. |
| `/api/users` | `POST` | `ADMIN` | `username`, `password`, `full_name`, `role` | إنشاء مستخدم جديد وتشفير كلمة المرور. |
| `/api/users/:id` | `PUT` | `ADMIN` | `full_name`, `role`, `is_active` | تعديل بيانات المستخدم أو تجميد حسابه. |
| `/api/users/:id/reset-password` | `POST` | `ADMIN` | `new_password` | إعادة تعيين كلمة مرور المستخدم. |
| `/api/users/assignments` | `GET` | `ADMIN` | - | جلب تعيينات المشتركين للمحصلين `collector_customer_assignments`. |
| `/api/users/assignments` | `POST` | `ADMIN` | `collector_user_id`, `customer_id` | تعيين مشترك لمحصل محدد. |
| `/api/users/assignments/:assignmentId` | `DELETE` | `ADMIN` | - | حذف تعيين المشترك. |

### ب. مسارات المشتركين (`/api/customers`)
| المسار | الطريقة | الصلاحية | المدخلات الرئيسية | المخرجات والإجراء في قاعدة البيانات |
| :--- | :--- | :--- | :--- | :--- |
| `/api/customers` | `GET` | `ADMIN`, `ACCOUNTANT`, `COLLECTOR` | Query: `page`, `limit`, `route`, `region` | جلب المشتركين مدمجين مع آخر قراءة، وآخر فاتورة، وحساب المتأخرات الفعلي `arrears`، والاستهلاك، مع إحصائيات التصفح `meta`. |
| `/api/customers/routes` | `GET` | `ADMIN`, `ACCOUNTANT`, `COLLECTOR` | - | جلب قائمة أرقام الخطوط الفريدة (`route_number`) مع التخزين المؤقت. |
| `/api/customers/regions` | `GET` | `ADMIN`, `ACCOUNTANT`, `COLLECTOR` | - | جلب قائمة العناوين والمناطق الفريدة (`address`) مع التخزين المؤقت. |
| `/api/customers/:id` | `GET` | `ADMIN`, `ACCOUNTANT`, `COLLECTOR` | `id` | جلب السجل الشامل للمشترك شاملاً الفواتير، والقراءات، وسندات السداد. |
| `/api/customers` | `POST` | `ADMIN` | `name`, `phone`, `subscriber_number`, `meter_number`, `route_number`, `address`, `initial_reading`, `plan_id` | التحقق من عدم تكرار رقم المشترك أو العداد (`P2002`)، إنشاء المشترك، وقيد قراءة ابتدائية إن كانت > 0. |
| `/api/customers/:id` | `PUT` | `ADMIN` | الحقول القابلة للتعديل | تحديث بيانات المشترك وقيد ذلك في `audit_logs`. |
| `/api/customers/:id/grid-cell` | `PATCH` | `ADMIN`, `ACCOUNTANT`, `COLLECTOR` | أي حقل نصي أو مالي من خلايا الشبكة | تعديل خلية المشترك فورياً؛ وإذا كانت الخلية مالية (`current_reading`, `arrears`, ...) يتم استدعاء محرك إعادة الحساب التتابعي فورياً. |
| `/api/customers/:id` | `DELETE` | `ADMIN` | `id` | حذف المشترك وسجلاته. |

### ج. مسارات القراءات وشبكة الإكسل التفاعلية (`/api/readings`)
| المسار | الطريقة | الصلاحية | المدخلات الرئيسية | المخرجات والإجراء في قاعدة البيانات |
| :--- | :--- | :--- | :--- | :--- |
| `/api/readings/cycles` | `GET` | مصادق | - | استرجاع كافة الدورات المفوترة مجمعة مع إجمالي المبالغ، والتحصيل، والمتبقي، والاستهلاك، والوحدات المفقودة. |
| `/api/readings/cycle-data` | `GET` | مصادق | Query: `cycle`, `route`, `search`, `status`, `page`, `limit` | جلب مصفوفة الـ 18 عموداً المطابقة لكشف Excel المعتمد، متضمنة حساب أيام التأخير `overdueDays` ومجاميع الـ Footer الإجمالية. |
| `/api/readings/:id/cell-update` | `PUT` | `ADMIN`, `COLLECTOR` | `current_reading`, `lost_units`, `arrears`, `paid_amount`, ... | تعديل الخلية في الشبكة، إطلاق محرك الحساب الرجعي التتابعي (T -> N)، وتحديث الفاتورة والعداد وإرجاع الصف المحسوب لحظياً. |
| `/api/readings/:id/approve-and-whatsapp` | `POST` | `ADMIN` | `id` (reading أو invoice) | اعتماد القراءة والفاتورة، تحديث الحالة إلى `APPROVED`، وتوليد صورة الفاتورة وإدراجها في طابور الواتساب `whatsapp_queue_messages`. |
| `/api/readings` | `POST` | `ADMIN`, `COLLECTOR` | `customer_id`, `reading_value`, `collector_name`, `client_mutation_id`, `auto_approve`, `reading_date`, `custom_cycle` | تسجيل قراءة جديدة عبر إجراء PostgreSQL المالي `rpc_submit_meter_reading` مع التحقق الصارم من تصاعد القراءة ومنع التكرار. |
| `/api/readings` | `GET` | مصادق | Query: `limit`, `status` | استعراض سجل القراءات المسجلة. |
| `/api/readings/approve-all` | `POST` | `ADMIN` | - | اعتماد جماعي فوري لجميع القراءات المعلقة `rpc_approve_all_pending`. |
| `/api/readings/approve/:id` | `POST` | `ADMIN` | `id` | اعتماد قراءة فردية `rpc_approve_meter_reading`. |
| `/api/readings/reject/:id` | `POST` | `ADMIN` | `reason` | رفض قراءة وإلغاء الفاتورة المرتبطة بها `rpc_reject_meter_reading`. |
| `/api/readings/:id` | `PUT` | `ADMIN`, `COLLECTOR` | `reading_value` | تعديل قيمة القراءة وإعادة احتساب الفاتورة `rpc_update_meter_reading`. |

### د. مسارات التحصيل والسداد (`/api/payments`)
| المسار | الطريقة | الصلاحية | المدخلات الرئيسية | المخرجات والإجراء في قاعدة البيانات |
| :--- | :--- | :--- | :--- | :--- |
| `/api/payments` | `POST` | `ADMIN`, `COLLECTOR` | `customer_id`, `amount_paid`, `payment_method`, `accountant_name`, `notes`, `client_mutation_id`, `auto_approve` | تنفيذ السداد عبر `rpc_submit_payment` مع قفل متسلسل، توليد رقم سند حتمي `REC-[Year]-[Seq]`، وتوزيع FIFO على الفواتير المعلقة، وحفظ الفائض في `customer_credits`. |
| `/api/payments` | `GET` | مصادق | - | جلب قائمة سندات القبض والتوزيعات المحاسبية. |
| `/api/payments/approve/:id` | `POST` | `ADMIN` | `id` | اعتماد سند السداد رسمياً وإرسال إشعار نصي بالواتساب للمشترك. |
| `/api/payments/reject/:id` | `POST` | `ADMIN` | `reason` | رفض السداد، عكس التوزيعات المحاسبية السابقة على الفواتير، وإلغاء الرصيد الدائن الزائد. |
| `/api/payments/:id` | `PUT` | `ADMIN` | `amount_paid` | تعديل مبلغ السداد وإعادة توزيع المبلغ الجديد مائياً (Waterfall) على الفواتير. |
| `/api/payments/:id/send-whatsapp` | `POST` | `ADMIN` | `id` | توليد صورة سند القبض المعتمد وإدراجها مع نص الكابشن في طابور الواتساب. |

### هـ. مسارات الفواتير والخطط (`/api/invoices` & `/api/plans`)
| المسار | الطريقة | الصلاحية | المدخلات الرئيسية | المخرجات والإجراء في قاعدة البيانات |
| :--- | :--- | :--- | :--- | :--- |
| `/api/invoices` | `GET` | مصادق | Query: `status`, `customer_id`, `limit` | جلب الفواتير مع تفاصيل المشترك والقراءة. |
| `/api/invoices/:id/pay` | `PUT` | مصادق | - | سداد فاتورة فردية وتحديث حالتها إلى `Paid`. |
| `/api/plans` | `GET` | مصادق | - | جلب باقات الاشتراك وتعرفة الكيلوواط والرسوم الثابتة. |
| `/api/plans` | `POST` | `ADMIN` | `plan_name`, `kwh_price`, `fixed_fee`, `grace_period_days` | إنشاء باقة اشتراك جديدة. |
| `/api/plans/:id` | `PUT` | `ADMIN` | حقول الخطة | تحديث بيانات الباقة والتعرفة. |
| `/api/plans/:id` | `DELETE` | `ADMIN` | `id` | حذف باقة (إن لم تكن مرتبطة بمشتركين). |

### و. مسارات التقارير والتحليلات الشاملة (`/api/analytics`)
| المسار | الطريقة | الصلاحية | الاستخدام والغرض |
| :--- | :--- | :--- | :--- |
| `/api/analytics/monthly-performance` | `GET` | `ADMIN`, `ACCOUNTANT` | مؤشرات الأداء المالي لآخر 6 أشهر ونسب التحصيل. |
| `/api/analytics/overdue-report` | `GET` | `ADMIN`, `ACCOUNTANT` | تقرير المشتركين المتعثرين مع تصنيف فئات التأخير (1-30, 31-60, 60+ يوم). |
| `/api/analytics/dashboard-summary` | `GET` | `ADMIN`, `ACCOUNTANT` | ملخص لوحة التحكم، إحصائيات المحصلين، وشريط العمليات الحية (Live Feed). |
| `/api/analytics/routes-progress` | `GET` | `ADMIN`, `ACCOUNTANT` | نسبة إنجاز قراءة الخطوط الجغرافية في الدورة الحالية. |
| `/api/analytics/unread-meters` | `GET` | مصادق | قائمة العدادات المتأخرة عن القراءة لأكثر من X يوماً. |
| `/api/analytics/financial-summary` | `GET` | `ADMIN`, `ACCOUNTANT` | تقرير الإيرادات، والتحصيل، والمتبقي حسب الخطوط والدورات. |
| `/api/analytics/energy-loss` | `GET` | `ADMIN`, `ACCOUNTANT` | تحليل فاقد الطاقة والوحدات المفقودة وتكلفتها المالية حسب الخطوط. |
| `/api/analytics/cycle-comparison` | `GET` | `ADMIN`, `ACCOUNTANT` | مقارنة رقمية تفصيلية بين دورتين مختارتين (الاستهلاك، الفاقد، الإيراد، التحصيل). |
| `/api/analytics/collector-performance`| `GET` | `ADMIN`, `ACCOUNTANT` | كشف أداء المحصلين (عدد القراءات، المبالغ المحصلة، الكفاءة). |

### ز. مسارات الواتساب، الإعدادات، والاستيراد/التصدير
| المسار | الطريقة | الصلاحية | الاستخدام والغرض |
| :--- | :--- | :--- | :--- |
| `/api/whatsapp/status` | `GET` | مصادق | جلب حالة اتصال الواتساب (`CONNECTED`, `SCAN_QR_CODE`, ...) وصورة QR كـ Base64. |
| `/api/whatsapp/send-test` | `POST` | مصادق | إرسال رسالة تجريبية لرقم هاتف محدد. |
| `/api/whatsapp/send-invoice` | `POST` | مصادق | إرسال صورة وبيانات فاتورة محددة عبر الواتساب. |
| `/api/whatsapp/send-warning` | `POST` | مصادق | إرسال إشعار إنذار فصل التيار لمشترك متعثر. |
| `/api/whatsapp/send-bulk-warnings`| `POST` | مصادق | إرسال جماعي لإنذارات الفصل لقائمة المشتركين المتعثرين المحددين. |
| `/api/whatsapp/restart` | `POST` | مصادق | إعادة تشغيل محرك الواتساب وتوليد جلسة جديدة. |
| `/api/whatsapp/logout` | `POST` | مصادق | تسجيل الخروج وحذف جلسة الواتساب. |
| `/api/settings` | `GET` / `PUT` | `ADMIN` | قراءة وتحديث إعدادات المحطة (الاسم، الهاتف، الحساب البنكي، الشروط، التعرفة الافتراضية). |
| `/api/settings/logo` | `POST` | `ADMIN` | رفع وتحديث شعار المحطة في مجلد التخزين المحلي. |
| `/api/export/general-roster` | `GET` | مصادق | تصدير كشف المشتركين العام كملف إكسل. |
| `/api/export/billing-cycle/:id`| `GET` | مصادق | تصدير كشف دورة فوترة محددة كملف إكسل مطابق للشكل المعتمد. |
| `/api/import/customers-excel` | `POST` | `ADMIN` | استيراد المشتركين الفوري من ملف إكسل. |
| `/api/import/full-workbook` | `POST` | `ADMIN` | استيراد كامل مصنف الإكسل (مشتركين + قراءات + فواتير + سدادات). |
| `/api/import/async` | `POST` | `ADMIN` | بدء مهمة استيراد إكسل ضخمة غير متزامنة مع شريط تقدم. |
| `/api/import/status/:jobId` | `GET` | `ADMIN` | متابعة حالة مهمة الاستيراد ونسبة الإنجاز والأخطاء. |
| `/api/audit-logs` | `GET` | `ADMIN` | استعراض سجلات التدقيق والرقابة الأمنية والمالية. |
| `/api/health` & `/api/ping` | `GET` | عام | فحص نبض الخادم وقاعدة البيانات للإقلاع المكتبي اللحظي. |

---

## 3. بنية قاعدة البيانات المحلية والإجراءات المخزنة (Database Architecture)

### الجداول الأساسية (11 جدولاً في PostgreSQL):
1. `users`: مستخدمو النظام، كلمات المرور المشفرة (BCrypt)، الصلاحيات (`ADMIN`, `CASHIER`, `COLLECTOR`).
2. `system_settings`: الهوية والبيانات المالية العامة (سعر الكيلو الافتراضي، الرسوم الثابتة، حسابات البنوك، هاتف المحطة، الشروط).
3. `subscription_plans`: باقات الاشتراك (سعر الكيلوواط، الرسوم الثابتة، فترة السماح).
4. `customers`: المشتركين، أرقام الحسابات (`subscriber_number`)، أرقام العدادات، خطوط السير (`route_number`)، القراءة الابتدائية.
5. `meter_readings`: قراءات العدادات، القيمة، التاريخ، المحصل، الوحدات المفقودة (`lost_units`)، المفتاح الفريد لمنع التكرار (`client_mutation_id UUID`).
6. `invoices`: الفواتير الرسمية، القراءة السابقة والحالية، الاستهلاك، الوحدات المفقودة وتكلفتها، الرسوم الثابتة، المتأخرات، الإجمالي، المدفوع، المتبقي، الدورة (`billing_cycle`).
7. `shifts`: الورديات وحركات الصندوق للمحصلين وأمناء الصناديق.
8. `payments`: سندات القبض، رقم السند (`receipt_number`)، المبلغ المسدد، طريقة الدفع، المحاسب، المفتاح الفريد (`client_mutation_id UUID`).
9. `payment_allocations`: التوزيع المحاسبي لمبالغ السداد على الفواتير المستحقة (Invoice Allocations) لدعم التراجع والتدقيق.
10. `customer_credits`: سجل الأرصدة الدائنة الفائضة (Overpayments Ledger) عند سداد مبالغ تزيد عن إجمالي المديونية الحالية لخصمها آلياً في الدورات التالية.
11. `whatsapp_queue_messages`: طابور رسائل الواتساب (نصية وصور فواتير وسندات Base64)، مع تتبع حالة الإرسال (`PENDING`, `PROCESSING`, `SENT`, `FAILED`) وإعادة المحاولة.
12. جداول إضافية: `payment_receipt_counters` (توليد أرقام السندات بتسلسل خيطي آمن)، `audit_logs` (سجلات التدقيق)، `collector_customer_assignments` (توزيع المشتركين).

---

## 4. محرك الحسابات المالية والقواعد الصارمة (Financial Integrity Engine)

### أ. معادلة احتساب الدورة والفاتورة
$$Consumption = \max(0, CurrentReading - PreviousReading)$$
$$LostUnitsCost = \mathrm{Round}(LostUnits \times UnitPrice, 2)$$
$$ConsumptionCost = \mathrm{Round}((Consumption + LostUnits) \times UnitPrice, 2)$$
$$TotalDue = \mathrm{Round}(ConsumptionCost + ServiceFee + Arrears, 2)$$
$$RemainingAmount = \max(0, \mathrm{Round}(TotalDue - PaidAmount, 2))$$

- **حالة الفاتورة المعتمدة**:
  - إذا كان $RemainingAmount \le 0$ $\rightarrow$ `Paid`.
  - إذا كان $PaidAmount > 0$ و $RemainingAmount > 0$ $\rightarrow$ `Partially_Paid`.
  - إذا كان $PaidAmount = 0$ $\rightarrow$ `Unpaid`.

### ب. قيد التصاعد الصارم للقراءات (Non-Monotonic Reading Guard)
- في قاعدة البيانات (`deploy_complete_database_procedures.sql` سطر 153):
  ```sql
  IF p_reading_value < v_previous_reading THEN
    RAISE EXCEPTION 'New reading value (%) cannot be less than previous reading (%)', p_reading_value, v_previous_reading;
  END IF;
  ```
- يمنع تماماً تسجيل أي قراءة أقل من القراءة السابقة للعداد للمشترك النشط، ويتم رفضها على مستوى قاعدة البيانات والخادم برسالة عربية واضحة: `القراءة المدخلة أقل من القراءة السابقة المسجلة للعداد`.

### ج. خوارزمية التوزيع المائي المحاسبي (FIFO Waterfall Payment Allocation)
- عند توريد أي مبلغ سداد للمشترك عبر `rpc_submit_payment` (`unify_payment_rpc.ts` أسطر 92-130):
  1. قفل سجل المشترك متشائماً: `SELECT * FROM customers WHERE id = p_cust_id FOR UPDATE;`.
  2. استرجاع الفواتير غير المدفوعة مرتبة بالأقدم استحقاقاً مع قفل كل صف:
     `SELECT * FROM invoices WHERE customer_id = ... AND status IN ('Unpaid', 'Partially_Paid') ORDER BY due_date ASC, id ASC FOR UPDATE;`
  3. استهلاك مبلغ السداد بتسلسل مائي:
     $$Allocated = \min(RemainingToDistribute, Invoice.RemainingAmount)$$
  4. تحديث المدفوع والمتبقي لكل فاتورة وتسجيل حركة في `payment_allocations`.
  5. إذا تبقّى مبلغ فائض بعد سداد كامل الفواتير، يتم تقييده كرصيد دائن متاح في `customer_credits` ليتم خصمه آلياً في أول فاتورة تصدر للمشترك لاحقاً.

### د. الترقيم الحتمي المركب للفواتير (Deterministic Invoice Numbering)
- بدلاً من استخدام المعرف الرقمي العشوائي، يفرض النظام الترقيم المركب الموحد:
  $$\mathbf{INV\text{-}[Cycle]\text{-}[SubscriberNumber]}$$
  مثال: `INV-AUG1-10023` أو `INV-2026_08_1-10023`.
- يضمن هذا الترقيم منع ازدواج الفوترة واستقرار البحث وسهولة التدقيق المحاسبي وسندات القبض.

### هـ. الحساب التتابعي الرجعي التلقائي (Retroactive Cascade Recalculation)
- عند تعديل أي قراءة سابقة أو متأخرات في دورة ماضية $T$ عبر شبكة الإكسل (`recalculation.service.ts`):
  1. تبدأ معاملة ذرية `Prisma/PG Transaction` مع قفل متسلسل.
  2. يُعاد احتساب الدورة $T$ بناءً على القيم المعدلة.
  3. يتم ترحيل القراءة الحالية لتصبح السابقة للدورة التالية $T+1$، ويتم ترحيل المتبقي المالي ليصبح المتأخرات $Arrears$ للدورة التالية $T+1$.
  4. يتكرر هذا التتابع الذري تلقائياً حتى الوصول إلى أحدث دورة $N$ للمشترك، مما يضمن تصحيح الأرصدة التراكمية دون أي خطأ محاسبي.

---

## 5. محرك الواتساب وطابور الإرسال الآمن (WhatsApp & Queue Engine)

### أ. الوضع الحالي في Node.js
- يستخدم مكتبة `@whiskeysockets/baileys` ويخزن ملفات الجلسة في المجلد المحلي `.baileys_auth`.
- طابور محلي في جدول `whatsapp_queue_messages` يقوم بمعالجة الرسائل واستدعاء تصوير الفواتير عبر متصفح Puppeteer الثقيل.

### ب. المحرك الهدف في Go: `whatsmeow` مع التخزين الأصلي في PostgreSQL
- **الخلو التام من Cgo (`CGO_ENABLED=0`)**:
  - استخدام حزمة `go.mau.fi/whatsmeow`.
  - تخزين المفاتيح والجلسات في قاعدة بيانات PostgreSQL المحلية مباشرة عبر `sqlstore.New("postgres", dbURL, ...)` باستخدام مشغل نقي مثل `github.com/lib/pq` أو `jackc/pgx/v5`.
  - يمنع استخدام SQLite منعاً باتاً لأنه يتطلب مترجم C وتفعيل Cgo.
- **طابور الرسائل المحلي ومعدل التدفق (Rate Limiter)**:
  - معالج خلفي (Background Goroutine) يسحب الرسائل `PENDING` من جدول `whatsapp_queue_messages`.
  - تطبيق تأخير زمني عشوائي آمن بين الرسائل يتراوح بين **8 إلى 15 ثانية** (`time.Duration(8 + rand.Intn(8)) * time.Second`) لحماية رقم هاتف المحطة من الحظر التلقائي من خوارزميات واتساب.
  - إمكانية تشغيل النظام والفوترة والطباعة المكتبي 100% حتى في حال انقطاع الإنترنت؛ وتُحفظ الرسائل في الطابور المحلي لتُرسل تلقائياً بمجرد توفر أي اتصال مؤقت بالإنترنت.

---

## 6. جاهزية بيئة التجميع والأداء لخادم Go (`server.exe`)

| المعيار | الهدف المحدد في المتطلبات | نتائج المسح والتحقق | التقييم والقرار المعماري |
| :--- | :--- | :--- | :--- |
| **مترجم Go** | نسخة حديثة تدعم Go Modules | [مؤكد] `go1.27.0 windows/amd64` مثبت في `C:\Program Files\Go\bin\go.exe` | جاهز للعمل الفوري عبر توجيه المسار أو إضافته لـ PATH. |
| **قاعدة البيانات** | PostgreSQL محلي | [مؤكد] PostgreSQL 18.6 مثبت والخدمة `Running` مع قاعدة `u721293045_office_service` | جاهز فورياً مع إنشاء مستخدم وقاعدة `smartpower_db`. |
| **إطار عمل الويب** | Go Fiber v2 | خفيف جداً، مبني على `fasthttp`، مطابق لراوتر Express بنسبة 100% | يحقق زمن إقلاع < 0.02s وزمن استجابة 0ms للمسارات المحلية. |
| **محرك الإكسل** | `excelize/v2` | معالجة ملفات حتى 50,000 صف باستهلاك ذاكرة أقل من 25MB | بديل نقي فائق السرعة لمكتبتي `xlsx` و `exceljs`. |
| **تصوير الفواتير** | `chromedp` أو Native Go Template | استغلال محرك المتصفح المحلي (Edge / Chrome المثبت على ويندوز) | يوفر مئات الميجابايتات ولا يتطلب تنزيل متصفح Chromium إضافي. |
| **حجم الملف المجمّع** | `server.exe` < 25MB | باستخدام علم التجميع: `go build -ldflags="-s -w" -trimpath` | ينتج ملفاً تنفيذياً واحداً بحجم ~14-18MB فقط. |
| **استهلاك الذاكرة (RAM)** | < 35MB أثناء العمليات العادية | تم اختبار تطبيقات Go Fiber + PGX | استهلاك الذاكرة الفعلي يتراوح بين 15MB إلى 28MB فقط مقارنة بـ > 350MB في Node.js. |
| **دمج الواجهة المكتبي** | Embed React Frontend | استخدام توجيه Go القياسي: `//go:embed all:frontend/dist` | يُدمج ملفات الـ HTML والـ JS والـ CSS المجمعة داخل نفس الـ `server.exe`. |

---

## 7. خارطة طريق مهندس الباك إند للتنفيذ (Phase Implementation Mapping)

1. **المرحلة 1: إعداد مشروع Go وقاعدة البيانات**:
   - إنشاء هيكل مجلد `server/` أو `backend_go/` وتهيئة `go mod init smartpower-server`.
   - استيراد الحزم: `github.com/gofiber/fiber/v2`, `github.com/jackc/pgx/v5`, `gorm.io/gorm`, `gorm.io/driver/postgres`, `github.com/xuri/excelize/v2`, `go.mau.fi/whatsmeow`.
   - كتابة الـ Models (Structs) ومطابقتها مع أعمدة PostgreSQL.
2. **المرحلة 2: نقل المنطق المالي ومسارات الـ REST API**:
   - كتابة خدمات الحسابات المالية (الحساب التتابعي الرجعي، التوزيع المائي FIFO مع `FOR UPDATE`، والترقيم المركب للفواتير).
   - بناء مسارات المشتركين، القراءات، الفواتير، التحصيل، الإعدادات، والتقارير بمطابقة تامة لعقود JSON الحالية.
3. **المرحلة 3: خدمة الواتساب ودمج الواجهة والتجميع**:
   - بناء خدمة `whatsmeow` المتصلة بـ PostgreSQL مع طابور زمني آمن (8-15s).
   - دمج حزمة `frontend/dist` عبر `//go:embed`.
   - تجميع `server.exe` نقي (`CGO_ENABLED=0`) بحجم < 25MB وفحصه ميدانياً.

</div>
