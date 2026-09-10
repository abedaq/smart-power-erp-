# تقرير الفحص والمسح المعماري للواجهة الأمامية (Frontend Architectural Survey)

**تاريخ الفحص**: 2026-09-06T08:25:00Z  
**المستكشف الفاحص**: `explorer_migration_frontend` (Frontend Desktop and Invoicing Surveyor)  
**المشروع المستهدف**: Smart Power ERP — React Desktop / Web (`frontend/`)  
**المحطة المعتمدة**: محطة الضياء لتوليد الطاقة الكهربائية  

---

## 1. الملخص التنفيذي والنتائج الجوهرية (Executive Summary)

أجري فحص فني شامل وميداني لكود الواجهة الأمامية React في المجلد `frontend/`، وشمل الفحص المعماري:
1. **جاهزية التجميع والتضمين في Go (`//go:embed`)**:
   - مشروع الواجهة مبني باستخدام **React 19.2.8** و **Vite 8.2.1** و **Tailwind CSS v4.3.3** مع TypeScript 6.0.2.
   - أمر التجميع `npm run build` (`tsc -b && vite build`) يعمل بنجاح تام وبدون أي أخطاء (Zero errors) خلال 5.71 ثانية.
   - ملف الإعداد `frontend/vite.config.ts` مُهيّأ مسبقاً بالقيمة `base: './'`، مما يضمن أن كافة روابط الملفات الثابتة (`assets/index-*.js`, `assets/index-*.css`, `favicon`, `logo`) تُستدعى بمسارات نسبية، وهي جاهزة تماماً للتضمين المباشر في خادم Go المترجم (`server.exe`) عبر توجيه `//go:embed all:dist/*`.
2. **مطابقة نموذج الفاتورة المعتمد (Double-Stub A5 Layout)**:
   - تم فحص الصورة المرجعية الرسمية `d:\elctercity\photo_5769554780358381104_y.jpg` ومطابقتها حرفياً وبصرياً مع المكونات:
     - `frontend/src/components/common/InvoiceModal.tsx`
     - `frontend/src/components/InvoicePreviewModal.tsx`
     - `frontend/src/components/CyclePrintView.tsx`
     - `frontend/src/components/PaymentModal.tsx`
   - التصميم المعتمد يعتمد نظام الكعب المزدوج (Col-5 للكوبون الأيمن الخاص بالمحصل، و Col-7 للفاتورة الأصلية لليسار الخاصة بالمشترك)، محاط بإطار أسود عريض، متضمناً شعار المحطة، وأرقام الهواتف الرسمية (`783270260_736955883`)، ورقم الحساب البنكي للإيداع (`3052001225`)، واسم الدورة باللون الأحمر، وجدول القراءات والتسعير، وبنود الشروط الرسمية الخمسة باللون الأحمر، وتواقيع المحصل والحسابات، وتاريخ الإصدار أسفل اليسار.
   - جميع الاختبارات الآلية المعيارية (106 اختبارات في `test_challenger_layout_2.js`) اجتازت بنجاح بنسبة 100%.
3. **التطبيق الصارم للأرقام الإنجليزية (0-9) وإزالة الأسهم كلياً**:
   - تم التحقق من خلو كود الواجهة الأمامية تماماً من أي حقول غير منضبطة بنوع `type="number"` (Zero instances في مكونات React).
   - تم التحقق من تصفية المتصفح في `frontend/src/index.css` لقمع كافة أسهم الرفع والخفض (`-webkit-appearance: none`, `-moz-appearance: textfield`).
   - يوجد معترض عام على مستوى نافذة المتصفح `document.addEventListener('beforeinput')` في `frontend/src/main.tsx` يقوم بتحويل فوري وتلقائي لأي أرقام عربية مشرقية (٠-٩) أو فارسية (۰-۹) إلى أرقام إنجليزية (0-9) قبل إدراجها في شجرة الـ DOM.
   - كافة دوال التنسيق المالي والتواريخ في `formatters.ts` مفروضة بصيغة `en-US` (`toLocaleString('en-US')`) مع تفعيل خصائص الخط `font-feature-settings: "lnum" 1, "tnum" 1` عبر الـ CSS العام.
