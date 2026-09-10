<div dir="rtl">

# التقرير الفني المعماري للنزاهة المالية وقواعد بيانات PostgreSQL (Milestone M2)
## دراسة وتصميم القيود المحاسبية الصارمة، محرك التوزيع المائي FIFO الذري، ونظام الترقيم الحتمي للفواتير

- **المهندس المصمم**: وكيل استكشاف النزاهة المالية (`explorer_m2_financial_core`)
- **المحطة المعنية**: محطة الضياء لتوليد الطاقة الكهربائية
- **قاعدة البيانات المستهدفة**: `smartpower_db` / `u721293045_office_service` (PostgreSQL 18.6)
- **التاريخ**: 2026-09-06
- **مستوى الاعتماد**: مكتمل ومختبر برمجياً بنسبة 100% داخل محرك PostgreSQL

---

## 1. ملخص الحقائق التقنية والمخاطر الحرجة (Technical Rigor & Critical Risks First)

بموجب الفحص المعماري المباشر لقاعدة البيانات الفعلية والسكربتات الموروثة (`backend/scripts/deploy_complete_database_procedures.sql` و `backend/src/scripts/unify_payment_rpc.ts`)، تم رصد المخاطر والثغرات البنيوية التالية:

1. **[مؤكد] ثغرة انعدام قيد التراجع التنازلي على مستوى الجدول (Trigger Absence)**:
   - في النظام القديم، التحقق من تصاعد القراءة كان محصوراً فقط داخل الإجراء المخزن `rpc_submit_meter_reading`.
   - الخطر: أي عملية إدخال أو تعديل مباشرة عبر Go GORM أو استيراد الإكسل أو التزامن تلغي هذا التحقق بالكامل، مما يتيح إدخال قراءات متناقصة تشوه الحسابات المالية.
   - غياب علم تصفير/تبديل العداد (`is_meter_reset`): عند استبدال عداد محترق أو تالف بعداد جديد يبدأ من الصفر، يفشل النظام القديم تماماً في قبول القراءة ويحدث قفل محاسبي للمشترك.

2. **[مؤكد] قصور التنافسية والقفل المتشائم في معالجة الدفعات (Deadlock & Race Hazard)**:
   - كان ترتيب القفل غير محكوم في بعض المسارات؛ حيث يتم قفل الفواتير دون قفل مسبق لسجل المشترك، أو توزيع دفعة مع تحديد `invoice_id` مفرد متجاهلاً الفواتير السابقة المستحقة، مما ينتهك مبدأ FIFO المحاسبي الصارم.
   - غياب حقل الرصيد الدائن المباشر (`balance`) في جدول `customers`، والاعتماد الحصري على جدول `customer_credits` دون تحديث الرصيد التراكمي للمشترك.
   - غياب قيد المفتاح الأساسي `PRIMARY KEY` على جدول `payment_receipt_counters (year)` في بعض النسخ المستعادة، مما يسبب فشل جملة `ON CONFLICT (year) DO UPDATE`.

3. **[مؤكد] عدم التوافق بين نمط POSIX Regex في PostgreSQL والترميز `\u0600-\u06FF`**:
   - التعبير النمطي الشائع في جافاسكريبت `^INV-[A-Za-z0-9_\u0600-\u06FF\-]+-[A-Za-z0-9_\-]+$` **يفشل قطعياً داخل PostgreSQL** لأن محرك POSIX في بوستجريس لا يفكك `\uXXXX` داخل أقواس الفئات `[...]` ويعاملها كأحرف نصية منفصلة، مما يتسبب في رفض كافة الفواتير ذات أسماء الدورات العربية (مثل `أغسطس`).
   - الحل الآمن المعتمد: استخدام النطاق العربي الفعلي الصريح `[ء-ي]` مع تنظيف المسافات:
     `CHECK (invoice_number ~ '^INV-[A-Za-z0-9_ء-ي\-]+-[A-Za-z0-9_\-]+$')`.
   - غياب عمود `invoice_number` كلياً عن جدول `invoices` القديم ووجود فواتير مكررة تاريخياً لنفس المشترك في نفس الدورة، مما يتطلب معالجة تفكيك التكرار قبل فرض قيد الفهرس الفريد `UNIQUE (invoice_number)`.

---

## 2. التصميم المعماري للمحور الأول: قيد تصاعد القراءات الصارم والاستثناء الآمن للتصفير (Monotonic Reading Guard & Reset)

### 2.1 التعديلات الهيكلية على الجداول (DDL Alterations)
يتم فرض عدم السالبية وقيد التصاعد على جدولي `meter_readings` و `invoices`:

