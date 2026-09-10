# تقرير المراجعة والتحدي العددي التنافسي (Challenger 1: Input & Numeral Stress)

## Challenge Summary

- **المهمة**: اختبار إجهاد تنافسي وتجريبي صارم (Empirical Adversarial Stress Test) لأنظمة الإدخال، معالجة الأرقام، وتكامل الحسابات المالية في شاشتي `ExcelGrid` و `TodayReadingsReview`.
- **التقييم العام للمخاطر (Overall Risk Assessment)**: **HIGH**
- **القرار الصريح (Explicit Verdict)**: **REJECT (رفض حتى تطبيق المعالجة المحددة)**

---

## Challenges (الثغرات ونقاط الفشل المكتشفة تجريبياً)

### [Critical] Challenge 1: انهيار الحسابات المالية والكميات المستهلكة إلى الصفر (Financial Calculation Collapse to Zero)
- **الفرضية التي تم تحديها**: افتراض أن دوال الحسابات المالية `computeRowFinancials` و `computeGridTotals` في `frontend/src/types/excelGrid.types.ts` قادرة على معالجة البيانات التي تحتوي على أرقام عربية مشرقية (٠-٩) أو فارسية (۰-۹).
- **سيناريو الهجوم (Attack Scenario)**:
  عند تمرير صفوف تحتوي على قراءات أو تعرفة أو متأخرات بصيغة نصية ذات أرقام مشرقية (مثل استيراد ملف إكسل، أو بيانات قادمة من واجهة خلفية/قاعدة بيانات بدون تسوية مسبقة، مثلاً: `currReading: '١٢٥٠'`, `prevReading: '١٠٠٠'`, `lostUnits: '١٠'`, `unitPrice: '١٤٠٠'`)، تقوم الدالة بالتحويل عبر `Number(row.currReading) || 0`.
  في محرك جافاسكريبت، تقييم `Number('١٢٥٠')` يُنتج `NaN`.
  بسبب عامل `|| 0`، تتحول القيمة فوراً إلى `0`.
- **نطاق الضرر (Blast Radius)**:
  - كمية الاستهلاك `units` تصبح `0` بدلاً من `250`.
  - قيمة الاستهلاك `consumptionCost` تصبح `0` بدلاً من `350,000` ريال.
  - تكلفة الفاقد `lostUnitsCost` تصبح `0` بدلاً من `14,000` ريال.
  - إجمالي المستحق `totalDue` ينهار إلى `1000` ريال (رسوم الخدمة فقط) بدلاً من `365,000` ريال (خسارة مالية بنسبة 99.7% في الفاتورة).
- **الدليل التجريبي (Empirical Proof)**:
  ```bash
  node -e "import('./frontend/src/types/excelGrid.types.ts').then(m => console.log(m.computeRowFinancials({currReading:'١٢٥٠', prevReading:'١٠٠٠', unitPrice:1400})))"
  # النتيجة الفعلية: { units: 0, consumptionCost: 0, totalDue: 0 }
  ```
- **المعالجة المقترحة (Mitigation)**:
  تغليف كافة حقول الإدخال في `computeRowFinancials` و `computeGridTotals` بدالة `toEnglishDigits` قبل استدعاء `Number()`:
  ```typescript
  const prev = Number(toEnglishDigits(row.prevReading)) || 0;
  const curr = Number(toEnglishDigits(row.currReading)) || 0;
  const lostUnits = Number(toEnglishDigits(row.lostUnits)) || 0;
  const unitPrice = Number(toEnglishDigits(row.unitPrice)) || 0;
  const serviceFee = Number(toEnglishDigits(row.serviceFee)) || 0;
  const arrears = Number(toEnglishDigits(row.arrears)) || 0;
  const paid = Number(toEnglishDigits(row.paidAmount)) || 0;
  ```

---

### [Critical] Challenge 2: فشل كامل في زر إرسال فواتير الواتساب (Direct WhatsApp Action Failure)
- **الفرضية التي تم تحديها**: افتراض أن دالة `formatYemeniPhone` في `frontend/src/types/excelGrid.types.ts` تدعم الأرقام الشرقية المشرقية.
- **سيناريو الهجوم (Attack Scenario)**:
  دالة `formatYemeniPhone` كُتبت بالصيغة:
  ```typescript
  export function formatYemeniPhone(rawPhone: string): string {
    let phone = (rawPhone || '').replace(/[^0-9]/g, '').trim();
    ...
  }
  ```
  عندما يكون رقم هاتف المشترك مدخلاً أو مستورداً بالأرقام المشرقية (مثل `٠٧٧١٢٣٤٥٦٧`)، فإن التعبير النمطي `/[^0-9]/g` يحذف جميع الأرقام لأنها خارج نطاق ASCII (0-9)، فتتحول السلسلة إلى فارغة `""`.
  عند النقر على زر الاعتماد المباشر أو زر الواتساب في `ExcelGrid` أو `TodayReadingsReview`:
  ```typescript
  const formattedPhone = formatYemeniPhone(row.phone);
  if (!formattedPhone || formattedPhone.length < 9) {
    toast.error('يرجى التأكد من كتابة رقم هاتف يمني صحيح للمشترك');
    return;
  }
  ```
  تتوقف العملية فوراً، ولا يتم فتح رابط الواتساب `wa.me`، وتفشل عملية الإرسال بالكامل.
