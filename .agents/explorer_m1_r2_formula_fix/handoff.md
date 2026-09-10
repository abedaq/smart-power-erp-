# تقرير التسليم النهائي — معالجة وتوحيد المعادلات المالية في المخطط المعماري
## (Handoff Report: Financial Formula Remediation for MASTER_PLAN.md)

<div dir="rtl">

- **المُعد**: `explorer_m1_r2_formula_fix` (Financial Formula Remediation Explorer)
- **الموجه المستلم**: `orchestrator_migration` (Conversation ID: `8662d701-dced-4ddd-b545-e2b64c0e3fc2`)
- **تاريخ الإنجاز**: 2026-09-06T09:07:00Z
- **نوع التسليم**: Hard Handoff (مكتمل بالكامل ومستوفٍ لكافة الشروط والأدلة)
- **الملف التحليلي الشامل المرجعي**: `d:\elctercity\.agents\explorer_m1_r2_formula_fix\analysis.md`

---

## 1. الملاحظات المادية المباشرة (Observation)

### 1.1 فحص معادلات الفوترة في `d:\elctercity\MIGRATION\MASTER_PLAN.md`
- **الموقع المادي**: السطور 42 إلى 56.
- **النص الحرفي المرصود**:
  ```markdown
  ### 2.1 معادلات الاستهلاك والفوترة الأساسية
  1. **قيمة الاستهلاك (Consumption)**:
     $$\text{Consumption} = \max(0, \text{CurrentReading} - \text{PreviousReading})$$
     - **قيد العداد غير التنازلي (Monotonic Reading Guard)**:
       - يُمنع منعاً باتاً تسجيل أي قراءة حالية تقل عن القراءة السابقة للعداد للمشترك النشط (`CurrentReading >= PreviousReading`).
       - يتم فرض هذا القيد في قاعدة البيانات (`CHECK constraint` وفي كود الـ Stored Procedure) وفي طبقة الخادم؛ وتُرفض القراءة المخالفة فوراً برسالة عربية واضحة: *"القراءة المدخلة أقل من القراءة السابقة المسجلة للعداد"*.
  2. **تكلفة الوحدات المفقودة (Lost Units Cost)**:
     $$\text{LostUnitsCost} = \text{Round}(\text{LostUnits} \times \text{UnitPrice}, 2)$$
  3. **إجمالي تكلفة الاستهلاك (Consumption Cost)**:
     $$\text{ConsumptionCost} = \text{Round}((\text{Consumption} + \text{LostUnits}) \times \text{UnitPrice}, 2)$$
  4. **إجمالي المبلغ المستحق (Total Due)**:
     $$\text{TotalDue} = \text{Round}(\text{ConsumptionCost} + \text{FixedServiceFee} + \text{Arrears}, 2)$$
  5. **المبلغ المتبقي (Remaining Amount)**:
     $$\text{RemainingAmount} = \max(0, \text{Round}(\text{TotalDue} - \text{PaidAmount}, 2))$$
  ```
- **الملاحظة الحرفية**:
  - تم تعريف `LostUnitsCost` في البند 2، ولكن تم إسقاطه تماماً من معادلة `TotalDue` في البند 4.
  - تم دمج `LostUnits` داخل `ConsumptionCost` في البند 3 بصيغة: $(\text{Consumption} + \text{LostUnits}) \times \text{UnitPrice}$.

### 1.2 فحص متطلبات المستخدم الأصلية في `d:\elctercity\.agents\ORIGINAL_REQUEST.md`
- **الموقع المادي**: القسم § 2026-09-02T17:07:57Z، البند R1، السطر 16.
- **النص الحرفي المرصود**:
  ```text
  Auto-calculate: Consumption = Current - Previous, Lost Units Cost = Lost Units * Unit Price, Total Due = Consumption Cost + Fixed Fee + Lost Units Cost + Arrears, Remaining = Total Due - Paid.
  ```
- **الملاحظة الحرفية**:
  - نص طلب المستخدم المرجعي على فصل صريح وقاطع: `Consumption Cost` يخص الاستهلاك الصافي للعداد فقط، و `Lost Units Cost` يُحسب بصورة منفصلة، ويُضاف كلاهما صراحة إلى `Total Due`.

### 1.3 فحص كود الواجهة الأمامية في `d:\elctercity\frontend\src\types\excelGrid.types.ts`
- **الموقع المادي**: السطور 43-50 والسطور 64-71.
- **النص الحرفي المرصود**:
  ```typescript
  // السطور 43-50:
  /**
   * Pure calculation of financial values for a single row.
   * Units = Math.max(0, currReading - prevReading)
   * Consumption Cost = Units * Unit Price
   * Lost Units Cost = Lost Units * Unit Price
   * Total Due = Consumption Cost + Lost Units Cost + Service Fee + Arrears
   * Remaining = Total Due - Paid Amount
   */

  // السطور 64-71:
  const consumptionCost = units * unitPrice;
  const lostUnitsCost = lostUnits * unitPrice;
  const serviceFee = parseNum(row.serviceFee);
  const arrears = parseNum(row.arrears);

  const totalDue = consumptionCost + serviceFee + arrears;
  const paid = parseNum(row.paidAmount);
  const remaining = totalDue - paid;
  ```
