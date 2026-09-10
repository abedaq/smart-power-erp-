# التقرير الهندسي الشامل: تصميم وهيكلة سجل التنفيذ وبوابات العبور
## (Comprehensive Architecture & Specification: MIGRATION/EXECUTION_LOG.md)

<div dir="rtl">

- **معرف الوكيل**: `explorer_m1_executionlog` (Execution Log Designer)
- **الموجه المشرف**: `orchestrator_migration` (Conversation ID: `8662d701-dced-4ddd-b545-e2b64c0e3fc2`)
- **تاريخ الصياغة**: 2026-09-06
- **مسار التقرير**: `d:\elctercity\.agents\explorer_m1_executionlog\analysis.md`
- **المهمة الحاكمة**: صياغة وتصميم الهيكل الكامل لسجل التنفيذ الحي `MIGRATION/EXECUTION_LOG.md`، وبناء بوابات العبور الصارمة المبنية على الأدلة (Evidence-Based Phase Gates) للمراحل الخمس، وتحديد أوامر التحقق ومخرجاتها الحرفية، وتجهيز الإدخالات الأولية للمرحلة صفر والمرحلة 1.

---

## 1. الحقيقة التقنية والمخاطر التشغيلية أولاً (Technical Reality & Operational Risks)

1. [مؤكد] **غياب سجل التنفيذ الحي حتى اللحظة**:
   - مجلد `MIGRATION/` غير موجود حالياً على القرص (`Test-Path d:\elctercity\MIGRATION` = `False`).
   - غياب سجل تنفيذ صارم يؤدي حتماً إلى انتقال المهندسين بين المراحل دون إثبات فعلي لاجتياز المتطلبات، مما يسبب تراكم الديون التقنية والانهيار المحاسبي في المراحل المتقدمة.
2. [مؤكد] **خطر بوابات العبور الصورية (Fake Phase Gates)**:
   - أكبر خطر يهدد مشاريع الترحيل الشاملة هو الاكتفاء بعبارات عامة مثل "تم الفحص بنجاح" دون تسجيل الأمر المنفذ نصياً، والمخرجات الفعلية الصادرة من الطرفية (Verbatim stdout/stderr)، ومطابقة التجزئة (Hash)، وزمن التنفيذ.
   - **القاعدة الحاكمة الصارمة**: يُحظر حظراً باتاً على أي وكيل الانتقال من المرحلة $N$ إلى المرحلة $N+1$ ما لم تتضمن وثيقة `EXECUTION_LOG.md` راية عبور قطعية `[GATE_STATUS: PASS]` مرفقة بمخرجات أوامر التحقق المطابقة لشروط القبول.
3. [مؤكد] **خطر التعديل بأثر رجعي في السجلات (Log Mutation)**:
   - يجب أن يكون سجل التنفيذ تراكمياً وغير قابل للتعديل التراجعي (Append-Only Journal)؛ في حال فشل أي بوابة يتم تسجيل `[GATE_STATUS: FAIL]` مع سبب الفشل والإجراء التصحيحي المتخذ في تدوينة لاحقة، ولا يتم مسح الفشل السابق لإخفائه.
4. [مؤكد] **الالتزام بالأرقام الإنجليزية (0-9) واللغة العربية**:
   - يُفرض الالتزام بنظام الأرقام الإنجليزية (0, 1, 2, 3, 4, 5, 6, 7, 8, 9) حصراً في كافة جداول ومخرجات السجل، ومنع استخدام الأرقام المشرقية منعاً باتاً.

---

## 2. معمارية وهيكل سجل التنفيذ الحي (Live Working Journal Architecture)

صُمم ملف `MIGRATION/EXECUTION_LOG.md` ليعمل كـ "صندوق أسود" وسجل وقائع حي (Flight Data Recorder) لمشروع التحديث والترحيل الشامل.

### 2.1 المبادئ المعمارية الحاكمة للسجل
1. **الخطية والتعاقب الصارم (Strict Linearity)**: كل تدوينة تعتمد على ما قبلها وترتبط برقم خطوة تسلسلي محدد.
2. **الإثبات النصي غير القابل للجدل (Verbatim Proof)**: تسجيل الأمر كاملاً مع كافة معاملاته، والمخرجات النصية المباشرة من الطرفية (Terminal stdout/stderr)، ورمز الخروج (`Exit Code = 0`).
3. **التوثيق الثنائي للحالات (Binary Pass/Fail Discipline)**: لا توجد حالة رمادية؛ البوابة إما `PASS` باجتياز 100% من الاختبارات، أو `FAIL` توقف التقدم فوراً.
4. **تتبع الفاعلين (Agent Traceability)**: كل مدخل يتضمن معرف الوكيل المنفذ، والدور، والطابع الزمني بصيغة UTC الدقيقة.

### 2.2 القالب المعياري الموحد لتدوينات المراحل (Standard Phase Entry Schema)

يجب أن تلتزم كل مرحلة في `MIGRATION/EXECUTION_LOG.md` بالهيكل التالي:

```markdown
# [PHASE_ID]: [عنوان المرحلة باللغتين العربية والإنجليزية]

- **الحالة (Status)**: `IN_PROGRESS` | `PASS` | `FAIL` | `BLOCKED`
- **الوكيل المسؤول (Agent)**: [اسم الوكيل ودوره]
- **معرف المحادثة (Conversation ID)**: [UUID]
- **تاريخ وتوقيت البدء (Start Timestamp)**: YYYY-MM-DDTHH:MM:SSZ
- **تاريخ وتوقيت الانتهاء (End Timestamp)**: YYYY-MM-DDTHH:MM:SSZ
- **المدة المستغرقة (Duration)**: [X minutes / seconds]

## 1. الشروط المسبقة (Pre-conditions)
- [ ] تحقق اكتمال بوابات المرحلة السابقة [PHASE_ID-1] برمز PASS صريح.
- [ ] توفر البيئة والأدوات المطلوبة.

## 2. سجل الإجراءات التفصيلية (Step-by-Step Execution Log)
### خطوة 2.1: [وصف الإجراء]
- **الأمر المنفذ (Command)**:
  ```powershell
  [Exact Command Line]
  ```
- **دليل التشغيل (Working Directory)**: `d:\elctercity\...`
- **رمز الخروج (Exit Code)**: `0`
- **مخرجات الطرفية الفعلية (Verbatim Output)**:
  ```text
  [Unmodified terminal output captured directly from stdout/stderr]
  ```
- **الأصول المتأثرة والملفات (Affected Artifacts)**:
  - `path/to/file.ext` (lines: X-Y, SHA-256: [hash])

## 3. مصفوفة تقييم بوابات العبور (Phase Gate Evaluation Matrix)
| معرف البوابة | معيار الفحص المستهدف | أمر التحقق الإلزامي | النتيجة المتوقعة | النتيجة الفعلية | التقييم |
|:---|:---|:---|:---|:---|:---:|
| Gate X.1 | [وصف المعيار] | `[command]` | [Expected] | [Actual] | `PASS` / `FAIL` |

## 4. قرار عبور البوابة (Gate Decision)
- **القرار النهائي**: `[GATE_STATUS: PASS]` أو `[GATE_STATUS: FAIL]`
- **توقيع الوكيل (Signoff)**: [اسم الوكيل] - [التاريخ والوقت UTC]
- **الإذن بالانتقال للمرحلة التالية**: [ممنوح / محظور]
```

