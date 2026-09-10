-- ============================================================================
-- Gate 2.6 Verification: Retroactive Cascade Recalculation Engine (T -> N)
-- Zero Rounding Errors & Strict Ascending Pessimistic Locking
-- File: d:\elctercity\database\tests\test_retroactive_recalc.sql
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
  v_cust_id    BIGINT;
  v_plan_id    BIGINT;
  v_inv1_id    BIGINT;
  v_inv2_id    BIGINT;
  v_inv3_id    BIGINT;
  v_read1_id   BIGINT;
  v_read2_id   BIGINT;
  v_read3_id   BIGINT;
  v_res        JSONB;
  
  -- Results inspection for Cycle 1
  v_c1_curr    NUMERIC(12,2);
  v_c1_cons    NUMERIC(12,2);
  v_c1_cost    NUMERIC(12,2);
  v_c1_lost    NUMERIC(12,2);
  v_c1_due     NUMERIC(12,2);
  v_c1_rem     NUMERIC(12,2);
  
  -- Results inspection for Cycle 2
  v_c2_prev    NUMERIC(12,2);
  v_c2_curr    NUMERIC(12,2);
  v_c2_cons    NUMERIC(12,2);
  v_c2_cost    NUMERIC(12,2);
  v_c2_lost    NUMERIC(12,2);
  v_c2_arrears NUMERIC(12,2);
  v_c2_due     NUMERIC(12,2);
  v_c2_rem     NUMERIC(12,2);
  
  -- Results inspection for Cycle 3
  v_c3_prev    NUMERIC(12,2);
  v_c3_curr    NUMERIC(12,2);
  v_c3_cons    NUMERIC(12,2);
  v_c3_arrears NUMERIC(12,2);
  v_c3_due     NUMERIC(12,2);
  v_c3_rem     NUMERIC(12,2);
