<div dir="rtl">

# التقرير الهندسي الشامل لمعالجة بوابات العبور في سجل التنفيذ الحي
## (Phase Gates Remediation Plan: MIGRATION/EXECUTION_LOG.md)

- **معرف الوكيل**: `explorer_m1_r2_gates_fix` (Phase Gates Remediation Explorer)
- **الموجه المستلم**: `orchestrator_migration` (Conversation ID: `8662d701-dced-4ddd-b545-e2b64c0e3fc2`)
- **تاريخ الصياغة**: 2026-09-06T09:05:00Z
- **مسار التقرير**: `d:\elctercity\.agents\explorer_m1_r2_gates_fix\analysis.md`
- **النطاق والوثائق المرجعية**:
  - `d:\elctercity\MIGRATION\EXECUTION_LOG.md`
  - `d:\elctercity\.agents\reviewer_m1_2\handoff.md`
  - `d:\elctercity\.agents\explorer_m1_executionlog\analysis.md`
  - `d:\elctercity\.agents\ORIGINAL_REQUEST.md` (§ 2026-09-06T07:57:38Z)

---

## 1. الحقيقة التقنية والمخاطر التشغيلية أولاً (Technical Reality & Operational Risks)

1. [مؤكد] **المأزق الراهن في `MIGRATION/EXECUTION_LOG.md`**:
   - يحتوي ملف `MIGRATION/EXECUTION_LOG.md` حالياً على 4 بوابات عبور فقط تخص المرحلة 1 (`Gate 1.1` إلى `Gate 1.4`).
   - المراحل من 2 إلى 5 (الأسطر 192-218) وردت بصيغة أسطر نائبة مقتضبة جداً (Placeholders) من 3 إلى 5 أسطر لكل مرحلة، دون ذكر أي بوابة عبور تفصيلية، أو أوامر PowerShell للتحقق، أو مخرجات طرفية متوقعة، أو معايير عبور رقمية.
2. [مؤكد] **الخطر الهندسي للغياب المسبق لبوابات المراحل**:
   - ترك المراحل المستقبلية بدون بوابات محددة مسبقاً قبل بدء التنفيذ يفتح الباب واسعاً لما يُعرف بـ "البوابات الصورية" (Fake Gates)، حيث يمكن لأي عامل في المراحل M2 أو M3 أو M4 أو M5 صياغة اختبارات متساهلة أو تخطي الشروط المعمارية الحرجة (مثل القفل المتشائم `FOR UPDATE` أو قيد تصاعد العدادات أو اختبارات التعافي من الكوارث).
3. [مؤكد] **تدقيق الحصر الحسابي للبوابات (Gate Count Reconciliation)**:
   - أشار تقرير المراجع `reviewer_m1_2` وموجه التكليف إلى "22 بوابة مفقودة للمراحل 2-5" و "إجمالي 26 بوابة".
   - عند الفحص الدقيق والعد الفعلي للمواصفات المعمارية المعتمدة في `explorer_m1_executionlog\analysis.md` (الأسطر 224-650)، نجد أن التوزيع الفعلي هو:
     - **المرحلة 1**: 4 بوابات (`Gate 1.1` إلى `Gate 1.4`) — مكتملة وموثقة بـ `PASS`.
     - **المرحلة 2**: 6 بوابات (`Gate 2.1` إلى `Gate 2.6`) — مفقودة في السجل الراهن.
     - **المرحلة 3**: 7 بوابات (`Gate 3.1` إلى `Gate 3.7`) — مفقودة في السجل الراهن.
     - **المرحلة 4**: 5 بوابات (`Gate 4.1` إلى `Gate 4.5`) — مفقودة في السجل الراهن.
     - **المرحلة 5**: 5 بوابات (`Gate 5.1` إلى `Gate 5.5`) — مفقودة في السجل الراهن.
     - **المجموع الفعلي للمراحل 2 إلى 5**: $6 + 7 + 5 + 5 = 23$ بوابة تفصيلية.
     - **المجموع الكلي للنظام عبر المراحل 1 إلى 5**: $4 + 23 = 27$ بوابة صارمة.
   - سنقوم في هذا التقرير باستخراج وصياغة كافة البوابات الـ 23 كاملة بدون إسقاط أي بوابة، لضمان تغطية معمارية بنسبة 100% تتجاوز الحد الأدنى المطلوب وتمنع أي ثغرة.
4. [مؤكد] **الالتزام الصارم بقواعد الأرقام الإنجليزية (0-9)**:
   - تم فحص وتدقيق كافة الأوامر والمخرجات المتوقعة في هذا التقرير لضمان خلوها بنسبة 100% من الأرقام العربية المشرقية (Unicode U+0660 to U+0669) لتجنب تكرار المخالفة التي رصدها المراجع في `FINAL_AUDIT.md`.

---

## 2. فهرس بوابات العبور المستخرجة للمراحل 2 و 3 و 4 و 5 (Extracted Gates Catalog)

### 2.1 بوابات المرحلة 2: قاعدة بيانات PostgreSQL المحلية والنزاهة المالية (6 بوابات)