- **الملاحظة الحرفية**:
  - التوثيق النصي للدالة (السطور 43-50) يطابق بدقة طلب المستخدم بفصل `Consumption Cost` وإضافة `Lost Units Cost` إلى `Total Due`.
  - بينما الكود التنفيذي الفعلي (السطر 69) أسقط `lostUnitsCost` تماماً من حساب `totalDue` بسبب الارتباك الناشئ عن دمج الفاقد في الباك إند القديم (`recalculation.service.ts`)، مما أدى لعدم فوترة الوحدات المفقودة في الواجهة الحالية.

### 1.4 فحص تقرير المراجعة الفنية `d:\elctercity\.agents\reviewer_m1_2\handoff.md`
- **الموقع المادي**: السطور 70-91 والسطور 149-157 (الملاحظة 3).
- **الملاحظة الحرفية**: اعتبر المراجع المستقل هذا الغموض عيباً معمارياً رئيساً (`[Major] Finding`) وألزم بصياغة نموذج قطعي لا يقبل اللبس يفصل تكلفة الاستهلاك الصافي عن تكلفة الفاقد.

---

## 2. السلسلة المنطقية (Logic Chain)

1. **الاستناد إلى الملاحظة 1.2 والملاحظة 1.1**:
   - طلب المستخدم الأصلي هو المرجع الأعلى والنهائي للنظام. ودمج `LostUnits` داخل `ConsumptionCost` في `MASTER_PLAN.md` خالف هذا الأصل الصريح وخلق متغيراً مهملاً (`LostUnitsCost`) لا يدخل في معادلة المجموع `TotalDue`.
2. **الاستناد إلى الملاحظة 1.3**:
   - أثبت فحص كود الواجهة الأمامية أن الغموض لم يكن مجرد اختلاف شكلي في الوثائق، بل تسرب إلى الكود التنفيذي وتسبب في إسقاط تكلفة الوحدات المفقودة (`lostUnitsCost`) من معادلة `totalDue` في شبكة الإكسل (`excelGrid.types.ts` السطر 69)، مما يعني أن النظام كان يعرض إجمالي مستحق لا يشمل قيمة الفاقد.
3. **الاستناد إلى الملاحظة 1.1 والملاحظة 1.3**:
   - إذا تم الإبقاء على تعريف `ConsumptionCost = (Consumption + LostUnits) * UnitPrice`، فإن عمود "قيمة الاستهلاك" المعروض للمستخدم في جدول الإكسل سيخالف الحساب الذهني المباشر لحاصل ضرب (الاستهلاك $\times$ التعرفة)، مما يخلق التباساً وشكوكاً لدى المشتركين والمحصلين.
4. **الخلاصة المنطقية الحتمية**:
   - لا بد من اعتماد النموذج القياسي المنفصل في `MASTER_PLAN.md`، بحيث تكون كل خطوة حسابية مستقلة وشفافة، وتنعكس مباشرة في مخطط قاعدة البيانات، وبنية خادم Go، والواجهة الأمامية، ونموذج الفاتورة.

---

## 3. التحفظات والحدود (Caveats)

1. [مؤكد] لم يتم تعديل أي ملف كود برمجى خارج مجلد `.agents/explorer_m1_r2_formula_fix/` التزاماً بقواعد الحصانة الممنوحة للمستكشف وقاعدة عدم التعديل دون موافقة صريحة.
2. [مؤكد] في الفاتورة الرسمية المطبوعة بحجم A5 (`photo_5769554780358381104_y.jpg`)، يحتوي جدول الفاتورة على 7 أعمدة (ق. السابقة، ق. الحالية، الفارق، اشتراك، القيمة، متأخرات، الاجمالي). الوحدات المفقودة وتكلفتها تظهر وتُعدل في شبكة الإكسل الميدانية (18 عموداً)، بينما ينعكس أثرها المالي التراكمي في عمود "الاجمالي" بالفاتورة المطبوعة.

---

## 4. الخلاصة والحل المعتمد (Conclusion & Canonical Remedy)

### 4.1 التعديل الصريح المعتمد لـ `d:\elctercity\MIGRATION\MASTER_PLAN.md` (القسم 2.1)

يُستبدل المقطع الحالي بالصيغة القياسية الصارمة التالية:

```markdown
### 2.1 معادلات الاستهلاك والفوترة الأساسية
1. **كمية الاستهلاك الفعلي (Consumption)**:
   $$\text{Consumption} = \max(0, \text{CurrentReading} - \text{PreviousReading})$$
   - **قيد العداد غير التنازلي (Monotonic Reading Guard)**:
     - يُمنع منعاً باتاً تسجيل أي قراءة حالية تقل عن القراءة السابقة للعداد للمشترك النشط (`CurrentReading >= PreviousReading`).
     - يتم فرض هذا القيد في قاعدة البيانات (`CHECK constraint` وفي كود الـ Stored Procedure) وفي طبقة الخادم؛ وتُرفض القراءة المخالفة فوراً برسالة عربية واضحة: *"القراءة المدخلة أقل من القراءة السابقة المسجلة للعداد"*.
2. **تكلفة الاستهلاك الفعلي (Consumption Cost)**:
   $$\text{ConsumptionCost} = \text{Round}(\text{Consumption} \times \text{UnitPrice}, 2)$$
   - تمثل القيمة المالية المباشرة لاستهلاك العداد الفعلي، وتطابق عمود "قيمة الاستهلاك" في شبكة الإكسل وعمود "القيمـة" في الفاتورة الرسمية A5.
3. **تكلفة الوحدات المفقودة (Lost Units Cost)**:
   $$\text{LostUnitsCost} = \text{Round}(\max(0, \text{LostUnits}) \times \text{UnitPrice}, 2)$$
   - تمثل القيمة المالية المستقلة لوحدات الفاقد المعتمدة للمشترك، وتُفصل محاسبياً لمنع أي التباس بين استهلاك العداد الفعلي والفاقد.
4. **إجمالي المبلغ المستحق (Total Due)**:
   $$\text{TotalDue} = \text{Round}(\text{ConsumptionCost} + \text{LostUnitsCost} + \text{FixedServiceFee} + \text{Arrears}, 2)$$
   - يمثل إجمالي المطالبة المالية للدورة الفوترية الناتجة عن جمع تكلفة الاستهلاك الصافي وتكلفة الوحدات المفقودة ورسوم الخدمة الثابتة والمتأخرات السابقة.
5. **المبلغ المتبقي قيد التحصيل (Remaining Amount)**:
   $$\text{RemainingAmount} = \max(0, \text{Round}(\text{TotalDue} - \text{PaidAmount}, 2))$$
   - يمثل الرصيد المدين الفعلي المطلوب سداده بعد خصم كافة المدفوعات المسددة أو التوزيعات المائية المرتبطة بالفاتورة.
```

### 4.2 التعديل التكميلي في القسم 2.4 (الحساب التتابعي الرجعي للدورات)
تحديث البند 2 في القسم 2.4 ليصبح:
`2. يُعاد احتساب الدورة $T$ بالقيم الجديدة وفق النموذج القياسي المعتمد: إعادة احتساب تكلفة الاستهلاك الصافي $\text{ConsumptionCost}$، وتكلفة الفاقد $\text{LostUnitsCost}$، وإجمالي المستحق $\text{TotalDue} = \text{ConsumptionCost} + \text{LostUnitsCost} + \text{FixedServiceFee} + \text{Arrears}$، والرصيد المتبقي $\text{RemainingAmount}$.`

---

## 5. طريقة التحقق المستقل (Verification Method)

لتكرار التحقق والتأكد المستقل من صحة العلاقات الحسابية:

1. **التحقق من خلو ملفات التحليل والتسليم من أي أرقام مشرقية**:
   ```powershell
   Get-ChildItem -Path "d:\elctercity\.agents\explorer_m1_r2_formula_fix" -Filter "*.md" | ForEach-Object {
       $content = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
       $matches = [regex]::Matches($content, "[\u0660-\u0669\u06F0-\u06F9]")
       [PSCustomObject]@{ File = $_.Name; EasternNumeralsCount = $matches.Count }
   }
   ```
   *(النتيجة المتوقعة: صفر أرقام مشرقية في كافة الملفات)*.

2. **التحقق الحسابي التجريبي الحتمي**:
   ```powershell
   # تجربة حسابية رقمية
   $prev = 1200; $curr = 1350; $lost = 25; $price = 1400; $fee = 1000; $arrears = 5000; $paid = 200000
   $consumption = [Math]::Max(0, $curr - $prev)
   $consumptionCost = [Math]::Round($consumption * $price, 2)
   $lostUnitsCost = [Math]::Round($lost * $price, 2)
   $totalDue = [Math]::Round($consumptionCost + $lostUnitsCost + $fee + $arrears, 2)
   $remaining = [Math]::Max(0, [Math]::Round($totalDue - $paid, 2))
   
   [PSCustomObject]@{
       Consumption = $consumption;
       ConsumptionCost = $consumptionCost;
       LostUnitsCost = $lostUnitsCost;
       TotalDue = $totalDue;
       Remaining = $remaining
   }
   ```
   *(المخرجات الحرفية المتوقعة: Consumption=150, ConsumptionCost=210000, LostUnitsCost=35000, TotalDue=251000, Remaining=51000)*.

</div>
