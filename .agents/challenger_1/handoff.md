# تقرير الفحص والتحدي التجريبي — Clean Boot & Blue Screen Challenger

<div dir="rtl">

## 1. Observation (الملاحظات المباشرة والأدلة التجريبية)

تم إجراء فحص تجريبي واختبارات إجهاد عدائية (Adversarial Stress Testing) لنظام التشغيل الذاتي النقي (Clean Boot) وآلية الحماية من الشاشة الزرقاء (0% Blue Screen Fallback) وتكامل محرك Node.js المدمج في إلكترون (`ELECTRON_RUN_AS_NODE=1`).

### أ. فحص بيئة Node المدمجة في إلكترون (`desktop/electron-bin/electron.exe`)
- **الأمر المنفذ**:
  ```powershell
  node -e "const { execFileSync } = require('child_process'); const out = execFileSync('d:/elctercity/desktop/electron-bin/electron.exe', ['-v'], { env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' } }); console.log(out.toString());"
  ```
- **النتيجة التجريبية**:
  - إصدار Node.js المدمج: `v20.18.0` (V8: `12.6.228.30-electron.0`, Electron: `31.7.7`).
  - [مؤكد] الملف التنفيذي `electron.exe` يعمل كمحرك Node.js مستقل بالكامل عند تمرير `ELECTRON_RUN_AS_NODE=1`.

### ب. اكتشاف ثغرة انهيار الخادم القاتلة (Fatal ERR_REQUIRE_ESM Crash)
- **الملفات المعنية**:
  1. `backend/src/services/invoice-renderer.service.ts` (السطر 2)
  2. `backend/src/services/receipt-renderer.service.ts` (السطر 2)
  3. `backend/dist/services/invoice-renderer.service.js` (السطر 8)
  4. `backend/dist/controllers/reading.controller.js` (السطر 6)
  5. `backend/package.json` (السطر 18 والسطر 35: `"type": "commonjs"`, `"puppeteer": "^25.9.0"`)
- **نص الخطأ الصريح عند الإقلاع**:
  ```
  Error [ERR_REQUIRE_ESM]: require() of ES Module d:\elctercity\backend\node_modules\puppeteer\lib\puppeteer\puppeteer.js from d:\elctercity\backend\dist\services\invoice-renderer.service.js not supported.
  Instead change the require of puppeteer.js in d:\elctercity\backend\dist\services\invoice-renderer.service.js to a dynamic import() which is available in all CommonJS modules.
      at c._load (node:electron/js2c/node_init:2:16955)
      at Object.<anonymous> (d:\elctercity\backend\dist\services\invoice-renderer.service.js:8:37)
      at c._load (node:electron/js2c/node_init:2:16955)
      at Object.<anonymous> (d:\elctercity\backend\dist\controllers\reading.controller.js:6:36) {
    code: 'ERR_REQUIRE_ESM'
  }
  ```
- **الملاحظة**: مكتبة `puppeteer` v25 هي حزمة Pure ESM. عند استخدام `import puppeteer from 'puppeteer'` في ملفات CommonJS (`backend/tsconfig.json`), يقوم المترجم بتوليد `require("puppeteer")`. في بيئة Node.js v20.18.0 (المعتمدة داخل `electron.exe`)، يتسبب `require()` على حزمة ESM في رمي استثناء قاتل `ERR_REQUIRE_ESM` أثناء الاستيراد المتزامن لملفات الـ Controller، مما يؤدي إلى موت عملية الخلفية فور تشغيلها قبل فتح منفذ 3000.

### ج. فحص الاستعلام وقاعدة البيانات بالوضع الافتراضي النقي (Zero Env Vars & No .env)
- **الأمر المنفذ**: تشغيل استعلام Prisma Raw عبر `electron.exe` مع مسح كامل لكافة متغيرات البيئة (`DATABASE_URL`, `DATABASE_SSL_CA`, `PORT`, `JWT_SECRET`, `SUPABASE_*`).
- **الكود المنفذ**:
  ```javascript
  const { prisma } = require('d:/elctercity/backend/dist/lib/prisma.js');
  const res = await prisma.$queryRaw`SELECT 1 as test_val, NOW() as current_time`;
  ```
- **النتيجة التجريبية**:
  - `FALLBACK QUERY SUCCESS: [{"test_val":1,"current_time":"2026-09-02T08:32:48.490Z"}]`
  - [مؤكد] نجاح الاتصال بقاعدة بيانات PostgreSQL عبر رابط الاتصال الافتراضي المدمج (`DEFAULT_DATABASE_URL`) مع شهادة SSL الاحتياطية (`certs/prod-ca-2021.crt`).

### د. فحص أصول الواجهة والمسارات النسبية (0% Blue Screen Validation)
- **الملف المفحوص**: `frontend/dist/index.html`
  - السطر 5: `<link rel="icon" type="image/svg+xml" href="./favicon.svg" />`
  - السطر 13: `<script type="module" crossorigin src="./assets/index-DJ0UwaAL.js"></script>`
  - السطر 14: `<link rel="stylesheet" crossorigin href="./assets/index-B9AtThOF.css">`
- **الملاحظة**:
  - تم التحقق من وجود الملفات الفعلية على القرص: `frontend/dist/assets/index-DJ0UwaAL.js` (1,171,973 bytes) و `frontend/dist/assets/index-B9AtThOF.css` (62,049 bytes).
  - استخدام المسارات النسبية تبدأ بـ `./` يضمن تحميل الملفات عبر بروتوكول `file://` دون أي روابط مطلقة معطلة تبدأ بـ `/assets/`.

