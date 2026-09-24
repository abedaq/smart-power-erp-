-- ====================================================================
-- SmartPower ERP: Supabase Cloud Atomic Sync Procedure & Constraints
-- Run this script in Supabase SQL Editor to establish Zero-Conflict Sync
-- ====================================================================

-- 1. Ensure Critical Unique Constraints & Natural Key Indices on Cloud
CREATE UNIQUE INDEX IF NOT EXISTS idx_cloud_sub_plans_name 
ON public.subscription_plans(plan_name);

CREATE UNIQUE INDEX IF NOT EXISTS idx_cloud_customers_sub_num 
ON public.customers(subscriber_number);

CREATE UNIQUE INDEX IF NOT EXISTS idx_cloud_invoices_inv_num 
ON public.invoices(invoice_number);

CREATE UNIQUE INDEX IF NOT EXISTS idx_cloud_payments_receipt_num 
ON public.payments(receipt_number);

-- 2. Atomic Sync RPC Function
CREATE OR REPLACE FUNCTION public.sync_station_payload(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_plans JSONB := COALESCE(p_payload->'subscription_plans', '[]'::jsonb);
    v_customers JSONB := COALESCE(p_payload->'customers', '[]'::jsonb);
    v_readings JSONB := COALESCE(p_payload->'meter_readings', '[]'::jsonb);
    v_invoices JSONB := COALESCE(p_payload->'invoices', '[]'::jsonb);
    v_payments JSONB := COALESCE(p_payload->'payments', '[]'::jsonb);
    v_allocations JSONB := COALESCE(p_payload->'payment_allocations', '[]'::jsonb);
    
    v_item JSONB;
    v_plan_id BIGINT;
    v_customer_id BIGINT;
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
    -- A. Sync Subscription Plans
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_plans)
    LOOP
        INSERT INTO public.subscription_plans (
            plan_name,
            kwh_price,
            fixed_fee,
            grace_period_days,
            description,
            is_active,
            created_at,
            updated_at
        ) VALUES (
            (v_item->>'plan_name')::TEXT,
            COALESCE((v_item->>'kwh_price')::NUMERIC, 0),
            COALESCE((v_item->>'fixed_fee')::NUMERIC, 0),
            COALESCE((v_item->>'grace_period_days')::INT, 10),
            (v_item->>'description')::TEXT,
            COALESCE((v_item->>'is_active')::BOOLEAN, true),
            COALESCE((v_item->>'created_at')::TIMESTAMPTZ, NOW()),
            NOW()
        )
        ON CONFLICT (plan_name) DO UPDATE SET
            kwh_price = EXCLUDED.kwh_price,
            fixed_fee = EXCLUDED.fixed_fee,
            grace_period_days = EXCLUDED.grace_period_days,
            description = EXCLUDED.description,
            is_active = EXCLUDED.is_active,
            updated_at = NOW();

        v_synced_plans := v_synced_plans + 1;
    END LOOP;

    -- B. Sync Customers (Natural Key: subscriber_number)
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_customers)
    LOOP
        -- Resolve cloud plan_id if plan_name is provided
        v_plan_id := NULL;
        IF (v_item->>'plan_name') IS NOT NULL AND (v_item->>'plan_name') != '' THEN
            SELECT id INTO v_plan_id FROM public.subscription_plans WHERE plan_name = (v_item->>'plan_name') LIMIT 1;
        END IF;

        INSERT INTO public.customers (
            subscriber_number,
            full_name,
            phone_number,
            id_card_url,
            address,
            meter_number,
            route_number,
            subscription_plan_id,
            initial_reading,
            start_cycle,
            status,
            sort_order,
            is_deleted,
            created_at,
            updated_at
        ) VALUES (
            (v_item->>'subscriber_number')::TEXT,
            (v_item->>'full_name')::TEXT,
            (v_item->>'phone_number')::TEXT,
            (v_item->>'id_card_url')::TEXT,
            (v_item->>'address')::TEXT,
            (v_item->>'meter_number')::TEXT,
            (v_item->>'route_number')::TEXT,
            v_plan_id,
            COALESCE((v_item->>'initial_reading')::NUMERIC, 0),
            COALESCE((v_item->>'start_cycle')::TEXT, '2026-08-1'),
            COALESCE((v_item->>'status')::TEXT, 'Active'),
            COALESCE((v_item->>'sort_order')::INT, 0),
            COALESCE((v_item->>'is_deleted')::BOOLEAN, false),
            COALESCE((v_item->>'created_at')::TIMESTAMPTZ, NOW()),
            NOW()
        )
        ON CONFLICT (subscriber_number) DO UPDATE SET
            full_name = EXCLUDED.full_name,
            phone_number = EXCLUDED.phone_number,
            id_card_url = COALESCE(EXCLUDED.id_card_url, public.customers.id_card_url),
            address = EXCLUDED.address,
            meter_number = EXCLUDED.meter_number,
            route_number = EXCLUDED.route_number,
            subscription_plan_id = COALESCE(v_plan_id, public.customers.subscription_plan_id),
            initial_reading = EXCLUDED.initial_reading,
            status = EXCLUDED.status,
            is_deleted = EXCLUDED.is_deleted,
            updated_at = NOW();

        v_synced_customers := v_synced_customers + 1;
    END LOOP;

    -- C. Sync Meter Readings (Natural Key: client_mutation_id or subscriber_number + reading_date)
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_readings)
    LOOP
        -- Resolve cloud customer_id
        SELECT id INTO v_customer_id 
        FROM public.customers 
        WHERE subscriber_number = (v_item->>'subscriber_number')
        LIMIT 1;

        IF v_customer_id IS NOT NULL THEN
            IF (v_item->>'client_mutation_id') IS NOT NULL AND (v_item->>'client_mutation_id') != '' THEN
                INSERT INTO public.meter_readings (
                    customer_id,
                    reading_value,
                    reading_date,
                    collector_name,
                    approval_status,
                    client_mutation_id,
                    whatsapp_sent,
                    created_at,
                    updated_at
                ) VALUES (
                    v_customer_id,
                    (v_item->>'reading_value')::NUMERIC,
                    COALESCE((v_item->>'reading_date')::TIMESTAMPTZ, NOW()),
                    COALESCE((v_item->>'collector_name')::TEXT, 'System'),
                    COALESCE((v_item->>'approval_status')::TEXT, 'APPROVED'),
                    (v_item->>'client_mutation_id')::UUID,
                    COALESCE((v_item->>'whatsapp_sent')::BOOLEAN, false),
                    COALESCE((v_item->>'created_at')::TIMESTAMPTZ, NOW()),
                    NOW()
                )
                ON CONFLICT (client_mutation_id) DO UPDATE SET
                    reading_value = EXCLUDED.reading_value,
                    approval_status = EXCLUDED.approval_status,
                    whatsapp_sent = EXCLUDED.whatsapp_sent,
                    updated_at = NOW();
            ELSE
                INSERT INTO public.meter_readings (
                    customer_id,
                    reading_value,
                    reading_date,
                    collector_name,
                    approval_status,
                    whatsapp_sent,
                    created_at,
                    updated_at
                ) VALUES (
                    v_customer_id,
                    (v_item->>'reading_value')::NUMERIC,
                    COALESCE((v_item->>'reading_date')::TIMESTAMPTZ, NOW()),
                    COALESCE((v_item->>'collector_name')::TEXT, 'System'),
                    COALESCE((v_item->>'approval_status')::TEXT, 'APPROVED'),
                    COALESCE((v_item->>'whatsapp_sent')::BOOLEAN, false),
                    COALESCE((v_item->>'created_at')::TIMESTAMPTZ, NOW()),
                    NOW()
                );
            END IF;
            v_synced_readings := v_synced_readings + 1;
        END IF;
    END LOOP;

    -- D. Sync Invoices (Natural Key: invoice_number)
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_invoices)
    LOOP
        SELECT id INTO v_customer_id 
        FROM public.customers 
        WHERE subscriber_number = (v_item->>'subscriber_number')
        LIMIT 1;

        IF v_customer_id IS NOT NULL THEN
            INSERT INTO public.invoices (
                customer_id,
                invoice_number,
                previous_reading,
                current_reading,
                consumption,
                consumption_value,
                kwh_price_snapshot,
                fixed_fee_snapshot,
                arrears,
                total_due,
                paid_amount,
                remaining_amount,
                billing_cycle,
                total_amount,
                due_date,
                approval_status,
                status,
                created_at,
                updated_at
            ) VALUES (
                v_customer_id,
                (v_item->>'invoice_number')::TEXT,
                COALESCE((v_item->>'previous_reading')::NUMERIC, 0),
                COALESCE((v_item->>'current_reading')::NUMERIC, 0),
                COALESCE((v_item->>'consumption')::NUMERIC, 0),
                COALESCE((v_item->>'consumption_value')::NUMERIC, 0),
                COALESCE((v_item->>'kwh_price_snapshot')::NUMERIC, 0),
                COALESCE((v_item->>'fixed_fee_snapshot')::NUMERIC, 0),
                COALESCE((v_item->>'arrears')::NUMERIC, 0),
                COALESCE((v_item->>'total_due')::NUMERIC, 0),
                COALESCE((v_item->>'paid_amount')::NUMERIC, 0),
                COALESCE((v_item->>'remaining_amount')::NUMERIC, 0),
                (v_item->>'billing_cycle')::TEXT,
                COALESCE((v_item->>'total_amount')::NUMERIC, 0),
                COALESCE((v_item->>'due_date')::DATE, CURRENT_DATE),
                COALESCE((v_item->>'approval_status')::TEXT, 'APPROVED'),
                COALESCE((v_item->>'status')::TEXT, 'Unpaid'),
                COALESCE((v_item->>'created_at')::TIMESTAMPTZ, NOW()),
                NOW()
            )
            ON CONFLICT (invoice_number) DO UPDATE SET
                previous_reading = EXCLUDED.previous_reading,
                current_reading = EXCLUDED.current_reading,
                consumption = EXCLUDED.consumption,
                consumption_value = EXCLUDED.consumption_value,
                kwh_price_snapshot = EXCLUDED.kwh_price_snapshot,
                fixed_fee_snapshot = EXCLUDED.fixed_fee_snapshot,
                arrears = EXCLUDED.arrears,
                total_due = EXCLUDED.total_due,
                paid_amount = EXCLUDED.paid_amount,
                remaining_amount = EXCLUDED.remaining_amount,
                total_amount = EXCLUDED.total_amount,
                approval_status = EXCLUDED.approval_status,
                status = EXCLUDED.status,
                updated_at = NOW();

            v_synced_invoices := v_synced_invoices + 1;
        END IF;
    END LOOP;

    -- E. Sync Payments (Natural Key: receipt_number)
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_payments)
    LOOP
        SELECT id INTO v_customer_id 
        FROM public.customers 
        WHERE subscriber_number = (v_item->>'subscriber_number')
        LIMIT 1;

        v_invoice_id := NULL;
        IF (v_item->>'invoice_number') IS NOT NULL AND (v_item->>'invoice_number') != '' THEN
            SELECT id INTO v_invoice_id FROM public.invoices WHERE invoice_number = (v_item->>'invoice_number') LIMIT 1;
        END IF;

        IF v_customer_id IS NOT NULL THEN
            INSERT INTO public.payments (
                customer_id,
                invoice_id,
                receipt_number,
                payment_method,
                amount_paid,
                payment_date,
                accountant_name,
                approval_status,
                notes,
                client_mutation_id,
                whatsapp_sent,
                created_at,
                updated_at
            ) VALUES (
                v_customer_id,
                v_invoice_id,
                (v_item->>'receipt_number')::TEXT,
                COALESCE((v_item->>'payment_method')::TEXT, 'CASH'),
                (v_item->>'amount_paid')::NUMERIC,
                COALESCE((v_item->>'payment_date')::TIMESTAMPTZ, NOW()),
                COALESCE((v_item->>'accountant_name')::TEXT, 'System'),
                COALESCE((v_item->>'approval_status')::TEXT, 'APPROVED'),
                (v_item->>'notes')::TEXT,
                (v_item->>'client_mutation_id')::UUID,
                COALESCE((v_item->>'whatsapp_sent')::BOOLEAN, false),
                COALESCE((v_item->>'created_at')::TIMESTAMPTZ, NOW()),
                NOW()
            )
            ON CONFLICT (receipt_number) DO UPDATE SET
                amount_paid = EXCLUDED.amount_paid,
                payment_method = EXCLUDED.payment_method,
                approval_status = EXCLUDED.approval_status,
                notes = EXCLUDED.notes,
                whatsapp_sent = EXCLUDED.whatsapp_sent,
                updated_at = NOW();

            v_synced_payments := v_synced_payments + 1;
        END IF;
    END LOOP;

    -- F. Sync Payment Allocations
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_allocations)
    LOOP
        SELECT id INTO v_payment_id FROM public.payments WHERE receipt_number = (v_item->>'receipt_number') LIMIT 1;
        SELECT id INTO v_invoice_id FROM public.invoices WHERE invoice_number = (v_item->>'invoice_number') LIMIT 1;

        IF v_payment_id IS NOT NULL AND v_invoice_id IS NOT NULL THEN
            INSERT INTO public.payment_allocations (
                payment_id,
                invoice_id,
                amount_allocated,
                is_reversed,
                reversed_at,
                reversal_reason,
                created_at
            ) VALUES (
                v_payment_id,
                v_invoice_id,
                (v_item->>'amount_allocated')::NUMERIC,
                COALESCE((v_item->>'is_reversed')::BOOLEAN, false),
                (v_item->>'reversed_at')::TIMESTAMPTZ,
                (v_item->>'reversal_reason')::TEXT,
                COALESCE((v_item->>'created_at')::TIMESTAMPTZ, NOW())
            );
            v_synced_allocations := v_synced_allocations + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'status', 'success',
        'synced_plans', v_synced_plans,
        'synced_customers', v_synced_customers,
        'synced_readings', v_synced_readings,
        'synced_invoices', v_synced_invoices,
        'synced_payments', v_synced_payments,
        'synced_allocations', v_synced_allocations,
        'timestamp', NOW()
    );
END;
$$;

-- Grant Execution Permissions to anon and authenticated clients
GRANT EXECUTE ON FUNCTION public.sync_station_payload(JSONB) TO anon;
GRANT EXECUTE ON FUNCTION public.sync_station_payload(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_station_payload(JSONB) TO service_role;