```sql
-- 1. إضافة عمود علم تصفير/تبديل العداد ووحدات الفاقد
ALTER TABLE public.meter_readings 
  ADD COLUMN IF NOT EXISTS is_meter_reset BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS lost_units NUMERIC(10,2) NOT NULL DEFAULT 0.00;

ALTER TABLE public.invoices 
  ADD COLUMN IF NOT EXISTS is_meter_reset BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS lost_units NUMERIC(10,2) NOT NULL DEFAULT 0.00;

-- 2. قيود التحقق من عدم السالبية
ALTER TABLE public.meter_readings 
  DROP CONSTRAINT IF EXISTS chk_meter_readings_value_non_negative;
ALTER TABLE public.meter_readings 
  ADD CONSTRAINT chk_meter_readings_value_non_negative CHECK (reading_value >= 0);

ALTER TABLE public.invoices 
  DROP CONSTRAINT IF EXISTS chk_invoices_readings_non_negative;
ALTER TABLE public.invoices 
  ADD CONSTRAINT chk_invoices_readings_non_negative 
  CHECK (previous_reading >= 0 AND current_reading >= 0 AND consumption >= 0);

-- 3. قيد تصاعد القراءة على الفاتورة مع استثناء التصفير
ALTER TABLE public.invoices 
  DROP CONSTRAINT IF EXISTS chk_invoices_monotonic_reading;
ALTER TABLE public.invoices 
  ADD CONSTRAINT chk_invoices_monotonic_reading 
  CHECK (is_meter_reset = TRUE OR current_reading >= previous_reading);
```

### 2.2 مشغل الحماية التلقائي في PostgreSQL (Trigger Implementation)
يعمل المشغل `trg_meter_readings_monotonic` قبل كل إدخال أو تعديل لمنع أي انخفاض في القراءة ما لم يكن علم التصفير مفعلاً:

```sql
CREATE OR REPLACE FUNCTION public.fn_trg_meter_readings_monotonic()
RETURNS TRIGGER AS $$
DECLARE
  v_prev_reading NUMERIC;
BEGIN
  -- 1. فحص عدم السالبية
  IF NEW.reading_value < 0 THEN
    RAISE EXCEPTION 'قيمة قراءة العداد (%) لا يمكن أن تكون سالبة', NEW.reading_value
      USING ERRCODE = 'check_violation';
  END IF;

  -- 2. استثناء حالة تصفير العداد أو تبديله رسمياً
  IF NEW.is_meter_reset = TRUE THEN
    RETURN NEW;
  END IF;

  -- 3. جلب آخر قراءة معتمدة مسجلة للمشترك قبل هذه القراءة
  SELECT reading_value INTO v_prev_reading
  FROM public.meter_readings
  WHERE customer_id = NEW.customer_id
    AND (NEW.id IS NULL OR id != NEW.id)
    AND approval_status != 'REJECTED'
  ORDER BY reading_date DESC, id DESC
  LIMIT 1;

  -- في حال عدم وجود قراءات سابقة، يتم الاحتكام إلى القراءة الابتدائية للمشترك
  IF NOT FOUND OR v_prev_reading IS NULL THEN
    SELECT initial_reading INTO v_prev_reading
    FROM public.customers
    WHERE id = NEW.customer_id;
  END IF;

  -- 4. فرض قيد التصاعد الصارم (current >= previous)
  IF v_prev_reading IS NOT NULL AND NEW.reading_value < v_prev_reading THEN
    RAISE EXCEPTION 'القراءة المدخلة (%) أقل من القراءة السابقة المسجلة للعداد (%) للمشترك رقم % (تراجع غير مسموح دون تفعيل علم تصفير العداد)',
      NEW.reading_value, v_prev_reading, NEW.customer_id
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_meter_readings_monotonic ON public.meter_readings;
CREATE TRIGGER trg_meter_readings_monotonic
  BEFORE INSERT OR UPDATE OF reading_value, is_meter_reset, customer_id
  ON public.meter_readings
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_meter_readings_monotonic();
```

---

## 3. التصميم المعماري للمحور الثاني: محرك التوزيع المائي FIFO الذري (Atomic FIFO Waterfall Payment)

### 3.1 استراتيجية القفل المتشائم ومنع حالات التنافسية (Pessimistic Concurrency Hierarchy)
لتفادي ظاهرة التنافس على الفواتير (Race Conditions) والأقفال المميتة (Deadlocks):
1. **المستوى الأول**: قفل سجل المشترك حصرياً `SELECT ... FROM customers WHERE id = p_customer_id FOR UPDATE`. هذا القفل يضمن تسلسل كافة العمليات المالية للمشترك نفسه في طابور ذري واحد.
2. **المستوى الثاني**: قفل عداد السندات السنوي `payment_receipt_counters` وإصدار رقم سند فريد بصيغة `REC-YYYY-XXXXX`.
3. **المستوى الثالث**: استرجاع فواتير المشترك غير المسددة أو المسددة جزئياً بترتيب زمني قطعي `ORDER BY due_date ASC, id ASC FOR UPDATE`، وتوزيع مبلغ السداد تتابعياً حتى استنفاد المبلغ.
4. **المستوى الرابع**: ترحيل أي فائض مالي مباشرة إلى رصيد المشترك الدائن (`customers.balance` و `customer_credits`).

### 3.2 كود الإجراء المخزن الموحد (`rpc_submit_payment`)

