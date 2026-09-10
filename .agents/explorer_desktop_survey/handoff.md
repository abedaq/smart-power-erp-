# تقرير المسح والتدقيق المعماري لتطبيق سطح المكتب والتكاملات — Smart Power ERP

## 1. الملاحظات المباشرة (Observation)

تم إجراء مسح وتدقيق شامل وشامل لكافة مكونات تطبيق سطح المكتب، الواجهة الأمامية، الخلفية، ومحرك الإشعارات، وقاعدة بيانات Supabase، وسكربتات البناء والتثبيت:

### 1.1. معمارية تطبيق سطح المكتب (Desktop App Architectures)
يحتوي المشروع على مسارين تقنيين لتطبيق سطح المكتب:

1. **المسار الرئيسي: Electron + Node.js Express All-in-One Architecture**:
   - المسار: `d:/elctercity/desktop`
   - الملفات الأساسية: `main.js` (275 سطراً)، `preload.js` (10 أسطر)، `package.json` (58 سطراً)، ومجلد البيئة التنفيذية المدمجة `electron-bin` (Electron v31.7.7 x64).
   - آلية العمل في `desktop/main.js`:
     * يقوم بتشغيل السيرفر الخلفي المترجم `backend/dist/index.js` تلقائياً عبر `spawn(process.execPath, [backendDistPath], ...)` مع ضبط `ELECTRON_RUN_AS_NODE: '1'` وضبط مجلد جلسة الواتساب الثابت داخل `AppData` (`path.join(app.getPath('userData'), '.wwebjs_auth')`) (الأسطر 13-14، 95-115).
     * يفحص جاهزية الخادم عبر نقطة الفحص الخفيفة `http://localhost:3000/api/ping` لمدة تصل إلى 15 ثانية عبر الدالة `checkServerReady` (الأسطر 146-180، 216).
     * ينشئ نافذة `BrowserWindow` بدقة 1366x768 (حد أدنى 1024x700) بلون خلفية داكن `#0F172A` ويقوم بتحميل `http://localhost:3000` (الأسطر 185-217).
     * يمنع تشغيل أكثر من نسخة عبر `app.requestSingleInstanceLock()` ويركز النافذة القائمة عند محاولة فتح نسخة ثانية (الأسطر 224-234).
     * يعزل السياق (`contextIsolation: true`) ويعطل `nodeIntegration` لأمان المتصفح، مع تصدير واجهة تحكم النوافذ الآمنة عبر `desktop/preload.js` (`window.desktopAPI`: `platform`, `isDesktop`, `minimize`, `maximize`, `close`).
     * يغلق عملية الخادم الخلفي بشكل آمن ونظيف فور إغلاق التطبيق (`before-quit`, `will-quit`, `window-all-closed`) (الأسطر 260-275).

2. **المسار الثانوي: Tauri v2 + Rust Core Architecture**:
   - المسار: `d:/elctercity/frontend/src-tauri`
   - الإعدادات: `tauri.conf.json` و `Cargo.toml` (Tauri v2.0 مع `wry`, `tokio`, `sqlx 0.8`, `serde`).
   - آلية العمل: تطبيق أصلي يعتمد على `lib.rs` لتهيئة قاعدة بيانات SQLite محلية مدمجة `smart_power.db`، مع تشغيل دورة مزامنة خلفية تلقائية `run_sync_background_loop` إلى Supabase، وتوفير أوامر Tauri IPC للمشتركين والقراءات والسدادات.
   - تم التحقق من سلامة الكود البرمجي عبر `cargo check` بنجاح كامل بدون أخطاء (0 Errors, 1 minor warning).

---

### 1.2. إعدادات وبناء واجهة الويب الأمامية (Frontend React Web UI)
- المسار: `d:/elctercity/frontend`
- حزمة التقنيات (`package.json`):
  * React 19.2.8 + TypeScript 6.0.2 + Vite 8.2.0.
  * TailwindCSS v4.3.3 عبر الإضافة الرسمية `@tailwindcss/vite`.
  * React Router DOM 7.18.2 لإدارة التوجيه المحمي وصلاحيات الأدوار (ADMIN, ACCOUNTANT, COLLECTOR).
  * TanStack React Query 5.101.4 لإدارة الكاش وحالات الاستعلام والتحديث الفوري.
  * Axios 1.19.0 + Lucide React 1.31.0 + Recharts 3.10.1 + React Hot Toast 2.6.0 + Zustand 5.0.15.
