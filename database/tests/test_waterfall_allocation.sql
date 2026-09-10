-- ============================================================================
-- Gate 2.4 Verification: Atomic FIFO Waterfall Payment Allocation & Credit Ledger
-- File: d:\elctercity\database\tests\test_waterfall_allocation.sql
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
  v_cid BIGINT;
  v_i1 BIGINT;
  v_i2 BIGINT;
  v_res1 JSON;
  v_res2 JSON;
  v_inv1 RECORD;
  v_inv2 RECORD;
  v_credit RECORD;
  v_cust RECORD;
  v_alloc_count INT;
BEGIN
  RAISE NOTICE '--- Starting Gate 2.4 FIFO Waterfall Allocation Test Battery ---';

  -- 1. Create Test Customer
  INSERT INTO public.customers (subscriber_number, full_name, phone_number, initial_reading, balance, status)
  VALUES ('SUB-GATE24-01', 'مشترك اختبار التوزيع المائي', '770000024', 0.00, 0.00, 'Active')
  RETURNING id INTO v_cid;

  -- 2. Invoice 1 (Older cycle): 10,000 YER due on 2026-08-10
  INSERT INTO public.invoices (
    customer_id, invoice_number, billing_cycle, previous_reading, current_reading, consumption,
    kwh_price_snapshot, fixed_fee_snapshot, arrears, total_due, total_amount, paid_amount, remaining_amount,
    due_date, approval_status, status
  ) VALUES (
    v_cid, 'INV-2026-08-SUB-GATE24-01', '2026-08', 0.00, 10.00, 10.00,
    1000.00, 0.00, 0.00, 10000.00, 10000.00, 0.00, 10000.00,
    '2026-08-10', 'APPROVED', 'Unpaid'
  ) RETURNING id INTO v_i1;

  -- 3. Invoice 2 (Newer cycle): 15,000 YER due on 2026-09-10
  INSERT INTO public.invoices (
    customer_id, invoice_number, billing_cycle, previous_reading, current_reading, consumption,
    kwh_price_snapshot, fixed_fee_snapshot, arrears, total_due, total_amount, paid_amount, remaining_amount,
    due_date, approval_status, status
  ) VALUES (
    v_cid, 'INV-2026-09-SUB-GATE24-01', '2026-09', 10.00, 25.00, 15.00,
    1000.00, 0.00, 10000.00, 15000.00, 15000.00, 0.00, 15000.00,
    '2026-09-10', 'APPROVED', 'Unpaid'
  ) RETURNING id INTO v_i2;

  RAISE NOTICE 'Invoices created: Inv1=10,000 YER, Inv2=15,000 YER (Total debt: 25,000 YER)';

  -- 4. Payment 1: Partial payment of 4,000 YER (Must settle oldest invoice 1 partially)
  v_res1 := public.rpc_submit_payment(
    p_customer_id     => v_cid,
    p_amount_paid     => 4000.00,
    p_payment_method  => 'CASH',
    p_collector_name  => 'أمين الصندوق',
    p_idempotency_key => gen_random_uuid(),
    p_payment_date    => '2026-08-15 10:00:00+03'
  );

  SELECT * INTO v_inv1 FROM public.invoices WHERE id = v_i1;
  IF v_inv1.paid_amount != 4000.00 OR v_inv1.remaining_amount != 6000.00 OR v_inv1.status != 'Partially_Paid' THEN
    RAISE EXCEPTION 'Partial allocation assertion failed on Inv 1: paid=%, rem=%, status=%',
      v_inv1.paid_amount, v_inv1.remaining_amount, v_inv1.status;
  END IF;
  RAISE NOTICE 'Payment 1 (4,000 YER): Inv 1 partially paid (Remaining: 6,000 YER). PASS.';

  -- 5. Payment 2: Overpayment of 26,000 YER
  -- Needs 6,000 to finish Inv 1, then 15,000 to finish Inv 2, leaving 5,000 excess credit
  v_res2 := public.rpc_submit_payment(
    p_customer_id     => v_cid,
    p_amount_paid     => 26000.00,
    p_payment_method  => 'BANK_TRANSFER',
    p_collector_name  => 'أمين الصندوق',
    p_idempotency_key => gen_random_uuid(),
    p_payment_date    => '2026-09-15 11:00:00+03'
  );

  -- Verify Invoice 1 state: Completely Paid
  SELECT * INTO v_inv1 FROM public.invoices WHERE id = v_i1;
  IF v_inv1.paid_amount != 10000.00 OR v_inv1.remaining_amount != 0.00 OR v_inv1.status != 'Paid' THEN
    RAISE EXCEPTION 'Final allocation assertion failed on Inv 1: paid=%, rem=%, status=%',
      v_inv1.paid_amount, v_inv1.remaining_amount, v_inv1.status;
  END IF;

  -- Verify Invoice 2 state: Completely Paid
  SELECT * INTO v_inv2 FROM public.invoices WHERE id = v_i2;
  IF v_inv2.paid_amount != 15000.00 OR v_inv2.remaining_amount != 0.00 OR v_inv2.status != 'Paid' THEN
    RAISE EXCEPTION 'Final allocation assertion failed on Inv 2: paid=%, rem=%, status=%',
      v_inv2.paid_amount, v_inv2.remaining_amount, v_inv2.status;
  END IF;

  -- Verify Overpayment Credit in customer_credits
  SELECT * INTO v_credit FROM public.customer_credits WHERE customer_id = v_cid AND status = 'AVAILABLE';
  IF NOT FOUND OR v_credit.amount != 5000.00 OR v_credit.remaining_amount != 5000.00 THEN
    RAISE EXCEPTION 'Credit record assertion failed: amount=%, remaining=%',
      v_credit.amount, v_credit.remaining_amount;
  END IF;

  -- Verify Customer Master Balance
  SELECT * INTO v_cust FROM public.customers WHERE id = v_cid;
  IF v_cust.balance != 5000.00 OR v_cust.total_due != 0.00 THEN
    RAISE EXCEPTION 'Customer balance assertion failed: balance=%, total_due=%',
      v_cust.balance, v_cust.total_due;
  END IF;

  -- Verify Allocations Count
  SELECT count(*) INTO v_alloc_count
  FROM public.payment_allocations pa
  JOIN public.payments p ON pa.payment_id = p.id
  WHERE p.customer_id = v_cid;

  IF v_alloc_count != 3 THEN
    RAISE EXCEPTION 'Expected 3 allocations (1 in payment 1, 2 in payment 2), found %', v_alloc_count;
  END IF;

  RAISE NOTICE 'Payment 2 (26,000 YER): Inv 1 fully settled (6,000 allocated), Inv 2 fully settled (15,000 allocated).';
  RAISE NOTICE 'Excess amount (5,000 YER) deposited into customer_credits wallet (balance: 5,000 YER).';
  RAISE NOTICE 'Remaining customer debt: 0.00 YER.';
  RAISE NOTICE '=======================================================';
  RAISE NOTICE 'GATE 2.4 VERIFICATION: PASS';
  RAISE NOTICE '=======================================================';
END;
$$;

ROLLBACK;
