# تقرير التسليم الشامل: مواصفات واجهة المستخدم والنموذج المعتمد (UI & Reference Design Specification)

## 1. الملاحظات المباشرة (Observation)

### أ. تحليل النموذج المرجعي `code_artifact (8).html`
تم فحص الملف المرجعي `d:/elctercity/code_artifact (8).html` (المكون من 1089 سطراً) واستخلاص كافة المعايير التصميمية والوظيفية بدقة متناهية:

1. **لوحة ألوان Tailwind CSS المعتمدة**:
   - **الخلفية العامة**: `bg-slate-100 text-slate-800` مع خط `Cairo` وتطبيق `dir="rtl"`.
   - **البطاقات والترويسة**: `bg-white border border-slate-200 rounded-2xl shadow-sm`.
   - **الهوية البصرية للمحطة وعناصر الإنجاز والاعتماد (Emerald)**:
     - أزرار الاعتماد والإضافة: `bg-emerald-600 hover:bg-emerald-700 text-white font-bold rounded-lg shadow-sm`.
     - الشارات وخلفيات المستحقات: `bg-emerald-50 text-emerald-800 border-emerald-300`.
     - نصوص المبالغ الإجمالية: `text-emerald-700 font-bold font-mono`.
   - **المتأخرات والديون والتحذيرات (Rose)**:
     - خلايا المتأخرات القابلة للتعديل المباشر: `bg-rose-50/70 text-rose-700 border-x-2 border-rose-300 font-mono font-bold`.
     - إجمالي المتأخرات في البطاقات والتذييل: `text-rose-600 font-bold font-mono`.
   - **استهلاك الطاقة والقراءات (Amber & Blue)**:
     - القراءة السابقة: `bg-slate-50 text-amber-900 font-mono font-bold`.
     - القراءة الحالية: `bg-slate-50 text-blue-900 font-mono font-bold`.
     - كمية الاستهلاك (Units): `bg-amber-100/50 text-amber-900 text-center font-mono font-bold`.
     - المبالغ المدفوعة: `text-blue-700 font-mono font-bold`.
     - المتبقي قيد التحصيل: `text-slate-900 font-mono font-bold` (أو `text-amber-800` عند وجود متبقي إيجابي).

2. **الترويسة وعناصر التحكم العلوية (Header & Controls)**:
   - أيقونة الهوية مع عنوان النظام وشارة `الوضع المرئي المباشر` (`bg-emerald-100 text-emerald-800 font-bold border border-emerald-300 rounded-full`).
   - محدد دورة الشهر (`#periodInput` مثل `اغسطس - 2026`).
   - زر فتح لوحة التعرفة الموحدة (`التعرفة الموحدة`) مع حقول سعر الوحدة الافتراضي (`#globalRateInput` = 1400) ورسوم الخدمة (`#globalFeeInput` = 1000) وزر `تطبيق على الجميع`.
   - زر `إضافة مشترك` (`addNewSubscriber`).
   - زر `تصدير Excel` (`exportToCSV`) مع ترميز UTF-8 BOM (`\uFEFF`).

3. **بطاقات المؤشرات المالية والتشغيلية (Top 5 KPI Cards)**:
   - شبكة متجاوبة `grid grid-cols-2 md:grid-cols-5 gap-3 mb-5`:
     1. **إجمالي المشتركين**: أيقونة `users` (Blue).
     2. **استهلاك الطاقة**: أيقونة `zap` (Amber) بوحدة `ك.و`.
     3. **إجمالي المتأخرات**: أيقونة `alert-circle` (Rose) مع خلفية `bg-rose-50/30 border-rose-200`.
     4. **إجمالي المستحق العام**: أيقونة `dollar-sign` (Emerald).
     5. **المتبقي قيد التحصيل**: أيقونة `check-circle-2` (Slate/Dark).

4. **شريط البحث والتنبيهات المباشرة**:
   - حقل بحث مرن يبحث بالاسم، رقم المشترك، رقم العداد، أو الهاتف مع شارة إرشادية خضراء (`يمكنك تعديل المتأخرات والقراءات مباشرة من الجدول...`).

