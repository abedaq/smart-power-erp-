<div dir="rtl">

# التحليل الفني الشامل وخطة تصحيح المعادلات المالية في المخطط المعماري
## (Financial Formula Remediation Analysis & Canonical Alignment Plan)
### مرجع الوثيقة: `d:\elctercity\MIGRATION\MASTER_PLAN.md`

- **المُعد**: `explorer_m1_r2_formula_fix` (Financial Formula Remediation Explorer)
- **الموجه المستلم**: `orchestrator_migration` (Conversation ID: `8662d701-dced-4ddd-b545-e2b64c0e3fc2`)
- **التاريخ**: 2026-09-06T09:07:00Z
- **النطاق**: تصحيح غموض معادلات الفاقد والاستهلاك وإجمالي المستحق، وتحقيق التطابق المحاسبي 100% بين متطلبات المستخدم، وقاعدة البيانات، وخادم Go، والواجهة الأمامية، ومطبوعات الفواتير A5، والواتساب.

---

## 1. التوصيف الفني للمشكلة وجذور الغموض المحاسبي (Root Cause Analysis)

### 1.1 الملاحظة الفنية والانحراف عن طلب المستخدم الأصلي
كشفت مراجعة الناقد المستقل `reviewer_m1_2` في تقريره (`reviewer_m1_2/handoff.md`، السطور 70-91 و 149-157) عن وجود خلل جوهري في صياغة معادلات الفوترة الأساسية في `d:\elctercity\MIGRATION\MASTER_PLAN.md` (السطور 48-55):

```markdown
2. **تكلفة الوحدات المفقودة (Lost Units Cost)**:
   $$\text{LostUnitsCost} = \text{Round}(\text{LostUnits} \times \text{UnitPrice}, 2)$$
3. **إجمالي تكلفة الاستهلاك (Consumption Cost)**:
   $$\text{ConsumptionCost} = \text{Round}((\text{Consumption} + \text{LostUnits}) \times \text{UnitPrice}, 2)$$
4. **إجمالي المبلغ المستحق (Total Due)**:
   $$\text{TotalDue} = \text{Round}(\text{ConsumptionCost} + \text{FixedServiceFee} + \text{Arrears}, 2)$$
5. **المبلغ المتبقي (Remaining Amount)**:
   $$\text{RemainingAmount} = \max(0, \text{Round}(\text{TotalDue} - \text{PaidAmount}, 2))$$
```

### 1.2 أوجه الخلل الأربعة الناتجة عن هذه الصياغة:
1. **التعارض المباشر مع متطلبات طلب المستخدم المرجعي (ORIGINAL_REQUEST.md)**:
   - ينص طلب المستخدم الأصلي الصريح في `ORIGINAL_REQUEST.md` (§ 2026-09-02T17:07:57Z R1) حرفياً على:
     ```text
     Auto-calculate: 
     - Consumption = Current - Previous
     - Lost Units Cost = Lost Units * Unit Price
     - Consumption Cost = Consumption * Unit Price
     - Total Due = Consumption Cost + Fixed Fee + Lost Units Cost + Arrears
     - Remaining = Total Due - Paid
     ```
   - متطلبات المستخدم تقضي صراحة بأن تكلفة الاستهلاك (`Consumption Cost`) تخص حصرياً استهلاك العداد الفعلي (`Consumption * Unit Price`)، بينما تكلفة الوحدات المفقودة (`Lost Units Cost`) تُحسب كبند منفصل (`Lost Units * Unit Price`)، ثم يُجمع الاثنان مع الرسوم الثابتة والمتأخرات لتكوين إجمالي المستحق (`Total Due`).

2. **ظاهرة المتغير المهمل (Orphan Variable Syndrome)**:
   - في صياغة `MASTER_PLAN.md` الحالية، تم تعريف المتغير `LostUnitsCost` في البند 2، ولكن عند حساب `TotalDue` في البند 4 لم يُستخدم المتغير `LostUnitsCost` على الإطلاق؛ لأنه دُمج تعسفياً داخل `ConsumptionCost` في البند 3. هذا التناقض يجعل البند 2 متغير حسابي ميت (Dead Code / Orphan Formula).

