<div dir="rtl">

# التقرير الرقابي والنقدي الشامل لسلامة قواعد البيانات والمعاملات المالية
# Database & Transaction Integrity Comprehensive Review & Adversarial Challenge Report

**تاريخ التقرير**: 2026-09-09  
**النظام المستهدف**: SmartPower Utility ERP  
**قاعدة البيانات**: PostgreSQL 18.6 (`smartpower_db` على المنفذ 5432)  
**الخادم الخلفي**: Go Backend (`server/internal/services` على المنفذ 3000)  
**المراجع والناقد العدائي**: Database & Transaction Integrity Reviewer & Critic  

---

## 1. ملخص المراجعة والقرار النهائي (Review Summary & Verdict)

**الحكم الفني الصارم (Verdict)**: **`REQUEST_CHANGES` (طلب تعديلات إلزامية)** [مؤكد].

الخطر الأكبر في النظام حالياً ليس في المحرك الحسابي المالي (الذي أثبت دقة متناهية بنسبة 100% وبفارق 0.00 ريال)، بل في **ثغرة سباق زمني حرجة (P0 TOCTOU Race Condition) في تسجيل المشتركين** ناتجة عن انحراف فهرس قاعدة البيانات الحية عن المخطط المعتمد، بالإضافة إلى **خلل معمارية السداد الشلالي (P1 FIFO Allocation Bug) للفواتير ذات الأرصدة السالبة** التي تترك بحالة غير مسددة وتتسبب في انهيار عمليات التحصيل اللاحقة.

---

## 2. مصفوفة الملاحظات والعيوب المكتشفة (Findings & Vulnerabilities)

### [حرج - CRITICAL] العيب الأول: ثغرة السباق الزمني (TOCTOU) في تسجيل المشتركين ذوي الأصفار البادئة
- **الموقع**: `server/internal/services/customer_service.go:154-185` وفهرس `uq_customers_subscriber_number_clean` في جدول `customers`.
- **الداعي والأثر (Why & Blast Radius)**:
  - دالة `CreateCustomer` تفحص وجود المشترك عبر استعلام `SELECT` برمجي منفصل (`s.db.Where("REGEXP_REPLACE(...) = ?").First(&existing)`) خارج أي قفل جدولي أو معاملة متسلسلة.
  - الفهرس الفعلي في قاعدة البيانات الحية المشغلة هو:
    ```sql
    CREATE UNIQUE INDEX uq_customers_subscriber_number_clean 
    ON public.customers USING btree (TRIM(BOTH FROM lower((subscriber_number)::text))) 
    WHERE (is_deleted = false);
    ```
    وهو يفتقر لدالة `REGEXP_REPLACE(..., '^0+', '')` المعتمدة في المخطط النظري `init_schema.sql:6034` و `02_tables_and_constraints.sql:167`.
  - تحت الضغط المتزامن لـ 25 خيط عمل في نفس الميلي ثانية بأشكال أصفار بادئة مختلفة (`7753477`, `07753477`, `007753477`...)، رأت جميع الخيوط أن الرقم غير موجود في لحظة الفحص، وعند تنفيذ الـ `INSERT` اعتبر محرك PostgreSQL أن السلاسل النصية متباينة، مما سمح بدخول **5 سجلات متكررة لنفس المشترك في نفس اللحظة**.
- **المعالجة الإلزامية (Remediation)**:
  1. تنفيذ أمر استبدال الفهرس على محرك PostgreSQL فوراً:
     ```sql
     DROP INDEX IF EXISTS uq_customers_subscriber_number_clean;
     CREATE UNIQUE INDEX uq_customers_subscriber_number_clean 
     ON public.customers USING btree (REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')) 
     WHERE (is_deleted = false);
     ```
  2. تضمين عملية الإنشاء داخل معاملة بقفل متشائم أو الاعتماد الكامل على قيد الفهرس الفريد لقاعدة البيانات لمنع أي تسريب.

---

### [رئيسي - MAJOR] العيب الثاني: تعطل خوارزمية السداد الشلالي (FIFO Allocation) عند وجود فواتير سالبة
- **الموقع**: `server/internal/services/payment_service.go:230-236` و `customer_service.go:744-750` و `payment_service.go:248-287`.
- **الداعي والأثر (Why & Blast Radius)**:
  - عند حدوث سداد فائض وترحيل الرصيد الدائن كمتأخرات سالبة إلى الدورات اللاحقة، تصبح قيمة `RemainingAmount` في فواتير الدورات اللاحقة سالبة (مثل $-33,000.00$ ر.ي للمشترك 788 و $-27,945.00$ ر.ي للمشترك 784).
  - الكود البرمجي يحدد الحالة بالشرط التالي:
    ```go
    if downInv.RemainingAmount <= 0 && downInv.PaidAmount > 0 {
        downInv.Status = "Paid"
    } else if downInv.PaidAmount > 0 {
        downInv.Status = "Partially_Paid"
    } else {
        downInv.Status = "Unpaid"
    }
    ```
    بما أن `PaidAmount == 0` في هذه الفاتورة اللاحقة، فإنها تسقط في خيار `else` وتصبح حالتها `Unpaid` بالرغم من أن رصيدها سالب!
  - عند محاولة تسجيل سند قبض جديد للمشترك بنظام FIFO، يقوم الاستعلام في `payment_service.go:249` بجلب هذه الفاتورة:
    ```go
    Where("customer_id = ? AND status IN ('Unpaid', 'Partially_Paid')", customer.ID)
    ```
    ويقوم بحساب مبلغ التوزيع:
    `allocAmount = invoices[i].RemainingAmount` (قيمة سالبة!)
    ثم يطرحها من المبلغ المدفوع ويعدل `PaidAmount` بقيمة سالبة، مما يؤدي إلى كسر القيد الهيكلي في PostgreSQL:
    `CONSTRAINT chk_invoices_financials CHECK (paid_amount >= 0)`
    وفشل المعاملة بالكامل وتوقف إمكانية تحصيل أي مبالغ من المشترك.