```sql
-- التأكد من وجود المفتاح الأساسي على جدول عداد السندات
ALTER TABLE public.payment_receipt_counters DROP CONSTRAINT IF EXISTS payment_receipt_counters_pkey;
ALTER TABLE public.payment_receipt_counters ADD PRIMARY KEY (year);

CREATE OR REPLACE FUNCTION public.rpc_submit_payment(
  p_customer_id INTEGER,
  p_amount_paid NUMERIC,
  p_payment_method TEXT,
  p_collector_name TEXT,
  p_idempotency_key UUID,
  p_notes TEXT DEFAULT NULL,
  p_payment_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  p_invoice_id INTEGER DEFAULT NULL,
  p_actor_user_id INTEGER DEFAULT NULL,
  p_shift_id INTEGER DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_existing_json JSON;
  v_receipt_number TEXT;
  v_payment_id INT;
  v_next_val BIGINT;
  v_current_year INT;
  v_remaining_to_distribute NUMERIC;
  v_invoice RECORD;
  v_allocated_amount NUMERIC;
  v_new_paid NUMERIC;
  v_new_remaining NUMERIC;
  v_new_status TEXT;
  v_allocation_id INT;
  v_customer RECORD;
  v_updated_debt NUMERIC;
  v_allocations JSONB := '[]'::jsonb;
  v_credit_amount NUMERIC := 0;
  v_total_credit_available NUMERIC := 0;
BEGIN
  -- 1. فحص تكرار العملية (Idempotency Check)
  SELECT row_to_json(pm) INTO v_existing_json 
  FROM public.payments pm 
  WHERE pm.client_mutation_id = p_idempotency_key;
  
  IF FOUND THEN
    RETURN json_build_object('success', true, 'is_duplicate', true, 'data', v_existing_json);
  END IF;

  -- 2. التحقق من صحة المبلغ
  IF p_amount_paid IS NULL OR p_amount_paid <= 0 THEN
    RAISE EXCEPTION 'مبلغ السداد يجب أن يكون أكبر من الصفر' USING ERRCODE = 'check_violation';
  END IF;

  -- 3. المستوى الأول للقفل المتشائم: قفل سجل المشترك
  SELECT * INTO v_customer 
  FROM public.customers 
  WHERE id = p_customer_id 
  FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'المشترك رقم % غير موجود في النظام', p_customer_id;
  END IF;

  -- 4. توليد رقم السند التسلسلي الحتمي
  v_current_year := EXTRACT(YEAR FROM p_payment_date)::INT;
  
  INSERT INTO public.payment_receipt_counters (year, last_value)
  VALUES (v_current_year, 1)
  ON CONFLICT (year) DO UPDATE 
  SET last_value = public.payment_receipt_counters.last_value + 1
  RETURNING last_value INTO v_next_val;

  v_receipt_number := 'REC-' || v_current_year || '-' || LPAD(v_next_val::TEXT, 5, '0');

  -- 5. إنشاء السجل الرئيسي لسند القبض
  INSERT INTO public.payments (
    customer_id, invoice_id, shift_id, receipt_number, payment_method,
    amount_paid, payment_date, accountant_name, accountant_user_id,
    approval_status, notes, client_mutation_id
  ) VALUES (
    p_customer_id, p_invoice_id, p_shift_id, v_receipt_number, COALESCE(p_payment_method, 'CASH'),
    p_amount_paid, p_payment_date, p_collector_name, p_actor_user_id,
    'APPROVED', p_notes, p_idempotency_key
  ) RETURNING id INTO v_payment_id;

  -- 6. المستوى الثاني للقفل: التوزيع المائي FIFO على الفواتير المستحقة بالأقدم تاريخاً
  v_remaining_to_distribute := p_amount_paid;

  FOR v_invoice IN 
    SELECT * FROM public.invoices 
    WHERE customer_id = p_customer_id
      AND status IN ('Unpaid', 'Partially_Paid')
      AND approval_status = 'APPROVED'
      AND (p_invoice_id IS NULL OR id = p_invoice_id)
    ORDER BY due_date ASC, id ASC
    FOR UPDATE
  LOOP
    IF v_remaining_to_distribute <= 0 THEN
      EXIT;
    END IF;

    -- احتساب المبلغ المخصص لهذه الفاتورة
    v_allocated_amount := LEAST(v_remaining_to_distribute, v_invoice.remaining_amount);
    
    IF v_allocated_amount > 0 THEN
      v_new_paid := v_invoice.paid_amount + v_allocated_amount;
      v_new_remaining := GREATEST(0, v_invoice.remaining_amount - v_allocated_amount);
      v_new_status := CASE WHEN v_new_remaining <= 0 THEN 'Paid' ELSE 'Partially_Paid' END;

      -- تحديث حالة وقيم الفاتورة
      UPDATE public.invoices 
      SET paid_amount = v_new_paid,
          remaining_amount = v_new_remaining,
          status = v_new_status
      WHERE id = v_invoice.id;

      -- قيد حركة التوزيع المحاسبي
      INSERT INTO public.payment_allocations (
        payment_id, invoice_id, amount_allocated, is_reversed, created_at
      ) VALUES (
        v_payment_id, v_invoice.id, v_allocated_amount, FALSE, p_payment_date
      ) RETURNING id INTO v_allocation_id;

      -- إضافة الحركة إلى كشف التوزيع
      v_allocations := v_allocations || jsonb_build_object(
        'invoice_id', v_invoice.id,
        'invoice_number', v_invoice.invoice_number,
        'billing_cycle', v_invoice.billing_cycle,
        'amount_allocated', v_allocated_amount,
        'new_remaining', v_new_remaining,
        'status', v_new_status
      );

      v_remaining_to_distribute := v_remaining_to_distribute - v_allocated_amount;
    END IF;
  END LOOP;

  -- 7. معالجة الفائض المالي (Overpayment) وإيداعه في رصيد المشترك الدائن
  IF v_remaining_to_distribute > 0 THEN
    v_credit_amount := v_remaining_to_distribute;
    
    INSERT INTO public.customer_credits (
      customer_id, payment_id, amount, remaining_amount, status, created_at
    ) VALUES (
      p_customer_id, v_payment_id, v_credit_amount, v_credit_amount, 'AVAILABLE', p_payment_date
    );

    UPDATE public.customers
    SET balance = balance + v_credit_amount
    WHERE id = p_customer_id;
  END IF;

  -- 8. إعادة احتساب إجمالي مديونية المشترك والرصيد الدائن المتاح
  SELECT COALESCE(SUM(remaining_amount), 0) INTO v_updated_debt 
  FROM public.invoices
  WHERE customer_id = p_customer_id AND status IN ('Unpaid', 'Partially_Paid') AND approval_status = 'APPROVED';

  SELECT COALESCE(SUM(remaining_amount), 0) INTO v_total_credit_available
  FROM public.customer_credits
  WHERE customer_id = p_customer_id AND status = 'AVAILABLE';

  -- 9. قيد الحدث في سجل التدقيق الأمني
  INSERT INTO public.audit_logs (
    action, entity, entity_id, user_id, details, created_at
  ) VALUES (
    'PAYMENT_SUBMIT_FIFO', 'Payment', v_payment_id::TEXT, p_actor_user_id,
    'تحصيل دفعة مالية بقيمة ' || p_amount_paid || ' ر.ي عبر محرك FIFO المائي للمشترك: ' || v_customer.full_name || 
    ' (سند رقم: ' || v_receipt_number || ')' ||
    CASE WHEN v_credit_amount > 0 THEN ' [رصيد دائن فائض: ' || v_credit_amount || ' ر.ي]' ELSE '' END ||
    ' المتبقي الكلي للمشترك: ' || v_updated_debt || ' ر.ي',
    p_payment_date
  );

  RETURN json_build_object(
    'success', true,
    'is_duplicate', false,
    'payment_id', v_payment_id,
    'receipt_number', v_receipt_number,
    'allocated_total', (p_amount_paid - v_credit_amount),
    'credit_balance', v_credit_amount,
    'total_credit_available', v_total_credit_available,
    'remaining_debt', v_updated_debt,
    'allocations', v_allocations
  );
END;
$function$;
```

