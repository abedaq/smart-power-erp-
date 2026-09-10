-- ============================================================================
-- Gate 2.5 Verification: Deterministic Composite Invoice Numbering
-- Pattern: INV-[Cycle]-[SubscriberNumber]
-- File: d:\elctercity\database\tests\test_deterministic_invoicing.sql
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
  v_cid BIGINT;
  v_inv_id BIGINT;
  v_inv RECORD;
  v_test_num TEXT;
BEGIN
  RAISE NOTICE '--- Starting Gate 2.5 Deterministic Invoicing Test Battery ---';

  -- 1. Unit testing the generation function fn_generate_invoice_number
  v_test_num := public.fn_generate_invoice_number('2026-08', 'C101');
  IF v_test_num != 'INV-2026-08-C101' THEN
    RAISE EXCEPTION 'Generation failed: Expected INV-2026-08-C101, got %', v_test_num;
  END IF;

  v_test_num := public.fn_generate_invoice_number('أغسطس - 2026', '10023');
  IF v_test_num != 'INV-أغسطس-2026-10023' THEN
    RAISE EXCEPTION 'Arabic cycle generation failed: Expected INV-أغسطس-2026-10023, got %', v_test_num;
  END IF;

  -- Regex check
  IF NOT (v_test_num ~ '^INV-[A-Za-z0-9_ء-ي\-]+-[A-Za-z0-9_\-]+$') THEN
    RAISE EXCEPTION 'Regex check violation for %', v_test_num;
  END IF;
  RAISE NOTICE 'Function fn_generate_invoice_number validated across ASCII and Arabic UTF-8 cycles.';

  -- 2. Trigger auto-generation test on table INSERT
  INSERT INTO public.customers (subscriber_number, full_name, phone_number, initial_reading, status)
  VALUES ('SUB-7788', 'مشترك اختبار الترقيم', '770000025', 0.00, 'Active')
  RETURNING id INTO v_cid;

  -- Insert invoice WITHOUT providing invoice_number
  INSERT INTO public.invoices (
    customer_id, billing_cycle, previous_reading, current_reading, consumption,
    kwh_price_snapshot, fixed_fee_snapshot, arrears, total_due, total_amount,
    paid_amount, remaining_amount, due_date, approval_status, status
  ) VALUES (
    v_cid, '2026-08', 0.00, 50.00, 50.00,
    1000.00, 0.00, 0.00, 50000.00, 50000.00,
    0.00, 50000.00, '2026-08-10', 'APPROVED', 'Unpaid'
  ) RETURNING id INTO v_inv_id;

  SELECT * INTO v_inv FROM public.invoices WHERE id = v_inv_id;

  IF v_inv.invoice_number != 'INV-2026-08-SUB-7788' THEN
    RAISE EXCEPTION 'Trigger failed to auto-set invoice_number. Expected INV-2026-08-SUB-7788, got %', v_inv.invoice_number;
  END IF;
  RAISE NOTICE 'Auto-generation trigger correctly populated invoice_number: %', v_inv.invoice_number;

  -- 3. Duplicate Prevention Test (UNIQUE constraint)
  BEGIN
    INSERT INTO public.invoices (
      customer_id, invoice_number, billing_cycle, previous_reading, current_reading, consumption,
      kwh_price_snapshot, fixed_fee_snapshot, arrears, total_due, total_amount,
      paid_amount, remaining_amount, due_date, approval_status, status
    ) VALUES (
      v_cid, 'INV-2026-08-SUB-7788', '2026-08', 50.00, 100.00, 50.00,
      1000.00, 0.00, 0.00, 50000.00, 50000.00,
      0.00, 50000.00, '2026-08-10', 'APPROVED', 'Unpaid'
    );
    RAISE EXCEPTION 'CRITICAL: Duplicate invoice number was permitted!';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'Duplicate invoice_number was strictly rejected by UNIQUE constraint.';
  END;

  RAISE NOTICE '=======================================================';
  RAISE NOTICE 'GATE 2.5 VERIFICATION: PASS';
  RAISE NOTICE '=======================================================';
END;
$$;

ROLLBACK;
