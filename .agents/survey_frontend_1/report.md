# التقرير المعماري الشامل لتطوير كشف العمليات وقراءات اليوم التفاعلي (Interactive Excel Grid & WhatsApp Auto-Approval Engine)

**تاريخ التقرير**: 2026-09-02  
**المعد**: المستشار المعماري والمتخصص في الواجهة الأمامية (Explorer 2 - Frontend Specialist)  
**المسار المستهدف**: `frontend/src/pages/TodayReadingsReview.tsx`، `frontend/src/pages/AuditLogs.tsx`، والمكونات والخدمات ذات الصلة.  
**المرجع البصري والبياني**: `photo_5769554780358381104_y.jpg` ومتطلبات التكليف الرسمي المؤرخ بـ `2026-09-02T16:31:02Z`.

---

## 1. الملخص التنفيذي والتشخيص المعماري (Executive Summary & Gap Analysis)

### 1.1 الحالة الراهنة (Current State)
- شاشة `TodayReadingsReview.tsx` الحالية تقدم جدولاً بسيطاً مكوناً من 9 أعمدة فقط يعتمد على نموذج التعديل التقليدي عبر النوافذ المنبثقة (Modal Pop-up).
- التعديل محصور في نافذة منبثقة تتطلب فتح المودال، إدخال القيم، ثم الضغط على حفظ وإغلاق المودال، مما يعيق سرعة المحاسب ومراجع القراءات في مراجعة مئات السجلات اليومية.
- غياب كامل لأعمدة أساسية مثل: **الوحدات المفقودة (Lost Units)**، **قيمة الفاقد (Lost Cost)**، **سعر الكيلو (Unit Price)**، **رسوم الاشتراك الثابتة (Fixed Fee)**، **المبلغ المسدد (Paid Amount)**، وتوزيع الأعمدة المالي المباشر.
- غياب التعديل التفاعلي المباشر داخل الخلايا (In-Cell Inline Editing) بنمط جداول Excel.
- غياب إعادة الاحتساب التفاعلي الفوري في الواجهة (Instant Reactive Recalculation) لجميع المعادلات المالية عند تغيير أي قيمة.
- زر الاعتماد والواتساب منفصل ومحدود، دون وجود اعتماد مدمج بنقرة واحدة per-row أو اعتماد جماعي (Bulk Approval).

### 1.2 الهدف المعماري المستهدف (Target Architectural Objective)
تحويل `TodayReadingsReview.tsx` إلى **كشف تفاعلي بنمط Excel (High-Performance RTL Interactive Operations Data Grid)** يتضمن:
1. **18 عموداً متكاملاً** مطابقاً للمواصفات الحسابية ونموذج الفاتورة المرجعية (`photo_5769554780358381104_y.jpg`).
2. **تعديل مباشر وفوري داخل الخلايا (Direct In-Cell Editing)** لـ 6 حقول تشغيلية: (القراءة الحالية، القراءة السابقة، الوحدات المفقودة، المتأخرات، الاشتراك الثابت، المبلغ المسدد).
3. **محرك احتساب تفاعلي فوري (Instant Client-Side Reactive Math Engine)** يعيد حساب الاستهلاك، قيمة الاستهلاك، قيمة الفاقد، الإجمالي المستحق، والمتبقي بصفر تأخير (0ms latency).
4. **زر مدمج لكل صف "اعتماد وإرسال واتساب" (One-Click Row Approval & WhatsApp Dispatch)** يغير حالة القراءة والفاتورة إلى `APPROVED`، ويحدث رصيد المشترك، ويولد صورة الفاتورة المعتمدة ويدرجها في طابور الواتساب تلقائياً مع مؤشرات تحميل وشارات حالة واضحة.
5. **شريط أدوات تشغيلي متقدم**: تحديد جماعي (Bulk Selection & Approval)، بحث شامل، فلاتر خطوط السير والمناطق وحالات الاعتماد والواتساب، وتصدير إكسل (.xlsx) وطباعة الكشف المجمع (PDF).
6. **التزام قطعي وصارم بالأرقام الإنجليزية (0, 1, 2, 3...)** في كافة الحقول والمدخلات والمخرجات والتصدير مع واجهة عربية RTL أصيلة.