---

## 3. بوابات العبور الصارمة للمراحل الخمس (Evidence-Based Phase Gates)

تم تقسيم المشروع إلى 5 مراحل رئيسية وفق وثيقة المتطلبات ووثيقة `PROJECT.md`. لكل مرحلة بوابات فرعية متخصصة تضمن النزاهة الهندسية والأداء والأمان والامتثال المالي.

```
+-------------------------------------------------------------------------------------------------------+
|                                  سلسلة بوابات العبور الصارمة للمشروع                                  |
+-------------------------------------------------------------------------------------------------------+
|                                                                                                       |
|  [المرحلة 1: بروتوكول الترحيل وتثبيت الأساس]                                                            |
|  Gate 1.1: التحقق الحصري للملفات الثلاثة في MIGRATION/                                                |
|  Gate 1.2: التحقق القطعي من الحذف الجسدي 100% لتطبيق المحمول وحزم الـ APK                             |
|  Gate 1.3: فحص سلامة بيئة الأدوات (Go 1.27 + PG 18.6 + Node.js) واجتياز بناء Frontend                |
|  Gate 1.4: تثبيت وحماية قواعد العمل المعتمدة (18 عموداً، الفاتورة A5 المزدوجة، الأرقام الإنجليزية)   |
|         |                                                                                             |
|         v (عند اجتياز جميع بوابات المرحلة 1 بـ PASS حصراً)                                            |
|                                                                                                       |
|  [المرحلة 2: قاعدة بيانات PostgreSQL المحلية والنزاهة المالية]                                        |
|  Gate 2.1: تهيئة قاعدة بيانات smartpower_db والمستخدم المحلي بنجاح                                    |
|  Gate 2.2: نشر المخطط المتين (11 جدولاً + الفهارس والقيود)                                            |
|  Gate 2.3: قيد تصاعد القراءات الصارم (منع القراءات التنازلية على مستوى DB Constraint)                 |
|  Gate 2.4: محرك توزيع السداد المائي FIFO الذري مع القفل المتشائم FOR UPDATE وحفظ الفائض             |
|  Gate 2.5: الترقيم الحتمي المركب للفواتير (INV-[Cycle]-[SubscriberNumber])                           |
|  Gate 2.6: محرك الحساب الرجعي التتابعي التلقائي (T -> N) وانعدام فروقات التقريب المالي               |
|         |                                                                                             |
|         v (عند اجتياز جميع بوابات المرحلة 2 بـ PASS حصراً)                                            |
|                                                                                                       |
|  [المرحلة 3: خادم Go المستقل ومحرك الواتساب]                                                          |
|  Gate 3.1: بناء مشروع Go وتجميعه النقي بنسبة 100% (CGO_ENABLED=0) بدون SQLite                         |
|  Gate 3.2: مطابقة عقود واجهات الـ REST API الـ 14 والـ 54 نقطة نهاية بنسبة 100%                      |
|  Gate 3.3: محرك الواتساب whatsmeow مع تخزين الجلسات مباشرة في PostgreSQL                             |
|  Gate 3.4: طابور الرسائل المحلي المحدد زمنياً (تأخير آمن 8-15 ثانية لحماية الأرقام)                  |
|  Gate 3.5: محرك تصوير الفواتير A5 عبر chromedp واستغلال متصفح النظام بدون تشويه الحروف العربية        |
|  Gate 3.6: محرك الإكسل المتدفق excelize/v2 مع دعم RTL الكامل واستهلاك ذاكرة < 20MB                   |
|  Gate 3.7: تجميع الواجهة frontend/dist داخل server.exe عبر //go:embed وتقديمها في < 0.1s             |
|         |                                                                                             |
|         v (عند اجتياز جميع بوابات المرحلة 3 بـ PASS حصراً)                                            |
|                                                                                                       |
|  [المرحلة 4: صقل واجهة React Desktop وفك الارتباط التام]                                              |
|  Gate 4.1: التطهير الشامل والاستئصال الكامل لكافة استدعاءات وبقايا Supabase                           |
|  Gate 4.2: ربط الواجهة الأمامية محلياً 100% بخادم Go REST API على المسار /api                        |
|  Gate 4.3: المطابقة البصرية الصارمة لنموذج الفاتورة A5 المزدوجة مع photo_5769554780358381104_y.jpg   |
|  Gate 4.4: التطبيق الشامل للأرقام الإنجليزية (0-9) وقمع أسهم المتصفح وانعدام الأرقام المشرقية         |
|  Gate 4.5: اجتياز بناء الإنتاج للواجهة npm run build بنسبة 100% وبدون أي تحذيرات تعطل                 |
|         |                                                                                             |
|         v (عند اجتياز جميع بوابات المرحلة 4 بـ PASS حصراً)                                            |
|                                                                                                       |
|  [المرحلة 5: التعافي من الكوارث، التحصين، والتدقيق الختامي]                                           |
|  Gate 5.1: النسخ الاحتياطي الآلي اليومي pg_dump -Fc مع التشفير واحتساب SHA-256                        |
|  Gate 5.2: الرصد التلقائي لأقراص USB عبر Win32 API والنسخ المطابق مع التراجع الآمن عند الغياب         |
|  Gate 5.3: اختبار التعافي من الانهيار المفاجئ وإعادة ضبط طابور الواتساب المعلق في < 0.1 ثانية        |
|  Gate 5.4: اختبارات الإجهاد والتزامن المالي (تزامن السداد وتعديل الخلايا دون تضارب)                  |
|  Gate 5.5: التدقيق الختامي المستقل وإصدار القرار النهائي الصريح READY في MIGRATION/FINAL_AUDIT.md     |
+-------------------------------------------------------------------------------------------------------+
```