| معرف البوابة | اسم البوابة | الهدف المعماري | أمر التحقق الإلزامي | شرط العبور (`PASS Criteria`) |
|:---|:---|:---|:---|:---|
| **Gate 2.1** | تهيئة قاعدة بيانات `smartpower_db` والمستخدم المحلي | إنشاء قاعدة بيانات محلية مخصصة للإنتاج على المنفذ 5432 | `psql -U postgres -h localhost -p 5432 -d smartpower_db -c "SELECT current_database(), current_user, inet_server_port();"` | الاتصال بقاعدة `smartpower_db` على المنفذ 5432 والمستخدم `postgres` برمز خروج 0 |
| **Gate 2.2** | نشر المخطط المتين والجداول الأساسية والقيود | إنشاء جداول النظام الـ 14 الأساسية مع الفهارس والمفاتيح الأجنبية | `psql -U postgres -h localhost -p 5432 -d smartpower_db -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;"` | وجود جميع الجداول الـ 14 كاملة بنسبة 100% (`COUNT(*) >= 14`) |
| **Gate 2.3** | قيد تصاعد القراءات الصارم (Non-Monotonic Reading Guard) | منع تسجيل أي قراءة أقل من القراءة السابقة على مستوى قيود DB | `psql -U postgres -h localhost -p 5432 -d smartpower_db -f "d:\elctercity\database\tests\test_monotonic_guard.sql"` | إطلاق استثناء قطعي من قاعدة البيانات ورفض المعاملة وتراجعها عند محاولة إدخال قراءة متناقصة (مع استثناء تصفير العداد المعتمد) |
| **Gate 2.4** | محرك توزيع السداد المائي FIFO الذري مع القفل المتشائم `FOR UPDATE` | سداد الفواتير الأقدم فالأحدث بنمط تسلسلي آمن وتخزين الفائض في `customer_credits` | `psql -U postgres -h localhost -p 5432 -d smartpower_db -f "d:\elctercity\database\tests\test_waterfall_allocation.sql"` | توزيع المبلغ بدقة رياضية 100% مع قفل الصفوف المتشائم وفرض الترتيب القطعي `ORDER BY customer_id ASC` لمنع Deadlocks |
| **Gate 2.5** | الترقيم الحتمي المركب للفواتير | فرض صيغة الترقيم `INV-[Cycle]-[SubscriberNumber]` | `psql -U postgres -h localhost -p 5432 -d smartpower_db -c "SELECT id, invoice_number, billing_cycle, customer_id FROM invoices LIMIT 5;"` | مطابقة أرقام الفواتير للتعبير النمطي الحتمي وانعدام المعرفات العشوائية |
| **Gate 2.6** | محرك الحساب الرجعي التتابعي التلقائي (Retroactive Recalculation) | تعديل قراءة سابقة في دورة ما وتحديث الأرصدة والمتأخرات في الدورات اللاحقة ذرياً | `psql -U postgres -h localhost -p 5432 -d smartpower_db -f "d:\elctercity\database\tests\test_retroactive_recalc.sql"` | تحديث متأخرات الدورات $T+1$ إلى $N$ في معاملة ذرية واحدة بصفر فروقات تقريب مالي |

---

### 2.2 بوابات المرحلة 3: خادم Go المستقل ومحرك الواتساب (7 بوابات)

| معرف البوابة | اسم البوابة | الهدف المعماري | أمر التحقق الإلزامي | شرط العبور (`PASS Criteria`) |
|:---|:---|:---|:---|:---|
| **Gate 3.1** | بناء مشروع Go وتجميعه النقي (`CGO_ENABLED=0`) | تجميع ملف تنفيذي مستقل `server.exe` بحجم < 25MB وبدون SQLite | `cd go_backend; $env:CGO_ENABLED="0"; go build -ldflags="-s -w" -trimpath -o "..\server.exe" .` | نجاح التجميع وحجم الملف التنفيذي أقل من 25MB قطيعاً وخالٍ من ارتباطات Cgo |
| **Gate 3.2** | مطابقة عقود واجهات الـ REST API الـ 14 والـ 54 نقطة نهاية | استجابة خادم Go Fiber لكافة مسارات الـ API بهياكل JSON مطابقة للواجهة | `cd go_backend; go test -v ./tests/api/...` | اجتياز 100% من اختبارات نقاط النهاية (54 نقطة عبر 14 مجموعة مسارات) برمز خروج 0 |
| **Gate 3.3** | محرك الواتساب `whatsmeow` مع تخزين الجلسات في PostgreSQL | تشغيل محرك الواتساب وتخزين مفاتيح الجلسة في PostgreSQL دون ملفات خارجية | `cd go_backend; go test -v ./whatsapp/store_test.go` | نجاح تخزين واسترجاع بيانات الجلسة والمفاتيح المشفرة مباشرة من جدول DB محلي |
| **Gate 3.4** | طابور الرسائل المحلي المحدد زمنياً (Rate Limiter) | فرض تأخير آمن بين 8 إلى 15 ثانية بين كل رسالة واتساب وأخرى لحماية الرقم من الحظر | `cd go_backend; go test -v ./whatsapp/queue_rate_limit_test.go` | قياس الفاصل الزمني بين الرسائل والتأكد من أنه يقع بين 8 و 15 ثانية باستمرار |
| **Gate 3.5** | محرك تصوير الفواتير A5 عبر `chromedp` والخطوط العربية | توليد PDF و PNG لفاتورة A5 ذات الكعب المزدوج عبر Edge Headless | `cd go_backend; go test -v ./chromedp/invoice_render_test.go` | إنتاج ملف PDF سليم (> 15KB) وصورة PNG بأبعاد 1748x1240 مع سلامة تشكيل الحروف العربية بنسبة 100% |
| **Gate 3.6** | محرك الإكسل المتدفق `excelize/v2` | تصدير واستيراد كشوفات القراءات بسرعة فائقة وذاكرة منخفضة | `cd go_backend; go test -v ./excel/excel_benchmark_test.go` | تصدير 5,000 صف في أقل من ثانية، واستهلاك ذاكرة RAM < 20MB، وتفعيل اتجاه RTL |
| **Gate 3.7** | تجميع الواجهة `frontend/dist` داخل `server.exe` عبر `//go:embed` | تشغيل التطبيق ككتلة واحدة وتقديم واجهة React عند طلب المنفذ 3000 | تشغيل `server.exe` في الخلفية واستدعاء `http://localhost:3000` و `/api/health` | استجابة الجذر بـ HTTP 200 واحتواء HTML على `<div id="root">` واستجابة API في < 0.1 ثانية |

---

### 2.3 بوابات المرحلة 4: صقل واجهة React Desktop وفك الارتباط التام (5 بوابات)

| معرف البوابة | اسم البوابة | الهدف المعماري | أمر التحقق الإلزامي | شرط العبور (`PASS Criteria`) |
|:---|:---|:---|:---|:---|
| **Gate 4.1** | التطهير الشامل والاستئصال الكامل لاستدعاءات Supabase | التأكد من خلو كود الواجهة في `frontend/src/` من أي اعتمادية على سوبابيز | `Select-String -Path frontend/src/**/*.ts,frontend/src/**/*.tsx -Pattern "supabase|getSupabase|@supabase"` | العثور على 0 تكرار (صفر استدعاءات أو مكتبات لسوبابيز) |
| **Gate 4.2** | ربط الواجهة الأمامية محلياً 100% بخادم Go على `/api` | توجيه كافة استدعاءات الخدمات في الواجهة إلى المسارات النسبية المحلية `/api/...` | `node frontend/src/tests/test_api_endpoints_coverage.js` | ربط كافة الخدمات الـ 12 ونقاط النهاية الـ 54 محلياً بنسبة 100% وصفر نقاط خارجية |
| **Gate 4.3** | المطابقة البصرية والطباعية لنموذج الفاتورة A5 المزدوجة | الحفاظ على تصميم الفاتورة المطابق للصورة الرسمية المعتمدة | `node frontend/src/tests/test_challenger_layout_2.js` | اجتياز 106 اختبارات تصميم وتنسيق بنسبة 100% (106 passed, 0 failed) |
| **Gate 4.4** | التطبيق الشامل للأرقام الإنجليزية وقمع أسهم المتصفح | ضمان ظهور الأرقام الإنجليزية (0-9) حصراً ومنع الأسهم في كافة الحقول | `node frontend/src/tests/test_numerals_scan.js` | صفر أرقام مشرقية، وصفر حقول `type=number` بدون ضوابط |
| **Gate 4.5** | اجتياز بناء الإنتاج للواجهة وتحديث حزمة `dist/` | توليد حزمة الإنتاج النظيفة المجهزة للتضمين في Go | `cd frontend; npm run build` | انتهاء البناء برمز خروج 0 وتحديث مجلد `frontend/dist/` دون أخطاء TypeScript |