### هـ. فحص منطق الاحتياط الفوري في إلكترون (`desktop/main.js`)
- **الدوال المفحوصة**:
  1. `getFrontendDistPath()`: تبحث في 7 مسارات مختلفة وتحدد مسار الحزمة المحلية بنجاح في جميع بيئات العمل.
  2. `checkServerReady(url, 4000)`: عند توقف السيرفر، تنتهي المهلة بعد 4 ثوانٍ وتُرجع `false`، مما يفعل دالة `loadOfflineFallbackUI` فوراً.
  3. `did-fail-load`: عند فشل تحميل `http://localhost:3000`، يتم تحويل النافذة فوراً إلى `loadFile('frontend/dist/index.html')` دون ترك الشاشة زرقاء أو بيضاء.
  4. `loadEnvFile()`: تم إخضاع الدالة لمدخلات تالفة ونصوص غير متوافقة (Unicode, unclosed quotes, empty lines, comments) ونجحت في تجاوز كافة الحالات الشاذة دون أي انهيار.

---

## 2. Logic Chain (سلسلة الاستنتاج المنطقي)

1. **الافتراض 1**: تطبيق سطح المكتب Standalone يعتمد على `desktop/electron-bin/electron.exe` مع `ELECTRON_RUN_AS_NODE=1` لتشغيل خادم Express في الخلفية دون الحاجة لتثبيت Node.js خارجي على جهاز العميل.
2. **الملاحظة المباشرة 1**: محرك `electron.exe` هو Node.js v20.18.0.
3. **الملاحظة المباشرة 2**: في Node.js v20، استدعاء `require()` على حزم Pure ESM مثل `puppeteer` v25 يولد خطأ فوري `ERR_REQUIRE_ESM`.
4. **الملاحظة المباشرة 3**: ملف `reading.controller.ts` يستورد `invoice-renderer.service.ts` بشكل متزامن عند بداية التشغيل، مما يُسقط تطبيق الباك إند كاملاً عند الإقلاع.
5. **الاستنتاج 1**: بالرغم من أن واجهة المستخدم React تتحمل الانقطاع وتفتح بوضع الـ Offline Fallback بنسبة 100%، إلا أن وظائف النظام الخلفية (الفوترة، تسجيل الدخول، مزامنة السحابة) ستظل معطلة تماماً على أي جهاز لابتوب جديد بسبب انهيار الـ الباك إند الناتج عن `ERR_REQUIRE_ESM`.
6. **الاستنتاج 2**: الحل البرمجي المطلوب هو تحويل استيراد `puppeteer` في `invoice-renderer.service.ts` و `receipt-renderer.service.ts` إلى Dynamic Import غير متزامن (`await import('puppeteer')`) مع استيراد الأنواع فقط (`import type { Browser } from 'puppeteer'`).

---

## 3. Caveats (التحفظات والحدود)

1. تم اختبار تشغيل الواجهة وحزم الـ Dist على بيئة Windows x64. لم يتم اختبار أنظمة 32-bit (غير مدعومة رسمياً من إلكترون الحديث).
2. فحص اتصال قاعدة البيانات الفعلي يعتمد على وجود اتصال إنترنت أثناء فحص السحابة؛ في حالة عدم وجود إنترنت على الإطلاق، يستمر تطبيق سطح المكتب بالعمل في وضع الواجهة الثابتة (Offline Static UI) بنجاح.

---

## 4. Conclusion (التقييم والقرار النهائي)

**القرار النهائي: REQUEST_CHANGES (مطلوب تعديل برمجي حاسم)**

[مؤكد] نجاح معمارية الـ Offline Fallback للواجهة (0% Blue Screen Rate) وتحقيق كامل متطلبات المسارات النسبية والبيئة الصفرية لقاعدة البيانات.
[مؤكد] وجود خطأ قاتل يمنع الباك إند من الإقلاع في بيئة إلكترون Standalone:
- خطأ `ERR_REQUIRE_ESM` الناتج عن استيراد `puppeteer` v25 المتزامن داخل `backend/src/services/invoice-renderer.service.ts` و `backend/src/services/receipt-renderer.service.ts`.

### التغييرات المطلوبة للإصلاح (Actionable Fix):
1. في `backend/src/services/invoice-renderer.service.ts`:
   - تحويل `import puppeteer from 'puppeteer';` إلى `import type { Browser } from 'puppeteer';`.
   - استخدام `const puppeteer = (await import('puppeteer')).default;` داخل دالة `generateInvoiceImage`.
2. في `backend/src/services/receipt-renderer.service.ts`:
   - تحويل `import puppeteer, { Browser } from 'puppeteer';` إلى `import type { Browser } from 'puppeteer';`.
   - استخدام `const puppeteer = (await import('puppeteer')).default;` داخل دالة `getBrowser`.
3. إعادة بناء الباك إند: `npm run build` في مجلد `backend`.

---

## 5. Verification Method (طريقة التحقق المستقلة)

للتحقق المستقل من الخطأ وإثباته:
1. تشغيل فحص التبعيات تحت بيئة إلكترون:
   ```powershell
   $env:ELECTRON_RUN_AS_NODE="1"
   & "d:\elctercity\desktop\electron-bin\electron.exe" -e "require('puppeteer')"
   ```
   **النتيجة المتوقعة**: يرمي `Error [ERR_REQUIRE_ESM]`.

2. تشغيل استيراد الباك إند الكامل تحت بيئة إلكترون:
   ```powershell
   $env:ELECTRON_RUN_AS_NODE="1"
   & "d:\elctercity\desktop\electron-bin\electron.exe" "d:\elctercity\backend\dist\index.js"
   ```
   **النتيجة المتوقعة**: انهيار فوري في `invoice-renderer.service.js`.

</div>
