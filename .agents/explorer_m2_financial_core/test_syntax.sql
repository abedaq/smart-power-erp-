BEGIN;

-- 1. Ensure test columns exist in temporary scope
ALTER TABLE public.meter_readings ADD COLUMN IF NOT EXISTS is_meter_reset BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.meter_readings ADD COLUMN IF NOT EXISTS lost_units NUMERIC(10,2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS is_meter_reset BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS lost_units NUMERIC(10,2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS invoice_number VARCHAR(100);
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS balance NUMERIC(10,2) NOT NULL DEFAULT 0.00;

ALTER TABLE public.payment_receipt_counters DROP CONSTRAINT IF EXISTS payment_receipt_counters_pkey;
ALTER TABLE public.payment_receipt_counters ADD PRIMARY KEY (year);

-- 2. Clean or add constraints
ALTER TABLE public.meter_readings DROP CONSTRAINT IF EXISTS chk_meter_readings_value_non_negative;
ALTER TABLE public.meter_readings ADD CONSTRAINT chk_meter_readings_value_non_negative CHECK (reading_value >= 0);

ALTER TABLE public.invoices DROP CONSTRAINT IF EXISTS chk_invoices_monotonic_reading;
ALTER TABLE public.invoices ADD CONSTRAINT chk_invoices_monotonic_reading CHECK (is_meter_reset = TRUE OR current_reading >= previous_reading);

ALTER TABLE public.invoices DROP CONSTRAINT IF EXISTS chk_invoices_number_pattern;
ALTER TABLE public.invoices ADD CONSTRAINT chk_invoices_number_pattern 
  CHECK (invoice_number ~ '^INV-[A-Za-z0-9_ء-ي\-]+-[A-Za-z0-9_\-]+$');

-- 3. Deterministic Invoice Number Generator
CREATE OR REPLACE FUNCTION public.fn_generate_invoice_number(
  p_billing_cycle TEXT,
  p_subscriber_number TEXT
)
RETURNS TEXT AS $$
DECLARE
  v_clean_cycle TEXT;
  v_clean_subscriber TEXT;
BEGIN
  v_clean_subscriber := regexp_replace(COALESCE(TRIM(p_subscriber_number), 'UNKNOWN'), '[^A-Za-z0-9_\-]', '', 'g');
  IF v_clean_subscriber = '' THEN
    v_clean_subscriber := 'SUB';
  END IF;

  v_clean_cycle := regexp_replace(COALESCE(TRIM(p_billing_cycle), 'CYCLE'), '\s*-\s*', '-', 'g');
  v_clean_cycle := regexp_replace(v_clean_cycle, '\s+', '_', 'g');
  v_clean_cycle := regexp_replace(v_clean_cycle, '[^A-Za-z0-9_\-ء-ي]', '', 'g');
  
  IF v_clean_cycle = '' THEN
    v_clean_cycle := 'GENERAL';
  END IF;

  RETURN 'INV-' || v_clean_cycle || '-' || v_clean_subscriber;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 4. Trigger for Invoices to auto-set invoice_number
CREATE OR REPLACE FUNCTION public.fn_trg_invoices_set_invoice_number()
RETURNS TRIGGER AS $$
DECLARE
  v_sub_num TEXT;
BEGIN
  IF NEW.invoice_number IS NULL OR TRIM(NEW.invoice_number) = '' THEN
    SELECT subscriber_number INTO v_sub_num FROM public.customers WHERE id = NEW.customer_id;
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

-- 5. Trigger on meter_readings for strict monotonic validation
CREATE OR REPLACE FUNCTION public.fn_trg_meter_readings_monotonic()
RETURNS TRIGGER AS $$
DECLARE
  v_prev_reading NUMERIC;
BEGIN
  IF NEW.reading_value < 0 THEN
    RAISE EXCEPTION 'قيمة قراءة العداد (%) لا يمكن أن تكون سالبة', NEW.reading_value
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.is_meter_reset = TRUE THEN
    RETURN NEW;
  END IF;

  SELECT reading_value INTO v_prev_reading
  FROM public.meter_readings
  WHERE customer_id = NEW.customer_id
    AND (NEW.id IS NULL OR id != NEW.id)
    AND approval_status != 'REJECTED'
  ORDER BY reading_date DESC, id DESC
  LIMIT 1;

  IF NOT FOUND OR v_prev_reading IS NULL THEN
    SELECT initial_reading INTO v_prev_reading
    FROM public.customers
    WHERE id = NEW.customer_id;
  END IF;

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

-- 6. Enhanced rpc_submit_meter_reading with Monotonic & Meter Reset & Deterministic INV Number
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
  -- 1. Idempotency Check
  SELECT row_to_json(m) INTO v_existing_json 
  FROM public.meter_readings m 
  WHERE m.client_mutation_id = p_idempotency_key;
  
  IF FOUND THEN
    RETURN json_build_object('success', true, 'is_duplicate', true, 'data', v_existing_json);
  END IF;

  -- 2. Lock Customer
  SELECT * INTO v_customer 
  FROM public.customers 
  WHERE id = p_customer_id 
  FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'المشترك رقم % غير موجود', p_customer_id;
  END IF;

  -- 3. Fetch Previous Reading
  SELECT reading_value INTO v_previous_reading 
  FROM public.meter_readings
  WHERE customer_id = p_customer_id AND approval_status != 'REJECTED'
  ORDER BY reading_date DESC, id DESC LIMIT 1;
  
  IF NOT FOUND OR v_previous_reading IS NULL THEN
    v_previous_reading := COALESCE(v_customer.initial_reading, 0);
  END IF;

  -- 4. Validate Monotonicity and Calculate Consumption
  IF p_is_meter_reset = FALSE THEN
    IF p_reading_value < v_previous_reading THEN
      RAISE EXCEPTION 'القراءة المدخلة (%) أقل من القراءة السابقة المسجلة للعداد (%) للمشترك رقم % (يجب تفعيل علم تصفير العداد)',
        p_reading_value, v_previous_reading, p_customer_id
        USING ERRCODE = 'check_violation';
    END IF;
    v_consumption := p_reading_value - v_previous_reading;
  ELSE
    -- Legitimate meter replacement/rollover
    v_consumption := p_reading_value;
    v_previous_reading := 0;
  END IF;

  v_approval_status := CASE WHEN p_auto_approve THEN 'APPROVED' ELSE 'PENDING' END;

  -- 5. Tariff and Fees Snapshots
  SELECT * INTO v_plan FROM public.subscription_plans WHERE id = v_customer.subscription_plan_id;
  SELECT * INTO v_settings FROM public.system_settings LIMIT 1;

  v_kwh_price := COALESCE(v_plan.kwh_price, v_settings.default_kwh_price, 1200::numeric);
  v_fixed_fee := COALESCE(v_plan.fixed_fee, v_settings.default_fixed_fee, 500::numeric);
  v_grace_days := COALESCE(v_plan.grace_period_days, v_settings.max_overdue_days, 7);

  -- 6. Arrears from latest approved unpaid invoice
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

  -- 7. Cycle & Deterministic Invoice Number
  IF p_custom_cycle IS NOT NULL AND TRIM(p_custom_cycle) != '' THEN
    v_billing_cycle := TRIM(p_custom_cycle);
  ELSE
    SELECT billing_cycle INTO v_last_cycle FROM public.invoices
    WHERE customer_id = p_customer_id AND approval_status != 'REJECTED' AND billing_cycle IS NOT NULL
    ORDER BY id DESC LIMIT 1;

    v_billing_cycle := COALESCE(v_last_cycle, TO_CHAR(p_reading_date, 'YYYY-MM'));
  END IF;

  v_invoice_number := public.fn_generate_invoice_number(v_billing_cycle, v_customer.subscriber_number);

  -- 8. Auto-apply Customer Credit
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

  -- 9. Insert Reading
  INSERT INTO public.meter_readings (
    customer_id, reading_value, reading_date, collector_name, collector_user_id,
    approval_status, client_mutation_id, is_meter_reset, lost_units
  ) VALUES (
    p_customer_id, p_reading_value, p_reading_date, p_collector_name, p_collector_user_id,
    v_approval_status, p_idempotency_key, p_is_meter_reset, COALESCE(p_lost_units, 0)
  ) RETURNING id INTO v_reading_id;

  -- 10. Insert Invoice with Deterministic Invoice Number
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

  -- 11. Audit Log
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

-- Test rpc_submit_meter_reading inside transaction
DO $$
DECLARE
  v_cust_id INT;
  v_res1 JSON;
  v_res2 JSON;
  v_caught BOOLEAN := FALSE;
BEGIN
  INSERT INTO public.customers (subscriber_number, full_name, phone_number, initial_reading, balance)
  VALUES ('TEST-C102', 'مشترك اختبار القراءات', '777111222', 200, 0)
  RETURNING id INTO v_cust_id;

  -- Valid reading 250
  v_res1 := public.rpc_submit_meter_reading(
    p_customer_id := v_cust_id,
    p_reading_value := 250,
    p_collector_name := 'محصل ميدان',
    p_idempotency_key := 'b0000000-0000-0000-0000-000000000001'::UUID,
    p_auto_approve := TRUE,
    p_custom_cycle := '2026-08'
  );

  RAISE NOTICE 'Reading 1 Result: %', v_res1;
  IF (v_res1->>'invoice_number') != 'INV-2026-08-TEST-C102' THEN
    RAISE EXCEPTION 'Invoice number mismatch: %', (v_res1->>'invoice_number');
  END IF;

  -- Monotonic decrease attempt without reset -> must throw
  BEGIN
    PERFORM public.rpc_submit_meter_reading(
      p_customer_id := v_cust_id,
      p_reading_value := 240,
      p_collector_name := 'محصل ميدان',
      p_idempotency_key := 'b0000000-0000-0000-0000-000000000002'::UUID,
      p_auto_approve := TRUE,
      p_custom_cycle := '2026-09',
      p_is_meter_reset := FALSE
    );
  EXCEPTION WHEN check_violation THEN
    v_caught := TRUE;
    RAISE NOTICE 'SUCCESS: rpc_submit_meter_reading properly rejected reading 240 < 250!';
  END;

  IF NOT v_caught THEN
    RAISE EXCEPTION 'FAILED: rpc_submit_meter_reading did not reject monotonic violation!';
  END IF;

  -- Monotonic decrease with is_meter_reset = TRUE -> must succeed
  v_res2 := public.rpc_submit_meter_reading(
    p_customer_id := v_cust_id,
    p_reading_value := 15,
    p_collector_name := 'محصل ميدان',
    p_idempotency_key := 'b0000000-0000-0000-0000-000000000003'::UUID,
    p_auto_approve := TRUE,
    p_custom_cycle := '2026-09',
    p_is_meter_reset := TRUE
  );

  RAISE NOTICE 'Reading 2 (Reset) Result: %', v_res2;
  IF (v_res2->>'invoice_number') != 'INV-2026-09-TEST-C102' THEN
    RAISE EXCEPTION 'Invoice number mismatch on reset: %', (v_res2->>'invoice_number');
  END IF;

  RAISE NOTICE 'SUCCESS: All rpc_submit_meter_reading monotonic & reset & invoice numbering tests PASSED!';
END;
$$;

ROLLBACK;