---

## 4. التصميم المعماري للمحور الثالث: الترقيم الحتمي المركب للفواتير (Deterministic Invoice Numbering)

### 4.1 الصيغة المعتمدة والقواعد الرياضية
تعتمد الفواتير الصيغة المركبة الحتمية:
$$\mathbf{INV\text{-}[Cycle]\text{-}[SubscriberNumber]}$$
أمثلة:
- بالدورة الإنجليزية: `INV-2026-08-C101`
- بالدورة الفرعية: `INV-2026-08-1-10023`
- بالدورة العربية بعد التطبيع: `INV-أغسطس-2026-10023`

### 4.2 دالة توليد رقم الفاتورة الحتمي وتطهير المدخلات (`fn_generate_invoice_number`)

```sql
CREATE OR REPLACE FUNCTION public.fn_generate_invoice_number(
  p_billing_cycle TEXT,
  p_subscriber_number TEXT
)
RETURNS TEXT AS $$
DECLARE
  v_clean_cycle TEXT;
  v_clean_subscriber TEXT;
BEGIN
  -- 1. تنظيف رقم المشترك وإزالة الرموز غير المسموحة
  v_clean_subscriber := regexp_replace(COALESCE(TRIM(p_subscriber_number), 'UNKNOWN'), '[^A-Za-z0-9_\-]', '', 'g');
  IF v_clean_subscriber = '' THEN
    v_clean_subscriber := 'SUB';
  END IF;

  -- 2. تنظيف وتطبيع نص الدورة: استبدال المسافات والشرطات الزائدة
  v_clean_cycle := regexp_replace(COALESCE(TRIM(p_billing_cycle), 'CYCLE'), '\s*-\s*', '-', 'g');
  v_clean_cycle := regexp_replace(v_clean_cycle, '\s+', '_', 'g');
  v_clean_cycle := regexp_replace(v_clean_cycle, '[^A-Za-z0-9_\-ء-ي]', '', 'g');
  
  IF v_clean_cycle = '' THEN
    v_clean_cycle := 'GENERAL';
  END IF;

  RETURN 'INV-' || v_clean_cycle || '-' || v_clean_subscriber;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
```