---

### 2.4 بوابات المرحلة 5: التعافي من الكوارث، التحصين، والتدقيق الختامي (5 بوابات)

| معرف البوابة | اسم البوابة | الهدف المعماري | أمر التحقق الإلزامي | شرط العبور (`PASS Criteria`) |
|:---|:---|:---|:---|:---|
| **Gate 5.1** | النسخ الاحتياطي الآلي اليومي عبر `pg_dump -Fc` واحتساب SHA-256 | تشغيل أمر النسخ المخصص وضغط البيانات والتحقق من سلامة الملف | `server.exe --backup-now; Get-FileHash backups/*.dump -Algorithm SHA256` | توليد ملف dump صالح ومضغوط وحجمه سليم واحتساب تجزئة SHA-256 بنجاح |
| **Gate 5.2** | الرصد التلقائي لأقراص USB عبر Win32 API ومطابقة المرآة | رصد الفلاش ميموري ونسخ ملف النسخة الاحتياطية ومطابقة التجزئة والتراجع الهادئ عند الغياب | `cd go_backend; go test -v ./backup/usb_mirror_test.go` | نجاح رصد محركات الأقراص القابلة للإزالة ومطابقة تجزئة SHA-256 بين القرص المحلي والفلاش 100% |
| **Gate 5.3** | اختبار التعافي من الانهيار المفاجئ (Cold-Boot & Crash Recovery) | محاكاة انقطاع مفاجئ للتيار واستعادة الرسائل العالقة في طابور الواتساب عند الإقلاع البارد | `cd go_backend; go test -v ./services/crash_recovery_test.go` | إعادة ضبط كافة الرسائل العالقة بحالة `PROCESSING` إلى `PENDING` في زمن أقل من 0.1 ثانية |
| **Gate 5.4** | اختبارات الإجهاد والتزامن المالي (Financial Concurrency Stress) | تشغيل 50 عملية سداد وقراءة متزامنة لنفس المشترك للتحقق من صرامة القفل المتشائم | `cd go_backend; go test -v ./tests/stress/concurrency_test.go` | انعدام التضارب بنسبة 100%، ومطابقة الأرصدة التامة، وصفر فروقات تقريب مالي |
| **Gate 5.5** | التدقيق الختامي المستقل وإصدار القرار في `FINAL_AUDIT.md` | مراجعة شاملة ومستقلة لكافة بنود التدقيق الـ 12 وإصدار القرار القطعي | `Get-Content MIGRATION/FINAL_AUDIT.md -Tail 20` | صدور القرار النهائي الصريح `# FINAL AUDIT VERDICT: READY` |

---

## 3. المحتوى الدقيق المجهز للإدراج في `MIGRATION/EXECUTION_LOG.md` (Exact Remediation Content)

فيما يلي النص الكامل والجاهز للاستبدال المباشر للأسطر 192-218 في ملف `d:\elctercity\MIGRATION\EXECUTION_LOG.md`، لتحويل المراحل من 2 إلى 5 من مجرد أسطر نائبة فارغة إلى مراحل متكاملة ومحصنة بجميع بوابات العبور:

```markdown
# PHASE 2: قاعدة بيانات PostgreSQL المحلية والنزاهة المالية (Local PostgreSQL & Financial Integrity Core)

- **الحالة (Status)**: `PLANNED`
- **الوكيل المستهدف (Target Agent)**: `worker_m2_database` (Local PostgreSQL & Financial Logic Implementer)
- **الهدف**: تهيئة قاعدة بيانات `smartpower_db` على المنفذ 5432، ونشر المخطط المتين المكون من 14 جدولاً، وفرض قيد تصاعد العدادات الصارم مع معالجة تصفير العداد، وتفعيل محرك التوزيع المائي FIFO الذري بالقفل المتشائم `FOR UPDATE` وترتيب المعرفات القطعي، وتوليد الترقيم الحتمي `INV-[Cycle]-[SubscriberNumber]`، وتشغيل محرك الحساب الرجعي التتابعي بصفر فروقات تقريب.

## 1. الشروط المسبقة (Pre-conditions)
- [x] اجتياز المرحلة 1 بالكامل والحصول على راية `[GATE_STATUS: PASS]` المعتمدة.
- [ ] توفر خادم PostgreSQL 18.6 المحلي قيد التشغيل على المنفذ 5432.
- [ ] توفر صلاحيات المدير للمستخدم `postgres` محلياً.

## 2. مصفوفة بوابات العبور المخططة للمرحلة 2 (Phase 2 Gate Matrix)
| معرف البوابة | معيار الفحص المستهدف | أمر التحقق الإلزامي | النتيجة المتوقعة | الحالة المبدئية |
|:---|:---|:---|:---|:---:|
| Gate 2.1 | تهيئة قاعدة بيانات `smartpower_db` والمستخدم المحلي | `& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -c "SELECT current_database(), current_user, inet_server_port();" -d smartpower_db` | الاتصال الناجح بقاعدة `smartpower_db` على المنفذ 5432 | `PLANNED` |
| Gate 2.2 | نشر المخطط المتين والجداول الأساسية الـ 14 والقيود | `& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -d smartpower_db -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;"` | وجود جميع الجداول الـ 14 كاملة بنسبة 100% | `PLANNED` |
| Gate 2.3 | قيد تصاعد القراءات الصارم (Non-Monotonic Guard) | `& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -d smartpower_db -f "d:\elctercity\database\tests\test_monotonic_guard.sql"` | رفض القراءة المتناقصة باستثناء قطعي وتراجع المعاملة بنجاح | `PLANNED` |
| Gate 2.4 | محرك توزيع السداد المائي FIFO الذري مع القفل المتشائم | `& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -d smartpower_db -f "d:\elctercity\database\tests\test_waterfall_allocation.sql"` | تسوية الفواتير القديمة أولاً وإيداع الفائض في الأرصدة الدائنة | `PLANNED` |
| Gate 2.5 | الترقيم الحتمي المركب للفواتير | `& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -d smartpower_db -c "SELECT id, invoice_number, billing_cycle, customer_id FROM invoices LIMIT 5;"` | مطابقة أرقام الفواتير لنمط `INV-[Cycle]-[SubscriberNumber]` | `PLANNED` |
| Gate 2.6 | محرك الحساب الرجعي التتابعي التلقائي (T -> N) | `& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -d smartpower_db -f "d:\elctercity\database\tests\test_retroactive_recalc.sql"` | تحديث كافة الأرصدة والمتأخرات في الدورات اللاحقة ذرياً | `PLANNED` |

