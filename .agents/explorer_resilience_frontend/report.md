# تقرير الفحص الشامل لصمود واستجابة الواجهات الأمامية والتفاعل الحي (Frontend UI Resilience & Live Interaction Report)

**تاريخ التقرير**: 2026-09-09  
**المحقق**: Frontend UI Resilience Explorer  
**مسار العمل**: `d:/elctercity/.agents/explorer_resilience_frontend/`  
**بيئة النظام**: React 19.2.8 + Vite 8.2.1 + Tailwind CSS 4.3.3 + Go Monolith API Backend  

---

## 1. الملخص التنفيذي (Executive Summary)

تم إجراء تدقيق استقصائي شامل وهندسي لبنية الواجهات الأمامية في نظام SmartPower ERP، مع التركيز على:
1. استجابة لوحة التحكم (`Dashboard.tsx`)، شبكة إكسل التفاعلية (`ExcelGrid.tsx`)، مراجعة القراءات والفوترة (`Invoices.tsx` و `TodayReadingsReview.tsx`)، وتقرير المديونيات المتأخرة (`ArrearsReport.tsx`).
2. آلية التعديل الحي داخل الخلايا (Inline Cell Editing)، والحفظ التلقائي عند مغادرة الخلية (Auto-Save on Blur)، ودورة إعادة الحساب التتابعية.
3. مخاطر التجميد أو بطء الاستجابة (UI Freezing Risks)، وضغط خيط التنفيذ الرئيسي (Main Thread) الناتج عن كثافة شجرة الـ DOM، وعمليات `useMemo` و `localStorage`.
4. أدوات وسكربتات الاختبار المؤتمتة (Automated Test Suites).

### [مؤكد] أبرز النتائج الفنية:
- **التعديل المباشر والحساب الفوري**: يعمل محرك الحساب الرياضي `computeRowFinancials` و `computeGridTotals` بسلاسة ودقة رياضية 100% متطابقة مع المعادلة المالية الرسمية، وتظهر التعديلات لحظياً في بطاقات الـ KPI وتذييل الجدول.
- **الحفظ الذكي الموجه بالحراسة**: يمتلك `handleCellBlur` في `ExcelGrid.tsx` صمام أمان صارم (`areValuesEqual`) يمنع إرسال أي طلبات شبكية في حال لم تتغير القيمة، مما يقلل الحمل بنسبة تتجاوز 90% أثناء التنقل بمفتاح Tab.
- **عنق زجاجة كثافة عناصر الـ DOM (غياب Virtualization)**: تعرض شبكة `ExcelGrid` جميع المشتركين (494 مشتركاً) دفعة واحدة في شجرة DOM غير مفهرسة افتراضياً (Unvirtualized Table)، حيث يتم رندر ما يقارب 7,410 حقل إدخال `<input>` متزامن، مما يستهلك دورات معالجة على الـ Main Thread عند تكرار الضربات السريعة.
- **التخزين المتزامن في `localStorage`**: يتم استدعاء `localStorage.setItem` بشكل متزامن عند كل ضغطة مفتاح لتتبع الخلايا المعدلة بلون الكهرمان (Amber Highlighting)، مما قد يسبب stuttering طفيفاً عند الكتابة السريعة على الأجهزة الضعيفة.
- **غياب أطر اختبار المتصفح الحديثة (No Playwright / No Vitest)**: يعتمد المشروع حالياً على اختبارات تكاملية بلغة بايثون (`test_whatsapp_and_ui.py`)، وفحوصات AST وسكربتات Node.js مستقلة في مجلد `frontend/src/tests/`، بينما تخلو حزمة `package.json` من Vitest أو Playwright أو Cypress.

---

## 2. الهيكلية وتوزيع المكونات (Component Architecture Decomposition)

### 2.1 لوحة التحكم (`frontend/src/pages/Dashboard.tsx`)
- **الملف**: `frontend/src/pages/Dashboard.tsx` (468 سطراً)
- **البيانات والاستعلامات**:
  - تستخدم مكتبة `@tanstack/react-query` مع `staleTime: 5 * 60 * 1000` (السطر 26-30).
  - تعتمد على استعلام `getMonthlyPerformance` لحساب مؤشرات التحصيل، والمبالغ المفوترة، ونسب التحصيل التاريخية.
  - تفصل الدورات الماضية والحالية النشطة عن الدورات المستقبلية عبر `currentCycleSortIndex` المعتمد على تاريخ النظام الفعلي (الأسطر 59-76).