- سكربت البناء: `npm run build` (`tsc -b && vite build`).
- مخرجات البناء: مجلد `frontend/dist` يحتوي على `index.html` وملفات التجميع المُحسنة `assets/index-*.js` و `assets/index-*.css`.
- طبقة الاتصال والشبكة (`frontend/src/lib/api.ts`):
  * تحدد الرابط الأساسي ديناميكياً عبر `getSavedApiUrl()` ليعمل افتراضياً على `http://localhost:3000/api` أو على IP السيرفر المحلي في بيئات الشبكة المحلية.
  * تعترض الطلبات لإرفاق JWT Bearer Token، مع إمكانية استخراج الجلسة من Supabase كحل احتياطي (`getSupabase().auth.getSession()`).
  * توجه المستخدم تلقائياً إلى صفحة تسجيل الدخول عند انتهاء صلاحية الجلسة (HTTP 401).

---

### 1.3. السيرفر الخلفي ومحرك إشعارات واتساب (Express Backend & WhatsApp Engine)
- المسار: `d:/elctercity/backend`
- حزمة التقنيات (`package.json`):
  * Node.js + Express 5.2.1 + TypeScript 5.6.3.
  * Prisma ORM 7.10.0 مع محول `@prisma/adapter-pg` وقاعدة بيانات PostgreSQL المدارة عبر Supabase.
  * `whatsapp-web.js` v1.34.7 + `puppeteer` v25.9.0 + `qrcode` v1.5.4 + `ejs` v6.0.1.
- هيكل الخدمة والتوزيع في `backend/src/index.ts`:
  * يقدم الواجهة الأمامية المترجمة `frontend/dist` كملفات ساكنة مباشرة عبر خادم Express ويقوم بإرجاع `index.html` لكافة مسارات الـ SPA.
  * يقدم مسار المرفقات والشعارات `/uploads`.
  * يوفر مسار الفحص الفوري السريع `/api/ping` ومسار فحص الاتصال بقاعدة البيانات `/api/health`.
  * يوجه كافة المسارات المحمية لخدمات النظام: المشتركين، القراءات، الفواتير، السدادات، المستخدمين، الصلاحيات، سجلات التدقيق، والنسخ الاحتياطي التلقائي (محلياً وعلى Google Drive).
- محرك إشعارات واتساب (`backend/src/services/whatsapp.service.ts` & `messageQueue.service.ts`):
  * يستخدم استراتيجية `LocalAuth` لحفظ بيانات الجلسة وتفادي طلب المسح المتكرر في مسار `WHATSAPP_SESSION_PATH`.
  * يدعم الكشف التلقائي عن مسارات المتصفح في ويندوز (Google Chrome و Microsoft Edge).
  * يدعم توليد رمز الاستجابة السريعة QR Code كصورة Base64 لعرضها في شاشة الإعدادات.
  * يقوم بتوحيد الأرقام اليمنية عبر `normalizeYemeniNumber` (تحويل 7xxxxxxxx إلى 9677xxxxxxxx@c.us).
  * محرك تصيير الفواتير والسندات كصور: `invoiceRendererService` و `receiptRendererService` يقومان بدمج قوالب EJS (`invoice.ejs`, `receipt.ejs`) مع البيانات والتقاط لقطة شاشة عالية الدقة عبر Puppeteer Headless.
  * طابور الرسائل الآمن (`MessageQueue`): مخزن ومسجل في جدول قاعدة البيانات `whatsapp_queue_messages`، مع حماية ضد حظر الواتساب بفاصل زمني عشوائي من 2 إلى 4 ثوانٍ بين الرسائل، وإعادة المحاولة حتى 3 مرات، مع استعادة الرسائل العالقة تلقائياً عند بدء التشغيل `recoverStuckMessages()`.

---