5. **هيكل الجدول التفاعلي بنمط Excel (Sticky Headers & Footers)**:
   - الحاوية: `bg-white border border-slate-300 rounded-xl shadow-sm overflow-hidden max-h-[640px] custom-scroll`.
   - الترويسة المثبتة: `<thead class="bg-slate-100 text-slate-700 sticky top-0 z-10 border-b-2 border-slate-300 shadow-xs font-bold select-none">`.
   - التذييل المثبت: `<tfoot class="bg-slate-200 text-slate-900 font-bold border-t-2 border-b-2 border-slate-400 sticky bottom-0 z-10 select-none">`.
   - الخلايا بنمط Excel: إدخال مباشر عبر `<input class="w-full bg-transparent px-1.5 py-1 rounded focus:bg-white focus:outline-none focus:ring-1 ... text-xs" />`.

6. **صيغة رسالة الواتساب الرسمية (`buildWhatsAppText`)**:
   - صياغة منسقة بالأيقونات والخطوط العريضة والمحاذاة المتقنة:
```text
⚡ *فاتورة استهلاك الطاقة الكهربائية* ⚡
📄 *الحالة:* معتمد وموثق ✅
━━━━━━━━━━━━━━━
👤 *المشترك:* {name}
🔢 *رقم الاشتراك:* {subNumber}
🔌 *رقم العداد:* {meterNumber}
📍 *العنوان:* {address}
📅 *الفترة:* {month}
━━━━━━━━━━━━━━━
📊 *القراءة السابقة:* {prevReading}
📈 *القراءة الحالية:* {currReading}
⚡ *كمية الاستهلاك:* {units} ك.و
💰 *سعر الوحدة:* {unitPrice} ريال
━━━━━━━━━━━━━━━
💵 *قيمة الاستهلاك:* {consumptionCost} ريال
🛠 *رسوم الخدمة:* {serviceFee} ريال
⏳ *المتأخرات السابقة:* {arrears} ريال
━━━━━━━━━━━━━━━
🔴 *إجمالي المستحق:* {totalDue} ريال
🟢 *المبلغ المدفوع:* {paidAmount} ريال
⚠️ *المبلغ المتبقي:* {remaining} ريال
━━━━━━━━━━━━━━━
شكراً لتعاونكم وسرعة السداد.
```

7. **نافذة معاينة الفاتورة المستقلة (`InvoiceModal`)**:
   - تعرض الفاتورة الرسمية بكامل حقولها المحدثة لحظياً، مع زرين:
     - `نسخ للواتس` (`copyCurrentInvoiceMessage` باستخدام `navigator.clipboard.writeText`).
     - `إرسال فوري معتمد` (`sendCurrentInvoiceWhatsApp` عبر الرابط المباشر `https://wa.me/{phone}?text=...`).

---

### ب. فحص الوضع الراهن للشاشات والصفحات القائمة في Frontend

1. **صفحة العملاء (`frontend/src/pages/Customers.tsx`)**:
   - تعتمد على جدول تقليدي بمسافات عريضة (`px-5 py-3.5`).
   - تفتقر تماماً إلى التعديل المباشر داخل الخلايا (تعتمد على نوافذ منبثقة منفصلة `ReadingModal` و `PaymentModal` و `StatementModal`).
   - لا توجد خلايا تفاعلية لاحتساب الاستهلاك والوحدات المفقودة والمتأخرات لحظياً.
   - لا يوجد تذييل مثبت (`sticky footer`) لجمع الإجماليات الحسابية المباشرة.

2. **صفحة الفواتير (`frontend/src/pages/Invoices.tsx`)**:
   - مقسمة إلى 3 تبويبات (`collections`, `cycle`, `cyclePrint`).
   - جدول الفواتير وجدول التحصيل يعرضان بيانات مقروءة فقط دون إمكانية التعديل السريع لخلايا القراءات أو المتأخرات أو السدادات داخل الجدول بنمط Excel.
   - إرسال الواتساب يتم عبر استدعاء API لخلفية النظام دون إتاحة خيار المعاينة والنسخ الفوري أو فتح `wa.me` بنمط `code_artifact (8).html`.