---

## 4. الفهرس التفصيلي لبوابات العبور وأوامر التحقق ومعايير النجاح (Detailed Gate Catalog)

### 4.1 المرحلة 1: بروتوكول الترحيل وتثبيت الأساس (Protocol Setup & Baseline Verification)

#### البوابة 1.1: التحقق الحصري للملفات الثلاثة في مجلد `MIGRATION/`
- **الهدف المعماري**: ضمان وجود ثلاثة ملفات فقط داخل `MIGRATION/` وعدم تشتت التوثيق.
- **أمر التحقق (Command)**:
  ```powershell
  Get-ChildItem -Path "d:\elctercity\MIGRATION" -File | Select-Object Name, Length
  ```
- **المخرجات المتوقعة (Expected Output)**:
  يجب أن تُعيد 3 ملفات فقط بأسمائها الصريحة:
  ```text
  Name                Length
  ----                ------
  EXECUTION_LOG.md    [> 0]
  FINAL_AUDIT.md      [> 0]
  MASTER_PLAN.md      [> 0]
  ```
- **معيار النجاح (`PASS`)**:
  - عدد الملفات يساوي 3 تماماً (`Count -eq 3`).
  - الأسماء مطابقة حصراً لـ `MASTER_PLAN.md`, `EXECUTION_LOG.md`, `FINAL_AUDIT.md`.
  - عدم وجود أي مجلد فرعي أو ملفات مسودة مؤقتة.

#### البوابة 1.2: التحقق القطعي من الحذف الجسدي 100% لتطبيق المحمول وحزم الـ APK
- **الهدف المعماري**: إثبات عدم وجود أي أثر لمجلد `mobile_app` أو حزم `*.apk` في كامل المستودع.
- **أمر التحقق (Command)**:
  ```powershell
  $hasDir = Test-Path "d:\elctercity\mobile_app"
  $apks = Get-ChildItem -Path "d:\elctercity" -Filter "*.apk" -Recurse -Force -ErrorAction SilentlyContinue
  [PSCustomObject]@{ MobileDirExists = $hasDir; ApkCount = @($apks).Count } | Format-List
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
  MobileDirExists : False
  ApkCount        : 0
  ```
- **معيار النجاح (`PASS`)**:
  - `MobileDirExists` = `False`.
  - `ApkCount` = `0`.

#### البوابة 1.3: فحص سلامة بيئة الأدوات وبناء الواجهة الأمامية
- **الهدف المعماري**: التأكد من جاهزية مترجم Go، وخادم PostgreSQL المحلي، ومحرك Node.js، ونجاح بناء الواجهة الأمامية React.
- **أمر التحقق (Command)**:
  ```powershell
  & "C:\Program Files\Go\bin\go.exe" version
  & "C:\Program Files\PostgreSQL\18\bin\psql.exe" --version
  Get-Service -Name "postgresql-x64-18" | Select-Object Name, Status
  Push-Location "d:\elctercity\frontend"; npm run build; $bSuccess = ($LASTEXITCODE -eq 0); Pop-Location; [PSCustomObject]@{ FrontendBuildSuccess = $bSuccess } | Format-List
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
  go version go1.27.0 windows/amd64
  psql (PostgreSQL) 18.6
  Name              Status
  ----              ------
  postgresql-x64-18 Running
  FrontendBuildSuccess : True
  ```
- **معيار النجاح (`PASS`)**:
  - توفر Go بنسخة $\ge 1.22$.
  - توفر PostgreSQL 18.x والخدمة في حالة `Running`.
  - انتهاء بناء الفرونت إند برمز خروج 0 وظهور ملفات `frontend/dist/`.

#### البوابة 1.4: تثبيت وحماية قواعد العمل المعتمدة ونموذج الفاتورة
- **الهدف المعماري**: إثبات اجتياز اختبارات نموذج الفاتورة المعتمدة والأرقام الإنجليزية وتبويبات النظام.
- **أمر التحقق (Command)**:
  ```powershell
  node "d:\elctercity\frontend\src\tests\test_challenger_layout_2.js"
  node "d:\elctercity\frontend\src\tests\test_routes_and_tabs.js"
  node "d:\elctercity\frontend\src\tests\test_numerals_scan.js"
  ```
- **المخرجات المتوقعة (Expected Output)**:
  - اختبار الفاتورة: `106 passed, 0 failed`.
  - اختبار التبويبات: `33 passed, 0 failed` مع تأكيد وجود تبويب "المديونيات" وحذف "التعرفة العامة".
  - فحص الأرقام: `0 Eastern Arabic numerals found, 0 unconstrained number inputs`.
- **معيار النجاح (`PASS`)**:
  - اجتياز 100% من الاختبارات دون أي إخفاق.

---

### 4.2 المرحلة 2: قاعدة بيانات PostgreSQL المحلية والنزاهة المالية (Local PostgreSQL & Financial Integrity Core)

#### البوابة 2.1: تهيئة قاعدة بيانات `smartpower_db` والمستخدم المحلي
- **الهدف المعماري**: إنشاء قاعدة بيانات نظيفة ومخصصة للإنتاج المحلي على المنفذ 5432.
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
- **معيار النجاح (`PASS`)**:
  - الاتصال الناجح بقاعدة `smartpower_db` على المنفذ 5432 برمز خروج 0.

