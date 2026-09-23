-- ============================================================================
-- SmartPower ERP: Zero-Conflict Atomic Station Payload Synchronization RPC
-- Run this in Supabase SQL Editor to enable flawless Outbox Payload sync
-- ============================================================================

CREATE OR REPLACE FUNCTION public.sync_station_payload(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_plans JSONB := COALESCE(p_payload->'subscription_plans', '[]'::jsonb);
    v_customers JSONB := COALESCE(p_payload->'customers', '[]'::jsonb);
    v_readings JSONB := COALESCE(p_payload->'meter_readings', '[]'::jsonb);
    v_invoices JSONB := COALESCE(p_payload->'invoices', '[]'::jsonb);
    v_payments JSONB := COALESCE(p_payload->'payments', '[]'::jsonb);
    v_allocations JSONB := COALESCE(p_payload->'payment_allocations', '[]'::jsonb);

    v_elem JSONB;
    v_customer_id BIGINT;
    v_plan_id BIGINT;
    v_reading_id BIGINT;
    v_invoice_id BIGINT;
    v_payment_id BIGINT;

    v_synced_plans INT := 0;
    v_synced_customers INT := 0;
    v_synced_readings INT := 0;
    v_synced_invoices INT := 0;
    v_synced_payments INT := 0;
    v_synced_allocations INT := 0;
BEGIN
    -- 1. Sync Subscription Plans
    FOR v_elem IN SELECT * FROM jsonb_array_elements(v_plans) LOOP
        INSERT INTO public.subscription_plans (
            plan_name, kwh_price, fixed_fee, grace_period_days, description, is_active, created_at
        ) VALUES (
            (v_elem->>'plan_name'),
            COALESCE((v_elem->>'kwh_price')::NUMERIC, 0),
            COALESCE((v_elem->>'fixed_fee')::NUMERIC, 0),
            COALESCE((v_elem->>'grace_period_days')::INT, 10),
            (v_elem->>'description'),
            COALESCE((v_elem->>'is_active')::BOOLEAN, true),
            COALESCE((v_elem->>'created_at')::TIMESTAMPTZ, NOW())
        )
        ON CONFLICT (plan_name) DO UPDATE SET
            kwh_price = EXCLUDED.kwh_price,
            fixed_fee = EXCLUDED.fixed_fee,
            grace_period_days = EXCLUDED.grace_period_days,
            description = EXCLUDED.description,
            is_active = EXCLUDED.is_active;
        v_synced_plans := v_synced_plans + 1;
    END LOOP;

    -- 2. Sync Customers by Natural Key (subscriber_number)
    FOR v_elem IN SELECT * FROM jsonb_array_elements(v_customers) LOOP
        v_plan_id := NULL;
        IF (v_elem->>'plan_name') IS NOT NULL AND (v_elem->>'plan_name') != '' THEN
            SELECT id INTO v_plan_id FROM public.subscription_plans WHERE plan_name = (v_elem->>'plan_name') LIMIT 1;
        END IF;

        INSERT INTO public.customers (
            subscriber_number, full_name, phone_number, id_card_url, address, meter_number,
            route_number, subscription_plan_id, initial_reading, start_cycle, status, sort_order, is_deleted, created_at
        ) VALUES (
            (v_elem->>'subscriber_number'),
            (v_elem->>'full_name'),
            (v_elem->>'phone_number'),
            (v_elem->>'id_card_url'),
            (v_elem->>'address'),
            (v_elem->>'meter_number'),
            (v_elem->>'route_number'),
            v_plan_id,
            COALESCE((v_elem->>'initial_reading')::NUMERIC, 0),
            (v_elem->>'start_cycle'),
            COALESCE((v_elem->>'status'), 'Active'),
            COALESCE((v_elem->>'sort_order')::INT, 0),
            COALESCE((v_elem->>'is_deleted')::BOOLEAN, false),
            COALESCE((v_elem->>'created_at')::TIMESTAMPTZ, NOW())
        )
        ON CONFLICT (subscriber_number) DO UPDATE SET
            full_name = EXCLUDED.full_name,
            phone_number = EXCLUDED.phone_number,
            id_card_url = EXCLUDED.id_card_url,
            address = EXCLUDED.address,
            meter_number = EXCLUDED.meter_number,
            route_number = EXCLUDED.route_number,
            subscription_plan_id = COALESCE(EXCLUDED.subscription_plan_id, customers.subscription_plan_id),
            initial_reading = EXCLUDED.initial_reading,
            start_cycle = EXCLUDED.start_cycle,
            status = EXCLUDED.status,
            sort_order = EXCLUDED.sort_order,
            is_deleted = EXCLUDED.is_deleted;
        v_synced_customers := v_synced_customers + 1;
    END LOOP;

    -- 3. Sync Meter Readings (resolving customer_id via subscriber_number)
    FOR v_elem IN SELECT * FROM jsonb_array_elements(v_readings) LOOP
        SELECT id INTO v_customer_id FROM public.customers WHERE subscriber_number = (v_elem->>'subscriber_number') LIMIT 1;
        IF v_customer_id IS NOT NULL THEN
            IF (v_elem->>'client_mutation_id') IS NOT NULL AND (v_elem->>'client_mutation_id') != '' THEN
                INSERT INTO public.meter_readings (
                    customer_id, reading_value, reading_date, collector_name, approval_status, client_mutation_id, whatsapp_sent, created_at
                ) VALUES (
                    v_customer_id,
                    COALESCE((v_elem->>'reading_value')::NUMERIC, 0),
                    COALESCE((v_elem->>'reading_date')::TIMESTAMPTZ, NOW()),
                    (v_elem->>'collector_name'),
                    COALESCE((v_elem->>'approval_status'), 'APPROVED'),
                    (v_elem->>'client_mutation_id'),
                    COALESCE((v_elem->>'whatsapp_sent')::BOOLEAN, false),
                    COALESCE((v_elem->>'created_at')::TIMESTAMPTZ, NOW())
                )
                ON CONFLICT (client_mutation_id) DO UPDATE SET
                    reading_value = EXCLUDED.reading_value,
                    reading_date = EXCLUDED.reading_date,
                    collector_name = EXCLUDED.collector_name,
                    approval_status = EXCLUDED.approval_status,
                    whatsapp_sent = EXCLUDED.whatsapp_sent;
            ELSE
                INSERT INTO public.meter_readings (
                    customer_id, reading_value, reading_date, collector_name, approval_status, whatsapp_sent, created_at
                ) VALUES (
                    v_customer_id,
                    COALESCE((v_elem->>'reading_value')::NUMERIC, 0),
                    COALESCE((v_elem->>'reading_date')::TIMESTAMPTZ, NOW()),
                    (v_elem->>'collector_name'),
                    COALESCE((v_elem->>'approval_status'), 'APPROVED'),
                    COALESCE((v_elem->>'whatsapp_sent')::BOOLEAN, false),
                    COALESCE((v_elem->>'created_at')::TIMESTAMPTZ, NOW())
                );
            END IF;
            v_synced_readings := v_synced_readings + 1;
        END IF;
    END LOOP;

    -- 4. Sync Invoices (resolving customer_id via subscriber_number & matching invoice_number)
    FOR v_elem IN SELECT * FROM jsonb_array_elements(v_invoices) LOOP
        SELECT id INTO v_customer_id FROM public.customers WHERE subscriber_number = (v_elem->>'subscriber_number') LIMIT 1;
        IF v_customer_id IS NOT NULL AND (v_elem->>'invoice_number') IS NOT NULL THEN
            INSERT INTO public.invoices (
                customer_id, invoice_number, previous_reading, current_reading, consumption,
                consumption_value, kwh_price_snapshot, fixed_fee_snapshot, arrears, total_due,
                paid_amount, remaining_amount, billing_cycle, total_amount, due_date, approval_status, status, created_at
            ) VALUES (
                v_customer_id,
                (v_elem->>'invoice_number'),
                COALESCE((v_elem->>'previous_reading')::NUMERIC, 0),
                COALESCE((v_elem->>'current_reading')::NUMERIC, 0),
                COALESCE((v_elem->>'consumption')::NUMERIC, 0),
                COALESCE((v_elem->>'consumption_value')::NUMERIC, 0),
                COALESCE((v_elem->>'kwh_price_snapshot')::NUMERIC, 0),
                COALESCE((v_elem->>'fixed_fee_snapshot')::NUMERIC, 0),
                COALESCE((v_elem->>'arrears')::NUMERIC, 0),
                COALESCE((v_elem->>'total_due')::NUMERIC, 0),
                COALESCE((v_elem->>'paid_amount')::NUMERIC, 0),
                COALESCE((v_elem->>'remaining_amount')::NUMERIC, 0),
                (v_elem->>'billing_cycle'),
                COALESCE((v_elem->>'total_amount')::NUMERIC, 0),
                COALESCE((v_elem->>'due_date')::DATE, CURRENT_DATE),
                COALESCE((v_elem->>'approval_status'), 'APPROVED'),
                COALESCE((v_elem->>'status'), 'Unpaid'),
                COALESCE((v_elem->>'created_at')::TIMESTAMPTZ, NOW())
            )
            ON CONFLICT (invoice_number) DO UPDATE SET
                previous_reading = EXCLUDED.previous_reading,
                current_reading = EXCLUDED.current_reading,
                consumption = EXCLUDED.consumption,
                consumption_value = EXCLUDED.consumption_value,
                arrears = EXCLUDED.arrears,
                total_due = EXCLUDED.total_due,
                paid_amount = EXCLUDED.paid_amount,
                remaining_amount = EXCLUDED.remaining_amount,
                billing_cycle = EXCLUDED.billing_cycle,
                total_amount = EXCLUDED.total_amount,
                approval_status = EXCLUDED.approval_status,
                status = EXCLUDED.status;
            v_synced_invoices := v_synced_invoices + 1;
        END IF;
    END LOOP;

    -- 5. Sync Payments (resolving customer_id & matching receipt_number)
    FOR v_elem IN SELECT * FROM jsonb_array_elements(v_payments) LOOP
        SELECT id INTO v_customer_id FROM public.customers WHERE subscriber_number = (v_elem->>'subscriber_number') LIMIT 1;
        IF v_customer_id IS NOT NULL AND (v_elem->>'receipt_number') IS NOT NULL THEN
            INSERT INTO public.payments (
                customer_id, receipt_number, payment_method, amount_paid, payment_date,
                accountant_name, approval_status, notes, client_mutation_id, whatsapp_sent, created_at
            ) VALUES (
                v_customer_id,
                (v_elem->>'receipt_number'),
                COALESCE((v_elem->>'payment_method'), 'CASH'),
                COALESCE((v_elem->>'amount_paid')::NUMERIC, 0),
                COALESCE((v_elem->>'payment_date')::TIMESTAMPTZ, NOW()),
                (v_elem->>'accountant_name'),
                COALESCE((v_elem->>'approval_status'), 'APPROVED'),
                (v_elem->>'notes'),
                (v_elem->>'client_mutation_id'),
                COALESCE((v_elem->>'whatsapp_sent')::BOOLEAN, false),
                COALESCE((v_elem->>'created_at')::TIMESTAMPTZ, NOW())
            )
            ON CONFLICT (receipt_number) DO UPDATE SET
                payment_method = EXCLUDED.payment_method,
                amount_paid = EXCLUDED.amount_paid,
                payment_date = EXCLUDED.payment_date,
                accountant_name = EXCLUDED.accountant_name,
                approval_status = EXCLUDED.approval_status,
                notes = EXCLUDED.notes,
                whatsapp_sent = EXCLUDED.whatsapp_sent;
            v_synced_payments := v_synced_payments + 1;
        END IF;
    END LOOP;

    -- 6. Sync Payment Allocations (resolving receipt_number & invoice_number)
    FOR v_elem IN SELECT * FROM jsonb_array_elements(v_allocations) LOOP
        SELECT id INTO v_payment_id FROM public.payments WHERE receipt_number = (v_elem->>'receipt_number') LIMIT 1;
        SELECT id INTO v_invoice_id FROM public.invoices WHERE invoice_number = (v_elem->>'invoice_number') LIMIT 1;

        IF v_payment_id IS NOT NULL AND v_invoice_id IS NOT NULL THEN
            INSERT INTO public.payment_allocations (
                payment_id, invoice_id, amount_allocated, is_reversed, reversed_at, reversal_reason, created_at
            ) VALUES (
                v_payment_id,
                v_invoice_id,
                COALESCE((v_elem->>'amount_allocated')::NUMERIC, 0),
                COALESCE((v_elem->>'is_reversed')::BOOLEAN, false),
                (v_elem->>'reversed_at')::TIMESTAMPTZ,
                (v_elem->>'reversal_reason'),
                COALESCE((v_elem->>'created_at')::TIMESTAMPTZ, NOW())
            )
            ON CONFLICT (payment_id, invoice_id) DO UPDATE SET
                amount_allocated = EXCLUDED.amount_allocated,
                is_reversed = EXCLUDED.is_reversed,
                reversed_at = EXCLUDED.reversed_at,
                reversal_reason = EXCLUDED.reversal_reason;
            v_synced_allocations := v_synced_allocations + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'synced_plans', v_synced_plans,
        'synced_customers', v_synced_customers,
        'synced_readings', v_synced_readings,
        'synced_invoices', v_synced_invoices,
        'synced_payments', v_synced_payments,
        'synced_allocations', v_synced_allocations
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_station_payload(JSONB) TO anon;
GRANT EXECUTE ON FUNCTION public.sync_station_payload(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_station_payload(JSONB) TO service_role;
