# تحليل واستقصاء حقول الإدخال الرقمية والأرقام الإنجليزية (Input Fields & English Numerals Survey)

<div dir="rtl">

## 1. الملخص التنفيذي
تم إجراء مسح شامل لجميع شاشات ومكونات الواجهة الأمامية في نظام Smart Power ERP (`frontend/src/`) لحصر كافة حقول الإدخال الرقمية التي تستخدم `type="number"` أو تتعامل مع الأرقام، وتحديد استراتيجية التحويل إلى `type="text"` مع `inputMode="decimal"` أو `inputMode="numeric"`، وإلغاء أسهم المتصفح (Spinners) كلياً، وتطبيق دالة التحويل الفوري للأرقام المشرقية `toEnglishDigits` مع التطهير بالتعابير النمطية (`Regex Sanitization`).

---

## 2. المشكلة التقنية وجذر الخلل (Root Cause Analysis)
1. **سلوك المتصفح مع `type="number"`**:
   - تفرض محركات المتصفحات (Blink / Gecko / WebKit) قيوداً صارمة على حقول `type="number"`. عند إدخال محارف غير لاتينية مثل الأرقام العربية المشرقية (٠، ١، ٢، ٣، ٤، ٥، ٦، ٧، ٨، ٩) أو الفواصل، يتجاهل المتصفح القيمة ولا يُطلق حدث `onChange` بقيمة صالحة، أو يُفرغ الحقل بالكامل.
   - يُجبر المستخدم على استخدام الأسهم المدمجة أو تغيير لغة الإدخال يدويّاً في كل مرة.
2. **أسهم التمرير (Spinners)**:
   - تتسبب في تغيير القيم المالية وقراءات العدادات عن طريق الخطأ عند التمرير بالماوس (`mousewheel`) أو اللمس على الشاشات الذكية، بالإضافة لتشويش محاذاة خلايا شبكة الإكسيل السريعة.
3. **غياب التنقية التلقائية للأرقام في حقول النصوص**:
   - حقول أرقام المشتركين، أرقام الهواتف، وأرقام العدادات تعتمد على `type="text"` دون فلتر تحويل الأرقام المشرقية، مما قد يُرسل أرقاماً مشرقة لقاعدة البيانات أو يتسبب في فشل التحقق من صحة رقم الهاتف في `validateYemeniPhone`.

---

## 3. المعمارية الموصى بها للحل (Recommended Architecture)

### أ. دوال المساعدة المركزية (`src/utils/formatters.ts`)
إضافة وتصدير الدوال التالية في `src/utils/formatters.ts`:

```typescript
/**
 * Convert Eastern Arabic numerals (٠-٩) and Persian numerals (۰-۹) to standard Western English digits (0-9).
 */
export function toEnglishDigits(str: string | number | null | undefined): string {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/[٠-٩]/g, (d) => (d.charCodeAt(0) - 1632).toString())
    .replace(/[۰-۹]/g, (d) => (d.charCodeAt(0) - 1776).toString());
}

/**
 * Sanitize decimal input for amounts, readings, rates, fees, arrears:
 * Converts Eastern digits -> English digits -> allows only (0-9 and single decimal dot).
 */
export function sanitizeDecimalInput(val: string | number | null | undefined): string {
  if (val === null || val === undefined) return '';
  const converted = toEnglishDigits(val).replace(/[^0-9.]/g, '');
  const parts = converted.split('.');
  if (parts.length > 2) {
    return parts[0] + '.' + parts.slice(1).join('');
  }
  return converted;
}

/**
 * Sanitize integer / digit-only input (subscriber numbers, phone numbers, meter numbers):
 * Converts Eastern digits -> English digits -> allows only (0-9).
 */
export function sanitizeIntegerInput(val: string | number | null | undefined): string {
  if (val === null || val === undefined) return '';
  return toEnglishDigits(val).replace(/[^0-9]/g, '');
}
```

### ب. النمط القياسي للحقول الرقمية التفاعلية
تحويل الحقول إلى:
```tsx
<input
  type="text"
  inputMode="decimal"
  value={row.prevReading ?? 0}
  onChange={(e) => {
    const clean = sanitizeDecimalInput(e.target.value);
    handleCellChange(row.id, 'prevReading', clean === '' ? 0 : Number(clean));
  }}
  onBlur={(e) => {
    const clean = sanitizeDecimalInput(e.target.value);
    handleCellBlur(row.id, 'prevReading', clean === '' ? 0 : Number(clean));
  }}
  className="..."
/>
```

---

## 4. الحصر الشامل لكافة الحقول والملفات في النظام

