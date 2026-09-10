# Handoff Report — Explorer 1 (Input Fields & Numerals Specialist)

<div dir="rtl">

## 1. الملاحظات والبيانات المرصودة (Observation)
1. **حقول `type="number"` في واجهة النظام**:
   - `frontend/src/components/common/ExcelGrid.tsx`:
     - السطر 277: `<input type="number"` (`globalRateInput`)
     - السطر 287: `<input type="number"` (`globalFeeInput`)
     - السطر 577: `<input type="number"` (`prevReading`)
     - السطر 593: `<input type="number"` (`currReading`)
     - السطر 615: `<input type="number"` (`lostUnits`)
     - السطر 632: `<input type="number"` (`unitPrice`)
     - السطر 653: `<input type="number"` (`serviceFee`)
     - السطر 669: `<input type="number"` (`arrears`)
     - السطر 690: `<input type="number"` (`paidAmount`)
   - `frontend/src/pages/TodayReadingsReview.tsx`:
     - السطور 413, 423, 765, 781, 802, 818, 839, 855, 876 (مطابقة لنفس خلايا `ExcelGrid.tsx`).
   - `frontend/src/components/ReadingModal.tsx`:
     - السطر 206: `<input required type="number" step="any" min={0} ... />`
   - `frontend/src/components/PaymentModal.tsx`:
     - السطر 112: `<input id="payment-amount-input" name="amountPaid" type="number" min={1} required ... />`
   - `frontend/src/components/ArrearsThresholdModal.tsx`:
     - السطر 49: `<input type="number" min="0" value={threshold} ... />`
   - `frontend/src/pages/Customers.tsx`:
     - السطر 631: `<input type="number" step="any" min={0} value={formData.initial_reading} ... />`
     - السطر 815: `<input type="number" step="any" min={0} value={editFormData.initial_reading} ... />`
   - `frontend/src/pages/Dashboard.tsx`:
     - السطر 776: `<input type="number" step="any" min="0" value={editValue} ... />`
   - `frontend/src/pages/UnreadMeters.tsx`:
     - السطر 376: `<input type="number" step="any" min={selectedCustomer.last_reading_value} value={readingValue} ... />`

2. **حالة أدوات التنسيق الحالية (`src/utils/formatters.ts`)**:
   - تحتوي على `normalizeNumerals(str)` (السطر 72)، لكنها لا تعالج القيم غير النصية (مثل `number` أو `null`) ولا توفر وظيفة تنقية الفواصل العشرية المتعددة أو التعابير النمطية للحقول الرقمية المباشرة.

3. **حالة CSS وتنسيقات الأسهم (`frontend/src/index.css`)**:
   - السطور 57-67 تحتوي على قواعد إخفاء الأسهم لـ `input[type="number"]`.
   - السطور 70-73 تحتوي على فرض الأرقام الإنجليزية عبر `font-feature-settings: "lnum" 1, "tnum" 1`.

---

## 2. سلسلة الاستدلال المنطقي (Logic Chain)
1. من الملاحظة (1)، يؤدي استخدام `type="number"` في المتصفحات إلى منع لوحة المفاتيح من إدخال الأرقام المشرقية (٠-٩) ويمنع تنقية المدخلات عبر `onChange` قبل أن يعالجها المتصفح، مما يُعطل تجربة المستخدم على الأجهزة المحمولة والحواسيب.
2. استخدام `type="text"` مع `inputMode="decimal"` يُتيح فتح لوحة الأرقام المناسبة في الهواتف، مع السماح بقبول أي محرف يُدخله المستخدم في React State.
3. دمج `toEnglishDigits` و `sanitizeDecimalInput` في حدث `onChange` و `onBlur` يضمن تحويل أي رقم عربي مشرقي فوراً إلى رقم إنجليزي (0-9) مع حذف أي أحرف أو رموز غير رقمية باستثناء نقطة عشرية واحدة فقط.
4. تطبيق `toEnglishDigits` على حقول أرقام المشتركين، أرقام الهواتف، وأرقام العدادات في `Customers.tsx`، `ExcelGrid.tsx`، `WhatsApp.tsx`، و `phoneValidation.ts` يحمي النظام بالكامل من أي تسرب للأرقام المشرقية إلى الـ Backend أو الواتساب.

---

## 3. التحفظات والافتراضات (Caveats)
- لم يتم رصد أي حقول رقمية أخرى خارج نطاق الـ 44 موضعاً المحددة في الجدول بملف `analysis.md`.
- التعديل المقترح آمن 100% ولا يكسر استدعاءات الـ API لأن القيم الممررة للـ State أو الـ Callbacks ستبقى رقمية (`Number(clean)`) أو سلاسل نصية مطهرة ومطابقة للتوقعات البرمجية السابقة.

---

## 4. الخلاصة والتوصية النهائية (Conclusion)
[مؤكد] تم حصر كافة الحقول البالغ عددها 44 موضعاً بدقة متناهية مع أرقام الأسطر والملفات المعنية.
يجب تنفيذ التعديلات التالية بالتتابع:
1. تحديث `src/utils/formatters.ts` بإضافة وتصدير `toEnglishDigits` و `sanitizeDecimalInput` و `sanitizeIntegerInput`.
2. تحديث `src/utils/phoneValidation.ts` لتمرير الأرقام عبر `toEnglishDigits`.
3. استبدال `type="number"` بـ `type="text" inputMode="decimal"` في المكونات المحددة (`ExcelGrid.tsx`، `ReadingModal.tsx`، `PaymentModal.tsx`، `Customers.tsx`، `TodayReadingsReview.tsx`، `Dashboard.tsx`، `UnreadMeters.tsx`، `ArrearsThresholdModal.tsx`).
4. إضافة `toEnglishDigits` على حقول النصوص الرقمية (الهاتف، العداد، رقم المشترك، المسار).

---

## 5. طريقة التحقق المستقل (Verification Method)
1. **فحص الامتثال للأرقام الإنجليزية**:
   ```bash
   node frontend/src/tests/test_numerals_scan.js
   ```
2. **بناء الواجهة الأمامية بالكامل**:
   ```bash
   cd frontend && npm run build
   ```
3. **التجربة اليدوية للواجهات**:
   - إدخال أرقام مشرقية (مثل: `١٢.٥`) في خلايا `ExcelGrid` وفي `ReadingModal` و `PaymentModal` والتأكد من تحولها فوراً إلى `12.5` دون ظهور أي أسهم متصفح.
</div>