- **نطاق الضرر (Blast Radius)**:
  تعطل ميزة الإرسال التلقائي المعتمد عبر الواتساب لكافة المشتركين المسجلين بأرقام مشرقية في قاعدة البيانات.
- **الدليل التجريبي (Empirical Proof)**:
  ```bash
  node -e "import('./frontend/src/types/excelGrid.types.ts').then(m => console.log(JSON.stringify(m.formatYemeniPhone('٠٧٧١٢٣٤٥٦٧'))))"
  # النتيجة الفعلية: ""
  ```
- **المعالجة المقترحة (Mitigation)**:
  استدعاء `toEnglishDigits` قبل تنظيف النص في `formatYemeniPhone`:
  ```typescript
  export function formatYemeniPhone(rawPhone: string): string {
    let phone = toEnglishDigits(rawPhone || '').replace(/[^0-9]/g, '').trim();
    if (phone.startsWith('00967')) phone = phone.substring(5);
    if (phone.startsWith('967')) phone = phone.substring(3);
    if (phone.startsWith('0')) phone = phone.substring(1);
    return phone ? `967${phone}` : '';
  }
  ```

---

### [High] Challenge 3: ظهور قيمة "NaN" الصريحة في نص الفاتورة الرسمية للواتساب (NaN in WhatsApp Invoice Template)
- **الفرضية التي تم تحديها**: افتراض سلامة قالب رسالة الواتساب `buildWhatsAppText` ضد القيم غير المعيارية.
- **سيناريو الهجوم (Attack Scenario)**:
  في السطور 118-119 من `frontend/src/types/excelGrid.types.ts`:
  ```typescript
  const prevStr = Number(row.prevReading || 0).toLocaleString('en-US');
  const currStr = Number(row.currReading || 0).toLocaleString('en-US');
  ```
  إذا كان `row.prevReading` أو `row.currReading` يحمل أرقاماً مشرقية نصية، فإن `Number('١٢٠٠')` يُنتج `NaN`. واستدعاء `NaN.toLocaleString('en-US')` يُنتج الكلمة النصية `"NaN"`.
- **نطاق الضرر (Blast Radius)**:
  توليد وإرسال فواتير رسمية للعملاء تحتوي على:
  `📊 *القراءة السابقة:* NaN`
  `📈 *القراءة الحالية:* NaN`
  مما يشوه مظهر الفاتورة الرسمية ويفقدها الموثوقية والمصداقية القانونية.
- **الدليل التجريبي (Empirical Proof)**:
  ```bash
  node -e "import('./frontend/src/types/excelGrid.types.ts').then(m => console.log(m.buildWhatsAppText({prevReading:'٠', currReading:'١٥٠', units:150})))"
  # النتيجة المباشرة:
  # 📊 *القراءة السابقة:* NaN
  # 📈 *القراءة الحالية:* NaN
  ```
- **المعالجة المقترحة (Mitigation)**:
  ```typescript
  const prevStr = Number(toEnglishDigits(row.prevReading) || 0).toLocaleString('en-US');
  const currStr = Number(toEnglishDigits(row.currReading) || 0).toLocaleString('en-US');
  ```

---

### [Medium] Challenge 4: تحويل فاصل الآلاف إلى فاصلة عشرية عند النسخ واللصق (Comma / Thousands Separator Ambiguity)
- **الفرضية التي تم تحديها**: استبدال الفواصل العادية `.` و `,` و `٫` و `٬` تلقائياً بنقطة عشرية `.` في `sanitizeDecimalInput`.
- **سيناريو الهجوم (Attack Scenario)**:
  إذا قام المحاسب بنسخ رقم يحتوي على فاصل آلاف مثل `"28,500"` أو `"1,000"` ولصقه في حقل المتأخرات أو المدفوع:
  تقوم الدالة بتحويل `,` إلى `.`، ليصبح الرقم `"28.500"` أو `"1.000"`.
  عند تحويله إلى رقم عبر `Number()`, تصبح القيمة `28.5` أو `1` بدلاً من `28500` أو `1000`.
- **نطاق الضرر (Blast Radius)**:
  انخفاض القيمة 1000 ضعف في حال لصق أرقام منسقة بفواصل الآلاف.
- **الملاحظة والتوصية**:
  هذا السلوك ناتج عن تلبية متطلب دعم الفاصلة كفاصلة عشرية (`12,5` -> `12.5`). يجب توعية المستخدم أو تحسين المعالج بحيث إذا تبعت الفاصلة 3 أرقام صحيحة بدون أجزاء عشرية أخرى يُعتبر فاصل آلاف ويُحذف، بينما إذا جاء بعده رقم أو رقمان يُعتبر علامة عشرية.

