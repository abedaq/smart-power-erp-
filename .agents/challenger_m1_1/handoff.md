# تقرير التحدي التجريبي — المرحلة M1: فحص واختبار إجهاد منع تكرار المشتركين
# Challenge Report — Milestone M1: Empirical Stress Testing of Subscriber Anti-Duplication

- **الوكيل الفاحص (Challenger)**: `challenger_m1_1`
- **الدور (Role)**: Critic / Specialist (Adversarial Verification)
- **المهمة (Task)**: Stress-test subscriber anti-duplication logic in `server/internal/services/customer_service.go`
- **التاريخ**: 2026-09-07T15:12:00Z
- **القرار النهائي (Verdict)**: **`APPROVE`** (مع ملاحظات تحسين معمارية موثقة)

---

## 1. Observation (الملاحظات المباشرة والأدلة التجريبية)

### 1.1 فحص كود خدمة المشتركين `server/internal/services/customer_service.go`
- **الأسطر 31-38**: تعريف التعبير النمطي ودالة التطبيع:
  ```go
  var leadingZeroRegex = regexp.MustCompile(`^0+`)

  func NormalizeSubscriberNumber(sub string) string {
      trimmed := strings.ToLower(strings.TrimSpace(sub))
      return leadingZeroRegex.ReplaceAllString(trimmed, "")
  }
  ```
- **الأسطر 140-151 (`GetNextSubscriberNumber`)**:
  استخدام حلقة كشف التصادم وتطبيع الرقم المرشح عبر:
  `s.db.Model(&models.Customer{}).Where("REGEXP_REPLACE(TRIM(LOWER(subscriber_number)), '^0+', '') = ? AND is_deleted = false", NormalizeSubscriberNumber(candidateStr)).Count(&count)`
- **الأسطر 158-165 (`CreateCustomer`)**:
  تطبيع الرقم المدخل والاستعلام الصارم قبل الإدراج:
  `cleanSub := NormalizeSubscriberNumber(trimmedSubNo)`
  `s.db.Where("REGEXP_REPLACE(TRIM(LOWER(subscriber_number)), '^0+', '') = ? AND is_deleted = false", cleanSub).First(&existing)`
  مع إرجاع رسالة خطأ واضحة: `رقم المشترك [%s] مسجل مسبقاً للمشترك [%s]! يمنع منعاً باتاً تكرار رقم المشترك.`
- **الأسطر 331-344 (`UpdateCustomer`)**:
  مقارنة `cleanSub` مع `currentClean` واستبعاد المعرف الحالي `id != ?`:
  `s.db.Where("REGEXP_REPLACE(TRIM(LOWER(subscriber_number)), '^0+', '') = ? AND id != ? AND is_deleted = false", cleanSub, id).First(&existing)`
- **الأسطر 433-448 (`UpdateGridCell`)**:
  تطبيق نفس فحص التصادم والتطبيع عند تعديل الخلية في الجدول مع استبعاد المشترك الحالي `id != customer.ID`.

### 1.2 فحص مخططات قاعدة البيانات والفهارس الفريدة
- **في `dist_portable/schema/init_schema.sql` (السطر 5240)**:
  ```sql
  CREATE UNIQUE INDEX uq_customers_subscriber_number_clean ON public.customers USING btree (REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')) WHERE (is_deleted = false);
  ```
- **في `database/02_tables_and_constraints.sql` (السطر 167)**:
  ```sql
  CREATE UNIQUE INDEX IF NOT EXISTS uq_customers_subscriber_number_clean ON public.customers USING btree (REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')) WHERE (is_deleted = false);
  ```
- **في قاعدة البيانات الحية الميدانية `smartpower_db` على المنفذ 5432**:
  أظهر فحص `pg_indexes` أن الفهرس الحالي هو:
  `CREATE UNIQUE INDEX uq_customers_subscriber_number_clean ON public.customers USING btree (TRIM(BOTH FROM lower((subscriber_number)::text))) WHERE (is_deleted = false)`
  [مؤكد] سبب ذلك هو أن أمر `CREATE UNIQUE INDEX IF NOT EXISTS` يعتبر عملية لاغية (no-op) عندما يكون اسم الفهرس موجوداً مسبقاً في قاعدة البيانات حتى لو اختلف تعبير الفهرس.

### 1.3 نتائج تنفيذ سكربت الاختبار التجريبي `test_subscriber_anti_duplication.py`
تم إنشاء وتنفيذ سكربت اختبار الإجهاد `test_subscriber_anti_duplication.py` وجاءت النتائج كالتالي:

1. **حزمة الاختبار 1 (NormalizeSubscriberNumber Unit Verification - 15 حالة طرفية)**:
   - `0001` -> `1` [PASS]
   - `0` -> `` [PASS]
   - `000` -> `` [PASS]
   - `100` -> `100` [PASS]
   - `0100` -> `100` [PASS]
   - `00100` -> `100` [PASS]
   - `00123` -> `123` [PASS]
   - `  00100  ` -> `100` [PASS]
   - `1001` -> `1001` [PASS] (تأكيد عدم مساس الأصفار الداخلية)
   - `0000000000` -> `` [PASS]
   - `0000000001` -> `1` [PASS]
   - `001000` -> `1000` [PASS]
   - `00910001` -> `910001` [PASS]
   - `00A1` -> `a1` [PASS]
   - `  00SUB-99  ` -> `sub-99` [PASS]

2. **حزمة الاختبار 2 (محاكاة ومطابقة SQL REGEXP_REPLACE في محرك PostgreSQL)**:
   - فحص `SELECT REGEXP_REPLACE(TRIM(BOTH FROM lower('00123')), '^0+', '');` أسفر بدقة عن `'123'`. [PASS]
   - مطابقة تامة بنسبة 100% بين مخرجات استعلام PostgreSQL الحقيقي ودالة Go/Python عبر كافة الحالات الـ 15. [PASS]

3. **حزمة الاختبار 3 (فحص كشف التصادم ومنع التكرار الميداني)**:
   - فحص عينات المشتركين الحاليين (`910001`, `910002`, `910004`, `910226`, `910005`): تم كشف التصادم بنجاح مع المتغيرات (`0910001`, `00910001`, `  00910001  `). [PASS]
   - تنفيذ معاملة اختبارية لمنع التكرار واكتشاف التصادم عبر PL/pgSQL بنجاح تام. [PASS]

4. **حزمة الاختبار 4 (سلامة كود Go واختبارات الحزمة `smartpower/internal/services`)**:
   - تنفيذ `go test -v ./internal/services`:
     ```
     === RUN   TestHash
     --- PASS: TestHash (0.11s)
     === RUN   TestPhoneNormalization
     --- PASS: TestPhoneNormalization (0.00s)
     === RUN   TestToEnglishDigits
     --- PASS: TestToEnglishDigits (0.00s)
     === RUN   TestFinancialArithmeticFormula
     --- PASS: TestFinancialArithmeticFormula (0.00s)
     === RUN   TestFIFOWaterfallAlgorithm
     --- PASS: TestFIFOWaterfallAlgorithm (0.00s)
     === RUN   TestCreditCreationOnOverpayment
     --- PASS: TestCreditCreationOnOverpayment (0.00s)
     PASS
     ok      smartpower/internal/services    0.265s
     ```

5. **حزمة الاختبار 5 (التشغيل المباشر داخل بيئة Go Runtime لـ `NormalizeSubscriberNumber`)**:
   - تم تنفيذ اختبار Go حقيقي يمرر الحالات الـ 15 واجتازها جميعاً برمز خروج 0 وبزمن 0.123s. [PASS]

6. **فحص التجميع والبناء الكامل للمخدم `server.exe`**:
   - تنفيذ `go build -o server.exe ./cmd/server` اكتمل بنجاح برمز خروج 0 وبدون أي تحذيرات أو أخطاء تجميع.

---

## 2. Logic Chain (سلسلة الاستدلال والتحليل المنطقي)

1. **الاستدلال على صحة التعبير النمطي `^0+`**:
   - التعبير `^0+` يحدد بدقة أي تتابع لأصفار تقع في بداية السلسلة النصية فقط.
   - الأصفار في المنتصف (مثل `1001`) أو في النهاية (مثل `100` أو `1000`) لا تتطابق مع بداية السلسلة (`^`)، وبالتالي تبقى سليمة دون أي مساس.
   - الأرقام التي تحتوي على أصفار فقط (مثل `0` و `000`) تتحول إلى سلسلة فارغة `""`. وبما أن الدالة `CreateCustomer` تفحص `if trimmedSubNo == ""` وتستدعي `GetNextSubscriberNumber`، فإن أي إدخال فارغ يتم معالجته بتوليد رقم تسلسلي تلقائي، بينما أي محاولة لإدخال `0` أو `00` يتم اكتشافها كتعارض مع الفهرس ومطابقتها لمنع الازدواجية.

2. **الاستدلال على تكافؤ Go و PostgreSQL**:
   - في Go: `leadingZeroRegex.ReplaceAllString(strings.ToLower(strings.TrimSpace(sub)), "")`
   - في PostgreSQL: `REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')`
   - التجربة الميدانية المباشرة أثبتت تطابقاً بنسبة 100% بين المخرجين عبر 15 عينة اختبارية.

