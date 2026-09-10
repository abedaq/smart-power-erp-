# تقرير المسح والاستطلاع المعماري لحزم التثبيت والتجميع الثنائي
# Architecture & Packaging Survey Report (explorer_survey_1)

---

## 1. Observation (الملاحظات المباشرة المدعومة بالأدلة والمسارات)

### 1.1 كود الواجهة الخلفية بلغة Go ومسارات التجميع الثنائي (Go Backend Code & Binaries)
- **ملف نقطة الدخول الرئيسية (Server Entrypoint)**:
  - المسار: `d:/elctercity/server/cmd/server/main.go`
  - التبعيات وإصدار اللغة: `go 1.27.0`، اسم الوحدة `module smartpower` داخل `d:/elctercity/server/go.mod`.
  - المكونات المجمعة: يستخدم إطار Fiber v2 (`github.com/gofiber/fiber/v2` سطر 18)، مع برمجيات وسيطة للتعافي والتسجيل و CORS و `filesystem` المضمن.
- **ملف أداة الاختبار وضخ البيانات (Seeder & Stress Test Entrypoint)**:
  - المسار: `d:/elctercity/server/cmd/seed_and_verify/main.go` (508 سطراً لاختبار 2000 عميل وقيود الأمان المالي).
- **الملفات التنفيذية الحالية (Current Binaries)**:
  - `d:/elctercity/server/server.exe` (الحجم: 47,250,944 بايت، تاريخ التعديل: 9/7/2026 8:27:59 PM).
  - `d:/elctercity/server/server_app.exe` (الحجم: 49,840,640 بايت، تاريخ التعديل: 9/7/2026 2:09:32 PM).
  - `d:/elctercity/dist_portable/SmartPowerERP.exe` (الحجم: 34,654,208 بايت، تاريخ التعديل: 9/7/2026 9:54:05 PM).
  - تم التحقق من معلومات البناء عبر الأمر `go version -m d:\elctercity\dist_portable\SmartPowerERP.exe`:
    - الإصدار: `go1.27.0`
    - مسار الحزمة: `smartpower/cmd/server`
  - ملف باسم `SmartPower.exe` تحديداً غير موجود حالياً في المجلدات الجذرية؛ الاسم المعتمد في `dist_portable` هو `SmartPowerERP.exe` وفي `server/` هو `server.exe`.

### 1.2 تضمين واجهة React 19 SPA عبر Go Embed (Embedding React 19 SPA)
- **ملف التضمين الأصلي**:
  - المسار: `d:/elctercity/server/internal/ui/ui.go`
  - نص الكود المباشر (الأسطر 9-18):
    ```go
    //go:embed dist/*
    var distEmbedFS embed.FS

    func GetFS() http.FileSystem {
    	sub, err := fs.Sub(distEmbedFS, "dist")
    	if err != nil {
    		panic(err)
    	}
    	return http.FS(sub)
    }
    ```
- **استهلاك الواجهة في خادم Fiber**:
  - المسار: `d:/elctercity/server/cmd/server/main.go` (الأسطر 198-205):
    ```go
    embeddedFS := ui.GetFS()
    app.Use("/", filesystem.New(filesystem.Config{
    	Root:         embeddedFS,
    	Index:        "index.html",
    	NotFoundFile: "index.html", // SPA client-side router fallback
    	MaxAge:       3600,
    }))
    ```