## 3. المواصفات التفصيلية لبوابات المرحلة 2 (Detailed Gate Specifications)

#### البوابة Gate 2.1: تهيئة قاعدة بيانات `smartpower_db` والمستخدم المحلي
- **الهدف المعماري**: إنشاء قاعدة بيانات مخصصة ومستقلة على الخادم المحلي.
- **أمر التحقق (Command)**:
  ```powershell
  & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -c "SELECT current_database(), current_user, inet_server_port();" -d smartpower_db
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
   current_database | current_user | inet_server_port 
  ------------------+--------------+------------------
   smartpower_db    | postgres     |             5432
  (1 row)
  ```
- **معيار النجاح (`PASS`)**: رمز خروج 0 والاتصال المؤكد بقاعدة البيانات المستهدفة.

#### البوابة Gate 2.2: نشر المخطط المتين والجداول الأساسية والقيود
- **الهدف المعماري**: إنشاء الـ 14 جدولاً الأساسية مع الفهارس والمفاتيح الأجنبية: `audit_logs`, `collector_customer_assignments`, `customer_credits`, `customers`, `invoices`, `meter_readings`, `payment_allocations`, `payment_receipt_counters`, `payments`, `shifts`, `subscription_plans`, `system_settings`, `users`, `whatsapp_queue_messages`.
- **أمر التحقق (Command)**:
  ```powershell
  & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -d smartpower_db -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;"
  ```
- **المخرجات المتوقعة (Expected Output)**: ظهور قائمة الجداول الـ 14 كاملة بدون نقصان.
- **معيار النجاح (`PASS`)**: عدد الجداول لا يقل عن 14 جدولاً منشأة بنجاح.

#### البوابة Gate 2.3: قيد تصاعد القراءات الصارم (Non-Monotonic Reading Guard)
- **الهدف المعماري**: إثبات رفض أي قراءة عداد أقل من القراءة السابقة عبر قيود قاعدة البيانات الصريحة لمنع التلاعب بالقراءات، مع استثناء تصفير العداد المعتمد (`is_meter_reset = true`).
- **أمر التحقق (Command)**:
  ```powershell
  & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -d smartpower_db -f "d:\elctercity\database\tests\test_monotonic_guard.sql"
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
  ERROR:  New reading value (140) cannot be less than previous reading (150)
  CONTEXT:  PL/pgSQL function rpc_submit_meter_reading ...
  TEST RESULT: NON_MONOTONIC_REJECTED_SUCCESSFULLY
  ```
- **معيار النجاح (`PASS`)**: صدور استثناء صريح وتراجع المعاملة ومنع تسجيل القراءة المخالفة.

#### البوابة Gate 2.4: محرك توزيع السداد المائي FIFO الذري مع القفل المتشائم `FOR UPDATE`
- **الهدف المعماري**: سداد الفواتير الأقدم أولاً وتوزيع المبلغ ذرياً مع قفل الصفوف المتشائم `FOR UPDATE` وترتيب المعرفات القطعي (`ORDER BY customer_id ASC`) لتفادي مشاكل Deadlocks وحفظ الفائض في `customer_credits`.
- **أمر التحقق (Command)**:
  ```powershell
  & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -d smartpower_db -f "d:\elctercity\database\tests\test_waterfall_allocation.sql"
  ```
- **المخرجات المتوقعة (Expected Output)**: سداد الفاتورة القديمة بالكامل، وتقسيط الفاتورة اللاحقة، وتحويل الفائض لحساب المشترك الدائن بدقة رياضية 100%.
- **معيار النجاح (`PASS`)**: مطابقة التوزيع المالي بنسبة 100% وانعدام أي فروقات تقريب مالي.

#### البوابة Gate 2.5: الترقيم الحتمي المركب للفواتير
- **الهدف المعماري**: تطبيق صيغة الترقيم المركبة `INV-[Cycle]-[SubscriberNumber]` لمنع تضارب الفواتير.
- **أمر التحقق (Command)**:
  ```powershell
  & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -d smartpower_db -c "SELECT id, invoice_number, billing_cycle, customer_id FROM invoices LIMIT 5;"
  ```
- **المخرجات المتوقعة (Expected Output)**: ظهور أرقام فواتير مطابقة للنمط `INV-YYYY_MM-[CustomerNumber]`.
- **معيار النجاح (`PASS`)**: مطابقة كافة أرقام الفواتير للنمط المركب الحتمي 100%.

#### البوابة Gate 2.6: محرك الحساب الرجعي التتابعي التلقائي (Retroactive Recalculation)
- **الهدف المعماري**: تعديل قراءة دورة سابقة وتحديث الأرصدة والمتأخرات في كافة الدورات اللاحقة ذرياً.
- **أمر التحقق (Command)**:
  ```powershell
  & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -d smartpower_db -f "d:\elctercity\database\tests\test_retroactive_recalc.sql"
  ```
- **المخرجات المتوقعة (Expected Output)**: ظهور النتيجة `RECALCULATION_CASCADE_VERIFIED_PASS`.
- **معيار النجاح (`PASS`)**: تحديث الأرصدة التراكمية في كافة الدورات اللاحقة بدقة محاسبية تامة.

## 4. قرار بوابة المرحلة 2 (Phase 2 Gate Decision)
- **القرار النهائي**: `[GATE_STATUS: PLANNED]`

---

# PHASE 3: خادم Go المستقل ومحرك الواتساب (Standalone Go Backend & WhatsApp Engine)

