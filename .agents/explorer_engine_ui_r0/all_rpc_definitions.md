# PostgreSQL RPC Function Definitions

## rpc_approve_all_pending
```sql
CREATE OR REPLACE FUNCTION public.rpc_approve_all_pending()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user_role TEXT;
  v_reading RECORD;
  v_payment RECORD;
  v_invoice RECORD;
  v_customer RECORD;
  v_readings_count INT := 0;
  v_payments_count INT := 0;
BEGIN
  IF auth.role() IS DISTINCT FROM 'authenticated' AND auth.role() IS NOT NULL THEN
    RAISE EXCEPTION 'Authentication required to bulk approve transactions';
  END IF;

  IF auth.role() = 'authenticated' THEN
    v_user_role := public.current_user_role();
    IF v_user_role != 'ADMIN' THEN
      RAISE EXCEPTION 'Only Administrators can bulk-approve transactions';
    END IF;
  END IF;

  -- 1. Bulk Approve Readings
  FOR v_reading IN 
    SELECT * FROM public.meter_readings WHERE approval_status = 'PENDING' FOR UPDATE
  LOOP
    UPDATE public.meter_readings SET approval_status = 'APPROVED' WHERE id = v_reading.id;
    
    SELECT * INTO v_invoice FROM public.invoices WHERE reading_id = v_reading.id LIMIT 1;
    SELECT * INTO v_customer FROM public.customers WHERE id = v_reading.customer_id;

    INSERT INTO public.audit_logs (
      action, entity, entity_id, details
    ) VALUES (
      'READING_APPROVE_RPC', 'MeterReading', v_reading.id::TEXT,
      'اعتماد قراءة عداد تلقائي (جماعي) للمشترك: ' || COALESCE(v_customer.full_name, '-') || ' (فاتورة رقم #' || COALESCE(v_invoice.id::TEXT, '-') || ')'
    );

    v_readings_count := v_readings_count + 1;
  END LOOP;

  -- 2. Bulk Approve Payments
  FOR v_payment IN 
    SELECT * FROM public.payments WHERE approval_status = 'PENDING' FOR UPDATE
  LOOP
    UPDATE public.payments SET approval_status = 'APPROVED' WHERE id = v_payment.id;

    SELECT * INTO v_customer FROM public.customers WHERE id = v_payment.customer_id;

    INSERT INTO public.audit_logs (
      action, entity, entity_id, details
    ) VALUES (
      'PAYMENT_APPROVE_RPC', 'Payment', v_payment.receipt_number,
      'اعتماد سند سداد تلقائي (جماعي) للمشترك: ' || COALESCE(v_customer.full_name, '-') || ' (سند رقم [' || v_payment.receipt_number || '])'
    );

    v_payments_count := v_payments_count + 1;
  END LOOP;

  RETURN json_build_object(
    'success', true,
    'message', 'تم اعتماد ' || v_readings_count || ' قراءة و ' || v_payments_count || ' سند سداد بنجاح!',
    'readings_approved', v_readings_count,
    'payments_approved', v_payments_count
  );
END;
$function$

```

## rpc_approve_meter_reading
```sql
CREATE OR REPLACE FUNCTION public.rpc_approve_meter_reading(p_reading_id integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user_role TEXT;
  v_reading RECORD;
  v_invoice RECORD;
  v_customer RECORD;
BEGIN
  IF auth.role() IS DISTINCT FROM 'authenticated' AND auth.role() IS NOT NULL THEN
    RAISE EXCEPTION 'Authentication required to approve readings';
  END IF;

  IF auth.role() = 'authenticated' THEN
    v_user_role := public.current_user_role();
    IF v_user_role != 'ADMIN' THEN
      RAISE EXCEPTION 'Only Administrators can approve transactions';
    END IF;
  END IF;

  SELECT * INTO v_reading FROM public.meter_readings WHERE id = p_reading_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reading not found';
  END IF;

  IF v_reading.approval_status = 'APPROVED' THEN
    RETURN json_build_object('success', true, 'message', 'Reading is already approved');
  END IF;

  IF v_reading.approval_status NOT IN ('PENDING', 'PENDING_REVIEW') THEN
    RAISE EXCEPTION 'Reading status must be PENDING to approve';
  END IF;

  UPDATE public.meter_readings SET approval_status = 'APPROVED' WHERE id = p_reading_id;
  UPDATE public.invoices SET approval_status = 'APPROVED', status = 'Unpaid' WHERE reading_id = p_reading_id AND status = 'Pending_Approval';

  SELECT * INTO v_invoice FROM public.invoices WHERE reading_id = p_reading_id LIMIT 1;
  SELECT * INTO v_customer FROM public.customers WHERE id = v_reading.customer_id;
  
  INSERT INTO public.audit_logs (
    action, entity, entity_id, details
  ) VALUES (
    'READING_APPROVE_RPC', 'MeterReading', p_reading_id::TEXT,
    'اعتماد قراءة عداد عبر RPC للمشترك: ' || COALESCE(v_customer.full_name, '-') || ' (فاتورة رقم #' || COALESCE(v_invoice.id::TEXT, '-') || ')'
  );

  RETURN json_build_object('success', true, 'message', 'Reading approved successfully');
END;
$function$

```