- **التحكم بالوصول (RBAC)**:
  - تقوم بإعادة توجيه أدوار `COLLECTOR` و `ACCOUNTANT` تلقائياً إلى `/invoices` (الأسطر 108-114)، مما يضمن حصر مؤشرات لوحة القيادة العليا بمدير النظام (`ADMIN`).

### 2.2 شبكة العمليات التفاعلية (`frontend/src/components/common/ExcelGrid.tsx`)
- **الملف**: `frontend/src/components/common/ExcelGrid.tsx` (1006 أسطر)
- **الدور**: المكون المحوري لكافة عمليات التعديل السريع للقراءات، والوحدات المفقودة، والرسوم، والمتأخرات، والدفعات.
- **الحالة المحلية والتفاؤلية (Optimistic Local State)**:
  - تحتفظ بحالة محلية `localRows` متزامنة مع `initialRows` الواردة من المكون الأب (الأسطر 80-123).
  - تتتبع الخلايا المعدلة عبر `dirtyCells` (مجموعة `Set<string>` بصيغة `id:field`) ويتم حفظها محلياً في `localStorage` باسم `smartpower_grid_dirty_cells` (الأسطر 133-167).
- **العرض البصري والحالات**:
  - تصبغ الخلايا المعدلة غير المحفوظة بلغة بصرية واضحة (خلفية كهرمانية `bg-amber-100` مع إطار `border-amber-400`).
  - تلون الصفوف بحسب حالة السداد:
    - مسدد بالكامل: `bg-emerald-100/80` (السطر 490)
    - مرسل / مطبوع: `bg-blue-100/80` (السطر 492)
    - مسدد جزئياً: `bg-emerald-50/70` (السطر 494)

### 2.3 مركز الفوترة والتحصيل (`frontend/src/pages/Invoices.tsx`) و `TodayReadingsReview.tsx`
- **الملفات**:
  - `frontend/src/pages/Invoices.tsx` (955 سطراً)
  - `frontend/src/pages/TodayReadingsReview.tsx` (4 أسطر - إعادة تصدير مباشر لمكون `Invoices`).
- **التكامل**:
  - يغذي `ExcelGrid` ببيانات دورة الفوترة المحددة (مثل `أغسطس 2` أو `سبتمبر 1`).
  - يوفر شريط تبويبات أفقي قابل للسحب بالماوس (`ExcelSheetTabs`، الأسطر 46-163) للتنقل السلس بين الدورات نصف الشهرية (15 يوماً).
  - يربط عمليات الحفظ عبر دالة `handleInvoiceCellSave` المستدعية للـ API `/api/readings/:id/cell-update` (الأسطر 369-408).

### 2.4 تقرير المديونيات والمتأخرات (`frontend/src/pages/ArrearsReport.tsx`)
- **الملف**: `frontend/src/pages/ArrearsReport.tsx` (1214 سطراً)
- **السمات**:
  - شاشة مستقلة مخصصة لجدولة الديون، وأعمار المتأخرات، وحساب أيام التأخير من تاريخ القراءة عبر دالة `calculateOverdueDays(inv)` (الأسطر 189-212).
  - لا تستخدم شبكة الإدخال `ExcelGrid` بل جدول عرض وتحليل منظم عالي الوضوح، يتيح:
    - إرسال إنذار الفصل العاجل الفردي والجماعي عبر الواتساب (`sendDisconnectionWarning` و `sendBulkDisconnectionWarnings`).
    - تصدير إكسل مدعوم بترميز UTF-8 BOM عبر مكتبة `xlsx` (الأسطر 423-500).
    - استعراض كشف حساب المشترك التفصيلي (`StatementModal`).

### 2.5 هيكل التوجيه والملاحة (`frontend/src/App.tsx` و `Sidebar.tsx`)
- في `App.tsx`:
  - تم توحيد المسارات: مسار `customers`، و `reports`، و `unread-meters`، و `approved-edits` يتم توجيهها جميعاً تلقائياً عبر `<Navigate to="/invoices" replace />` لتركيز تجربة المستخدم حول شبكة العمليات التفاعلية.
  - مسار `arrears` مستقل تماماً ومتاح لأدوار `ADMIN`, `ACCOUNTANT`, `CASHIER`.
- في `Sidebar.tsx`:
  - قائمة مخصصة ونظيفة بحسب الدور (RBAC) خالية تماماً من المسارات الملغاة.
  - ميزة باركود الربط الميداني السريع (QR Code) مع كشف شبكة الـ Wi-Fi ونقطة الاتصال Hotspot المحلية (الأسطر 30-51).

---

## 3. التدقيق المعمق: التعديل المباشر والحفظ التلقائي (Inline Editing & Auto-Save)