3. **صفحة المديونيات (`frontend/src/pages/ArrearsReport.tsx`)**:
   - تعرض قائمة المتأخرين ومستويات التأخير وتصدر Excel عبر SheetJS.
   - تفتقر إلى التعديل المباشر لقيم المتأخرات أو السداد المباشر من نفس الجدول، ولا تحتوي على عمود `أيام التأخير` التفاعلي المرتبط بيوم القراءة المعتمدة مع زر الإنذار المباشر بنمط كشف العمليات الموحد.

4. **صفحة التعديلات المعتمدة (`frontend/src/pages/ApprovedEdits.tsx`)**:
   - صفحة منعزلة تفتح كشف الحساب الفردي لتعديل العمليات. بناءً على متطلبات `ORIGINAL_REQUEST.md` (R4)، يجب حذف هذه الصفحة بالكامل وإلغاء مسارها من `App.tsx` و `Sidebar.tsx`.

5. **مكون باقات الاشتراكات (`frontend/src/components/PlansManagement.tsx`)**:
   - مكون منفصل في شاشة الإعدادات. وفقاً لـ R4، يجب إزالته من مسارات التنقل واستبداله بنموذج التعرفة والرسوم الموحدة في الترويسة أو الإعدادات العامة.

6. **مركز التقارير الشامل (Reports Hub)**:
   - غير موجود حالياً كشاشة مركزية موحدة، وتتوزع التقارير بشكل متفرق بين `AuditLogs.tsx` و `ArrearsReport.tsx` و `Invoices.tsx`.

---

## 2. سلسلة الاستدلال والتحليل الهندسي (Logic Chain)

```
الملاحظة: `code_artifact (8).html` يقدم نمط كشف إكسل عالي الكفاءة يتيح التعديل المباشر على 7 حقول رئيسية (القراءة السابقة، الحالية، الوحدات المفقودة، سعر الوحدة، رسوم الخدمة، المتأخرات، المدفوع) مع إعادة احتساب لحظية فورية.
↓
الاستدلال: إبقاء واجهات React معتمدة على النوافذ المنبثقة (Modals) لكل تعديل قراءة أو سداد يسبب بطئاً شديداً في تجربة الكاشير والمحصل الميداني.
↓
الحل المعماري: تحويل جداول `Customers.tsx`، `Invoices.tsx`، `ArrearsReport.tsx`، و `TodayReadingsReview.tsx` (Live Operations Log) إلى مكون جدول تفاعلي موحد (Excel Grid Component) يطبق نفس معايير CSS والألوان ونمط الإدخال الفوري (Auto-Save on Blur) من `code_artifact (8).html`.
```

### جدول مقارنة الفجوات الفنية (UI & Feature Gap Analysis)