| # | الملف | السطر | الحقل / الوظيفة | النوع الحالي | التعديل الموصى به |
|---|---|---|---|---|---|
| 1 | `src/components/common/ExcelGrid.tsx` | 277 | `globalRateInput` (التعرفة الموحدة) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 2 | `src/components/common/ExcelGrid.tsx` | 287 | `globalFeeInput` (الرسوم الموحدة) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 3 | `src/components/common/ExcelGrid.tsx` | 504 | `subNumber` (رقم المشترك في الخلية) | `type="text"` | إضافة `toEnglishDigits` على `onChange` |
| 4 | `src/components/common/ExcelGrid.tsx` | 516 | `route` (خط السير في الخلية) | `type="text"` | إضافة `toEnglishDigits` على `onChange` |
| 5 | `src/components/common/ExcelGrid.tsx` | 553 | `meterNumber` (رقم العداد في الخلية) | `type="text"` | إضافة `toEnglishDigits` على `onChange` |
| 6 | `src/components/common/ExcelGrid.tsx` | 565 | `phone` (رقم الهاتف في الخلية) | `type="text"` | إضافة `toEnglishDigits` على `onChange` |
| 7 | `src/components/common/ExcelGrid.tsx` | 577 | `prevReading` (القراءة السابقة في الخلية) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 8 | `src/components/common/ExcelGrid.tsx` | 593 | `currReading` (القراءة الحالية في الخلية) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 9 | `src/components/common/ExcelGrid.tsx` | 615 | `lostUnits` (الوحدات الضائعة في الخلية) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 10 | `src/components/common/ExcelGrid.tsx` | 632 | `unitPrice` (سعر الوحدة في الخلية) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 11 | `src/components/common/ExcelGrid.tsx` | 653 | `serviceFee` (رسوم الخدمة في الخلية) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 12 | `src/components/common/ExcelGrid.tsx` | 669 | `arrears` (المتأخرات السابقة في الخلية) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 13 | `src/components/common/ExcelGrid.tsx` | 690 | `paidAmount` (المبلغ المسدد في الخلية) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 14 | `src/pages/TodayReadingsReview.tsx` | 413 | `globalRateInput` (شريط التعرفة) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 15 | `src/pages/TodayReadingsReview.tsx` | 423 | `globalFeeInput` (شريط الرسوم) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 16 | `src/pages/TodayReadingsReview.tsx` | 692 | `subNumber` (رقم المشترك في الخلية) | `type="text"` | إضافة `toEnglishDigits` على `onChange` |
| 17 | `src/pages/TodayReadingsReview.tsx` | 704 | `route` (خط السير في الخلية) | `type="text"` | إضافة `toEnglishDigits` على `onChange` |
| 18 | `src/pages/TodayReadingsReview.tsx` | 740 | `meterNumber` (رقم العداد في الخلية) | `type="text"` | إضافة `toEnglishDigits` على `onChange` |
| 19 | `src/pages/TodayReadingsReview.tsx` | 752 | `phone` (رقم الهاتف في الخلية) | `type="text"` | إضافة `toEnglishDigits` على `onChange` |
| 20 | `src/pages/TodayReadingsReview.tsx` | 765 | `prevReading` (القراءة السابقة في الخلية) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 21 | `src/pages/TodayReadingsReview.tsx` | 781 | `currReading` (القراءة الحالية في الخلية) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 22 | `src/pages/TodayReadingsReview.tsx` | 802 | `lostUnits` (الوحدات الضائعة في الخلية) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 23 | `src/pages/TodayReadingsReview.tsx` | 818 | `unitPrice` (سعر الوحدة في الخلية) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 24 | `src/pages/TodayReadingsReview.tsx` | 839 | `serviceFee` (رسوم الخدمة في الخلية) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 25 | `src/pages/TodayReadingsReview.tsx` | 855 | `arrears` (المتأخرات السابقة في الخلية) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 26 | `src/pages/TodayReadingsReview.tsx` | 876 | `paidAmount` (المبلغ المسدد في الخلية) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 27 | `src/components/ReadingModal.tsx` | 206 | `readingValue` (قراءة العداد الحالية) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 28 | `src/components/PaymentModal.tsx` | 112 | `amountPaid` (المبلغ المسدد) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 29 | `src/components/ArrearsThresholdModal.tsx` | 49 | `threshold` (حد المديونية) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 30 | `src/pages/Customers.tsx` | 557 | `subscriber_number` (إضافة مشترك) | `type="text"` | إضافة `toEnglishDigits` على `onChange` |
| 31 | `src/pages/Customers.tsx` | 585 | `phone` (إضافة مشترك) | `type="text"` | إضافة `toEnglishDigits` على `onChange` |
| 32 | `src/pages/Customers.tsx` | 607 | `meter_number` (إضافة مشترك) | `type="text"` | إضافة `toEnglishDigits` على `onChange` |
| 33 | `src/pages/Customers.tsx` | 619 | `route_number` (إضافة مشترك) | `type="text"` | إضافة `toEnglishDigits` على `onChange` |
| 34 | `src/pages/Customers.tsx` | 631 | `initial_reading` (إضافة مشترك) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 35 | `src/pages/Customers.tsx` | 721 | `subscriber_number` (تعديل مشترك) | `type="text"` | إضافة `toEnglishDigits` على `onChange` |
| 36 | `src/pages/Customers.tsx` | 749 | `phone_number` (تعديل مشترك) | `type="text"` | إضافة `toEnglishDigits` على `onChange` |
| 37 | `src/pages/Customers.tsx` | 790 | `meter_number` (تعديل مشترك) | `type="text"` | إضافة `toEnglishDigits` على `onChange` |
| 38 | `src/pages/Customers.tsx` | 803 | `route_number` (تعديل مشترك) | `type="text"` | إضافة `toEnglishDigits` على `onChange` |
| 39 | `src/pages/Customers.tsx` | 815 | `initial_reading` (تعديل مشترك) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 40 | `src/pages/Dashboard.tsx` | 776 | `editValue` (نافذة تعديل القراءة/السداد المباشر) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 41 | `src/pages/UnreadMeters.tsx` | 376 | `readingValue` (تسجيل قراءة عداد) | `type="number"` | `type="text" inputMode="decimal"` + `sanitizeDecimalInput` |
| 42 | `src/pages/WhatsApp.tsx` | 240 | `testNumber` (رقم هاتف الرسالة التجريبية) | `type="text"` | إضافة `toEnglishDigits` على `onChange` |
| 43 | `src/utils/phoneValidation.ts` | 13 | `validateYemeniPhone` | دالة تحقق | تمرير القيمة عبر `toEnglishDigits` قبل المعالجة |
| 44 | `src/index.css` | 57-67 | CSS Resets للأسهم | نمط عام | التأكيد على إخفاء الأسهم وقواعد `font-feature-settings: "lnum" 1, "tnum" 1` |

