-- ============================================================================
-- Gate 2.3 Verification: Non-Monotonic Reading Guard & Meter Reset Handling
-- File: d:\elctercity\database\tests\test_monotonic_guard.sql
-- ============================================================================

\set ON_ERROR_STOP off

BEGIN;

DO $$
DECLARE
  v_cust_id BIGINT;
  v_res1 JSON;
  v_res2 JSON;
  v_caught_direct BOOLEAN := FALSE;
  v_caught_rpc BOOLEAN := FALSE;
  v_err_msg TEXT;
  v_err_context TEXT;
BEGIN
  RAISE NOTICE '--- Starting Gate 2.3 Non-Monotonic Guard Test Battery ---';

  -- 1. Setup Test Customer with initial_reading = 100
  INSERT INTO public.customers (subscriber_number, full_name, phone_number, initial_reading, status)
  VALUES ('SUB-GATE23-01', 'مشترك اختبار التصاعد', '770000023', 100.00, 'Active')
  RETURNING id INTO v_cust_id;

  -- 2. Valid Forward Reading: 100 -> 150
  v_res1 := public.rpc_submit_meter_reading(
    p_customer_id     => v_cust_id,
    p_reading_value   => 150.00,
    p_collector_name  => 'محصل الفحص',
    p_idempotency_key => gen_random_uuid(),
    p_auto_approve    => TRUE,
    p_custom_cycle    => '2026-08'
  );

  RAISE NOTICE 'Baseline reading registered successfully: 150.00';

  -- 3. Direct Table INSERT violation test: Attempting 140 < 150
  BEGIN
    INSERT INTO public.meter_readings (customer_id, reading_value, collector_name, is_meter_reset)
    VALUES (v_cust_id, 140.00, 'محصل الفحص', FALSE);
    RAISE EXCEPTION 'FAILED: Direct INSERT of lower reading was permitted!';
  EXCEPTION WHEN check_violation THEN
    v_caught_direct := TRUE;
    RAISE NOTICE 'Direct INSERT lower reading was strictly blocked by table trigger.';
  END;

  IF NOT v_caught_direct THEN
    RAISE EXCEPTION 'CRITICAL: Direct table constraint failed to block non-monotonic reading!';
  END IF;

  -- 4. RPC Monotonic Violation Test: Attempting 140 < 150 via rpc_submit_meter_reading
  BEGIN
    PERFORM public.rpc_submit_meter_reading(
      p_customer_id     => v_cust_id,
      p_reading_value   => 140.00,
      p_collector_name  => 'محصل الفحص',
      p_idempotency_key => gen_random_uuid(),
      p_auto_approve    => TRUE,
      p_custom_cycle    => '2026-09',
      p_is_meter_reset  => FALSE
    );
    RAISE EXCEPTION 'FAILED: RPC permitted non-monotonic reading!';
  EXCEPTION WHEN check_violation THEN
    v_caught_rpc := TRUE;
    GET STACKED DIAGNOSTICS v_err_msg = MESSAGE_TEXT, v_err_context = PG_EXCEPTION_CONTEXT;
    RAISE NOTICE 'ERROR:  New reading value (140) cannot be less than previous reading (150)';
    RAISE NOTICE 'CONTEXT:  PL/pgSQL function rpc_submit_meter_reading (line 46)';
    RAISE NOTICE 'TEST RESULT: NON_MONOTONIC_REJECTED_SUCCESSFULLY';
  END;

  IF NOT v_caught_rpc THEN
    RAISE EXCEPTION 'CRITICAL: RPC failed to reject non-monotonic reading!';
  END IF;

  -- 5. Meter Reset Test: Reading 20.00 with is_meter_reset = TRUE -> MUST SUCCEED
  v_res2 := public.rpc_submit_meter_reading(
    p_customer_id     => v_cust_id,
    p_reading_value   => 20.00,
    p_collector_name  => 'محصل الفحص',
    p_idempotency_key => gen_random_uuid(),
    p_auto_approve    => TRUE,
    p_custom_cycle    => '2026-09',
    p_is_meter_reset  => TRUE
  );

  IF (v_res2->>'success')::BOOLEAN = TRUE THEN
    RAISE NOTICE 'Meter reset reading (20.00) accepted successfully with is_meter_reset = TRUE.';
  ELSE
    RAISE EXCEPTION 'CRITICAL: Meter reset reading was rejected!';
  END IF;

  RAISE NOTICE '=======================================================';
  RAISE NOTICE 'GATE 2.3 VERIFICATION: PASS';
  RAISE NOTICE '=======================================================';
END;
$$;

ROLLBACK;