BEGIN
  RAISE NOTICE '--- Starting Gate 2.6 Cascade Recalculation Test Battery ---';

  -- 1. Setup subscription plan: kwh_price = 100, fixed_fee = 500
  INSERT INTO public.subscription_plans (plan_name, kwh_price, fixed_fee, grace_period_days)
  VALUES ('باقة فحص تتابعي', 100.00, 500.00, 10)
  RETURNING id INTO v_plan_id;

  -- 2. Setup customer: initial_reading = 100.00
  INSERT INTO public.customers (subscriber_number, full_name, phone_number, subscription_plan_id, initial_reading, status)
  VALUES ('SUB-TEST-CASCADE-01', 'مشترك اختبار الحساب التتابعي', '770000001', v_plan_id, 100.00, 'Active')
  RETURNING id INTO v_cust_id;

  -- 3. Create Cycle 1 (أغسطس-1): Reading 100 -> 150 (consumption = 50), paid 3000
  -- Cost = 50 * 100 = 5000 + fee 500 = 5500. Rem = 5500 - 3000 = 2500
  INSERT INTO public.meter_readings (customer_id, reading_value, reading_date, collector_name, approval_status, lost_units)
  VALUES (v_cust_id, 150.00, '2026-08-01 10:00:00+03', 'المحصل', 'APPROVED', 0.00)
  RETURNING id INTO v_read1_id;

  INSERT INTO public.invoices (
    customer_id, reading_id, previous_reading, current_reading, consumption, lost_units,
    consumption_value, kwh_price_snapshot, fixed_fee_snapshot, arrears, total_due,
    paid_amount, remaining_amount, billing_cycle, total_amount, due_date, approval_status, status, created_at
  ) VALUES (
    v_cust_id, v_read1_id, 100.00, 150.00, 50.00, 0.00,
    5000.00, 100.00, 500.00, 0.00, 5500.00,
    3000.00, 2500.00, 'أغسطس-1-2026', 5500.00, '2026-08-10', 'APPROVED', 'Partially_Paid', '2026-08-01 10:00:00+03'
  ) RETURNING id INTO v_inv1_id;

  -- 4. Create Cycle 2 (أغسطس-2): Reading 150 -> 220 (consumption = 70), lost_units = 5 (cost = 500)
  -- Arrears = 2500. Due = 7000 + 500 + 500 + 2500 = 10500. Paid 8000. Rem = 2500
  INSERT INTO public.meter_readings (customer_id, reading_value, reading_date, collector_name, approval_status, lost_units)
  VALUES (v_cust_id, 220.00, '2026-08-15 10:00:00+03', 'المحصل', 'APPROVED', 5.00)
  RETURNING id INTO v_read2_id;

  INSERT INTO public.invoices (
    customer_id, reading_id, previous_reading, current_reading, consumption, lost_units,
    consumption_value, kwh_price_snapshot, fixed_fee_snapshot, arrears, total_due,
    paid_amount, remaining_amount, billing_cycle, total_amount, due_date, approval_status, status, created_at
  ) VALUES (
    v_cust_id, v_read2_id, 150.00, 220.00, 70.00, 5.00,
    7000.00, 100.00, 500.00, 2500.00, 10500.00,
    8000.00, 2500.00, 'أغسطس-2-2026', 10500.00, '2026-08-25', 'APPROVED', 'Partially_Paid', '2026-08-15 10:00:00+03'
  ) RETURNING id INTO v_inv2_id;

  -- 5. Create Cycle 3 (سبتمبر-1): Reading 220 -> 310 (consumption = 90), lost_units = 0
  -- Arrears = 2500. Due = 9000 + 500 + 2500 = 12000. Paid 10000. Rem = 2000
  INSERT INTO public.meter_readings (customer_id, reading_value, reading_date, collector_name, approval_status, lost_units)
  VALUES (v_cust_id, 310.00, '2026-09-01 10:00:00+03', 'المحصل', 'APPROVED', 0.00)
  RETURNING id INTO v_read3_id;

  INSERT INTO public.invoices (
    customer_id, reading_id, previous_reading, current_reading, consumption, lost_units,
    consumption_value, kwh_price_snapshot, fixed_fee_snapshot, arrears, total_due,
    paid_amount, remaining_amount, billing_cycle, total_amount, due_date, approval_status, status, created_at
  ) VALUES (
    v_cust_id, v_read3_id, 220.00, 310.00, 90.00, 0.00,
    9000.00, 100.00, 500.00, 2500.00, 12000.00,
    10000.00, 2000.00, 'سبتمبر-1-2026', 12000.00, '2026-09-10', 'APPROVED', 'Partially_Paid', '2026-09-01 10:00:00+03'
  ) RETURNING id INTO v_inv3_id;

  -- --------------------------------------------------------------------------
  -- Execute Critical Retroactive Modification on Cycle 1 (T1):
  -- Update current_reading: 150.00 -> 170.00 (+20 kWh consumption)
  -- Add lost_units = 2.00 (+200 YER)
  -- --------------------------------------------------------------------------
  RAISE NOTICE 'Executing retroactive patch on Cycle 1 (T1)...';
  v_res := public.rpc_recalculate_customer_cascade(
    p_customer_id        => v_cust_id,
    p_trigger_invoice_id => v_inv1_id,
    p_updates            => '{"current_reading": 170.00, "lost_units": 2.00}'::jsonb,
    p_actor_user_id      => 1
  );

  -- --------------------------------------------------------------------------
  -- Verification for Cycle 1:
  -- Consumption = 170 - 100 = 70 (Cost = 7000)
  -- Lost units = 2 * 100 = 200
  -- Fee = 500, Arrears = 0
  -- Total Due = 7000 + 200 + 500 = 7700.00
  -- Rem = 7700 - 3000 = 4700.00
  -- --------------------------------------------------------------------------
  SELECT current_reading, consumption, consumption_value, lost_units, total_due, remaining_amount
  INTO v_c1_curr, v_c1_cons, v_c1_cost, v_c1_lost, v_c1_due, v_c1_rem
  FROM public.invoices WHERE id = v_inv1_id;

  IF v_c1_curr != 170.00 OR v_c1_cons != 70.00 OR v_c1_due != 7700.00 OR v_c1_rem != 4700.00 THEN
    RAISE EXCEPTION 'Cycle 1 verification failed: due=%, rem=%', v_c1_due, v_c1_rem;
  END IF;

  -- --------------------------------------------------------------------------
  -- Verification for Cycle 2:
  -- Previous reading cascaded = 170.00
  -- Current reading = 220.00 -> Consumption = 50 (Cost = 5000)
  -- Lost units = 5 * 100 = 500
  -- Fee = 500
  -- Arrears cascaded = 4700.00
  -- Total Due = 5000 + 500 + 500 + 4700 = 10700.00
  -- Rem = 10700 - 8000 = 2700.00
  -- --------------------------------------------------------------------------
  SELECT previous_reading, current_reading, consumption, consumption_value, lost_units, arrears, total_due, remaining_amount
  INTO v_c2_prev, v_c2_curr, v_c2_cons, v_c2_cost, v_c2_lost, v_c2_arrears, v_c2_due, v_c2_rem
  FROM public.invoices WHERE id = v_inv2_id;

  IF v_c2_prev != 170.00 OR v_c2_cons != 50.00 OR v_c2_arrears != 4700.00 OR v_c2_due != 10700.00 OR v_c2_rem != 2700.00 THEN
    RAISE EXCEPTION 'Cycle 2 verification failed: prev=%, arrears=%, due=%, rem=%',
      v_c2_prev, v_c2_arrears, v_c2_due, v_c2_rem;
  END IF;

  -- --------------------------------------------------------------------------
  -- Verification for Cycle 3:
  -- Previous reading = 220.00, Current = 310.00 -> Consumption = 90 (Cost = 9000)
  -- Lost units = 0, Fee = 500
  -- Arrears cascaded = 2700.00
  -- Total Due = 9000 + 0 + 500 + 2700 = 12200.00
  -- Rem = 12200 - 10000 = 2200.00
  -- --------------------------------------------------------------------------
  SELECT previous_reading, current_reading, consumption, arrears, total_due, remaining_amount
  INTO v_c3_prev, v_c3_curr, v_c3_cons, v_c3_arrears, v_c3_due, v_c3_rem
  FROM public.invoices WHERE id = v_inv3_id;

  IF v_c3_prev != 220.00 OR v_c3_cons != 90.00 OR v_c3_arrears != 2700.00 OR v_c3_due != 12200.00 OR v_c3_rem != 2200.00 THEN
    RAISE EXCEPTION 'Cycle 3 verification failed: arrears=%, due=%, rem=%',
      v_c3_arrears, v_c3_due, v_c3_rem;
  END IF;

  -- --------------------------------------------------------------------------
  -- Non-Monotonic Guard test via Cascade:
  -- Attempting 240 > 220 in Cycle 1 without reset -> Must reject
  -- --------------------------------------------------------------------------
  BEGIN
    PERFORM public.rpc_recalculate_customer_cascade(
      p_customer_id        => v_cust_id,
      p_trigger_invoice_id => v_inv1_id,
      p_updates            => '{"current_reading": 240.00}'::jsonb,
      p_is_meter_reset     => FALSE
    );
    RAISE EXCEPTION 'FAILED: Non-monotonic cascade update was permitted!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM ~ 'يتعارض مع القراءة المسجلة للدورة اللاحقة' THEN
      RAISE NOTICE 'Downstream monotonic violation successfully intercepted: %', SQLERRM;
    ELSE
      RAISE EXCEPTION 'Unexpected exception: %', SQLERRM;
    END IF;
  END;

  RAISE NOTICE '=======================================================';
  RAISE NOTICE 'TEST RESULT: RECALCULATION_CASCADE_VERIFIED_PASS';
  RAISE NOTICE '=======================================================';
END;
$$;

ROLLBACK;
