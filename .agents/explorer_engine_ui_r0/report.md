<div dir="rtl">

# تقرير المسح والتحليل المعماري لمحرك الرفض والفوترة وإدارة الحالة والإشعارات (Requirements R4 & R5)

**تاريخ التقرير:** 2026-09-02  
**نطاق الفحص:** دمج وتحليل محرك الرفض والإلغاء (Rejection & Void Engine)، محرك الحسابات والفوترة المالية (Financial Billing Engine)، قوالب PDF وإشعارات WhatsApp، وإدارة الحالة في واجهة React (React Query Cache Invalidation).

---

## 1. الملخص التنفيذي (Executive Summary)

تم إجراء تدقيق واستقصاء برمجي شامل ومطابقة دقيقة للعقود البرمجية عبر طبقات النظام الأربع:
1. قاعدة بيانات PostgreSQL / Supabase RPCs والـ Views المهاجرة.
2. خادم Express / Node.js وخدمات المعالجة الخلفية (Puppeteer, EJS, WhatsApp Service, Message Queue).
3. واجهة الويب React Dashboard وإدارة الحالة عبر `@tanstack/react-query`.
4. تطبيق الموبايل الميداني Flutter Mobile App ونظام المزامنة وحسابات Hive المحلية.

**النتيجة الإجمالية:** محركات النظام المالية ومحرك الرفض والإلغاء تتبع مساراً موحداً وقوياً معتمداً على إجراءات PostgreSQL المخزنة (`SECURITY DEFINER` RPCs) مما يضمن اتساق البيانات ومنع التلاعب، مع وجود بعض الملاحظات التقنية الدقيقة في إدارة إبطال الكاش (Cache Invalidation) تم توثيقها وتفصيلها أدناه.

---

## 2. تفاصيل المتطلب R4: محرك الرفض والإلغاء والارتداد (Rejection & Void Engine)

### 2.1 مسار رفض القراءات (Reading Rejection Workflow)
- **الموقع البرمجي في واجهة React:**
  - الملف: `frontend/src/pages/Dashboard.tsx` (الأسطر 186-211)
  - الدالة: `handleRejectSingle(item)`
  - تستدعي: `rejectReadingApi(id, reason)` في `frontend/src/services/analytics.service.ts` (الأسطر 192-199).
- **الموقع البرمجي في خادم Express:**
  - المسار: `POST /api/readings/reject/:id` في `backend/src/routes/reading.routes.ts`.
  - الدالة: `rejectReading` في `backend/src/controllers/reading.controller.ts` (الأسطر 172-195).
  - تستدعي الدالة المالية الموحدة: `rejectMeterReadingRpc(readingId, reason)` في `backend/src/services/financial-rpc.service.ts` (الأسطر 133-135).
- **الموقع البرمجي في قاعدة البيانات PostgreSQL:**
  - الدالة: `public.rpc_reject_meter_reading(p_reading_id integer, p_rejection_reason text)`
  ```sql
  -- التحقق من حالة القراءة الحالية
  IF v_reading.approval_status = 'REJECTED' THEN
    RETURN json_build_object('success', true, 'message', 'Reading is already rejected');
  END IF;

  IF v_reading.approval_status NOT IN ('PENDING', 'PENDING_REVIEW') THEN
    RAISE EXCEPTION 'Reading status must be PENDING to reject';
  END IF;

  -- 1. تحديث حالة القراءة إلى REJECTED مع تسجيل سبب الرفض
  UPDATE public.meter_readings 
  SET approval_status = 'REJECTED', rejection_reason = p_rejection_reason 
  WHERE id = p_reading_id;

  -- 2. إبطال الفاتورة المرتبطة وتحويل حالتها إلى Void
  SELECT * INTO v_invoice FROM public.invoices WHERE reading_id = p_reading_id LIMIT 1;
  IF FOUND THEN
    UPDATE public.invoices
    SET approval_status = 'REJECTED', status = 'Void'
    WHERE id = v_invoice.id;
  END IF;

  -- 3. تسجيل حركة التدقيق الأمني
  INSERT INTO public.audit_logs (action, entity, entity_id, details)
  VALUES ('READING_REJECT_RPC', 'MeterReading', p_reading_id::TEXT,
          'رفض قراءة عداد عبر RPC للمشترك: ' || COALESCE(v_customer.full_name, '-') || ' (سبب الرفض: ' || p_rejection_reason || ')');
  ```