## rpc_approve_payment
```sql
CREATE OR REPLACE FUNCTION public.rpc_approve_payment(p_payment_id integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user_role TEXT;
  v_payment RECORD;
  v_customer RECORD;
BEGIN
  IF auth.role() IS DISTINCT FROM 'authenticated' AND auth.role() IS NOT NULL THEN
    RAISE EXCEPTION 'Authentication required to approve payments';
  END IF;

  IF auth.role() = 'authenticated' THEN
    v_user_role := public.current_user_role();
    IF v_user_role != 'ADMIN' THEN
      RAISE EXCEPTION 'Only Administrators can approve transactions';
    END IF;
  END IF;

  SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment not found';
  END IF;

  IF v_payment.approval_status = 'APPROVED' THEN
    RETURN json_build_object('success', true, 'message', 'Payment is already approved');
  END IF;

  IF v_payment.approval_status NOT IN ('PENDING', 'PENDING_REVIEW') THEN
    RAISE EXCEPTION 'Payment status must be PENDING to approve';
  END IF;

  UPDATE public.payments SET approval_status = 'APPROVED' WHERE id = p_payment_id;

  SELECT * INTO v_customer FROM public.customers WHERE id = v_payment.customer_id;
  
  INSERT INTO public.audit_logs (
    action, entity, entity_id, details
  ) VALUES (
    'PAYMENT_APPROVE_RPC', 'Payment', v_payment.receipt_number,
    'اعتماد سند سداد عبر RPC للمشترك: ' || COALESCE(v_customer.full_name, '-') || ' (سند رقم [' || v_payment.receipt_number || '])'
  );

  RETURN json_build_object('success', true, 'message', 'Payment approved successfully');
END;
$function$

```

## rpc_create_user
```sql
CREATE OR REPLACE FUNCTION public.rpc_create_user(p_username text, p_full_name text, p_password text, p_role text DEFAULT 'CASHIER'::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_username TEXT := TRIM(COALESCE(p_username, ''));
  v_name TEXT := TRIM(COALESCE(p_full_name, ''));
  v_role TEXT := UPPER(TRIM(COALESCE(p_role, 'CASHIER')));
  v_user_id INT;
BEGIN
  IF auth.role() IS DISTINCT FROM 'authenticated' AND auth.role() IS NOT NULL THEN
    RAISE EXCEPTION 'Authentication required to create users';
  END IF;
  IF auth.role() = 'authenticated' AND public.current_user_role() != 'ADMIN' THEN
    RAISE EXCEPTION 'Only Administrators can create users';
  END IF;
  IF v_username = '' OR length(v_username) < 3 THEN
    RAISE EXCEPTION 'Username must contain at least 3 characters';
  END IF;
  IF v_name = '' OR length(v_name) < 3 THEN
    RAISE EXCEPTION 'Full name must contain at least 3 characters';
  END IF;
  IF p_password IS NULL OR length(p_password) < 12 THEN
    RAISE EXCEPTION 'Password must contain at least 12 characters';
  END IF;
  IF v_role NOT IN ('ADMIN', 'ACCOUNTANT', 'CASHIER', 'COLLECTOR') THEN
    RAISE EXCEPTION 'Invalid user role';
  END IF;
  IF EXISTS (SELECT 1 FROM public.users WHERE username = v_username) THEN
    RAISE EXCEPTION 'Username already exists';
  END IF;

  INSERT INTO public.users (username, full_name, password_hash, role, is_active)
  VALUES (v_username, v_name, extensions.crypt(p_password, extensions.gen_salt('bf', 12)), v_role, true)
  RETURNING id INTO v_user_id;

  INSERT INTO public.audit_logs (action, entity, entity_id, details)
  VALUES ('CREATE_USER_RPC', 'User', v_user_id::TEXT,
          'إنشاء مستخدم من RPC: ' || v_username || ' بدور ' || v_role);

  RETURN json_build_object('success', true, 'user_id', v_user_id, 'username', v_username,
                           'full_name', v_name, 'role', v_role, 'is_active', true);
END;
$function$

```

