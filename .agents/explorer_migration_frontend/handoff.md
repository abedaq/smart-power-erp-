# Handoff Report — Frontend Desktop and Invoicing Surveyor

**Agent**: `explorer_migration_frontend`  
**Recipient**: `orchestrator_migration` (8662d701-dced-4ddd-b545-e2b64c0e3fc2)  
**Date**: 2026-09-06T08:26:00Z  
**Scope**: React Frontend (`frontend/`), UI Architecture, Packaging, Go Embed Compatibility, Dual-Stub A5 Invoicing, English Numerals Enforcement, and Cloud Decoupling.

---

## 1. Observation

1. **إعدادات البناء وتجميع الـ Frontend**:
   - الملف `frontend/package.json` يحدد الحزم الأساسية: React `19.2.8`، Vite `8.2.0`، Tailwind CSS `4.3.3`، React Router `7.18.2`، TanStack React Query `5.101.4`، Axios `1.19.0`.
   - الملف `frontend/vite.config.ts` سطر 7 يحدد: `base: './'`.
   - تنفيذ الأمر `npm run build` في المجلد `frontend/` اجتاز بنجاح تام (Exit Code: 0) في زمن قدره 5.71 ثانية وأنتج المجلد `frontend/dist/` محتوياً على:
     - `dist/index.html` (1,022 بايت)
     - `dist/assets/index-DpPsKfpn.css` (77,847 بايت)
     - `dist/assets/index-D11JyXiW.js` (1,584,316 بايت)
     - الأصول الثابتة والشعارات (`favicon.svg`, `station_logo.png`, `icon.png`).

2. **مطابقة نموذج الفاتورة المعتمد مع الصورة المرجعية `photo_5769554780358381104_y.jpg`**:
   - الصورة المرجعية في `d:\elctercity\photo_5769554780358381104_y.jpg` تُظهر بوضوح فاتورة بحجم A5 أفقي بنظام الكعب المزدوج (Double-Stub):
     - الكوبون الأيمن (كوبون المحصل/المحطة): يمثل حوالي 40% من العرض، يحتوي على ترويسة المحطة (`محطة الضياء لتوليد الطاقة الكهربائية` وهاتف `783270260_736955883`)، بيانات المشترك، عنوان الدورة بالأحمر، جدول مدمج من 5 أعمدة (`ق. السابقة`, `ق. الحالية`, `الفارق`, `متأخرات وغرامات`, `الاجمالي`)، وتوقيعي المحصل والحسابات.
     - الكوبون الأيسر (الفاتورة الأصلية للمشترك): يمثل حوالي 60% من العرض ومفصول بخط رأسي، يحتوي على ترويسة المحطة والهواتف وحساب الإيداع (`3052001225`)، بيانات المشترك ورقم الفاتورة وخط السير، عنوان الدورة بالأحمر، جدول تفصيلي من 7 أعمدة (`ق. السابقة`, `ق. الحالية`, `الفارق`, `اشتراك`, `القيمـة`, `متأخرات`, `الاجمالي`)، ومربع الشروط واللوائح الرسمية الخمسة بنقاط دائرية ولون أحمر، وتوقيعي المحصل والحسابات، وتاريخ الإصدار أسفل اليسار.
   - المكونات `InvoiceModal.tsx` و `InvoicePreviewModal.tsx` و `CyclePrintView.tsx` مطابقة 100% لهذا الهيكل.
   - تشغيل جناح الاختبار `node frontend/src/tests/test_challenger_layout_2.js` أسفر عن نجاح 106 اختبارات من أصل 106 (Zero failures).

3. **فرض الأرقام الإنجليزية (0-9) وإزالة الأسهم**:
   - في `frontend/src/main.tsx` الأسطر 8-19، يوجد معترض لحدث `beforeinput` على مستوى النافذة يقوم بتحويل فوري للأرقام العربية المشرقية والفارسية `[\u0660-\u0669\u06F0-\u06F9]` إلى أرقام إنجليزية ASCII (0-9) قبل إدراجها بالـ DOM.
   - في `frontend/src/index.css` الأسطر 57-115، تم قمع كافة أسهم المتصفح بخصائص `-webkit-appearance: none !important; -moz-appearance: textfield !important;` مع فرض `font-feature-settings: "lnum" 1, "tnum" 1 !important;` على كافة العناصر.
   - مسح الكود بحثاً عن `type="number"` في `frontend/src/` أظهر 0 نتائج في مكونات React (تم تحويل كافة الحقول إلى `type="text"` مع `inputMode="decimal"` أو `inputMode="numeric"`).
   - مسح الكود في `test_numerals_scan.js` أظهر صفر حروف أرقام مشرقية في قوالب الواجهة.