---

## 2. جدول المواصفات الفنية التفصيلية للأعمدة الـ 18 (18-Column Data Grid Specification)

تم ترتيب الأعمدة من اليمين إلى اليسار (RTL Order) لتوفير تجربة مستخدم محاسبية مريحة:

| # | اسم العمود بالعربية | المعرف البرمجي (Field Key) | نوع الخلية | قابلية التعديل (Editable) | مصدر البيانات والمعادلة البرمجية | شروط التنسيق والأرقام |
|---|---|---|---|---|---|---|
| 1 | **م / الترتيب** | `index` / `row_selection` | رقم + Checkbox | ❌ | تسلسل الصف `index + 1` وصندوق الاختيار الجماعي | رقم إنجليزي، محاذاة وسط |
| 2 | **اسم المشترك** | `customer_name` | نص (Text) | ❌ | `record.customer.full_name` | خط عريض، محاذاة يمين، تثبيت عمودي (Sticky RTL) |
| 3 | **رقم المشترك** | `subscriber_number` | نص/كود | ❌ | `record.customer.subscriber_number` | خط أحادي `font-mono`، شارة زرقاء `#123` |
| 4 | **ق. السابقة** | `previous_reading` | مدخل رقمي (Input) | ✅ نعم | `record.invoice.previous_reading` | خط أحادي، أرقام إنجليزية، تنبيه عند `curr < prev` |
| 5 | **ق. الحالية** | `current_reading` | مدخل رقمي (Input) | ✅ نعم | `record.reading_value` | خط أحادي عريض، لون أزرق، أرقام إنجليزية |
| 6 | **الاستهلاك** | `consumption` | محسوب (Calculated) | ❌ (تلقائي) | `Math.max(0, current_reading - previous_reading)` | خط أحادي عريض، وحدة `kWh` |
| 7 | **الوحدات المفقودة** | `lost_units` | مدخل رقمي (Input) | ✅ نعم | `record.invoice.lost_units` أو `0` | خط أحادي، لون برتقالي/عنبري، أرقام إنجليزية |
| 8 | **سعر الكيلو** | `unit_price` | رقمي (Snapshot) | ❌ (ثابت للباقة) | `record.customer.subscription_plan?.kwh_price \|\| 1400` | خط أحادي، أرقام إنجليزية، وحدة `ر.ي` |
| 9 | **قيمة الاستهلاك** | `consumption_cost` | محسوب (Calculated) | ❌ (تلقائي) | `consumption * unit_price` | خط أحادي، أرقام إنجليزية بفواصل الآلاف |
| 10 | **قيمة الفاقد** | `lost_cost` | محسوب (Calculated) | ❌ (تلقائي) | `lost_units * unit_price` | خط أحادي، أرقام إنجليزية بفواصل الآلاف |
| 11 | **الاشتراك الثابت** | `fixed_fee` | مدخل رقمي (Input) | ✅ نعم | `record.invoice.fixed_fee_snapshot \|\| plan.fixed_fee` | خط أحادي، أرقام إنجليزية، افتراضي `1000` |
| 12 | **المتأخرات** | `arrears` | مدخل رقمي (Input) | ✅ نعم | `record.invoice.previous_arrears \|\| record.invoice.arrears` | خط أحادي، لون أحمر/وردي، أرقام إنجليزية |
| 13 | **الإجمالي المستحق** | `total_due` | محسوب (Calculated) | ❌ (تلقائي) | `consumption_cost + fixed_fee + lost_cost + arrears` | خط أحادي عريض، أرقام إنجليزية، لون داكن |
| 14 | **المسدد** | `paid_amount` | مدخل رقمي (Input) | ✅ نعم | `record.invoice.paid_amount \|\| 0` | خط أحادي، لون أخضر زمردي، أرقام إنجليزية |
| 15 | **المتبقي المطلوب** | `remaining_amount` | محسوب (Calculated) | ❌ (تلقائي) | `Math.max(0, total_due - paid_amount)` | خط أحادي عريض جداً، لون أحمر/زمردي |
| 16 | **حالة الاعتماد** | `approval_status` | شارة (Badge) | ❌ | `APPROVED` \| `PENDING_REVIEW` \| `REJECTED` | شارة ملونة: أخضر معتمد / أصفر قيد المراجعة |
| 17 | **حالة الواتساب** | `whatsapp_status` | شارة (Badge) | ❌ | `SENT` \| `QUEUED` \| `FAILED` \| `NOT_SENT` | أيقونة + شارة: تم الإرسال 📲 / في الطابور ⏳ |
| 18 | **الإجراءات** | `actions` | أزرار عمليات | تفاعلي | زر "اعتماد وإرسال واتساب" + قائمة إجراءات فرعية | زر رئيسي أخضر مميز مع حالة تحميل Spinner |

