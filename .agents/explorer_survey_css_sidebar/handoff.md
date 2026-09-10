# Handoff Report — Explorer 2 (CSS & Navigation Specialist)

## 1. Observation
1. **ملفات CSS ومحددات الأرقام الحالية**:
   - في `frontend/src/index.css` (الأسطر 57-67):
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
   - لوحظ غياب محددات إضافية مثل `display: none !important;` و `opacity: 0 !important;` و `pointer-events: none !important;` التي تلزم لإلغاء تفاعل اللمس على أجهزة iOS/WebKit، بالإضافة لغياب فئات مساعدة مثل `.no-spinners`.

2. **قائمة الشريط الجانبي ومسارات التبويبات**:
   - في `frontend/src/components/Sidebar.tsx` (الأسطر 39-62):
     ```tsx
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
     } else if (role === 'ACCOUNTANT') {
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
   - في `frontend/src/types/index.ts` (السطر 7): `role: 'ADMIN' | 'CASHIER' | 'COLLECTOR';`.
   - في `frontend/src/pages/UsersManagement.tsx` (السطور 11 و 371): أدوار المستخدمين المعرفة هي `'ADMIN' | 'CASHIER' | 'COLLECTOR'`.
   - في `frontend/src/App.tsx` (الأسطر 92-98):
     ```tsx
     <Route 
       path="arrears" 
       element={
         <ProtectedRoute allowedRoles={['ADMIN', 'ACCOUNTANT']}>
           <ArrearsReport />
         </ProtectedRoute>
       } 
     />
     ```

3. **حالة تبويب التعرفة والرسوم العامة**:
   - لا يوجد أي وجود لتبويب "التعرفة والرسوم العامة" في `Sidebar.tsx` أو `App.tsx` أو `Settings.tsx` أو `Navbar.tsx`.
   - المكون القديم `frontend/src/components/PlansManagement.tsx` معطل تماماً ويرجع `null`.
   - المكون `frontend/src/pages/ApprovedEdits.tsx` يعيد التوجيه إلى `/reports`.

---

## 2. Logic Chain
1. **الربط بين محددات CSS وتجربة المستخدم**:
   - من الملاحظة (1)، على الرغم من تطبيق `-webkit-appearance: none` و `-moz-appearance: textfield`، إلا أن المتصفحات الحديثة والمتنقلة تتطلب تعزيز القواعد بـ `display: none` و `opacity: 0` و `pointer-events: none` ومحددات عامة لمنع ظهور الأسهم تماماً تحت أي ظرف.
2. **الربط بين استقرار تبويب المديونيات وأدوار المستخدمين**:
   - من الملاحظة (2)، التبويب `/arrears` مضاف ومثبت في `Sidebar.tsx` ومربوط بـ `ArrearsReport.tsx` في `App.tsx`.
   - ولكن بما أن النظام يستخدم دور `'CASHIER'` لتعريف المحاسب وأمين الصندوق (كما وُجد في `types/index.ts` و `UsersManagement.tsx` و `Navbar.tsx`)، فإن شرط `role === 'ACCOUNTANT'` في `Sidebar.tsx` و `App.tsx` يتجاهل مستخدمي `'CASHIER'` ويصنفهم كمحصلين ميدانيين، مما يحرمهم من رؤية تبويب المديونيات.
   - تعديل الشرط في `Sidebar.tsx` و `App.tsx` ليدعم `ACCOUNTANT` و `CASHIER` يضمن استقرار الرؤية لجميع الطواقم الإدارية والمالية.
3. **تأكيد خلو النظام من تبويب التعرفة العامة**:
   - من الملاحظة (3)، كافة المسارات والمكونات خالية من أي بقايا لتبويب التعرفة العامة.

---

## 3. Caveats
- تم فحص الواجهة الأمامية React Web UI فقط؛ لا توجد تبعات تؤثر على تطبيق الموبايل Flutter.
- لا توجد أي تحفظات أخرى (No further caveats).

---

## 4. Conclusion
1. **CSS**: يجب تحديث `frontend/src/index.css` بالقواعد المقترحة الشاملة لإخفاء أسهم الأرقام وتصفية مفاتيح المتصفحات.
2. **Navigation**: تبويب المديونيات `/arrears` موجود ومستقر، ويجب دعم دور `CASHIER` إلى جانب `ACCOUNTANT` في `Sidebar.tsx` و `App.tsx` لضمان ظهوره المستقر لكافة المحاسبين.
3. **Tariff Purge**: تبويب التعرفة والرسوم العامة محذوف ومطهر كلياً من القوائم والتوجيه.

---

## 5. Verification Method
1. **فحص الكود المصدري**:
   - فحص `frontend/src/index.css` للتأكد من وجود قواعد WebKit/Gecko/MS الشاملة.
   - فحص `frontend/src/components/Sidebar.tsx` للتأكد من وجود رابط `/arrears` ودعم `ACCOUNTANT` و `CASHIER`.
   - فحص `frontend/src/App.tsx` للتأكد من مسار `arrears` وصلاحياته.
2. **أمر اختبار البناء**:
   - تشغيل `npm run build` داخل مجلد `frontend` للتأكد من خلو المشروع من أية أخطاء تجميع أو مشاكل في التوجيه والأنواع.