## rpc_reject_meter_reading
```sql
CREATE OR REPLACE FUNCTION public.rpc_reject_meter_reading(p_reading_id integer, p_rejection_reason text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user_role TEXT;
  v_reading RECORD;
  v_invoice RECORD;
  v_customer RECORD;
BEGIN
  IF auth.role() IS DISTINCT FROM 'authenticated' AND auth.role() IS NOT NULL THEN
    RAISE EXCEPTION 'Authentication required to reject readings';
  END IF;

  IF auth.role() = 'authenticated' THEN
    v_user_role := public.current_user_role();
    IF v_user_role != 'ADMIN' THEN
      RAISE EXCEPTION 'Only Administrators can reject transactions';
    END IF;
  END IF;

  SELECT * INTO v_reading FROM public.meter_readings WHERE id = p_reading_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reading not found';
  END IF;

  IF v_reading.approval_status = 'REJECTED' THEN
    RETURN json_build_object('success', true, 'message', 'Reading is already rejected');
  END IF;

  IF v_reading.approval_status NOT IN ('PENDING', 'PENDING_REVIEW') THEN
    RAISE EXCEPTION 'Reading status must be PENDING to reject';
  END IF;

  UPDATE public.meter_readings 
  SET approval_status = 'REJECTED', rejection_reason = p_rejection_reason 
  WHERE id = p_reading_id;

  SELECT * INTO v_invoice FROM public.invoices WHERE reading_id = p_reading_id LIMIT 1;
  IF FOUND THEN
    -- Preserve original amounts for audit/history. Void invoices are excluded from active finance queries.
    UPDATE public.invoices
    SET approval_status = 'REJECTED', status = 'Void'
    WHERE id = v_invoice.id;
  END IF;

  SELECT * INTO v_customer FROM public.customers WHERE id = v_reading.customer_id;
  INSERT INTO public.audit_logs (
    action, entity, entity_id, details
  ) VALUES (
    'READING_REJECT_RPC', 'MeterReading', p_reading_id::TEXT,
    'رفض قراءة عداد عبر RPC للمشترك: ' || COALESCE(v_customer.full_name, '-') || ' (سبب الرفض: ' || p_rejection_reason || ')'
  );

  RETURN json_build_object('success', true, 'message', 'Reading rejected and invoice voided successfully');
END;
$function$

```

## rpc_reject_payment
```sql
CREATE OR REPLACE FUNCTION public.rpc_reject_payment(p_payment_id integer, p_rejection_reason text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user_role TEXT;
  v_payment RECORD;
  v_allocation RECORD;
  v_invoice RECORD;
  v_customer RECORD;
  v_reverted_paid NUMERIC;
  v_reverted_remaining NUMERIC;
  v_reverted_status TEXT;
BEGIN
  IF auth.role() IS DISTINCT FROM 'authenticated' AND auth.role() IS NOT NULL THEN
    RAISE EXCEPTION 'Authentication required to reject payments';
  END IF;

  IF auth.role() = 'authenticated' THEN
    v_user_role := public.current_user_role();
    IF v_user_role != 'ADMIN' THEN
      RAISE EXCEPTION 'Only Administrators can reject transactions';
    END IF;
  END IF;

  SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment not found';
  END IF;

  IF v_payment.approval_status = 'REJECTED' THEN
    RETURN json_build_object('success', true, 'message', 'Payment is already rejected');
  END IF;

  IF v_payment.approval_status NOT IN ('PENDING', 'PENDING_REVIEW') THEN
    RAISE EXCEPTION 'Payment status must be PENDING to reject';
  END IF;

  -- 1. Revert Allocations on each Invoice
  FOR v_allocation IN 
    SELECT * FROM public.payment_allocations 
    WHERE payment_id = p_payment_id AND is_reversed = false 
    FOR UPDATE
  LOOP
    SELECT * INTO v_invoice FROM public.invoices WHERE id = v_allocation.invoice_id FOR UPDATE;
    IF FOUND THEN
      v_reverted_paid := GREATEST(0::numeric, v_invoice.paid_amount - v_allocation.amount_allocated);
      v_reverted_remaining := v_invoice.total_due - v_reverted_paid;
      v_reverted_status := CASE WHEN v_reverted_paid <= 0 THEN 'Unpaid' ELSE 'Partially_Paid' END;

      UPDATE public.invoices 
      SET paid_amount = v_reverted_paid, remaining_amount = v_reverted_remaining, status = v_reverted_status
      WHERE id = v_invoice.id;
    END IF;
  END LOOP;

  -- 2. Soft-Reverse Payment Allocations (HIGH-02: Preserve history)
  UPDATE public.payment_allocations 
  SET is_reversed = true, reversed_at = CURRENT_TIMESTAMP, reversal_reason = p_rejection_reason 
  WHERE payment_id = p_payment_id;

  -- 3. Cancel any Customer Credit generated from this payment (HIGH-04)
  UPDATE public.customer_credits 
  SET status = 'CANCELLED', remaining_amount = 0 
  WHERE payment_id = p_payment_id;

  -- 4. Mark Payment as REJECTED
  UPDATE public.payments 
  SET approval_status = 'REJECTED', rejection_reason = p_rejection_reason 
  WHERE id = p_payment_id;

  -- 5. Audit Log
  SELECT * INTO v_customer FROM public.customers WHERE id = v_payment.customer_id;
  INSERT INTO public.audit_logs (
    action, entity, entity_id, details
  ) VALUES (
    'PAYMENT_REJECT_RPC', 'Payment', v_payment.receipt_number,
    'رفض سند سداد وإلغاء التوزيع المحاسبي عبر RPC للمشترك: ' || COALESCE(v_customer.full_name, '-') || ' (سند رقم [' || v_payment.receipt_number || '], سبب الرفض: ' || p_rejection_reason || ')'
  );

  RETURN json_build_object('success', true, 'message', 'Payment rejected and allocations reversed successfully');
END;
$function$

```