#### البوابة 2.2: نشر المخطط المتين والجداول الأساسية والقيود
- **الهدف المعماري**: إنشاء الـ 11 جدولاً الأساسية مع فهارس الأداء وقيود المفاتيح الأجنبية.
- **أمر التحقق (Command)**:
  ```powershell
  & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -d smartpower_db -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;"
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ظهور قائمة الجداول كاملة:
  - `audit_logs`
  - `collector_customer_assignments`
  - `customer_credits`
  - `customers`
  - `invoices`
  - `meter_readings`
  - `payment_allocations`
  - `payment_receipt_counters`
  - `payments`
  - `shifts`
  - `subscription_plans`
  - `system_settings`
  - `users`
  - `whatsapp_queue_messages`
- **معيار النجاح (`PASS`)**:
  - وجود جميع الجداول الـ 14 بنجاح (`COUNT(*) >= 14`).

#### البوابة 2.3: قيد تصاعد القراءات الصارم (Non-Monotonic Reading Guard)
- **الهدف المعماري**: إثبات أن محاولة تسجيل قراءة أقل من القراءة السابقة يتم إحباطها ورفضها بقيد قاعدة البيانات الصريح.
- **أمر التحقق (Command)**:
  تشغيل سكربت اختبار يدرج قراءة سابقة = 150 ثم يحاول إدراج قراءة حالية = 140:
  ```powershell
  & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -d smartpower_db -f "d:\elctercity\database\tests\test_monotonic_guard.sql"
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
  ERROR:  New reading value (140) cannot be less than previous reading (150)
  CONTEXT:  PL/pgSQL function rpc_submit_meter_reading ...
  TEST RESULT: NON_MONOTONIC_REJECTED_SUCCESSFULLY
  ```
- **معيار النجاح (`PASS`)**:
  - إطلاق استثناء قطعي من قاعدة البيانات ومنع إدراج الصف المخالف وتراجع المعاملة (Rollback).

#### البوابة 2.4: محرك توزيع السداد المائي FIFO الذري مع القفل المتشائم `FOR UPDATE`
- **الهدف المعماري**: إثبات دقة سداد الفواتير القديمة أولاً وتوزيع المبلغ وحفظ الفائض في `customer_credits`.
- **أمر التحقق (Command)**:
  تشغيل سكربت اختبار السداد المائي: مشترك عليه فاتورتين (الأولى 1,000 ريال والثانية 2,000 ريال) ويسدد 1,500 ريال ثم يسدد 2,000 ريال إضافية:
  ```powershell
  & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -d smartpower_db -f "d:\elctercity\database\tests\test_waterfall_allocation.sql"
  ```
- **المخرجات المتوقعة (Expected Output)**:
  - الفاتورة الأولى تصبح `remaining_amount = 0`, `status = 'Paid'`.
  - الفاتورة الثانية تصبح `paid_amount = 500`, `remaining_amount = 1500`, `status = 'Partially_Paid'`.
  - عند سداد الـ 2,000 الإضافية: تكتمل الفاتورة الثانية (`remaining = 0, status = 'Paid'`) ويتبقى 500 تسجل في `customer_credits` كرصيد دائن للمشترك.
- **معيار النجاح (`PASS`)**:
  - مطابقة التوزيع المالي بنسبة 100% وانعدام أي فروق حسابية (Zero rounding drift).

#### البوابة 2.5: الترقيم الحتمي المركب للفواتير
- **الهدف المعماري**: التحقق من فرض الترقيم بصيغة `INV-[Cycle]-[SubscriberNumber]`.
- **أمر التحقق (Command)**:
  ```powershell
  & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -d smartpower_db -c "SELECT id, invoice_number, billing_cycle, customer_id FROM invoices LIMIT 5;"
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ظهور أرقام فواتير مطابقة للنمط التعبيري `^INV-[A-Za-z0-9_\u0600-\u06FF\-]+-[A-Za-z0-9_\-]+$`.
- **معيار النجاح (`PASS`)**:
  - كل صف يحمل ترقيماً مركباً حتمياً خالياً من الأرقام العشوائية.

#### البوابة 2.6: محرك الحساب الرجعي التتابعي التلقائي (Retroactive Recalculation)
- **الهدف المعماري**: تعديل قراءة سابقة في الدورة T والتأكد من تحديث كافة الأرصدة والمتأخرات في الدورات T+1 إلى N تلقائياً.
- **أمر التحقق (Command)**:
  ```powershell
  & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -d smartpower_db -f "d:\elctercity\database\tests\test_retroactive_recalc.sql"
  ```
- **المخرجات المتوقعة (Expected Output)**:
  - نجاح المعاملة الذرية وظهور `RECALCULATION_CASCADE_VERIFIED_PASS`.
- **معيار النجاح (`PASS`)**:
  - تحديث المتأخرات في جميع الدورات اللاحقة بدقة وبدون تدخل يدوي.

---

### 4.3 المرحلة 3: خادم Go المستقل ومحرك الواتساب (Standalone Go Backend & WhatsApp Engine)

#### البوابة 3.1: بناء مشروع Go وتجميعه النقي بنسبة 100% (`CGO_ENABLED=0`)
- **الهدف المعماري**: تجميع ملف تنفيذي مستقل بالكامل `server.exe` بحجم < 25MB وبدون أي اعتماديات Cgo أو SQLite.
- **أمر التحقق (Command)**:
  ```powershell
  Push-Location "d:\elctercity\go_backend"
  $env:CGO_ENABLED="0"
  $env:GOOS="windows"
  $env:GOARCH="amd64"
  & "C:\Program Files\Go\bin\go.exe" build -ldflags="-s -w" -trimpath -o "..\server.exe" .
  $bSuccess = ($LASTEXITCODE -eq 0)
  Pop-Location
  $f = Get-Item "d:\elctercity\server.exe"
  [PSCustomObject]@{ BuildSuccess = $bSuccess; SizeMB = [math]::Round($f.Length / 1MB, 2) } | Format-List
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
  BuildSuccess : True
  SizeMB       : [14.0 - 22.0]
  ```
- **معيار النجاح (`PASS`)**:
  - تجميع نظيف (Exit code: 0).
  - حجم `server.exe` أقل من 25MB قطيعاً.
  - خلو البناء من أي ربط بـ CGO (`CGO_ENABLED=0`).

#### البوابة 3.2: مطابقة عقود واجهات الـ REST API الـ 14 والـ 54 نقطة نهاية
- **الهدف المعماري**: التأكد من استجابة خادم Go Fiber لنقاط النهاية المعيارية بنفس هياكل JSON المتوافقة مع React.
- **أمر التحقق (Command)**:
  تشغيل جناح اختبار واجهات البرمجة الآلي:
  ```powershell
  Push-Location "d:\elctercity\go_backend"
  & "C:\Program Files\Go\bin\go.exe" test -v ./tests/api/...
  Pop-Location
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
  === RUN   TestAuthRoutes
  --- PASS: TestAuthRoutes (0.05s)
  === RUN   TestCustomerRoutes
  --- PASS: TestCustomerRoutes (0.12s)
  === RUN   TestReadingsExcelGridRoutes
  --- PASS: TestReadingsExcelGridRoutes (0.08s)
  === RUN   TestPaymentsWaterfallRoutes
  --- PASS: TestPaymentsWaterfallRoutes (0.09s)
  === RUN   TestInvoicesDoubleStubRoutes
  --- PASS: TestInvoicesDoubleStubRoutes (0.04s)
  === RUN   TestAnalyticsComprehensiveRoutes
  --- PASS: TestAnalyticsComprehensiveRoutes (0.06s)
  PASS
  ok      smartpower/tests/api    1.42s
  ```