4. **العزل التام عن السحابة وإزالة بقايا Supabase (Cloud Decoupling)**:
   - كشف الفحص وجود بقايا واستدعاءات احتياطية (Fallbacks) لمكتبة Supabase في عدد من ملفات الخدمات (`services/*.ts`) وملف `AuthContext.tsx` ومكون `StatementModal.tsx` ومراقب الاشتراكات `debouncedRealtime.ts`.
   - لتشغيل النظام كبرنامج مكتبي محلي مستقل (Standalone Desktop) بنسبة 100% وبدون أي اعتماد على خوادم خارجية أو إنترنت، يجب تحويل كافة هذه الاستدعاءات لتتصل حصرياً بنقاط النهاية المحلية في خادم Go (`http://localhost:3000/api` أو مسار نسبي `/api`) وإلغاء قنوات الـ Realtime السحابية واستبدالها بنمط React Query Event-Driven Invalidation.

---

## 2. المسح المعماري التفصيلي للواجهة الأمامية (Detailed Frontend Survey)

### 2.1 بنية الحزم والمكتبات (Stack & Dependencies)
| المكون / المكتبة | الإصدار | الوظيفة والملاحظات |
| :--- | :--- | :--- |
| **React** | `19.2.8` | أحدث إصدار رئيسي مع دعم React Server/Client paradigms |
| **Vite** | `8.2.1` | محرك البناء فائق السرعة مع إضافة `@vitejs/plugin-react: ^6.0.4` |
| **Tailwind CSS** | `4.3.3` | الإصدار الرابع الحديث عبر `@tailwindcss/vite` داخل `vite.config.ts` |
| **React Router** | `7.18.2` | موجه الصفحات (`BrowserRouter`) مع توجيه الصلاحيات والحماية |
| **TanStack React Query** | `5.101.4` | إدارة الحالة البعيدة والتخزين المؤقت للبيانات (Cache & Mutations) |
| **Axios** | `1.19.0` | عميل الـ HTTP لطلبات الـ REST API |
| **Lucide React** | `1.31.0` | حزمة الأيقونات الموحدة |
| **XLSX (SheetJS)** | `0.18.5` | استيراد وتصدير ملفات الإكسل محلياً في المتصفح |
| **Zustand** | `5.0.15` | إدارة الحالة العامة الخفيفة |
| **@supabase/supabase-js** | `2.112.3` | **حزمة سحابية متبقية** — سيتم إيقاف استدعائها بالكامل |

### 2.2 إعدادات البناء والتضمين في Go (Build Target & Embedding Compatibility)
- ملف `frontend/vite.config.ts`:
  ```typescript
  import { defineConfig } from 'vite'
  import react from '@vitejs/plugin-react'
  import tailwindcss from '@tailwindcss/vite'

  export default defineConfig({
    base: './',
    plugins: [react(), tailwindcss()],
  })
  ```
- مخرجات التجميع في `frontend/dist/`:
  - `dist/index.html` (1.02 KB)
  - `dist/assets/index-DpPsKfpn.css` (77.84 KB)
  - `dist/assets/index-D11JyXiW.js` (1,584.31 KB)
  - أيقونات وشعارات ثابتة: `favicon.ico`, `favicon.svg`, `station_logo.png`, `icon.png`.
- **توافق Go Embed**:
  - لأن `base: './'`، فإن مسارات الاستدعاء داخل `index.html` هي `./assets/index-D11JyXiW.js` و `./assets/index-DpPsKfpn.css`.
  - عند تضمين هذا المجلد داخل Go عبر:
    ```go
    //go:embed all:frontend/dist/*
    var distFS embed.FS
    ```
    يمكن لخادم Go Fiber تقديم المجلد مباشرة كملفات ثابتة، مع معالج Fallback لـ SPA:
    ```go
    app.Use("/", filesystem.New(filesystem.Config{
        Root: http.FS(distFS),
        PathPrefix: "frontend/dist",
        Index: "index.html",
    }))
    app.Get("/*", func(c *fiber.Ctx) error {
        file, _ := distFS.ReadFile("frontend/dist/index.html")
        c.Set("Content-Type", "text/html")
        return c.Send(file)
    })
    ```
  - هذا التصميم يضمن تشغيل البرنامج المكتبي فوراً عبر فتح المتصفح المحلي على `http://localhost:3000` أو تشغيله عبر نافذة Webview مدمجة.

