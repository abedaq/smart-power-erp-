<div dir="rtl">

# تقرير الاستطلاع الفني: محرك PostgreSQL 18 المدمج، دورة حياة قاعدة البيانات، ومخطط التهيئة الأولي

## 1. الملاحظات المباشرة (Observations)

### أ. ملفات محرك PostgreSQL 18 المحمول (Portable Engine Binaries)
- **المسار الأساسي**: `d:/elctercity/dist_portable/pgsql`
- **الحجم الإجمالي وعدد الملفات**: 1740 ملفاً بحجم غير مضغوط يبلغ 147,031,864 بايت (~140.22 ميجابايت).
- **إصدار المحرك**: PostgreSQL 18.6 (x64) مثبت من ترويسة ملف التصدير ومن ملفات الترجمة `share/locale/*/LC_MESSAGES/*-18.mo`.
- **محتويات المجلد `dist_portable/pgsql/bin`** (37 ملفاً، بحجم 77,988,718 بايت / 74.38 ميجابايت):
  - `postgres.exe`: الحجم 10,266,624 بايت (السطر التنفيذي الرئيسي للمحرك).
  - `initdb.exe`: الحجم 246,784 بايت (لتهيئة عنقود البيانات الأولي).
  - `pg_ctl.exe`: الحجم 133,120 بايت (للتحكم في تشغيل وإيقاف المحرك كخدمة محلية).
  - `psql.exe`: الحجم 653,824 بايت (لتنفيذ سكريبتات SQL واستيراد المخطط الأولي).
  - أدوات مساعدة: `createdb.exe` (135,680 بايت)، `dropdb.exe` (134,144 بايت)، `pg_dump.exe` (633,344 بايت)، `pg_restore.exe` (379,904 بايت).
  - مكتبات الربط الديناميكي الأساسية (DLLs): `libpq.dll` (384,512 بايت)، `libcrypto-3-x64.dll` (5,708,800 بايت)، `libssl-3-x64.dll` (1,313,792 بايت)، حزم ICU الدولية (`icudt77.dll` بحجم 31.89 ميجابايت، `icuin77.dll`، `icuuc77.dll`، `icuio77.dll`، `icutu77.dll`)، و `zlib1.dll`، `libzstd.dll`، `liblz4.dll`، `libxml2.dll`، `libxslt.dll`.
- **محتويات المجلد `dist_portable/pgsql/lib`** (146 ملفاً، بحجم 38,185,566 بايت / 36.42 ميجابايت):
  - ملحقات وإضافات برمجية: `plpgsql.dll`، `pgcrypto.dll` (212,480 بايت)، `uuid-ossp.dll` (49,664 بايت)، `btree_gist.dll`، `btree_gin.dll`، `citext.dll`، `hstore.dll`، `unaccent.dll`، `postgres_fdw.dll`.
- **محتويات المجلد `dist_portable/pgsql/share`** (1557 ملفاً، بحجم 30,857,580 بايت / 29.43 ميجابايت):
  - ملفات القوالب والتهيئة التأسيسية: `postgres.bki` (985,639 بايت)، `postgresql.conf.sample` (32,652 بايت)، `pg_hba.conf.sample` (5,635 بايت)، `information_schema.sql` (113,997 بايت)، قوالب المناطق الزمنية واللغات وقواعد البيانات النصية.

---