| الخاصية / المعيار | النموذج المعتمد `code_artifact (8).html` | الوضع الحالي في React Frontend | المتطلب المعياري للتطبيق |
|---|---|---|---|
| **نمط التعديل** | تعديل مباشر داخل خلايا الجدول (In-Grid Cell Editing) مع حفظ تلقائي عند فقدان التركيز (Auto-Save on Blur) | نوافذ منبثقة متعددة (ReadingModal, PaymentModal, EditModal) | تطبيق التعديل المباشر داخل الخلايا بنمط Excel مع معالجة `onBlur` و `onChange` المتفائلة. |
| **التفاعل الحسابي اللحظي** | احتساب فوري داخل المتصفح لـ (`units`, `consumptionCost`, `totalDue`, `remaining`) وتحديث فوري للتذييل والبطاقات | انتظار استجابة السيرفر وتحديث البيانات عبر React Query Refetch | دوال نقية `calculateRowTotals` و `calculateFooterTotals` تعمل فور كتابة أي رقم وتحدث الواجهة بدون وميض. |
| **الوحدات المفقودة (Lost Units)** | يدعم التكلفة الكلية مع الوحدات المفقودة `(units + lost_units) * unit_price` | غير متوفرة كحقل تعديل في الواجهات القديمة | إضافة عمود `الوحدات المفقودة` مع الاحتساب الآلي في التكلفة وإجمالي المستحق. |
| **حقل المتأخرات (Arrears)** | مميز بلون وردي بارز `bg-rose-50/70 border-rose-300 text-rose-700` قابل للتعديل المباشر | معروض للقراءة فقط داخل بطاقات المشترك | تمييز الخانة باللون الوردي المعتمد مع إتاحة التعديل اللحظي الآمن. |
| **إرسال واعتماد الواتساب** | زر `معتمد` يفتح مباشرة رابط `https://wa.me/...` مع نص الفاتورة المنسق | استدعاء API يضيف الفاتورة لطابور الخلفية دون معاينة مباشرة للمستخدم | توفير زر الاعتماد والإرسال المباشر مع نافذة معاينة تتيح النسخ `navigator.clipboard` والفتح المباشر. |
| **شريط التذييل المثبت** | تذييل مثبت `sticky bottom-0` يجمع 5 إجماليات مالية وفنية تلقائياً | مجاميع مفرقة في أعلى الصفحة بدون تذييل مثبت للجدول | تذييل مثبت يعرض مجموع الاستهلاك، المتأخرات، إجمالي الاستحقاق، المدفوع، والمتبقي. |
| **بطاقات الـ KPI العلوية** | 5 بطاقات موحدة ومتناسقة مع هوية الألوان (Blue, Amber, Rose, Emerald, Slate) | بطاقات متغيرة ومتباينة بين الصفحات | توحيد شبكة البطاقات الخمس في كافة الشاشات الرئيسية. |
| **تصدير Excel / CSV** | تصدير فوري لملف CSV بترميز UTF-8 BOM شامل كافة الحقول المحسوبة | تصدير عبر استدعاءات API أو SheetJS متباينة | توحيد وظيفة التصدير لتشمل جميع الحقول الـ 18 المحسوبة بدقة. |
| **تبويب التعديلات المعتمدة والباقات** | ملغاة ومدمجة في التعديل المباشر والتعرفة الموحدة | صفحات وتبويبات منفصلة تشوش تدفق العمل | حذف مسار `ApprovedEdits` و `PlansManagement` بالكامل وفقاً لـ R4. |
| **تبويب التقارير الشامل** | مركز تقارير موحد | تقارير متفرقة | إنشاء صفحة `ReportsHub.tsx` موحدة تحتوي كافة التقارير والتدقيق والمقارنات. |

---

## 3. التحفظات والاعتبارات الفنية (Caveats)

1. **دقة الحسابات المالية ومنع الأخطاء التقريبية**:
   - يجب أن تتم جميع العمليات الحسابية للأرقام العشرية بالاعتماد على التحويل الصارم لـ `Number(val) || 0` وتجنب معالجة القيم الفارغة كـ `NaN`.
   - استخدام `toLocaleString('en-US')` حصراً لفرض الأرقام الإنجليزية ومنع ظهور الأرقام المشرقية في أي خانة.
2. **استراتيجية الحفظ التلقائي (Auto-Save on Blur vs Optimistic Updates)**:
   - عند تعديل الخلية: يُحدَّث الـ Local State فوراً عبر `onChange` لضمان تجاوب الواجهة اللحظي بدون أي تأخير (0ms latency).
   - عند `onBlur` (أو الضغط على مفتاح Enter): يتم إرسال طلب التحديث إلى الـ Backend API. في حال فشل الطلب، يتم إظهار إشعار خطأ والتراجع للخلية إلى قيمتها السابقة (Rollback).
3. **أرقام الهواتف اليمنية والروابط المباشرة للواتساب**:
   - عند توليد رابط `wa.me/967...`: يجب تنظيف رقم الهاتف وإزالة الصفر المسبوق والتأكد من إضافة رمز الدولة `967` تلقائياً.

---

## 4. الخلاصة والمواصفات المعمارية الدقيقة (Conclusion & Technical Specification)

### أ. مواصفات مكون كشف العمليات وجدول الفواتير التفاعلي (18 عموداً)
توزيع الأعمدة بالترتيب الدقيق من اليمين إلى اليسار (RTL):