## rpc_reset_user_password
```sql
CREATE OR REPLACE FUNCTION public.rpc_reset_user_password(p_user_id integer, p_new_password text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user RECORD;
BEGIN
  IF auth.role() IS DISTINCT FROM 'authenticated' AND auth.role() IS NOT NULL THEN
    RAISE EXCEPTION 'Authentication required to reset passwords';
  END IF;
  IF auth.role() = 'authenticated' AND public.current_user_role() != 'ADMIN' THEN
    RAISE EXCEPTION 'Only Administrators can reset passwords';
  END IF;
  IF p_new_password IS NULL OR length(p_new_password) < 8 THEN
    RAISE EXCEPTION 'Password must contain at least 8 characters';
  END IF;

  SELECT * INTO v_user FROM public.users WHERE id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'User not found'; END IF;

  UPDATE public.users
  SET password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf', 10))
  WHERE id = p_user_id;

  IF v_user.supabase_uid IS NOT NULL THEN
    UPDATE auth.users
    SET encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf', 10)),
        updated_at = CURRENT_TIMESTAMP
    WHERE id = v_user.supabase_uid;
  END IF;

  INSERT INTO public.audit_logs (action, entity, entity_id, details)
  VALUES ('RESET_USER_PASSWORD_RPC', 'User', p_user_id::TEXT,
          'إعادة تعيين كلمة مرور مستخدم بواسطة المدير: ' || COALESCE(v_user.full_name, v_user.username, '-'));

  RETURN json_build_object('success', true, 'user_id', p_user_id);
END;
$function$

```