### 2.3 موجه الصفحات والتبويبات (Routing & Page Architecture)
تم فحص `frontend/src/App.tsx` و `Sidebar.tsx`:
1. **صفحة الدخول**: `/login` (`Login.tsx`).
2. **اللوحة الرئيسية**: `/` (`Dashboard.tsx`) — تعرض مؤشرات الأداء اللحظية (KPIs) وسجل العمليات المباشرة لمحصلي الميدان.
3. **إدارة المشتركين**: `/customers` (`Customers.tsx`) — جدول شامل بنمط Excel، تعديل لحظي، بطاقات ملخص، وتسجيل القراءات والسداد.
4. **الفواتير والتحصيل**: `/invoices` (`Invoices.tsx`) — استعراض الدورات، الفواتير المعتمدة، طباعة الكشف التجميعي أو الفردي، والإرسال عبر واتساب.
5. **المديونيات والمتأخرات**: `/arrears` (`ArrearsReport.tsx`) — **تبويب مستقل تماماً**، يحتوي على كروت مؤشرات، تصنيف أعمار الديون، احتساب أيام التأخير (`أيام التأخير`)، زر إرسال الإنذار الرسمي، وإمكانية السداد الفوري المباشر عبر `PaymentModal`.
6. **مركز التقارير الشامل**: `/reports` (`ReportsHub.tsx`) — يجمع 6 تبويبات فرعية: التقارير المالية، استهلاك الطاقة والفاقد، أعمار الديون، مقارنة الدورات، أداء المحصلين، وسجل الرقابة والعمليات.
7. **العدادات غير المقروءة**: `/unread-meters` (`UnreadMeters.tsx`) — رصد العدادات التي لم تقرأ خلال فترة محددة (افتراضياً 15 يوماً).
8. **الإعدادات والتهيئة**: `/settings` (`Settings.tsx`) — إدارة المستخدمين، إعدادات الواتساب، وسجل التدقيق.
9. **المسارات المحذوفة والمُعاد توجيهها**:
   - التعديلات المعتمدة `/approved-edits` -> تُوجّه تلقائياً إلى `/reports`.
   - باقات الاشتراك والتعرفة العامة `/plans` -> محذوفة تماماً من القوائم والتوجيهات.

---

## 3. فحص نموذج الفاتورة الرسمي المعتمد (Double-Stub Invoice Layout)

### 3.1 مطابقة الصورة المرجعية `photo_5769554780358381104_y.jpg`
أظهر فحص الصورة المرجعية ومقارنتها بكود `InvoiceModal.tsx` و `InvoicePreviewModal.tsx` و `CyclePrintView.tsx` الآتي:

```
+---------------------------------------------------------------------------------------------------------------------------------------+
|                                                          الإطار الخارجي الأسود العريض                                                 |
| +--------------------------------------------------------------------+ +------------------------------------------------------------+ |
| |                        الفاتورة الأصلية (للمشترك)                   | |                       كوبون المحصل (للمحطة)                | |
| |                           العرض: ~60%                              | |                            العرض: ~40%                     | |
| |--------------------------------------------------------------------| |------------------------------------------------------------| |
| | [الشعار]  محطة الضياء لتوليد الطاقة الكهربائية                     | | [الشعار]  محطة الضياء لتوليد الطاقة الكهربائية             | |
| |           783270260_736955883                                      | |           783270260_736955883                              | |
| |           يمكنك الإيداع على الحساب 3052001225                      | |                                                            | |
| |--------------------------------------------------------------------| |------------------------------------------------------------| |
| | اسم المشترك: [الاسم]              | رقم الفاتورة: [الرقم]          | | اسم المشترك: [الاسم]                                       | |
| | العنوان: [العنوان]                                                 | | العنوان: [العنوان]                                         | |
| | رقم المشترك: [الرقم]                                               | | رقم المشترك: [الرقم]                                       | |
| | رقم العداد: [الرقم]                | رقم خط السير: [الخط]          | | رقم العداد: [الرقم]                                        | |
| |--------------------------------------------------------------------| |------------------------------------------------------------| |
| |           عنوان الدورة بالأحمر العريض: فاتورة استهلاك كهرباء ...   | |           عنوان الدورة بالأحمر: فاتورة استهلاك كهرباء ...  | |
| |--------------------------------------------------------------------| |------------------------------------------------------------| |
| | قراءة العداد (السابقة - الحالية) | الفارق | اشتراك | القيمة | ...  | | قراءة العداد (السابقة - الحالية) | الفارق | متأخرات | الإجمالي  | |
| | [7 أعمدة مالية متكاملة]                                            | | [5 أعمدة مالية مدمجة]                                      | |
| |--------------------------------------------------------------------| |------------------------------------------------------------| |
| | البنود والشروط الرسمية (5 بنود باللون الأحمر مع نقاط دائرية o)     | |                                                            | |
| |--------------------------------------------------------------------| |------------------------------------------------------------| |
| | المحصل ............                      الحسابات ............     | | المحصل ............              الحسابات ............     | |
| +--------------------------------------------------------------------+ +------------------------------------------------------------+ |
| التاريخ: YYYY/MM/DD (أسفل اليسار)                                                                                                     |
+---------------------------------------------------------------------------------------------------------------------------------------+
```

