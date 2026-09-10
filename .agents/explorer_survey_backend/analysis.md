# تقرير الاستكشاف والتحليل الفني للواجهة الخلفية وقواعد البيانات (Backend & Database Survey Report)

## 1. الملخص التنفيذي (Executive Summary)
تم إجراء فحص واستقصاء معمق لقواعد البيانات (PostgreSQL / Supabase) وشفرة الواجهة الخلفية (Node.js / Express / Prisma) لتغطية متطلبات R4 و R5 المحددة في طلب التطوير:
1. **تشخيص خطأ `column "r" does not exist` في دوال PostgreSQL RPC**: [مؤكد] تم تحديد السبب الجذري بدقة متناهية؛ الخطأ ناجم عن غياب الاسم المستعار (Alias) للجدول `public.meter_readings` في استعلام التحقق من تكرار العملية (Idempotency Check) داخل الدالة `rpc_submit_meter_reading`، حيث كُتب الاستعلام `SELECT row_to_json(r) ... FROM public.meter_readings` بدلاً من `FROM public.meter_readings r` أو `FROM public.meter_readings m`.
2. **منظومة معالجة الأخطاء ورسائل الخطأ العربية (Error Handling & Arabic Messages)**: [مؤكد] توجد دالة `formatRpcErrorMessage` في `financial-rpc.service.ts` تقوم بتحويل الأخطاء الشائعة إلى نصوص عربية، مع وجود معالج أخطاء مركزي في `index.ts`. تم رصد نقاط تحسين لمنع تسريب أي تفاصيل تقنية خام عند حدوث استثناءات غير متوقعة.
3. **مسار الاعتماد التلقائي للمدير (Admin Auto-Approval Flow)**: [مؤكد] تم تفعيل الاعتماد الفوري للقراءات المنشأة بواسطة المسؤول (`autoApprove = true`) عبر استدعاء `approveMeterReadingRpc` مباشرة. تم تحديد تحسين إضافي لدعم `auto_approve` مباشرة داخل دالة `rpc_submit_payment` في PostgreSQL بدلاً من الاعتماد على خطوتين منفصلتين.
4. **سجل العمليات المباشرة والاشتراكات اللحظية (Live Operations & Real-Time Subscriptions)**: [مؤكد] جدول `meter_readings`, `invoices`, `payments`, `customer_credits`, `payment_allocations` مفعلة بالكامل في نشر `supabase_realtime`. الواجهة الأمامية تدعم بالفعل قنوات `supabase.channel`، ويمكن ربط سجل العمليات المباشرة بها مباشرة.
5. **اكتشاف معماري حرج في التوجيه (Routing Discrepancy)**: [مؤكد] ملف `backend/src/index.ts` يقوم بربط `reading.routes.ts` على المسار `/api/readings`، بينما مسارات الدورات والتعديل المباشر للخلايا (`/cycles`, `/cycle-data`, `/:id/cell-update`, `/:id/approve-and-whatsapp`) معرفة في `todayReadings.routes.ts`. يجب توحيد المسارات لضمان وصول الواجهة الأمامية إليها دون تعارض.

---

## 2. التحليل التفصيلي لمتطلب R4: أخطاء دالة PostgreSQL RPC ورسائل الخطأ العربية

### 2.1 السبب الجذري لخطأ `column "r" does not exist` [مؤكد]
- **الموقع في قاعدة البيانات**: دالة `public.rpc_submit_meter_reading(integer, numeric, text, uuid, boolean, timestamp with time zone, text, integer)` في `pg_proc`.
- **الموقع في ملفات الشفرة**:
  - `backend/src/scripts/clean_and_unify_rpc.ts` (السطر 112)
  - `backend/src/scripts/apply_bimonthly_cycle_rpc.ts` (السطر 113)
  - `backend/dist/scripts/clean_and_unify_rpc.js` (السطر 109)
  - `backend/dist/scripts/apply_bimonthly_cycle_rpc.js` (السطr 109)
- **الكود المسبب للخطأ**:
  ```sql
  -- 1. Idempotency Check
  SELECT row_to_json(r) INTO v_existing_json FROM public.meter_readings WHERE client_mutation_id = p_idempotency_key;
  ```
- **التحليل الفني والفيزيائي للخطأ**:
  - دالة `row_to_json(record)` في PL/pgSQL تتطلب اسم متغير أو اسم جدول/اسم مستعار معرف صراحة في جملة `FROM`.
  - الجدول في الاستعلام تم تعريفه كـ `FROM public.meter_readings` دون اسم مستعار `r`.
  - عند قيام محرك PostgreSQL بتفسير الاستعلام، يبحث عن عمود أو كائن بالاسم `r`، ونظراً لعدم وجود عمود بهذا الاسم أو جدول مستعار، يُرجع الخطأ البرمجي:
    `ERROR: column "r" does not exist` (أو `missing FROM-clause entry for table "r"`).