3. **التضارب والوهم المحاسبي في واجهة المستخدم (UI Arithmetic Illusion)**:
   - في واجهة شبكة الإكسل التفاعلية الـ 18 عموداً (`TodayReadingsReview.tsx` و `ExcelGrid.tsx` و `code_artifact (8).html`)، توجد أعمدة منفصلة ومعلنة للمستخدم والمحصل:
     - عمود: **الاستهلاك** (Consumption)
     - عمود: **الوحدات المفقودة** (Lost Units)
     - عمود: **سعر الوحدة** (Unit Price)
     - عمود: **قيمة الاستهلاك** (Consumption Cost)
   - إذا تم تطبيق معادلة `MASTER_PLAN.md` الحالية بحساب `ConsumptionCost = (Consumption + LostUnits) * UnitPrice`:
     - لو كان الاستهلاك = 100 ك.و، والوحدات المفقودة = 20 ك.و، وسعر الوحدة = 1000 ريال.
     - سيظهر في الجدول: الاستهلاك = 100، سعر الوحدة = 1000، ولكن عمود "قيمة الاستهلاك" = 120,000 ريال!
     - المشترك أو المحصل سيرى خللاً حسابياً فادحاً بالعين المجردة لأن: $100 \times 1000 \ne 120,000$.
     - بينما الصياغة الصحيحة المعتمدة تفرض: قيمة الاستهلاك = $100 \times 1000 = 100,000$ ريال، وتكلفة الفاقد = $20 \times 1000 = 20,000$ ريال، وإجمالي المستحق يجمع $100,000 + 20,000 = 120,000$ ريال بكل شفافية.

4. **إسقاط تكلفة الوحدات المفقودة فعلياً في كود الفرونت إند الحالي**:
   - بالتحقق المادي من كود الواجهة الأمامية في `frontend/src/types/excelGrid.types.ts` (السطور 64-69):
     ```typescript
     const consumptionCost = units * unitPrice;
     const lostUnitsCost = lostUnits * unitPrice;
     const serviceFee = parseNum(row.serviceFee);
     const arrears = parseNum(row.arrears);

     const totalDue = consumptionCost + serviceFee + arrears;
     ```
   - أظهر الفحص أن المبرمج حسب `consumptionCost` على أساس `units * unitPrice` فقط، وحسب `lostUnitsCost = lostUnits * unitPrice`، ولكنه عند حساب `totalDue` أسقط تماماً `lostUnitsCost` ظناً منه أن `consumptionCost` سيحتويه أو نتيجة نسيان برمجى! وبناءً عليه، فإن أي إدخال لوحدات مفقودة في الواجهة الحالية لا يتم احتسابه نهائياً في الفاتورة أو المتبقي، مما يسبب خسائر مالية تراكمية للمحطة.

---

## 2. النموذج المحاسبي القياسي الموحد (Canonical Financial Model)

لتوحيد العمليات الرياضية والمحاسبية بنسبة 100% وإزالة أي لبس عبر كافة طبقات النظام (قاعدة البيانات، خادم Go، الواجهة الأمامية، ونموذج الفاتورة A5)، يتم اعتماد المعادلات الحتمية التالية:

### 2.1 المعادلات الرياضية الحتمية
1. **كمية الاستهلاك الفعلي للمشترك (Actual Meter Consumption)**:
   $$\text{Consumption} = \max(0, \text{CurrentReading} - \text{PreviousReading})$$
   - *القيد الحاكم*: $\text{CurrentReading} \ge \text{PreviousReading}$ (قيد عداد غير تنازلي إلزامي).

2. **تكلفة الاستهلاك الفعلي (Base Consumption Cost)**:
   $$\text{ConsumptionCost} = \text{Round}(\text{Consumption} \times \text{UnitPrice}, 2)$$
   - يمثل القيمة المالية الصافية للطاقة المقروءة عبر عداد المشترك.

3. **تكلفة الوحدات المفقودة (Lost Units Cost)**:
   $$\text{LostUnitsCost} = \text{Round}(\max(0, \text{LostUnits}) \times \text{UnitPrice}, 2)$$
   - يمثل القيمة المالية المترتبة على فاقد الطاقة أو التوصيلات المباشرة المعتمدة لهذا المشترك.

4. **إجمالي تكلفة الطاقة الكلية (Total Energy Value — المفهوم المرجعي للتدقيق)**:
   $$\text{TotalEnergyValue} = \text{ConsumptionCost} + \text{LostUnitsCost} = \text{Round}((\text{Consumption} + \text{LostUnits}) \times \text{UnitPrice}, 2)$$

5. **إجمالي المبلغ المستحق للدورة (Total Due)**:
   $$\text{TotalDue} = \text{Round}(\text{ConsumptionCost} + \text{LostUnitsCost} + \text{ServiceFee} + \text{Arrears}, 2)$$
   - الجمع صريح ولا يقبل اللبس: تكلفة الاستهلاك الصافي + تكلفة الفاقد + رسوم الخدمة الثابتة + المتأخرات السابقة.