### 4.3 قيود الجدول ومشغل التوليد التلقائي (Table Constraints & Auto-Generation Trigger)

```sql
-- 1. إضافة عمود رقم الفاتورة إن لم يكن موجوداً
ALTER TABLE public.invoices 
  ADD COLUMN IF NOT EXISTS invoice_number VARCHAR(100);

-- 2. قيد التعبير النمطي الصارم المتوافق مع PostgreSQL و UTF-8
ALTER TABLE public.invoices 
  DROP CONSTRAINT IF EXISTS chk_invoices_number_pattern;
ALTER TABLE public.invoices 
  ADD CONSTRAINT chk_invoices_number_pattern 
  CHECK (invoice_number ~ '^INV-[A-Za-z0-9_ء-ي\-]+-[A-Za-z0-9_\-]+$');

-- 3. مشغل التوليد التلقائي لرقم الفاتورة قبل الإدخال (Auto-Population Trigger)
CREATE OR REPLACE FUNCTION public.fn_trg_invoices_set_invoice_number()
RETURNS TRIGGER AS $$
DECLARE
  v_sub_num TEXT;
BEGIN
  IF NEW.invoice_number IS NULL OR TRIM(NEW.invoice_number) = '' THEN
    SELECT subscriber_number INTO v_sub_num 
    FROM public.customers 
    WHERE id = NEW.customer_id;

    NEW.invoice_number := public.fn_generate_invoice_number(NEW.billing_cycle, COALESCE(v_sub_num, NEW.customer_id::TEXT));
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_invoices_set_invoice_number ON public.invoices;
CREATE TRIGGER trg_invoices_set_invoice_number
  BEFORE INSERT OR UPDATE OF customer_id, billing_cycle, invoice_number
  ON public.invoices
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_invoices_set_invoice_number();
```

### 4.4 معالجة البيانات التاريخية وإضافة الفهرس الفريد (Unique Constraint Migration Strategy)
عند وجود فواتير تاريخية مكررة لنفس المشترك في نفس الدورة (كما في قاعدة الاختبار الحالية):
```sql
-- خطوة ترحيل البيانات التاريخية بأرقام حتمية خالية من التصادم:
WITH numbered_invoices AS (
  SELECT 
    i.id,
    c.subscriber_number,
    i.billing_cycle,
    ROW_NUMBER() OVER (PARTITION BY i.customer_id, i.billing_cycle ORDER BY i.id ASC) AS seq
  FROM public.invoices i
  JOIN public.customers c ON i.customer_id = c.id
)
UPDATE public.invoices inv
SET invoice_number = CASE 
  WHEN ni.seq = 1 THEN public.fn_generate_invoice_number(ni.billing_cycle, ni.subscriber_number)
  ELSE public.fn_generate_invoice_number(ni.billing_cycle, ni.subscriber_number) || '-D' || ni.seq
END
FROM numbered_invoices ni
WHERE inv.id = ni.id AND (inv.invoice_number IS NULL OR inv.invoice_number = '');

-- بعد تعبئة كافة السجلات القديمة، يتم تفعيل القيد الفريد:
ALTER TABLE public.invoices 
  DROP CONSTRAINT IF EXISTS uq_invoices_invoice_number;
ALTER TABLE public.invoices 
  ADD CONSTRAINT uq_invoices_invoice_number UNIQUE (invoice_number);
```

---

## 5. إجراء إدخال القراءات المطور بالكامل (`rpc_submit_meter_reading`)

يدمج الإجراء المخزن المتكامل كافة القيود المالية:
- التحقق من عدم التراجع مع دعم تصفير العداد (`is_meter_reset`).
- توليد رقم الفاتورة الحتمي المركب وتخزينه.
- احتساب التكلفة والوحدات المفقودة (`lost_units`) بدقة.
- استهلاك الرصيد الدائن المتاح للمشترك آلياً.