---

## 5. مصفوفة تفصيلية للتحويل (Before vs After Code Snippets)

### 1. `src/utils/formatters.ts`
```typescript
// إضافة التصدير التالي:
export function toEnglishDigits(str: string | number | null | undefined): string {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/[٠-٩]/g, (d) => (d.charCodeAt(0) - 1632).toString())
    .replace(/[۰-۹]/g, (d) => (d.charCodeAt(0) - 1776).toString());
}

export function sanitizeDecimalInput(val: string | number | null | undefined): string {
  if (val === null || val === undefined) return '';
  const converted = toEnglishDigits(val).replace(/[^0-9.]/g, '');
  const parts = converted.split('.');
  if (parts.length > 2) {
    return parts[0] + '.' + parts.slice(1).join('');
  }
  return converted;
}
```

### 2. `ReadingModal.tsx`
**قبل:**
```tsx
<input
  required
  type="number"
  step="any"
  min={0}
  placeholder="أدخل القراءة الحالية (مثال: 1.30 أو 15.50)..."
  value={readingValue}
  onChange={(e) => setReadingValue(e.target.value)}
  className="..."
/>
```
**بعد:**
```tsx
<input
  required
  type="text"
  inputMode="decimal"
  placeholder="أدخل القراءة الحالية (مثال: 1.30 أو 15.50)..."
  value={readingValue}
  onChange={(e) => setReadingValue(sanitizeDecimalInput(e.target.value))}
  className="..."
/>
```

### 3. `PaymentModal.tsx`
**قبل:**
```tsx
<input
  id="payment-amount-input"
  name="amountPaid"
  type="number"
  min={1}
  required
  autoFocus
  value={amountPaid}
  onChange={(e) => setAmountPaid(e.target.value)}
  className="..."
/>
```
**بعد:**
```tsx
<input
  id="payment-amount-input"
  name="amountPaid"
  type="text"
  inputMode="decimal"
  required
  autoFocus
  value={amountPaid}
  onChange={(e) => setAmountPaid(sanitizeDecimalInput(e.target.value))}
  className="..."
/>
```

### 4. `ExcelGrid.tsx` & `TodayReadingsReview.tsx` (خلايا القراءة والسداد والتعرفة)
**قبل:**
```tsx
<input
  type="number"
  value={row.currReading ?? 0}
  onChange={(e) => handleCellChange(row.id, 'currReading', Number(e.target.value) || 0)}
  onBlur={(e) => handleCellBlur(row.id, 'currReading', Number(e.target.value) || 0)}
  className="..."
/>
```
**بعد:**
```tsx
<input
  type="text"
  inputMode="decimal"
  value={row.currReading ?? 0}
  onChange={(e) => {
    const clean = sanitizeDecimalInput(e.target.value);
    handleCellChange(row.id, 'currReading', clean === '' ? 0 : Number(clean));
  }}
  onBlur={(e) => {
    const clean = sanitizeDecimalInput(e.target.value);
    handleCellBlur(row.id, 'currReading', clean === '' ? 0 : Number(clean));
  }}
  className="..."
/>
```

---

## 6. خطة التحقق والضمان (Verification Plan)
1. تشغيل `node src/tests/test_numerals_scan.js` للتأكد من خلو واجهات النظام من أي محارف عربية مشرقية ثابتة.
2. إضافة اختبار وحدة في `test_numerals_scan.js` يختبر `toEnglishDigits` و `sanitizeDecimalInput` مع مدخلات معقدة:
   - `١٢.٣٤` -> `12.34`
   - `٠٧٧١٢٣٤٥٦٧` -> `0771234567`
   - `abc١٢.٣٤xyz` -> `12.34`
   - `١٢..٣٤` -> `12.34`
3. تشغيل `npm run build` في `frontend` للتحقق من عدم وجود أي خطأ في Typescript أو التجميع.

</div>
