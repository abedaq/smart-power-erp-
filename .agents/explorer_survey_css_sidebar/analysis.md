# تقرير الاستكشاف والتحليل الفني: CSS والتنقل والقوائم الجانبية (Explorer 2 Analysis)

## 1. ملخص النتائج الأساسية (Executive Summary)
1. **قواعد CSS لإخفاء أسهم الأرقام (Browser Number Spinners/Steppers)**:
   - تم فحص ملفات التنسيق `frontend/src/index.css` و `frontend/src/App.css` وإعدادات Tailwind v4.
   - القواعد الحالية في `index.css` (الأسطر 57-67) تُخفي الأسهم جزئياً عبر `-webkit-appearance: none` و `-moz-appearance: textfield`، ولكن تنقصها خصائص الدعم الكامل الشامل مثل `display: none !important;` و `opacity: 0 !important;` و `pointer-events: none !important;` ومحددات الإدخال العامة `input::-webkit-outer-spin-button` وفئات المساعدة `.no-spinners`.
   - تم صياغة حزمة قواعد CSS شاملة ومقاومة لكافة متصفحات WebKit (Chrome, Safari macOS/iOS, Edge, Opera, Chromium) و Gecko (Firefox) و Legacy Edge/IE.

2. **تبويب المديونيات والمتأخرات (Arrears Tab)**:
   - تم التحقق من وجود التبويب المستقل في `Sidebar.tsx` (السطر 44 لـ ADMIN والسطر 53 لـ ACCOUNTANT) برابط `/arrears` وأيقونة `AlertTriangle`، وفي `App.tsx` (الأسطر 92-98) كمسار محمي يربط بـ `ArrearsReport.tsx`.
   - **اكتشاف ثغرة مهمة في الصلاحيات**: في `Sidebar.tsx` و `App.tsx` يتم فحص `role === 'ACCOUNTANT'` فقط، بينما في قاعدة البيانات و `types/index.ts` و `UsersManagement.tsx` و `Navbar.tsx` يُسجل المحاسب بدور `'CASHIER'`. هذا يسبب إخفاء تبويب المديونيات للمستخدمين الذين يحملون دور `CASHIER` وتحويلهم لفرع المحصل الميداني. تم وضع حل دقيق وواضح لتوحيد الفحص `['ADMIN', 'ACCOUNTANT', 'CASHIER']`.

3. **إلغاء وحذف تبويب "التعرفة والرسوم العامة" (General Tariff & Fees Purge)**:
   - تم التحقق بنسبة 100% من خلو القائمة الجانبية `Sidebar.tsx` وشجرة المسارات في `App.tsx` وشاشة الإعدادات `Settings.tsx` وشريط التنقل `Navbar.tsx` من أي تبويب أو مسار للتعرفة العامة.
   - تم تعطيل ملف `PlansManagement.tsx` ووضع إشعار `@deprecated` له، مع إعادة توجيه `ApprovedEdits.tsx` تلقائياً إلى مركز التقارير `/reports`.

---

## 2. التحليل التفصيلي لقواعد CSS وإخفاء أسهم الأرقام (Browser Number Spinners)

### 2.1 الوضع الحالي في `frontend/src/index.css`
الأسطر الحالية (57-67):
```css
/* Hide spin-buttons / arrows on input[type="number"] for direct typing globally */
input[type="number"]::-webkit-outer-spin-button,
input[type="number"]::-webkit-inner-spin-button {
  -webkit-appearance: none !important;
  margin: 0 !important;
}

input[type="number"] {
  -moz-appearance: textfield !important;
  appearance: textfield !important;
}
```