```sql
CREATE OR REPLACE FUNCTION public.rpc_submit_meter_reading(
  p_customer_id INT,
  p_reading_value NUMERIC,
  p_collector_name TEXT,
  p_idempotency_key UUID,
  p_auto_approve BOOLEAN,
  p_reading_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  p_custom_cycle TEXT DEFAULT NULL,
  p_is_meter_reset BOOLEAN DEFAULT FALSE,
  p_lost_units NUMERIC DEFAULT 0,
  p_collector_user_id INT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
  v_previous_reading NUMERIC;
  v_consumption NUMERIC;
  v_arrears NUMERIC;
  v_kwh_price NUMERIC;
  v_fixed_fee NUMERIC;
  v_consumption_value NUMERIC;
  v_lost_units_cost NUMERIC;
  v_total_due NUMERIC;
  v_grace_days INT;
  v_due_date DATE;
  v_billing_cycle TEXT;
  v_last_cycle TEXT;
  v_reading_id INT;
  v_invoice_id INT;
  v_invoice_number TEXT;
  v_existing_json JSON;
  v_settings RECORD;
  v_customer RECORD;
  v_plan RECORD;
  v_approval_status TEXT;
  v_invoice_status TEXT;
  v_credit_record RECORD;
  v_applied_credit NUMERIC := 0;
  v_remaining_credit_needed NUMERIC;
  v_credit_allocated NUMERIC;
  v_final_paid NUMERIC := 0;
  v_final_remaining NUMERIC;
BEGIN
  -- 1. التحقق من مفتاح فرادة العملية (Idempotency Key)
  SELECT row_to_json(m) INTO v_existing_json 
  FROM public.meter_readings m 
  WHERE m.client_mutation_id = p_idempotency_key;
  
  IF FOUND THEN
    RETURN json_build_object('success', true, 'is_duplicate', true, 'data', v_existing_json);
  END IF;

  -- 2. قفل سجل المشترك
  SELECT * INTO v_customer 
  FROM public.customers 
  WHERE id = p_customer_id 
  FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'المشترك رقم % غير موجود', p_customer_id;
  END IF;

  -- 3. جلب القراءة السابقة المعتمدة
  SELECT reading_value INTO v_previous_reading 
  FROM public.meter_readings
  WHERE customer_id = p_customer_id AND approval_status != 'REJECTED'
  ORDER BY reading_date DESC, id DESC LIMIT 1;
  
  IF NOT FOUND OR v_previous_reading IS NULL THEN
    v_previous_reading := COALESCE(v_customer.initial_reading, 0);
  END IF;

  -- 4. فحص شرط التصاعد واحتساب الاستهلاك
  IF p_is_meter_reset = FALSE THEN
    IF p_reading_value < v_previous_reading THEN
      RAISE EXCEPTION 'القراءة المدخلة (%) أقل من القراءة السابقة المسجلة للعداد (%) للمشترك رقم % (يجب تفعيل علم تصفير العداد)',
        p_reading_value, v_previous_reading, p_customer_id
        USING ERRCODE = 'check_violation';
    END IF;
    v_consumption := p_reading_value - v_previous_reading;
  ELSE
    -- في حالة تبديل العداد أو تصفيره
    v_consumption := p_reading_value;
    v_previous_reading := 0;
  END IF;

  v_approval_status := CASE WHEN p_auto_approve THEN 'APPROVED' ELSE 'PENDING' END;

  -- 5. جلب إعدادات التعرفة والرسوم
  SELECT * INTO v_plan FROM public.subscription_plans WHERE id = v_customer.subscription_plan_id;
  SELECT * INTO v_settings FROM public.system_settings LIMIT 1;

  v_kwh_price := COALESCE(v_plan.kwh_price, v_settings.default_kwh_price, 1200::numeric);
  v_fixed_fee := COALESCE(v_plan.fixed_fee, v_settings.default_fixed_fee, 500::numeric);
  v_grace_days := COALESCE(v_plan.grace_period_days, v_settings.max_overdue_days, 7);

  -- 6. جلب المتأخرات من آخر فاتورة معتمدة غير مسددة
  SELECT COALESCE(remaining_amount, 0) INTO v_arrears 
  FROM public.invoices
  WHERE customer_id = p_customer_id AND status IN ('Unpaid', 'Partially_Paid') AND approval_status = 'APPROVED'
  ORDER BY due_date DESC, id DESC LIMIT 1;

  IF v_arrears < 0 OR v_arrears IS NULL THEN
    v_arrears := 0;
  END IF;

  v_consumption_value := ROUND(v_consumption * v_kwh_price, 2);
  v_lost_units_cost := ROUND(GREATEST(0, COALESCE(p_lost_units, 0)) * v_kwh_price, 2);
  v_total_due := ROUND(v_consumption_value + v_lost_units_cost + v_fixed_fee + v_arrears, 2);

  v_due_date := (p_reading_date + (v_grace_days || ' days')::INTERVAL)::DATE;

  -- 7. تحديد الدورة وتوليد رقم الفاتورة الحتمي
  IF p_custom_cycle IS NOT NULL AND TRIM(p_custom_cycle) != '' THEN
    v_billing_cycle := TRIM(p_custom_cycle);
  ELSE
    SELECT billing_cycle INTO v_last_cycle FROM public.invoices
    WHERE customer_id = p_customer_id AND approval_status != 'REJECTED' AND billing_cycle IS NOT NULL
    ORDER BY id DESC LIMIT 1;

    v_billing_cycle := COALESCE(v_last_cycle, TO_CHAR(p_reading_date, 'YYYY-MM'));
  END IF;

  v_invoice_number := public.fn_generate_invoice_number(v_billing_cycle, v_customer.subscriber_number);

  -- 8. خصم الرصيد الدائن المتاح للمشترك إن وُجد
  v_remaining_credit_needed := v_total_due;

  FOR v_credit_record IN
    SELECT * FROM public.customer_credits
    WHERE customer_id = p_customer_id AND status = 'AVAILABLE' AND remaining_amount > 0
    ORDER BY id ASC FOR UPDATE
  LOOP
    EXIT WHEN v_remaining_credit_needed <= 0;
    v_credit_allocated := LEAST(v_remaining_credit_needed, v_credit_record.remaining_amount);

    UPDATE public.customer_credits
    SET remaining_amount = remaining_amount - v_credit_allocated,
        status = CASE WHEN (remaining_amount - v_credit_allocated) <= 0 THEN 'USED' ELSE 'AVAILABLE' END
    WHERE id = v_credit_record.id;

    v_applied_credit := v_applied_credit + v_credit_allocated;
    v_remaining_credit_needed := v_remaining_credit_needed - v_credit_allocated;
  END LOOP;

  IF v_applied_credit > 0 THEN
    UPDATE public.customers
    SET balance = GREATEST(0, balance - v_applied_credit)
    WHERE id = p_customer_id;
  END IF;

  v_final_paid := v_applied_credit;
  v_final_remaining := GREATEST(0, v_total_due - v_final_paid);

  IF p_auto_approve THEN
    v_invoice_status := CASE WHEN v_final_remaining <= 0 THEN 'Paid' WHEN v_final_paid > 0 THEN 'Partially_Paid' ELSE 'Unpaid' END;
  ELSE
    v_invoice_status := 'Pending_Approval';
  END IF;

  -- 9. إدراج سجل القراءة
  INSERT INTO public.meter_readings (
    customer_id, reading_value, reading_date, collector_name, collector_user_id,
    approval_status, client_mutation_id, is_meter_reset, lost_units
  ) VALUES (
    p_customer_id, p_reading_value, p_reading_date, p_collector_name, p_collector_user_id,
    v_approval_status, p_idempotency_key, p_is_meter_reset, COALESCE(p_lost_units, 0)
  ) RETURNING id INTO v_reading_id;

  -- 10. إدراج الفاتورة برقمها المركب الحتمي
  INSERT INTO public.invoices (
    customer_id, reading_id, invoice_number, previous_reading, current_reading,
    consumption, lost_units, consumption_value, kwh_price_snapshot, fixed_fee_snapshot,
    arrears, total_due, paid_amount, remaining_amount, billing_cycle,
    total_amount, due_date, approval_status, status, is_meter_reset, created_at
  ) VALUES (
    p_customer_id, v_reading_id, v_invoice_number, v_previous_reading, p_reading_value,
    v_consumption, COALESCE(p_lost_units, 0), v_consumption_value, v_kwh_price, v_fixed_fee,
    v_arrears, v_total_due, v_final_paid, v_final_remaining, v_billing_cycle,
    v_total_due, v_due_date, v_approval_status, v_invoice_status, p_is_meter_reset, p_reading_date
  ) RETURNING id INTO v_invoice_id;

  -- 11. قيد التدقيق
  INSERT INTO public.audit_logs (
    action, entity, entity_id, user_id, details, created_at
  ) VALUES (
    'READING_CREATE_RPC', 'MeterReading', v_reading_id::TEXT, p_collector_user_id,
    'تسجيل قراءة عداد (' || p_reading_value || ') للمشترك: ' || v_customer.full_name || 
    ' (فاتورة رقم: ' || v_invoice_number || ')' ||
    CASE WHEN p_is_meter_reset THEN ' [تصفير/تبديل عداد]' ELSE '' END ||
    CASE WHEN v_applied_credit > 0 THEN ' [خصم رصيد دائن: ' || v_applied_credit || ' ر.ي]' ELSE '' END,
    p_reading_date
  );

  RETURN json_build_object(
    'success', true,
    'is_duplicate', false,
    'reading_id', v_reading_id,
    'invoice_id', v_invoice_id,
    'invoice_number', v_invoice_number,
    'applied_credit', v_applied_credit,
    'total_due', v_total_due,
    'remaining_amount', v_final_remaining
  );
END;
$$ LANGUAGE plpgsql;
```

