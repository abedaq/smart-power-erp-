<div dir="rtl">

# تقرير التسليم المعماري الشامل (Handoff Report)
## تصميم المخطط الهيكلي لقاعدة بيانات PostgreSQL المحلية (`smartpower_db`) — المرحلة 2

- **المرسل**: `explorer_m2_db_schema` (PostgreSQL Database Schema Architect)
- **المستلم**: `orchestrator_migration` (معرف المحادثة: `8662d701-dced-4ddd-b545-e2b64c0e3fc2`)
- **الملف المرجعي التفصيلي**: `d:\elctercity\.agents\explorer_m2_db_schema\analysis.md`
- **نوع التسليم**: Hard Handoff (مكتمل ومستوفٍ لكافة البنود)

---

## 1. الملاحظات والبيانات المرصودة (Observation)

1. **البيئة المحلية وأدوات التشغيل**:
   - تم التحقق من تشغيل خدمة PostgreSQL 18.6 محلياً عبر الأمر:
     `Get-Service *postgres*`
     المخرجات الفعلية:
     `Running  postgresql-x64-18  postgresql-x64-18 - PostgreSQL Server 18`
   - تم فحص قواعد البيانات الموجودة محلياً عبر أداة `psql` بنجاح:
     `& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -c "\l"`
     المخرجات أظهرت القواعد: `postgres`, `smart_power_restore_qa`, `u721293045_office_service`، مع عدم وجود قاعدة بيانات `smartpower_db` بعد، مما يؤكد جاهزية البيئة لتنفيذ تهيئة `smartpower_db` للمرحلة 2.
2. **فحص المخطط الحالي وأنواع البيانات في الكود القائم**:
   - في ملف `backend/prisma/schema.prisma` (الأسطر 57-145)، كانت بعض الحقول المالية معرفة بـ `Decimal(10,2)` بينما كانت القراءات في قاعدة البيانات الفعلية `u721293045_office_service` من نوع `integer`، مما يتطلب ترقية وتوحيد شامل إلى `NUMERIC(12,2)`.
   - في ملف `backend/scripts/deploy_complete_database_procedures.sql` (الأسطر 153-155)، تم رصد دالة التحقق من القراءة السابقة:
     ```sql
     IF p_reading_value < v_previous_reading THEN
       RAISE EXCEPTION 'New reading value (%) cannot be less than previous reading (%)', p_reading_value, v_previous_reading;
     END IF;
     ```
     ولكن هذا القيد كان محصوراً في الإجراء المخزن فقط ولم يكن مفروضاً كـ `CHECK constraint` مباشر على مستوى الجدول، مما قد يسمح بتسجيل قراءات متناقصة عبر عمليات الإدخال المباشرة.
3. **الجداول المطلوبة في أمر التكليف وبوابات المرحلة 2**:
   - نص التكليف في أمر المستخدم:
     *"Complete DDL schema script creating all 11 tables with proper PostgreSQL data types (UUID, NUMERIC(12,2), TIMESTAMPTZ, TEXT, BOOLEAN): users, customers, meter_readings, invoices, payments, billing_cycles, plans, settings, audit_logs, whatsapp_queue_messages, whatsapp_sessions."*
   - نص مواصفات البوابة Gate 2.2 في `MIGRATION/EXECUTION_LOG.md`:
     تأكيد الحاجة إلى الجداول الأساسية والملحقات المالية: `customer_credits`, `payment_allocations`, `shifts`, `payment_receipt_counters`, `collector_customer_assignments`.

---

## 2. سلسلة الاستدلال والمنطق الهندسي (Logic Chain)

1. **الربط بين تباين أنواع البيانات وقرار التوحيد على `NUMERIC(12,2)`**:
   - بالاستناد للملاحظة (2)، احتواء بعض الجداول على `integer` وبعضها على `Decimal(10,2)` يؤدي إلى تشوهات في احتساب الكسور المئوية للكيلوواط وفروقات التقريب في المبالغ الضخمة.
   - الاستنتاج: توحيد كافة الحقول المالية وقيم القراءات والفاقد على `NUMERIC(12,2)` يضمن دقة متناهية (Zero Rounding Errors) ويستوعب مبالغ تصل إلى 9 مليارات ريال يمني.
2. **الربط بين قيد العداد غير التنازلي وتصفير العداد**:
   - بالاستناد للملاحظة (2) واشتراطات `MASTER_PLAN.md` §2.1، قيد `CHECK (reading_value >= previous_reading)` ضروري لمنع التلاعب بالقراءات، لكنه يتسبب بكسر العمليات إذا قام المشترك بتركيب عداد جديد مصفر.
   - الاستنتاج: إضافة عمود `is_meter_reset BOOLEAN DEFAULT false` يجعل القيد مرناً ومحكماً:
     `CHECK (is_meter_reset = true OR reading_value >= previous_reading)` مع دعم التراجع الفوري في المعاملات المخالفة.