| # | اسم العمود (بالعربية) | نوع الخلية | النمط البصري ومحددات Tailwind | السلوك الحسابي والتفاعلي |
|---|---|---|---|---|
| 1 | `#` (التسلسل) | نص ثابت | `w-10 text-center bg-slate-200 text-slate-400 font-mono text-[11px]` | رقم تسلسلي للسطر الظاهر بعد الفلترة |
| 2 | `الإرسال المعتمد` | زر إجراء | `w-24 text-center bg-emerald-50/80` مع زر `bg-emerald-600 hover:bg-emerald-700 text-white` | اعتماد السطر + فتح نافذة/رابط الواتساب المعتمد |
| 3 | `رقم المشترك` | إدخال نصي | `font-mono text-slate-800 text-xs` | قابل للتعديل المباشر (Auto-Save on Blur) |
| 4 | `خط السير` | إدخال نصي | `w-16 text-center font-mono text-slate-700 text-xs` | قابل للتعديل المباشر |
| 5 | `اسم المشترك` | إدخال نصي | `min-w-[170px] text-slate-900 font-bold text-xs` | قابل للتعديل المباشر |
| 6 | `العنوان` | إدخال نصي | `min-w-[110px] text-slate-600 text-[11px]` | قابل للتعديل المباشر |
| 7 | `رقم العداد` | إدخال نصي | `min-w-[100px] font-mono text-slate-700 text-xs` | قابل للتعديل المباشر |
| 8 | `الهاتف` | إدخال نصي | `min-w-[100px] font-mono font-bold text-emerald-800 text-xs` | قابل للتعديل المباشر مع التحقق من الهواتف اليمنية |
| 9 | `السابقة` | إدخال رقمي | `bg-slate-50 font-mono font-bold text-amber-900 text-left text-xs` | قابل للتعديل المباشر (يحدث الاستهلاك فورياً) |
| 10 | `الحالية` | إدخال رقمي | `bg-slate-50 font-mono font-bold text-blue-900 text-left text-xs` | قابل للتعديل المباشر (يحدث الاستهلاك فورياً) |
| 11 | `الاستهلاك` | محسوب آلياً | `bg-amber-100/40 text-amber-900 text-center font-bold font-mono text-xs` | `Math.max(0, currReading - prevReading)` |
| 12 | `الوحدات المفقودة` | إدخال رقمي | `bg-amber-50 font-mono font-bold text-amber-800 text-left text-xs` | قابل للتعديل المباشر (يضاف للاستهلاك المحاسبي) |
| 13 | `سعر الوحدة` | إدخال رقمي | `font-mono text-slate-700 text-left text-xs` | قابل للتعديل المباشر أو عبر التعرفة الموحدة |
| 14 | `قيمة الاستهلاك` | محسوب آلياً | `font-mono font-bold text-slate-800 text-left text-xs` | `(units + lostUnits) * unitPrice` |
| 15 | `رسوم خدمة` | إدخال رقمي | `font-mono text-slate-700 text-left text-xs` | قابل للتعديل المباشر |
| 16 | `المتأخرات` | إدخال بارز | `bg-rose-50/70 border-x-2 border-rose-300 text-rose-700 font-bold font-mono text-left text-xs` | قابل للتعديل المباشر (يحدث إجمالي المستحق فورياً) |
| 17 | `إجمالي المستحق` | محسوب آلياً | `bg-emerald-50/60 text-emerald-800 font-bold font-mono text-left text-xs` | `consumptionCost + serviceFee + arrears` |
| 18 | `المدفوع` | إدخال رقمي | `font-mono font-bold text-blue-700 text-left text-xs` | قابل للتعديل المباشر (يحدث المتبقي فورياً) |
| 19 | `المتبقي` | محسوب آلياً | `font-mono font-bold text-left text-xs (text-amber-800 أو slate-500)` | `totalDue - paidAmount` |
| 20 | `معاينة` | زر أيقونة | `w-12 text-center text-slate-400 hover:text-slate-700` | يفتح نافذة المعاينة التفاعلية للفاتورة |
| 21 | `حذف` | زر أيقونة | `w-12 text-center text-slate-400 hover:text-rose-600` | يفتح نافذة التأكيد المخصصة لحذف السطر |

---

### ب. مواصفات TypeScript لمحرك التعديل المباشر وإعادة الاحتساب الفوري