## rpc_submit_meter_reading
```sql
CREATE OR REPLACE FUNCTION public.rpc_submit_meter_reading(p_customer_id integer, p_reading_value numeric, p_collector_name text, p_idempotency_key uuid, p_auto_approve boolean DEFAULT false, p_reading_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP, p_custom_cycle text DEFAULT NULL::text, p_actor_user_id integer DEFAULT NULL::integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    DECLARE
      v_user_role TEXT;
      v_previous_reading NUMERIC;
      v_consumption NUMERIC;
      v_arrears NUMERIC;
      v_kwh_price NUMERIC;
      v_fixed_fee NUMERIC;
      v_consumption_value NUMERIC;
      v_total_due NUMERIC;
      v_grace_days INT;
      v_due_date DATE;
      v_billing_cycle TEXT;
      v_last_cycle TEXT;
      v_reading_id INT;
      v_invoice_id INT;
      v_existing_json JSON;
      v_settings RECORD;
      v_customer RECORD;
      v_plan RECORD;
      v_approval_status TEXT;
      v_invoice_status TEXT;
    BEGIN
      -- 1. Idempotency Check
      SELECT row_to_json(m) INTO v_existing_json FROM public.meter_readings m WHERE m.client_mutation_id = p_idempotency_key;
      IF FOUND THEN
        RETURN json_build_object('success', true, 'is_duplicate', true, 'data', v_existing_json);
      END IF;

      -- 2. Lock Customer Row & Retrieve Details
      SELECT * INTO v_customer FROM public.customers WHERE id = p_customer_id FOR UPDATE;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Customer not found';
      END IF;

      -- 3. Get Previous Reading (Excluding REJECTED)
      SELECT reading_value INTO v_previous_reading FROM public.meter_readings
      WHERE customer_id = p_customer_id AND approval_status != 'REJECTED'
      ORDER BY reading_date DESC, id DESC LIMIT 1;
      
      IF NOT FOUND THEN
        v_previous_reading := v_customer.initial_reading;
      END IF;

      -- Validate New Reading
      IF p_reading_value < v_previous_reading THEN
        RAISE EXCEPTION 'New reading value (%) cannot be less than previous reading (%)', p_reading_value, v_previous_reading;
      END IF;

      v_consumption := p_reading_value - v_previous_reading;

      v_approval_status := CASE WHEN p_auto_approve THEN 'APPROVED' ELSE 'PENDING' END;
      v_invoice_status := CASE WHEN p_auto_approve THEN 'Unpaid' ELSE 'Pending_Approval' END;

      -- 4. Retrieve Subscription Plan & Settings
      SELECT * INTO v_plan FROM public.subscription_plans WHERE id = v_customer.subscription_plan_id;
      SELECT * INTO v_settings FROM public.system_settings LIMIT 1;

      v_kwh_price := COALESCE(v_plan.kwh_price, v_settings.default_kwh_price, 1200::numeric);
      v_fixed_fee := COALESCE(v_plan.fixed_fee, v_settings.default_fixed_fee, 500::numeric);
      v_grace_days := COALESCE(v_plan.grace_period_days, v_settings.max_overdue_days, 7);

      -- 5. Calculate Arrears
      SELECT COALESCE(SUM(remaining_amount), 0) INTO v_arrears FROM public.invoices
      WHERE customer_id = p_customer_id AND status IN ('Unpaid', 'Partially_Paid');

      v_consumption_value := v_consumption * v_kwh_price;
      v_total_due := v_consumption_value + v_fixed_fee + v_arrears;

      v_due_date := (p_reading_date + (v_grace_days || ' days')::INTERVAL)::DATE;

      -- 6. Calculate Next Billing Cycle String
      IF p_custom_cycle IS NOT NULL AND TRIM(p_custom_cycle) != '' THEN
        v_billing_cycle := TRIM(p_custom_cycle);
      ELSE
        SELECT billing_cycle INTO v_last_cycle FROM public.invoices
        WHERE customer_id = p_customer_id AND approval_status != 'REJECTED' AND billing_cycle IS NOT NULL AND billing_cycle != 'رصيد افتتاحي'
        ORDER BY id DESC LIMIT 1;

        IF v_last_cycle IS NULL OR TRIM(v_last_cycle) = '' THEN
          SELECT billing_cycle INTO v_last_cycle FROM public.invoices
          WHERE approval_status != 'REJECTED' AND billing_cycle IS NOT NULL AND billing_cycle != 'رصيد افتتاحي'
          ORDER BY id DESC LIMIT 1;
        END IF;

        v_billing_cycle := public.fn_get_next_billing_cycle(v_last_cycle);
      END IF;

      -- 7. Insert Meter Reading
      INSERT INTO public.meter_readings (
        customer_id, reading_value, reading_date, collector_name, approval_status, client_mutation_id
      ) VALUES (
        p_customer_id, p_reading_value, p_reading_date, p_collector_name, v_approval_status, p_idempotency_key
      ) RETURNING id INTO v_reading_id;

      -- 8. Insert Invoice
      INSERT INTO public.invoices (
        customer_id, reading_id, previous_reading, current_reading, consumption,
        consumption_value, kwh_price_snapshot, fixed_fee_snapshot, arrears, total_due,
        paid_amount, remaining_amount, billing_cycle, total_amount, due_date, approval_status, status, created_at
      ) VALUES (
        p_customer_id, v_reading_id, v_previous_reading, p_reading_value, v_consumption,
        v_consumption_value, v_kwh_price, v_fixed_fee, v_arrears, v_total_due,
        0, v_total_due, v_billing_cycle, v_total_due, v_due_date, v_approval_status, v_invoice_status, p_reading_date
      ) RETURNING id INTO v_invoice_id;

      -- 9. Log Audit Entry
      INSERT INTO public.audit_logs (
        action, entity, entity_id, details, created_at
      ) VALUES (
        'READING_CREATE_RPC', 'MeterReading', v_reading_id::TEXT,
        'تسجيل قراءة عداد جديدة عبر RPC (' || p_reading_value || ') للمشترك: ' || v_customer.full_name || ' لدورة: ' || v_billing_cycle || ' (فاتورة رقم #' || v_invoice_id || ') بواسطة: ' || p_collector_name,
        p_reading_date
      );

      RETURN json_build_object(
        'success', true,
        'is_duplicate', false,
        'reading_id', v_reading_id,
        'invoice_id', v_invoice_id,
        'consumption', v_consumption,
        'total_due', v_total_due,
        'billing_cycle', v_billing_cycle,
        'approval_status', v_approval_status,
        'invoice_status', v_invoice_status,
        'auto_approved', v_approval_status = 'APPROVED'
      );
    END;
    $function$

```

