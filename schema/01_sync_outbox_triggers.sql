-- ====================================================================
-- SmartPower ERP: Transactional Outbox Triggers for Local Database
-- Captures all INSERT, UPDATE, DELETE events for lossless cloud sync
-- ====================================================================

-- 1. Ensure sync_outbox table structure
CREATE TABLE IF NOT EXISTS public.sync_outbox (
    id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(50) NOT NULL,
    record_id BIGINT NOT NULL,
    natural_key VARCHAR(100),
    operation VARCHAR(10) NOT NULL, -- 'INSERT', 'UPDATE', 'DELETE'
    payload JSONB NOT NULL,
    status VARCHAR(20) DEFAULT 'PENDING', -- 'PENDING', 'SYNCED', 'FAILED'
    attempts INT DEFAULT 0,
    last_error TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    synced_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_sync_outbox_pending_v2 
ON public.sync_outbox(status, id ASC);

CREATE INDEX IF NOT EXISTS idx_sync_outbox_table_rec 
ON public.sync_outbox(table_name, record_id);

-- 2. Generic Outbox Trigger Function
CREATE OR REPLACE FUNCTION public.fn_capture_sync_outbox()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_table_name VARCHAR(50);
    v_record_id BIGINT;
    v_natural_key VARCHAR(100) := NULL;
    v_operation VARCHAR(10);
    v_payload JSONB;
BEGIN
    v_table_name := TG_TABLE_NAME;
    v_operation := TG_OP;

    IF TG_OP = 'DELETE' THEN
        v_record_id := OLD.id;
        v_payload := to_jsonb(OLD);
        
        IF v_table_name = 'customers' THEN
            v_natural_key := OLD.subscriber_number;
        ELSIF v_table_name = 'invoices' THEN
            v_natural_key := OLD.invoice_number;
        ELSIF v_table_name = 'payments' THEN
            v_natural_key := OLD.receipt_number;
        ELSIF v_table_name = 'meter_readings' THEN
            v_natural_key := COALESCE(OLD.client_mutation_id::TEXT, OLD.id::TEXT);
        ELSIF v_table_name = 'subscription_plans' THEN
            v_natural_key := OLD.plan_name;
        END IF;
    ELSE
        v_record_id := NEW.id;
        v_payload := to_jsonb(NEW);

        IF v_table_name = 'customers' THEN
            v_natural_key := NEW.subscriber_number;
        ELSIF v_table_name = 'invoices' THEN
            v_natural_key := NEW.invoice_number;
        ELSIF v_table_name = 'payments' THEN
            v_natural_key := NEW.receipt_number;
        ELSIF v_table_name = 'meter_readings' THEN
            v_natural_key := COALESCE(NEW.client_mutation_id::TEXT, NEW.id::TEXT);
        ELSIF v_table_name = 'subscription_plans' THEN
            v_natural_key := NEW.plan_name;
        END IF;
    END IF;

    -- Insert into sync_outbox within the same local transaction
    INSERT INTO public.sync_outbox (
        table_name,
        record_id,
        natural_key,
        operation,
        payload,
        status,
        created_at
    ) VALUES (
        v_table_name,
        v_record_id,
        v_natural_key,
        v_operation,
        v_payload,
        'PENDING',
        CURRENT_TIMESTAMP
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

-- 3. Attach Triggers to Critical Entities

-- Customers Trigger
DROP TRIGGER IF EXISTS trg_sync_outbox_customers ON public.customers;
CREATE TRIGGER trg_sync_outbox_customers
AFTER INSERT OR UPDATE OR DELETE ON public.customers
FOR EACH ROW EXECUTE FUNCTION public.fn_capture_sync_outbox();

-- Subscription Plans Trigger
DROP TRIGGER IF EXISTS trg_sync_outbox_subscription_plans ON public.subscription_plans;
CREATE TRIGGER trg_sync_outbox_subscription_plans
AFTER INSERT OR UPDATE OR DELETE ON public.subscription_plans
FOR EACH ROW EXECUTE FUNCTION public.fn_capture_sync_outbox();

-- Meter Readings Trigger
DROP TRIGGER IF EXISTS trg_sync_outbox_meter_readings ON public.meter_readings;
CREATE TRIGGER trg_sync_outbox_meter_readings
AFTER INSERT OR UPDATE OR DELETE ON public.meter_readings
FOR EACH ROW EXECUTE FUNCTION public.fn_capture_sync_outbox();

-- Invoices Trigger
DROP TRIGGER IF EXISTS trg_sync_outbox_invoices ON public.invoices;
CREATE TRIGGER trg_sync_outbox_invoices
AFTER INSERT OR UPDATE OR DELETE ON public.invoices
FOR EACH ROW EXECUTE FUNCTION public.fn_capture_sync_outbox();

-- Payments Trigger
DROP TRIGGER IF EXISTS trg_sync_outbox_payments ON public.payments;
CREATE TRIGGER trg_sync_outbox_payments
AFTER INSERT OR UPDATE OR DELETE ON public.payments
FOR EACH ROW EXECUTE FUNCTION public.fn_capture_sync_outbox();

-- Payment Allocations Trigger
DROP TRIGGER IF EXISTS trg_sync_outbox_payment_allocations ON public.payment_allocations;
CREATE TRIGGER trg_sync_outbox_payment_allocations
AFTER INSERT OR UPDATE OR DELETE ON public.payment_allocations
FOR EACH ROW EXECUTE FUNCTION public.fn_capture_sync_outbox();