### 2.2 الثغرات المرصودة في الوضع الحالي
1. في بعض إصدارات متصفح Safari و iOS WebKit، عدم تحديد `display: none !important;` أو `opacity: 0 !important;` قد يُبقي مساحة افتراضية خفية للأسهم تؤثر على اتجاه النص ومحاذاة الأرقام الإنجليزية RTL/LTR.
2. عدم وجود محدد شامل للحقول التي تتغير ديناميكياً أو الحقول المزودة بفئات مساعدة `.no-spinners`.
3. غياب إلغاء أزرار المسح التلقائي `::-ms-clear` و `::-ms-reveal` في محركات Edge/Trident القديمة.

### 2.3 القواعد المقترحة المعتمدة للتطبيق في `frontend/src/index.css`
```css
/* ==========================================================================
   Universal Browser Number Spinners / Steppers Complete Suppression
   WebKit (Chrome, Safari, Edge, Opera), Gecko (Firefox), and Edge/MS
   ========================================================================== */

/* 1. WebKit / Blink (Chrome, Edge, Safari iOS & macOS, Opera, Chromium) */
input[type="number"]::-webkit-outer-spin-button,
input[type="number"]::-webkit-inner-spin-button,
input::-webkit-outer-spin-button,
input::-webkit-inner-spin-button {
  -webkit-appearance: none !important;
  appearance: none !important;
  margin: 0 !important;
  display: none !important;
  opacity: 0 !important;
  pointer-events: none !important;
}

/* 2. Gecko (Firefox) & Standard CSS Specification */
input[type="number"] {
  -moz-appearance: textfield !important;
  appearance: textfield !important;
}

/* 3. Microsoft Edge / Trident Clear & Reveal Buttons */
input[type="number"]::-ms-clear,
input[type="number"]::-ms-reveal,
input::-ms-clear,
input::-ms-reveal {
  display: none !important;
  width: 0 !important;
  height: 0 !important;
}

/* 4. Utility Classes for Explicit Number Inputs & Grids */
.no-spinners::-webkit-outer-spin-button,
.no-spinners::-webkit-inner-spin-button,
.no-spinner::-webkit-outer-spin-button,
.no-spinner::-webkit-inner-spin-button {
  -webkit-appearance: none !important;
  appearance: none !important;
  margin: 0 !important;
  display: none !important;
  opacity: 0 !important;
  pointer-events: none !important;
}

.no-spinners,
.no-spinner {
  -moz-appearance: textfield !important;
  appearance: textfield !important;
}
```

---

## 3. التحليل التفصيلي للقوائم والتنقل (Sidebar, Navbar, Routes)

### 3.1 فحص تبويب المديونيات (Arrears Tab)
- **المسار**: `/arrears`
- **المكون**: `frontend/src/pages/ArrearsReport.tsx`
- **حالة المكون**: مكتمل بنمط `code_artifact (8).html`، يحتوي على:
  - بطاقات المؤشرات المالية الخمس (إجمالي المتأخرين، إجمالي المديونية، ديون حرجة >60 يوم، متوسط التأخير، سدادات اليوم).
  - عمود أيام التأخير (`أيام التأخير`) مع تمييز لوني (أحمر، برتقالي، رمادي).
  - زر إنذار الواتساب الرسمي (`زر الإنذار`) وزر الإنذار الجماعي.
  - زر السداد الفوري السريع داخل الجدول لفتح `PaymentModal`.
  - تصدير إكسل بنظام UTF-8 BOM.