## rpc_submit_payment
```sql
CREATE OR REPLACE FUNCTION public.rpc_submit_payment(p_customer_id integer, p_amount_paid numeric, p_payment_method text, p_collector_name text, p_idempotency_key uuid, p_notes text DEFAULT NULL::text, p_payment_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP, p_invoice_id integer DEFAULT NULL::integer, p_actor_user_id integer DEFAULT NULL::integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    DECLARE
      v_user_role TEXT;
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
      v_updated_balance NUMERIC;
      v_allocations JSONB := '[]'::jsonb;
      v_credit_amount NUMERIC := 0;
    BEGIN
      -- 1. Idempotency Check
      SELECT row_to_json(pm) INTO v_existing_json FROM public.payments pm WHERE pm.client_mutation_id = p_idempotency_key;
      IF FOUND THEN
        RETURN json_build_object('success', true, 'is_duplicate', true, 'data', v_existing_json);
      END IF;

      -- 2. Lock Customer & Validate
      SELECT * INTO v_customer FROM public.customers WHERE id = p_customer_id FOR UPDATE;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Customer not found';
      END IF;

      IF p_amount_paid <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than zero';
      END IF;

      -- 3. Concurrency-Safe Receipt Number Generation
      v_current_year := EXTRACT(YEAR FROM p_payment_date)::INT;
      
      INSERT INTO public.payment_receipt_counters (year, last_value)
      VALUES (v_current_year, 1)
      ON CONFLICT (year) DO UPDATE 
      SET last_value = public.payment_receipt_counters.last_value + 1
      RETURNING last_value INTO v_next_val;

      v_receipt_number := 'REC-' || v_current_year || '-' || LPAD(v_next_val::TEXT, 4, '0');

      -- 4. Create Main Payment Record
      INSERT INTO public.payments (
        customer_id, invoice_id, receipt_number, payment_method, amount_paid, payment_date,
        accountant_name, approval_status, notes, client_mutation_id
      ) VALUES (
        p_customer_id, p_invoice_id, v_receipt_number, p_payment_method, p_amount_paid, p_payment_date,
        p_collector_name, 'PENDING', p_notes, p_idempotency_key
      ) RETURNING id INTO v_payment_id;

      -- 5. Lock and fetch unpaid/partially paid invoices (FIFO order by due_date)
      v_remaining_to_distribute := p_amount_paid;

      FOR v_invoice IN 
        SELECT * FROM public.invoices 
        WHERE customer_id = p_customer_id
          AND status IN ('Unpaid', 'Partially_Paid')
          AND (p_invoice_id IS NULL OR id = p_invoice_id)
        ORDER BY due_date ASC, id ASC
        FOR UPDATE
      LOOP
        IF v_remaining_to_distribute <= 0 THEN
          EXIT;
        END IF;

        v_allocated_amount := LEAST(v_remaining_to_distribute, v_invoice.remaining_amount);

        v_new_paid := v_invoice.paid_amount + v_allocated_amount;
        v_new_remaining := v_invoice.total_due - v_new_paid;
        v_new_status := CASE WHEN v_new_remaining <= 0 THEN 'Paid' ELSE 'Partially_Paid' END;

        -- Update Invoice
        UPDATE public.invoices 
        SET paid_amount = v_new_paid, remaining_amount = v_new_remaining, status = v_new_status
        WHERE id = v_invoice.id;

        -- Create Payment Allocation
        INSERT INTO public.payment_allocations (
          payment_id, invoice_id, amount_allocated, is_reversed, created_at
        ) VALUES (
          v_payment_id, v_invoice.id, v_allocated_amount, false, p_payment_date
        ) RETURNING id INTO v_allocation_id;

        -- Append to allocations JSON list
        v_allocations := v_allocations || jsonb_build_object(
          'invoice_id', v_invoice.id,
          'amount_allocated', v_allocated_amount,
          'billing_cycle', v_invoice.billing_cycle
        );

        v_remaining_to_distribute := v_remaining_to_distribute - v_allocated_amount;
      END LOOP;

      -- 6. Handle Overpayment as Customer Credit Ledger
      IF v_remaining_to_distribute > 0 THEN
        v_credit_amount := v_remaining_to_distribute;
        INSERT INTO public.customer_credits (
          customer_id, payment_id, amount, remaining_amount, status, created_at
        ) VALUES (
          p_customer_id, v_payment_id, v_credit_amount, v_credit_amount, 'AVAILABLE', p_payment_date
        );
      END IF;

      -- 7. Calculate Customer Remaining Overall Balance
      SELECT COALESCE(SUM(remaining_amount), 0) INTO v_updated_balance FROM public.invoices
      WHERE customer_id = p_customer_id AND status IN ('Unpaid', 'Partially_Paid');

      -- 8. Create Audit Log Entry
      INSERT INTO public.audit_logs (
        action, entity, entity_id, details, created_at
      ) VALUES (
        'PAYMENT_CREATE_RPC', 'Payment', v_receipt_number,
        'تحصيل مبلغ ' || p_amount_paid || ' ر.ي عبر RPC من المشترك: ' || v_customer.full_name || ' (سند رقم [' || v_receipt_number || ']' || 
        CASE WHEN v_credit_amount > 0 THEN ', رصيد دائن زائد: ' || v_credit_amount || ' ر.ي' ELSE '' END || 
        ') بواسطة: ' || p_collector_name,
        p_payment_date
      );

      RETURN json_build_object(
        'success', true,
        'is_duplicate', false,
        'payment_id', v_payment_id,
        'receipt_number', v_receipt_number,
        'updated_balance', v_updated_balance,
        'credit_balance', v_credit_amount,
        'allocations', v_allocations
      );
    END;
    $function$

```