- **المقارنة مع الدوال السليمة**:
  - في دالة `rpc_submit_payment` (السطر 264 و 670):
    `SELECT row_to_json(pm) INTO v_existing_json FROM public.payments pm WHERE pm.client_mutation_id = p_idempotency_key;` (صحيحة 100% لوجود `pm`).
  - في دالة `apply_credit_deduction_rpc.js` (السطر 49):
    `SELECT row_to_json(m) INTO v_existing_json FROM public.meter_readings m WHERE m.client_mutation_id = p_idempotency_key;` (صحيحة 100% لوجود `m`).
- **الحل المقترح المعياري**:
  تعديل جملة التحقق في الدالة `rpc_submit_meter_reading` إلى:
  ```sql
  SELECT row_to_json(m) INTO v_existing_json FROM public.meter_readings m WHERE m.client_mutation_id = p_idempotency_key;
  ```

---

### 2.2 مراجعة طبقة معالجة الأخطاء والرسائل العربية (Error Handling & Arabic Middleware) [مؤكد]
- **الموقع**: `backend/src/services/financial-rpc.service.ts` -> دالة `formatRpcErrorMessage(error)` (الأسطر 13-58).
- **الواقع الحالي**:
  الدالة تستخرج الرسالة الأساسية من استثناءات Prisma / PostgreSQL (`Message: ...` أو `error: ...`) وتطابقها عبر Regular Expressions مع قائمة الأخطاء الشائعة:
  - التحقق من القراءة السابقة -> `"القراءة المدخلة أقل من القراءة السابقة المسجلة للعداد"`
  - القيم السالبة -> `"قيمة القراءة يجب أن تكون رقماً موجباً"`
  - مبالغ السداد -> `"مبلغ السداد يجب أن يكون أكبر من الصفر"`
  - السجلات غير الموجودة (مشترك، فاتورة، قراءة، سند) -> رسائل عربية صريحة
  - تكرار المفتاح الفريد -> `"تم إرسال وقيد هذه المعاملة مسبقاً لمنع التكرار"`
  - الصلاحيات والحسابات غير النشطة -> رسائل عربية واضحة
- **معالج الأخطاء المركزي (Centralized Error Handler)**:
  - في `backend/src/index.ts` (الأسطر 119-146):
    يلتقط أخطاء `JSON parse`, `LIMIT_FILE_SIZE`, `IMPORT_FILE_TYPE_NOT_ALLOWED` ويعيد استجابات JSON عربية برمز 400 أو 500 مع منع تسريب مسارات الملفات (Stack Trace).
- **التحسينات الموصى بها**:
  1. إضافة مطابقة لحالات خطأ القيود الخارجية (Foreign Key Constraints) مثل حذف مشترك مرتبط بفواتير نشطة لتصبح: `"لا يمكن تنفيذ العملية لوجود سجلات مالية مرتبطة"`.
  2. تغليف أي خطأ غير معروف بنص عام: `"حدث خطأ أثناء معالجة العملية المالية، يرجى المحاولة لاحقاً"` مع الاحتفاظ بالتفاصيل الفنية داخل سجلات الخادم فقط (`console.error`).

---

## 3. التحليل التفصيلي لمتطلب R5: مسار الاعتماد التلقائي للمدير وسجل العمليات المباشرة

### 3.1 آلية الاعتماد التلقائي للمدير (Admin Auto-Approval Mechanism) [مؤكد]
- **الوضع الحالي للقراءات (Readings)**:
  - في `backend/src/controllers/todayReadings.controller.ts` (الأسطر 536-571) و `backend/src/controllers/reading.controller.ts` (الأسطر 31-58):
    1. يتحقق الخادم من دور المستخدم `userRole === 'ADMIN' || req.body?.approval_status === 'APPROVED'`.
    2. يُمرر `autoApprove: true` إلى دالة `submitMeterReadingRpc`.
    3. تقوم الدالة بتسجيل القراءة بحالة `APPROVED` والفاتورة بحالة `Unpaid` (أو `Paid` في حال وجود رصيد دائن كافٍ).
    4. يستدعي الكنترولر فوراً `approveMeterReadingRpc(readingId)` للتأكيد المالي وتوليد صورة الفاتورة وإدراجها في طابور رسائل الواتساب (`sendApprovedInvoiceNotification`).
- **الوضع الحالي للمدفوعات (Payments)**:
  - في `backend/src/controllers/payment.controller.ts` (الأسطر 52-56):
    1. عند إنشاء سند سداد بواسطة مسؤول (`userRole === 'ADMIN'`)، يتم استدعاء `approvePaymentRpc(paymentId)` فورياً لتغيير حالة السند من `PENDING` إلى `APPROVED`.