### ب. فحص كود دورة حياة قاعدة البيانات (`db_lifecycle.go`)
- **مسار الملف**: `d:/elctercity/server/internal/database/db_lifecycle.go` (246 سطراً).
- **فحص الآليات الخمس المطلوبة**:
  1. **التهيئة لأول مرة (`initdb`)**:
     - الأسطر 86-98: يتحقق من وجود الراية عبر `os.Stat(flagFile)`، وإذا لم تكن موجودة يُسند `needsInit = true` ويستدعي `m.initDB()`.
     - الأسطر 123-137:
       ```go
       initdbExe := filepath.Join(m.PgBinDir, "initdb.exe")
       cmd := exec.Command(initdbExe,
           "-D", m.DataDir,
           "-U", "postgres",
           "-E", "UTF8",
           "--locale=C",
           "-A", "trust",
       )
       ```
     - الأسطر 198-231 في دالة `createDatabaseAndSeed`: ينشئ قاعدة البيانات `smartpower_db` ثم يستدعي `psql.exe` لتنفيذ ملف التهيئة:
       ```go
       cmd := exec.Command(psqlExe,
           "-h", "127.0.0.1",
           "-p", strconv.Itoa(m.Port),
           "-U", "postgres",
           "-d", "smartpower_db",
           "-f", m.InitDataFile,
       )
       ```
  2. **ربط المنفذ المعزول محلياً (`127.0.0.1:15432`)**:
     - السطر 60: `port := 15432`
     - السطر 68: `DatabaseURL: fmt.Sprintf("postgres://postgres:postgres@127.0.0.1:%d/smartpower_db?sslmode=disable", port)`
     - الأسطر 164-169 في دالة `startPostgres`:
       ```go
       cmd := exec.Command(pgCtl,
           "-D", m.DataDir,
           "-l", logFile,
           "-o", fmt.Sprintf("-p %d -h 127.0.0.1", m.Port),
           "start",
       )
       ```
       يتم تمرير المعامل الصارم `-o "-p 15432 -h 127.0.0.1"` مما يقيد الاستماع على الـ Loopback الداخلي فقط.
  3. **راية عدم التكرار (`.db_initialized`)**:
     - السطر 86: `flagFile := filepath.Join(m.DataDir, ".db_initialized")`
     - السطر 88: التحقق من عدم وجود الراية `if _, err := os.Stat(flagFile); os.IsNotExist(err) { needsInit = true }`
     - السطر 115: إنشاء الراية وكتابة الختم الزمني عند نجاح أول استيراد:
       ```go
       _ = os.WriteFile(flagFile, []byte(time.Now().Format(time.RFC3339)), 0644)
       ```
     - عند الإقلاع الثاني، وجود الملف يمنع إعادة استدعاء `initdb` واستيراد السكيما، مما يمنع تصفير البيانات.
  4. **كشف القفل العالق وإصلاحه تلقائياً (`postmaster.pid`)**:
     - الأسطر 139-158 في دالة `cleanStalePID`:
       ```go
       pidFile := filepath.Join(m.DataDir, "postmaster.pid")
       data, err := os.ReadFile(pidFile)
       // ...
       pid, err := strconv.Atoi(strings.TrimSpace(lines[0]))
       if err == nil {
           chk := exec.Command("tasklist", "/FI", fmt.Sprintf("PID eq %d", pid))
           out, _ := chk.Output()
           if !strings.Contains(string(out), fmt.Sprintf("%d", pid)) {
               log.Printf("🧹 Removing stale postmaster.pid (PID %d is no longer active)", pid)
               _ = os.Remove(pidFile)
           }
       }
       ```
  5. **الإغلاق الآمن السلس (`pg_ctl stop -m fast`)**:
     - الأسطر 233-245 في دالة `Stop()`:
       ```go
       func (m *DBLifecycleManager) Stop() error {
           if !m.IsPortable {
               return nil
           }
           log.Println("🛑 Stopping embedded PostgreSQL server gracefully...")
           pgCtl := filepath.Join(m.PgBinDir, "pg_ctl.exe")
           cmd := exec.Command(pgCtl, "-D", m.DataDir, "-m", "fast", "stop")
           out, err := cmd.CombinedOutput()
           if err != nil {
               log.Printf("pg_ctl stop output: %s", string(out))
           }
           return err
       }
       ```
- **الثغرة الجوهرية المكتشفة في الكود (Critical Disconnection)**:
  - عند فحص `server/cmd/server/main.go` (الأسطر 30-37):
    ```go
    // 1. Load Configuration
    cfg := config.LoadConfig()

    // 2. Initialize Database Connection
    db, err := database.InitDB(cfg)
    ```
  - **ملاحظة قطعية**: دالة `NewDBLifecycleManager()` ودالة `EnsureDatabaseReady()` **لا يتم استدعاؤهما نهائياً** داخل `main.go` أو أي ملف تنفيذي آخر في المشروع!
  - في `server/internal/config/config.go` (السطر 42): الرابط الافتراضي لقاعدة البيانات مضبوط على المنفذ 5432 (`postgres://postgres:postgres@localhost:5432/smartpower_db?sslmode=disable`).
  - في `server/cmd/server/main.go`: لا يوجد أي التقاط لإشارات النظام (`os.Interrupt` / `syscall.SIGTERM`)، وبالتالي دالة `Stop()` لإيقاف محرك PostgreSQL بسلاسة لا يتم استدعاؤها مطلقاً عند إغلاق التطبيق.