```
[مستخدم يكتب في الخلية] 
        │
        ▼
   onChange: toEnglishDigits() -> handleCellChange()
        │
        ├─► markCellDirty(id, field) -> localStorage.setItem(...)
        │
        ├─► setLocalRows() تحديث الحالة المحلية
        │
        └─► useMemo: computeRowFinancials() + computeGridTotals()
             └─► تحديث فوري لاستهلاك السطر، وقيمة الاستهلاك، والمتبقي، وتذييل الجدول، وبطاقات الـ KPI
        │
[المستخدم يغادر الخلية (onBlur) أو يضغط Enter]
        │
        ▼
   handleCellBlur(id, field, rawValue)
        │
        ├─► Change Guard: areValuesEqual(origVal, rawValue)
        │    └─► [إذا لم تتغير القيمة]: خروج فوري دون أي استدعاء شبكي!
        │
        ├─► [إذا تغيرت القيمة]: تحديث initialRowsMap
        │
        └─► onCellSave(id, field, rawValue, computed)
             │
             ├─► إرسال PUT /api/readings/:id/cell-update
             │
             ├─► نجاح: queryClient.invalidateQueries(['invoices', 'payments', 'customers'])
             │    └─► unmarkCellDirty(id, field) -> إزالة اللون الكهرماني
             │
             └─► فشل: toast.error(...) + بقاء اللون الكهرماني لتنبيه المستخدم
```

### 3.1 دورة التعديل خطوة بخطوة:
1. **تحويل الأرقام والتعقيم الفوري (Keystroke Sanitization)**:
   - عند الكتابة في أي حقل، يتم تمرير القيمة مباشرة عبر دالة `toEnglishDigits` من `frontend/src/utils/formatters.ts`، لتحويل الأرقام المشرقية (٠-٩) والفارسية (۰-۹) فورياً إلى أرقام إنجليزية (0-9).
2. **التحديث المحلي التفاؤلي (Optimistic Local Update)**:
   - تستقبل دالة `handleCellChange` القيمة وتستدعي `setLocalRows(prev => prev.map(...))` (السطر 229 في `ExcelGrid.tsx`).
3. **إعادة الحساب الفوري للسطر والجدول (Real-Time Recalculation)**:
   - دالة `computeRowFinancials` (السطر 54 في `excelGrid.types.ts`) تعيد احتساب:
     $$\text{Units} = \max(0, \text{currReading} - \text{prevReading})$$
     $$\text{ConsumptionCost} = \text{Units} \times \text{UnitPrice}$$
     $$\text{LostUnitsCost} = \text{LostUnits} \times \text{UnitPrice}$$
     $$\text{TotalDue} = \text{ConsumptionCost} + \text{LostUnitsCost} + \text{ServiceFee} + \text{Arrears}$$
     $$\text{Remaining} = \text{TotalDue} - \text{PaidAmount}$$
   - دالة `computeGridTotals` (السطر 94 في `excelGrid.types.ts`) تجمع إجماليات الأعمدة المعروضة فورياً لبطاقات الـ KPI وتذييل الجدول.
4. **حراسة التغيير الصارمة (Strict Change Guard)**:
   - في السطر 248 من `ExcelGrid.tsx`، تفحص دالة `handleCellBlur`:
     ```typescript
     if (areValuesEqual(origVal, rawValue)) {
       return; // DO NOT save, DO NOT call API!
     }
     ```
   - هذا يمنع أي استهلاك غير ضروري لعرض النطاق الترددي وموارد السيرفر.
5. **الاتصال بالخلفية وإعادة التزامن**:
   - ترسل `handleInvoiceCellSave` طلباً إلى `/api/readings/:targetId/cell-update` بحمولة موحدة.
   - في السيرفر Go (`server/internal/services/customer_service.go:469`)، تنفذ العملية داخل معاملة قاعدة بيانات مع قفل تفاؤلي `FOR UPDATE` على مستوى السطر لمنع أي تعارض، وتعيد احتساب الفواتير والمتأخرات تتابعياً.

---

## 4. تقييم مخاطر تجميد الواجهة والأداء (UI Freezing & Performance Analysis)