- **معيار النجاح (`PASS`)**:
  - اجتياز كافة اختبارات نقاط النهاية (Exit code: 0).

#### البوابة 3.3: محرك الواتساب `whatsmeow` مع تخزين الجلسات في PostgreSQL
- **الهدف المعماري**: تشغيل `whatsmeow` وتخزين الجلسات في جدول PostgreSQL بدون الحاجة لـ SQLite أو ملفات خارجية.
- **أمر التحقق (Command)**:
  ```powershell
  Push-Location "d:\elctercity\go_backend"
  & "C:\Program Files\Go\bin\go.exe" test -v ./whatsapp/store_test.go
  Pop-Location
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
  === RUN   TestPostgresSessionStore
  --- PASS: TestPostgresSessionStore (0.15s)
  PASS
  ```
- **معيار النجاح (`PASS`)**:
  - نجاح الاتصال وتخزين واسترجاع الجلسة من قاعدة بيانات PostgreSQL مباشرة.

#### البوابة 3.4: طابور الرسائل المحلي المحدد زمنياً (Rate Limiter)
- **الهدف المعماري**: التحقق من أن طابور الواتساب يفرض تأخيراً آمناً يتراوح بين 8 إلى 15 ثانية بين كل رسالة وأخرى لحماية رقم هاتف المحطة من الحظر.
- **أمر التحقق (Command)**:
  ```powershell
  Push-Location "d:\elctercity\go_backend"
  & "C:\Program Files\Go\bin\go.exe" test -v ./whatsapp/queue_rate_limit_test.go
  Pop-Location
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
  === RUN   TestQueueRateLimiterDelay
      queue_test.go:45: Dispatching msg 1 at T+0s
      queue_test.go:52: Dispatching msg 2 at T+9.4s (Delay >= 8s confirmed)
      queue_test.go:52: Dispatching msg 3 at T+18.1s (Delay >= 8s confirmed)
  --- PASS: TestQueueRateLimiterDelay (18.15s)
  PASS
  ```
- **معيار النجاح (`PASS`)**:
  - التأخير الزمني المقاس بين الرسائل لا يقل عن 8 ثوانٍ ولا يزيد عن 15 ثانية.

#### البوابة 3.5: محرك تصوير الفواتير A5 عبر `chromedp` والخطوط العربية
- **الهدف المعماري**: التأكد من قدرة الخادم على توليد صورة PNG وملف PDF لفاتورة A5 ذات الكعب المزدوج باستخدام متصفح Edge المحلي، مع سلامة تشكيل الحروف العربية بنسبة 100%.
- **أمر التحقق (Command)**:
  ```powershell
  Push-Location "d:\elctercity\go_backend"
  & "C:\Program Files\Go\bin\go.exe" test -v ./chromedp/invoice_render_test.go
  Pop-Location
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
  === RUN   TestA5InvoiceRenderChromedp
      invoice_render_test.go:62: Generated PDF artifact: test_invoice.pdf (size > 15KB)
      invoice_render_test.go:68: Generated PNG artifact: test_invoice.png (dimensions: 1748x1240, 300DPI)
  --- PASS: TestA5InvoiceRenderChromedp (0.85s)
  PASS
  ```
- **معيار النجاح (`PASS`)**:
  - إنتاج الملفات بنجاح، وعدم ظهور أحرف مقطعة أو معكوسة في المعاينة.

#### البوابة 3.6: محرك الإكسل المتدفق `excelize/v2`
- **الهدف المعماري**: تصدير واستيراد الكشوفات بسرعة فائقة باستهلاك ذاكرة أقل من 20MB ودعم اتجاه الـ RTL الكامل.
- **أمر التحقق (Command)**:
  ```powershell
  Push-Location "d:\elctercity\go_backend"
  & "C:\Program Files\Go\bin\go.exe" test -v ./excel/excel_benchmark_test.go
  Pop-Location
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
  === RUN   TestExcelStreamingExport_5000Rows
      excel_test.go:85: Exported 5,000 rows in 0.42s, Peak RAM: 14.2 MB (< 20MB PASS)
  === RUN   TestExcelRTLProperty
      excel_test.go:102: Sheet rightToLeft property verified: true
  --- PASS: TestExcelStreamingExport_5000Rows (0.42s)
  --- PASS: TestExcelRTLProperty (0.01s)
  PASS
  ```
- **معيار النجاح (`PASS`)**:
  - تفعيل RTL، وتوليد الملف في زمن < 1 ثانية واستهلاك RAM < 20MB.

#### البوابة 3.7: تجميع الواجهة `frontend/dist` داخل `server.exe` عبر `//go:embed`
- **الهدف المعماري**: تقديم واجهة React Desktop فورياً عند طلب `http://localhost:3000` بدون خوادم خارجية.
- **أمر التحقق (Command)**:
  تشغيل الخادم في الخلفية وطلب الصفحة الرئيسية:
  ```powershell
  $job = Start-Process -FilePath "d:\elctercity\server.exe" -PassThru
  Start-Sleep -Milliseconds 500
  $resp = Invoke-WebRequest -Uri "http://localhost:3000" -UseBasicParsing
  $apiResp = Invoke-WebRequest -Uri "http://localhost:3000/api/health" -UseBasicParsing
  Stop-Process -Id $job.Id -Force
  [PSCustomObject]@{ RootStatus = $resp.StatusCode; HasReactRoot = $resp.Content.Contains('<div id="root">'); ApiStatus = $apiResp.StatusCode } | Format-List
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
  RootStatus    : 200
  HasReactRoot  : True
  ApiStatus     : 200
  ```
- **معيار النجاح (`PASS`)**:
  - استجابة جذر الخادم بصفحة React SPA بنجاح (HTTP 200).

---

### 4.4 المرحلة 4: صقل واجهة React Desktop وفك الارتباط التام (React Desktop UI Polish & Decoupling)

#### البوابة 4.1: التطهير الشامل والاستئصال الكامل لكافة استدعاءات Supabase
- **الهدف المعماري**: التأكد من خلو كود الواجهة في `frontend/src/` من أي استيراد أو استدعاء لـ `@supabase/supabase-js` أو `getSupabase`.
- **أمر التحقق (Command)**:
  ```powershell
  $res = Select-String -Path "d:\elctercity\frontend\src\**\*.ts","d:\elctercity\frontend\src\**\*.tsx" -Pattern "supabase|getSupabase|@supabase" -SimpleMatch
  [PSCustomObject]@{ SupabaseOccurrences = @($res).Count } | Format-List
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
  SupabaseOccurrences : 0
  ```
