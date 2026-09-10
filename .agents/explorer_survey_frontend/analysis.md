# تقرير الاستكشاف والمسح الشامل للواجهة الأمامية (Frontend & UI Survey)

## 1. ملخص تنفيذي (Executive Summary)
تم إجراء مسح فني شامل لهيكل الواجهة الأمامية (React + Vite + Tailwind CSS + TypeScript) لنظام **Smart Power ERP** مع التركيز على ثلاثة محاور رئيسية:
1. **R1: توحيد إدخالات الأرقام، إزالة أسهم التمرير (Spinners)، وفرض الأرقام الإنجليزية (0-9)**.
2. **R2: إنشاء تبويب المديونيات المستقل ونموذج `code_artifact (8).html` وحذف تبويب "التعرفة والرسوم العامة" بالكامل**.
3. **R5: سجل العمليات المباشر (Live Operations Log) وتنسيق شبكة Excel التفاعلية والاعتماد الفوري لمدير النظام**.

---

## 2. المحور الأول: إدخالات الأرقام وإزالة أسهم المتصفح (R1)

### 2.1 مسح حقول الإدخال الرقمية (`type="number"`)
تم رصد 29 حقلاً رقمياً رئيسياً عبر الملفات التالية:
| الملف | السطور | الاستخدام |
|---|---|---|
| `components/common/ExcelGrid.tsx` | 277, 287, 577, 593, 615, 632, 653, 669, 690 | خلايا التعديل المباشر للقراءات، الوحدات، المتأخرات، الرسوم، والمدفوع |
| `pages/TodayReadingsReview.tsx` | 371, 381, 723, 739, 760, 776, 797, 813, 834 | خلايا شبكة العمليات المباشرة وإدخال التعرفة |
| `components/PaymentModal.tsx` | 112 | إدخال المبلغ المسدد |
| `components/ReadingModal.tsx` | 206 | إدخال قراءة العداد الجديدة |
| `components/ArrearsThresholdModal.tsx` | 49 | إدخال حد التنبيه للمديونيات |
| `pages/Customers.tsx` | 631, 815 | القراءة الابتدائية عند إضافة/تعديل المشترك |
| `pages/Dashboard.tsx` | 776 | تعديل القراءة المباشرة من لوحة المتابعة |
| `pages/Settings.tsx` | 103, 120, 137, 154 | إدخال سعر الكيلوواط، الرسوم الثابتة، والحدود |
| `pages/UnreadMeters.tsx` | 380 | نافذة تسجيل قراءة للعدادات غير المقروءة |

### 2.2 مراجعة قواعد CSS لإلغاء أسهم التمرير (Browser Spinners Reset)
في ملف `d:/elctercity/frontend/src/index.css` (السطور 57-67):
```css
/* Hide spin-buttons / arrows on input[type="number"] for direct typing */
input[type="number"]::-webkit-outer-spin-button,
input[type="number"]::-webkit-inner-spin-button {
  -webkit-appearance: none;
  margin: 0;
}

input[type="number"] {
  -moz-appearance: textfield;
  appearance: textfield;
}
```
**الملاحظة والتقييم:**
- القواعد تغطي محركات Webkit (Chrome, Edge, Safari) و Gecko (Firefox).
- يتم تطبيق محاذاة أرقام إنجليزية موحدة عبر `font-feature-settings: "lnum" 1;` في `body` و `font-feature-settings: "lnum" 1, "tnum" 1;` في فئة `.font-mono`.

### 2.3 فحص تطبيق الأرقام الإنجليزية (0-9)
- مكتبة التنسيق المركزية `frontend/src/utils/formatters.ts` توفر الدوال:
  - `formatDate`: تفرض `toLocaleString('en-US', ...)`
  - `formatDateOnly`: تفرض `toLocaleDateString('en-US', ...)`
  - `formatMonth`: شهر بالعربي + سنة بالأرقام الإنجليزية
  - `formatNumber` و `formatCurrency`: أرقام إنجليزية وفواصل آلاف `en-US`.
- **المخالفات المرصودة:**
  - في `pages/UnreadMeters.tsx` السطر 85 و 318: استخدام `toLocaleDateString('ar-EG')` (يولد أرقاماً مشرقية ٠-٩).
  - في `pages/UnreadMeters.tsx` السطر 315 و 374: استخدام `toLocaleString()` بدون تمرير `'en-US'`.
- **التوصية المقترحة:**
  - إضافة دالة `normalizeNumerals(str)` في `formatters.ts` لتحويل أي مدخلات أو أرقام يتم لصقها بالأرقام المشرقية (٠-٩) إلى الإنجليزية (0-9) تلقائياً.
  - استبدال دوال `UnreadMeters.tsx` بدوال `formatters.ts`.

---

## 3. المحور الثاني: تبويب المديونيات وحذف تبويب التعرفة والرسوم (R2)

### 3.1 تحليل النموذج المعتمد `code_artifact (8).html` لتبويب المديونيات
عند فحص `code_artifact (8).html`:
1. **العمود البارز للمتأخرات**:
   - يحمل التنسيق `bg-rose-50 text-rose-800 border-x-2 border-rose-300 font-extrabold`.
   - قابل للتعديل الفوري مع إعادة احتساب `إجمالي المستحق = قيمة الاستهلاك + رسوم الخدمة + المتأخرات` و `المتبقي = إجمالي المستحق - المدفوع`.