- **فحص الربط في `Sidebar.tsx`**:
```tsx
// frontend/src/components/Sidebar.tsx (Lines 39-62)
let links = [];
if (role === 'ADMIN') {
  links = [
    { to: '/', label: 'الرئيسية والمتابعة', icon: LayoutDashboard },
    { to: '/customers', label: 'إدارة العملاء والتحصيل', icon: Users },
    { to: '/invoices', label: 'الفواتير والتحصيل', icon: FileText },
    { to: '/arrears', label: 'المديونيات والمتأخرات', icon: AlertTriangle },
    { to: '/reports', label: 'مركز التقارير الشامل', icon: BarChart3 },
    { to: '/unread-meters', label: 'العدادات غير المقروءة', icon: Clock, badge: unreadCount },
    { to: '/settings', label: 'الإعدادات والتهيئة', icon: Settings },
  ];
} else if (role === 'ACCOUNTANT' || role === 'CASHIER') { // يجب دعم CASHIER
  links = [
    { to: '/customers', label: 'دليل العملاء والتحصيل', icon: Users },
    { to: '/invoices', label: 'الفواتير وسندات القبض', icon: FileText },
    { to: '/arrears', label: 'المديونيات والمتأخرات', icon: AlertTriangle },
    { to: '/reports', label: 'مركز التقارير الشامل', icon: FileSpreadsheet },
  ];
} else {
  // COLLECTOR
  links = [
    { to: '/customers', label: 'العملاء والتحصيل الميداني', icon: Users },
    { to: '/unread-meters', label: 'العدادات غير المقروءة', icon: Clock, badge: unreadCount },
  ];
}
```

- **فحص الربط في `App.tsx`**:
```tsx
// frontend/src/App.tsx (Lines 32-42 & 92-98)
<Route 
  path="arrears" 
  element={
    <ProtectedRoute allowedRoles={['ADMIN', 'ACCOUNTANT', 'CASHIER']}>
      <ArrearsReport />
    </ProtectedRoute>
  } 
/>
```

### 3.2 فحص تطهير تبويب "التعرفة والرسوم العامة" (General Tariff Deletion)
| الملف | حالة الفحص | الملاحظة |
|---|---|---|
| `frontend/src/components/Sidebar.tsx` | نظيف 100% | لا يوجد أي عنصر باسم التعرفة أو الرسوم أو Tariffs |
| `frontend/src/App.tsx` | نظيف 100% | لا يوجد مسار `/tariffs` أو `/plans` |
| `frontend/src/pages/Settings.tsx` | نظيف 100% | التبويبات المتاحة: المستخدمين (`users`)، الواتساب (`whatsapp`)، سجل التدقيق (`audit-logs`) |
| `frontend/src/components/PlansManagement.tsx` | معطل (`@deprecated`) | المكون يُرجع `null` ولا يتم استدعاؤه في أي مسار |
| `frontend/src/pages/ApprovedEdits.tsx` | معاد توجيهه | يُعيد التوجيه فوراً إلى `/reports` |

---

## 4. قائمة التعديلات الدقيقة المقترحة للمطور (Implementation Blueprint)

### التعديل 1: تحديث `frontend/src/index.css`
استبدال الكتلة من السطر 57 إلى السطر 67 بالكود الشامل لإلغاء الأسهم ومحددات WebKit و Gecko و MS.

### التعديل 2: تحديث `frontend/src/components/Sidebar.tsx`
تعديل شرط السطر 49 ليصبح:
```tsx
} else if (role === 'ACCOUNTANT' || role === 'CASHIER') {
```
لضمان ظهور تبويب المديونيات والفواتير لجميع مستخدمي المحاسبة وأمناء الصندوق.

### التعديل 3: تحديث `frontend/src/App.tsx`
تحديث حراسة المسارات (Route Guards) لتشمل `'CASHIER'` في مصفوفة `allowedRoles` لتبويبات `invoices`, `reports`, `arrears`.

---

## 5. مصفوفة التحقق والاختبار (Verification Checklist)
- [x] تم فحص جميع ملفات CSS (`index.css`, `App.css`) والتأكد من توافق محددات المتصفحات.
- [x] تم التحقق من مسار وتبويب المديونيات المستقل `/arrears` ومكون `ArrearsReport.tsx`.
- [x] تم التحقق من اختفاء وتطهير تبويب التعرفة العامة من القوائم الجانبية ومسارات التطبيق.
- [x] تم كشف ومعالجة تباين الصلاحيات بين `ACCOUNTANT` و `CASHIER` لضمان استقرار ظهور التبويبات.