```typescript
// frontend/src/types/excelGrid.types.ts

export interface GridRowData {
  id: number;
  subNumber: string;
  route: string;
  name: string;
  address: string;
  meterNumber: string;
  phone: string;
  prevReading: number;
  currReading: number;
  lostUnits: number;
  unitPrice: number;
  serviceFee: number;
  arrears: number;
  paidAmount: number;
  sent?: boolean;
  approvalStatus?: 'PENDING' | 'APPROVED' | 'REJECTED';
  overdueDays?: number;
}

export interface ComputedGridRow extends GridRowData {
  units: number;
  lostUnitsCost: number;
  consumptionCost: number;
  totalDue: number;
  remaining: number;
}

export interface GridFooterTotals {
  visibleCount: number;
  totalUnitsSum: number;
  totalLostUnitsSum: number;
  totalArrearsSum: number;
  totalConsumptionCostSum: number;
  totalDueSum: number;
  totalPaidSum: number;
  totalRemainingSum: number;
}

/**
 * دالة الحساب المالي النقية للسطر الفردي
 */
export function computeRowFinancials(row: GridRowData): ComputedGridRow {
  const prev = Number(row.prevReading) || 0;
  const curr = Number(row.currReading) || 0;
  const units = Math.max(0, curr - prev);
  const lostUnits = Number(row.lostUnits) || 0;
  const unitPrice = Number(row.unitPrice) || 0;
  
  const consumptionCost = units * unitPrice;
  const lostUnitsCost = lostUnits * unitPrice;
  const serviceFee = Number(row.serviceFee) || 0;
  const arrears = Number(row.arrears) || 0;

  // إجمالي المستحق = قيمة الاستهلاك + تكلفة الفاقد + رسوم الخدمة + المتأخرات
  const totalDue = consumptionCost + lostUnitsCost + serviceFee + arrears;
  const paid = Number(row.paidAmount) || 0;
  const remaining = totalDue - paid;

  return {
    ...row,
    units,
    lostUnitsCost,
    consumptionCost,
    totalDue,
    remaining,
  };
}

/**
 * دالة احتساب إجماليات التذييل المثبت والبطاقات العلوية
 */
export function computeGridTotals(rows: ComputedGridRow[]): GridFooterTotals {
  return rows.reduce(
    (acc, row) => ({
      visibleCount: acc.visibleCount + 1,
      totalUnitsSum: acc.totalUnitsSum + row.units,
      totalLostUnitsSum: acc.totalLostUnitsSum + (Number(row.lostUnits) || 0),
      totalArrearsSum: acc.totalArrearsSum + (Number(row.arrears) || 0),
      totalConsumptionCostSum: acc.totalConsumptionCostSum + row.consumptionCost,
      totalDueSum: acc.totalDueSum + row.totalDue,
      totalPaidSum: acc.totalPaidSum + (Number(row.paidAmount) || 0),
      totalRemainingSum: acc.totalRemainingSum + row.remaining,
    }),
    {
      visibleCount: 0,
      totalUnitsSum: 0,
      totalLostUnitsSum: 0,
      totalArrearsSum: 0,
      totalConsumptionCostSum: 0,
      totalDueSum: 0,
      totalPaidSum: 0,
      totalRemainingSum: 0,
    }
  );
}
```

---

## 5. طريقة التحقق المستقلة (Verification Method)

1. **التحقق البصري والوظيفي لكشف الإكسل**:
   - مطابقة الأعمدة الـ 18 والتنسيق اللوني بالكامل مع `code_artifact (8).html`.
   - تعديل أي قيمة (مثلاً تعديل القراءة الحالية أو المتأخرات) وملاحظة التحديث الفوري للسطر والتذييل والبطاقات العلوية بدون وميض وبدون الحاجة لإعادة تحميل الصفحة.
2. **التحقق من قالب الواتساب والمودال**:
   - الضغط على أيقونة المعاينة والتحقق من تطابق نص الفاتورة وزري النسخ والإرسال المباشر.
3. **التحقق من خلو الأرقام من أي محارف عربية مشرقية**:
   - فحص كافة الحقول والتأكد من استخدام التنسيق الإنجليزي `en-US` (0, 1, 2, 3...).
4. **فحص بناء الواجهة الأمامية**:
   - تشغيل أمر البناء للتأكد من انعدام أخطاء TypeScript:
     ```powershell
     cd frontend
     npm run build
     ```