---

### ج. فحص سكريبت ومخطط قاعدة البيانات (`dist_portable/schema/init_schema.sql`)
- **مسار الملف**: `d:/elctercity/dist_portable/schema/init_schema.sql`
- **الحجم والأسطر**: 833,130 بايت (~813 كيلوبايت)، ويحتوي على 7818 سطراً.
- **تعداد سجلات المشتركين (`customers`)**:
  - يبدأ أمر الاستيراد في السطر 2649 وينتهي في السطر 3145:
    `COPY public.customers (...) FROM stdin;`
  - إجمالي الأسطر الموجودة: **495 سطراً** (بفارق سطر واحد عن الرقم المطلوب 494).
  - التفصيل الدقيق للسجلات:
    - **494 مشتركاً فعلياً** (المعرفات من 1 إلى 494): تاريخ إنشائهم هو `2026-08-30 13:00:00+03`، وحقل `start_cycle` مضبوط على `أغسطس 2`، وحالتهم جميعاً `Active` و `is_deleted = f`.
    - **سجل اختبار تجريبي إضافي (السطر 3119)**:
      ```tsv
      495	1212121	اختبار نظام	773245776	\N	تعز	02154	1	\N	5.00	0.00	0.00	0.00	Active	f	\N	2026-09-07 15:16:47.833337+03	2026-09-07 16:25:42.830217+03	سبتمبر 1
      ```
      المشترك برقم `1212121` واسم `اختبار نظام` أُضيف أثناء اختبارات النظام بتاريخ اليوم (2026-09-07 الساعة 15:16:47).
- **فحص جداول دورة أغسطس 2 (القراءات، الفواتير، والمدفوعات)**:
  - **الفواتير (`invoices`)**: الأسطر 3152 إلى 5133، بإجمالي **1979 فاتورة** موزعة كالآتي:
    - دورة `أغسطس 2`: **494 فاتورة** (المعرفات 1 إلى 494، تاريخ إنشائها 2026-08-30، حالتها `APPROVED` و `Unpaid`).
    - دورة `سبتمبر 1`: **495 فاتورة** (تاريخ إنشائها اليوم 2026-09-07 الساعة 15:05:07، حالتها `PENDING`).
    - دورة `سبتمبر 2`: **495 فاتورة** (تاريخ إنشائها اليوم 2026-09-07 الساعة 15:17:31، حالتها `PENDING`).
    - دورة `أكتوبر 1`: **495 فاتورة** (تاريخ إنشائها اليوم 2026-09-07 الساعة 15:17:38، حالتها `PENDING`).
    - جدول `billing_cycles` (السطر 2621): يحتوي فقط على دورة واحدة معرفها 1 وهي `أغسطس 2`. الدورات اللاحقة غير معرفة رسمياً كدورات كاملة في هذا الجدول بالرغم من توليد 1485 فاتورة لها.
  - **القراءات (`meter_readings`)**: الأسطر 5139 إلى 5636، بإجمالي **495 قراءة**:
    - 494 قراءة تابعة لدورة `أغسطس 2` (المعرف cycle_id = 1) وحالتها `APPROVED`.
    - قراءة واحدة للمشترك رقم 495 (`اختبار نظام`) بقيمة 5.00 ومعرف الدورة فيها فارغ `\N`.
  - **المدفوعات (`payments`)**: الأسطر 5704 إلى 5752، بإجمالي **46 دفعة معتمدة** مسجلة في التواريخ 2026-09-04 إلى 2026-09-06.
  - **توزيعات المدفوعات (`payment_allocations`)**: الأسطر 5642 إلى 5689، بإجمالي **45 تخصيصاً** سارياً.
  - **بيانات اختبارية أخرى متخلفة في السكريبت**:
    - `whatsapp_queue_messages`: يحتوي على 21 رسالة اختبار متخلفة (الأسطر 5794-5817).
    - `audit_logs`: يحتوي على 75 سجلاً من سجلات التدقيق الناتجة عن عمليات التعديل التجريبية اليوم (الأسطر 2538-2615).