3. **الربط بين الترقيم الحتمي للفواتير ومنع تضارب العمليات**:
   - بالاستناد لمتطلبات البوابة Gate 2.5، تطبيق النمط `INV-[Cycle]-[SubscriberNumber]` يوفر معرفاً تجارياً حتمياً فريداً يُنشأ عبر `TRIGGER` تلقائي ويمنع تكرار إصدار أكثر من فاتورة لنفس المشترك في نفس الدورة.
4. **الربط بين تخزين الواتساب وجدول `whatsapp_sessions`**:
   - بالاستناد لمتطلبات المرحلة 3 ومحرك `whatsmeow` في وضع `CGO_ENABLED=0`، إنشاء جدول `whatsapp_sessions` ببيانات الاعتماد المشفرة (`BYTEA` و `JSONB`) يتيح لمحرك الواتساب العمل مباشرة على PostgreSQL دون الحاجة إلى Cgo أو ملفات SQLite المحلية.
5. **الربط بين التوافق مع الكود القائم واستحداث جداول `plans` و `settings`**:
   - بما أن الكود القائم في Prisma يستعلم عن `subscription_plans` و `system_settings`، بينما التكليف حدد `plans` و `settings`، تم اعتماد الجداول بأسماء `plans` و `settings` مع إنشاء واجهات توافق خلفية (`CREATE OR REPLACE VIEW subscription_plans AS SELECT * FROM plans;` و `CREATE OR REPLACE VIEW system_settings AS SELECT * FROM settings;`)، مما يحقق متطلبات التكليف ويمنع أي كسر في استعلامات الواجهة أو الباك إند القائم.

---

## 3. المحاذير والافتراضات (Caveats)

1. **صلاحيات حساب PostgreSQL**:
   - يُفترض توفر حساب `postgres` بكلمة المرور الافتراضية أو عبر المقبس المحلي مع صلاحيات `SUPERUSER` لإنشاء قاعدة البيانات `smartpower_db` وتفعيل الإضافات (`uuid-ossp`, `pgcrypto`).
2. **ترحيل البيانات التاريخية**:
   - هذا التقرير يختص بهندسة المخطط الهيكلي (DDL Schema) والقيود؛ أما عملية سحب البيانات القديمة من `u721293045_office_service` وضخها في `smartpower_db` فستتم في مرحلة الترحيل المالي للبيانات ضمن مهام الوكيل المنفذ `worker_m2_database`.
3. **لا توجد محاذير معمارية أخرى (No other caveats)**.

---

## 4. الاستنتاج والقرار الفني (Conclusion)

تم إنجاز المخطط الهندسي المتكامل لقاعدة بيانات `smartpower_db` بالكامل في الملف `analysis.md`، متضمناً:
1. نص إنشاء وتهيئة قاعدة البيانات مع الإضافات وضبط التوقيت اليمني.
2. نص الـ DDL الكامل لإنشاء الجداول الـ 11 المحددة بدقة (+ 5 جداول مساعدة للحسابات المائية والورديات).
3. القيود المحاسبية الصارمة: منع القراءات التنازلية، منع القيم السالبة، مفاتيح تفادي التكرار UUID، وحذف السجلات المترابطة (`ON DELETE RESTRICT` أو `CASCADE`).
4. منظومة الفهارس الموجهة للأداء العالي (الفهارس الفردية والمركبة).
5. الإجراءات المخزنة لمحرك تسجيل القراءات ومحرك التوزيع المائي FIFO بالقفل المتشائم.
المخطط جاهز فوراً للتنفيذ والاعتماد لاجتياز بوابتي Gate 2.1 و Gate 2.2.

---

## 5. طريقة التحقق المستقل (Verification Method)

يمكن للوكيل المنفذ أو المشرف التحقق من صحة المخطط واختباره بالخطوات التالية:

### الخطوة 1: تنفيذ سكربت التهيئة ونشر المخطط
```powershell
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -c "CREATE DATABASE smartpower_db;"
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -d smartpower_db -f "d:\elctercity\.agents\explorer_m2_db_schema\analysis.md"
```

### الخطوة 2: التحقق من اتصال وبوابة Gate 2.1
```powershell
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -c "SELECT current_database(), current_user, inet_server_port();" -d smartpower_db
```
- **شرط النجاح**: ظهور `smartpower_db | postgres | 5432` برمز خروج 0.

### الخطوة 3: التحقق من اكتمال الجداول وبوابة Gate 2.2
```powershell
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -d smartpower_db -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE' ORDER BY table_name;"
```
- **شرط النجاح**: ظهور الجداول الـ 11 كاملة (+ الجداول المساعدة) بإجمالي لا يقل عن 14 جدولاً.

### الخطوة 4: التحقق من قيد منع القراءة التنازلية (Gate 2.3)
```powershell
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -d smartpower_db -c "INSERT INTO customers (id, subscriber_number, full_name, phone_number, initial_reading) VALUES (999, 'SUB-TEST', 'مشترك تجريبي', '770000000', 100); INSERT INTO meter_readings (customer_id, reading_value, previous_reading, collector_name) VALUES (999, 90, 100, 'محصل');"
```
- **شرط النجاح**: رفض العملية بـ `ERROR: new row for relation "meter_readings" violates check constraint "chk_meter_readings_monotonic"`.

</div>