---

## Stress Test Results (نتائج الاختبارات التجريبية)

تم بناء وتنفيذ سويت اختبار تجريبي شامل `frontend/src/tests/test_adversarial_numerals_stress.js` يغطي 108 فحصاً إجهادياً:

| الاختبار / السيناريو | السلوك المتوقع | السلوك الفعلي | النتيجة |
|---|---|---|---|
| الأرقام المشرقية (٠-٩) في `toEnglishDigits` | تحويل كامل إلى (0-9) | تحويل مطابق 100% | **PASS** |
| الأرقام الفارسية (۰-۹) | تحويل كامل إلى (0-9) | تحويل مطابق 100% | **PASS** |
| الفاصلة العشرية العربية (`٫`) والفاصلة العربية (`،`) | التحويل إلى نقطة `.` | تحويل مطابق | **PASS** |
| الحروف اللاتينية والعربية والرموز | حذف كامل غير الأرقام | تنظيف دقيق | **PASS** |
| الحفاظ على النقطة العائمة أثناء الكتابة (`"12."`, `"0."`) | عدم بلع النقطة وتثبيتها | الحفاظ على النقطة أثناء الكتابة | **PASS** |
| محاكاة تسلسل النقر (Keystroke Simulation) عبر `onChange` | عدم حدوث `NaN` في الحسابات اللحظية | حسابات مرنة بدون أي خطأ | **PASS** |
| الخروج من الحقل بعد كتابة نقطة منفردة `"."` في `onBlur` | التحويل التلقائي إلى `0` | تحويل آمن إلى `0` | **PASS** |
| تفريغ الحقل بالكامل `""` في `onBlur` | التحويل التلقائي إلى `0` | تحويل آمن إلى `0` | **PASS** |
| تكرار النقاط العائمة (`"12.3.4.5"`) | الاحتفاظ بأول نقطة ودمج الباقي | إنتاج `"12.345"` سليم | **PASS** |
| أداء واحتساب 1,000 صف مالي دفعة واحدة | إنجاز في أقل من 50ms | إنجاز في **2.82ms** | **PASS** |
| فحص استدعاءات `en-US` عبر جميع الملفات | انعدام أي `ar` محلي في الأرقام | لا توجد استدعاءات مخالفة | **PASS** |
| تجميع المشروع `npm run build` في الواجهة | نجاح بدون أي خطأ تجميعي | نجاح تجميع Vite + TS بنسبة 100% | **PASS** |
| تجميع الخادم `npm run build` في الخلفية | نجاح بدون أي خطأ تجميعي | نجاح تجميع tsc بنسبة 100% | **PASS** |
| **دعم الأرقام المشرقية في `formatYemeniPhone`** | **تحويل إلى صيغة يمنية دولية** | **إرجاع `""` وفشل الواتساب** | **FAIL** ❌ |
| **قراءة الأرقام المشرقية في `computeRowFinancials`** | **احتساب الفاتورة بدقة** | **انهيار الحسابات إلى الصفر** | **FAIL** ❌ |
| **نص رسالة الواتساب `buildWhatsAppText` مع أرقام مشرقية** | **عرض الأرقام بصيغة إنجليزية** | **ظهور الكلمة `"NaN"`** | **FAIL** ❌ |

---

## Unchallenged Areas

- **اختبارات الطابعات الحرارية المادية عبر USB**: خارج نطاق الاختبار البرمجي التنافسي (تم التحقق من أكواد التوليد والمعاينة والـ CSS).
- **اتصال جلسة WhatsApp Web الحية (QR Code)**: تم اختبار محرك صياغة الروابط `wa.me` وتوليد النصوص، ولم يتم إجراء مسح QR للواتساب لعدم توفر هاتف حقيقي في البيئة التجريبية.

---

## Final Challenger Verdict

### **القرار النهائي: REJECT ❌**

**السبب الموجب للرفض**:
على الرغم من نجاح الواجهات ومكونات الإدخال في التعامل مع الكتابة المباشرة، إلا أن طبقة الحسابات المركزية `frontend/src/types/excelGrid.types.ts` بها 3 ثغرات برمجية حاسمة تؤدي إلى:
1. تصفير كميات وفواتير المشتركين عند معالجة أرقام مشرقية غير منقاة مسبقاً.
2. عجز زر الواتساب عن إرسال الفواتير لأي مشترك يحمل رقماً مشرقياً.
3. حقن قيمة `NaN` الصريحة داخل نص الفاتورة الرسمية.

لا يمكن اعتماد العمل (APPROVE) إلا بعد تطبيق التعديل المقترح البسيط (استدعاء `toEnglishDigits` في `excelGrid.types.ts`) وإعادة تشغيل سويت الاختبارات بنجاح 100%.