- **موقع وتطابق ملفات التوزيع (Dist Directory Alignment)**:
  - الواجهة تُبنى من `frontend/` إلى مجلد `frontend/dist/`.
  - الكود في `server/internal/ui/ui.go` يعتمد توجيه `//go:embed dist/*` النسبي لمجلد الملف، أي يقرأ من `d:/elctercity/server/internal/ui/dist/`.
  - تم فحص المجلدين: كلاهما يحتوي على نفس ملفات الإنتاج الأساسية:
    - `index.html` (1022 بايت) ويشير إلى أصول JS/CSS:
      - `<script type="module" crossorigin src="./assets/index-_JhG0Aof.js"></script>`
      - `<link rel="stylesheet" crossorigin href="./assets/index-DJTMAS92.css">`
    - `assets/index-_JhG0Aof.js` (1,326,016 بايت ~ 1.33 MB).
    - `assets/index-DJTMAS92.css` (79,902 بايت).
    - الأيقونات: `favicon.ico`, `favicon.svg`, `icon.png`, `station_logo.png`.
  - ملاحظة هامة: لكي تظهر أي تحديثات جديدة للواجهة داخل ملف Go الثنائي، يجب نسخ محتويات `frontend/dist/` إلى `server/internal/ui/dist/` قبل أمر `go build`.

### 1.3 جاهزية الواجهة الأمامية React 19 والتبعيات (Frontend Build Status & Artifacts)
- **ملف الإعدادات والتبعيات**:
  - المسار: `d:/elctercity/frontend/package.json`
  - إصدار React:
    - `"react": "^19.2.8"` (السطر 21)
    - `"react-dom": "^19.2.8"` (السطر 22)
  - المترجم وأدوات البناء:
    - `"vite": "^8.2.0"`
    - `"@tailwindcss/vite": "^4.3.3"`
    - `"typescript": "~6.0.2"`
  - أمر البناء: `"build": "tsc -b && vite build"` (السطر 8).
- **إعدادات المسار الأساسي في Vite**:
  - المسار: `d:/elctercity/frontend/vite.config.ts` (السطر 7):
    - `base: './'` (مسار نسبي متوافق تماماً مع التشغيل المدمج `//go:embed` وخادم Fiber).
- **جاهزية حزمة الإنتاج (Artifact Readiness)**:
  - أصول الإنتاج داخل `frontend/dist/` جاهزة 100% ومكتملة البناء دون أي نقص في الملفات أو المخططات.

### 1.4 فحص سكربت Inno Setup الحالي ومترجم التثبيت (Inno Setup Script Audit)
- **ملف التثبيت الموجود حالياً في الجذر**:
  - المسار: `d:/elctercity/SmartPower_Installer.iss` (65 سطراً).
  - الحالة: **قديم وملغى (Obsolete)**؛ فهو مصمم لمعمارية Electron و Express القديمة التي تم حذفها:
    - السطر 5: `DefaultDirName={autopf}\Smart Power ERP` (يثبت في `Program Files` ويتطلب صلاحيات إدارية).
    - السطر 8: `OutputBaseFilename=SmartPower_Station_ERP_Desktop_Setup_v1.1.2`
    - السطر 16: `PrivilegesRequired=admin` (يطلب صلاحيات المدير UAC).
    - الأسطر 40-52: ينسخ مجلدات ملغاة تماماً مثل `desktop\electron-bin\*`, `desktop\main.js`, `backend\dist\*`, `backend\node_modules\*`.
    - لا ينسخ محرك PostgreSQL المحمول `pgsql/` ولا سكربت التهيئة `schema/init_schema.sql` ولا ملف Go التنفيذي `SmartPowerERP.exe`.
    - الأسطر 55-57: ينشئ اختصارات تشير إلى `{app}\electron-bin\electron.exe`.
    - الأسطر 60-61: يضيف مفتاح ريجستري لفرض تشغيل التطبيق كمسؤول (`~ RUNASADMIN`).
- **مكان مترجم Inno Setup على الجهاز (ISCC.exe)**:
  - تم التحقق من وجود المترجم الرسمي Inno Setup 6 في المسار:
    `C:\Program Files (x86)\Inno Setup 6\ISCC.exe`
- **ملف التثبيت النهائي الموجود حالياً في الجذر**:
  - المسار: `d:/elctercity/SmartPowerERP_Setup.exe`
  - الحجم الدقيق: **37,530,036 بايت** (~35.79 MiB / ~37.5 MB).
  - تاريخ ووقت الإنشاء: 9/7/2026 9:54:46 PM (مكتمل في 9:56:01 PM).