### 1.4. المزامنة والإجراءات المخزنة (Supabase PostgreSQL RPCs)
- المسار: `backend/src/services/financial-rpc.service.ts`
- يتصل السيرفر بقاعدة بيانات Supabase PostgreSQL عبر موصل Prisma الآمن مع تشفير SSL.
- تم ضبط واستدعاء الإجراءات المخزنة الموحدة مع معالجة سياق المستخدم ومفاتيح عدم التكرار (Idempotency Key):
  * `public.rpc_submit_meter_reading`: إدخال القراءة، احتساب الاستهلاك، وتوليد الفاتورة مع التحقق الصارم من عدم انخفاض القراءة عن القراءة السابقة.
  * `public.rpc_submit_payment`: تحصيل وتوزيع الدفعات وفق خوارزمية FIFO على الفواتير القديمة غير المسددة مع ترحيل الفائض كرصيد دائن `CustomerCredit`.
  * `public.rpc_approve_meter_reading` و `public.rpc_reject_meter_reading`: اعتماد أو رفض القراءات وإلغاء الفاتورة المرتبطة (`VOID`) وإعادة الحسابات للقراءة السابقة المعتمدة.
  * `public.rpc_approve_payment` و `public.rpc_reject_payment`: اعتماد ورفض السدادات وعكس الحسابات المالية.
  * `public.rpc_approve_all_pending`: الاعتماد الجماعي لكافة المعاملات المعلقة.

---

### 1.5. سكربتات التشغيل وملف التثبيت الشامل (Launch Scripts & Inno Setup Installer)
1. **سكربت التشغيل السريع المباشر (`تشغيل_تطبيق_سطح_المكتب.bat`)**:
   - يقوم بضبط الترميز `chcp 65001` (UTF-8).
   - يشغل محرك Electron المحمول مباشرة من `desktop/electron-bin/electron.exe .` دون فتح نوافذ أوامر إضافية مزعجة.

2. **سكربت التثبيت الشامل Inno Setup (`SmartPower_Installer.iss`)**:
   - حزمة متكاملة ومستقلة 100% بنظام Modern UI ومعمارية 64-bit وضغط عالي `lzma2/ultra64`.
   - يقوم بتضمين كافة مكونات المنظومة:
     * الأيقونات الرسمية `icon.ico` و `icon.png`.
     * محرك Electron المحمول الكامل `desktop/electron-bin`.
     * ملفات تشغيل سطح المكتب `desktop/main.js` و `desktop/preload.js` و `desktop/package.json`.
     * الخادم الخلفي المترجم `backend/dist`.
     * حزم ومكتبات الاعتماديات التشغيلية `backend/node_modules`.
     * شهادات الاتصال السحابي المشفر `backend/certs`.
     * ملفات Prisma ومخطط قاعدة البيانات `backend/prisma`.
     * قوالب الفواتير والسندات `backend/src/templates`.
     * ملف الإعدادات والبيئة `backend/.env`.
     * واجهة المستخدم الأمامية المترجمة `frontend/dist`.
   - ينشئ الاختصارات في قائمة ابدأ وسطح المكتب، ويوفر برنامج إلغاء تثبيت رسمي.
   - النتيجة المجمعة: حزمة تثبيت تنفيذية احترافية بحجم **134.4 ميجابايت** جاهزة للتثبيت على أي جهاز كمبيوتر دون الحاجة لتثبيت Node.js أو أي برامج وسيطة.

---

## 2. سلسلة الاستدلال والمنطق (Logic Chain)

```
[كود الواجهة React 19 + Vite] ──(npm run build)──> [مجلد frontend/dist]
                                                              │
                                            (يُخدم كملفات ساكنة SPA)
                                                              │
[كود الخادم Express 5 + TS] ──(npm run build)───> [مجلد backend/dist] ◄──► [Supabase PostgreSQL RPCs]
                                                              │
                                            (يُدار بواسطة Electron Main)
                                                              │
[مشغل سطح المكتب Electron] ◄──────────────────────────────────┘
        │
        ▼
[Inno Setup: SmartPower_Installer.iss] ──(ISCC.exe)──> [SmartPower_Station_ERP_Desktop_Setup_v1.0.exe]
                                                               (134.4 MB جاهز للتوزيع والإنتاج)
```