6. **المبلغ المتبقي قيد التحصيل (Remaining Amount)**:
   $$\text{RemainingAmount} = \max(0, \text{Round}(\text{TotalDue} - \text{PaidAmount}, 2))$$

---

## 3. مصفوفة التطابق المعماري عبر الطبقات (Cross-Layer Architecture Alignment Matrix)

يوضح الجدول التالي الربط الدقيق بين المفاهيم المحاسبية وكافة طبقات النظام لضمان التوافق التام أثناء تنفيذ المراحل M2 و M3 و M4 و M5:

| المفهوم المحاسبي | المعادلة الرياضية المعتمدة | حقل قاعدة البيانات (`smartpower_db.invoices`) | حقل خادم Go (`server.exe` Struct) | حقل الواجهة الأمامية (`excelGrid.types.ts`) | عمود شبكة الإكسل (18 عمود) | عمود الفاتورة الرسمية A5 (7 أعمدة) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **القراءة السابقة** | مدخلة / مرحلة من الدورة $T-1$ | `previous_reading` (NUMERIC 12,2) | `PreviousReading` (`decimal.Decimal`) | `prevReading` (`number`) | السابقة | ق. السابقة |
| **القراءة الحالية** | مدخلة من المحصل / العداد | `current_reading` (NUMERIC 12,2) | `CurrentReading` (`decimal.Decimal`) | `currReading` (`number`) | الحالية | ق. الحالية |
| **كمية الاستهلاك** | $\max(0, \text{Curr} - \text{Prev})$ | `consumption` (NUMERIC 12,2) | `Consumption` (`decimal.Decimal`) | `units` (`number`) | الاستهلاك | الفارق |
| **الوحدات المفقودة** | مدخلة (افتراضي: 0) | `lost_units` (NUMERIC 12,2) | `LostUnits` (`decimal.Decimal`) | `lostUnits` (`number`) | الوحدات المفقودة | *(مدمجة بالإجمالي)* |
| **سعر الوحدة** | تعرفة المشترك / الباقة | `kwh_price_snapshot` (NUMERIC 10,2) | `UnitPrice` (`decimal.Decimal`) | `unitPrice` (`number`) | سعر الوحدة | *(التعرفة المعتمدة)* |
| **تكلفة الاستهلاك** | $\text{Consumption} \times \text{Price}$ | `consumption_value` (NUMERIC 12,2) | `ConsumptionCost` (`decimal.Decimal`) | `consumptionCost` (`number`) | قيمة الاستهلاك | القيمـة |
| **تكلفة الفاقد** | $\text{LostUnits} \times \text{Price}$ | `lost_units_value` (NUMERIC 12,2) | `LostUnitsCost` (`decimal.Decimal`) | `lostUnitsCost` (`number`) | *(حساب داخلي)* | *(مدمجة بالإجمالي)* |
| **رسوم الخدمة** | الرسوم الثابتة للاشتراك | `fixed_fee_snapshot` (NUMERIC 10,2) | `ServiceFee` (`decimal.Decimal`) | `serviceFee` (`number`) | رسوم خدمة | اشتراك |
| **المتأخرات** | متبقي الدورة $T-1$ | `arrears` (NUMERIC 12,2) | `Arrears` (`decimal.Decimal`) | `arrears` (`number`) | المتأخرات | متأخرات |
| **إجمالي المستحق** | $\text{ConsCost} + \text{LostCost} + \text{Fee} + \text{Arr}$ | `total_due` (NUMERIC 12,2) | `TotalDue` (`decimal.Decimal`) | `totalDue` (`number`) | إجمالي المستحق | الاجمالي |
| **المدفوع** | مجموع سندات القبض الموزعة | `paid_amount` (NUMERIC 12,2) | `PaidAmount` (`decimal.Decimal`) | `paidAmount` (`number`) | المدفوع | *(سند القبض)* |
| **المتبقي** | $\max(0, \text{TotalDue} - \text{Paid})$ | `remaining_amount` (NUMERIC 12,2) | `RemainingAmount` (`decimal.Decimal`) | `remaining` (`number`) | المتبقي | *(الرصيد المتبقي)* |

---

## 4. نص التعديل الدقيق المطلوب تطبيقه في `MIGRATION/MASTER_PLAN.md`