- **فحص فهرس منع تكرار رقم المشترك (Unique Index)**:
  - في `init_schema.sql` (السطر 7524):
    ```sql
    CREATE UNIQUE INDEX uq_customers_subscriber_number_clean ON public.customers USING btree (TRIM(BOTH FROM lower((subscriber_number)::text))) WHERE (is_deleted = false);
    ```
  - **ملاحظة نقدية**: الفهرس الحالي يعتمد `TRIM(BOTH FROM lower(subscriber_number))`، بينما المتطلب R3 ينص صراحة على:
    `REGEXP_REPLACE(subscriber_number, '^0+', '')`
    حتى يتم منع التكرار مع وجود أصفار بادئة (مثل اعتبار 00123 و 123 رقمين متطابقين).
  - في كود Go (`customer_service.go` الأسطر 136 و 152 و 325 و 426): يتم فقط مقارنة `TRIM(LOWER(subscriber_number))` بدون تنظيف الأصفار البادئة.

---

## 2. سلسلة الاستدلال المنطقي (Logic Chain)

1. **الاستدلال على بنية وتكامل محرك قاعدة البيانات**:
   - بناءً على الملاحظة (أ)، محرك PostgreSQL 18.6 كاملاً بجميع ملفاته الثنائية التنفيذية (`postgres.exe`, `initdb.exe`, `pg_ctl.exe`, `psql.exe`) ومكتباته متوفر في المجلد `dist_portable/pgsql`.
   - هذا يثبت أن الحزمة المستقلة لا تحتاج إلى تثبيت مسبق لمحرك PostgreSQL خارجي من قبل العميل، وأن جميع الأدوات المطلوبة للتهيئة والتشغيل موجودة محلياً.

2. **الاستدلال على اكتمال المنطق البرمجي لدورة الحياة مقابل انقطاع الربط**:
   - بناءً على الملاحظة (ب)، تم تصميم `DBLifecycleManager` في `db_lifecycle.go` بكفاءة عالية؛ حيث يغطي التهيئة التلقائية (`initdb`)، تشغيل المحرك على المنفذ المعزول `15432` على `127.0.0.1`، كتابة راية التثبيت `.db_initialized` لمنع إعادة التهيئة، كشف القفل العالق للـ PID الميت عبر أمر `tasklist`، وإيقاف المحرك سريعاً بـ `pg_ctl stop -m fast`.
   - غير أنه بمراجعة نقطة الدخول الرئيسية `server/cmd/server/main.go`، يتضح أن هذا المدير غير مستدعى إطلاقاً، والتطبيق يحاول الاتصال المباشر على المنفذ الافتراضي 5432 عبر `InitDB(cfg)`.
   - يترتب على ذلك منطقياً: إذا تم تشغيل الحزمة المحمولة حالياً، سيفشل الاتصال بقاعدة البيانات لعدم بدء تشغيل المحرك المحمول المدمج تلقائياً عند إقلاع السيرفر.

3. **الاستدلال على حالة وملاءمة بيانات التهيئة (`init_schema.sql`)**:
   - بناءً على الملاحظة (ج)، ملف `dist_portable/schema/init_schema.sql` ليس ملف قالب خام (Seed Skeleton)، بل هو نسخة احتياطية حية تم استخراجها عبر `pg_dump` من قاعدة بيانات كانت قيد الاختبار النشط في 2026-09-07.
   - النتيجة المنطقية هي وجود المشترك التجريبي رقم 495 (`اختبار نظام`)، وفواتير غير معتمدة للدورات المستقبلية (سبتمبر 1، سبتمبر 2، أكتوبر 1 بإجمالي 1485 فاتورة)، ورسائل واتساب عالقة وسجلات تدقيق تجريبية.
   - لضمان وصول النظام للمستخدم النهائي بحالة "أغسطس 2 نظيفة" تقتصر على 494 مشتركاً، يجب إزالة هذا السجل التجريبي والفواتير التابعة للدورات اللاحقة قبل التغليف النهائي للحزمة.

---

## 3. التحفظات والحدود (Caveats)

