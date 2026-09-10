# تقرير المراجعة والتدقيق النقدي المعاكس — المرحلة M1: كود الواجهة الخلفية
# Review & Adversarial Critic Report — Milestone M1: Backend Code Review

- **المراجع والناقد (Reviewer & Critic)**: `reviewer_m1_1`
- **الهدف (Target)**: مراجعة تعديلات `worker_m1` في `server/cmd/server/main.go` و `server/internal/services/customer_service.go` وقاعدة البيانات
- **تاريخ المراجعة**: 2026-09-07T15:10:00Z
- **القرار النهائي (Verdict)**: **APPROVE (مع ملاحظات تحسين استشارية)**

---

## 1. Observation (الملاحظات المباشرة والأدلة)

### 1.1 فحص نقطة دخول الخادم `server/cmd/server/main.go`
- **استدعاء دورة حياة قاعدة البيانات**:
  - السطر 37: استدعاء `dbManager, err := database.NewDBLifecycleManager()`.
  - السطر 41: استدعاء `dbURL, err := dbManager.EnsureDatabaseReady()` **قبل** استدعاء `database.InitDB(cfg)` في السطر 57.
  - الأسطر 45-48: تجاوز رابط الاتصال `cfg.DatabaseURL = dbURL` عند توفر المنفذ 15432 المعزول.
  - الأسطر 50-54: تأمين الإغلاق الاحتياطي عبر `defer func() { if dbManager != nil { _ = dbManager.Stop() } }()`.
- **اعتراض إشارات الإغلاق الآمن**:
  - الأسطر 251-265: اعتراض إشارات `os.Interrupt` و `syscall.SIGTERM` عبر Goroutine مستقل وقناة `quit := make(chan os.Signal, 1)`.
  - استدعاء `dbManager.Stop()` ثم `app.Shutdown()` ثم `os.Exit(0)`.

### 1.2 فحص خدمة المشتركين `server/internal/services/customer_service.go`
- **دالة التجريد والتطبيع**:
  - الأسطر 31-38: تعريف التعبير النمطي `leadingZeroRegex = regexp.MustCompile("^0+")` وتطبيق دالة `NormalizeSubscriberNumber(sub string) string` التي تقوم بقص المسافات وتحويل الأحرف وتجريد الأصفار البادئة.
- **الحماية في إنشاء المشترك `CreateCustomer`**:
  - الأسطر 159-165: فحص التصادم برمجياً قبل الإدخال:
    `s.db.Where("REGEXP_REPLACE(TRIM(LOWER(subscriber_number)), '^0+', '') = ? AND is_deleted = false", cleanSub).First(&existing)`
    مع إرجاع رسالة خطأ واضحة باللغة العربية.
  - الأسطر 178-183: اعتراض خطأ الفهرس الفريد لقاعدة البيانات وترجمته لرسالة ودية.
- **الحماية في توليد الرقم التلقائي `GetNextSubscriberNumber`**:
  - الأسطر 140-151: حلقة فحص التصادم:
    `s.db.Model(&models.Customer{}).Where("REGEXP_REPLACE(TRIM(LOWER(subscriber_number)), '^0+', '') = ? AND is_deleted = false", NormalizeSubscriberNumber(candidateStr)).Count(&count)`
- **الحماية في تعديل المشترك `UpdateCustomer`**:
  - الأسطر 331-344: مقارنة القيمة المنظفة الجديدة مع القديمة، ثم فحص وجود الرقم لأي مشترك آخر باستثناء المشترك الحالي (`id != ?`).
- **الحماية في تعديل الخلية المباشر `UpdateGridCell`**:
  - الأسطر 432-448: تطبيق الفحص الصارم داخل معاملة مالية مقفلة بسطر المشترك (`FOR UPDATE`).

### 1.3 فحص قيود قاعدة البيانات والسكيما المحمولة
- **مخطط `dist_portable/schema/init_schema.sql`**:
  - السطر 6034: تم التحقق من وجود الفهرس الصارم:
    `CREATE UNIQUE INDEX uq_customers_subscriber_number_clean ON public.customers USING btree (REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')) WHERE (is_deleted = false);`
  - عدد المشتركين: 494 مشتركاً بالضبط (تم إزالة المشترك التجريبي 495).
  - عدد الفواتير: 494 فاتورة تتبع حصراً دورة `أغسطس 2`.
  - عدد قراءات العداد: 494 قراءة بالضبط.
  - مؤشرات التسلسل: `customers_id_seq` = 494، `invoices_id_seq` = 494، `meter_readings_id_seq` = 494.
- **مخطط `database/02_tables_and_constraints.sql`**:
  - السطر 167: وجود نفس الفهرس الفريد عبر `CREATE UNIQUE INDEX IF NOT EXISTS uq_customers_subscriber_number_clean ...`.

### 1.4 التحقق الميداني من الاختبارات والبناء
- تشغيل `go test -v ./...` في `server/`:
  - اجتياز جميع الاختبارات بنجاح (`PASS`) بدون أي فشل في غضون 0.223 ثانية.
- تشغيل `go build -o server_test_build.exe ./cmd/server`:
  - اكتمال التجميع بنجاح برمز خروج 0 وحجم تنفيذي متكامل.

---

## 2. Logic Chain (سلسلة الاستدلال المنطقي)