- **المعالجة الإلزامية (Remediation)**:
  1. تعديل منطق تحديد الحالة: إذا كان `RemainingAmount <= 0` تصبح الحالة `Paid` حتى لو كان `PaidAmount == 0`.
  2. تعديل استعلام جلب فواتير الـ FIFO في `payment_service.go:249` ليصبح:
     ```go
     Where("customer_id = ? AND status IN ('Unpaid', 'Partially_Paid') AND remaining_amount > 0", customer.ID)
     ```

---

### [ثانوي - MINOR] العيب الثالث: غياب عنوان الـ IP في جميع سجلات الرقابة والتدقيق (Forensic Nullity)
- **الموقع**: `server/internal/models/audit_log.go` وخدمات تسجيل التدقيق.
- **الداعي والأثر**: فحص 331 سجلاً في جدول `audit_logs` أظهر أن 100% من السجلات تحتوي على `ip_address = NULL`. هذا يُسقط ركناً أساسياً من ركائز التحقيق الجنائي وتتبع العمليات المالية للمحصلين والمدراء.
- **المعالجة المقترحة**: ربط حقل `ip_address` بنموذج GORM والتقاط `c.IP()` من إطار عمل Go Fiber وتمريره لدالة تسجيل التدقيق.

---

### [ثانوي - MINOR] العيب الرابع: افتراض هش في اختبار تنظيف قاعدة البيانات (`db_verify_test.go`)
- **الموقع**: `server/internal/services/db_verify_test.go:25-32`.
- **الداعي والأثر**: يفترض الاختبار أن أي مشترك يحمل معرّفاً `id >= 500` يعتبر مشتركاً تجريبياً وهمياً ويجب حذفه. هذا الافتراض ينكسر طبيعياً مع النمو الشرعي للمشتركين (حيث وصل النظام حالياً إلى 511 مشتركاً فعلياً حتى المعرّف 832)، مما يتسبب في فشل فحص الـ CI/CD (`go test`).
- **المعالجة المقترحة**: تحديث معيار الفحص في الاختبار للبحث عن الأسماء التجريبية أو حقول الاختبار بدلاً من الرقم التسلسلي التراكمي.

---

## 3. الادعاءات التي تم التحقق منها مخبرياً وتجريبياً (Verified Claims)

| الادعاء المفحوص | المنهجية وطريقة التحقق المستقل | النتيجة المباشرة | مستوى اليقين | التقييم |
| :--- | :--- | :--- | :---: | :---: |
| **المطابقة المالية 100% عبر 3,571 ثم 3,578 فاتورة** | استعلام SQL دقيق لكافة الفواتير وحساب الفارق: `ROUND(total_due - (paid_amount + remaining_amount), 2)` | الفارق = 0.00 ريال يمني؛ عدد الفواتير غير المتطابقة = 0 من أصل 3,578 | [مؤكد] | **PASS** |
| **تطابق مؤشرات لوحة التحكم مع جداول قاعدة البيانات** | استدعاء `GET /api/analytics/dashboard-summary` ومطابقتها مع مجاميع SQL الحية | `total_billed`: 121,104,055 ر.ي متطابق 100%<br>`total_collected`: 2,262,020 ر.ي متطابق 100% | [مؤكد] | **PASS** |
| **انعدام تصادم أرقام السندات تحت 30 خيطاً متزامناً** | إطلاق 30 عملية سداد متزامنة في نفس الميلي ثانية عبر `threading.Barrier(30)` | توليد 30 سنداً فريداً (`REC-2026-000046` إلى `REC-2026-000075`)، التكرار في DB = 0 | [مؤكد] | **PASS** |
| **فاعلية القفل المتشائم `FOR UPDATE` لعداد السندات** | فحص كود `payment_service.go:68` واستعلام قيد الفرادة في جدول `payments` | حماية متسلسلة صارمة تمنع التكرار وتفرض الانتظار المنظم | [مؤكد] | **PASS** |
| **انعدام الأقفال الميتة (Deadlocks) تحت الضغط المكثف** | استعلام `pg_stat_database` قبل وبعد 400 طلب قراءة و 30 سداد متزامن و 20 تعديل خلايا | `deadlocks delta = 0`، أقفال معلقة = 0 | [مؤكد] | **PASS** |
| **استقرار وإنتاجية القراءة تحت الضغط** | 40 خيطاً نفذت 400 طلب قراءة موزع على نقاط النهاية الحساسة | 400/400 نجحت بنسبة 100%، المعدل 280.0 طلب/ثانية، متوسط التأخير 100.2ms | [مؤكد] | **PASS** |
| **التحقق من خلو العمل من التدليس (Integrity Violation Check)** | مراجعة الكود المصدري وسجلات الاختبارات ونصوص الـ SQL في حزم الاختبار | لا توجد نتائج وهمية مسبقة الصنع أو واجهات خادعة؛ الحسابات والأدوات حقيقية ومباشرة | [مؤكد] | **PASS** |

