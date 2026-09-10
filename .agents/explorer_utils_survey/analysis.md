# تقرير التحليل المعمق — دوال التحويل الرقمي وبنية البناء والتجميع (Utilities & Build Survey)

## 1. ملخص تنفيذي (Executive Summary)
تم إجراء مسح شامل لجميع دوال معالجة الأرقام والتواريخ والعملات، وميكانيكية إدخال الأرقام عبر لوحة المفاتيح، والتحقق التام من سكربتات البناء وإعدادات TypeScript في الواجهة الأمامية (`frontend`) والخلفية (`backend`).
- **حالة البناء (Build Status)**: كلاً من `frontend` و `backend` يجتازان اختبارات البناء `npm run build` بنسبة **100% بنجاح ودون أي أخطاء** (Exit code 0).
- **حالة المدخلات (Numeric Inputs)**: تم التخلص كلياً من `type="number"` في جميع مكونات الواجهة الأمامية واستبدالها بحقول نصية `type="text"` مع `inputMode="decimal"` أو `inputMode="numeric"`.
- **معالجة الأرقام الإنجليزية (English Numerals Enforce)**: تتوفر حزمة متكاملة وموحدة من دوال التنظيف والتحويل في `frontend/src/utils/formatters.ts`.

---

## 2. مسح دوال التحويل الرقمي والتنسيق الحالية (Existing Utilities Survey)

### 2.1 الواجهة الأمامية (Frontend Utilities)
الموقع المركزي: `frontend/src/utils/formatters.ts`

| الدالة | المسار / الموقع | الوظيفة | آلية العمل والضمانات |
| :--- | :--- | :--- | :--- |
| `toEnglishDigits(val)` | `frontend/src/utils/formatters.ts:72` | تحويل الأرقام العربية المشرقية (٠-٩) والفارسية (۰-۹) إلى إنجليزية (0-9) | تستبدل الرموز في النطاقات `\u0660-\u0669` و `\u06F0-\u06F9` بحساب فرق الترميز اليونيكود. تدعم المدخلات `null` و `undefined` و `number` بأمان. |
| `normalizeNumerals(str)` | `frontend/src/utils/formatters.ts:82` | دالة توافقية خلفية | تُوجّه مباشرة إلى `toEnglishDigits(str)`. |
| `sanitizeDecimalInput(val)` | `frontend/src/utils/formatters.ts:90` | تنظيف وتجهيز المدخلات العشرية (قراءات، تعرفة، مبالغ، متأخرات) | تُحوّل الأرقام المشرقية، تحظر أي أحرف غير رقمية عدا النقطة `.replace(/[^0-9.]/g, '')`، وتضمن وجود نقطة عشرية واحدة كحد أقصى `parts[0] + '.' + parts.slice(1).join('')`. |
| `sanitizeIntegerInput(val)` | `frontend/src/utils/formatters.ts:104` | تنظيف المدخلات الصحيحة (أرقام المشتركين، أرقام العدادات، الهواتف) | تُحوّل الأرقام المشرقية وتقتطع جميع الحروف والرموز غير الرقمية `.replace(/[^0-9]/g, '')`. |
| `formatDate(date)` | `frontend/src/utils/formatters.ts:10` | تنسيق التاريخ والوقت | تفرض `en-US` لمنع توليد أرقام مشرقية: `new Date(date).toLocaleString('en-US', ...)`. |
| `formatDateOnly(date)` | `frontend/src/utils/formatters.ts:25` | تنسيق التاريخ فقط | تفرض `en-US`: `new Date(date).toLocaleDateString('en-US', ...)`. |
| `formatMonth(date)` | `frontend/src/utils/formatters.ts:45` | تنسيق اسم الشهر والسنة | تستخدم مصفوفة أسماء الأشهر العربية يدوياً `ARABIC_MONTHS` وتدمجها برقم السنة الإنجليزي `${d.getFullYear()}` لمنع المتصفح من قلب أرقام السنة إلى مشرقية. |
| `formatNumber(value)` | `frontend/src/utils/formatters.ts:54` | تنسيق الأرقام مع فواصل الآلاف | تفرض `en-US`: `Number(value).toLocaleString('en-US')`. |
| `formatCurrency(value)` | `frontend/src/utils/formatters.ts:62` | تنسيق المبالغ المالية بالريال اليمني | تفرض `en-US` مع تحديد الخانات العشرية `0 - 2`. |
| `validateYemeniPhone(phone)` | `frontend/src/utils/phoneValidation.ts:9` | التحقق وتنسيق رقم الهاتف اليمني | تُطبّق `toEnglishDigits` أولاً، وتتحقق من بادئات الشركات اليمنية (77، 73، 71، 70، 78) وتعيد الصيغة الدولية `+967...`. |