## rpc_update_meter_reading
```sql
CREATE OR REPLACE FUNCTION public.rpc_update_meter_reading(p_reading_id integer, p_reading_value numeric)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_reading RECORD;
  v_invoice RECORD;
  v_customer RECORD;
  v_consumption NUMERIC;
  v_consumption_value NUMERIC;
  v_total_due NUMERIC;
  v_remaining_amount NUMERIC;
  v_status TEXT;
BEGIN
  IF auth.role() IS DISTINCT FROM 'authenticated' AND auth.role() IS NOT NULL THEN
    RAISE EXCEPTION 'Authentication required to update readings';
  END IF;
  IF auth.role() = 'authenticated' AND public.current_user_role() != 'ADMIN' THEN
    RAISE EXCEPTION 'Only Administrators can update readings';
  END IF;
  IF p_reading_value IS NULL OR p_reading_value < 0 THEN
    RAISE EXCEPTION 'Reading value must be non-negative';
  END IF;

  SELECT * INTO v_reading FROM public.meter_readings WHERE id = p_reading_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Reading not found'; END IF;
  IF v_reading.approval_status = 'REJECTED' THEN RAISE EXCEPTION 'Rejected readings cannot be edited'; END IF;

  SELECT * INTO v_invoice FROM public.invoices WHERE reading_id = p_reading_id LIMIT 1 FOR UPDATE;
  IF FOUND THEN
    IF p_reading_value < v_invoice.previous_reading THEN
      RAISE EXCEPTION 'New reading cannot be lower than previous reading';
    END IF;
    v_consumption := p_reading_value - v_invoice.previous_reading;
    v_consumption_value := ROUND(v_consumption * v_invoice.kwh_price_snapshot, 2);
    v_total_due := ROUND(v_consumption_value + v_invoice.fixed_fee_snapshot + v_invoice.arrears, 2);
    v_remaining_amount := GREATEST(0, ROUND(v_total_due - v_invoice.paid_amount, 2));
    v_status := CASE WHEN v_remaining_amount <= 0 THEN 'Paid' WHEN v_invoice.paid_amount > 0 THEN 'Partially_Paid' ELSE 'Unpaid' END;
    UPDATE public.invoices
    SET current_reading = p_reading_value,
        consumption = v_consumption,
        consumption_value = v_consumption_value,
        total_due = v_total_due,
        total_amount = v_total_due,
        remaining_amount = v_remaining_amount,
        status = v_status
    WHERE id = v_invoice.id;
  ELSE
    v_consumption := p_reading_value;
  END IF;

  UPDATE public.meter_readings SET reading_value = p_reading_value WHERE id = p_reading_id;
  SELECT * INTO v_customer FROM public.customers WHERE id = v_reading.customer_id;
  INSERT INTO public.audit_logs (action, entity, entity_id, details)
  VALUES ('READING_UPDATE_RPC', 'MeterReading', p_reading_id::TEXT,
          'تعديل قراءة مؤكدة عبر الهاتف من ' || v_reading.reading_value || ' إلى ' || p_reading_value || ' للمشترك: ' || COALESCE(v_customer.full_name, '-'));

  RETURN json_build_object('success', true, 'reading_id', p_reading_id, 'invoice_id', v_invoice.id, 'reading_value', p_reading_value, 'consumption', v_consumption);
END;
$function$

```