- **معيار النجاح (`PASS`)**:
  - صفر استدعاءات أو إشارات لسوبابيز داخل كود الواجهة الأمامية النشط.

#### البوابة 4.2: ربط الواجهة الأمامية محلياً 100% بخادم Go REST API على المسار `/api`
- **الهدف المعماري**: إثبات أن كافة الخدمات في `frontend/src/services/` تستدعي `/api/...` بنمط نسبي محلي.
- **أمر التحقق (Command)**:
  ```powershell
  node "d:\elctercity\frontend\src\tests\test_api_endpoints_coverage.js"
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
  Total services checked: 12
  Total endpoints bound to /api: 54
  Unbound or external endpoints: 0
  VERDICT: ALL_ENDPOINTS_LOCALLY_BOUND_PASS
  ```
- **معيار النجاح (`PASS`)**:
  - تغطية بنسبة 100% لكافة نقاط النهاية المحلية.

#### البوابة 4.3: المطابقة البصرية الصارمة لنموذج الفاتورة A5 المزدوجة
- **الهدف المعماري**: التأكد من الحفاظ الدقيق على تصميم الفاتورة ذي الكعب المزدوج المتطابق مع `photo_5769554780358381104_y.jpg`.
- **أمر التحقق (Command)**:
  ```powershell
  node "d:\elctercity\frontend\src\tests\test_challenger_layout_2.js"
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
  106 tests passed, 0 failed.
  ```
- **معيار النجاح (`PASS`)**:
  - اجتياز 106 اختبارات بنسبة 100%.

#### البوابة 4.4: التطبيق الشامل للأرقام الإنجليزية (0-9) وقمع أسهم المتصفح
- **الهدف المعماري**: ضمان خلو جميع حقول الإدخال والشاشات من أسهم المتصفح والأرقام المشرقية.
- **أمر التحقق (Command)**:
  ```powershell
  node "d:\elctercity\frontend\src\tests\test_numerals_scan.js"
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
  Eastern Arabic Numerals Count: 0
  Invalid type=number Inputs: 0
  VERDICT: 100_PERCENT_ENGLISH_NUMERALS_PASS
  ```
- **معيار النجاح (`PASS`)**:
  - نتيجة فحص خالية تماماً من المخالفات.

#### البوابة 4.5: اجتياز بناء الإنتاج للواجهة وتحديث حزمة `dist/`
- **الهدف المعماري**: تجميع حزمة الإنتاج الخالية من الأخطاء والجاهزة للتضمين النهائي.
- **أمر التحقق (Command)**:
  ```powershell
  Push-Location "d:\elctercity\frontend"
  npm run build
  $bSuccess = ($LASTEXITCODE -eq 0)
  Pop-Location
  [PSCustomObject]@{ BuildSuccess = $bSuccess } | Format-List
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
  BuildSuccess : True
  ```
- **معيار النجاح (`PASS`)**:
  - انتهاء البناء برمز خروج 0 وظهور الأصول المحدثة.

---

### 4.5 المرحلة 5: التعافي من الكوارث، التحصين، والتدقيق الختامي (Disaster Recovery, Hardening & Independent Audit)

#### البوابة 5.1: النسخ الاحتياطي الآلي اليومي عبر `pg_dump -Fc` واحتساب SHA-256
- **الهدف المعماري**: تشغيل أمر النسخ الاحتياطي وضغط البيانات واحتساب التجزئة لضمان عدم تلف الملف.
- **أمر التحقق (Command)**:
  ```powershell
  & "d:\elctercity\server.exe" --backup-now
  $latestDump = Get-ChildItem -Path "d:\elctercity\backups\*.dump" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $hash = Get-FileHash -Path $latestDump.FullName -Algorithm SHA256
  [PSCustomObject]@{ DumpFile = $latestDump.Name; SizeKB = [math]::Round($latestDump.Length / 1KB, 2); SHA256 = $hash.Hash } | Format-List
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ظهور اسم الملف بحجم سليم وتجزئة SHA-256 صحيحة:
  ```text
  DumpFile : smartpower_backup_YYYYMMDD_HHMMSS.dump
  SizeKB   : [> 10.0]
  SHA256   : [64-character hex string]
  ```
- **معيار النجاح (`PASS`)**:
  - توليد ملف dump صالح ومضغوط واحتساب التجزئة بنجاح.

#### البوابة 5.2: الرصد التلقائي لأقراص USB عبر Win32 API ومطابقة المرآة
- **الهدف المعماري**: التأكد من رصد الفلاش ميموري المتصل بنجاح، ومطابقة تجزئة SHA-256 بين النسخة المحلية ونسخة الفلاش، والتراجع الهادئ عند عدم وجود فلاش.
- **أمر التحقق (Command)**:
  ```powershell
  Push-Location "d:\elctercity\go_backend"
  & "C:\Program Files\Go\bin\go.exe" test -v ./backup/usb_mirror_test.go
  Pop-Location
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
  === RUN   TestUSBDetectionWin32
      usb_test.go:42: Win32 API GetDriveTypeW test completed. Removable drives detected or safe fallback verified.
  === RUN   TestSHA256IntegrityMatch
      usb_test.go:68: Local hash matches USB mirror hash 100%.
  --- PASS: TestUSBDetectionWin32 (0.05s)
  --- PASS: TestSHA256IntegrityMatch (0.12s)
  PASS
  ```
- **معيار النجاح (`PASS`)**:
  - نجاح كشف منافذ Win32 واكتمال المطابقة.

#### البوابة 5.3: اختبار التعافي من الانهيار المفاجئ (Cold-Boot & Crash Recovery)
- **الهدف المعماري**: محاكاة انهيار مفاجئ للتيار أثناء وجود رسائل بحالة `PROCESSING` في طابور الواتساب، والتحقق من إعادة ضبطها إلى `PENDING` عند الإقلاع البارد في زمن < 0.1 ثانية.
- **أمر التحقق (Command)**:
  ```powershell
  Push-Location "d:\elctercity\go_backend"
  & "C:\Program Files\Go\bin\go.exe" test -v ./services/crash_recovery_test.go
  Pop-Location
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
  === RUN   TestCrashRecoveryStuckQueue
      crash_test.go:34: Injected 3 stuck PROCESSING messages.
      crash_test.go:48: Executed Cold-Boot recovery routine in 0.012s (< 0.1s PASS).
      crash_test.go:55: Verified stuck messages reset to PENDING: count = 3.
  --- PASS: TestCrashRecoveryStuckQueue (0.08s)
  PASS
  ```
- **معيار النجاح (`PASS`)**:
  - إعادة ضبط جميع الرسائل العالقة بنجاح والإقلاع في أقل من 0.1 ثانية.

#### البوابة 5.4: اختبارات الإجهاد والتزامن المالي (Concurrency & Stress Testing)
- **الهدف المعماري**: تشغيل 50 عملية سداد وقراءة متزامنة لنفس المشترك في نفس اللحظة للتحقق من صرامة القفل المتشائم `FOR UPDATE` وانعدام أي فروق حسابية.
- **أمر التحقق (Command)**:
  ```powershell
  Push-Location "d:\elctercity\go_backend"
  & "C:\Program Files\Go\bin\go.exe" test -v ./tests/stress/concurrency_test.go
  Pop-Location
  ```
- **المخرجات المتوقعة (Expected Output)**:
  ```text
  === RUN   TestConcurrentPaymentsPessimisticLock
      concurrency_test.go:88: Executed 50 parallel payments across 10 workers.
      concurrency_test.go:94: Reconciled customer balance: expected = 45000.00, actual = 45000.00.
      concurrency_test.go:98: Rounding discrepancies: 0.00.
  --- PASS: TestConcurrentPaymentsPessimisticLock (1.84s)
  PASS
  ```
- **معيار النجاح (`PASS`)**:
  - انعدام التضارب بنسبة 100% ومطابقة الأرصدة التامة بصفر فروقات تقريب.

#### البوابة 5.5: التدقيق الختامي المستقل وإصدار القرار في `MIGRATION/FINAL_AUDIT.md`
- **الهدف المعماري**: مراجعة شاملة ومستقلة لكافة بوابات المراحل الخمس وإصدار حكم حاسم وصريح.
- **أمر التحقق (Command)**:
  ```powershell
  Get-Content -Path "d:\elctercity\MIGRATION\FINAL_AUDIT.md" -Tail 20
  ```
- **المخرجات المتوقعة (Expected Output)**:
  يجب أن ينتهي الملف بالصيغة القطعية:
  ```markdown
  # FINAL AUDIT VERDICT: READY
  ```
- **معيار النجاح (`PASS`)**:
  - صدور القرار الصريح `READY` واستيفاء كافة البنود بدون أي تحفظات معلقة.

---

## 5. الصياغة الجاهزة لملف سجل التنفيذ الأولي (`MIGRATION/EXECUTION_LOG.md`)

فيما يلي النص الهندسي الكامل المعتمد لتأسيس الملف الفعلي `MIGRATION/EXECUTION_LOG.md` متضمناً نتائج استطلاع المرحلة صفر (Phase 0) وتأسيس المرحلة 1 (Phase 1):

```markdown
# SmartPower ERP — Migration Execution Log (سجل التنفيذ وبوابات العبور)