---

## 3. المعمارية الهندسية للتعديل المباشر داخل الخلايا والحساب التفاعلي (In-Cell Editing & Reactive Architecture)

### 3.1 هيكل البيانات الداخلي للصف (Row State Data Structure)
لضمان الأداء العالي ومنع إعادة تصيير الجدول بالكامل عند كل حرف يُكتب، يتم حفظ حالة السجلات محلياً في State تفاعلي مع تخزين القيم المعدلة (Dirty Tracking):

```typescript
export interface EditableGridRow {
  id: number; // Reading ID
  reading_date: string;
  collector_name: string;
  approval_status: 'APPROVED' | 'PENDING' | 'PENDING_REVIEW' | 'REJECTED';
  whatsapp_sent: boolean;
  whatsapp_status?: 'SENT' | 'QUEUED' | 'FAILED' | 'NOT_SENT';
  
  customer: {
    id: number;
    subscriber_number: string;
    full_name: string;
    phone_number: string;
    meter_number: string;
    address: string;
    route_number: string;
    plan_name: string;
    unit_price: number; // e.g. 1400
    default_fixed_fee: number; // e.g. 1000
  };

  invoice_id?: number;
  
  // Editable fields (controlled inputs as strings for smooth typing)
  previous_reading: string;
  current_reading: string;
  lost_units: string;
  fixed_fee: string;
  arrears: string;
  paid_amount: string;

  // Calculated reactive values
  consumption: number;
  consumption_cost: number;
  lost_cost: number;
  total_due: number;
  remaining_amount: number;

  // Meta & UI States
  isDirty: boolean;
  isSaving: boolean;
  isApproving: boolean;
}
```

### 3.2 محرك الاحتساب التفاعلي الفوري (Pure Calculation Utility Function)
دالة احتساب نقية وموحدة تضمن مطابقة الحسابات الرياضية عبر كافة واجهات النظام:

```typescript
export function recalculateRowMath(row: Partial<EditableGridRow>, unitPrice: number) {
  const prev = Math.max(0, parseFloat(row.previous_reading || '0') || 0);
  const curr = Math.max(0, parseFloat(row.current_reading || '0') || 0);
  const lost = Math.max(0, parseFloat(row.lost_units || '0') || 0);
  const fee = Math.max(0, parseFloat(row.fixed_fee || '0') || 0);
  const arr = Math.max(0, parseFloat(row.arrears || '0') || 0);
  const paid = Math.max(0, parseFloat(row.paid_amount || '0') || 0);

  const consumption = Math.max(0, curr - prev);
  const consumption_cost = consumption * unitPrice;
  const lost_cost = lost * unitPrice;
  const total_due = consumption_cost + fee + lost_cost + arr;
  const remaining_amount = Math.max(0, total_due - paid);

  return {
    consumption,
    consumption_cost,
    lost_cost,
    total_due,
    remaining_amount
  };
}
```