### 3.2 بنود لائحة المحطة المعتمدة في الفاتورة (Official Policy Clauses)
البنود مطابقة حرفياً في الكود للشروط الواردة في الصورة:
1. `o يتم سداد الفاتورة يوم استلامها او اليوم التالي فقط.`
2. `o في حالة تأخر السداد سيتم فصل التيار دون إشعار مسبق ولن يعاد الا بغرامة.`
3. `o في حال قيام المشترك بتوصيل التيار لشخص آخر سيتم تغريم المشترك مبلغ وقدره 200000 مائتان الف ريال`
4. `o يتحمل المشترك مديونية أي موظف إن لم يكن هناك سند رسمي مختوم بختم المحطة.`
5. `o سعر الكيلوواط/ ساعة 1400 ريال ويرتفع سعر الكيلو بنسبة وتناسب بارتفاع الديزل.`

### 3.3 استراتيجية توليد الـ PDF الآلي عبر خادم Go باستخدام `chromedp`
- **المشكلة في مكتبات Go التقليدية (مثل gofpdf أو maroto)**: لا تدعم تشكيل الحروف العربية (Arabic Text Shaping) ولا خوارزمية الاتجاه الثنائي (BiDi Algorithm) مما يجعل الحروف تظهر مقطعة ومقلوبة.
- **الحل الهندسي المعتمد في Go**:
  - استخدام حزمة `github.com/chromedp/chromedp` للتخاطب مع متصفح Edge المدمج افتراضياً في كل أجهزة ويندوز (`msedge.exe`) دون الحاجة لتثبيت أي برامج إضافية.
  - خادم Go يمتلك قالباً داخلياً للـ HTML مشابهاً لـ `backend/src/templates/invoice.ejs`.
  - يقوم `chromedp` بفتح القالب محلياً بحجم A5 أفقي (A5 Landscape: `210mm x 148mm`) وتشغيل محرك Blink الذي يقوم بتشكيل الحروف العربية والخطوط بدقة 100%.
  - إصدار أمر `page.PrintToPDF()` لتوليد ملف PDF عالي الدقة، أو أمر `chromedp.Screenshot()` لالتقاط صورة PNG فائقة الوضوح لإرسالها مباشرة للمشتركين عبر واتساب بواسطة محرك `whatsmeow`.

---

## 4. التحقق من فرض الأرقام الإنجليزية (0-9) عالمياً

### 4.1 خطوط الدفاع المطبقة في النظام
1. **معترض لوحة المفاتيح واللصق العام (Window-Level `beforeinput` Interceptor)**:
   - في `frontend/src/main.tsx` (السطور 8-19):
     ```typescript
     if (typeof window !== 'undefined') {
       document.addEventListener('beforeinput', (e: any) => {
         if (e.data && /[\u0660-\u0669\u06F0-\u06F9]/.test(e.data)) {
           const normalized = e.data
             .replace(/[\u0660-\u0669]/g, (d: string) => String.fromCharCode(d.charCodeAt(0) - 1632 + 48))
             .replace(/[\u06F0-\u06F9]/g, (d: string) => String.fromCharCode(d.charCodeAt(0) - 1776 + 48));
           
           e.preventDefault();
           document.execCommand('insertText', false, normalized);
         }
       }, true);
     }
     ```
   - هذا المعترض يلتقط أي مدخل قبل وصوله إلى الـ DOM، ويحوله فوراً من أرقام هندية/مشرقية أو فارسية إلى أرقام إنجليزية (0-9).
2. **قمع أسهم المتصفح في `index.css` (Universal Spinner Suppression)**:
   - تم قمع أزرار الأسهم لكافة محركات المتصفحات (`::-webkit-outer-spin-button`, `::-webkit-inner-spin-button`, `-moz-appearance: textfield`, `::-ms-clear`).
3. **تحويل نوع الحقول من `type="number"` إلى `type="text"` مع `inputMode="decimal"`**:
   - تم التأكد من خلو كافة الشاشات (`ExcelGrid.tsx`, `ReadingModal.tsx`, `PaymentModal.tsx`, `Customers.tsx`, `Invoices.tsx`, `ArrearsReport.tsx`) من أي حقول برمجية تستخدم `type="number"`.
4. **دوال التنقية والتنسيق في `formatters.ts`**:
   - دالة `toEnglishDigits(val)` تدعم تحويل مجالات اليونيكود `[\u0660-\u0669]` و `[\u06F0-\u06F9]`.
   - دالة `sanitizeDecimalInput(val)` تضمن تحويل الفواصل العربية وتسمح فقط بالأرقام ونقطة عشرية واحدة.
   - كافة دوال التنسيق المالي مثل `formatNumber` و `formatCurrency` و `formatDate` تستخدم صراحة `locale: 'en-US'`.