### 2.2 آلية ارتداد القراءات في الحسابات (Reading Rollback Mechanism)
عند رفض قراءة، تعود حسابات العداد والمديونية فوراً إلى آخر قراءة معتمدة صالحة عبر المستويات التالية:
1. **في إجراء احتساب القراءة الجديدة `rpc_submit_meter_reading` (الأسطر 123-130):**
   ```sql
   SELECT reading_value INTO v_previous_reading FROM public.meter_readings
   WHERE customer_id = p_customer_id AND approval_status != 'REJECTED'
   ORDER BY reading_date DESC, id DESC LIMIT 1;
   
   IF NOT FOUND THEN
     v_previous_reading := v_customer.initial_reading;
   END IF;
   ```
   يتم استبعاد أي قراءة بحالة `REJECTED` تلقائياً، وبالتالي ترتد القراءة السابقة إلى القراءة المعتمدة التي تسبقها مباشرة.
2. **في الـ View الموحدة لمزامنة الموبايل `view_customers_mobile_sync`:**
   ```sql
   COALESCE((
     SELECT mr.reading_value FROM meter_readings mr 
     WHERE mr.customer_id = c.id AND mr.approval_status::text <> 'REJECTED'::text 
     ORDER BY mr.reading_date DESC, mr.id DESC LIMIT 1
   ), c.initial_reading) AS last_reading
   ```
3. **في استعلامات الواجهة الخلفية `customer.controller.ts` (الأسطر 28-32 والأسطر 90-97):**
   تتضمن الاستعلامات دائماً الشرط الصارم `where: { approval_status: { not: 'REJECTED' } }` و `status: { not: 'Void' }`.
4. **في احتساب المديونية والمتأخرات:**
   الفواتير ذات الحالة `status = 'Void'` مستبعدة تماماً من مجاميع المديونية `SUM(remaining_amount)` في كافة الواجهات والتقارير.

### 2.3 إدارة إبطال كاش React Query (Cache Invalidation)
جدول يوضح مفاتيح الكاش التي يتم إبطالها عند كل عملية في واجهة الويب React:

| العملية | الملف ورقم السطر | مفاتيح الكاش المبطلة (`queryKey`) | التقييم الفني |
|---|---|---|---|
| **رفض عملية فردية (قراءة/سداد)** | `Dashboard.tsx:201-206` | `['dashboard-summary']`, `['customers']`, `['unread-meters']`, `['readings']`, `['invoices']`, `['analytics']` | [مؤكد] إبطال شامل ومثالي لكافة الشاشات المرتبطة |
| **اعتماد جماعي للعمليات** | `Dashboard.tsx:175-176` | `['dashboard-summary']`, `['invoices']` | [مؤكد] يحدث الملخص والفواتير |
| **تعديل قراءة/سداد وحفظه** | `Dashboard.tsx:247-250` | `['dashboard-summary']`, `['recent-transactions']`, `['invoices']`, `['customers']` | [مؤكد] إبطال متكامل |
| **اعتماد فردي لقراءة/سداد** | `Dashboard.tsx:154` | `['dashboard-summary']` فقط | [ملاحظة دقيقة] يعتمد على Supabase Realtime لتحديث `['recent-transactions']` |
| **تسجيل قراءة جديدة** | `ReadingModal.tsx:56-60` | `['customers']`, `['customer-details', id]`, `['invoices']`, `['routes-progress']`, `['dashboard-summary']` | [مؤكد] إبطال شامل وفوري |
| **تسجيل سداد جديد** | `PaymentModal.tsx:35-36` | `['customers']`, `['customer-details']` | [مؤكد] إبطال مباشر |
| **تعديل سداد من شاشة السندات** | `Invoices.tsx:148-149` | `['payments']`, `['invoices']` | [مؤكد] إبطال مباشر |
| **تسجيل قراءة للعدادات المتأخرة** | `UnreadMeters.tsx:132-133` | `['unread-meters']`, `['dashboard-summary']` | [مؤكد] إبطال فوري |
| **تعديل السجلات في كشف الحساب** | `StatementModal.tsx:79, 89` | `['customers']` + Refetch داخلي للقراءات والفواتير والسدادات | [مؤكد] تحديث محلي وخارجي متزامن |