- [مؤكد] لم يتم تعديل أي ملف في الكود أو قاعدة البيانات التزاماً بدور الاستطلاع الصارم للقراءة فقط.
- [مؤكد] لم يتم تشغيل أوامر بناء (Build Commands).
- [مرجّح] ملف التثبيت `SmartPowerERP_Setup.exe` الموجود في المجلد الرئيسي بحجم 37,530,036 بايت تم تجميعه مسبقاً، ولكن نظراً لانفصال `db_lifecycle.go` عن `main.go` في الكود المصدري الحالي، فإنه يحتاج إلى إعادة ربط وتجميع من قبل فريق العمل (Workers) في مراحل التنفيذ القادمة.
- [مؤكد] لا توجد تحفظات إضافية على النطاق المستطلع.

---

## 4. الخلاصة والتقييم النهائي (Conclusion)

1. **محرك PostgreSQL 18.6**: جاهز بنسبة 100% ومكتمل في المسار `dist_portable/pgsql` بحجم 147 ميجابايت (37 ملفاً تنفيذياً في bin، 146 مكتبة في lib، 1557 قالباً في share).
2. **مدير دورة الحياة (`db_lifecycle.go`)**: مكتمل منطقياً ويحقق الشروط الخمسة، لكنه **معزول وغير مربوط في نقطة دخول السيرفر `server/cmd/server/main.go`**. يجب على فريق العمل:
   - استدعاء `dbManager := database.NewDBLifecycleManager()` في `main.go`.
   - استدعاء `dbURL, err := dbManager.EnsureDatabaseReady()` واستبدال `cfg.DatabaseURL` بالرابط المرتجع على المنفذ 15432.
   - تسجيل قناة إشارات `os.Interrupt` و `syscall.SIGTERM` لاستدعاء `dbManager.Stop()` عند الخروج.
3. **مخطط وبيانات التهيئة (`init_schema.sql`)**:
   - يحتوي على 495 مشتركاً (494 حقيقيون + 1 مشترك تجريبي رقم 495).
   - يحتوي على 1979 فاتورة (494 لدورة أغسطس 2 + 1485 لدورات سبتمبر وأكتوبر الناتجة عن الاختبارات).
   - يحتاج إلى تنظيف (Sanitization) بحذف المشترك 495 وحذف فواتير الدورات اللاحقة وتفريغ جداول `audit_logs` و `whatsapp_queue_messages` لضمان نظافة الحزمة الأولى.
   - تعديل فهرس منع التكرار `uq_customers_subscriber_number_clean` ليعتمد `REGEXP_REPLACE(subscriber_number, '^0+', '')` لمطابقة المتطلب الصارم.

---

## 5. طريقة التحقق المستقل (Verification Method)

يمكن لأي مدقق أو عامل التحقق من هذه النتائج عبر الأوامر المستقلة التالية:

1. **التحقق من ملفات محرك PostgreSQL 18**:
   ```powershell
   Test-Path "d:/elctercity/dist_portable/pgsql/bin/postgres.exe"
   Test-Path "d:/elctercity/dist_portable/pgsql/bin/initdb.exe"
   Test-Path "d:/elctercity/dist_portable/pgsql/bin/pg_ctl.exe"
   Test-Path "d:/elctercity/dist_portable/pgsql/bin/psql.exe"
   ```

2. **التحقق من تعداد المشتركين والمشترك التجريبي في سكريبت التهيئة**:
   ```python
   with open('dist_portable/schema/init_schema.sql', 'r', encoding='utf-8') as f:
       lines = f.readlines()
   # استعراض أسطر المشتركين
   cust_lines = lines[2649:3144]
   print("Total Customers:", len(cust_lines))
   print("Line 3119 (Test Customer):", lines[3118])
   ```

3. **التحقق من فواتير الدورات المتعددة**:
   ```python
   with open('dist_portable/schema/init_schema.sql', 'r', encoding='utf-8') as f:
       text = f.read()
   invoices = text.split('COPY public.invoices ')[1].split('FROM stdin;')[1].split('\n\.')[0].strip().split('\n')
   cycles = {}
   for inv in invoices:
       c = inv.split('\t')[5]
       cycles[c] = cycles.get(c, 0) + 1
   print("Invoices by Cycle:", cycles)
   ```

4. **التحقق من عدم ربط `DBLifecycleManager` في `server/cmd/server/main.go`**:
   فحص الملف بالعين المجردة أو باستخدام أداة البحث:
   ```powershell
   Select-String -Path "d:/elctercity/server/cmd/server/main.go" -Pattern "DBLifecycle"
   ```
   (ستكون النتيجة: لا يوجد أي تطابق).

</div>