---

## 4. التحليل العدائي للأقفال ومنع الأقفال الميتة (Deadlock Analysis)

تم إجراء تدقيق نظري وعدائي صارم على تسلسل إقفال الموارد عبر الخدمات البرمجية الثلاث:

1. **`PaymentService.CreatePayment`**:
   - القفل 1: يطلب قفل المشترك `customers` أولاً (`clause.Locking{Strength: "UPDATE"}`).
   - القفل 2: يطلب قفل عداد السندات `payment_receipt_counters` ثانياً.
   - القفل 3: يطلب قفل الفواتير المستحقة مرتبة تصاعدياً بحسب تاريخ الاستحقاق والمعرف (`Order("due_date ASC, id ASC")`).
2. **`ReadingService.CreateReading`**:
   - القفل 1: يطلب قفل المشترك `customers` أولاً.
   - لا يطلب قفل عداد السندات إطلاقاً.
3. **`CustomerService.UpdateGridCell`**:
   - القفل 1: يطلب قفل المشترك `customers` أولاً.
   - ينفذ تعديلات الفواتير التابعة لنفس المشترك تباعاً.

**الاستنتاج المعماري**:
نظراً لأن جميع الخدمات البرمجية تعتمد قاعدة صارمة وموحدة ببدء القفل دائماً من كيان المشترك (`Customer Lock First`)، فإن العمليات المتزامنة لنفس المشترك تصطف تسلسلياً فوراً عند الخطوة الأولى. وبما أنه لا توجد أي معاملة في النظام تطلب قفل عداد السندات أو الفواتير ثم تحاول قفل المشترك بعدها، فإن حدوث دورة انتظار حلقية (Circular Wait) مستحيل رياضياً في هذا الهيكل، وهو ما أثبتته بيانات محرك PostgreSQL عملياً (`deadlocks = 0`).

---

## 5. خطة التحقق المستقل وإعادة الفحص (Independent Verification Method)

للتحقق المستقل من كافة النتائج والأرقام الواردة في هذا التقرير:

1. **التحقق من التطابق المالي التام لجميع الفواتير**:
   ```powershell
   & "d:\elctercity\dist_portable\pgsql\bin\psql.exe" -h localhost -p 5432 -U postgres -d smartpower_db -c "SELECT count(*) AS total_invoices, COALESCE(SUM(total_due), 0) AS sum_billed, COALESCE(SUM(paid_amount), 0) AS sum_paid, COALESCE(SUM(remaining_amount), 0) AS sum_remaining, COALESCE(SUM(ROUND(total_due - (paid_amount + remaining_amount), 2)), 0) AS diff, COUNT(*) FILTER (WHERE ROUND(total_due - (paid_amount + remaining_amount), 2) != 0) AS mismatches FROM invoices;"
   ```
   *المعيار*: يجب أن يكون `diff = 0.00` و `mismatches = 0`.

2. **التحقق من انعدام تكرار السندات**:
   ```powershell
   & "d:\elctercity\dist_portable\pgsql\bin\psql.exe" -h localhost -p 5432 -U postgres -d smartpower_db -c "SELECT receipt_number, COUNT(*) FROM payments GROUP BY receipt_number HAVING COUNT(*) > 1;"
   ```
   *المعيار*: ظهور `(0 rows)`.

3. **التحقق من عيب فهرس المشترك في قاعدة البيانات الحية**:
   ```powershell
   & "d:\elctercity\dist_portable\pgsql\bin\psql.exe" -h localhost -p 5432 -U postgres -d smartpower_db -c "SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'customers' AND indexname = 'uq_customers_subscriber_number_clean';"
   ```
   *المعيار*: ملاحظة غياب `REGEXP_REPLACE` في التعريف الحالي مقارنة بـ `init_schema.sql`.

4. **تشغيل أداة التحدي التجريبي الشامل للضغط والتزامن**:
   ```powershell
   python d:\elctercity\test_concurrency_stress_challenge.py
   ```
   *المعيار*: اجتياز المتجهات 1 و 2 و 3A و 4 و 5 و 6 و 7 بنجاح، وظهور التشخيص الدقيق لثغرة المتجه 3B.

</div>