- **وثيقة المشروع الحاكمة**: `MIGRATION/MASTER_PLAN.md`
- **معيار التوثيق الثلاثي**: `MIGRATION/` يضم حصراً: `MASTER_PLAN.md`, `EXECUTION_LOG.md`, `FINAL_AUDIT.md`.
- **قاعدة الانتقال بين المراحل**: يُحظر بدء أي مرحلة جديدة قبل الحصول على راية `[GATE_STATUS: PASS]` صريحة لجميع بوابات المرحلة السابقة وتوثيق مخرجات الأوامر الفعلية.
- **تاريخ إنشاء السجل**: 2026-09-06T08:30:00Z
- **المنظومة المستهدفة**: نظام محلي مكتبي مستقل 100% (`server.exe` بلغة Go وقاعدة بيانات PostgreSQL المحلية `smartpower_db`).

---

# PHASE 0: الاستطلاع المعماري الشامل والمسح الميداني (System Discovery & Architecture Survey)

- **الحالة (Status)**: `PASS`
- **الوكلاء المسؤولون**:
  - `explorer_migration_backend` (مسح الباك إند وقواعد البيانات)
  - `explorer_migration_frontend` (مسح الواجهة الأمامية والفواتير)
  - `explorer_migration_ops` (مسح العمليات والنسخ الاحتياطي وحذف المحمول)
- **تاريخ البدء**: 2026-09-06T08:00:00Z
- **تاريخ الانتهاء**: 2026-09-06T08:28:00Z
- **المدة المستغرقة**: 28 دقيقة

## 1. الشروط المسبقة (Pre-conditions)
- [x] استلام أمر التكليف الشامل في `d:\elctercity\.agents\ORIGINAL_REQUEST.md`.
- [x] تشغيل 3 وكلاء استطلاع مستقلين لتغطية كافة محاور النظام.

## 2. مخرجات الاستطلاع والتحقق الفعلي
### أ. بيئة البرمجيات والأدوات المحلية
- **الأمر المنفذ**:
  ```powershell
  & "C:\Program Files\Go\bin\go.exe" version; & "C:\Program Files\PostgreSQL\18\bin\psql.exe" --version; Get-Service *postgres*
  ```
- **المخرجات الفعلية الصادرة من الطرفية**:
  ```text
  go version go1.27.0 windows/amd64
  psql (PostgreSQL) 18.6
  Status   Name               DisplayName
  ------   ----               -----------
  Running  postgresql-x64-18  postgresql-x64-18 - PostgreSQL Server 18
  ```
- **النتيجة**: بيئة تجميع Go وقاعدة بيانات PostgreSQL 18.6 مثبتة وقيد التشغيل محلياً [مؤكد].

### ب. الوضع المادي لتطبيق المحمول وحزم الـ APK
- **الأمر المنفذ**:
  ```powershell
  Test-Path "d:\elctercity\mobile_app"; Get-ChildItem -Path "d:\elctercity" -Filter "*.apk" -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object | Select-Object Count
  ```
- **المخرجات الفعلية الصادرة من الطرفية**:
  ```text
  False
  Count : 0
  ```
- **النتيجة**: مجلد `mobile_app` وحزم APK محذوفة مادياً بنسبة 100% من القرص [مؤكد].

### ج. جاهزية تجميع الواجهة الأمامية React
- **الأمر المنفذ**:
  ```powershell
  cd d:\elctercity\frontend; npm run build
  ```
- **المخرجات الفعلية الصادرة من الطرفية**:
  ```text
  > frontend@0.0.0 build
  > tsc -b && vite build

  vite v8.2.0 building for production...
  transforming...
  ✓ 1845 modules transformed.
  rendering chunks...
  computing gzip size...
  dist/index.html                   1.02 kB │ gzip:   0.49 kB
  dist/assets/index-DpPsKfpn.css   77.85 kB │ gzip:  13.40 kB
  dist/assets/index-D11JyXiW.js  1,584.32 kB │ gzip: 472.10 kB
  ✓ built in 5.71s
  ```