### 3.3 استراتيجية الحفظ التلقائي وإدارة التغييرات (Persistence & Debounce Strategy)
1. **التحديث المحلي الفوري (Immediate Local Update)**: عند تغيير أي خانة (`onChange`)، يتم تحديث الحالة المحلية فوراً وإعادة حساب القيم التابعة في أجزاء من الألف من الثانية دون إرسال طلبات للشبكة.
2. **تمييز الخلايا المعدلة (Dirty Cell Visual Indicator)**: الخلية التي تم تعديل قيمتها تظهر بحدود ملونة (Amber ring) لإعلام المستخدم بأن القيمة تم تعديلها ولم تُعتمد بعد.
3. **الحفظ عند الخروج من الخلية (`onBlur`) أو ضغط Enter**: إرسال تحديث صامت للباك إند عبر `PUT /api/today-readings/:id/full-update`.
4. **الحفظ والاعتماد المباشر عند النقر على "اعتماد وإرسال واتساب"**: يرسل الحزمة المحدثة بالكامل ويعتمد السجل في عملية ذرية واحدة (Atomic Operation).

---

## 4. محرك الاعتماد التلقائي والواتساب وشارات الحالة (Approval & WhatsApp Engine)

### 4.1 زر "اعتماد وإرسال واتساب" (Row Action Workflow)
- **الحالة 1: القراءة قيد المراجعة (`PENDING_REVIEW` / `PENDING`)**:
  - يظهر الزر بلون أخضر زمردي جذاب: `[⚡ اعتماد وإرسال واتساب]`.
  - عند النقر:
    1. تفعيل Spinner داخلي في الزر مع تعطيله لمنع النقر المزدوج (`disabled={row.isApproving}`).
    2. استدعاء الـ Endpoint الموحد:
       ```http
       POST /api/today-readings/:id/approve-and-whatsapp
       Content-Type: application/json

       {
         "current_reading": 94,
         "previous_reading": 87,
         "lost_units": 0,
         "fixed_fee": 1000,
         "arrears": 18800,
         "paid_amount": 0
       }
       ```
    3. يقوم الباك إند بتنفيذ إجراء `approveMeterReadingRpc` وتحديث أرصدة المشترك، وتوليد صورة الفاتورة فوراً عبر `invoiceRendererService` وإضافتها لطابور رسائل الواتساب `whatsapp_queue_messages`.
    4. يرجع الباك إند `{ success: true, reading_id, invoice_id, queue_id }`.
    5. تتحول شارة الحالة إلى `معتمدة ✅`، وشارة الواتساب إلى `📲 في طابور الإرسال` أو `✅ تم الإرسال`.
    6. إظهار إشعار Toast بنجاح الاعتماد والجدولة.
- **الحالة 2: القراءة معتمدة مسبقاً (`APPROVED`)**:
  - يتحول الزر إلى خيار ثانوي: `[📲 إعادة إرسال بالواتساب]` بلون رمادي/أخضر هادئ.
  - إتاحة زر منسدل فرعي لإجراء "تعديل بعد الاعتماد" أو "إلغاء الاعتماد (Rollback/Reject)".

### 4.2 نظام الشارات المرئية (Badge Status Indicators)

| الحالة البرمجية | نص الشارة بالعربية | التنسيق اللوني (Tailwind Classes) |
|---|---|---|
| `approval_status === 'APPROVED'` | ✅ معتمدة | `bg-emerald-100 text-emerald-800 border-emerald-300` |
| `approval_status === 'PENDING_REVIEW'` | ⏳ قيد المراجعة | `bg-amber-100 text-amber-800 border-amber-300` |
| `approval_status === 'REJECTED'` | ❌ مرفوضة | `bg-rose-100 text-rose-800 border-rose-300` |
| `whatsapp_status === 'SENT'` | 📲 تم الإرسال | `bg-emerald-50 text-emerald-700 border-emerald-200` |
| `whatsapp_status === 'QUEUED'` | ⏳ في طابور الواتساب | `bg-blue-50 text-blue-700 border-blue-200` |
| `whatsapp_status === 'FAILED'` | ⚠️ فشل الإرسال | `bg-red-50 text-red-700 border-red-200` |
| `whatsapp_status === 'NOT_SENT'` | ⚪ لم يُرسل | `bg-slate-100 text-slate-600 border-slate-200` |