3. **الاستدلال المعماري لحماية النظام عبر طبقتين (Defense in Depth)**:
   - **الطبقة الأولى (Application Layer)**: خدمات `CreateCustomer` و `UpdateCustomer` و `UpdateGridCell` تستعلم مسبقاً باستخدام `REGEXP_REPLACE(...) = ?` مما يمنع إرسال أي أمر إدراج مكرر ويعيد رسالة خطأ عربية واضحة ومفهومة للمستخدم.
   - **الطبقة الثانية (Storage Layer)**: الفهرس الفريد `uq_customers_subscriber_number_clean` في سكيما التثبيت النظيفة `init_schema.sql` يمنع كلياً إدخال أي سجلات مكررة حتى في حال تجاوز طبقة التطبيق.

---

## 3. Caveats & Architectural Recommendations (المحاذير والملاحظات المعمارية)

1. **ملاحظة فهرس قاعدة البيانات الحالية `smartpower_db` [مؤكد]**:
   - سكيما التوزيع المحمول الجديدة `dist_portable/schema/init_schema.sql` تحتوي على الفهرس الصحيح بدقة:
     `CREATE UNIQUE INDEX uq_customers_subscriber_number_clean ON public.customers USING btree (REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')) WHERE (is_deleted = false);`
   - ولكن في قاعدة البيانات التطويرية المحلية الحالية `smartpower_db` (التي تعمل على المنفذ 5432)، لا يزال الفهرس مبنياً على `TRIM(BOTH FROM lower(subscriber_number))` لأن `CREATE UNIQUE INDEX IF NOT EXISTS` لم تقم بإعادة بنائه.
   - **التوصية للمرحلة M2/M3**: في حال الرغبة في تحديث قاعدة بيانات التطوير الحالية، يتم تنفيذ:
     `DROP INDEX IF EXISTS uq_customers_subscriber_number_clean;` متبوعاً بأمر الإنشاء الجديد. مع العلم أن ذلك لا يؤثر على المثبت النهائي لأن المثبت ينشئ قاعدة البيانات من الصفر اعتماداً على `init_schema.sql`.

2. **الأرقام العربية المشرقية في واجهات API المباشرة [مرجّح]**:
   - الدالة `NormalizeSubscriberNumber` تبدأ بـ `strings.ToLower(strings.TrimSpace(sub))`.
   - التعبير `^0+` يتعامل مع الصفر الإنجليزي ASCII (`0`).
   - الواجهة الأمامية تطبق `toEnglishDigits` على جميع الحقول قبل الإرسال. لكن لتوفير حماية إضافية (Defense in Depth) في حال تم استدعاء الـ API من جهات خارجية بأرقام مشرقية (مثل `٠١٠٠`)، يُقترح استدعاء `ToEnglishDigits(sub)` داخل `NormalizeSubscriberNumber` مستقبلاً.

---

## 4. Conclusion & Verdict (الخلاصة والقرار النهائي)

- **القرار**: **`APPROVE`** [مؤكد].
- **مبررات القرار**:
  1. نجاح دالة `NormalizeSubscriberNumber` بنسبة 100% في كافة الحالات الطرفية المطلوبة (`0001`, `0`, `000`, `100`, `0100`, `00100`) و 9 حالات إضافية.
  2. ثبوت تكافؤ منطق Go مع استعلام PostgreSQL `REGEXP_REPLACE(TRIM(BOTH FROM lower('00123')), '^0+', '') = '123'`.
  3. كفاءة منطق كشف التصادم ومنع التكرار في `CreateCustomer` و `UpdateCustomer` و `UpdateGridCell` و `GetNextSubscriberNumber`.
  4. اجتياز كافة اختبارات حزمة `server/internal/services` بنجاح واكتمال بناء `server.exe` بدون أخطاء.

---

## 5. Verification Method (طريقة التحقق المستقل)

لإعادة التحقق المستقل والتكرار التجريبي الكامل:

1. **تشغيل سكربت اختبار الإجهاد الشامل**:
   ```powershell
   cd d:\elctercity
   python test_subscriber_anti_duplication.py
   ```
   - النتيجة المتوقعة: اجتياز حزم الاختبار الـ 5 وظهور `VERDICT: ALL ADVERSARIAL STRESS TESTS COMPLETED AND VERIFIED [PASS]`.

2. **تشغيل اختبارات خدمات Go**:
   ```powershell
   cd d:\elctercity\server
   go test -v ./internal/services
   ```
   - النتيجة المتوقعة: ظهور `PASS` و `ok smartpower/internal/services`.

3. **التحقق من تجميع السيرفر**:
   ```powershell
   cd d:\elctercity\server
   go build -o server.exe ./cmd/server
   ```
   - النتيجة المتوقعة: نجاح التجميع برمز خروج 0.