### 2.2 الخلفية (Backend Utilities)
| الملف | الدالة | الملاحظات التقنية والتوصيات |
| :--- | :--- | :--- |
| `backend/src/lib/phone.ts:1` | `formatPhoneNumber(phone)` | تنظف الرموز وتعيد صيغة `+967...` القياسية. |
| `backend/src/lib/tafqeet.ts:1` | `tafqeet(amount)` | تُحوّل المبالغ الرقمية إلى كلمات عربية (تفقيط). **ملاحظة**: في السطر 34 تستخدم `num.toLocaleString('ar-YE')` كبديل احتياطي للمبالغ الكبيرة جداً، يُفضل تغييرها إلى `en-US` أو `ar-YE-u-nu-latn` لضمان عدم ظهور أرقام مشرقية في بيئات Node.js غير المضبوطة. |
| `backend/src/controllers/analytics.controller.ts` | سطور 11 و 476 | تستخدم `targetDate.toLocaleString('ar-EG', { month: 'long', year: 'numeric' })` مما قد يولد أرقام مشرقية في بعض بيئات السيرفر، ويُفضل استخدام `ar-EG-u-nu-latn` أو استخراج الشهر والسنة بشكل منفصل. |

---

## 3. تحليل سلاسة الكتابة بلوحة المفاتيح والتعامل مع الفاصلة العشرية (Typing Ergonomics & Decimal Edge Cases)

### 3.1 مشكلة ابتلاع النقطة العشرية (Dot Swallowing Glitch) — [مؤكد]
عند ربط حقل إدخال بـ state في React، إذا قام معالج `onChange` بتحويل القيمة فوراً إلى `Number(clean)`:
1. عندما يكتب المستخدم `1` ثم يضغط `.` ليصبح الحقل `"1."`:
   - التقييم البرمجي: `Number("1.") === 1` (يتحول إلى رقم صحيح).
   - يتم تخزين `1` في الحالة (State).
   - يعيد React رسم الحقل بالقيمة `1`، فيتم **حذف النقطة فورياً من الحقل** أمام المستخدم!
   - إذا حاول المستخدم كتابة `5` بعدها، تصبح القيمة `15` بدلاً من `1.5`!
2. عندما يكتب المستخدم `0.` أو `0.0`:
   - `Number("0.") === 0` و `Number("0.0") === 0`.
   - يتم ابتلاع الصفر والفاصلة، مما يمنع كتابة أرقام مثل `0.05`.
3. عندما يكتب المستخدم `.` بمفردها كبداية للكسر:
   - `Number(".") === NaN`.
   - إذا لم يتم التعامل معها كنص، ستفسد الحالة الرياضية أو تعرض `"NaN"`.

### 3.2 الحل الهندسي المعتمد لسلاسة الإدخال (Robust Input Pattern)
لضمان تجربة كتابة سلسة وسريعة 100%:
1. **في مستوى الحالة أثناء التعديل (State During Editing)**:
   - يجب أن تحتفظ حالة الإدخال (`localRows` أو `formData` أو `useState`) بالقيمة كـ **نص مُعقّم** `clean = sanitizeDecimalInput(e.target.value)`.
2. **في مستوى العمليات الحسابية المباشرة (Live Real-time Computation)**:
   - دوال الاحتساب (مثل `computeRowFinancials`) تقوم بتحويل النصوص إلى أرقام عبر `parseFloat(val) || 0` أو `Number(val) || 0` أثناء التقييم دون تعديل نص الحقل في واجهة المستخدم.
3. **في مستوى الحفظ بعد الخروج (On Blur / Save)**:
   - عند حدث `onBlur`، يتم تثبيت الرقم النهائي كـ `Number(clean) || 0` وإرساله للخادم.