---

## 5. العمليات الجماعية وشريط الأدوات والتصدير (Bulk Actions, Filters & Export)

### 5.1 العمليات الجماعية (Bulk Operations)
- **صندوق الاختيار في رأس الجدول (Select All Checkbox)**: تحديد كافة السجلات المعروضة في الصفحة الحالية أو إلغاء تحديدها.
- **شريط العمليات العائم (Floating Bulk Action Bar)**: يظهر تلقائياً أسفل الشاشة عند تحديد سجل واحد أو أكثر:
  - عداد السجلات المحددة: `تم تحديد (X) قراءة`.
  - زر **[⚡ اعتماد وإرسال واتساب للكل المحددين]**: ينفذ طلب الاعتماد والجدولة دفعة واحدة عبر `POST /api/today-readings/bulk-approve`.
  - زر **[📊 تصدير المحدد إلى إكسل]**: تنزيل ملف Excel يحتوي فقط على السجلات المختارة.
  - زر **[❌ إلغاء التحديد]**.

### 5.2 منظومة الفلاتر والبحث (Filtering & Search Ecosystem)
- **شريط البحث اللحظي**: بحث متعدد الحقول (اسم المشترك، رقم المشترك، رقم العداد، رقم الهاتف، اسم المحصل).
- **فلتر خطوط السير (Route Filter)**: قائمة منسدلة بخطوط السير المتوفرة (A1, A2, B1...).
- **فلتر المناطق التجميعية (Area Grouping Filter)**: تبويبات سريعة للمناطق (الجملية، التحرير، الحبوش...) مع عداد السجلات لكل منطقة.
- **فلتر حالة الاعتماد (Approval Filter)**: (الكل، قيد المراجعة فقط، المعتمدة فقط، المرفوضة).
- **فلتر حالة الواتساب (WhatsApp Filter)**: (الكل، المرسلة، غير المرسلة، الفاشلة).

### 5.3 منظومة التصدير والطباعة (Export & Print Engine)
1. **تصدير Excel (.xlsx)**:
   - تصدير كامل الأعمدة الـ 18 باستخدام مكتبة `xlsx` المدمجة.
   - إجبار الأرقام الإنجليزية في جميع الخلايا الرياضية.
   - ضبط اتجاه ورقة العمل كـ RTL (`ws['!views'] = [{ RTL: true }]`).
   - تسمية الملف باسم معبر وتاريخ اليوم: `SmartPower_Today_Readings_2026-09-02.xlsx`.
2. **طباعة الكشف والكوبونات (PDF / Print View)**:
   - تكامل سلس مع مكون `CyclePrintView` المعتمد لدعم طباعة كشف تجميعي شامل أو طباعة الفواتير المفردة بنمط القسيمة الثنائية (فاتورة المشترك + كعب المحصل) المطابقة تماماً للصورة `photo_5769554780358381104_y.jpg`.

---

## 6. التحقق الصارم من الأرقام الإنجليزية والتصميم العربي (Numerals & RTL Verification)

### 6.1 قاعدة الأرقام الإنجليزية (English Numerals Verification)
- **المدخلات (Input Fields)**: تستخدم `type="number"` و `dir="ltr"` مع خط أحادي `font-mono` لضمان أن الإدخال بالإنجليزية حصراً.
- **المخرجات (Display Values)**: تمر عبر دوال `formatters.ts` المركزية:
  ```typescript
  // Format numbers with strict Latin numerals
  export function formatNumber(value: number | string): string {
    return Number(value || 0).toLocaleString('en-US');
  }
  ```