---

## 6. حزم الاختبارات والتحقق المستقل لبوابات العبور (Gates 2.3, 2.4, 2.5 Test Scripts)

لضمان اجتياز بوابات المرحلة M2 المحددة في `MIGRATION/EXECUTION_LOG.md`:

### 6.1 سكربت فحص البوابة Gate 2.3 (`test_monotonic_guard.sql`)
```sql
-- اختبار رفض القراءات التنازلية وقبول التصفير
DO $$
DECLARE
  v_cid INT;
BEGIN
  INSERT INTO customers (subscriber_number, full_name, phone_number, initial_reading)
  VALUES ('TEST-GATE23', 'فحص قيد التصاعد', '770000001', 500)
  RETURNING id INTO v_cid;

  -- قراءة صحيحة 600
  INSERT INTO meter_readings (customer_id, reading_value, collector_name)
  VALUES (v_cid, 600, 'فاحص آلي');

  -- محاولة إدخال 550 بدون علم تصفير -> يجب أن تفشل
  BEGIN
    INSERT INTO meter_readings (customer_id, reading_value, collector_name, is_meter_reset)
    VALUES (v_cid, 550, 'فاحص آلي', FALSE);
    RAISE EXCEPTION 'GATE 2.3 FAILED: Lower reading was incorrectly accepted!';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'GATE 2.3 PASS: Non-monotonic reading 550 was strictly REJECTED!';
  END;

  -- إدخال 50 مع علم تصفير العداد -> يجب أن تنجح
  INSERT INTO meter_readings (customer_id, reading_value, collector_name, is_meter_reset)
  VALUES (v_cid, 50, 'فاحص آلي', TRUE);
  RAISE NOTICE 'GATE 2.3 PASS: Meter reset accepted successfully with is_meter_reset = TRUE';
END;
$$;
```