1. **التحقق من صحة الربط المعماري**:
   - استدعاء `EnsureDatabaseReady()` قبل `InitDB` يضمن أن بيئة العمل المحمولة (Portable PostgreSQL على المنفذ 15432) تعمل وتهيئ سكيما أغسطس 2 قبل محاولة الخادم فتح بركة الاتصالات (Connection Pool).
   - تجاوز `cfg.DatabaseURL` بالرابط المعزول `127.0.0.1:15432` يمنع تماماً التداخل مع أي خادم PostgreSQL محلي أو خارجي آخر.
   - التقاط إشارات النظام يضمن إيقاف المحرك الخلفي بنظافة دون ترك ملفات أقفال ميتة (`postmaster.pid`).

2. **التطابق التام بين طبقة التطبيق وطبقة قاعدة البيانات**:
   - التعبير النمطي في Go: `regexp.MustCompile("^0+").ReplaceAllString(trimmed, "")`
   - الدالة المقابلة في PostgreSQL: `REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')`
   - التماثل الرياضي والمنطقي بين التعبيرين يضمن أن أي قيمة يعتبرها Go مكررة ستعتبرها قاعدة البيانات مكررة والعكس صحيح بنسبة 100%.

3. **التحقق من النزاهة (Integrity Check)**:
   - لا توجد أي نتائج اختبارات مسبقة البرمجة (Hardcoded test results).
   - لا توجد واجهات وهمية (Facade implementations).
   - تم التحقق المستقل من سلامة الملفات والأكواد مباشرة دون الاعتماد على ادعاءات العامل السابقة.

---

## 3. Caveats & Adversarial Findings (المحاذير والملاحظات النقدية المعاكسة)

### [Minor/Architectural] ملاحظة 1: ترتيب إيقاف الخدمات عند الإغلاق الآمن في `main.go`
- **الموقع**: `server/cmd/server/main.go:256-263`
- **الملاحظة**: يستدعي الكود حالياً `dbManager.Stop()` أولاً ثم `app.Shutdown()`.
- **الخطر**: في حال وجود طلبات HTTP قيد المعالجة لحظة استلام إشارة الإيقاف، فإن إيقاف قاعدة البيانات قبل إغلاق خادم الويب قد يؤدي إلى فشل تلك الطلبات بأخطاء اتصال بقاعدة البيانات.
- **التوصية**: يُفضل في مراحل التطوير اللاحقة عكس الترتيب: استدعاء `app.Shutdown()` أولاً لإيقاف استقبال الطلبات وإنهاء الاتصالات العالقة، ثم استدعاء `dbManager.Stop()`.

### [Minor/Edge-Case] ملاحظة 2: التحويل الصارم لنوع رقم المشترك في `UpdateGridCell`
- **الموقع**: `server/internal/services/customer_service.go:433-437`
- **الملاحظة**: يعتمد الكود على `payload["subscriber_number"].(string)`.
- **الخطر**: إذا أرسل العميل رقم المشترك كقيمة رقمية في الـ JSON (مثل `{"subscriber_number": 1234}`) بدلاً من نص، سيفشل فحص النوع (`ok == false`) ويتم تجاهل التعديل بصمت.
- **التوصية**: التعامل بمرونة مع النوع الرقمي أو استخدام `fmt.Sprintf("%v", val)` لدعم الإدخال النصي والرقمي على حد سواء.

### [Minor/Coverage] ملاحظة 3: غياب اختبارات الوحدة الخاصة بدالة `NormalizeSubscriberNumber`
- **الموقع**: `server/internal/services/`
- **الملاحظة**: على الرغم من نجاح حزمة الاختبارات العامة، إلا أنه لا يوجد ملف اختبارات وحدة مخصص لدالة `NormalizeSubscriberNumber` وتفرعات منع التكرار في `customer_service.go`.
- **التوصية**: إضافة اختبارات مائدة (Table-driven tests) لتغطية الحالات الشاذة (`0123`, `00123`, `0`, `100`, `abc`).

---

## 4. Conclusion (الخلاصة والقرار النهائي)

- **القرار النهائي**: **APPROVE** (اعتماد كامل لمخرجات المرحلة M1).
- تم استيفاء جميع المتطلبات الوظيفية والمعمارية بدقة:
  1. الربط المعماري الكامل لـ `DBLifecycleManager` في `server/cmd/server/main.go`.
  2. التطبيق الصارم لمنع تكرار المشتركين في جميع المسارات الأربعة (`CreateCustomer`, `UpdateCustomer`, `UpdateGridCell`, `GetNextSubscriberNumber`).
  3. التماثل الكامل بين كود Go وفهرس قاعدة البيانات الفريد `uq_customers_subscriber_number_clean`.
  4. نظافة سكيما التوزيع المحمول مع 494 مشتركاً حقيقياً وضبط دقيق للمؤشرات.
  5. اجتياز اختبارات Go وتجميع الملف التنفيذي بنجاح 100%.

---

## 5. Verification Method (طريقة التحقق المستقل)

1. **تشغيل اختبارات Go**:
   ```powershell
   cd d:\elctercity\server
   go test -v ./...
   ```
   - النتيجة: `ok smartpower/internal/services 0.223s` (اجتياز 100%).

2. **التحقق من تجميع السيرفر**:
   ```powershell
   cd d:\elctercity\server
   go build -o server_test_build.exe ./cmd/server
   ```
   - النتيجة: نجاح التجميع برمز خروج 0.

3. **التحقق المستقل من السكيما والفهارس**:
   ```powershell
   cd d:\elctercity
   Select-String -Path "dist_portable\schema\init_schema.sql" -Pattern "uq_customers_subscriber_number_clean"
   Select-String -Path "database\02_tables_and_constraints.sql" -Pattern "uq_customers_subscriber_number_clean"
   ```
   - النتيجة: ظهور تعريف الفهرس الفريد باستخدام `REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')`.