## rpc_update_payment_amount
```sql
CREATE OR REPLACE FUNCTION public.rpc_update_payment_amount(p_payment_id integer, p_amount_paid numeric)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_payment RECORD;
  v_allocation RECORD;
  v_invoice RECORD;
  v_customer RECORD;
  v_previous_amount NUMERIC;
  v_remaining_to_distribute NUMERIC;
  v_allocated_amount NUMERIC;
  v_new_paid NUMERIC;
  v_new_remaining NUMERIC;
  v_new_status TEXT;
BEGIN
  IF auth.role() IS DISTINCT FROM 'authenticated' AND auth.role() IS NOT NULL THEN
    RAISE EXCEPTION 'Authentication required to update payments';
  END IF;
  IF auth.role() = 'authenticated' AND public.current_user_role() != 'ADMIN' THEN
    RAISE EXCEPTION 'Only Administrators can update payments';
  END IF;
  IF p_amount_paid IS NULL OR p_amount_paid <= 0 THEN
    RAISE EXCEPTION 'Payment amount must be greater than zero';
  END IF;

  SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found'; END IF;
  IF v_payment.approval_status = 'REJECTED' THEN RAISE EXCEPTION 'Rejected payments cannot be edited'; END IF;
  v_previous_amount := v_payment.amount_paid;

  FOR v_allocation IN SELECT * FROM public.payment_allocations WHERE payment_id = p_payment_id AND is_reversed = false FOR UPDATE LOOP
    SELECT * INTO v_invoice FROM public.invoices WHERE id = v_allocation.invoice_id FOR UPDATE;
    IF FOUND THEN
      v_new_paid := GREATEST(0, v_invoice.paid_amount - v_allocation.amount_allocated);
      v_new_remaining := GREATEST(0, v_invoice.total_due - v_new_paid);
      v_new_status := CASE WHEN v_new_remaining <= 0 THEN 'Paid' WHEN v_new_paid > 0 THEN 'Partially_Paid' ELSE 'Unpaid' END;
      UPDATE public.invoices SET paid_amount = v_new_paid, remaining_amount = v_new_remaining, status = v_new_status WHERE id = v_invoice.id;
    END IF;
    UPDATE public.payment_allocations
    SET is_reversed = true, reversed_at = CURRENT_TIMESTAMP, reversal_reason = 'تم عكس التخصيص بسبب تعديل مبلغ السداد'
    WHERE id = v_allocation.id;
  END LOOP;

  UPDATE public.customer_credits SET status = 'CANCELLED', remaining_amount = 0 WHERE payment_id = p_payment_id AND status = 'AVAILABLE';
  v_remaining_to_distribute := p_amount_paid;

  FOR v_invoice IN
    SELECT * FROM public.invoices
    WHERE customer_id = v_payment.customer_id AND status IN ('Unpaid', 'Partially_Paid')
    ORDER BY due_date ASC, id ASC FOR UPDATE
  LOOP
    EXIT WHEN v_remaining_to_distribute <= 0;
    IF v_invoice.remaining_amount <= 0 THEN CONTINUE; END IF;
    v_allocated_amount := LEAST(v_remaining_to_distribute, v_invoice.remaining_amount);
    v_new_paid := v_invoice.paid_amount + v_allocated_amount;
    v_new_remaining := GREATEST(0, v_invoice.total_due - v_new_paid);
    v_new_status := CASE WHEN v_new_remaining <= 0 THEN 'Paid' ELSE 'Partially_Paid' END;
    UPDATE public.invoices SET paid_amount = v_new_paid, remaining_amount = v_new_remaining, status = v_new_status WHERE id = v_invoice.id;
    INSERT INTO public.payment_allocations (payment_id, invoice_id, amount_allocated, is_reversed, created_at)
    VALUES (p_payment_id, v_invoice.id, v_allocated_amount, false, CURRENT_TIMESTAMP);
    v_remaining_to_distribute := v_remaining_to_distribute - v_allocated_amount;
  END LOOP;

  IF v_remaining_to_distribute > 0 THEN
    INSERT INTO public.customer_credits (customer_id, payment_id, amount, remaining_amount, status)
    VALUES (v_payment.customer_id, p_payment_id, v_remaining_to_distribute, v_remaining_to_distribute, 'AVAILABLE');
  END IF;

  UPDATE public.payments SET amount_paid = p_amount_paid WHERE id = p_payment_id;
  SELECT * INTO v_customer FROM public.customers WHERE id = v_payment.customer_id;
  INSERT INTO public.audit_logs (action, entity, entity_id, details)
  VALUES ('PAYMENT_AMOUNT_UPDATE_RPC', 'Payment', COALESCE(v_payment.receipt_number, p_payment_id::TEXT),
          'تعديل مبلغ السداد عبر الهاتف من ' || v_previous_amount || ' إلى ' || p_amount_paid || ' للمشترك: ' || COALESCE(v_customer.full_name, '-'));

  RETURN json_build_object('success', true, 'payment_id', p_payment_id, 'amount_paid', p_amount_paid, 'credit_balance', GREATEST(0, v_remaining_to_distribute));
END;
$function$

```

## rpc_update_user_profile
```sql
CREATE OR REPLACE FUNCTION public.rpc_update_user_profile(p_user_id integer, p_full_name text, p_role text, p_is_active boolean DEFAULT NULL::boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user RECORD;
  v_role TEXT := UPPER(TRIM(COALESCE(p_role, '')));
  v_name TEXT := TRIM(COALESCE(p_full_name, ''));
BEGIN
  IF auth.role() IS DISTINCT FROM 'authenticated' AND auth.role() IS NOT NULL THEN
    RAISE EXCEPTION 'Authentication required to update users';
  END IF;
  IF auth.role() = 'authenticated' AND public.current_user_role() != 'ADMIN' THEN
    RAISE EXCEPTION 'Only Administrators can update users';
  END IF;
  IF v_name = '' OR length(v_name) < 3 THEN
    RAISE EXCEPTION 'Full name must contain at least 3 characters';
  END IF;
  IF v_role NOT IN ('ADMIN', 'ACCOUNTANT', 'CASHIER', 'COLLECTOR') THEN
    RAISE EXCEPTION 'Invalid user role';
  END IF;

  SELECT * INTO v_user FROM public.users WHERE id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'User not found'; END IF;

  UPDATE public.users
  SET full_name = v_name,
      role = v_role,
      is_active = COALESCE(p_is_active, is_active)
  WHERE id = p_user_id;

  INSERT INTO public.audit_logs (action, entity, entity_id, details)
  VALUES ('UPDATE_USER_PROFILE_RPC', 'User', p_user_id::TEXT,
          'تعديل ملف مستخدم من ' || COALESCE(v_user.full_name, '-') || ' إلى ' || v_name || ' والدور إلى ' || v_role);

  RETURN json_build_object('success', true, 'user_id', p_user_id, 'full_name', v_name, 'role', v_role,
                           'is_active', COALESCE(p_is_active, v_user.is_active));
END;
$function$

```