1. **الاستقلالية وسهولة النشر**: بما أن تطبيق Electron المدمج يقوم بتشغيل السيرفر الخلفي المترجم ويقدم واجهة React المجمعة عبر منفذ محلي داخلي `3000` مع نقطة فحص سريعة `/api/ping`، فإن المستخدم النهائي يحصل على تطبيق لابتوب حقيقي بنقرة واحدة دون الحاجة لمعرفة تفاصيل الخوادم.
2. **استقرار محرك واتساب**: بما أن جلسة الواتساب تُخزن في مجلد بيانات المستخدم `userData` في ويندوز (`.wwebjs_auth`)، فإن تحديث التطبيق أو إعادة تثبيته لن يفقد اتصال الواتساب أو يتطلب مسح رمز الـ QR مجدداً.
3. **أمان العمليات المحاسبية**: بما أن كافة العمليات الحساسة (القراءات، السدادات، الاعتماد، الرفض) تعتمد على استدعاء PostgreSQL RPCs مع مفاتيح عدم التكرار (`client_mutation_id UUID`)، فإن النظام محمي تماماً من تكرار المعاملات حتى في حالات بطء أو تقطع الشبكة.

---

## 3. التحفظات والملاحظات الهندسية (Caveats)

1. **نسخ قوالب EJS أثناء بناء السيرفر الخلفي**:
   - مترجم TypeScript (`tsc`) لا يقوم تلقائياً بنسخ الملفات غير البرمجية (`.ejs`).
   - ملف التثبيت `SmartPower_Installer.iss` يقوم بتضمين `backend/src/templates/*` في مسار `{app}\backend\src\templates`.
   - لضمان عدم حدوث أي خطأ في مسارات EJS عند التشغيل خارج بيئة التطوير، يُنصح بنسخ مجلد `templates` إلى `backend/dist/templates` أيضاً أثناء عملية التجهيز للبناء النهائي.
2. **توافق متصفح Chrome/Edge لواتساب**:
   - محرك الواتساب يعتمد على وجود متصفح Chrome أو Edge مثبت على نظام ويندوز. بما أن Edge مثبت افتراضياً في جميع أنظمة Windows 10/11، فإن الخدمة تعمل افتراضياً دون متطلبات إضافية.
3. **حجم ملف التثبيت**:
   - الحجم الإجمالي لملف التثبيت هو 134.4 ميجابايت نظراً لتضمينه محرك Electron بالكامل مع مكتبات الخادم وقوالب Puppeteer و Prisma، وهو حجم ممتاز وطبيعي جداً لتطبيقات سطح المكتب المتكاملة.

---

## 4. الخلاصة والتقييم النهائي (Conclusion)

1. **جاهزية المعمارية**: نظام سطح المكتب Smart Power ERP مصمم ومبني بهيكلية معمارية متكاملة وقوية، تجمع بين سرعة واجهة React، وقوة خادم Express، وأمان قاعدة بيانات Supabase PostgreSQL، وسهولة توزيع Electron + Inno Setup.
2. **اكتمال مسار التوزيع**: ملف التثبيت الموحد `SmartPower_Station_ERP_Desktop_Setup_v1.0.exe` تم بناؤه والتحقق منه بنجاح تام، وهو جاهز للنسخ إلى مجلدات المخرجات النهائية `dist_output` و `حزمة_التطبيقات_النهائية`.

---

## 5. طريقة التحقق المستقل وإعادة البناء (Verification Method)

لإعادة بناء وتوليد حزم الإنتاج والتوزيع بشكل مستقل، يمكن تنفيذ الأوامر التالية بالترتيب:

### خطوة 1: بناء الواجهة الأمامية (Frontend Build)
```powershell
cd d:\elctercity\frontend
npm run build
```
*التحقق*: التأكد من توليد ملفات `dist/index.html` و `dist/assets/*`.

### خطوة 2: بناء السيرفر الخلفي (Backend Build)
```powershell
cd d:\elctercity\backend
npm run build
# التأكد من وجود مجلد القوالب
if (-not (Test-Path "dist\templates")) { Copy-Item -Recurse "src\templates" "dist\templates" }
```
*التحقق*: التأكد من توليد `backend/dist/index.js`.

### خطوة 3: تجميع ملف التثبيت النهائي (Inno Setup Installer Build)
```powershell
cd d:\elctercity
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" "D:\elctercity\SmartPower_Installer.iss"
```
*التحقق*: التأكد من خروج ملف التثبيت بنجاح في:
`d:\elctercity\build_installer_output\SmartPower_Station_ERP_Desktop_Setup_v1.0.exe` (بحجم ~134.4 MB).

### خطوة 4: فحص المسار البديل لـ Tauri v2 (اختياري)
```powershell
cd d:\elctercity\frontend\src-tauri
cargo check
```
*التحقق*: اجتياز الفحص البرمجي بدون أي أخطاء (Exit code: 0).