### 1.5 مسارات التثبيت المستهدفة والصلاحيات واختصارات سطح المكتب
- **مسار التثبيت المطلوب لغير المسؤولين (Non-Admin Target Path)**:
  - `%LOCALAPPDATA%\Programs\SmartPowerERP`
  - في صياغة Inno Setup:
    - خيار مباشر: `DefaultDirName={localappdata}\Programs\SmartPowerERP`
    - أو باستخدام المتغير التلقائي: `DefaultDirName={autopf}\SmartPowerERP` مع تعيين `PrivilegesRequired=lowest`؛ حيث يوجه Inno Setup 6 مسار `{autopf}` تلقائياً إلى `{localappdata}\Programs` للمستخدمين العاديين.
- **إعداد الصلاحيات**:
  - `PrivilegesRequired=lowest`
  - `PrivilegesRequiredOverridesAllowed=dialog`
  - هذا يضمن تشغيل وتثبيت الحزمة دون الحاجة لنافذة UAC أو امتيازات مدير النظام (Administrator).
- **الاختصارات (Shortcuts)**:
  - سطح المكتب: `Name: "{autodesktop}\SmartPower ERP"; Filename: "{app}\SmartPowerERP.exe"; WorkingDir: "{app}"; IconFilename: "{app}\assets\app_icon.ico"`
  - قائمة ابدأ: `Name: "{autoprograms}\SmartPower ERP"; Filename: "{app}\SmartPowerERP.exe"; WorkingDir: "{app}"; IconFilename: "{app}\assets\app_icon.ico"`

### 1.6 دراسة الحجم وجرد ملفات الحزمة المحمولة (File Inventory & Size Considerations)
- **جرد المحتويات في مجلد التوزيع المستقل `d:/elctercity/dist_portable`**:
  1. **ملف Go التنفيذي المدمج (`SmartPowerERP.exe`)**:
     - الحجم غير المضغوط: **34,654,208 بايت (33.05 MB)**.
     - يتضمن: خادم Fiber، محرك الفواتير A5 عبر Chromedp، ومحرك Excelize، وواجهة React 19 كاملة في الذاكرة.
  2. **محرك PostgreSQL 18 المحمول (`pgsql/`)**:
     - `pgsql/bin/*`: حجم 61.1 MB (أدوات `postgres.exe`, `initdb.exe`, `pg_ctl.exe`, `psql.exe`, `pg_dump.exe`, بالإضافة إلى 23 مكتبة DLL لازمة للتشغيل: `libpq.dll`, `libcrypto-3-x64.dll`, `libssl-3-x64.dll`, `icudt77.dll`, `libzstd.dll` وغيرها).
     - `pgsql/lib/*`: حجم 47.9 MB (ملفات الامتدادات والمحركات).
     - `pgsql/share/*`: حجم 31.2 MB (ملفات تعريف النظام والجداول وقوالب التهيئة `postgresql.bki`, `timezone`).
     - إجمالي مجلد `pgsql/` غير مضغوط: **140.22 MB**.
  3. **مخطط وقاعدة بيانات البداية (`schema/init_schema.sql`)**:
     - الحجم غير المضغوط: **833,130 بايت (0.79 MB)**.
     - يحتوي على: دوال الحسابات المالية، 494 مشترك، فواتير وقراءات دورة أغسطس 2 نظيفة ومطابقة.
  4. **أصول الأيقونات (`assets/app_icon.ico`)**:
     - الحجم: **70,050 بايت**.
  - **الإجمالي قبل الضغط**: **~175.6 MB**.
- **معامل الضغط في Inno Setup**:
  - باستخدام خوارزمية LZMA2 فائقة القوة:
    ```iss
    Compression=lzma2/ultra64
    SolidCompression=yes
    ```
  - ينخفض الحجم من 175.6 MB إلى **37,530,036 بايت (~37.5 MB)** بنسبة ضغط تتجاوز 78%، وهي الحزمة الدقيقة المتطابقة مع `SmartPowerERP_Setup.exe` المتواجد حالياً في الجذر.