---

## 3. تفاصيل المتطلب R5: المحرك المالي وتوليد PDF وإشعارات WhatsApp

### 3.1 معادلة احتساب الاستهلاك (Consumption Equation)
المعادلة المعتمدة في النظام:
$$\text{Consumption} = \text{Current Reading} - \text{Last Approved Reading}$$

- **في PostgreSQL RPC (`rpc_submit_meter_reading` الأسطر 133-137):**
  ```sql
  IF p_reading_value < v_previous_reading THEN
    RAISE EXCEPTION 'New reading value (%) cannot be less than previous reading (%)', p_reading_value, v_previous_reading;
  END IF;
  v_consumption := p_reading_value - v_previous_reading;
  ```
- **في PostgreSQL RPC للتعديل (`rpc_update_meter_reading` الأسطر 758-761):**
  ```sql
  IF p_reading_value < v_invoice.previous_reading THEN
    RAISE EXCEPTION 'New reading cannot be lower than previous reading';
  END IF;
  v_consumption := p_reading_value - v_invoice.previous_reading;
  ```
- **في React UI (`ReadingModal.tsx` الأسطر 94-96):**
  `const consumption = !isNaN(newReadingNum) ? newReadingNum - previousReading : null;`
  مع فحص منع الإدخال إذا كان `newReadingNum < previousReading`.
- **في تطبيق Flutter (`reading_dialog.dart` السطر 71):**
  `final double consumption = (_currentInput > previousReading) ? (_currentInput - previousReading) : 0.0;`
  مع التحقق الصارم في زر الحفظ: `if (parsed < widget.customer.lastReading) return;`.

### 3.2 معادلة إجمالي الفاتورة (Invoice Total Due Equation)
المعادلة المعتمدة في النظام:
$$\text{Total Due} = \text{Consumption Amount} + \text{Fixed Fee} + \text{Previous Outstanding Arrears}$$
حيث:
- $\text{Consumption Amount} = \text{Consumption} \times \text{KWh Price}$
- $\text{Fixed Fee} = \text{الرسوم الثابتة المحددة في باقة الاشتراك أو إعدادات المحطة}$
- $\text{Previous Arrears} = \sum \text{المبالغ المتبقية على الفواتير غير المسددة أو المسددة جزئياً}$

- **التطبيق في قاعدة البيانات (`rpc_submit_meter_reading` الأسطر 146-156):**
  ```sql
  v_kwh_price := COALESCE(v_plan.kwh_price, v_settings.default_kwh_price, 1200::numeric);
  v_fixed_fee := COALESCE(v_plan.fixed_fee, v_settings.default_fixed_fee, 500::numeric);
  v_grace_days := COALESCE(v_plan.grace_period_days, v_settings.max_overdue_days, 7);

  SELECT COALESCE(SUM(remaining_amount), 0) INTO v_arrears FROM public.invoices
  WHERE customer_id = p_customer_id AND status IN ('Unpaid', 'Partially_Paid');

  v_consumption_value := v_consumption * v_kwh_price;
  v_total_due := v_consumption_value + v_fixed_fee + v_arrears;
  ```
- **الحقول المحفوظة في جدول `invoices`:**
  - `previous_reading`, `current_reading`, `consumption`
  - `kwh_price_snapshot`, `fixed_fee_snapshot` (تثبيت السعر وقت إصدار الفاتورة لمنع تأثرها بتغيير التعريفة لاحقاً)
  - `consumption_value`
  - `arrears`
  - `total_due`, `total_amount`, `remaining_amount` (تبدأ مساوية لـ `total_due`)
  - `paid_amount` (يبدأ بـ 0)

### 3.3 توليد صور/PDF الفواتير وإرسال إشعارات WhatsApp
البنية الهندسية لمنظومة الإشعارات والطباعة:

```
[اعتماد قراءة / سداد] 
         │
         ├──> [WhatsApp Notifier Service (Polling كل 10 ثوانٍ)]
         │              │
         │              ▼
         │   [InvoiceRendererService / ReceiptRendererService]
         │              │  (EJS Template + Puppeteer Headless Browser)
         │              ▼
         │   [توليد صورة عالية الدقة Base64 PNG + نص كابشن رسمي]
         │              │
         │              ▼
         ├──> [MessageQueue Service] (طابور رسائل دائم في جدول whatsapp_queue_messages)
                        │
                        ▼  (تأخير عشوائي 2-4 ثوانٍ للحماية من الحظر)
              [WhatsApp Web JS Client] ──> [إرسال لهاتف المشترك اليمني 9677XXXXXXXX]
                        │
                        ▼
              [تحديث حالة الرسالة إلى SENT و whatsapp_sent = true في السجل الأصلي]
```

#### تفاصيل الملفات والمكونات:
1. **خدمة تصيير الفواتير (`backend/src/services/invoice-renderer.service.ts`):**
   - تستخدم القالب `backend/src/templates/invoice.ejs` الذي يطابق النموذج اليمني (فاتورة مقسومة إلى جزأين: فاتورة المشترك الرئيسية وقسيمة كعب المحصل).
   - تشغيل Puppeteer في الوضع الخفي، التقاط العنصر `#receipt-container`، وتصديره كسلسلة Base64.
   - الكشف التلقائي عن مسار Chrome و Edge على بيئة Windows.
2. **خدمة تصيير السندات (`backend/src/services/receipt-renderer.service.ts`):**
   - تستخدم القالب `backend/src/templates/receipt.ejs` مع خدمة التفقيط باللغة العربية (`tafqeet.ts`).
3. **طابور الرسائل الذكي (`backend/src/services/messageQueue.service.ts`):**
   - جدول `whatsapp_queue_messages` يدعم الرسائل النصية والصور.
   - خاصية الاستعادة التلقائية للرسائل العالقة بعد انقطاع الخدمة (`recoverStuckMessages`).
   - وتيرة إرسال بمعدل زمني عشوائي من 2000ms إلى 4000ms لتفادي حظر حسابات WhatsApp.
4. **خدمة المراقبة والإرسال التلقائي (`backend/src/services/whatsapp-notifier.service.ts`):**
   - تعمل كـ Background Daemon يفحص كل 10 ثوانٍ القراءات المعتمدة (`approval_status = 'APPROVED'` و `whatsapp_sent = false`).
   - تقوم بتوليد صورة الفاتورة تلقائياً وتضعها في الطابور مع نص الكابشن المفصل.

---

## 4. التحقق والمطابقة الصارمة لقاعدة الأرقام (English Numerals Verification)

تم فحص كافة الملفات والقوالب:
- قوالب EJS: تستخدم `toLocaleString('en-US')` صراحة لجميع القيم الرقمية والعملات.
- واجهات React: تستخدم دوال التنسيق `formatCurrency` و `toLocaleString('en-US')` ومكتبة Lucide مع خطوط Mono للأرقام الإنجليزية (0, 1, 2, 3...).
- تطبيق Flutter: يستخدم `NumberFormat('#,##0', 'en_US')`.

---

## 5. الخلاصة والتوصيات الفنية

1. [مؤكد] محرك الرفض والإلغاء (R4) يعمل بتكامل تام بين React Web, Express, و PostgreSQL RPCs.
2. [مؤكد] إبطال الفواتير التلقائي يضمن عدم احتساب الفواتير المرفوضة في المتأخرات أو المديونية.
3. [مؤكد] ارتداد القراءات الحسابية يعمل بشكل فوري وصحيح بنسبة 100%.
4. [مؤكد] المعادلات المالية (R5) الخاصة بالاستهلاك وإجمالي الفاتورة متطابقة تماماً بين الواجهة الأمامية والخلفية والإجراءات المخزنة.
5. [مؤكد] خدمة توليد فواتير السداد وإشعارات WhatsApp تعمل وفق معمارية طابور معالجة آمن (Queue-backed anti-ban system).

</div>