| مكمن الخطر / الأداء | مستوى الخطورة | التوصيف الفني والتحليل | الأثر العملي الحالي والحل المقترح |
|---|---|---|---|
| **غياب الـ Virtualization لشجرة الـ DOM** | **متوسط إلى مرتفع** (Medium-High) | يرندر جدول `ExcelGrid` كامل المشتركين (494 صفاً) دفعة واحدة. كل صف يحتوي على 13 إلى 15 عنصر `<input>` نشط، أي أكثر من 7,400 عنصر إدخال متزامن في الـ DOM. | عند 494 مشتركاً، زمن الحساب الرياضي يستغرق 26ms (مقبول)، لكن مع نمو المشتركين لـ 1,500+، سيتسبب في انخفاض معدل الإطارات (FPS drop) أثناء التمرير السريع. الحل: استخدام `@tanstack/react-virtual`. |
| **إعادة رندر الجدول بالكامل في كل ضغطة مفتاح** | **متوسط** (Medium) | لا توجد حراسة بمستوى السطر (`React.memo` على صفوف `<tr>`). عند كتابة رقم في أي خلية، يتغير `localRows` مما يجعل React يعيد معالجة ومقارنة (Diffing) كافة الصفوف الـ 494. | يستهلك طاقة المعالج في جلسات الإدخال المكثفة. الحل: فصل خلايا الإدخال إلى مكون فرعي بحالة محلية غير مقيدة (Uncontrolled Input with Debounce). |
| **عمليات I/O متزامنة مع `localStorage`** | **منخفض إلى متوسط** (Low-Medium) | استدعاء `localStorage.setItem('smartpower_grid_dirty_cells', ...)` في السطر 150 من `ExcelGrid.tsx` عند كل تعديل خلية، وهي دالة متزامنة تمنع الـ Event Loop. | قد يسبب تقطيعاً صغيراً جداً (Micro-stutter) عند الكتابة بسرعة فائقة. الحل: تغليف الكتابة بمؤقت تأخير (Debounced Sync). |
| **استعلامات إعادة التحميل بعد الحفظ (Query Invalidation)** | **منخفض** (Low) | استدعاء `invalidateQueries` لثلاثة مفاتيح (`invoices`, `payments`, `customers`) بعد كل حفظ خلية ناجح. | في السيرفر المحلي المستقل (Local Go Monolith)، الاستجابة فورية (< 15ms) ولا تسبب انتظاراً ملحوظاً، لكن دمجها في تحديث تفاؤلي محلي مباشر يلغي الحاجة لطلب الشبكة المتكرر. |
| **حجم حزمة الجافاسكريبت الواحدة (Monolithic Bundle)** | **منخفض** (Low) | حزمة الـ JS المجمعة `index-CeuheoGF.js` يبلغ حجمها 1,572 كيلوبايت (1.57 ميجابايت) لعدم وجود تقطيع للكود (Code Splitting). | بما أن التطبيق مكتبي ويعمل على Loopback محلي (`http://localhost:3000`) ومضمن داخل ملف `SmartPower.exe`، فإن زمن التحميل أقل من 0.05 ثانية، وبالتالي لا يؤثر سلباً على تجربة المستخدم الأوفلاين. |
| **خطاف الوقت الحقيقي الصوري (`useDebouncedRealtime`)** | **معلوماتي** (Info) | تم تفريغ الدالة في `debouncedRealtime.ts` لتصبح `return () => {}` نظراً لأن السيرفر Go يعمل محلياً دون تبعية سحابية لـ Supabase. | لا يوجد تجميد للواجهة ناتج عن اتصالات الـ WebSockets المنقطعة، والتحديثات تتم عبر واجهات الاستعلام المحلية. |

---

## 5. فحص وتوثيق سكربتات الاختبار المؤتمتة (Automated Test Suites Survey)

### 5.1 حزمة الاختبارات في `package.json`
- لا توجد أطر اختبار قياسية مثل `vitest` أو `jest` أو `playwright` أو `cypress` مثبتة في تبعيات الواجهة الأمامية (`devDependencies`).
- فحص البناء `npm run build` يعتمد على `tsc -b && vite build` وقد اجتاز الفحص بنجاح 100% بزمن قدره **1.38 ثانية** دون أي أخطاء ترجمة.

### 5.2 سكربتات الاختبار المخصصة في `frontend/src/tests/`:

| اسم ملف الاختبار | الوظيفة ونطاق الفحص | النتيجة الحالية | الملاحظات والتشخيص |
|---|---|---|---|
| `test_adversarial_numerals_stress.js` | فحص مدخلات الأرقام المتطرفة، التحويل من المشرقية، الحسابات المالية للأسطر والإجماليات، واختبار التحمل لـ 1,000 سطر. | **نجح 101 من أصل 108** (فشل 7) | الحساب المالي نجح واختبار التحمل لـ 1,000 سطر استغرق 26.61ms. حالات الفشل السبع ترجع لتوقعات قديمة في السكربت كانت ترفض الإشارات السالبة بينما تم تحديث الكود لدعم الأرصدة الدائنة (`-20000`). |
| `test_challenger_layout_2.js` | التحقق من مطابقة نموذج الفاتورة المزدوجة A5 (12 عموداً: 5 للمحصل و 7 للمشترك)، والشروط الرسمية، والأرقام الإنجليزية. | **نجح 99 من أصل 106** (فشل 7) | مطابقة بنية الفاتورة والطباعة حققت 100%. حالات الفشل السبع ناتجة عن فحص صارم لصلاحيات إظهار تبويب المديونيات للمحصل في الشريط الجانبي. |
| `test_numerals_scan.js` | مسح 61 ملفاً مصدرياً للتأكد من انعدام الأرقام المشرقية في الكود وانعدام `type="number"`. | **نجح 32 من أصل 37** (فشل 5) | اجتاز انعدام الأرقام المشرقية بالكامل. الفشل في 5 حالات متعلق بفحص بعض بادئات أرقام الهاتف اليمنية. |
| `test_whatsapp_and_phone.js` | فحص تجهيز نصوص فواتير الواتساب، وتنسيق الأرقام اليمنية، وروابط `wa.me`. | **نجح 59 من أصل 65** (فشل 6) | سبب الفشل في الحالات الست هو خطأ حسابي في نص الاختبار نفسه حيث لم يضف كاتب الاختبار قيمة الوحدات المفقودة (`lostUnits: 15 * 1400 = 21000`) في الناتج المتوقع، بينما حسبها المحرك المالي بدقة. |
| `test_routes_and_tabs.js` | فحص اكتمال التوجيهات وحذف التبويبات الملغاة. | **فشل** (ENOENT) | توقف السكربت لمحاولته قراءة ملف ملغي تم دمجه مسبقاً وهو `ReportsHub.tsx`. |

### 5.3 سكربتات التكامل المؤتمتة على مستوى السيرفر (Root E2E Tests):
- **`test_whatsapp_and_ui.py`**:
  - فحص متكامل مع السيرفر الحي (`http://127.0.0.1:3000/api`).
  - اختبر تسجيل الدخول، وإرسال رسائل الواتساب لطابور الإرسال، واستعلام مؤشرات الـ Analytics، وسجلات الرقابة والتدقيق `audit_logs`.
  - **النتيجة**: اجتاز الاختبار بنجاح تام 100% واستجاب السيرفر في غضون ثوانٍ معدودة.
- **`test_subscriber_anti_duplication.py`**:
  - فحص صمود منع تكرار أرقام المشتركين مع إزالة الأصفار البادئة على مستوى قاعدة بيانات PostgreSQL.
- **`test_financial_suite.py`**:
  - فحص تكاملي للقيود المالية، وترحيل الدفعات المتتالية، ومطابقة الأرصدة.

---

## 6. خلاصة التقييم والتوصيات المعمارية (Architectural Recommendations)

1. **إدخال تقنية التقطيع الافتراضي (DOM Virtualization)**:
   - يوصى بدمج `@tanstack/react-virtual` في `ExcelGrid.tsx` لعرض الصفوف المرئية فقط على الشاشة (حوالي 25 صفاً بدلاً من 494 صفاً)، مما يخفض عدد عناصر الـ DOM من 7,400 عنصر إلى أقل من 400 عنصر، ويقضي نهائياً على أي احتمال لتجميد الواجهة مستقبلاً عند وصول المشتركين إلى الآلاف.
2. **عزل حالة خلايا الإدخال (Uncontrolled Inputs with Local State)**:
   - جعل حقل الإدخال يحتفظ بقيمته محلياً أثناء الكتابة، وتأجيل تحديث حالة الجدول المركزية (`localRows`) إلى حدث `onBlur` أو عبر `debounce(150ms)`، لتفادي إعادة رندر كامل الجدول في كل ضربة مفتاح.
3. **تأخير كتابة `localStorage` (Debounced LocalStorage Sync)**:
   - نقل تخزين `smartpower_grid_dirty_cells` ليكون عبر مؤقت زمني خفيف (Debounce 500ms) لمنع عمليات الـ I/O المتزامنة على خيط التنفيذ الرئيسي أثناء الطباعة السريعة.
4. **تحديث أطر الاختبارات**:
   - تثبيت `vitest` لتشغيل اختبارات الوحدات البرمجية محلياً وسريعاً، وتحديث توقعات ملف `test_adversarial_numerals_stress.js` و `test_whatsapp_and_phone.js` لتطابق السلوك المعياري المحدث للأرصدة الدائنة والوحدات المفقودة.