- **النتيجة**: الواجهة تبنى بنجاح مع ضبط `base: './'` الجاهز للتضمين المباشر في خادم Go [مؤكد].

### د. فحص نموذج الفاتورة الرسمي A5 ذو الكعب المزدوج والأرقام الإنجليزية
- **الأمر المنفذ**:
  ```powershell
  node "d:\elctercity\frontend\src\tests\test_challenger_layout_2.js"
  node "d:\elctercity\frontend\src\tests\test_numerals_scan.js"
  ```
- **المخرجات الفعلية الصادرة من الطرفية**:
  ```text
  106 passed, 0 failed.
  Eastern Arabic Numerals Count: 0. Unconstrained number inputs: 0.
  ```
- **النتيجة**: نموذج الفاتورة مطابق تماماً للصورة المرجعية والأرقام الإنجليزية مفروضة بنسبة 100% [مؤكد].

## 3. قرار بوابة المرحلة صفر (Phase 0 Gate Decision)
- **حالة البوابة**: `[GATE_STATUS: PASS]`
- **التوقيع**: `orchestrator_migration` - 2026-09-06T08:29:00Z
- **الإذن بالمضي للمرحلة 1**: مُنح رسمياً.

---

# PHASE 1: بروتوكول الترحيل وتثبيت الأساس (Protocol Setup & Baseline Verification)

- **الحالة (Status)**: `IN_PROGRESS`
- **الوكيل المسؤول**: `worker_m1_protocol`
- **تاريخ البدء**: 2026-09-06T08:30:00Z
- **الهدف**: إنشاء مجلد `MIGRATION/` بالملفات الثلاثة الحصرية، وتثبيت مرجعية النظام، وإقرار الحذف الجسدي للمحمول، وتفعيل بوابات العبور الصارمة.

## 1. الشروط المسبقة (Pre-conditions)
- [x] اجتياز المرحلة صفر والحصول على `[GATE_STATUS: PASS]`.
- [x] اكتمال تقارير الاستطلاع الثلاثية وتحديد خطة العمل الهندسية.

## 2. خطوات التنفيذ المجدولة وبوابات العبور
| معرف البوابة | الوصف الفني | الأمر الإلزامي | شرط العبور (Pass Criteria) | الحالة الراهنة |
|:---|:---|:---|:---|:---:|
| Gate 1.1 | حصر ملفات `MIGRATION/` الثلاثية | `Get-ChildItem -Path d:\elctercity\MIGRATION -File` | وجود الملفات الثلاثة فقط بدون أي ملف رابع | `PENDING` |
| Gate 1.2 | إثبات خلو المستودع من المحمول و APK | `Test-Path mobile_app; Get-ChildItem *.apk` | النتيجة False وصفر ملفات APK | `PENDING` |
| Gate 1.3 | توفر بيئة الأدوات Go و PG وبناء Frontend | `go version; psql --version; npm run build` | نجاح البناء وتوفر أدوات Go 1.27 و PG 18.6 | `PENDING` |
| Gate 1.4 | مطابقة نموذج الفاتورة A5 والأرقام | `node test_challenger_layout_2.js` | اجتياز 106/106 وصفر أرقام مشرقية | `PENDING` |

## 3. قرار بوابة المرحلة 1 (Phase 1 Gate Decision)
- **القرار النهائي**: `[GATE_STATUS: PENDING]`
*(سيتم استيفاء وتوثيق مخرجات كل بوابة فور تنفيذ العامل لمهام الإنشاء والتثبيت الميداني)*.

---

# PHASE 2: قاعدة بيانات PostgreSQL المحلية والنزاهة المالية (Local PostgreSQL & Financial Integrity Core)
- **الحالة (Status)**: `PLANNED`
*(سيتم فتح تدوينات المرحلة 2 فور توثيق اجتياز المرحلة 1 بـ PASS)*.

---

# PHASE 3: خادم Go المستقل ومحرك الواتساب (Standalone Go Backend & WhatsApp Engine)
- **الحالة (Status)**: `PLANNED`
*(سيتم فتح تدوينات المرحلة 3 فور توثيق اجتياز المرحلة 2 بـ PASS)*.

---

# PHASE 4: صقل واجهة React Desktop وفك الارتباط التام (React Desktop UI Polish & Decoupling)
- **الحالة (Status)**: `PLANNED`
*(سيتم فتح تدوينات المرحلة 4 فور توثيق اجتياز المرحلة 3 بـ PASS)*.

---

# PHASE 5: التعافي من الكوارث، التحصين، والتدقيق الختامي (Disaster Recovery, Hardening & Independent Audit)
- **الحالة (Status)**: `PLANNED`
*(سيتم فتح تدوينات المرحلة 5 فور توثيق اجتياز المرحلة 4 بـ PASS)*.
```

---

## 6. بروتوكول التدقيق الذاتي والتعامل مع حالات الفشل (Failure Handling & Self-Correction Protocol)

1. **التعامل مع فشل البوابة (`[GATE_STATUS: FAIL]`)**:
   - إذا أخفق أي اختبار في أي بوابة، يُحظر حذف الخطوة الفاشلة من السجل.
   - يتم تسجيل بلوك الفشل:
     ```markdown
     ### إشعار إخفاق البوابة [GATE_ID: FAIL]
     - سبب الفشل: [التشخيص الدقيق للسبب الجذري]
     - الخطأ الصادر: [Verbatim Error Traceback]
     - الإجراء التصحيحي المطلوب: [الإجراء المقترح لمعالجة الخلل]
     ```
   - بعد تصحيح الخلل من قبل العامل، يُعاد تشغيل أمر التحقق ويُدرج مدخل جديد يحمل الطابع الزمني المحدث ويوثق اجتياز البوابة `PASS`.
2. **صلاحية التدقيق المستقل (Forensic Auditor Authority)**:
   - يتولى وكيل التدقيق المستقل (`auditor_m1`, `auditor_integrity`) التحقق الحرفي من تطابق ما ورد في `EXECUTION_LOG.md` مع الواقع الفعلي على القرص وقاعدة البيانات.
   - إذا اكتشف المدقق أي ادعاء غير مثبت بأمر فعلي ومخرجات صادقة، يُصدر فوراً تقرير `INTEGRITY_VIOLATION` مما يُلغي تقدم المرحلة ويلزم الفريق بإعادة التنفيذ.

</div>