- **الوضع في التعديل المباشر للخلايا (Inline Cell Editing)**:
  - في `backend/src/services/recalculation.service.ts` -> `updateReadingAndRecalculate`:
    أي تعديل يجريه المسؤول على القراءة الحالية أو السابقة أو الوحدات المفقودة أو المتأخرات أو السداد يتم تطبيقه فورياً وإعادة الحساب الرجعي التلقائي لجميع الدورات اللاحقة وحفظها في قاعدة البيانات مع تسجيل حركة تدقيق `RECALCULATE_CASCADE`.

---

### 3.2 سجل العمليات المباشرة وقنوات البث اللحظي (Live Operations Log & Realtime) [مؤكد]
- **حالة نشر Supabase Real-Time في قاعدة البيانات**:
  تم فحص جدول `pg_publication_tables` للنشر `supabase_realtime` وتبين احتوائه على:
  - `public.customers`
  - `public.meter_readings`
  - `public.invoices`
  - `public.payments`
  - `public.payment_allocations`
  - `public.customer_credits`
- **حالة واجهة المستخدم وسجل العمليات**:
  - الواجهة الأمامية في `Dashboard.tsx` تستخدم بالفعل `getSupabase().channel('public:meter_readings')` و `getSupabase().channel('public:payments')` لإعادة جلب المؤشرات فورياً.
  - صفحة `TodayReadingsReview.tsx` (جدول إكسل التفاعلي المكون من 18 عموداً) وصفحة `AuditLogs.tsx` يمكن تزويدهما بنفس اشتراك القنوات (`postgres_changes`) لتحديث الصفوف لحظياً فور إدخال أي محصل لقراءة أو دفعة جديدة من تطبيق الموبايل دون الحاجة لتحديث الصفحة يدوياً.

---

### 3.3 مشكلة التوجيه الحرجة المكتشفة (Routing Discrepancy Observation) [مؤكد]
- **الملاحظة**:
  في `backend/src/index.ts` (السطر 93):
  `app.use('/api/readings', authenticateToken, readingRoutes);`
  حيث يستورد `readingRoutes` من `./routes/reading.routes`.
  بينما مسارات التعديل المباشر والدورات المطلوبة للشاشات الجديدة:
  - `GET /api/readings/cycles`
  - `GET /api/readings/cycle-data`
  - `PUT /api/readings/:id/cell-update`
  - `POST /api/readings/:id/approve-and-whatsapp`
  معرفة بالكامل داخل ملف منفصل هو `backend/src/routes/todayReadings.routes.ts`.
- **الأثر**:
  إذا طلبت الواجهة الأمامية `/api/readings/cycles` أو `cell-update`، فسيعيد السيرفر خطأ 404 إذا لم تكن هذه المسارات متضمنة في مسار `/api/readings` الفعال في `index.ts`.
- **الحل المقترح**:
  دمج مسارات `todayReadings.routes.ts` بالكامل داخل مسار `/api/readings` أو استيراد `todayReadings.routes` كمسار رئيسي في `index.ts`.

---

## 4. مصفوفة التحقق والجاهزية (Verification Matrix)

| البند | الحالة الحالية | الإجراء المطلوب | مستوى الثقة |
|---|---|---|---|
| دالة `rpc_submit_meter_reading` (خطأ `column "r"`) | يوجد استعلام غير مسمى `row_to_json(r)` بدون Alias | تحديث الاستعلام إلى `row_to_json(m) ... FROM public.meter_readings m` في قاعدة البيانات وملفات السكربت | [مؤكد] |
| رسائل الخطأ العربية في الـ RPC | متوفرة عبر `formatRpcErrorMessage` | إضافة تغليف شامل للأخطاء غير المتوقعة ومنع تسريب Stack Traces | [مؤكد] |
| الاعتماد التلقائي للمدير | مطبق في الكنترولر للقراءات والسداد والتعديل الرجعي | ممتاز ويعمل بصورة فورية؛ يوصى بدعم `auto_approve` مباشرة في `rpc_submit_payment` | [مؤكد] |
| مسار `/api/readings` ومسارات الدورات | مسارات الدورات في `todayReadings.routes` غير مدمجة في `reading.routes` | دمج وتوحيد المسارات لضمان عمل `/cycles` و `/cell-update` | [مؤكد] |
| اشتراك Supabase Realtime لسجل العمليات | الجداول مضمنة في `supabase_realtime` | تفعيل اشتراك `supabase.channel` في صفحة `TodayReadingsReview.tsx` | [مؤكد] |
| سلامة بناء المشروع (Build Integrity) | `npm run build` ناجح 100% في `backend` و `frontend` | الحفاظ على نظافة البناء دون أخطاء TypeScript | [مؤكد] |