2. **أيام التأخير (Overdue Days)**:
   - تمييز الديون الحرجة بألوان مميزة (أكثر من 60 يوماً بلون أحمر وردي، وأكثر من 30 يوماً بلون كهرماني).
3. **أزرار التحصيل والإنذار**:
   - زر "سداد" فوري يفتح نافذة الدفع المباشر (`PaymentModal`).
   - زر "إنذار" يفتح رسالة الإنذار الرسمية عبر الواتساب (`sendDisconnectionWarning`).
4. **تذييل الجدول والإحصائيات العلوية (KPI Cards)**:
   - بطاقات إحصائية: إجمالي المديونية، ديون حرجة (>60 يوم)، متوسط التأخير، وسدادات اليوم.

### 3.2 حالة صفحة المديونيات الحالية (`pages/ArrearsReport.tsx`)
- الصفحة مبنية بالفعل ومطابقة بالكامل لمواصفات `code_artifact (8).html` (924 سطراً)، وتحتوي على:
  - عمود أيام التأخير (`أيام التأخير`) مع تصنيف الحالة (فصل نهائي / إنذار كارت / متأخر عادي).
  - زر إشعار الإنذار بالسداد وفصل الخدمة (`buildWarningNoticeText` + إرسال واتساب).
  - زر سداد مالي فوري يفتح `PaymentModal`.
  - فلاتر المناطق (Area Grouping Pills) والدورات ومستويات التأخير.
- **الخلل في التوجيه والقائمة الجانبية**:
  - في `App.tsx` (السطور 91-97): المسار `/arrears` يقوم بإعادة توجيه داخلية إلى `/reports?tab=arrears` بدلاً من عرض الصفحة المستقلة `<ArrearsReport />`.
  - في `components/Sidebar.tsx`: لا يوجد رابط للمديونيات في القائمة الجانبية للأدمن أو المحاسب.
- **خطة التعديل المقترحة**:
  - تحديث `App.tsx` لربط المسار `/arrears` بمكون `<ArrearsReport />` مباشرة.
  - إضافة رابط `المديونيات والمتأخرات` (أيقونة `AlertTriangle`) إلى `Sidebar.tsx` لكل من `ADMIN` و `ACCOUNTANT`.

### 3.3 حصر مراجع تبويب "التعرفة والرسوم العامة" لحذفه بالكامل
تم حصر المراجع التالية لحذفها:
1. **في `pages/Settings.tsx`**:
   - حذف مكون `GeneralTariffSettings` (السطور 12-233).
   - حذف زر التبويب الفرعي `tariffs` ("التعرفة والرسوم العامة") (السطور 279-289).
   - حذف عرض التبويب `{activeTab === 'tariffs' && <GeneralTariffSettings />}` (السطور 322-326).
2. **في `App.tsx`**:
   - إزالة أو تعديل `<Route path="import" element={<Navigate to="/settings?tab=tariffs" replace />} />` ليوجه إلى `/settings`.
3. **في `components/PlansManagement.tsx`**:
   - المكون ملغى ومفرغ بالفعل ويعيد `null`.

---

## 4. المحور الثالث: سجل العمليات المباشر (R5) وشبكة Excel والاعتماد التلقائي

### 4.1 تحليل مكونات سجل العمليات المباشر
1. **`pages/TodayReadingsReview.tsx`**:
   - يمثل كشف Excel التفاعلي المتكامل بـ 18 عموداً وفق `code_artifact (8).html`.
   - تعديل مباشر للخلايا مع الحفظ التلقائي عند مغادرة الخلية (`PUT /api/readings/:id/cell-update`).
   - اعتماد فوري مع إرسال فاتورة الواتساب بضغطة زر واحدة (`POST /api/readings/:id/approve-and-whatsapp`).
   - اعتماد جماعي لكافة القراءات والسدادات المعلقة (`POST /api/readings/approve-all`).
2. **`components/common/ExcelGrid.tsx`**:
   - مكون شبكة Excel قابل لإعادة الاستخدام في مختلف الشاشات، ويدعم الحسابات المالية التلقائية والمطابقة لأرقام `en-US`.
3. **`pages/Dashboard.tsx`**:
   - يحتوي على قسم "سجل العمليات المباشر ومراجعة المدير" مع دعم التحديث الفوري عبر اشتراكات Supabase Realtime للجدولين `meter_readings` و `payments`.

### 4.2 فحص مسار الاعتماد التلقائي لمدير النظام (Admin Auto-Approval Flow)
تم التحقق من منطق الاعتماد التلقائي في السيرفر:
- في `backend/src/controllers/reading.controller.ts` (السطور 32-55):
  - عندما يكون `userRole === 'ADMIN'` يتم تفعيل `autoApprove: true` تلقائياً، ويتم اعتماد القراءة وإصدار فاتورتها فوراً بحالة `APPROVED` دون انتظار.
- في `backend/src/controllers/payment.controller.ts` (السطور 53-65):
  - عندما يقوم الأدمن بإدخال سداد، يتم اعتماده فوراً وتحديث رصيد المشترك مباشرة بحالة `Paid`.

---

## 5. حالة البناء والاختبارات (Build & Verification Status)
- تم تشغيل `npm run build` في مجلد `frontend` واكتمل بنجاح تام:
  - 2560 وحدة برمجية تم تحويلها وبناؤها بنجاح (`dist/index.html`, `dist/assets/...`).
  - صفر أخطاء TypeScript أو Vite.
- تم فحص اختبارات التوجيه `test_routes_and_tabs.js` واجتازت 30/30 اختباراً بنجاح.