### 4.1 التعديل المستهدف في القسم 2.1 (السطور 42-56)

#### النص الحالي في `MASTER_PLAN.md`:
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

#### النص البديل الدقيق والمعتمد الموصى بإحلاله في `MASTER_PLAN.md`:
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
في القسم 2.4 من `MASTER_PLAN.md` (السطر 89):
- **النص الحالي**:
  `2. يُعاد احتساب الدورة $T$ بالقيم الجديدة.`
- **النص المعدل الموصى به**:
  `2. يُعاد احتساب الدورة $T$ بالقيم الجديدة وفق النموذج القياسي المعتمد: إعادة احتساب تكلفة الاستهلاك الصافي $\text{ConsumptionCost}$، وتكلفة الفاقد $\text{LostUnitsCost}$، وإجمالي المستحق $\text{TotalDue} = \text{ConsumptionCost} + \text{LostUnitsCost} + \text{FixedServiceFee} + \text{Arrears}$، والرصيد المتبقي $\text{RemainingAmount}$.`

---

## 5. خطة التوجيه التنفيذي للمراحل القادمة (Implementation Roadmap Guidance)

1. **المرحلة M2 (قاعدة البيانات والنزاهة المالية)**:
   - إضافة عمود `lost_units_value NUMERIC(12,2) DEFAULT 0 NOT NULL` في جدول `invoices` بـ `smartpower_db`.
   - صياغة دالة التخزين `rpc_submit_meter_reading` و `fn_recalculate_cycle` لاحتساب:
     ```sql
     v_consumption_value := ROUND(v_consumption * v_kwh_price, 2);
     v_lost_units_value := ROUND(COALESCE(p_lost_units, 0) * v_kwh_price, 2);
     v_total_due := ROUND(v_consumption_value + v_lost_units_value + v_fixed_fee + v_arrears, 2);
     ```
   - فرض قيد التحقق في الجدول:
     ```sql
     CHECK (total_due = consumption_value + lost_units_value + fixed_fee_snapshot + arrears);
     ```

2. **المرحلة M3 (خادم Go المستقل `server.exe`)**:
   - استخدام مكتبة `github.com/shopspring/decimal` للحسابات المالية بالدقة العشرية الثنائية وتفادي أخطاء الفاصلة العائمة (Float Drift).
   - توحيد دالة `CalculateCycleFinancials` في Go لتطابق نموذج الـ 6 معادلات المعتمد.

3. **المرحلة M4 (الواجهة الأمامية React Desktop)**:
   - إصلاح السطر 69 في `frontend/src/types/excelGrid.types.ts`:
     ```typescript
     // تصحيح: إضافة lostUnitsCost إلى totalDue
     const totalDue = consumptionCost + lostUnitsCost + serviceFee + arrears;
     ```
   - تحديث نموذج رسالة الواتساب `buildWhatsAppText` لإظهار بند الفاقد بوضوح إذا كان أكبر من الصفر (`row.lostUnits > 0`).

---

## 6. التحقق والاختبار (Verification Method)

للتأكد المستقل من صحة العلاقات الحسابية والتطابق:
1. **فحص خلو ملف الخطة والتحليل من الأرقام المشرقية**:
   ```powershell
   $content = Get-Content -LiteralPath "d:\elctercity\.agents\explorer_m1_r2_formula_fix\analysis.md" -Raw -Encoding UTF8
   $matches = [regex]::Matches($content, "[\u0660-\u0669\u06F0-\u06F9]")
   Write-Host "Eastern numerals count: $($matches.Count)"
   ```
2. **التحقق من معادلات الحساب بمثال رقمي قطعي**:
   - $\text{Prev} = 1200$, $\text{Curr} = 1350$ $\implies$ $\text{Consumption} = 150$.
   - $\text{LostUnits} = 25$, $\text{UnitPrice} = 1400$.
   - $\text{ConsumptionCost} = 150 \times 1400 = 210,000$ ر.ي.
   - $\text{LostUnitsCost} = 25 \times 1400 = 35,000$ ر.ي.
   - $\text{ServiceFee} = 1,000$ ر.ي، $\text{Arrears} = 5,000$ ر.ي.
   - $\text{TotalDue} = 210,000 + 35,000 + 1,000 + 5,000 = 251,000$ ر.ي.
   - $\text{Paid} = 200,000$ ر.ي $\implies$ $\text{Remaining} = 51,000$ ر.ي.
   - الناتج متطابق وخالٍ من أي تعارض بنسبة 100%.

</div>