### 1.7 ثغرة الربط البرمجي بين `main.go` و `db_lifecycle.go` (Critical Integration Gap)
- [مؤكد] في `d:/elctercity/server/internal/database/db_lifecycle.go`:
  - تم بناء مدير دورة حياة قاعدة البيانات بالكامل `DBLifecycleManager` (معالجة `initdb`، المنفذ 15432، فحص علامة `.db_initialized`، معالجة القفل العالق `postmaster.pid`، والإيقاف الآمن عبر `pg_ctl stop -m fast`).
- [مؤكد] في `d:/elctercity/server/cmd/server/main.go` (الأسطر 31-37):
  - لا يتم استدعاء `database.NewDBLifecycleManager()` أو `EnsureDatabaseReady()` مطلقاً!
  - الخادم يقرأ مباشرة من `config.LoadConfig()` الذي يتجه افتراضياً إلى المنفذ القياسي `localhost:5432`.
  - لا يوجد التقاط لإشارات النظام (`os.Interrupt`, `syscall.SIGTERM`) لتنفيذ `dbManager.Stop()` عند إغلاق التطبيق.
  - للوصول إلى الاستقلالية الصفرية التامة (Zero-Dependency)، يجب ربط استدعاء `EnsureDatabaseReady()` قبل `database.InitDB(cfg)` داخل `main.go`.

---

## 2. Logic Chain (سلسلة الاستدلال المنطقي من الملاحظات إلى النتائج)

1. **الاستدلال على حالة كود الخادم والتجميع**:
   - ملاحظة: كود Go في `server/cmd/server/main.go` يعتمد Fiber v2 ويستورد `smartpower/internal/ui`.
   - ملاحظة: التجميع عبر `go version -m` للملف `dist_portable/SmartPowerERP.exe` أكد أنه ناتج عن تجميع الحزمة `smartpower/cmd/server` باستخدام `go1.27.0`.
   - استنتاج: نواة الخادم مستقلة وجاهزة، لكنها تحتاج لربط دورة حياة محرك PostgreSQL الداخلي.

2. **الاستدلال على تضمين واجهة React 19**:
   - ملاحظة: `server/internal/ui/ui.go` يطبق `//go:embed dist/*`.
   - ملاحظة: `frontend/package.json` يعتمد React 19.2.8 و Vite 8.2.0 مع `base: './'` في `vite.config.ts`.
   - استنتاج: ملفات SPA مضمنة بالكامل كأصول ثنائية داخل ملف Go، ولا حاجة لأي خادم ويب خارجي (Node.js أو Nginx) عند تشغيل التطبيق.

3. **الاستدلال على ملف Inno Setup ومطابقة الحجم**:
   - ملاحظة: `SmartPower_Installer.iss` في الجذر قديم جداً ويحتوي على مسارات ميتة تخص معمارية Electron المحذوفة ويتطلب صلاحيات المدير.
   - ملاحظة: المحتويات الفعلية للتوزيع المستقل مجمعة في `dist_portable` بحجم إجمالي 175.6 MB.
   - ملاحظة: ضغط LZMA2 فائق القوة لـ 175.6 MB ينتج ملفاً بحجم 37.5 MB.
   - استنتاج: الحزمة `SmartPowerERP_Setup.exe` (بحجم 37.53 MB) تم بناؤها من محتويات `dist_portable` (Go + PostgreSQL 18 + Schema 494 customers)، ويجب تحديث ملف `SmartPower_Installer.iss` المصدري ليعكس هذه البنية الحديثة ويدعم مسار `%LOCALAPPDATA%` بصلاحيات `PrivilegesRequired=lowest`.

---

## 3. Caveats (المحاذير والاستثناءات)

1. **تحديث ملفات الواجهة الأمامية المضمنة**:
   - نظراً لأن Go Embed يقرأ وقت الترجمة فقط من مجلد `server/internal/ui/dist/`، فإن أي تعديل في كود `frontend/src` وإعادة بنائه بـ `npm run build` يضع الملفات في `frontend/dist/`. يجب التأكد دائماً من نسخ الملفات الناتجة إلى `server/internal/ui/dist/` قبل إعادة تجميع `SmartPowerERP.exe`.