- **الحالة (Status)**: `PLANNED`
- **الوكيل المستهدف (Target Agent)**: `worker_m3_gobackend` (Go Fiber Backend & WhatsApp Implementer)
- **الهدف**: تجميع ملف تنفيذي نقي `server.exe` بدون Cgo (`CGO_ENABLED=0`) بحجم < 25MB واستهلاك RAM < 35MB، واستيفاء كافة مسارات الـ REST API الـ 14، ومحرك `whatsmeow` المتصل مباشرة بـ PostgreSQL، وطابور رسائل الواتساب مع تأخير 8-15 ثانية، ومحرك تصوير الفاتورة A5 المزدوجة عبر `chromedp`، ومحرك الإكسل المتدفق `excelize/v2` مع RTL، وتضمين واجهة React المكتملة عبر `//go:embed`.

## 1. الشروط المسبقة (Pre-conditions)
- [ ] اجتياز المرحلة 2 بالكامل والحصول على راية `[GATE_STATUS: PASS]`.
- [ ] توفر بيئة تجميع Go 1.27 على نظام التشغيل Windows x64.
- [ ] جاهزية حزمة الواجهة المبنية `frontend/dist/`.

## 2. مصفوفة بوابات العبور المخططة للمرحلة 3 (Phase 3 Gate Matrix)
| معرف البوابة | معيار الفحص المستهدف | أمر التحقق الإلزامي | النتيجة المتوقعة | الحالة المبدئية |
|:---|:---|:---|:---|:---:|
| Gate 3.1 | تجميع Go النقي المستقل (`CGO_ENABLED=0`) | `cd go_backend; $env:CGO_ENABLED="0"; go build -ldflags="-s -w" -trimpath -o "..\server.exe" .` | نجاح التجميع وحجم `server.exe` < 25MB | `PLANNED` |
| Gate 3.2 | تغطية ومطابقة مسارات الـ REST API الـ 14 والـ 54 نقطة نهاية | `cd go_backend; go test -v ./tests/api/...` | اجتياز 100% من اختبارات المسارات برمز خروج 0 | `PLANNED` |
| Gate 3.3 | محرك الواتساب `whatsmeow` مع تخزين الجلسات في PostgreSQL | `cd go_backend; go test -v ./whatsapp/store_test.go` | نجاح الاتصال وتخزين واسترجاع الجلسة في PostgreSQL | `PLANNED` |
| Gate 3.4 | طابور الرسائل المحلي المحدد زمنياً (تأخير 8-15 ثانية) | `cd go_backend; go test -v ./whatsapp/queue_rate_limit_test.go` | تأخير زمني بين الرسائل $\ge 8$ ثوانٍ و $\le 15$ ثانية | `PLANNED` |
| Gate 3.5 | محرك تصوير الفواتير A5 عبر `chromedp` والخطوط العربية | `cd go_backend; go test -v ./chromedp/invoice_render_test.go` | توليد PDF و PNG بأبعاد صحيحة وتشكيل عربي نقي 100% | `PLANNED` |
| Gate 3.6 | محرك الإكسل المتدفق `excelize/v2` باستهلاك ذاكرة منخفض | `cd go_backend; go test -v ./excel/excel_benchmark_test.go` | تصدير 5,000 صف في < 1 ثانية واستهلاك RAM < 20MB | `PLANNED` |
| Gate 3.7 | تضمين الواجهة في `server.exe` والتقديم في < 0.1 ثانية | تشغيل `server.exe` وطلب `http://localhost:3000` و `/api/health` | استجابة HTTP 200 وتقديم React SPA في أقل من 0.1 ثانية | `PLANNED` |

## 3. المواصفات التفصيلية لبوابات المرحلة 3 (Detailed Gate Specifications)

#### البوابة Gate 3.1: بناء مشروع Go وتجميعه النقي بنسبة 100% (`CGO_ENABLED=0`)
- **الهدف المعماري**: إنتاج ملف تنفيذي مستقل بالكامل بدون أي اعتمادية على مكتبات C أو SQLite خارجية بحجم أقل من 25MB.
- **أمر التحقق (Command)**:
  ```powershell
  Push-Location "d:\elctercity\go_backend"
  $env:CGO_ENABLED="0"; $env:GOOS="windows"; $env:GOARCH="amd64"
  & "C:\Program Files\Go\bin\go.exe" build -ldflags="-s -w" -trimpath -o "..\server.exe" .
  $bSuccess = ($LASTEXITCODE -eq 0); Pop-Location
  $f = Get-Item "d:\elctercity\server.exe"
  [PSCustomObject]@{ BuildSuccess = $bSuccess; SizeMB = [math]::Round($f.Length / 1MB, 2) } | Format-List
  ```
- **المخرجات المتوقعة (Expected Output)**: `BuildSuccess : True`, `SizeMB : [14.0 - 22.0]`.
- **معيار النجاح (`PASS`)**: نجاح التجميع وحجم الملف أقل قطيعاً من 25MB.

#### البوابة Gate 3.2: مطابقة عقود واجهات الـ REST API الـ 14 والـ 54 نقطة نهاية
- **الهدف المعماري**: ضمان توافق خادم Go Fiber مع كافة نقاط النهاية المستخدمة في الواجهة الأمامية بنفس هياكل JSON.
- **أمر التحقق (Command)**:
  ```powershell
  Push-Location "d:\elctercity\go_backend"
  & "C:\Program Files\Go\bin\go.exe" test -v ./tests/api/...
  Pop-Location
  ```
- **المخرجات المتوقعة (Expected Output)**: ظهور علامة `PASS` لجميع مجموعات المسارات برمز خروج 0.
- **معيار النجاح (`PASS`)**: اجتياز 100% من اختبارات الـ API.

#### البوابة Gate 3.3: محرك الواتساب `whatsmeow` مع تخزين الجلسات في PostgreSQL
- **الهدف المعماري**: تشغيل مكتبة `whatsmeow` باستخدام مخزن جلسات مكتوب بلغة Go الصرفة يتصل بـ PostgreSQL بدون SQLite.
- **أمر التحقق (Command)**:
  ```powershell
  Push-Location "d:\elctercity\go_backend"
  & "C:\Program Files\Go\bin\go.exe" test -v ./whatsapp/store_test.go
  Pop-Location
  ```
- **المخرجات المتوقعة (Expected Output)**: `=== RUN TestPostgresSessionStore ... PASS`.
- **معيار النجاح (`PASS`)**: نجاح اختبارات التخزين والاسترجاع بنسبة 100%.

#### البوابة Gate 3.4: طابور الرسائل المحلي المحدد زمنياً (Rate Limiter)
- **الهدف المعماري**: حماية رقم هاتف محطة الكهرباء من الحظر عبر فرض تأخير يتراوح بين 8 إلى 15 ثانية بين كل رسالة وأخرى.
- **أمر التحقق (Command)**:
  ```powershell
  Push-Location "d:\elctercity\go_backend"
  & "C:\Program Files\Go\bin\go.exe" test -v ./whatsapp/queue_rate_limit_test.go
  Pop-Location
  ```