### 3.3 دعم فاصلة لوحة المفاتيح العربية (`٫` و `,`) — [موصى به]
لوحات المفاتيح على أجهزة الجوال أو بعض تخطيطات لوحة المفاتيح العربية تُرسل رمز الفاصلة العشرية العربية `٫` (اليونيكود `\u066B`) أو الفاصلة الإنجليزية `,`.
- **التوصية**: تحديث `toEnglishDigits` أو `sanitizeDecimalInput` لتحويل `[\u066B,]` إلى `.` قبل تطبيق الفلترة `.replace(/[^0-9.]/g, '')`.
- الكود المقترح:
```typescript
export function sanitizeDecimalInput(val: string | number | null | undefined): string {
  if (val === null || val === undefined) return '';
  const converted = toEnglishDigits(val)
    .replace(/[\u066B,]/g, '.')
    .replace(/[^0-9.]/g, '');
  const parts = converted.split('.');
  if (parts.length > 2) {
    return parts[0] + '.' + parts.slice(1).join('');
  }
  return converted;
}
```

---

## 4. تدقيق إعدادات الحزم والتجميع واختبارات البناء (Build & Compilation Audit)

### 4.1 الواجهة الأمامية (`frontend`)
- **ملف `package.json`**:
  - السكربت المعتمد: `"build": "tsc -b && vite build"`
  - الأدوات: TypeScript 6.0.2, Vite 8.2.1, React 19.2.8, Tailwind CSS v4.
- **إعدادات TypeScript (`tsconfig.app.json`)**:
  - `target: "es2023"`, `moduleResolution: "bundler"`, `noEmit: true`, `strict: true`.
- **نتيجة تشغيل `npm run build`**:
  - **النتيجة**: نجاح تام (Exit code 0).
  - زمن البناء: `3.98s`.
  - مخرجات الحزم:
    - `dist/index.html`: `1.02 kB`
    - `dist/assets/index-CjR-AVVU.css`: `74.41 kB`
    - `dist/assets/index-BCd_Z1c2.js`: `1,562.65 kB`

### 4.2 الخلفية (`backend`)
- **ملف `package.json`**:
  - السكربت المعتمد: `"build": "tsc --project tsconfig.json"`
  - الأدوات: TypeScript 5.6.3, Express 5.2.1, Prisma 7.10.0, Node.js.
- **إعدادات TypeScript (`tsconfig.json`)**:
  - `target: "ES2020"`, `module: "commonjs"`, `strict: true`, `skipLibCheck: true`.
- **نتيجة تشغيل `npm run build`**:
  - **النتيجة**: نجاح تام (Exit code 0).
  - تم توليد ملفات `dist` بدون أي أخطاء نوعية (0 type errors).

### 4.3 اختبارات الفحص الرقمي (Automated Numeral Scanners)
- تم تشغيل `node frontend/src/tests/test_numerals_scan.js`:
  - فحص 55 ملفاً مصدرياً: **0** أرقام مشرقية في واجهات المستخدم.
  - فحص حقول الإدخال: **0** حقول `type="number"` غير منضبطة.
  - فحص دوال التنسيق: **0** استدعاءات `toLocaleString` خارج `en-US`.
  - اختبارات دوال `formatters.ts` و `phoneValidation.ts`: **29/29 اختبار ناجح بنسبة 100%**.
- تم تشغيل `test_routes_and_tabs.js`, `test_whatsapp_and_phone.js`, `scan_all_formats.js`: **جميعها اجتازت الاختبار بنجاح**.

---

## 5. مصفوفة التوصيات والإجراءات (Actionable Recommendations Matrix)

| البند | المشكلة المحتملة | الحل المقترح | مستوى الأولوية |
| :--- | :--- | :--- | :--- |
| **دعم الفاصلة العربية** | الفاصلة `٫` (`\u066B`) أو `,` قد تُحذف في بعض الكيبوردات العربية | استبدال `[\u066B,]` بنقطة `.` داخل `sanitizeDecimalInput` قبل الفلترة | متوسطة |
| **سلاسة إدخال الجداول** | تحويل `clean` إلى `Number` فوراً يبتلع النقطة أثناء الطباعة السريعة | تخزين `clean` كنص في `localRows` أثناء `onChange` وتحويله لرقم في الحسابات و`onBlur` | عالية |
| **احتياطي التفقيط بالخلفية** | `tafqeet.ts:34` تستخدم `ar-YE` للمبالغ فوق المليون | استبدالها بـ `toLocaleString('en-US')` | منخفضة |
| **تسميات شهور التحليلات** | `analytics.controller.ts` تستخدم `ar-EG` لاسم الشهر والسنة | استخدام `ar-EG-u-nu-latn` أو فصل الشهر والسنة لضمان أرقام إنجليزية للسنة | منخفضة |