- **حظر تام للأرقام الهندية (٠-٩)**: منع أي دالة تحويل محلية تستخدم أرقاماً مشرقية، واستبدالها بنظام الترقيم اللاتيني `latn`.

### 6.2 تصميم الواجهة ومحاذاة RTL والـ Grid العريض
- تعيين حاوية الجدول كـ `dir="rtl"`.
- محاذاة أسماء المشتركين والعناوين إلى اليمين (`text-right`).
- محاذاة كافة الأعمدة الرقمية والعملات والكميات في المنتصف أو اليسار بخط أحادي `font-mono text-center`.
- شريط تمرير أفقي انسيابي (`overflow-x-auto`) مع تثبيت العمودين الأولين (الترتيب واسم المشترك) بخاصية `sticky right-0` لضمان عدم ضياع هوية المشترك أثناء التمرير الأفقي للأعمدة المالية الـ 18.
- ارتفاع صفوف مضغوط ومريح بنمط جداول البيانات الكثيفة (`py-2 px-2.5 text-xs`).

---

## 7. التكامل مع سجل التدقيق والمراقبة (AuditLogs Integration)

- شاشة `AuditLogs.tsx` مدمجة حالياً ضمن تبويبات الإعدادات (`/settings?tab=audit-logs`) وتعتمد على `getAuditLogsApi`.
- لضمان الشفافية الكاملة، عند قيام المحاسب أو المشرف بتعديل أي خلية في `TodayReadingsReview.tsx` (مثل تعديل القراءة السابقة أو المتأخرات أو الفاقد) أو اعتماد العملية، يتم إرسال سجل تدقيق بالحدث:
  - نوع الإجراء: `READING_FULL_UPDATE` أو `READING_APPROVE_WITH_WHATSAPP`.
  - تفاصيل العملية: توثيق القيمة السابقة والجديدة للمتأخرات والقراءات والفاقد.
  - إبطال كاش `queryClient.invalidateQueries({ queryKey: ['audit-logs'] })` لتظهر العمليات فوراً في سجل التدقيق.

---

## 8. الخطة التنفيذية المقترحة للمطورين (Implementation Plan for Developers)

1. **الخطوة 1: تحديث واجهات الأنواع والخدمات (`types/index.ts` & `services/`)**:
   - إضافة حقول `lost_units`، `lost_cost`، `fixed_fee_snapshot`، `whatsapp_status` إلى واجهات `TodayReadingRecord` و `Invoice`.
   - إنشاء دوال الـ API الجديدة: `approveAndSendWhatsAppApi`، `bulkApproveReadingsApi`، `fullUpdateReadingApi`.
2. **الخطوة 2: بناء مكون جدول العمليات التفاعلي (`TodayReadingsReview.tsx`)**:
   - تطبيق بنية الحالة المحلية `EditableGridRow` مع محرك الاحتساب الفوري `recalculateRowMath`.
   - رسم الأعمدة الـ 18 بتنسيق RTL المتوافق مع شاشات سطح المكتب.
   - تضمين عناصر الإدخال السريع داخل الخلايا مع معالجة أحداث `onChange` و `onBlur` و `onKeyDown`.
3. **الخطوة 3: تفعيل أزرار الاعتماد وشريط العمليات الجماعية**:
   - ربط زر الاعتماد الفردي وتحديث شارات الحالة.
   - تفعيل شريط العمليات الجماعية والـ Checkboxes.
4. **الخطوة 4: تفعيل التصدير لإكسل والتكامل مع الطباعة**:
   - كتابة دالة تصدير Excel للأعمدة الـ 18 بأرقام إنجليزية.
   - ربط زر الطباعة بنافذة `CyclePrintView`.
5. **الخطوة 5: التحقق والاختبار الشامل**:
   - تشغيل أوامر الفحص والـ TypeCheck (`tsc -b`).
   - اختبار سيناريوهات تعديل القراءات، والتحقق من صحة المعادلات المالية.