- **المخرجات المتوقعة (Expected Output)**: تسجيل فواصل إرسال تقع بين 8 و 15 ثانية.
- **معيار النجاح (`PASS`)**: ثبوت الالتزام بالمدى الزمني المحدد وعدم الإرسال العشوائي المتزامن.

#### البوابة Gate 3.5: محرك تصوير الفواتير A5 عبر `chromedp` والخطوط العربية
- **الهدف المعماري**: توليد الفاتورة A5 ذات الكعب المزدوج عبر متصفح النظام Headless بدقة طباعة 300 DPI وتشبيك الحروف العربية السليم.
- **أمر التحقق (Command)**:
  ```powershell
  Push-Location "d:\elctercity\go_backend"
  & "C:\Program Files\Go\bin\go.exe" test -v ./chromedp/invoice_render_test.go
  Pop-Location
  ```
- **المخرجات المتوقعة (Expected Output)**: توليد ملف PDF سليم (> 15KB) وصورة PNG سليمة الأبعاد.
- **معيار النجاح (`PASS`)**: اجتياز الاختبار وتوليد الملفات دون أي تشويه للأحرف العربية.

#### البوابة Gate 3.6: محرك الإكسل المتدفق `excelize/v2`
- **الهدف المعماري**: استيراد وتصدير كشوفات القراءات الكبيرة مع ضبط خاصية RTL التلقائية وذاكرة منخفضة < 20MB.
- **أمر التحقق (Command)**:
  ```powershell
  Push-Location "d:\elctercity\go_backend"
  & "C:\Program Files\Go\bin\go.exe" test -v ./excel/excel_benchmark_test.go
  Pop-Location
  ```
- **المخرجات المتوقعة (Expected Output)**: تصدير 5,000 صف في أقل من 1 ثانية واستهلاك ذاكرة < 20MB وتأكيد RTL.
- **معيار النجاح (`PASS`)**: اجتياز اختبار الأداء ومطابقة الذاكرة وخصائص الاتجاه.

#### البوابة Gate 3.7: تجميع الواجهة `frontend/dist` داخل `server.exe` عبر `//go:embed`
- **الهدف المعماري**: تقديم واجهة React Desktop فورياً وبشكل محلي متكامل من داخل الملف التنفيذي نفسه.
- **أمر التحقق (Command)**:
  ```powershell
  $job = Start-Process -FilePath "d:\elctercity\server.exe" -PassThru
  Start-Sleep -Milliseconds 500
  $resp = Invoke-WebRequest -Uri "http://localhost:3000" -UseBasicParsing
  $apiResp = Invoke-WebRequest -Uri "http://localhost:3000/api/health" -UseBasicParsing
  Stop-Process -Id $job.Id -Force
  [PSCustomObject]@{ RootStatus = $resp.StatusCode; HasReactRoot = $resp.Content.Contains('<div id="root">'); ApiStatus = $apiResp.StatusCode } | Format-List
  ```
- **المخرجات المتوقعة (Expected Output)**: `RootStatus : 200`, `HasReactRoot : True`, `ApiStatus : 200`.
- **معيار النجاح (`PASS`)**: عمل التطبيق المستقل وتقديم ملفات الواجهة والـ API بنجاح.

## 4. قرار بوابة المرحلة 3 (Phase 3 Gate Decision)
- **القرار النهائي**: `[GATE_STATUS: PLANNED]`

---

# PHASE 4: صقل واجهة React Desktop وفك الارتباط التام (React Desktop UI Polish & Decoupling)

- **الحالة (Status)**: `PLANNED`
- **الوكيل المستهدف (Target Agent)**: `worker_m4_frontend` (React Desktop Modernization & Polish Implementer)
- **الهدف**: استئصال كافة بقايا واستدعاءات Supabase نهائياً، وربط كافة خدمات الواجهة محلياً 100% بمسارات خادم Go على المسار `/api`، وتثبيت وتأكيد مطابقة نموذج الفاتورة الرسمي A5 ذي الكعب المزدوج، وفرض الأرقام الإنجليزية (0-9) وقمع أسهم المتصفح بنسبة 100%، واجتياز بناء الإنتاج النظيف.

## 1. الشروط المسبقة (Pre-conditions)
- [ ] اجتياز المرحلة 3 بالكامل والحصول على راية `[GATE_STATUS: PASS]`.
- [ ] جاهزية خادم Go واستجابته لمسارات `/api/...`.

## 2. مصفوفة بوابات العبور المخططة للمرحلة 4 (Phase 4 Gate Matrix)
| معرف البوابة | معيار الفحص المستهدف | أمر التحقق الإلزامي | النتيجة المتوقعة | الحالة المبدئية |
|:---|:---|:---|:---|:---:|
| Gate 4.1 | التطهير الشامل والاستئصال الكامل لاستدعاءات Supabase | `Select-String -Path frontend/src/**/*.ts,frontend/src/**/*.tsx -Pattern "supabase|getSupabase|@supabase"` | النتيجة 0 (خلو كود الواجهة التام من سوبابيز) | `PLANNED` |
| Gate 4.2 | ربط الواجهة الأمامية محلياً 100% بخادم Go على `/api` | `node frontend/src/tests/test_api_endpoints_coverage.js` | ربط كافة الخدمات الـ 12 والنقاط الـ 54 محلياً | `PLANNED` |
| Gate 4.3 | المطابقة البصرية لنموذج الفاتورة A5 المزدوجة | `node frontend/src/tests/test_challenger_layout_2.js` | اجتياز 106 اختبارات بنسبة 100% | `PLANNED` |
| Gate 4.4 | التطبيق الشامل للأرقام الإنجليزية وقمع أسهم المتصفح | `node frontend/src/tests/test_numerals_scan.js` | صفر أرقام مشرقية وصفر حقول `type=number` بدون ضوابط | `PLANNED` |
| Gate 4.5 | اجتياز بناء الإنتاج للواجهة وتحديث حزمة `dist/` | `cd frontend; npm run build` | انتهاء البناء بنجاح برمز خروج 0 | `PLANNED` |

## 3. المواصفات التفصيلية لبوابات المرحلة 4 (Detailed Gate Specifications)