4. **حصر الاعتمادات السحابية المتبقية (Supabase Residues)**:
   - تم رصد استيرادات واستدعاءات لـ `getSupabase` في:
     - `frontend/src/lib/api.ts` (السطر 2 و 56)
     - `frontend/src/context/AuthContext.tsx` (السطور 2، 28، 106، 166)
     - `frontend/src/services/customer.service.ts` (السطر 2 و 17)
     - `frontend/src/services/invoice.service.ts` (السطر 1 و 14)
     - `frontend/src/services/payment.service.ts` (السطر 1 و 12)
     - `frontend/src/services/analytics.service.ts` (السطور 1، 6، 21، 76، 114، 164)
     - `frontend/src/services/audit.service.ts` (السطر 1 و 4)
     - `frontend/src/services/plan.service.ts` (السطر 1 و 13)
     - `frontend/src/services/settings.service.ts` (السطر 1 و 14)
     - `frontend/src/components/StatementModal.tsx` (السطر 3 و 40)
     - `frontend/src/utils/debouncedRealtime.ts` (السطر 3 و 23)

---

## 2. Logic Chain

1. **من الملاحظة 1 (نجاح البناء ووجود `base: './'`)**:
   - بما أن البناء ينتج ملفات ثابتة مستقلة بمسارات نسبية، فإن خادم Go المبني عبر Fiber يمكنه تضمين المجلد `frontend/dist` مباشرة عبر `//go:embed` وتقديمه للمستخدم فور تشغيل `server.exe` بدون الحاجة لتثبيت Node.js أو تشغيل خادمين منفصلين.
2. **من الملاحظة 2 (مطابقة الفاتورة واجتياز 106 اختبارات)**:
   - بما أن نماذج الفواتير في React مطابقة للصورة المرجعية، فإن القالب يمكن استخدامه مباشرة عبر متصفح العميل للطباعة عبر `printElementViaIframe`، كما يمكن استخدام قالبه الـ HTML المتطابق في خادم Go لإنتاج ملفات PDF وصور PNG عالية الدقة عبر `chromedp` دون أي تشويه للحروف العربية.
3. **من الملاحظة 3 (الأرقام الإنجليزية وخلو المكونات من `type="number"`)**:
   - تطبيق المعترض العام `beforeinput` بجانب التنقية في `formatters.ts` وقمع الـ CSS يضمن بشكل قاطع عدم ظهور أي أرقام مشرقية في النظام أو في الفواتير الصادرة.
4. **من الملاحظة 4 (وجود استدعاءات Supabase في طبقة الخدمات)**:
   - بما أن الهدف النهائي هو نظام محلي مستقل 100% (Standalone Offline-First)، فإن بقاء هذه الاستدعاءات يشكل خطراً عند انقطاع الإنترنت (حيث قد تتأخر الطلبات بسبب محاولة الاتصال بـ Supabase أو تفشل العمليات).
   - الحل المباشر هو إزالة هذه المسارات البديلة (Fallbacks) وتوجيه كافة دوال الـ Services حصرياً إلى نقاط نهاية خادم Go المحلي (`/api/*`)، وإلغاء مكتبة `@supabase/supabase-js`.

---

## 3. Caveats

1. **الخطوط غير المتصلة (Offline Fonts)**: في الوقت الحالي يستدعي `index.html` خط `IBM Plex Sans Arabic` من Google Fonts عبر الإنترنت، مع وجود بدائل نظام مدمجة في ويندوز (`Segoe UI`, `Tahoma`). يُستحسن في المرحلة التنفيذية حفظ ملف خط WOFF2 محلياً في `frontend/public/fonts/` لضمان تطابق الخط حتى عند انقطاع الإنترنت تماماً.
2. **مكتبة Baileys / whatsmeow**: الواجهة الأمامية تستدعي نقاط النهاية `/api/whatsapp/*` لإرسال الرسائل وحالة الاتصال؛ الواجهة معزولة تماماً عن مكتبة واتساب ولا تحتاج لأي تعديل بنيوي للتعامل مع محرك Go `whatsmeow` طالما حافظت الـ API على نفس عقود الـ JSON.

---

## 4. Conclusion

1. الواجهة الأمامية React جاهزة هندسياً وبنائياً للتضمين الفوري في خادم Go (`server.exe`).
2. نماذج الفواتير مطابقة تماماً للمواصفات المعتمدة في الصورة `photo_5769554780358381104_y.jpg`.
3. تم حصر كافة الملفات المرتبطة بـ Supabase بدقة متناهية، والمسار التنفيذي واضح تماماً لتصفيرها وتوجيهها إلى خادم Go المحلي.

---

## 5. Verification Method

1. **التحقق من سلامة البناء**:
   ```powershell
   cd d:\elctercity\frontend
   npm run build
   ```
   *المتوقع*: انتهاء البناء بنجاح (Exit code 0) وإنتاج ملفات `frontend/dist/`.

2. **التحقق من مطابقة نموذج الفاتورة والأرقام**:
   ```powershell
   cd d:\elctercity
   node frontend/src/tests/test_challenger_layout_2.js
   node frontend/src/tests/test_routes_and_tabs.js
   ```
   *المتوقع*: اجتياز 106/106 اختبارات لتصميم الفاتورة، واجتياز 33/33 اختباراً لتبويبات ومسارات النظام.

3. **التحقق من خلو المكونات من `type="number"`**:
   ```powershell
   cd d:\elctercity
   node frontend/src/tests/test_numerals_scan.js
   ```
   *المتوقع*: 0 أرقام مشرقية و 0 حقول `type="number"` غير منضبطة.