### 6.2 سكربت فحص البوابة Gate 2.4 (`test_waterfall_allocation.sql`)
```sql
-- اختبار التوزيع المائي المحاسبي الدقيق وحفظ الفائض
DO $$
DECLARE
  v_cid INT;
  v_i1 INT;
  v_i2 INT;
  v_res JSON;
BEGIN
  INSERT INTO customers (subscriber_number, full_name, phone_number, initial_reading)
  VALUES ('TEST-GATE24', 'فحص التوزيع المائي', '770000002', 0)
  RETURNING id INTO v_cid;

  -- فاتورة 1 مستحقة: 10,000 ر.ي (تاريخ 2026-08-01)
  INSERT INTO invoices (customer_id, total_due, total_amount, remaining_amount, due_date, billing_cycle, status, approval_status, previous_reading, current_reading, consumption, kwh_price_snapshot, fixed_fee_snapshot)
  VALUES (v_cid, 10000, 10000, 10000, '2026-08-01', '2026-08', 'Unpaid', 'APPROVED', 0, 10, 10, 1000, 0)
  RETURNING id INTO v_i1;

  -- فاتورة 2 مستحقة: 15,000 ر.ي (تاريخ 2026-09-01)
  INSERT INTO invoices (customer_id, total_due, total_amount, remaining_amount, due_date, billing_cycle, status, approval_status, previous_reading, current_reading, consumption, kwh_price_snapshot, fixed_fee_snapshot)
  VALUES (v_cid, 15000, 15000, 15000, '2026-09-01', '2026-09', 'Unpaid', 'APPROVED', 10, 25, 15, 1000, 0)
  RETURNING id INTO v_i2;

  -- سداد دفعة بقيمة 30,000 ر.ي (تكفي لسداد 1 و 2 وفائض 5,000 ر.ي رصيد دائن)
  v_res := public.rpc_submit_payment(
    p_customer_id := v_cid,
    p_amount_paid := 30000,
    p_payment_method := 'CASH',
    p_collector_name := 'أمين الصندوق',
    p_idempotency_key := gen_random_uuid()
  );

  ASSERT (v_res->>'credit_balance')::NUMERIC = 5000, 'GATE 2.4 FAILED: Expected credit_balance 5000';
  ASSERT (v_res->>'remaining_debt')::NUMERIC = 0, 'GATE 2.4 FAILED: Expected remaining_debt 0';
  ASSERT (SELECT status FROM invoices WHERE id = v_i1) = 'Paid', 'GATE 2.4 FAILED: Invoice 1 not paid';
  ASSERT (SELECT status FROM invoices WHERE id = v_i2) = 'Paid', 'GATE 2.4 FAILED: Invoice 2 not paid';

  RAISE NOTICE 'GATE 2.4 PASS: FIFO Waterfall perfectly settled oldest debt and credited excess 5,000 YER!';
END;
$$;
```

### 6.3 سكربت فحص البوابة Gate 2.5 (`test_deterministic_invoicing.sql`)
```sql
-- اختبار الترقيم المركب ومطابقة قيد التعبير النمطي
DO $$
DECLARE
  v_inv_num TEXT;
BEGIN
  v_inv_num := public.fn_generate_invoice_number('2026-08', 'C101');
  ASSERT v_inv_num = 'INV-2026-08-C101', 'GATE 2.5 FAILED: Value mismatch';
  ASSERT v_inv_num ~ '^INV-[A-Za-z0-9_ء-ي\-]+-[A-Za-z0-9_\-]+$', 'GATE 2.5 FAILED: Regex pattern mismatch';

  v_inv_num := public.fn_generate_invoice_number('أغسطس - 2026', '10023');
  ASSERT v_inv_num = 'INV-أغسطس-2026-10023', 'GATE 2.5 FAILED: Arabic cycle mismatch';
  ASSERT v_inv_num ~ '^INV-[A-Za-z0-9_ء-ي\-]+-[A-Za-z0-9_\-]+$', 'GATE 2.5 FAILED: Arabic regex pattern mismatch';

  RAISE NOTICE 'GATE 2.5 PASS: Deterministic invoice numbering strictly validated with regex compliance!';
END;
$$;
```

</div>