#### البوابة Gate 4.1: التطهير الشامل والاستئصال الكامل لكافة استدعاءات Supabase
- **الهدف المعماري**: ضمان تحول النظام إلى نظام محلي مستقل بنسبة 100% خلوه من أي اتصالات سحابية قديمة.
- **أمر التحقق (Command)**:
  ```powershell
  $res = Select-String -Path "d:\elctercity\frontend\src\**\*.ts","d:\elctercity\frontend\src\**\*.tsx" -Pattern "supabase|getSupabase|@supabase" -SimpleMatch
  [PSCustomObject]@{ SupabaseOccurrences = @($res).Count } | Format-List
  ```
- **المخرجات المتوقعة (Expected Output)**: `SupabaseOccurrences : 0`.
- **معيار النجاح (`PASS`)**: خلو كامل كود الفرونت إند من أي أثر لسوبابيز.

#### البوابة Gate 4.2: ربط الواجهة الأمامية محلياً 100% بخادم Go REST API على المسار `/api`
- **الهدف المعماري**: التأكد من أن جميع طبقات البيانات والخدمات تستدعي واجهات Go المحلية حصراً.
- **أمر التحقق (Command)**:
  ```powershell
  node "d:\elctercity\frontend\src\tests\test_api_endpoints_coverage.js"
  ```
- **المخرجات المتوقعة (Expected Output)**: فحص 12 خدمة، وربط 54 نقطة نهاية محلياً، وظهور نتيجة `ALL_ENDPOINTS_LOCALLY_BOUND_PASS`.
- **معيار النجاح (`PASS`)**: تغطية 100% بدون أي نقطة نهاية مفصولة.

#### البوابة Gate 4.3: المطابقة البصرية الصارمة لنموذج الفاتورة A5 المزدوجة
- **الهدف المعماري**: ضمان التطابق الدقيق مع تصميم الفاتورة ذي الكعب المزدوج المعتمد من `photo_5769554780358381104_y.jpg`.
- **أمر التحقق (Command)**:
  ```powershell
  node "d:\elctercity\frontend\src\tests\test_challenger_layout_2.js"
  ```
- **المخرجات المتوقعة (Expected Output)**: `TOTAL TESTS: 106 | PASSED: 106 | FAILED: 0`.
- **معيار النجاح (`PASS`)**: اجتياز 100% من اختبارات الفاتورة.

#### البوابة Gate 4.4: التطبيق الشامل للأرقام الإنجليزية (0-9) وقمع أسهم المتصفح
- **الهدف المعماري**: فرض الأرقام الإنجليزية في كافة شاشات ومكونات الواجهة وتفعيل محول الأرقام الفوري `toEnglishDigits`.
- **أمر التحقق (Command)**:
  ```powershell
  node "d:\elctercity\frontend\src\tests\test_numerals_scan.js"
  ```
- **المخرجات المتوقعة (Expected Output)**: `Eastern Arabic Numerals Count: 0, Invalid type=number Inputs: 0`.
- **معيار النجاح (`PASS`)**: خلو النظام التام من الأرقام المشرقية في الواجهة.

#### البوابة Gate 4.5: اجتياز بناء الإنتاج للواجهة وتحديث حزمة `dist/`
- **الهدف المعماري**: توليد حزمة الإنتاج الخالية من الأخطاء والجاهزة للتضمين النهائي في خادم Go.
- **أمر التحقق (Command)**:
  ```powershell
  Push-Location "d:\elctercity\frontend"
  npm run build
  $bSuccess = ($LASTEXITCODE -eq 0)
  Pop-Location
  [PSCustomObject]@{ BuildSuccess = $bSuccess } | Format-List
  ```
- **المخرجات المتوقعة (Expected Output)**: `BuildSuccess : True`.
- **معيار النجاح (`PASS`)**: اكتمال أمر البناء برمز خروج 0 بدون أخطاء.

## 4. قرار بوابة المرحلة 4 (Phase 4 Gate Decision)
- **القرار النهائي**: `[GATE_STATUS: PLANNED]`

---

# PHASE 5: التعافي من الكوارث، التحصين، والتدقيق الختامي (Disaster Recovery, Hardening & Independent Audit)

- **الحالة (Status)**: `PLANNED`
- **الوكيل المستهدف (Target Agent)**: `worker_m5_hardening` (Disaster Recovery, Hardening & Final Audit Coordinator)
- **الهدف**: تفعيل النسخ الاحتياطي اليومي الآلي المضغوط `pg_dump -Fc` مع التشفير وتجزئة SHA-256، والرصد التلقائي لأقراص USB عبر Win32 API والنسخ المطابق، واختبارات الإقلاع البارد والتعافي من الانهيار المفاجئ في < 0.1 ثانية، واختبارات الإجهاد والتزامن المالي، واكتمال التدقيق الختامي المستقل في `MIGRATION/FINAL_AUDIT.md` بقرار `READY`.

## 1. الشروط المسبقة (Pre-conditions)
- [ ] اجتياز المرحلة 4 بالكامل والحصول على راية `[GATE_STATUS: PASS]`.
- [ ] توفر الملف التنفيذي النهائي المكتمل `server.exe` وقاعدة البيانات المهيأة.

## 2. مصفوفة بوابات العبور المخططة للمرحلة 5 (Phase 5 Gate Matrix)
| معرف البوابة | معيار الفحص المستهدف | أمر التحقق الإلزامي | النتيجة المتوقعة | الحالة المبدئية |
|:---|:---|:---|:---|:---:|
| Gate 5.1 | النسخ الاحتياطي الآلي اليومي عبر `pg_dump -Fc` واحتساب SHA-256 | `& "d:\elctercity\server.exe" --backup-now; Get-FileHash backups/*.dump -Algorithm SHA256` | توليد ملف dump صالح واحتساب تجزئة SHA-256 بنجاح | `PLANNED` |
| Gate 5.2 | الرصد التلقائي لأقراص USB عبر Win32 API ومطابقة المرآة | `cd go_backend; go test -v ./backup/usb_mirror_test.go` | رصد الفلاش ميموري ومطابقة تجزئة SHA-256 بنسبة 100% | `PLANNED` |
| Gate 5.3 | اختبار التعافي من الانهيار المفاجئ (Cold-Boot Recovery) | `cd go_backend; go test -v ./services/crash_recovery_test.go` | إعادة ضبط رسائل الواتساب العالقة في < 0.1 ثانية | `PLANNED` |
| Gate 5.4 | اختبارات الإجهاد والتزامن المالي (Stress & Concurrency) | `cd go_backend; go test -v ./tests/stress/concurrency_test.go` | 50 معاملة سداد متزامنة بصفر تضارب وصفر فروقات تقريب | `PLANNED` |
| Gate 5.5 | التدقيق الختامي المستقل وإصدار القرار في `FINAL_AUDIT.md` | `Get-Content -Path MIGRATION/FINAL_AUDIT.md -Tail 20` | صدور القرار النهائي الصريح `# FINAL AUDIT VERDICT: READY` | `PLANNED` |