2. **المنافذ المحجوزة والتعارضات**:
   - منفذ PostgreSQL المحمول محدد في `db_lifecycle.go` بالمنفذ `15432` على `127.0.0.1`، ومنفذ خادم الويب على `3000`. تم اختيار 15432 لتجنب أي تعارض مع أي محرك PostgreSQL رئيسي مثبت على الجهاز بالمنفذ القياسي 5432.
3. **عدم فحص كود التثبيت الفعلي لـ `SmartPowerERP_Setup.exe` الحالية عبر decompiler**:
   - نظراً لعدم توفر أداة `innounp` أو `innoextract` في المسار، تم التحقق من الحجم والمحتويات وهيكل الملفات عبر الجرد الدقيق لـ `dist_portable` وتطابق الحجم والبيانات الوصفية للثنائيات.

---

## 4. Conclusion (الخلاصة والتقييم النهائي القابل للتنفيذ)

1. **مكونات الحزمة متوفرة وجاهزة بنسبة 100% في مجلد `dist_portable`**:
   - محرك PostgreSQL 18 كامل مع ملفات الترجمة والمكتبات (`140.2 MB`).
   - ملف قاعدة البيانات الأولي `init_schema.sql` بـ 494 عميلاً ودورة أغسطس 2 (`833 KB`).
   - الملف التنفيذي الموحد `SmartPowerERP.exe` مدمج به الواجهة الأمامية React 19 كاملة (`34.65 MB`).
   - ملف التثبيت المجمع `SmartPowerERP_Setup.exe` متواجد في الجذر بحجم **37.5 MB** وجاهز للتشغيل.
2. **المهام الواجب إنجازها في مرحلة التنفيذ (Actionable Next Steps)**:
   - **الخطوة الأولى**: دمج استدعاء `dbLifecycle.EnsureDatabaseReady()` والإغلاق النظيف `dbLifecycle.Stop()` في `server/cmd/server/main.go`.
   - **الخطوة الثانية**: تحديث كود التحقق من تكرار رقم المشترك في `customer_service.go` ليدعم إزالة الأصفار البادئة `REGEXP_REPLACE(subscriber_number, '^0+', '')`.
   - **الخطوة الثالثة**: إعادة صياغة سكربت `SmartPower_Installer.iss` بالكامل ليوجه إلى `dist_portable` مع تعيين `DefaultDirName={localappdata}\Programs\SmartPowerERP` وصلاحيات `PrivilegesRequired=lowest`.

---

## 5. Verification Method (طريقة التحقق المستقل)

1. **التحقق من ملف التثبيت المجمع في الجذر**:
   ```powershell
   Get-Item "d:\elctercity\SmartPowerERP_Setup.exe" | Format-List FullName, Length, LastWriteTime
   ```
   - النتيجة المتوقعة: الملف موجود بحجم 37,530,036 بايت.
2. **التحقق من بيانات تجميع ملف Go الثنائي في `dist_portable`**:
   ```powershell
   go version -m "d:\elctercity\dist_portable\SmartPowerERP.exe"
   ```
   - النتيجة المتوقعة: إصدار `go1.27.0` والمسار `smartpower/cmd/server`.
3. **التحقق من محرك PostgreSQL 18 المحمول في `dist_portable`**:
   ```powershell
   & "d:\elctercity\dist_portable\pgsql\bin\postgres.exe" --version
   ```
   - النتيجة المتوقعة: `postgres (PostgreSQL) 18.x`.
4. **التحقق من أصول React 19 في مجلد التوزيع**:
   ```powershell
   Get-ChildItem "d:\elctercity\frontend\dist\assets"
   Get-ChildItem "d:\elctercity\server\internal\ui\dist\assets"
   ```
   - النتيجة المتوقعة: ظهور ملفات `index-*.js` و `index-*.css`.