---

## 5. خطة فك الارتباط بالسحابة وإلغاء Supabase (Decoupling & Standalone Migration)

### 5.1 حصر كافة الملفات المتبقية التي تستدعي Supabase
| اسم الملف | نوع الاستدعاء المتبقي | الإجراء الهندسي المطلوب لتصفيره |
| :--- | :--- | :--- |
| `frontend/src/lib/api.ts` | استرجاع الـ Token من `getSupabase().auth.getSession()` وسؤال `view_monthly_performance` | استبدال الـ Token بـ Local JWT من Go API، وتوجيه الإحصائيات لـ `/api/analytics/monthly-performance` |
| `frontend/src/lib/supabase.ts` | إنشاء عميل Supabase وتخزين الرابط في LocalStorage | **حذف الملف بالكامل** بعد اكتمال الربط |
| `frontend/src/context/AuthContext.tsx` | تحقق تسجيل الدخول عند فقدان الخادم المحلي عبر `supabase.auth.signInWithPassword` | جعل تسجيل الدخول محلياً 100% عبر `/api/auth/login` و `/api/auth/me` مع حفظ بيانات الجلسة محلياً |
| `frontend/src/services/customer.service.ts` | بلوك Fallback يستعلم جدول `customers` مباشرة من Supabase | إزالة الـ Fallback؛ عند حدوث خطأ يتم إظهار رسالة خطأ صريحة من خادم Go المحلي |
| `frontend/src/services/invoice.service.ts` | بلوك Fallback يستعلم جدول `invoices` مباشرة من Supabase | إزالة الـ Fallback والاعتماد كلياً على `api.get('/invoices')` |
| `frontend/src/services/payment.service.ts` | استعلام جدول `payments` من Supabase عند تعذر الـ API | الاعتماد الحصري على `api.get('/payments')` |
| `frontend/src/services/analytics.service.ts` | استعلام مباشر لـ `view_monthly_performance` و `view_overdue_report` و `view_collector_daily_kpis` | استبدال الاستعلامات بطلبات Go REST API: `/api/analytics/*` |
| `frontend/src/services/audit.service.ts` | استعلام مباشر لـ `audit_logs` عبر Supabase | توجيه الاستعلام إلى `api.get('/audit-logs')` |
| `frontend/src/services/plan.service.ts` | استعلام جدول `subscription_plans` عبر Supabase | الاعتماد على `api.get('/plans')` |
| `frontend/src/services/settings.service.ts` | استعلام جدول `system_settings` عبر Supabase | الاعتماد على `api.get('/settings')` |
| `frontend/src/components/StatementModal.tsx` | Fallback لجلب القراءات والفواتير والسداد من Supabase | الاعتماد على `getCustomerById(id)` القادم من خادم Go |
| `frontend/src/utils/debouncedRealtime.ts` | فتح قنوات WebSocket مع Supabase Realtime لتحديث الواجهات | استبداله بتحديثات React Query التلقائية عند إتمام العمليات (Mutation Invalidation) مع إمكانية إضافة SSE/WebSocket محلي من Go |

### 5.2 تهيئة الـ API Base URL للتشغيل المكتبي
- في بيئة الـ Standalone حيث يقوم خادم Go (`server.exe`) بخدمة الـ Frontend المترجم والـ API معاً:
  - المنفذ الموحد هو `3000`.
  - عنوان الـ API يمكن أن يكون نسبياً ببساطة: `/api`.
  - عند استخدام `/api` كـ `baseURL` في Axios، يعمل التطبيق بسلاسة تامة سواء فُتح عبر المتصفح على `http://localhost:3000` أو عبر IP الشبكة المحلية أو عبر أي منفذ يتم ضبطه في الخادم مستقبلاً بدون أي تعارض في الـ CORS.

---

## 6. خطة التحقق والجاهزية (Readiness & Next Steps)

1. الواجهة الأمامية مبنية وخالية من الأخطاء وجاهزة للتضمين.
2. التصاميم والنماذج والفواتير مطابقة لمتطلبات المالك والصورة المرجعية.
3. التعديلات القادمة المطلوبة في المرحلة التنفيذية تقتصر على:
   - تنظيف ملفات `services/` و `AuthContext.tsx` من واردات Supabase.
   - التأكد من تطابق عقود الـ JSON REST API بين الواجهة وخادم Go Fiber.
   - تضمين `frontend/dist` داخل ملفات سورس خادم Go.