## 3. المواصفات التفصيلية لبوابات المرحلة 5 (Detailed Gate Specifications)

#### البوابة Gate 5.1: النسخ الاحتياطي الآلي اليومي عبر `pg_dump -Fc` واحتساب SHA-256
- **الهدف المعماري**: ضمان حماية بيانات المشتركين والمحطة عبر نسخة احتياطية يومية مشفرة ومضغوطة بصيغة PostgreSQL الثنائية.
- **أمر التحقق (Command)**:
  ```powershell
  & "d:\elctercity\server.exe" --backup-now
  $latestDump = Get-ChildItem -Path "d:\elctercity\backups\*.dump" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $hash = Get-FileHash -Path $latestDump.FullName -Algorithm SHA256
  [PSCustomObject]@{ DumpFile = $latestDump.Name; SizeKB = [math]::Round($latestDump.Length / 1KB, 2); SHA256 = $hash.Hash } | Format-List
  ```
- **المخرجات المتوقعة (Expected Output)**: اسم ملف النسخة الاحتياطية بحجم سليم (> 10KB) وتجزئة SHA-256 صحيحة.
- **معيار النجاح (`PASS`)**: توليد النسخة الاحتياطية المحلية وتوثيق تجزئة SHA-256 بنجاح.

#### البوابة Gate 5.2: الرصد التلقائي لأقراص USB عبر Win32 API ومطابقة المرآة
- **الهدف المعماري**: الكشف التلقائي عن الفلاش ميموري المتصل بنظام التشغيل عبر دالة `GetDriveTypeW` ونسخ ملف النسخة الاحتياطية ومطابقة التجزئة، مع التراجع الهادئ عند عدم وجود فلاش.
- **أمر التحقق (Command)**:
  ```powershell
  Push-Location "d:\elctercity\go_backend"
  & "C:\Program Files\Go\bin\go.exe" test -v ./backup/usb_mirror_test.go
  Pop-Location
  ```
- **المخرجات المتوقعة (Expected Output)**: `=== RUN TestUSBDetectionWin32 ... PASS`, `=== RUN TestSHA256IntegrityMatch ... PASS`.
- **معيار النجاح (`PASS`)**: مطابقة تجزئة الملف المحلي مع الفلاش بنسبة 100%.

#### البوابة Gate 5.3: اختبار التعافي من الانهيار المفاجئ (Cold-Boot & Crash Recovery)
- **الهدف المعماري**: ضمان سلامة طابور الواتساب والعمليات عند انقطاع التيار الكهربائي المفاجئ، وإعادة جدولة الرسائل العالقة في حالة `PROCESSING` لتصبح `PENDING` خلال أقل من 0.1 ثانية عند الإقلاع.
- **أمر التحقق (Command)**:
  ```powershell
  Push-Location "d:\elctercity\go_backend"
  & "C:\Program Files\Go\bin\go.exe" test -v ./services/crash_recovery_test.go
  Pop-Location
  ```
- **المخرجات المتوقعة (Expected Output)**: إعادة ضبط الرسائل العالقة في زمن < 0.1 ثانية بدون فقدان أي رسالة أو تكرارها.
- **معيار النجاح (`PASS`)**: نجاح اختبار التعافي السريع.

#### البوابة Gate 5.4: اختبارات الإجهاد والتزامن المالي (Concurrency & Stress Testing)
- **الهدف المعماري**: التحقق من صرامة القفل المتشائم `FOR UPDATE` وترتيب الاستعلامات القطعي في منع حالات التجمد (Deadlocks) أو تضارب الأرصدة أثناء ضغط العمليات المتزامنة.
- **أمر التحقق (Command)**:
  ```powershell
  Push-Location "d:\elctercity\go_backend"
  & "C:\Program Files\Go\bin\go.exe" test -v ./tests/stress/concurrency_test.go
  Pop-Location
  ```
- **المخرجات المتوقعة (Expected Output)**: تنفيذ 50 عملية سداد متزامنة بنجاح، وتطابق رصيد المشترك المتوقع مع الفعلي، وانعدام فروق التقريب (Rounding discrepancies: 0.00).
- **معيار النجاح (`PASS`)**: انعدام التضارب بنسبة 100% ومطابقة الأرصدة.

#### البوابة Gate 5.5: التدقيق الختامي المستقل وإصدار القرار في `MIGRATION/FINAL_AUDIT.md`
- **الهدف المعماري**: التدقيق النهائي المستقل والشامل لمصفوفة البنود الـ 12 وتوقيع القرار النهائي الصريح.
- **أمر التحقق (Command)**:
  ```powershell
  Get-Content -Path "d:\elctercity\MIGRATION\FINAL_AUDIT.md" -Tail 20
  ```
- **المخرجات المتوقعة (Expected Output)**: ظهور السطر النهائي القطعي: `# FINAL AUDIT VERDICT: READY`.
- **معيار النجاح (`PASS`)**: صدور قرار الجاهزية التامة للإنتاج `READY`.

## 4. قرار بوابة المرحلة 5 (Phase 5 Gate Decision)
- **القرار النهائي**: `[GATE_STATUS: PLANNED]`
```

---

## 4. خطة التطبيق المقترحة ومسار الاعتماد (Implementation & Signoff Plan)

وفقاً لقاعدة المشروع الصارمة في `AGENTS.md` بعدم التعديل على أي ملف دون إذن مسبق وموافقة صريحة، فإن المسار الهندسي الموصى به لمعالجة الملاحظة هو:

1. **الخطوة 1 (الاستكشاف والتجهيز — منجز)**: تم حصر واستخراج وتدقيق كافة بوابات العبور الـ 23 في هذا الملف `analysis.md` مع ضمان خلوها من الأرقام المشرقية بنسبة 100%.
2. **الخطوة 2 (التكليف والتنفيذ)**: يكلف الموجه `orchestrator_migration` الوكيل المنفذ `worker_m1` باستبدال الأسطر 192-218 في `d:\elctercity\MIGRATION\EXECUTION_LOG.md` بالكتلة النصية المعدة أعلاه في القسم 3 من هذا التقرير.
3. **الخطوة 3 (إعادة التدقيق المستقل)**: يقوم المراجع `reviewer_m1_2` بإعادة فحص `EXECUTION_LOG.md` للتأكد من وجود كافة البوابات الـ 27، مما يمهد لرفع حكم `REQUEST_CHANGES` ومنح الاعتماد النهائي للمرحلة M1.

</div>
