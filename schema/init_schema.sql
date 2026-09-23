--
-- PostgreSQL database dump
--

\restrict meXbHGDVwU8d5ZLnmvQInaeaMKMTXc2A7svWoxgkSVwJbHvPdF5H7AHASXdLxpA

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS '';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: fn_calculate_cycle_financials(numeric, numeric, numeric, numeric, numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_calculate_cycle_financials(p_current_reading numeric, p_previous_reading numeric, p_lost_units numeric, p_unit_price numeric, p_service_fee numeric, p_arrears numeric, p_paid_amount numeric) RETURNS TABLE(consumption numeric, consumption_cost numeric, lost_units_cost numeric, total_due numeric, remaining_amount numeric, status text)
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
DECLARE
  v_curr     NUMERIC(12,2) := COALESCE(p_current_reading, 0.00);
  v_prev     NUMERIC(12,2) := COALESCE(p_previous_reading, 0.00);
  v_price    NUMERIC(12,2) := GREATEST(0.00, COALESCE(p_unit_price, 0.00));
  v_fee      NUMERIC(12,2) := GREATEST(0.00, COALESCE(p_service_fee, 0.00));
  v_arrears  NUMERIC(12,2) := COALESCE(p_arrears, 0.00);
  v_paid     NUMERIC(12,2) := GREATEST(0.00, COALESCE(p_paid_amount, 0.00));
  
  v_cons     NUMERIC(12,2);
  v_cons_val NUMERIC(12,2);
  v_due      NUMERIC(12,2);
  v_rem      NUMERIC(12,2);
  v_status   TEXT;
BEGIN
  -- 1. Net Consumption
  v_cons := GREATEST(0.00, ROUND(v_curr - v_prev, 2));
  
  -- 2. Net Consumption Cost
  v_cons_val := ROUND(v_cons * v_price, 2);
  
  -- 3. Total Due = Consumption Cost + Service Fee + Arrears (lost units cost eliminated)
  v_due := ROUND(v_cons_val + v_fee + v_arrears, 2);
  
  -- 4. Remaining Balance
  v_rem := GREATEST(0.00, ROUND(v_due - v_paid, 2));
  
  -- 5. Status
  IF v_rem <= 0.00 THEN
    v_status := 'Paid';
  ELSIF v_paid > 0.00 THEN
    v_status := 'Partially_Paid';
  ELSE
    v_status := 'Unpaid';
  END IF;

  RETURN QUERY SELECT v_cons, v_cons_val, 0.00::NUMERIC, v_due, v_rem, v_status;
END;
$$;


ALTER FUNCTION public.fn_calculate_cycle_financials(p_current_reading numeric, p_previous_reading numeric, p_lost_units numeric, p_unit_price numeric, p_service_fee numeric, p_arrears numeric, p_paid_amount numeric) OWNER TO postgres;

--
-- Name: fn_generate_invoice_number(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_generate_invoice_number(p_billing_cycle text, p_subscriber_number text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_clean_cycle TEXT;
    v_clean_subscriber TEXT;
BEGIN
    v_clean_subscriber := regexp_replace(COALESCE(TRIM(p_subscriber_number), 'UNKNOWN'), '[^A-Za-z0-9_\-]', '', 'g');
    IF v_clean_subscriber = '' THEN
        v_clean_subscriber := 'SUB';
    END IF;

    v_clean_cycle := regexp_replace(COALESCE(TRIM(p_billing_cycle), 'CYCLE'), '\s*-\s*', '-', 'g');
    v_clean_cycle := regexp_replace(v_clean_cycle, '\s+', '-', 'g');
    v_clean_cycle := regexp_replace(v_clean_cycle, '-+', '-', 'g');
    v_clean_cycle := regexp_replace(v_clean_cycle, '[^A-Za-z0-9_\-ء-ي]', '', 'g');
    v_clean_cycle := trim(both '-' from v_clean_cycle);

    IF v_clean_cycle = '' THEN
        v_clean_cycle := 'GENERAL';
    END IF;

    RETURN 'INV-' || v_clean_cycle || '-' || v_clean_subscriber;
END;
$$;


ALTER FUNCTION public.fn_generate_invoice_number(p_billing_cycle text, p_subscriber_number text) OWNER TO postgres;

--
-- Name: fn_trg_invoices_set_invoice_number(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_trg_invoices_set_invoice_number() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fn_trg_invoices_set_invoice_number() OWNER TO postgres;

--
-- Name: fn_trg_meter_readings_monotonic(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_trg_meter_readings_monotonic() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_prev_reading NUMERIC(12,2);
BEGIN
    -- Allow meter reset
    IF NEW.is_meter_reset = TRUE THEN
        IF NEW.previous_reading IS NULL OR NEW.previous_reading = 0 THEN
            NEW.previous_reading := 0;
        END IF;
        NEW.consumption := GREATEST(0.00, NEW.reading_value);
        RETURN NEW;
    END IF;

    -- Look up last approved reading strictly BEFORE this reading
    SELECT reading_value INTO v_prev_reading
    FROM public.meter_readings
    WHERE customer_id = NEW.customer_id
      AND approval_status != 'REJECTED'
      AND id != COALESCE(NEW.id, -1)
      AND (
        reading_date < NEW.reading_date 
        OR (reading_date = NEW.reading_date AND (NEW.id IS NULL OR id < NEW.id))
      )
    ORDER BY reading_date DESC, id DESC
    LIMIT 1;

    -- Fallback to initial reading if no previous reading exists
    IF NOT FOUND OR v_prev_reading IS NULL THEN
        SELECT initial_reading INTO v_prev_reading
        FROM public.customers
        WHERE id = NEW.customer_id;
    END IF;

    -- Enforce strict monotonic rule
    IF v_prev_reading IS NOT NULL AND NEW.reading_value < v_prev_reading THEN
        RAISE EXCEPTION 'New reading value (%) cannot be less than previous reading (%) for customer %',
            NEW.reading_value, v_prev_reading, NEW.customer_id
            USING ERRCODE = 'check_violation';
    END IF;

    -- Populate previous_reading and consumption if needed
    IF NEW.previous_reading IS NULL OR NEW.previous_reading = 0 THEN
        NEW.previous_reading := COALESCE(v_prev_reading, 0.00);
    END IF;
    IF NEW.consumption IS NULL OR NEW.consumption = 0 THEN
        NEW.consumption := GREATEST(0.00, NEW.reading_value - NEW.previous_reading);
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_trg_meter_readings_monotonic() OWNER TO postgres;

--
-- Name: rpc_recalculate_customer_cascade(integer, integer, integer, jsonb, integer, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rpc_recalculate_customer_cascade(p_customer_id integer, p_trigger_invoice_id integer DEFAULT NULL::integer, p_trigger_reading_id integer DEFAULT NULL::integer, p_updates jsonb DEFAULT '{}'::jsonb, p_actor_user_id integer DEFAULT NULL::integer, p_is_meter_reset boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_customer             RECORD;
  v_invoices             public.invoices[];
  v_inv                  public.invoices;
  v_target_idx           INT := -1;
  v_affected_cycles      TEXT[] := ARRAY[]::TEXT[];
  v_updated_summaries    JSONB[] := ARRAY[]::JSONB[];
  
  -- Calculation variables per cycle
  v_curr_reading         NUMERIC(12,2);
  v_prev_reading         NUMERIC(12,2);
  v_lost_units           NUMERIC(12,2);
  v_unit_price           NUMERIC(12,2);
  v_service_fee          NUMERIC(12,2);
  v_arrears              NUMERIC(12,2);
  v_paid_amount          NUMERIC(12,2);
  
  v_calc                 RECORD;
  
  -- Cascading memory between cycles
  v_cascade_reading      NUMERIC(12,2);
  v_cascade_arrears      NUMERIC(12,2);
  
  v_total_invoices_count INT := 0;
BEGIN
  -- 1. Pessimistic Lock on Customer
  IF p_customer_id IS NULL OR p_customer_id <= 0 THEN
    RAISE EXCEPTION 'معرف المشترك غير صحيح (%)', p_customer_id;
  END IF;

  SELECT * INTO v_customer 
  FROM public.customers 
  WHERE id = p_customer_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'المشترك غير موجود برقم (%)', p_customer_id;
  END IF;

  -- 2. Fetch and Lock Active Customer Invoices Chronologically
  SELECT ARRAY(
    SELECT inv
    FROM public.invoices inv
    WHERE inv.customer_id = p_customer_id
      AND inv.approval_status != 'REJECTED'
      AND inv.status != 'Void'
    ORDER BY inv.created_at ASC, inv.id ASC
    FOR UPDATE
  ) INTO v_invoices;

  v_total_invoices_count := COALESCE(array_length(v_invoices, 1), 0);

  IF v_total_invoices_count = 0 THEN
    RETURN jsonb_build_object(
      'success', true,
      'customer_id', p_customer_id,
      'affected_cycles', '[]'::jsonb,
      'updated_invoices', '[]'::jsonb,
      'final_customer_balance', 0.00,
      'message', 'لا توجد فواتير مسجلة للمشترك'
    );
  END IF;

  -- 3. Determine Trigger Cycle Index
  IF p_trigger_invoice_id IS NOT NULL THEN
    FOR i IN 1..v_total_invoices_count LOOP
      IF v_invoices[i].id = p_trigger_invoice_id THEN
        v_target_idx := i;
        EXIT;
      END IF;
    END LOOP;
  ELSIF p_trigger_reading_id IS NOT NULL THEN
    FOR i IN 1..v_total_invoices_count LOOP
      IF v_invoices[i].reading_id = p_trigger_reading_id THEN
        v_target_idx := i;
        EXIT;
      END IF;
    END LOOP;
  ELSE
    v_target_idx := 1;
  END IF;

  IF v_target_idx = -1 THEN
    RAISE EXCEPTION 'لم يتم العثور على الفاتورة أو القراءة المستهدفة ضمن سجلات المشترك';
  END IF;

  -- 4. Initialize Cascading Indicators before Trigger Cycle T
  IF v_target_idx > 1 THEN
    v_cascade_reading := v_invoices[v_target_idx - 1].current_reading;
    v_cascade_arrears := v_invoices[v_target_idx - 1].remaining_amount;
  ELSE
    v_cascade_reading := COALESCE(v_customer.initial_reading, 0.00);
    v_cascade_arrears := 0.00;
  END IF;

  -- 5. Cascade Loop from Cycle T to Cycle N
  FOR i IN v_target_idx..v_total_invoices_count LOOP
    v_inv := v_invoices[i];

    IF i = v_target_idx THEN
      -- Trigger Cycle T: Apply new updates or keep existing
      v_curr_reading := COALESCE((p_updates->>'current_reading')::NUMERIC, v_inv.current_reading);
      
      IF (p_updates->>'previous_reading') IS NOT NULL THEN
        v_prev_reading := (p_updates->>'previous_reading')::NUMERIC;
      ELSE
        v_prev_reading := CASE WHEN i > 1 THEN v_cascade_reading ELSE v_inv.previous_reading END;
      END IF;

      -- Check Monotonic Guard
      IF v_curr_reading < v_prev_reading AND NOT p_is_meter_reset THEN
        RAISE EXCEPTION 'القراءة الحالية (%) لا يمكن أن تكون أقل من القراءة السابقة (%) في الدورة (%)',
          v_curr_reading, v_prev_reading, COALESCE(v_inv.billing_cycle, v_inv.id::TEXT);
      END IF;

      v_lost_units  := COALESCE((p_updates->>'lost_units')::NUMERIC, v_inv.lost_units, 0.00);
      v_unit_price  := COALESCE((p_updates->>'unit_price')::NUMERIC, (p_updates->>'kwh_price')::NUMERIC, v_inv.kwh_price_snapshot);
      v_service_fee := COALESCE((p_updates->>'service_fee')::NUMERIC, (p_updates->>'fixed_fee')::NUMERIC, v_inv.fixed_fee_snapshot);
      
      IF (p_updates->>'arrears') IS NOT NULL THEN
        v_arrears := (p_updates->>'arrears')::NUMERIC;
      ELSE
        v_arrears := CASE WHEN i > 1 THEN v_cascade_arrears ELSE v_inv.arrears END;
      END IF;

      v_paid_amount := COALESCE((p_updates->>'paid_amount')::NUMERIC, v_inv.paid_amount);

    ELSE
      -- Subsequent Cycles (T+1 .. N): Automatically inherit previous reading & arrears
      v_prev_reading := v_cascade_reading;
      v_arrears      := v_cascade_arrears;
      v_curr_reading := v_inv.current_reading;

      -- Downstream Monotonic Guard
      IF v_curr_reading < v_prev_reading AND NOT p_is_meter_reset THEN
        RAISE EXCEPTION 'تعديل القراءة للدورة السابقة إلى (%) يتعارض مع القراءة المسجلة للدورة اللاحقة (%) البالغة (%)',
          v_prev_reading, COALESCE(v_inv.billing_cycle, v_inv.id::TEXT), v_curr_reading;
      END IF;

      v_lost_units  := COALESCE(v_inv.lost_units, 0.00);
      v_unit_price  := v_inv.kwh_price_snapshot;
      v_service_fee := v_inv.fixed_fee_snapshot;
      v_paid_amount := v_inv.paid_amount;
    END IF;

    -- Calculate Cycle Financials
    SELECT * INTO v_calc 
    FROM public.fn_calculate_cycle_financials(
      v_curr_reading,
      v_prev_reading,
      v_lost_units,
      v_unit_price,
      v_service_fee,
      v_arrears,
      v_paid_amount
    );

    -- Update Invoice Record
    UPDATE public.invoices
    SET previous_reading   = v_prev_reading,
        current_reading    = v_curr_reading,
        consumption        = v_calc.consumption,
        lost_units         = v_lost_units,
        consumption_value  = v_calc.consumption_cost,
        lost_units_value   = v_calc.lost_units_cost,
        kwh_price_snapshot = v_unit_price,
        fixed_fee_snapshot = v_service_fee,
        arrears            = v_arrears,
        total_due          = v_calc.total_due,
        total_amount       = v_calc.total_due,
        paid_amount        = v_paid_amount,
        remaining_amount   = v_calc.remaining_amount,
        status             = v_calc.status,
        updated_at         = CURRENT_TIMESTAMP
    WHERE id = v_inv.id;

    -- Update Meter Reading if linked
    IF v_inv.reading_id IS NOT NULL THEN
      UPDATE public.meter_readings
      SET reading_value = v_curr_reading,
          previous_reading = v_prev_reading,
          consumption = v_calc.consumption,
          lost_units = v_lost_units,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = v_inv.reading_id;
    END IF;

    -- Record Affected Cycle
    v_affected_cycles := array_append(v_affected_cycles, COALESCE(v_inv.billing_cycle, 'دورة-' || v_inv.id));

    v_updated_summaries := array_append(v_updated_summaries, jsonb_build_object(
      'invoice_id', v_inv.id,
      'reading_id', v_inv.reading_id,
      'cycle', COALESCE(v_inv.billing_cycle, 'دورة-' || v_inv.id),
      'previous_reading', v_prev_reading,
      'current_reading', v_curr_reading,
      'consumption', v_calc.consumption,
      'lost_units', v_lost_units,
      'unit_price', v_unit_price,
      'service_fee', v_service_fee,
      'arrears', v_arrears,
      'total_due', v_calc.total_due,
      'paid_amount', v_paid_amount,
      'remaining_amount', v_calc.remaining_amount,
      'status', v_calc.status
    ));

    -- Update Cascading Indicators for next cycle
    v_cascade_reading := v_curr_reading;
    v_cascade_arrears := v_calc.remaining_amount;
  END LOOP;

  -- 6. Update Final Customer Balance & Initial Reading if T=1
  UPDATE public.customers
  SET initial_reading = CASE WHEN v_target_idx = 1 AND (p_updates->>'previous_reading') IS NOT NULL 
                             THEN (p_updates->>'previous_reading')::NUMERIC 
                             ELSE initial_reading END,
      last_reading = v_cascade_reading,
      total_due = v_cascade_arrears,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_customer_id;

  -- 7. Audit Logging
  INSERT INTO public.audit_logs (
    user_id, action, entity, entity_id, details, created_at
  ) VALUES (
    p_actor_user_id,
    'RECALCULATE_CASCADE',
    'CUSTOMER',
    p_customer_id::TEXT,
    jsonb_build_object(
      'trigger_invoice_id', p_trigger_invoice_id,
      'trigger_reading_id', p_trigger_reading_id,
      'affected_cycles', to_jsonb(v_affected_cycles),
      'affected_count', array_length(v_affected_cycles, 1),
      'final_customer_balance', v_cascade_arrears,
      'is_meter_reset', p_is_meter_reset
    )::TEXT,
    CURRENT_TIMESTAMP
  );

  RETURN jsonb_build_object(
    'success', true,
    'customer_id', p_customer_id,
    'affected_cycles', to_jsonb(v_affected_cycles),
    'updated_invoices', to_jsonb(v_updated_summaries),
    'final_customer_balance', v_cascade_arrears
  );
END;
$$;


ALTER FUNCTION public.rpc_recalculate_customer_cascade(p_customer_id integer, p_trigger_invoice_id integer, p_trigger_reading_id integer, p_updates jsonb, p_actor_user_id integer, p_is_meter_reset boolean) OWNER TO postgres;

--
-- Name: rpc_recalculate_customer_cascade(bigint, bigint, bigint, jsonb, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rpc_recalculate_customer_cascade(p_customer_id bigint, p_trigger_invoice_id bigint DEFAULT NULL::bigint, p_trigger_reading_id bigint DEFAULT NULL::bigint, p_updates jsonb DEFAULT '{}'::jsonb, p_actor_user_id bigint DEFAULT NULL::bigint, p_is_meter_reset boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_customer             RECORD;
  v_invoices             public.invoices[];
  v_inv                  public.invoices;
  v_target_idx           INT := -1;
  v_affected_cycles      TEXT[] := ARRAY[]::TEXT[];
  v_updated_summaries    JSONB[] := ARRAY[]::JSONB[];
  
  -- Calculation variables per cycle
  v_curr_reading         NUMERIC(12,2);
  v_prev_reading         NUMERIC(12,2);
  v_lost_units           NUMERIC(12,2);
  v_unit_price           NUMERIC(12,2);
  v_service_fee          NUMERIC(12,2);
  v_arrears              NUMERIC(12,2);
  v_paid_amount          NUMERIC(12,2);
  
  v_calc                 RECORD;
  
  -- Cascading memory between cycles
  v_cascade_reading      NUMERIC(12,2);
  v_cascade_arrears      NUMERIC(12,2);
  
  v_total_invoices_count INT := 0;
BEGIN
  -- 1. Pessimistic Lock on Customer
  IF p_customer_id IS NULL OR p_customer_id <= 0 THEN
    RAISE EXCEPTION 'معرف المشترك غير صحيح (%)', p_customer_id;
  END IF;

  SELECT * INTO v_customer 
  FROM public.customers 
  WHERE id = p_customer_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'المشترك غير موجود برقم (%)', p_customer_id;
  END IF;

  -- 2. Fetch and Lock Active Customer Invoices Chronologically
  SELECT ARRAY(
    SELECT inv
    FROM public.invoices inv
    WHERE inv.customer_id = p_customer_id
      AND inv.approval_status != 'REJECTED'
      AND inv.status != 'Void'
    ORDER BY inv.created_at ASC, inv.id ASC
    FOR UPDATE
  ) INTO v_invoices;

  v_total_invoices_count := COALESCE(array_length(v_invoices, 1), 0);

  IF v_total_invoices_count = 0 THEN
    RETURN jsonb_build_object(
      'success', true,
      'customer_id', p_customer_id,
      'affected_cycles', '[]'::jsonb,
      'updated_invoices', '[]'::jsonb,
      'final_customer_balance', 0.00,
      'message', 'لا توجد فواتير مسجلة للمشترك'
    );
  END IF;

  -- 3. Determine Trigger Cycle Index
  IF p_trigger_invoice_id IS NOT NULL THEN
    FOR i IN 1..v_total_invoices_count LOOP
      IF v_invoices[i].id = p_trigger_invoice_id THEN
        v_target_idx := i;
        EXIT;
      END IF;
    END LOOP;
  ELSIF p_trigger_reading_id IS NOT NULL THEN
    FOR i IN 1..v_total_invoices_count LOOP
      IF v_invoices[i].reading_id = p_trigger_reading_id THEN
        v_target_idx := i;
        EXIT;
      END IF;
    END LOOP;
  ELSE
    v_target_idx := 1;
  END IF;

  IF v_target_idx = -1 THEN
    RAISE EXCEPTION 'لم يتم العثور على الفاتورة أو القراءة المستهدفة ضمن سجلات المشترك';
  END IF;

  -- 4. Initialize Cascading Indicators before Trigger Cycle T
  IF v_target_idx > 1 THEN
    v_cascade_reading := v_invoices[v_target_idx - 1].current_reading;
    v_cascade_arrears := v_invoices[v_target_idx - 1].remaining_amount;
  ELSE
    v_cascade_reading := COALESCE(v_customer.initial_reading, 0.00);
    v_cascade_arrears := 0.00;
  END IF;

  -- 5. Cascade Loop from Cycle T to Cycle N
  FOR i IN v_target_idx..v_total_invoices_count LOOP
    v_inv := v_invoices[i];

    IF i = v_target_idx THEN
      -- Trigger Cycle T: Apply new updates or keep existing
      v_curr_reading := COALESCE((p_updates->>'current_reading')::NUMERIC, v_inv.current_reading);
      
      IF (p_updates->>'previous_reading') IS NOT NULL THEN
        v_prev_reading := (p_updates->>'previous_reading')::NUMERIC;
      ELSE
        v_prev_reading := CASE WHEN i > 1 THEN v_cascade_reading ELSE v_inv.previous_reading END;
      END IF;

      -- Check Monotonic Guard
      IF v_curr_reading < v_prev_reading AND NOT p_is_meter_reset THEN
        RAISE EXCEPTION 'القراءة الحالية (%) لا يمكن أن تكون أقل من القراءة السابقة (%) في الدورة (%)',
          v_curr_reading, v_prev_reading, COALESCE(v_inv.billing_cycle, v_inv.id::TEXT);
      END IF;

      v_lost_units  := COALESCE((p_updates->>'lost_units')::NUMERIC, v_inv.lost_units, 0.00);
      v_unit_price  := COALESCE((p_updates->>'unit_price')::NUMERIC, (p_updates->>'kwh_price')::NUMERIC, v_inv.kwh_price_snapshot);
      v_service_fee := COALESCE((p_updates->>'service_fee')::NUMERIC, (p_updates->>'fixed_fee')::NUMERIC, v_inv.fixed_fee_snapshot);
      
      IF (p_updates->>'arrears') IS NOT NULL THEN
        v_arrears := (p_updates->>'arrears')::NUMERIC;
      ELSE
        v_arrears := CASE WHEN i > 1 THEN v_cascade_arrears ELSE v_inv.arrears END;
      END IF;

      v_paid_amount := COALESCE((p_updates->>'paid_amount')::NUMERIC, v_inv.paid_amount);

    ELSE
      -- Subsequent Cycles (T+1 .. N): Automatically inherit previous reading & arrears
      v_prev_reading := v_cascade_reading;
      v_arrears      := v_cascade_arrears;
      v_curr_reading := v_inv.current_reading;

      -- Downstream Monotonic Guard
      IF v_curr_reading < v_prev_reading AND NOT p_is_meter_reset THEN
        RAISE EXCEPTION 'تعديل القراءة للدورة السابقة إلى (%) يتعارض مع القراءة المسجلة للدورة اللاحقة (%) البالغة (%)',
          v_prev_reading, COALESCE(v_inv.billing_cycle, v_inv.id::TEXT), v_curr_reading;
      END IF;

      v_lost_units  := COALESCE(v_inv.lost_units, 0.00);
      v_unit_price  := v_inv.kwh_price_snapshot;
      v_service_fee := v_inv.fixed_fee_snapshot;
      v_paid_amount := v_inv.paid_amount;
    END IF;

    -- Calculate Cycle Financials
    SELECT * INTO v_calc 
    FROM public.fn_calculate_cycle_financials(
      v_curr_reading,
      v_prev_reading,
      v_lost_units,
      v_unit_price,
      v_service_fee,
      v_arrears,
      v_paid_amount
    );

    -- Update Invoice Record
    UPDATE public.invoices
    SET previous_reading   = v_prev_reading,
        current_reading    = v_curr_reading,
        consumption        = v_calc.consumption,
        lost_units         = v_lost_units,
        consumption_value  = v_calc.consumption_cost,
        lost_units_value   = v_calc.lost_units_cost,
        kwh_price_snapshot = v_unit_price,
        fixed_fee_snapshot = v_service_fee,
        arrears            = v_arrears,
        total_due          = v_calc.total_due,
        total_amount       = v_calc.total_due,
        paid_amount        = v_paid_amount,
        remaining_amount   = v_calc.remaining_amount,
        status             = v_calc.status,
        updated_at         = CURRENT_TIMESTAMP
    WHERE id = v_inv.id;

    -- Update Meter Reading if linked
    IF v_inv.reading_id IS NOT NULL THEN
      UPDATE public.meter_readings
      SET reading_value = v_curr_reading,
          previous_reading = v_prev_reading,
          consumption = v_calc.consumption,
          lost_units = v_lost_units,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = v_inv.reading_id;
    END IF;

    -- Record Affected Cycle
    v_affected_cycles := array_append(v_affected_cycles, COALESCE(v_inv.billing_cycle, 'دورة-' || v_inv.id));

    v_updated_summaries := array_append(v_updated_summaries, jsonb_build_object(
      'invoice_id', v_inv.id,
      'reading_id', v_inv.reading_id,
      'cycle', COALESCE(v_inv.billing_cycle, 'دورة-' || v_inv.id),
      'previous_reading', v_prev_reading,
      'current_reading', v_curr_reading,
      'consumption', v_calc.consumption,
      'lost_units', v_lost_units,
      'unit_price', v_unit_price,
      'service_fee', v_service_fee,
      'arrears', v_arrears,
      'total_due', v_calc.total_due,
      'paid_amount', v_paid_amount,
      'remaining_amount', v_calc.remaining_amount,
      'status', v_calc.status
    ));

    -- Update Cascading Indicators for next cycle
    v_cascade_reading := v_curr_reading;
    v_cascade_arrears := v_calc.remaining_amount;
  END LOOP;

  -- 6. Update Final Customer Balance & Initial Reading if T=1
  UPDATE public.customers
  SET initial_reading = CASE WHEN v_target_idx = 1 AND (p_updates->>'previous_reading') IS NOT NULL 
                             THEN (p_updates->>'previous_reading')::NUMERIC 
                             ELSE initial_reading END,
      last_reading = v_cascade_reading,
      total_due = v_cascade_arrears,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_customer_id;

  -- 7. Audit Logging
  INSERT INTO public.audit_logs (
    user_id, action, entity, entity_id, details, created_at
  ) VALUES (
    p_actor_user_id,
    'RECALCULATE_CASCADE',
    'CUSTOMER',
    p_customer_id::TEXT,
    jsonb_build_object(
      'trigger_invoice_id', p_trigger_invoice_id,
      'trigger_reading_id', p_trigger_reading_id,
      'affected_cycles', to_jsonb(v_affected_cycles),
      'affected_count', array_length(v_affected_cycles, 1),
      'final_customer_balance', v_cascade_arrears,
      'is_meter_reset', p_is_meter_reset
    )::TEXT,
    CURRENT_TIMESTAMP
  );

  RETURN jsonb_build_object(
    'success', true,
    'customer_id', p_customer_id,
    'affected_cycles', to_jsonb(v_affected_cycles),
    'updated_invoices', to_jsonb(v_updated_summaries),
    'final_customer_balance', v_cascade_arrears
  );
END;
$$;


ALTER FUNCTION public.rpc_recalculate_customer_cascade(p_customer_id bigint, p_trigger_invoice_id bigint, p_trigger_reading_id bigint, p_updates jsonb, p_actor_user_id bigint, p_is_meter_reset boolean) OWNER TO postgres;

--
-- Name: rpc_submit_meter_reading(integer, numeric, text, uuid, boolean, timestamp with time zone, text, boolean, numeric, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rpc_submit_meter_reading(p_customer_id integer, p_reading_value numeric, p_collector_name text, p_idempotency_key uuid, p_auto_approve boolean, p_reading_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP, p_custom_cycle text DEFAULT NULL::text, p_is_meter_reset boolean DEFAULT false, p_lost_units numeric DEFAULT 0, p_collector_user_id integer DEFAULT NULL::integer) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_previous_reading NUMERIC(12,2);
  v_consumption NUMERIC(12,2);
  v_arrears NUMERIC(12,2) := 0.00;
  v_kwh_price NUMERIC(12,2);
  v_fixed_fee NUMERIC(12,2);
  v_consumption_value NUMERIC(12,2);
  v_lost_units_cost NUMERIC(12,2);
  v_total_due NUMERIC(12,2);
  v_grace_days INT;
  v_due_date DATE;
  v_billing_cycle TEXT;
  v_last_cycle TEXT;
  v_reading_id BIGINT;
  v_invoice_id BIGINT;
  v_invoice_number TEXT;
  v_existing_json JSON;
  v_settings RECORD;
  v_customer RECORD;
  v_plan RECORD;
  v_approval_status TEXT;
  v_invoice_status TEXT;
  v_credit_record RECORD;
  v_applied_credit NUMERIC(12,2) := 0.00;
  v_remaining_credit_needed NUMERIC(12,2);
  v_credit_allocated NUMERIC(12,2);
  v_final_paid NUMERIC(12,2) := 0.00;
  v_final_remaining NUMERIC(12,2);
BEGIN
  -- 1. Idempotency Check
  SELECT row_to_json(m) INTO v_existing_json 
  FROM public.meter_readings m 
  WHERE m.client_mutation_id = p_idempotency_key;
  
  IF FOUND THEN
    RETURN json_build_object('success', true, 'is_duplicate', true, 'data', v_existing_json);
  END IF;

  -- 2. Lock Customer Row
  SELECT * INTO v_customer 
  FROM public.customers 
  WHERE id = p_customer_id 
  FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'المشترك رقم % غير موجود', p_customer_id;
  END IF;

  -- 3. Retrieve Previous Approved Reading
  SELECT reading_value INTO v_previous_reading 
  FROM public.meter_readings
  WHERE customer_id = p_customer_id AND approval_status != 'REJECTED'
  ORDER BY reading_date DESC, id DESC LIMIT 1;
  
  IF NOT FOUND OR v_previous_reading IS NULL THEN
    v_previous_reading := COALESCE(v_customer.initial_reading, 0.00);
  END IF;

  -- 4. Check Non-Monotonic Guard
  IF p_is_meter_reset = FALSE THEN
    IF p_reading_value < v_previous_reading THEN
      RAISE EXCEPTION 'New reading value (%) cannot be less than previous reading (%) for customer %',
        p_reading_value, v_previous_reading, p_customer_id
        USING ERRCODE = 'check_violation';
    END IF;
    v_consumption := ROUND(p_reading_value - v_previous_reading, 2);
  ELSE
    v_consumption := ROUND(p_reading_value, 2);
    v_previous_reading := 0.00;
  END IF;

  v_approval_status := CASE WHEN p_auto_approve THEN 'APPROVED' ELSE 'PENDING' END;

  -- 5. Tariffs & Settings
  SELECT * INTO v_plan FROM public.subscription_plans WHERE id = v_customer.subscription_plan_id;
  SELECT * INTO v_settings FROM public.system_settings LIMIT 1;

  v_kwh_price := COALESCE(v_plan.kwh_price, v_settings.default_kwh_price, 1000.00);
  v_fixed_fee := COALESCE(v_plan.fixed_fee, v_settings.default_fixed_fee, 1000.00);
  v_grace_days := COALESCE(v_plan.grace_period_days, v_settings.max_overdue_days, 10);

  -- 6. Arrears from previous unpaid approved invoices
  SELECT COALESCE(remaining_amount, 0.00) INTO v_arrears 
  FROM public.invoices
  WHERE customer_id = p_customer_id AND status IN ('Unpaid', 'Partially_Paid') AND approval_status = 'APPROVED'
  ORDER BY due_date DESC, id DESC LIMIT 1;

  IF v_arrears < 0 OR v_arrears IS NULL THEN
    v_arrears := 0.00;
  END IF;

  v_consumption_value := ROUND(v_consumption * v_kwh_price, 2);
  v_lost_units_cost := ROUND(GREATEST(0.00, COALESCE(p_lost_units, 0.00)) * v_kwh_price, 2);
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

  -- 8. Deduct Available Customer Credits
  v_remaining_credit_needed := v_total_due;

  FOR v_credit_record IN
    SELECT * FROM public.customer_credits
    WHERE customer_id = p_customer_id AND status = 'AVAILABLE' AND remaining_amount > 0
    ORDER BY id ASC FOR UPDATE
  LOOP
    EXIT WHEN v_remaining_credit_needed <= 0;
    v_credit_allocated := LEAST(v_remaining_credit_needed, v_credit_record.remaining_amount);

    UPDATE public.customer_credits
    SET remaining_amount = ROUND(remaining_amount - v_credit_allocated, 2),
        status = CASE WHEN (remaining_amount - v_credit_allocated) <= 0 THEN 'USED' ELSE 'AVAILABLE' END,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = v_credit_record.id;

    v_applied_credit := ROUND(v_applied_credit + v_credit_allocated, 2);
    v_remaining_credit_needed := ROUND(v_remaining_credit_needed - v_credit_allocated, 2);
  END LOOP;

  IF v_applied_credit > 0 THEN
    UPDATE public.customers
    SET balance = GREATEST(0.00, ROUND(balance - v_applied_credit, 2)),
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_customer_id;
  END IF;

  v_final_paid := v_applied_credit;
  v_final_remaining := GREATEST(0.00, ROUND(v_total_due - v_final_paid, 2));

  IF p_auto_approve THEN
    v_invoice_status := CASE WHEN v_final_remaining <= 0 THEN 'Paid' WHEN v_final_paid > 0 THEN 'Partially_Paid' ELSE 'Unpaid' END;
  ELSE
    v_invoice_status := 'Unpaid';
  END IF;

  -- 9. Insert Meter Reading
  INSERT INTO public.meter_readings (
    customer_id, reading_value, previous_reading, consumption, lost_units,
    reading_date, collector_name, collector_user_id, approval_status,
    client_mutation_id, is_meter_reset
  ) VALUES (
    p_customer_id, p_reading_value, v_previous_reading, v_consumption, COALESCE(p_lost_units, 0.00),
    p_reading_date, p_collector_name, p_collector_user_id, v_approval_status,
    p_idempotency_key, p_is_meter_reset
  ) RETURNING id INTO v_reading_id;

  -- 10. Insert Invoice
  INSERT INTO public.invoices (
    customer_id, reading_id, invoice_number, previous_reading, current_reading,
    consumption, lost_units, consumption_value, lost_units_value, kwh_price_snapshot, fixed_fee_snapshot,
    arrears, total_due, paid_amount, remaining_amount, billing_cycle,
    total_amount, due_date, approval_status, status, is_meter_reset, created_at
  ) VALUES (
    p_customer_id, v_reading_id, v_invoice_number, v_previous_reading, p_reading_value,
    v_consumption, COALESCE(p_lost_units, 0.00), v_consumption_value, v_lost_units_cost, v_kwh_price, v_fixed_fee,
    v_arrears, v_total_due, v_final_paid, v_final_remaining, v_billing_cycle,
    v_total_due, v_due_date, v_approval_status, v_invoice_status, p_is_meter_reset, p_reading_date
  ) RETURNING id INTO v_invoice_id;

  -- 11. Update Customer Last Reading and Total Due
  UPDATE public.customers
  SET last_reading = p_reading_value,
      total_due = (SELECT COALESCE(SUM(remaining_amount), 0.00) FROM public.invoices WHERE customer_id = p_customer_id AND status IN ('Unpaid', 'Partially_Paid') AND approval_status = 'APPROVED'),
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_customer_id;

  -- 12. Audit Logging
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
$$;


ALTER FUNCTION public.rpc_submit_meter_reading(p_customer_id integer, p_reading_value numeric, p_collector_name text, p_idempotency_key uuid, p_auto_approve boolean, p_reading_date timestamp with time zone, p_custom_cycle text, p_is_meter_reset boolean, p_lost_units numeric, p_collector_user_id integer) OWNER TO postgres;

--
-- Name: rpc_submit_meter_reading(bigint, numeric, text, uuid, boolean, timestamp with time zone, text, boolean, numeric, bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rpc_submit_meter_reading(p_customer_id bigint, p_reading_value numeric, p_collector_name text, p_idempotency_key uuid, p_auto_approve boolean, p_reading_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP, p_custom_cycle text DEFAULT NULL::text, p_is_meter_reset boolean DEFAULT false, p_lost_units numeric DEFAULT 0, p_collector_user_id bigint DEFAULT NULL::bigint) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_previous_reading NUMERIC(12,2);
  v_consumption NUMERIC(12,2);
  v_arrears NUMERIC(12,2) := 0.00;
  v_kwh_price NUMERIC(12,2);
  v_fixed_fee NUMERIC(12,2);
  v_consumption_value NUMERIC(12,2);
  v_lost_units_cost NUMERIC(12,2);
  v_total_due NUMERIC(12,2);
  v_grace_days INT;
  v_due_date DATE;
  v_billing_cycle TEXT;
  v_last_cycle TEXT;
  v_reading_id BIGINT;
  v_invoice_id BIGINT;
  v_invoice_number TEXT;
  v_existing_json JSON;
  v_settings RECORD;
  v_customer RECORD;
  v_plan RECORD;
  v_approval_status TEXT;
  v_invoice_status TEXT;
  v_credit_record RECORD;
  v_applied_credit NUMERIC(12,2) := 0.00;
  v_remaining_credit_needed NUMERIC(12,2);
  v_credit_allocated NUMERIC(12,2);
  v_final_paid NUMERIC(12,2) := 0.00;
  v_final_remaining NUMERIC(12,2);
BEGIN
  -- 1. Idempotency Check
  SELECT row_to_json(m) INTO v_existing_json 
  FROM public.meter_readings m 
  WHERE m.client_mutation_id = p_idempotency_key;
  
  IF FOUND THEN
    RETURN json_build_object('success', true, 'is_duplicate', true, 'data', v_existing_json);
  END IF;

  -- 2. Lock Customer Row
  SELECT * INTO v_customer 
  FROM public.customers 
  WHERE id = p_customer_id 
  FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'المشترك رقم % غير موجود', p_customer_id;
  END IF;

  -- 3. Retrieve Previous Approved Reading
  SELECT reading_value INTO v_previous_reading 
  FROM public.meter_readings
  WHERE customer_id = p_customer_id AND approval_status != 'REJECTED'
  ORDER BY reading_date DESC, id DESC LIMIT 1;
  
  IF NOT FOUND OR v_previous_reading IS NULL THEN
    v_previous_reading := COALESCE(v_customer.initial_reading, 0.00);
  END IF;

  -- 4. Check Non-Monotonic Guard
  IF p_is_meter_reset = FALSE THEN
    IF p_reading_value < v_previous_reading THEN
      RAISE EXCEPTION 'New reading value (%) cannot be less than previous reading (%) for customer %',
        p_reading_value, v_previous_reading, p_customer_id
        USING ERRCODE = 'check_violation';
    END IF;
    v_consumption := ROUND(p_reading_value - v_previous_reading, 2);
  ELSE
    v_consumption := ROUND(p_reading_value, 2);
    v_previous_reading := 0.00;
  END IF;

  v_approval_status := CASE WHEN p_auto_approve THEN 'APPROVED' ELSE 'PENDING' END;

  -- 5. Tariffs & Settings
  SELECT * INTO v_plan FROM public.subscription_plans WHERE id = v_customer.subscription_plan_id;
  SELECT * INTO v_settings FROM public.system_settings LIMIT 1;

  v_kwh_price := COALESCE(v_plan.kwh_price, v_settings.default_kwh_price, 1000.00);
  v_fixed_fee := COALESCE(v_plan.fixed_fee, v_settings.default_fixed_fee, 1000.00);
  v_grace_days := COALESCE(v_plan.grace_period_days, v_settings.max_overdue_days, 10);

  -- 6. Arrears from previous unpaid approved invoices
  SELECT COALESCE(remaining_amount, 0.00) INTO v_arrears 
  FROM public.invoices
  WHERE customer_id = p_customer_id AND status IN ('Unpaid', 'Partially_Paid') AND approval_status = 'APPROVED'
  ORDER BY due_date DESC, id DESC LIMIT 1;

  IF v_arrears < 0 OR v_arrears IS NULL THEN
    v_arrears := 0.00;
  END IF;

  v_consumption_value := ROUND(v_consumption * v_kwh_price, 2);
  v_lost_units_cost := ROUND(GREATEST(0.00, COALESCE(p_lost_units, 0.00)) * v_kwh_price, 2);
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

  -- 8. Deduct Available Customer Credits
  v_remaining_credit_needed := v_total_due;

  FOR v_credit_record IN
    SELECT * FROM public.customer_credits
    WHERE customer_id = p_customer_id AND status = 'AVAILABLE' AND remaining_amount > 0
    ORDER BY id ASC FOR UPDATE
  LOOP
    EXIT WHEN v_remaining_credit_needed <= 0;
    v_credit_allocated := LEAST(v_remaining_credit_needed, v_credit_record.remaining_amount);

    UPDATE public.customer_credits
    SET remaining_amount = ROUND(remaining_amount - v_credit_allocated, 2),
        status = CASE WHEN (remaining_amount - v_credit_allocated) <= 0 THEN 'USED' ELSE 'AVAILABLE' END,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = v_credit_record.id;

    v_applied_credit := ROUND(v_applied_credit + v_credit_allocated, 2);
    v_remaining_credit_needed := ROUND(v_remaining_credit_needed - v_credit_allocated, 2);
  END LOOP;

  IF v_applied_credit > 0 THEN
    UPDATE public.customers
    SET balance = GREATEST(0.00, ROUND(balance - v_applied_credit, 2)),
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_customer_id;
  END IF;

  v_final_paid := v_applied_credit;
  v_final_remaining := GREATEST(0.00, ROUND(v_total_due - v_final_paid, 2));

  IF p_auto_approve THEN
    v_invoice_status := CASE WHEN v_final_remaining <= 0 THEN 'Paid' WHEN v_final_paid > 0 THEN 'Partially_Paid' ELSE 'Unpaid' END;
  ELSE
    v_invoice_status := 'Unpaid';
  END IF;

  -- 9. Insert Meter Reading
  INSERT INTO public.meter_readings (
    customer_id, reading_value, previous_reading, consumption, lost_units,
    reading_date, collector_name, collector_user_id, approval_status,
    client_mutation_id, is_meter_reset
  ) VALUES (
    p_customer_id, p_reading_value, v_previous_reading, v_consumption, COALESCE(p_lost_units, 0.00),
    p_reading_date, p_collector_name, p_collector_user_id, v_approval_status,
    p_idempotency_key, p_is_meter_reset
  ) RETURNING id INTO v_reading_id;

  -- 10. Insert Invoice
  INSERT INTO public.invoices (
    customer_id, reading_id, invoice_number, previous_reading, current_reading,
    consumption, lost_units, consumption_value, lost_units_value, kwh_price_snapshot, fixed_fee_snapshot,
    arrears, total_due, paid_amount, remaining_amount, billing_cycle,
    total_amount, due_date, approval_status, status, is_meter_reset, created_at
  ) VALUES (
    p_customer_id, v_reading_id, v_invoice_number, v_previous_reading, p_reading_value,
    v_consumption, COALESCE(p_lost_units, 0.00), v_consumption_value, v_lost_units_cost, v_kwh_price, v_fixed_fee,
    v_arrears, v_total_due, v_final_paid, v_final_remaining, v_billing_cycle,
    v_total_due, v_due_date, v_approval_status, v_invoice_status, p_is_meter_reset, p_reading_date
  ) RETURNING id INTO v_invoice_id;

  -- 11. Update Customer Last Reading and Total Due
  UPDATE public.customers
  SET last_reading = p_reading_value,
      total_due = (SELECT COALESCE(SUM(remaining_amount), 0.00) FROM public.invoices WHERE customer_id = p_customer_id AND status IN ('Unpaid', 'Partially_Paid') AND approval_status = 'APPROVED'),
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_customer_id;

  -- 12. Audit Logging
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
$$;


ALTER FUNCTION public.rpc_submit_meter_reading(p_customer_id bigint, p_reading_value numeric, p_collector_name text, p_idempotency_key uuid, p_auto_approve boolean, p_reading_date timestamp with time zone, p_custom_cycle text, p_is_meter_reset boolean, p_lost_units numeric, p_collector_user_id bigint) OWNER TO postgres;

--
-- Name: rpc_submit_payment(integer, numeric, text, text, uuid, text, timestamp with time zone, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rpc_submit_payment(p_customer_id integer, p_amount_paid numeric, p_payment_method text, p_collector_name text, p_idempotency_key uuid, p_notes text DEFAULT NULL::text, p_payment_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP, p_invoice_id integer DEFAULT NULL::integer, p_actor_user_id integer DEFAULT NULL::integer, p_shift_id integer DEFAULT NULL::integer) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_existing_json JSON;
  v_receipt_number TEXT;
  v_payment_id BIGINT;
  v_next_val BIGINT;
  v_current_year INT;
  v_remaining_to_distribute NUMERIC(12,2);
  v_invoice RECORD;
  v_allocated_amount NUMERIC(12,2);
  v_new_paid NUMERIC(12,2);
  v_new_remaining NUMERIC(12,2);
  v_new_status TEXT;
  v_allocation_id BIGINT;
  v_customer RECORD;
  v_updated_debt NUMERIC(12,2);
  v_allocations JSONB := '[]'::jsonb;
  v_credit_amount NUMERIC(12,2) := 0.00;
  v_total_credit_available NUMERIC(12,2) := 0.00;
BEGIN
  -- 1. Idempotency Check
  SELECT row_to_json(pm) INTO v_existing_json 
  FROM public.payments pm 
  WHERE pm.client_mutation_id = p_idempotency_key;
  
  IF FOUND THEN
    RETURN json_build_object('success', true, 'is_duplicate', true, 'data', v_existing_json);
  END IF;

  -- 2. Validate Amount
  IF p_amount_paid IS NULL OR p_amount_paid <= 0 THEN
    RAISE EXCEPTION 'مبلغ السداد يجب أن يكون أكبر من الصفر' USING ERRCODE = 'check_violation';
  END IF;

  -- 3. Pessimistic Lock Level 1: Lock Customer Row
  SELECT * INTO v_customer 
  FROM public.customers 
  WHERE id = p_customer_id 
  FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'المشترك رقم % غير موجود في النظام', p_customer_id;
  END IF;

  -- 4. Generate Deterministic Sequential Receipt Number
  v_current_year := EXTRACT(YEAR FROM p_payment_date)::INT;
  
  INSERT INTO public.payment_receipt_counters (year, last_value)
  VALUES (v_current_year, 1)
  ON CONFLICT (year) DO UPDATE 
  SET last_value = public.payment_receipt_counters.last_value + 1
  RETURNING last_value INTO v_next_val;

  v_receipt_number := 'REC-' || v_current_year || '-' || LPAD(v_next_val::TEXT, 5, '0');

  -- 5. Insert Primary Payment Record
  INSERT INTO public.payments (
    customer_id, invoice_id, shift_id, receipt_number, payment_method,
    amount_paid, payment_date, accountant_name, accountant_user_id,
    approval_status, notes, client_mutation_id
  ) VALUES (
    p_customer_id, p_invoice_id, p_shift_id, v_receipt_number, COALESCE(p_payment_method, 'CASH'),
    ROUND(p_amount_paid, 2), p_payment_date, p_collector_name, p_actor_user_id,
    'APPROVED', p_notes, p_idempotency_key
  ) RETURNING id INTO v_payment_id;

  -- 6. Pessimistic Lock Level 2: Strict FIFO Waterfall Allocation ORDER BY due_date ASC, id ASC FOR UPDATE
  v_remaining_to_distribute := ROUND(p_amount_paid, 2);

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

    v_allocated_amount := LEAST(v_remaining_to_distribute, v_invoice.remaining_amount);
    
    IF v_allocated_amount > 0 THEN
      v_new_paid := ROUND(v_invoice.paid_amount + v_allocated_amount, 2);
      v_new_remaining := GREATEST(0.00, ROUND(v_invoice.remaining_amount - v_allocated_amount, 2));
      v_new_status := CASE WHEN v_new_remaining <= 0 THEN 'Paid' ELSE 'Partially_Paid' END;

      UPDATE public.invoices 
      SET paid_amount = v_new_paid,
          remaining_amount = v_new_remaining,
          status = v_new_status,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = v_invoice.id;

      INSERT INTO public.payment_allocations (
        payment_id, invoice_id, amount_allocated, is_reversed, created_at
      ) VALUES (
        v_payment_id, v_invoice.id, v_allocated_amount, FALSE, p_payment_date
      ) RETURNING id INTO v_allocation_id;

      v_allocations := v_allocations || jsonb_build_object(
        'invoice_id', v_invoice.id,
        'invoice_number', v_invoice.invoice_number,
        'billing_cycle', v_invoice.billing_cycle,
        'amount_allocated', v_allocated_amount,
        'new_remaining', v_new_remaining,
        'status', v_new_status
      );

      v_remaining_to_distribute := ROUND(v_remaining_to_distribute - v_allocated_amount, 2);
    END IF;
  END LOOP;

  -- 7. Handle Overpayment: Credit Ledger Deposit
  IF v_remaining_to_distribute > 0 THEN
    v_credit_amount := v_remaining_to_distribute;
    
    INSERT INTO public.customer_credits (
      customer_id, payment_id, amount, remaining_amount, status, created_at
    ) VALUES (
      p_customer_id, v_payment_id, v_credit_amount, v_credit_amount, 'AVAILABLE', p_payment_date
    );

    UPDATE public.customers
    SET balance = ROUND(balance + v_credit_amount, 2),
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_customer_id;
  END IF;

  -- 8. Recalculate Total Remaining Debt and Total Available Credit
  SELECT COALESCE(SUM(remaining_amount), 0.00) INTO v_updated_debt 
  FROM public.invoices
  WHERE customer_id = p_customer_id AND status IN ('Unpaid', 'Partially_Paid') AND approval_status = 'APPROVED';

  SELECT COALESCE(SUM(remaining_amount), 0.00) INTO v_total_credit_available
  FROM public.customer_credits
  WHERE customer_id = p_customer_id AND status = 'AVAILABLE';

  UPDATE public.customers
  SET total_due = v_updated_debt,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_customer_id;

  -- 9. Security Audit Logging
  INSERT INTO public.audit_logs (
    action, entity, entity_id, user_id, details, created_at
  ) VALUES (
    'PAYMENT_SUBMIT_FIFO', 'Payment', v_payment_id::TEXT, p_actor_user_id,
    'تحصيل دفعة مالية بقيمة ' || p_amount_paid || ' ر.ي للمشترك: ' || v_customer.full_name || 
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
    'allocated_total', ROUND(p_amount_paid - v_credit_amount, 2),
    'credit_balance', v_credit_amount,
    'total_credit_available', v_total_credit_available,
    'remaining_debt', v_updated_debt,
    'allocations', v_allocations
  );
END;
$$;


ALTER FUNCTION public.rpc_submit_payment(p_customer_id integer, p_amount_paid numeric, p_payment_method text, p_collector_name text, p_idempotency_key uuid, p_notes text, p_payment_date timestamp with time zone, p_invoice_id integer, p_actor_user_id integer, p_shift_id integer) OWNER TO postgres;

--
-- Name: rpc_submit_payment(bigint, numeric, text, text, uuid, text, timestamp with time zone, bigint, bigint, bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rpc_submit_payment(p_customer_id bigint, p_amount_paid numeric, p_payment_method text, p_collector_name text, p_idempotency_key uuid, p_notes text DEFAULT NULL::text, p_payment_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP, p_invoice_id bigint DEFAULT NULL::bigint, p_actor_user_id bigint DEFAULT NULL::bigint, p_shift_id bigint DEFAULT NULL::bigint) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_existing_json JSON;
  v_receipt_number TEXT;
  v_payment_id BIGINT;
  v_next_val BIGINT;
  v_current_year INT;
  v_remaining_to_distribute NUMERIC(12,2);
  v_invoice RECORD;
  v_allocated_amount NUMERIC(12,2);
  v_new_paid NUMERIC(12,2);
  v_new_remaining NUMERIC(12,2);
  v_new_status TEXT;
  v_allocation_id BIGINT;
  v_customer RECORD;
  v_updated_debt NUMERIC(12,2);
  v_allocations JSONB := '[]'::jsonb;
  v_credit_amount NUMERIC(12,2) := 0.00;
  v_total_credit_available NUMERIC(12,2) := 0.00;
BEGIN
  -- 1. Idempotency Check
  SELECT row_to_json(pm) INTO v_existing_json 
  FROM public.payments pm 
  WHERE pm.client_mutation_id = p_idempotency_key;
  
  IF FOUND THEN
    RETURN json_build_object('success', true, 'is_duplicate', true, 'data', v_existing_json);
  END IF;

  -- 2. Validate Amount
  IF p_amount_paid IS NULL OR p_amount_paid <= 0 THEN
    RAISE EXCEPTION 'مبلغ السداد يجب أن يكون أكبر من الصفر' USING ERRCODE = 'check_violation';
  END IF;

  -- 3. Pessimistic Lock Level 1: Lock Customer Row
  SELECT * INTO v_customer 
  FROM public.customers 
  WHERE id = p_customer_id 
  FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'المشترك رقم % غير موجود في النظام', p_customer_id;
  END IF;

  -- 4. Generate Deterministic Sequential Receipt Number
  v_current_year := EXTRACT(YEAR FROM p_payment_date)::INT;
  
  INSERT INTO public.payment_receipt_counters (year, last_value)
  VALUES (v_current_year, 1)
  ON CONFLICT (year) DO UPDATE 
  SET last_value = public.payment_receipt_counters.last_value + 1
  RETURNING last_value INTO v_next_val;

  v_receipt_number := 'REC-' || v_current_year || '-' || LPAD(v_next_val::TEXT, 5, '0');

  -- 5. Insert Primary Payment Record
  INSERT INTO public.payments (
    customer_id, invoice_id, shift_id, receipt_number, payment_method,
    amount_paid, payment_date, accountant_name, accountant_user_id,
    approval_status, notes, client_mutation_id
  ) VALUES (
    p_customer_id, p_invoice_id, p_shift_id, v_receipt_number, COALESCE(p_payment_method, 'CASH'),
    ROUND(p_amount_paid, 2), p_payment_date, p_collector_name, p_actor_user_id,
    'APPROVED', p_notes, p_idempotency_key
  ) RETURNING id INTO v_payment_id;

  -- 6. Pessimistic Lock Level 2: Strict FIFO Waterfall Allocation ORDER BY due_date ASC, id ASC FOR UPDATE
  v_remaining_to_distribute := ROUND(p_amount_paid, 2);

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

    v_allocated_amount := LEAST(v_remaining_to_distribute, v_invoice.remaining_amount);
    
    IF v_allocated_amount > 0 THEN
      v_new_paid := ROUND(v_invoice.paid_amount + v_allocated_amount, 2);
      v_new_remaining := GREATEST(0.00, ROUND(v_invoice.remaining_amount - v_allocated_amount, 2));
      v_new_status := CASE WHEN v_new_remaining <= 0 THEN 'Paid' ELSE 'Partially_Paid' END;

      UPDATE public.invoices 
      SET paid_amount = v_new_paid,
          remaining_amount = v_new_remaining,
          status = v_new_status,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = v_invoice.id;

      INSERT INTO public.payment_allocations (
        payment_id, invoice_id, amount_allocated, is_reversed, created_at
      ) VALUES (
        v_payment_id, v_invoice.id, v_allocated_amount, FALSE, p_payment_date
      ) RETURNING id INTO v_allocation_id;

      v_allocations := v_allocations || jsonb_build_object(
        'invoice_id', v_invoice.id,
        'invoice_number', v_invoice.invoice_number,
        'billing_cycle', v_invoice.billing_cycle,
        'amount_allocated', v_allocated_amount,
        'new_remaining', v_new_remaining,
        'status', v_new_status
      );

      v_remaining_to_distribute := ROUND(v_remaining_to_distribute - v_allocated_amount, 2);
    END IF;
  END LOOP;

  -- 7. Handle Overpayment: Credit Ledger Deposit
  IF v_remaining_to_distribute > 0 THEN
    v_credit_amount := v_remaining_to_distribute;
    
    INSERT INTO public.customer_credits (
      customer_id, payment_id, amount, remaining_amount, status, created_at
    ) VALUES (
      p_customer_id, v_payment_id, v_credit_amount, v_credit_amount, 'AVAILABLE', p_payment_date
    );

    UPDATE public.customers
    SET balance = ROUND(balance + v_credit_amount, 2),
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_customer_id;
  END IF;

  -- 8. Recalculate Total Remaining Debt and Total Available Credit
  SELECT COALESCE(SUM(remaining_amount), 0.00) INTO v_updated_debt 
  FROM public.invoices
  WHERE customer_id = p_customer_id AND status IN ('Unpaid', 'Partially_Paid') AND approval_status = 'APPROVED';

  SELECT COALESCE(SUM(remaining_amount), 0.00) INTO v_total_credit_available
  FROM public.customer_credits
  WHERE customer_id = p_customer_id AND status = 'AVAILABLE';

  UPDATE public.customers
  SET total_due = v_updated_debt,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_customer_id;

  -- 9. Security Audit Logging
  INSERT INTO public.audit_logs (
    action, entity, entity_id, user_id, details, created_at
  ) VALUES (
    'PAYMENT_SUBMIT_FIFO', 'Payment', v_payment_id::TEXT, p_actor_user_id,
    'تحصيل دفعة مالية بقيمة ' || p_amount_paid || ' ر.ي للمشترك: ' || v_customer.full_name || 
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
    'allocated_total', ROUND(p_amount_paid - v_credit_amount, 2),
    'credit_balance', v_credit_amount,
    'total_credit_available', v_total_credit_available,
    'remaining_debt', v_updated_debt,
    'allocations', v_allocations
  );
END;
$$;


ALTER FUNCTION public.rpc_submit_payment(p_customer_id bigint, p_amount_paid numeric, p_payment_method text, p_collector_name text, p_idempotency_key uuid, p_notes text, p_payment_date timestamp with time zone, p_invoice_id bigint, p_actor_user_id bigint, p_shift_id bigint) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.audit_logs (
    id bigint NOT NULL,
    user_id bigint,
    action character varying(50) NOT NULL,
    entity character varying(50) NOT NULL,
    entity_id character varying(100),
    details text,
    ip_address character varying(50),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.audit_logs OWNER TO postgres;

--
-- Name: audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.audit_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.audit_logs_id_seq OWNER TO postgres;

--
-- Name: audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.audit_logs_id_seq OWNED BY public.audit_logs.id;


--
-- Name: billing_cycles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.billing_cycles (
    id bigint NOT NULL,
    code character varying(50) NOT NULL,
    name character varying(100) NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    due_date date NOT NULL,
    status character varying(20) DEFAULT 'OPEN'::character varying NOT NULL,
    total_consumption numeric(12,2) DEFAULT 0.00 NOT NULL,
    total_amount numeric(12,2) DEFAULT 0.00 NOT NULL,
    total_paid numeric(12,2) DEFAULT 0.00 NOT NULL,
    total_arrears numeric(12,2) DEFAULT 0.00 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_cycles_dates CHECK (((end_date >= start_date) AND (due_date >= end_date))),
    CONSTRAINT chk_cycles_status CHECK (((status)::text = ANY (ARRAY[('OPEN'::character varying)::text, ('CLOSED'::character varying)::text, ('ARCHIVED'::character varying)::text]))),
    CONSTRAINT chk_cycles_totals CHECK (((total_consumption >= (0)::numeric) AND (total_amount >= (0)::numeric) AND (total_paid >= (0)::numeric) AND (total_arrears >= (0)::numeric)))
);


ALTER TABLE public.billing_cycles OWNER TO postgres;

--
-- Name: billing_cycles_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.billing_cycles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.billing_cycles_id_seq OWNER TO postgres;

--
-- Name: billing_cycles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.billing_cycles_id_seq OWNED BY public.billing_cycles.id;


--
-- Name: collector_customer_assignments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.collector_customer_assignments (
    id bigint NOT NULL,
    collector_user_id bigint NOT NULL,
    customer_id bigint NOT NULL,
    assigned_by_user_id bigint,
    assigned_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.collector_customer_assignments OWNER TO postgres;

--
-- Name: collector_customer_assignments_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.collector_customer_assignments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.collector_customer_assignments_id_seq OWNER TO postgres;

--
-- Name: collector_customer_assignments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.collector_customer_assignments_id_seq OWNED BY public.collector_customer_assignments.id;


--
-- Name: customer_credits; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.customer_credits (
    id bigint NOT NULL,
    customer_id bigint NOT NULL,
    payment_id bigint NOT NULL,
    amount numeric(12,2) NOT NULL,
    remaining_amount numeric(12,2) NOT NULL,
    status character varying(20) DEFAULT 'AVAILABLE'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_credits_amounts CHECK (((amount > (0)::numeric) AND (remaining_amount >= (0)::numeric) AND (remaining_amount <= amount))),
    CONSTRAINT chk_credits_status CHECK (((status)::text = ANY (ARRAY[('AVAILABLE'::character varying)::text, ('USED'::character varying)::text, ('EXPIRED'::character varying)::text])))
);


ALTER TABLE public.customer_credits OWNER TO postgres;

--
-- Name: customer_credits_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.customer_credits_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.customer_credits_id_seq OWNER TO postgres;

--
-- Name: customer_credits_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.customer_credits_id_seq OWNED BY public.customer_credits.id;


--
-- Name: customers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.customers (
    id bigint NOT NULL,
    subscriber_number character varying(50) NOT NULL,
    full_name character varying(100) NOT NULL,
    phone_number character varying(30) NOT NULL,
    id_card_url text,
    address text,
    meter_number character varying(50),
    route_number character varying(50),
    subscription_plan_id bigint,
    initial_reading numeric(12,2) DEFAULT 0.00 NOT NULL,
    last_reading numeric(12,2) DEFAULT 0.00 NOT NULL,
    total_due numeric(12,2) DEFAULT 0.00 NOT NULL,
    balance numeric(12,2) DEFAULT 0.00 NOT NULL,
    status character varying(20) DEFAULT 'Active'::character varying NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    test_run_id character varying(100),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    start_cycle character varying(50) DEFAULT '2026-08-1'::character varying NOT NULL,
    sort_order integer DEFAULT 0,
    CONSTRAINT chk_customers_balance CHECK ((balance >= (0)::numeric)),
    CONSTRAINT chk_customers_readings CHECK (((initial_reading >= (0)::numeric) AND (last_reading >= (0)::numeric))),
    CONSTRAINT chk_customers_status CHECK (((status)::text = ANY (ARRAY[('Active'::character varying)::text, ('Suspended'::character varying)::text, ('Disconnected'::character varying)::text, ('Terminated'::character varying)::text])))
);


ALTER TABLE public.customers OWNER TO postgres;

--
-- Name: customers_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.customers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.customers_id_seq OWNER TO postgres;

--
-- Name: customers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.customers_id_seq OWNED BY public.customers.id;


--
-- Name: invoices; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.invoices (
    id bigint NOT NULL,
    invoice_number character varying(100) NOT NULL,
    customer_id bigint NOT NULL,
    reading_id bigint,
    cycle_id bigint,
    billing_cycle character varying(50) NOT NULL,
    previous_reading numeric(12,2) DEFAULT 0.00 NOT NULL,
    current_reading numeric(12,2) DEFAULT 0.00 NOT NULL,
    consumption numeric(12,2) DEFAULT 0.00 NOT NULL,
    consumption_value numeric(12,2) DEFAULT 0.00 NOT NULL,
    kwh_price_snapshot numeric(12,2) NOT NULL,
    fixed_fee_snapshot numeric(12,2) DEFAULT 0.00 NOT NULL,
    arrears numeric(12,2) DEFAULT 0.00 NOT NULL,
    total_due numeric(12,2) DEFAULT 0.00 NOT NULL,
    total_amount numeric(12,2) DEFAULT 0.00 NOT NULL,
    paid_amount numeric(12,2) DEFAULT 0.00 NOT NULL,
    remaining_amount numeric(12,2) DEFAULT 0.00 NOT NULL,
    due_date date NOT NULL,
    approval_status character varying(20) DEFAULT 'APPROVED'::character varying NOT NULL,
    status character varying(20) DEFAULT 'Unpaid'::character varying NOT NULL,
    is_meter_reset boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    whatsapp_sent_at timestamp with time zone,
    is_printed boolean DEFAULT false,
    CONSTRAINT chk_invoices_approval CHECK (((approval_status)::text = ANY (ARRAY[('APPROVED'::character varying)::text, ('PENDING'::character varying)::text, ('REJECTED'::character varying)::text]))),
    CONSTRAINT chk_invoices_financials CHECK (((consumption_value >= (0)::numeric) AND (kwh_price_snapshot >= (0)::numeric) AND (fixed_fee_snapshot >= (0)::numeric) AND (paid_amount >= (0)::numeric))),
    CONSTRAINT chk_invoices_monotonic CHECK (((is_meter_reset = true) OR (current_reading = (0)::numeric) OR (current_reading >= previous_reading))),
    CONSTRAINT chk_invoices_number_pattern CHECK (((invoice_number)::text ~ '^INV-[A-Za-z0-9_ء-ي\-]+-[A-Za-z0-9_\-]+$'::text)),
    CONSTRAINT chk_invoices_readings CHECK (((previous_reading >= (0)::numeric) AND (current_reading >= (0)::numeric) AND (consumption >= (0)::numeric))),
    CONSTRAINT chk_invoices_status CHECK (((status)::text = ANY (ARRAY[('Unpaid'::character varying)::text, ('Partially_Paid'::character varying)::text, ('Paid'::character varying)::text, ('Cancelled'::character varying)::text, ('Void'::character varying)::text, ('Pending_Approval'::character varying)::text])))
);


ALTER TABLE public.invoices OWNER TO postgres;

--
-- Name: invoices_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.invoices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.invoices_id_seq OWNER TO postgres;

--
-- Name: invoices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.invoices_id_seq OWNED BY public.invoices.id;


--
-- Name: meter_readings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.meter_readings (
    id bigint NOT NULL,
    customer_id bigint NOT NULL,
    cycle_id bigint,
    reading_value numeric(12,2) NOT NULL,
    previous_reading numeric(12,2) DEFAULT 0.00 NOT NULL,
    consumption numeric(12,2) DEFAULT 0.00 NOT NULL,
    reading_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    collector_name character varying(100) NOT NULL,
    collector_user_id bigint,
    approval_status character varying(20) DEFAULT 'APPROVED'::character varying NOT NULL,
    client_mutation_id uuid DEFAULT gen_random_uuid() NOT NULL,
    rejection_reason text,
    whatsapp_sent boolean DEFAULT false NOT NULL,
    is_meter_reset boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_meter_readings_amounts CHECK (((reading_value >= (0)::numeric) AND (previous_reading >= (0)::numeric) AND (consumption >= (0)::numeric))),
    CONSTRAINT chk_meter_readings_approval CHECK (((approval_status)::text = ANY (ARRAY[('APPROVED'::character varying)::text, ('PENDING'::character varying)::text, ('REJECTED'::character varying)::text]))),
    CONSTRAINT chk_meter_readings_monotonic CHECK (((is_meter_reset = true) OR (reading_value = (0)::numeric) OR (reading_value >= previous_reading)))
);


ALTER TABLE public.meter_readings OWNER TO postgres;

--
-- Name: meter_readings_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.meter_readings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.meter_readings_id_seq OWNER TO postgres;

--
-- Name: meter_readings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.meter_readings_id_seq OWNED BY public.meter_readings.id;


--
-- Name: payment_allocations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.payment_allocations (
    id bigint NOT NULL,
    payment_id bigint NOT NULL,
    invoice_id bigint NOT NULL,
    amount_allocated numeric(12,2) NOT NULL,
    is_reversed boolean DEFAULT false NOT NULL,
    reversed_at timestamp with time zone,
    reversal_reason text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_allocations_amount CHECK ((amount_allocated > (0)::numeric))
);


ALTER TABLE public.payment_allocations OWNER TO postgres;

--
-- Name: payment_allocations_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.payment_allocations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.payment_allocations_id_seq OWNER TO postgres;

--
-- Name: payment_allocations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.payment_allocations_id_seq OWNED BY public.payment_allocations.id;


--
-- Name: payment_receipt_counters; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.payment_receipt_counters (
    year integer NOT NULL,
    last_value bigint DEFAULT 0 NOT NULL,
    CONSTRAINT chk_receipt_counter_val CHECK ((last_value >= 0))
);


ALTER TABLE public.payment_receipt_counters OWNER TO postgres;

--
-- Name: payments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.payments (
    id bigint NOT NULL,
    receipt_number character varying(50) NOT NULL,
    customer_id bigint NOT NULL,
    invoice_id bigint,
    shift_id bigint,
    payment_method character varying(20) DEFAULT 'CASH'::character varying NOT NULL,
    amount_paid numeric(12,2) NOT NULL,
    payment_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    accountant_name character varying(100) NOT NULL,
    accountant_user_id bigint,
    approval_status character varying(20) DEFAULT 'APPROVED'::character varying NOT NULL,
    notes text,
    client_mutation_id uuid DEFAULT gen_random_uuid() NOT NULL,
    rejection_reason text,
    whatsapp_sent boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_payments_amount CHECK ((amount_paid > (0)::numeric)),
    CONSTRAINT chk_payments_approval CHECK (((approval_status)::text = ANY (ARRAY[('APPROVED'::character varying)::text, ('PENDING'::character varying)::text, ('REJECTED'::character varying)::text]))),
    CONSTRAINT chk_payments_method CHECK (((payment_method)::text = ANY (ARRAY[('CASH'::character varying)::text, ('TRANSFER'::character varying)::text, ('BANK_TRANSFER'::character varying)::text, ('BANK'::character varying)::text, ('KURAMI'::character varying)::text, ('KURSHI'::character varying)::text, ('OTHER'::character varying)::text])))
);


ALTER TABLE public.payments OWNER TO postgres;

--
-- Name: payments_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.payments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.payments_id_seq OWNER TO postgres;

--
-- Name: payments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.payments_id_seq OWNED BY public.payments.id;


--
-- Name: subscription_plans; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.subscription_plans (
    id bigint NOT NULL,
    plan_name character varying(50) NOT NULL,
    kwh_price numeric(12,2) NOT NULL,
    fixed_fee numeric(12,2) DEFAULT 0.00 NOT NULL,
    grace_period_days integer DEFAULT 10 NOT NULL,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_plans_prices CHECK (((kwh_price >= (0)::numeric) AND (fixed_fee >= (0)::numeric) AND (grace_period_days >= 0)))
);


ALTER TABLE public.subscription_plans OWNER TO postgres;

--
-- Name: plans; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.plans AS
 SELECT id,
    plan_name,
    kwh_price,
    fixed_fee,
    grace_period_days,
    description,
    is_active,
    created_at,
    updated_at
   FROM public.subscription_plans;


ALTER VIEW public.plans OWNER TO postgres;

--
-- Name: system_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.system_settings (
    id bigint NOT NULL,
    station_name character varying(100) DEFAULT 'محطة الضياء لتوليد الطاقة الكهربائية'::character varying NOT NULL,
    station_logo_url text,
    station_phone character varying(100) DEFAULT '+967 783270260'::character varying NOT NULL,
    station_phone_alt character varying(100) DEFAULT '+967 736955883'::character varying,
    bank_accounts text DEFAULT 'بنك الكريمي: 3052001225'::text,
    invoice_policy_text text DEFAULT '1- نرجو تسديد الفاتورة خلال فترة السماح المحددة تفادياً لفصل التيار.
2- في حال وجود أي اعتراض على القراءة يرجى مراجعة إدارة المحطة خلال 48 ساعة.
3- إعادة التيار بعد الفصل تتطلب سداد الرسوم المقررة.
4- المشترك مسؤول عن سلامة العداد والوصلات التابعة له.
5- استخدام الطاقة في غير الغرض المخصص يعرض المشترك للمساءلة.'::text,
    whatsapp_status character varying(20) DEFAULT 'Disconnected'::character varying NOT NULL,
    receipt_footer character varying(255) DEFAULT 'شكراً لاختياركم خدماتنا - نرجو المحافظة على الطاقة'::character varying,
    arrears_threshold numeric(12,2) DEFAULT 0.00 NOT NULL,
    default_kwh_price numeric(12,2) DEFAULT 1000.00 NOT NULL,
    default_fixed_fee numeric(12,2) DEFAULT 1000.00 NOT NULL,
    max_overdue_days integer DEFAULT 7 NOT NULL,
    currency character varying(10) DEFAULT 'YER'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_settings_prices CHECK (((default_kwh_price >= (0)::numeric) AND (default_fixed_fee >= (0)::numeric) AND (arrears_threshold >= (0)::numeric) AND (max_overdue_days >= 0)))
);


ALTER TABLE public.system_settings OWNER TO postgres;

--
-- Name: settings; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.settings AS
 SELECT id,
    station_name,
    station_logo_url,
    station_phone,
    station_phone_alt,
    bank_accounts,
    invoice_policy_text,
    whatsapp_status,
    receipt_footer,
    arrears_threshold,
    default_kwh_price,
    default_fixed_fee,
    max_overdue_days,
    currency,
    created_at,
    updated_at
   FROM public.system_settings;


ALTER VIEW public.settings OWNER TO postgres;

--
-- Name: shifts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.shifts (
    id bigint NOT NULL,
    user_id bigint,
    cashier_name character varying(100) NOT NULL,
    start_time timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    end_time timestamp with time zone,
    starting_cash numeric(12,2) DEFAULT 0.00 NOT NULL,
    ending_cash numeric(12,2),
    total_collected numeric(12,2) DEFAULT 0.00 NOT NULL,
    status character varying(20) DEFAULT 'OPEN'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_shifts_cash CHECK (((starting_cash >= (0)::numeric) AND ((ending_cash IS NULL) OR (ending_cash >= (0)::numeric)) AND (total_collected >= (0)::numeric))),
    CONSTRAINT chk_shifts_status CHECK (((status)::text = ANY (ARRAY[('OPEN'::character varying)::text, ('CLOSED'::character varying)::text])))
);


ALTER TABLE public.shifts OWNER TO postgres;

--
-- Name: shifts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.shifts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.shifts_id_seq OWNER TO postgres;

--
-- Name: shifts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.shifts_id_seq OWNED BY public.shifts.id;


--
-- Name: subscription_plans_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.subscription_plans_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.subscription_plans_id_seq OWNER TO postgres;

--
-- Name: subscription_plans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.subscription_plans_id_seq OWNED BY public.subscription_plans.id;


--
-- Name: sync_checkpoints; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sync_checkpoints (
    table_name character varying(50) NOT NULL,
    last_synced_id bigint DEFAULT 0,
    last_synced_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.sync_checkpoints OWNER TO postgres;

--
-- Name: sync_outbox; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sync_outbox (
    id bigint NOT NULL,
    table_name character varying(50) NOT NULL,
    record_id bigint NOT NULL,
    operation character varying(10) NOT NULL,
    payload jsonb NOT NULL,
    status character varying(20) DEFAULT 'PENDING'::character varying,
    attempts integer DEFAULT 0,
    last_error text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    synced_at timestamp with time zone
);


ALTER TABLE public.sync_outbox OWNER TO postgres;

--
-- Name: sync_outbox_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.sync_outbox_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sync_outbox_id_seq OWNER TO postgres;

--
-- Name: sync_outbox_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.sync_outbox_id_seq OWNED BY public.sync_outbox.id;


--
-- Name: system_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.system_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.system_settings_id_seq OWNER TO postgres;

--
-- Name: system_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.system_settings_id_seq OWNED BY public.system_settings.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    username character varying(50) NOT NULL,
    password_hash text NOT NULL,
    full_name character varying(100) NOT NULL,
    role character varying(20) DEFAULT 'CASHIER'::character varying NOT NULL,
    phone_number character varying(30),
    is_active boolean DEFAULT true NOT NULL,
    supabase_uid uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_users_role CHECK (((role)::text = ANY (ARRAY[('ADMIN'::character varying)::text, ('CASHIER'::character varying)::text, ('COLLECTOR'::character varying)::text]))),
    CONSTRAINT chk_users_username_len CHECK ((length(TRIM(BOTH FROM username)) >= 3))
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_id_seq OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: whatsapp_queue_messages; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.whatsapp_queue_messages (
    id bigint NOT NULL,
    phone_number character varying(30) NOT NULL,
    type character varying(20) DEFAULT 'TEXT'::character varying,
    message text,
    image_base64 text,
    caption text,
    media_path text,
    status character varying(20) DEFAULT 'PENDING'::character varying,
    retries bigint DEFAULT 0,
    max_retries bigint DEFAULT 3,
    error_msg text,
    source_entity character varying(30),
    source_id bigint,
    client_mutation_id uuid,
    scheduled_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    processing_started_at timestamp with time zone,
    sent_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_wa_queue_retries CHECK (((retries >= 0) AND (max_retries >= 0))),
    CONSTRAINT chk_wa_queue_status CHECK (((status)::text = ANY (ARRAY[('PENDING'::character varying)::text, ('PROCESSING'::character varying)::text, ('SENT'::character varying)::text, ('FAILED'::character varying)::text, ('CANCELLED'::character varying)::text]))),
    CONSTRAINT chk_wa_queue_type CHECK (((type)::text = ANY (ARRAY[('TEXT'::character varying)::text, ('IMAGE'::character varying)::text, ('INVOICE_PDF'::character varying)::text, ('PAYMENT_RECEIPT'::character varying)::text])))
);


ALTER TABLE public.whatsapp_queue_messages OWNER TO postgres;

--
-- Name: whatsapp_queue_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.whatsapp_queue_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.whatsapp_queue_messages_id_seq OWNER TO postgres;

--
-- Name: whatsapp_queue_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.whatsapp_queue_messages_id_seq OWNED BY public.whatsapp_queue_messages.id;


--
-- Name: whatsapp_sessions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.whatsapp_sessions (
    session_id character varying(100) NOT NULL,
    jid character varying(100),
    status character varying(20) DEFAULT 'DISCONNECTED'::character varying NOT NULL,
    qr_code text,
    push_name character varying(100),
    auth_data bytea,
    device_props jsonb,
    keys_data jsonb,
    is_active boolean DEFAULT true NOT NULL,
    last_connected_at timestamp with time zone,
    last_heartbeat_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_wa_session_status CHECK (((status)::text = ANY (ARRAY[('CONNECTED'::character varying)::text, ('DISCONNECTED'::character varying)::text, ('SCAN_QR_CODE'::character varying)::text, ('INITIALIZING'::character varying)::text])))
);


ALTER TABLE public.whatsapp_sessions OWNER TO postgres;

--
-- Name: whatsmeow_app_state_mutation_macs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.whatsmeow_app_state_mutation_macs (
    jid text NOT NULL,
    name text NOT NULL,
    version bigint NOT NULL,
    index_mac bytea NOT NULL,
    value_mac bytea NOT NULL,
    CONSTRAINT whatsmeow_app_state_mutation_macs_index_mac_check CHECK ((length(index_mac) = 32)),
    CONSTRAINT whatsmeow_app_state_mutation_macs_value_mac_check CHECK ((length(value_mac) = 32))
);


ALTER TABLE public.whatsmeow_app_state_mutation_macs OWNER TO postgres;

--
-- Name: whatsmeow_app_state_sync_keys; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.whatsmeow_app_state_sync_keys (
    jid text NOT NULL,
    key_id bytea NOT NULL,
    key_data bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    fingerprint bytea NOT NULL
);


ALTER TABLE public.whatsmeow_app_state_sync_keys OWNER TO postgres;

--
-- Name: whatsmeow_app_state_version; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.whatsmeow_app_state_version (
    jid text NOT NULL,
    name text NOT NULL,
    version bigint NOT NULL,
    hash bytea NOT NULL,
    CONSTRAINT whatsmeow_app_state_version_hash_check CHECK ((length(hash) = 128))
);


ALTER TABLE public.whatsmeow_app_state_version OWNER TO postgres;

--
-- Name: whatsmeow_chat_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.whatsmeow_chat_settings (
    our_jid text NOT NULL,
    chat_jid text NOT NULL,
    muted_until bigint DEFAULT 0 NOT NULL,
    pinned boolean DEFAULT false NOT NULL,
    archived boolean DEFAULT false NOT NULL
);


ALTER TABLE public.whatsmeow_chat_settings OWNER TO postgres;

--
-- Name: whatsmeow_contacts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.whatsmeow_contacts (
    our_jid text NOT NULL,
    their_jid text NOT NULL,
    first_name text,
    full_name text,
    push_name text,
    business_name text,
    redacted_phone text
);


ALTER TABLE public.whatsmeow_contacts OWNER TO postgres;

--
-- Name: whatsmeow_device; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.whatsmeow_device (
    jid text NOT NULL,
    lid text,
    facebook_uuid uuid,
    registration_id bigint NOT NULL,
    noise_key bytea NOT NULL,
    identity_key bytea NOT NULL,
    signed_pre_key bytea NOT NULL,
    signed_pre_key_id integer NOT NULL,
    signed_pre_key_sig bytea NOT NULL,
    adv_key bytea NOT NULL,
    adv_details bytea NOT NULL,
    adv_account_sig bytea NOT NULL,
    adv_account_sig_key bytea NOT NULL,
    adv_device_sig bytea NOT NULL,
    platform text DEFAULT ''::text NOT NULL,
    business_name text DEFAULT ''::text NOT NULL,
    push_name text DEFAULT ''::text NOT NULL,
    lid_migration_ts bigint DEFAULT 0 NOT NULL,
    companion_meta_nonce text DEFAULT ''::text NOT NULL,
    CONSTRAINT whatsmeow_device_adv_account_sig_check CHECK ((length(adv_account_sig) = 64)),
    CONSTRAINT whatsmeow_device_adv_account_sig_key_check CHECK ((length(adv_account_sig_key) = 32)),
    CONSTRAINT whatsmeow_device_adv_device_sig_check CHECK ((length(adv_device_sig) = 64)),
    CONSTRAINT whatsmeow_device_identity_key_check CHECK ((length(identity_key) = 32)),
    CONSTRAINT whatsmeow_device_noise_key_check CHECK ((length(noise_key) = 32)),
    CONSTRAINT whatsmeow_device_registration_id_check CHECK (((registration_id >= 0) AND (registration_id < '4294967296'::bigint))),
    CONSTRAINT whatsmeow_device_signed_pre_key_check CHECK ((length(signed_pre_key) = 32)),
    CONSTRAINT whatsmeow_device_signed_pre_key_id_check CHECK (((signed_pre_key_id >= 0) AND (signed_pre_key_id < 16777216))),
    CONSTRAINT whatsmeow_device_signed_pre_key_sig_check CHECK ((length(signed_pre_key_sig) = 64))
);


ALTER TABLE public.whatsmeow_device OWNER TO postgres;

--
-- Name: whatsmeow_event_buffer; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.whatsmeow_event_buffer (
    our_jid text NOT NULL,
    ciphertext_hash bytea NOT NULL,
    plaintext bytea,
    server_timestamp bigint NOT NULL,
    insert_timestamp bigint NOT NULL,
    CONSTRAINT whatsmeow_event_buffer_ciphertext_hash_check CHECK ((length(ciphertext_hash) = 32))
);


ALTER TABLE public.whatsmeow_event_buffer OWNER TO postgres;

--
-- Name: whatsmeow_identity_keys; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.whatsmeow_identity_keys (
    our_jid text NOT NULL,
    their_id text NOT NULL,
    identity bytea NOT NULL,
    CONSTRAINT whatsmeow_identity_keys_identity_check CHECK ((length(identity) = 32))
);


ALTER TABLE public.whatsmeow_identity_keys OWNER TO postgres;

--
-- Name: whatsmeow_lid_map; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.whatsmeow_lid_map (
    lid text NOT NULL,
    pn text NOT NULL
);


ALTER TABLE public.whatsmeow_lid_map OWNER TO postgres;

--
-- Name: whatsmeow_message_secrets; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.whatsmeow_message_secrets (
    our_jid text NOT NULL,
    chat_jid text NOT NULL,
    sender_jid text NOT NULL,
    message_id text NOT NULL,
    key bytea NOT NULL
);


ALTER TABLE public.whatsmeow_message_secrets OWNER TO postgres;

--
-- Name: whatsmeow_nct_salt; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.whatsmeow_nct_salt (
    our_jid text NOT NULL,
    salt bytea NOT NULL
);


ALTER TABLE public.whatsmeow_nct_salt OWNER TO postgres;

--
-- Name: whatsmeow_pre_keys; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.whatsmeow_pre_keys (
    jid text NOT NULL,
    key_id integer NOT NULL,
    key bytea NOT NULL,
    uploaded boolean NOT NULL,
    CONSTRAINT whatsmeow_pre_keys_key_check CHECK ((length(key) = 32)),
    CONSTRAINT whatsmeow_pre_keys_key_id_check CHECK (((key_id >= 0) AND (key_id < 16777216)))
);


ALTER TABLE public.whatsmeow_pre_keys OWNER TO postgres;

--
-- Name: whatsmeow_privacy_tokens; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.whatsmeow_privacy_tokens (
    our_jid text NOT NULL,
    their_jid text NOT NULL,
    token bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    sender_timestamp bigint
);


ALTER TABLE public.whatsmeow_privacy_tokens OWNER TO postgres;

--
-- Name: whatsmeow_retry_buffer; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.whatsmeow_retry_buffer (
    our_jid text NOT NULL,
    chat_jid text NOT NULL,
    message_id text NOT NULL,
    format text NOT NULL,
    plaintext bytea NOT NULL,
    "timestamp" bigint NOT NULL
);


ALTER TABLE public.whatsmeow_retry_buffer OWNER TO postgres;

--
-- Name: whatsmeow_sender_keys; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.whatsmeow_sender_keys (
    our_jid text NOT NULL,
    chat_id text NOT NULL,
    sender_id text NOT NULL,
    sender_key bytea NOT NULL
);


ALTER TABLE public.whatsmeow_sender_keys OWNER TO postgres;

--
-- Name: whatsmeow_sessions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.whatsmeow_sessions (
    our_jid text NOT NULL,
    their_id text NOT NULL,
    session bytea
);


ALTER TABLE public.whatsmeow_sessions OWNER TO postgres;

--
-- Name: whatsmeow_version; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.whatsmeow_version (
    version integer,
    compat integer
);


ALTER TABLE public.whatsmeow_version OWNER TO postgres;

--
-- Name: audit_logs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs ALTER COLUMN id SET DEFAULT nextval('public.audit_logs_id_seq'::regclass);


--
-- Name: billing_cycles id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.billing_cycles ALTER COLUMN id SET DEFAULT nextval('public.billing_cycles_id_seq'::regclass);


--
-- Name: collector_customer_assignments id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.collector_customer_assignments ALTER COLUMN id SET DEFAULT nextval('public.collector_customer_assignments_id_seq'::regclass);


--
-- Name: customer_credits id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_credits ALTER COLUMN id SET DEFAULT nextval('public.customer_credits_id_seq'::regclass);


--
-- Name: customers id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers ALTER COLUMN id SET DEFAULT nextval('public.customers_id_seq'::regclass);


--
-- Name: invoices id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.invoices ALTER COLUMN id SET DEFAULT nextval('public.invoices_id_seq'::regclass);


--
-- Name: meter_readings id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.meter_readings ALTER COLUMN id SET DEFAULT nextval('public.meter_readings_id_seq'::regclass);


--
-- Name: payment_allocations id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payment_allocations ALTER COLUMN id SET DEFAULT nextval('public.payment_allocations_id_seq'::regclass);


--
-- Name: payments id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments ALTER COLUMN id SET DEFAULT nextval('public.payments_id_seq'::regclass);


--
-- Name: shifts id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.shifts ALTER COLUMN id SET DEFAULT nextval('public.shifts_id_seq'::regclass);


--
-- Name: subscription_plans id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscription_plans ALTER COLUMN id SET DEFAULT nextval('public.subscription_plans_id_seq'::regclass);


--
-- Name: sync_outbox id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sync_outbox ALTER COLUMN id SET DEFAULT nextval('public.sync_outbox_id_seq'::regclass);


--
-- Name: system_settings id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.system_settings ALTER COLUMN id SET DEFAULT nextval('public.system_settings_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: whatsapp_queue_messages id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsapp_queue_messages ALTER COLUMN id SET DEFAULT nextval('public.whatsapp_queue_messages_id_seq'::regclass);


--
-- Data for Name: audit_logs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.audit_logs (id, user_id, action, entity, entity_id, details, ip_address, created_at) FROM stdin;
15	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-17 07:16:59.335254+03
16	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-17 07:17:05.585402+03
17	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-17 07:18:44.943328+03
23	1	READING_CREATE	READING	512	تسجيل قراءة عداد جديدة للمشترك رقم [511] - القراءة: [1050.00]	127.0.0.1	2026-09-17 07:18:59.272228+03
24	1	CREATE_PAYMENT	PAYMENT	REC-2026-000001	تم تحصيل سند قبض وسداد بمبلغ 16000.00 ريال وتوزيعه آلياً على 2 فاتورة مستحقة	127.0.0.1	2026-09-17 07:19:01.3225+03
25	1	READING_CREATE	READING	513	تسجيل قراءة عداد جديدة للمشترك رقم [512] - القراءة: [2050.00]	127.0.0.1	2026-09-17 07:19:03.39335+03
26	1	READING_CREATE	READING	514	تسجيل قراءة عداد جديدة للمشترك رقم [513] - القراءة: [3030.00]	127.0.0.1	2026-09-17 07:19:05.44849+03
27	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-17 07:19:32.170553+03
28	1	READING_CREATE	READING	515	تسجيل قراءة عداد جديدة للمشترك رقم [511] - القراءة: [1050.00]	127.0.0.1	2026-09-17 07:19:56.706531+03
29	1	CREATE_PAYMENT	PAYMENT	REC-2026-000002	تم تحصيل سند قبض وسداد بمبلغ 16000.00 ريال وتوزيعه آلياً على 1 فاتورة مستحقة	127.0.0.1	2026-09-17 07:19:58.774598+03
30	1	READING_CREATE	READING	516	تسجيل قراءة عداد جديدة للمشترك رقم [512] - القراءة: [2050.00]	127.0.0.1	2026-09-17 07:20:00.811002+03
31	1	READING_CREATE	READING	517	تسجيل قراءة عداد جديدة للمشترك رقم [513] - القراءة: [3030.00]	127.0.0.1	2026-09-17 07:20:02.858633+03
32	1	CREATE_PAYMENT	PAYMENT	REC-2026-000003	تم تحصيل سند قبض وسداد بمبلغ 60000.00 ريال وتوزيعه آلياً على 2 فاتورة مستحقة	127.0.0.1	2026-09-17 07:20:04.892231+03
33	1	READING_CREATE	READING	518	تسجيل قراءة عداد جديدة للمشترك رقم [514] - القراءة: [4040.00]	127.0.0.1	2026-09-17 07:20:06.937543+03
34	1	READING_CREATE	READING	519	تسجيل قراءة عداد جديدة للمشترك رقم [515] - القراءة: [5000.00]	127.0.0.1	2026-09-17 07:20:08.977742+03
35	1	READING_CREATE	READING	520	تسجيل قراءة عداد جديدة للمشترك رقم [511] - القراءة: [1100.00]	127.0.0.1	2026-09-17 07:20:11.013744+03
36	1	CREATE_PAYMENT	PAYMENT	REC-2026-000004	تم تحصيل سند قبض وسداد بمبلغ 16000.00 ريال وتوزيعه آلياً على 1 فاتورة مستحقة	127.0.0.1	2026-09-17 07:20:13.040548+03
37	1	READING_CREATE	READING	521	تسجيل قراءة عداد جديدة للمشترك رقم [512] - القراءة: [2100.00]	127.0.0.1	2026-09-17 07:20:15.091243+03
38	1	READING_CREATE	READING	522	تسجيل قراءة عداد جديدة للمشترك رقم [513] - القراءة: [3060.00]	127.0.0.1	2026-09-17 07:20:17.137616+03
39	1	READING_CREATE	READING	523	تسجيل قراءة عداد جديدة للمشترك رقم [514] - القراءة: [4080.00]	127.0.0.1	2026-09-17 07:20:19.179577+03
40	1	READING_CREATE	READING	524	تسجيل قراءة عداد جديدة للمشترك رقم [515] - القراءة: [5000.00]	127.0.0.1	2026-09-17 07:20:21.204387+03
41	1	CREATE_PAYMENT	PAYMENT	REC-2026-000005	تم تحصيل سند قبض وسداد بمبلغ 2000.00 ريال وتوزيعه آلياً على 2 فاتورة مستحقة	127.0.0.1	2026-09-17 07:20:23.242684+03
42	1	READING_CREATE	READING	525	تسجيل قراءة عداد جديدة للمشترك رقم [511] - القراءة: [1150.00]	127.0.0.1	2026-09-17 07:20:25.29253+03
43	1	CREATE_PAYMENT	PAYMENT	REC-2026-000006	تم تحصيل سند قبض وسداد بمبلغ 16000.00 ريال وتوزيعه آلياً على 1 فاتورة مستحقة	127.0.0.1	2026-09-17 07:20:27.353272+03
44	1	READING_CREATE	READING	526	تسجيل قراءة عداد جديدة للمشترك رقم [512] - القراءة: [2150.00]	127.0.0.1	2026-09-17 07:20:29.408488+03
45	1	READING_CREATE	READING	527	تسجيل قراءة عداد جديدة للمشترك رقم [513] - القراءة: [3090.00]	127.0.0.1	2026-09-17 07:20:31.443072+03
46	1	READING_CREATE	READING	528	تسجيل قراءة عداد جديدة للمشترك رقم [514] - القراءة: [4120.00]	127.0.0.1	2026-09-17 07:20:33.481429+03
47	1	CREATE_PAYMENT	PAYMENT	REC-2026-000007	تم تحصيل سند قبض وسداد بمبلغ 40000.00 ريال وتوزيعه آلياً على 1 فاتورة مستحقة	127.0.0.1	2026-09-17 07:20:35.53361+03
48	1	READING_CREATE	READING	529	تسجيل قراءة عداد جديدة للمشترك رقم [515] - القراءة: [5000.00]	127.0.0.1	2026-09-17 07:20:37.581065+03
49	1	READING_CREATE	READING	530	تسجيل قراءة عداد جديدة للمشترك رقم [511] - القراءة: [1200.00]	127.0.0.1	2026-09-17 07:20:39.656399+03
50	1	CREATE_PAYMENT	PAYMENT	REC-2026-000008	تم تحصيل سند قبض وسداد بمبلغ 16000.00 ريال وتوزيعه آلياً على 1 فاتورة مستحقة	127.0.0.1	2026-09-17 07:20:41.709832+03
51	1	READING_CREATE	READING	531	تسجيل قراءة عداد جديدة للمشترك رقم [512] - القراءة: [2200.00]	127.0.0.1	2026-09-17 07:20:43.753843+03
52	1	READING_CREATE	READING	532	تسجيل قراءة عداد جديدة للمشترك رقم [513] - القراءة: [3120.00]	127.0.0.1	2026-09-17 07:20:45.783456+03
53	1	READING_CREATE	READING	533	تسجيل قراءة عداد جديدة للمشترك رقم [514] - القراءة: [4160.00]	127.0.0.1	2026-09-17 07:20:47.837887+03
54	1	CREATE_PAYMENT	PAYMENT	REC-2026-000009	تم تحصيل سند قبض وسداد بمبلغ 13000.00 ريال وتوزيعه آلياً على 2 فاتورة مستحقة	127.0.0.1	2026-09-17 07:20:49.888334+03
55	1	READING_CREATE	READING	534	تسجيل قراءة عداد جديدة للمشترك رقم [515] - القراءة: [5000.00]	127.0.0.1	2026-09-17 07:20:51.939942+03
56	1	CREATE_PAYMENT	PAYMENT	REC-2026-000010	تم تحصيل سند قبض وسداد بمبلغ 2000.00 ريال وتوزيعه آلياً على 1 فاتورة مستحقة	127.0.0.1	2026-09-17 07:20:53.980883+03
57	1	READING_CREATE	READING	535	تسجيل قراءة عداد جديدة للمشترك رقم [511] - القراءة: [1250.00]	127.0.0.1	2026-09-17 07:20:56.048601+03
58	1	CREATE_PAYMENT	PAYMENT	REC-2026-000011	تم تحصيل سند قبض وسداد بمبلغ 16000.00 ريال وتوزيعه آلياً على 1 فاتورة مستحقة	127.0.0.1	2026-09-17 07:20:58.100834+03
59	1	READING_CREATE	READING	536	تسجيل قراءة عداد جديدة للمشترك رقم [512] - القراءة: [2250.00]	127.0.0.1	2026-09-17 07:21:00.165468+03
60	1	READING_CREATE	READING	537	تسجيل قراءة عداد جديدة للمشترك رقم [513] - القراءة: [3150.00]	127.0.0.1	2026-09-17 07:21:04.260144+03
61	1	READING_CREATE	READING	538	تسجيل قراءة عداد جديدة للمشترك رقم [514] - القراءة: [4200.00]	127.0.0.1	2026-09-17 07:21:06.310867+03
62	1	READING_CREATE	READING	539	تسجيل قراءة عداد جديدة للمشترك رقم [515] - القراءة: [5000.00]	127.0.0.1	2026-09-17 07:21:10.366453+03
63	1	READING_CREATE	READING	540	تسجيل قراءة عداد جديدة للمشترك رقم [511] - القراءة: [1300.00]	127.0.0.1	2026-09-17 07:21:12.408269+03
64	1	READING_CREATE	READING	541	تسجيل قراءة عداد جديدة للمشترك رقم [512] - القراءة: [2300.00]	127.0.0.1	2026-09-17 07:21:16.505617+03
65	1	READING_CREATE	READING	542	تسجيل قراءة عداد جديدة للمشترك رقم [513] - القراءة: [3180.00]	127.0.0.1	2026-09-17 07:21:18.541896+03
66	1	READING_CREATE	READING	543	تسجيل قراءة عداد جديدة للمشترك رقم [514] - القراءة: [4240.00]	127.0.0.1	2026-09-17 07:21:20.588949+03
67	1	READING_CREATE	READING	544	تسجيل قراءة عداد جديدة للمشترك رقم [515] - القراءة: [5000.00]	127.0.0.1	2026-09-17 07:21:24.674008+03
68	1	READING_CREATE	READING	545	تسجيل قراءة عداد جديدة للمشترك رقم [511] - القراءة: [1350.00]	127.0.0.1	2026-09-17 07:21:28.764076+03
69	1	READING_CREATE	READING	546	تسجيل قراءة عداد جديدة للمشترك رقم [512] - القراءة: [2350.00]	127.0.0.1	2026-09-17 07:21:32.814821+03
70	1	READING_CREATE	READING	547	تسجيل قراءة عداد جديدة للمشترك رقم [513] - القراءة: [3210.00]	127.0.0.1	2026-09-17 07:21:34.856528+03
71	1	READING_CREATE	READING	548	تسجيل قراءة عداد جديدة للمشترك رقم [514] - القراءة: [4280.00]	127.0.0.1	2026-09-17 07:21:38.919918+03
72	1	READING_CREATE	READING	549	تسجيل قراءة عداد جديدة للمشترك رقم [515] - القراءة: [5000.00]	127.0.0.1	2026-09-17 07:21:42.998173+03
73	1	READING_CREATE	READING	550	تسجيل قراءة عداد جديدة للمشترك رقم [511] - القراءة: [1400.00]	127.0.0.1	2026-09-17 07:21:45.032308+03
74	1	READING_CREATE	READING	551	تسجيل قراءة عداد جديدة للمشترك رقم [512] - القراءة: [2400.00]	127.0.0.1	2026-09-17 07:21:49.076877+03
75	1	READING_CREATE	READING	552	تسجيل قراءة عداد جديدة للمشترك رقم [513] - القراءة: [3240.00]	127.0.0.1	2026-09-17 07:21:51.12828+03
76	1	READING_CREATE	READING	553	تسجيل قراءة عداد جديدة للمشترك رقم [514] - القراءة: [4320.00]	127.0.0.1	2026-09-17 07:21:55.22781+03
77	1	READING_CREATE	READING	554	تسجيل قراءة عداد جديدة للمشترك رقم [515] - القراءة: [5000.00]	127.0.0.1	2026-09-17 07:21:59.319576+03
78	1	READING_CREATE	READING	555	تسجيل قراءة عداد جديدة للمشترك رقم [511] - القراءة: [1450.00]	127.0.0.1	2026-09-17 07:22:03.403256+03
79	1	READING_CREATE	READING	556	تسجيل قراءة عداد جديدة للمشترك رقم [512] - القراءة: [2450.00]	127.0.0.1	2026-09-17 07:22:07.525495+03
80	1	READING_CREATE	READING	557	تسجيل قراءة عداد جديدة للمشترك رقم [513] - القراءة: [3270.00]	127.0.0.1	2026-09-17 07:22:09.557839+03
81	1	READING_CREATE	READING	558	تسجيل قراءة عداد جديدة للمشترك رقم [514] - القراءة: [4360.00]	127.0.0.1	2026-09-17 07:22:13.652474+03
82	1	READING_CREATE	READING	559	تسجيل قراءة عداد جديدة للمشترك رقم [515] - القراءة: [5000.00]	127.0.0.1	2026-09-17 07:22:17.732541+03
83	1	READING_CREATE	READING	560	تسجيل قراءة عداد جديدة للمشترك رقم [511] - القراءة: [1500.00]	127.0.0.1	2026-09-17 07:22:19.769861+03
84	1	READING_CREATE	READING	561	تسجيل قراءة عداد جديدة للمشترك رقم [512] - القراءة: [2500.00]	127.0.0.1	2026-09-17 07:22:23.834943+03
85	1	READING_CREATE	READING	562	تسجيل قراءة عداد جديدة للمشترك رقم [513] - القراءة: [3300.00]	127.0.0.1	2026-09-17 07:22:25.896024+03
86	1	READING_CREATE	READING	563	تسجيل قراءة عداد جديدة للمشترك رقم [514] - القراءة: [4400.00]	127.0.0.1	2026-09-17 07:22:29.977708+03
87	1	READING_CREATE	READING	564	تسجيل قراءة عداد جديدة للمشترك رقم [515] - القراءة: [5000.00]	127.0.0.1	2026-09-17 07:22:34.084243+03
88	1	READING_CREATE	READING	565	تسجيل قراءة عداد جديدة للمشترك رقم [511] - القراءة: [1550.00]	127.0.0.1	2026-09-17 07:22:38.156709+03
89	1	READING_CREATE	READING	566	تسجيل قراءة عداد جديدة للمشترك رقم [512] - القراءة: [2550.00]	127.0.0.1	2026-09-17 07:22:42.226126+03
90	1	READING_CREATE	READING	567	تسجيل قراءة عداد جديدة للمشترك رقم [513] - القراءة: [3330.00]	127.0.0.1	2026-09-17 07:22:44.296952+03
91	1	READING_CREATE	READING	568	تسجيل قراءة عداد جديدة للمشترك رقم [514] - القراءة: [4440.00]	127.0.0.1	2026-09-17 07:22:48.413043+03
92	1	READING_CREATE	READING	569	تسجيل قراءة عداد جديدة للمشترك رقم [515] - القراءة: [5000.00]	127.0.0.1	2026-09-17 07:22:52.477944+03
93	1	READING_CREATE	READING	570	تسجيل قراءة عداد جديدة للمشترك رقم [511] - القراءة: [1600.00]	127.0.0.1	2026-09-17 07:22:54.531986+03
94	1	READING_CREATE	READING	571	تسجيل قراءة عداد جديدة للمشترك رقم [512] - القراءة: [2600.00]	127.0.0.1	2026-09-17 07:22:58.60603+03
95	1	READING_CREATE	READING	572	تسجيل قراءة عداد جديدة للمشترك رقم [513] - القراءة: [3360.00]	127.0.0.1	2026-09-17 07:23:00.652906+03
96	1	READING_CREATE	READING	573	تسجيل قراءة عداد جديدة للمشترك رقم [514] - القراءة: [4480.00]	127.0.0.1	2026-09-17 07:23:04.742678+03
97	1	READING_CREATE	READING	574	تسجيل قراءة عداد جديدة للمشترك رقم [515] - القراءة: [5000.00]	127.0.0.1	2026-09-17 07:23:08.861932+03
98	1	CUSTOMER_DELETE	CUSTOMER	511	تم حذف المشترك رقم [511]	127.0.0.1	2026-09-17 07:23:38.122907+03
99	1	CUSTOMER_DELETE	CUSTOMER	512	تم حذف المشترك رقم [512]	127.0.0.1	2026-09-17 07:23:40.165409+03
100	1	CUSTOMER_DELETE	CUSTOMER	513	تم حذف المشترك رقم [513]	127.0.0.1	2026-09-17 07:23:42.197965+03
101	1	CUSTOMER_DELETE	CUSTOMER	514	تم حذف المشترك رقم [514]	127.0.0.1	2026-09-17 07:23:44.228089+03
102	1	CUSTOMER_DELETE	CUSTOMER	515	تم حذف المشترك رقم [515]	127.0.0.1	2026-09-17 07:23:46.265707+03
103	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-17 07:34:44.036557+03
104	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-17 07:42:19.931772+03
105	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-17 07:42:27.747645+03
106	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-17 07:43:04.217154+03
107	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-17 07:50:01.720188+03
108	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-17 07:57:17.369121+03
109	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-17 08:14:43.797952+03
\.


--
-- Data for Name: billing_cycles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.billing_cycles (id, code, name, start_date, end_date, due_date, status, total_consumption, total_amount, total_paid, total_arrears, created_at, updated_at) FROM stdin;
1	أغسطس 2	دورة أغسطس 2	2026-08-01	2026-08-31	2026-09-10	OPEN	6062.00	8847000.00	1559120.00	6424700.00	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03
\.


--
-- Data for Name: collector_customer_assignments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.collector_customer_assignments (id, collector_user_id, customer_id, assigned_by_user_id, assigned_at) FROM stdin;
\.


--
-- Data for Name: customer_credits; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.customer_credits (id, customer_id, payment_id, amount, remaining_amount, status, created_at, updated_at) FROM stdin;
2	136	32	19200.00	19200.00	AVAILABLE	2026-09-16 22:12:12.696254+03	2026-09-16 22:12:12.696254+03
\.


--
-- Data for Name: customers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.customers (id, subscriber_number, full_name, phone_number, id_card_url, address, meter_number, route_number, subscription_plan_id, initial_reading, last_reading, total_due, balance, status, is_deleted, test_run_id, created_at, updated_at, start_cycle, sort_order) FROM stdin;
4	910226	مشترك 910226		\N	صنعاء	910226	0	1	1288.00	1288.00	2000.00	2000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	417
51	910011	منزل عمار المحسن ج رشيد	772281276	\N	الخزانات	202003034236	13	1	670.00	680.00	35600.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	18
62	910012	منزل الدكتور رشيد	777739388	\N	الخزانات	202003034225	14	1	550.00	553.00	21600.00	21600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	19
63	910525	حسان عبدالكريم هزاع	770523605	\N	الخزانات ج رشيد	20230527604	14	1	169.00	169.00	1000.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	20
80	910307	منزل محمد البارقي	730876328	\N	الخزانات ج الدكتور رشيد	2408092824	15	1	127.00	130.00	13100.00	13100.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	21
93	910015	منزل وجدي عصام	777889331	\N	الخزانات	200321239	16	1	1118.00	1127.00	13600.00	13600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	22
104	910437	محمد عبدالله عبدالرحمن احمد	735889404	\N	جوار المهندس عصام	241016068447	17	1	85.00	105.00	29000.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	23
115	910390	منزل عبدالله صغير حمود	739751153	\N	عقبة ج فاروق عبدالقدوس	241016065843	18	1	96.00	100.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	24
116	910442	حبيب عبدالغني 2	774325012	\N	عقبه ج فاروق عبدالقدوس	910442	18	1	58.00	59.00	8200.00	8200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	25
117	910444	صقر مختار عبدالله الشريف	739123770	\N	الخزانات جار بشير العريفي	241016064895	18	1	362.00	367.00	8100.00	1100.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	26
133	910382	منزل عبدالملك سليمان	775390908	\N	عقبة ج فاروق عبدالقدوس	202005104789	19	1	1857.00	1896.00	55600.00	55600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	27
146	910288	ماجد احمد مسعد الطيار	773485109	\N	عقبة بدل فاروق عبدالقدوس	202408083136	20	1	498.00	512.00	20600.00	600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	28
157	910414	منزل محمد عبداللطيف محمد البعداني	739780283	\N	عقبة ج فاروق عبدالقدوس	202409029780	21	1	159.00	162.00	5200.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	29
171	910289	منزل وليد احمد عبدالجليل الاغبري	738482282	\N	عقبة جوارفاروق عبدالقدوس	2408080630	22	1	727.00	752.00	36000.00	36000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	30
185	910337	منزل ماجدعبدالله قائد الزرعي	735047834	\N	عقبة ج حذيفة الاجعش	202408096422	23	1	325.00	332.00	10800.00	10800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	31
195	910028	بقالة يوسف شعبان	774368015	\N	عقبة	2019110784	24	1	2324.00	2324.00	1000.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	32
206	910285	ام محمد نجيب	735603805	\N	عقبة مقابل بقالةشعبان	202408080573	25	1	190.00	196.00	9400.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	33
219	910461	محمد علي احمد سيف المعمري	771298426	\N	عقبةج  فاروق عبدالقدوس	202003029209	26	1	220.00	220.00	1000.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	34
220	910547	فضل علي احمد الجهيم	735842567	\N	عقبة ج عمارة فهد	250900092539	26	1	44.00	151.00	150800.00	150800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	35
237	910030	منزل حذيفه الاجعش	775042103	\N	عقبة	202308014076	27	1	337.00	343.00	9400.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	37
238	910535	فهد عبدالله احمد سعيد	777327600	\N	عقبة ج جامع الهدئ	2401010774	27	1	228.00	242.00	20600.00	20600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	36
248	910336	بقالة عبدالجليل محمدالشرعبي	738905666	\N	عقبة ج حذيفة الاجعش	202009064748	28	1	566.00	574.00	12200.00	12200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	38
261	910258	منزل وهيب عبدالعزيزالصلوي	738001289	\N	عقبةج  يوسف شعبان	202401059500	29	1	391.00	391.00	2000.00	2000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	39
274	910033	منزل احمد علي راجح	734927701	\N	عقبة	2210106289	30	1	231.00	239.00	81200.00	81200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	40
286	910034	منزل سمير الصامت	733114459	\N	عقبة	2008287422	31	1	1418.00	1453.00	57800.00	7800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	41
287	910538	عاهد محمد عبالله احمد	775204317	\N	عقبة ج سمير الصامت	202508000840	31	1	74.00	88.00	42600.00	42600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	42
300	910036	منزل هيثم ناجي المحيا	734583665	\N	عقبة	22008273564	32	1	534.00	534.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	43
314	910037	اللمنيوم اسامة الحاج	733929451	\N	عقبة	13285	33	1	2462.00	2482.00	29000.00	29000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	44
325	910035	منزل بلال عبدالحميداحمدالحاج	008619-8221-57943	\N	عقبة	219153	34	1	752.00	775.00	33800.00	33800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	45
339	910265	منزل ماجد الحاج عقبة	777771494	\N	عقبة ج أسامة الحاج	24101607396	35	1	156.00	160.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	46
353	910412	منزل هشام ناجي محمد سعيد غالب	772750752	\N	عقبة ج أسامة الحاج	24010696	36	1	1872.00	1953.00	133600.00	133600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	47
365	910479	احمد نبيل الكدهي	773824282	\N	عقبة ج هشام ناجي	202408095987	37	1	326.00	326.00	170900.00	170900.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	48
377	910038	منزل هاني قاىد الشريف	737236776	\N	عقبةج المحطة	214008	38	1	553.00	559.00	9400.00	9400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	49
386	910039	منزل عمراحمدمهيوب	737088954	\N	عقبة	202008285783	39	1	449.00	452.00	5200.00	5200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	50
399	910407	منزل مصطفئ نجيب مصطفئ الاديمي	775268423	\N	عقبة جوار محطة ديني	202303081435	40	1	203.00	213.00	28600.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	51
409	910032	ديني دحان.محطة عقبة	771366890	\N	عقبة	202204289650	41	1	139.00	139.00	9200.00	9200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	52
414	910102	منزل محمد الزبيدي	738062237	\N	الحارثي	327325	42	1	1729.00	1754.00	36000.00	36000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	54
415	910519	محمد احمد محمود طاهر	736508006	\N	بقالة عقبة ج الجامع	202003038624	42	1	1580.00	1580.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	55
416	910523	مروان محمد بجاش	770153175	\N	عقبة ج الجامع	202508006551	42	1	67.00	67.00	4400.00	4400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	53
419	910293	منزل ناجح عبدالله محمدهراش	772438412	\N	عقبة جوار الفرن	2088277131	43	1	227.00	227.00	9100.00	100.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	56
421	910260	عمرمحمد عبدالله حزام	714701653	\N	عقبةجوارناجح	202310068966	44	1	440.00	460.00	29000.00	29000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	57
422	910522	يحيئ محمد ناجي حسام	777784454	\N	عقبة ج ناجح	202508007220	45	1	13.00	13.00	11000.00	11000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	58
423	910027	منزل وليد الهمداني	739674447	\N	عقبة	22009065166	46	1	398.00	402.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	59
424	910331	منزل اصيل عبدالمومن الصبري	734715400	\N	عقبة جار بلال الغنام	202408096439	47	1	130.00	130.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	61
425	910356	منزل جديس محمد علي المحلوي	777451051	\N	عقبةج جامع التقوئ	241016060884	47	1	493.00	513.00	29000.00	29000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	60
426	910423	منزل محمد احمدسعيدنصاري	737625840	\N	عقبةجوار جديس	202409049360	48	1	238.00	238.00	4400.00	4400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	62
427	910564	محمد عبدة صلاح بجاش	733408020	\N	عقبة ج مصطفئ عبدةبجاش	250900102498	49	1	1.00	2.00	3400.00	3400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	63
430	910355	منزل مامون يحيئ عبدالله محمد الابي	773193232	\N	عقبة جوار جامع التقوئ	202409016476	50	1	104.00	104.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	64
431	910352	منزل مصطفئ عبدة صلاح بجاش	774949202	\N	عقبة جوار جامع التقوئ	202409034712	51	1	238.00	246.00	12200.00	12200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	65
432	910024	منزل فارس علي عبدالمجيدالدبعي	734137110	\N	عقبة ج جامع التقوى	214254	52	1	273.00	278.00	8000.00	8000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	66
433	910023	منزل تمام منصورمحمد الفاتش	771435180	\N	عقبةج جامع التقوى	215563	54	1	324.00	329.00	8000.00	8000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	67
434	910021	يوسف المخلافي ج مسجد التقوى	733502821	\N	الخزانات	201905008582	55	1	585.00	592.00	10800.00	10800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	68
435	910022	منزل عزمي قائداحمدج يوسف المخلافي	734716637	\N	جوار مدرسة العز	202003028395	56	1	699.00	722.00	33200.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	69
436	910247	منزل حاتم محمد احمد محمد	734926699	\N	عقبة ج فوادالمليكي	202409028591	57	1	66.00	70.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	70
437	910020	منزل فواد المليكي	777556899	\N	عقبة	22009079753	58	1	458.00	465.00	10800.00	10800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	71
438	910561	فائز شبكة السعيد	770273486	\N	عقبة ج فوادالمليكي	202008271197	58	1	616.00	648.00	45800.00	45800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	72
439	910018	منزل ذي يزن	739493871	\N	عقبة	20200280066	59	1	885.00	900.00	22000.00	22000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	73
442	910019	منزل محمد عبدالجبارعبدة	770549454	\N	عقبةج ذي يزن	202401010762	60	1	57.00	57.00	1000.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	74
443	910017	منير سرحان محمد	777123124	\N	جواروليدالهمداني	202204317601	61	1	168.00	172.00	7600.00	7600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	75
444	910013	منزل عبدالرحمن قاسم	783270260	\N	صنعاء	910013	62	1	112.00	112.00	28000.00	28000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	76
445	910309	منزل الصلوي ج الماطور	783270260	\N	فوق بيت نزار هائل	910309	63	1	330.00	337.00	39600.00	39600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	77
446	910556	جارنا محمد الزبيدي	783270260	\N	جوار المولد	910556	64	1	264.00	264.00	71600.00	71600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	78
447	910043	بقالةبسام يحيئ	783270260	\N	الخزانات	22003029263	65	1	589.00	589.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	79
448	910395	منزل إسماعيل ج المستهلك	+967737858686	\N	الخزانات ج المستهلك	241016095128	67	1	83.00	88.00	8200.00	8200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	80
449	910343	منزل ماجد علي حسن محمد	779516487	\N	الخزانات ج بقالة المستهلك	202408080826	68	1	239.00	239.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	81
450	910058	كندم الزبيدي	738062237	\N	الخزانات	257335	69	1	4016.00	4107.00	128400.00	128400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	82
452	910441	شهاب سعيد قائد سلطان	776690044	\N	الخزانات مقابل المشروع	241016068454	70	1	134.00	149.00	22000.00	22000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	83
453	910540	أسامة محطة الغاز	783270260	\N	الخزانات مدرسة الثلاياء	202210201407	70	1	1174.00	1174.00	19600.00	19600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	84
454	910565	محمد الزبيدي لحام	738062237	\N	كندم الزبيدي	202302028300	70	1	851.00	851.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	85
455	910057	مدرسة الثلاياء/طلال الفهيدي	775624241	\N	الخزانات	219142	71	1	627.00	645.00	26200.00	26200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	86
456	910455	علي عبدالله قائدالشوافي	735271027	\N	الخزانات ج إسماعيل	202303220673	72	1	356.00	370.00	42300.00	42300.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	87
457	910477	عبدالمولئ احمد عبدالفتاح المنيفي	777752106	\N	الخزانات ج المستهلك	250900006653	72	1	44.00	48.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	88
458	910041	وائل ثابت للخياطة	735036021	\N	العسكري	3034038	73	1	566.00	579.00	19200.00	19200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	89
459	910446	جميل محمد علي العبد	730873035	\N	الخزانات ج المستهلك	202401044088	74	1	286.00	295.00	13600.00	13600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	90
460	910468	نصر عمار احمدالثوبة	783270260	\N	الخزانات ج المستهلك	241128101399	74	1	48.00	48.00	45600.00	45600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	91
461	910040	منزل اكرم محمدعبدالله الراسني	730613351	\N	العسكري ج الضالعي	2304151626	75	1	132.00	135.00	9500.00	9500.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	92
462	910530	انس منير عبدالحافظ الهتاري	778882274	\N	العسكري ج وائل الخياط	202305217684	75	1	389.00	389.00	1200.00	1200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	93
463	910275	منزل محمدعبدالله احمد التبعي	774627557	\N	العسكري ج وائل الخياط	202401011615	76	1	340.00	347.00	10800.00	10800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	94
464	910500	رضاء منير عبدالحافظ الهتاري	770900693	\N	العسكري ج الهتاري	202508007252	76	1	55.00	62.00	10800.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	95
465	910521	اكرم قائد احمد الاعجم	775599558	\N	العسكري ج التبعي	202508006876	76	1	145.00	156.00	37400.00	37400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	96
466	910300	منزل حمزة عبدالمغني الصلاحي	770600465	\N	العسكري ج جامع السلام	910300	77	1	907.00	925.00	622900.00	622900.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	97
467	910531	عرفات اللهبي	774106774	\N	العسكري ج رضا الهتاري	202303090303	77	1	312.00	327.00	30000.00	30000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	98
469	910279	منزل عبدالجبار محمد عبدالفتاح الهتاري 1	778848182	\N	العسكري ج جامع السلام	202408080833	78	1	1322.00	1337.00	27600.00	27600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	99
470	910280	منزل عبدالجبار محمد عبدالفتاح الهتاري 2	733502350	\N	العسكري ج جامع السلام	202408080625	79	1	1614.00	1614.00	154600.00	154600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	100
472	910044	بوفية عبدالرحمن عبدة إسماعيل	730114142	\N	بوفية الخزانات	202401010771	80	1	191.00	197.00	16000.00	16000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	101
473	910045	بقالة ياسين محمد العريقي	783270260	\N	مقابل جامع الحميري	214033	81	1	249.00	249.00	25600.00	25600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	103
474	910303	منزل مياس هائل سعيد	783270260	\N	الخزانات ج جامع الحميري	20180664004	81	1	110.00	110.00	2000.00	2000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	102
475	910046	جامع الحميري	783270260	\N	صنعاء	202209701898	82	1	421.00	450.00	41600.00	41600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	104
476	910554	فواد الصبيحي السعيدة 1	777238977	\N	مبنا السعيدة	250900086323	82	1	33.00	44.00	16400.00	16400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	105
477	910555	عبدالحكيم السعيدة 2	739008141	\N	مبنا السعيدة	250900086239	82	1	40.00	48.00	23200.00	23200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	106
478	910273	منزل ام احمد0عفاف سليم العدني	774271401	\N	الخزانات ج عارف الشميري	2012154163	83	1	93.00	97.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	107
479	910557	هائل حميد حسن السعيدة 3	714747481	\N	مبنا السعيدة	250900086324	83	1	23.00	28.00	8800.00	8800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	108
480	910047	منزل  عارف نصرعلي الشميري	777102434	\N	جوار مبنا السعيدة	24010187	84	1	764.00	792.00	40200.00	40200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	109
481	910048	منزل محمدعبدالجبار دبوان الشميري	772759468	\N	مبنى السعيدة	214783	85	1	138.00	145.00	20200.00	20200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	110
482	910049	منزل احمد شيبان1	777211848	\N	السعيدة	3021077	86	1	2207.00	2235.00	40200.00	40200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	111
483	910050	منزل احمد شيبان2	777211848	\N	السعيدة	3035418	87	1	913.00	920.00	11900.00	11900.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	112
484	910051	منزل احمد شيبان3.	777211848	\N	السعيدة	3040118	88	1	1312.00	1360.00	68200.00	68200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	113
485	910053	احمد شيبان 4	770119626	\N	السعيدة	202008282038	89	1	532.00	540.00	26800.00	26800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	114
487	910052	منزل خالدمطهر السدمي	733264485	\N	السعيدة	202302019369	90	1	385.00	392.00	10800.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	115
488	910340	منزل وسيم قاسم احمد سنان	774944131	\N	بيت الدجاج ج حبيب عبدالغني	202408096440	91	1	203.00	205.00	9000.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	116
489	910481	نجيب احمد عبدالرحمن منصر	783270260	\N	بيت الدجاج  ج وسيم قاسم	202508002321	91	1	328.00	347.00	27600.00	27600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	117
490	910482	حميد علي صالح عبدالرحمن	734655468	\N	بيت الجاج ج وسيم قاسم	202508002546	91	1	37.00	41.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	118
491	910056	منزل حبيب عبدالغني عبدة علي	730457493	\N	بيت الدجاج	202305217740	92	1	357.00	364.00	11200.00	1200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	119
492	910054	منزل محمد عبدة عاقل سمير	771909975	\N	السعيد	202009078919	93	1	368.00	375.00	10800.00	10800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	120
493	910426	منزل علاءثابت مصلح صويلح	774937300	\N	السعيدة ج هاني الشدادي	241016063715	94	1	65.00	65.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	121
494	910055	منزل هاني محمدمنصورالشدادي	772781914	\N	السعيدةج عاقل سمير	219606	95	1	175.00	179.00	7400.00	7400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	122
495	910335	منزل عادل محمد الحناني	777639417	\N	الخزانات مقابل بقالة صدام	202408080822	96	1	150.00	150.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	123
496	910271	منزل احمدعلي محمد الفلي	770506820	\N	الخزانات ج بقالةصدام	2208156215	97	1	234.00	240.00	16000.00	16000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	124
497	910272	شبكة فارس الربيعي	735816493	\N	الخزانات ج بقالة صدام	142306	98	1	867.00	885.00	74100.00	74100.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	125
498	910403	منزل امين احمد مدهش الخرباش	734159028	\N	الخزانات جوار الفلي	24010256	99	1	365.00	377.00	17800.00	17800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	126
8	910062	عصام عبد الواسع الوجية	736042531	\N	الخزانات	20200823701	100	1	475.00	482.00	10800.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	127
9	910552	منزل شكري عون	773835019	\N	الخزانات ج الفلي	241128101399	100	1	109.00	131.00	68000.00	68000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	128
10	910065	منزل حبيب غالب محمدالجرادي	738567036	\N	الخزانات ج عصام الوجية	219788	101	1	272.00	277.00	30200.00	30200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	129
12	910063	منزل احمدمحمدعبدالله الغريبي	777004024	\N	الخزانات ج عصام الوجية	2003034231	102	1	1282.00	1308.00	37400.00	7400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	130
13	910066	بقالة هشام هاشم	735335545	\N	الخزانات	202211102987	103	1	549.00	550.00	2400.00	2400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	131
14	910070	اسماعيل محمد العزي	777339043	\N	الخزانات	202305218685	104	1	959.00	963.00	9200.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	132
15	910069	منزل القاضي علي احمدعكروت	733389897	\N	الخزانات ج الوصابي	234152488	105	1	979.00	1002.00	45400.00	45400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	133
16	910542	محمد عبدالله احمد الرشيدي	735919469	\N	مقابل بقالة هشام هاشم	202508006690	105	1	47.00	56.00	13600.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	134
17	910068	منزل عبدالرحمن محمد الوصابي	771100430	\N	الخزانات ج إسماعيل العزي	214008	106	1	519.00	533.00	20600.00	20600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	135
18	910067	عبدالقادر طارش الزبيري	778917695	\N	الخزنات.ج.حسامmtn	202008272559	107	1	1045.00	1048.00	57600.00	57600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	136
19	910492	وليد العمراني	772198216	\N	الخزانات ج الزبيري	202508004773	107	1	149.00	158.00	24400.00	24400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	137
20	910071	منزل بسام يحي	738638241	\N	الخزانات	202204324206	108	1	308.00	310.00	38900.00	38900.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	138
21	910072	منزل ياسر محمد بخيت	738136720	\N	الخزانات	202211102983	109	1	1527.00	1560.00	47200.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	139
22	910491	ياسر عبدة محمد غالب	735832323	\N	الخزانات ج موقع صالة	202508004263	109	1	86.00	98.00	17800.00	17800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	140
24	910291	منزل احمد منصور محمدقاسم	733528656	\N	الخزانات ج ياسربخيت	2408083127	110	1	312.00	324.00	17800.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	141
25	910546	عبدالباسط معمر عبدالحميد	739519511	\N	الخزانات ج موقع 73	250900092539	110	1	545.00	638.00	131200.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	142
26	910074	منزل شعيب الصلوي	736582760	\N	الخزانات	9079505	111	1	687.00	691.00	16000.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	143
27	910075	منزل احمدحسن بخيت الزرنوقي	735425479	\N	الخزانات ج شعيب الصلوي	2401010780	112	1	630.00	642.00	17800.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	144
28	910294	منزل محمد عبدالله حسن الصلاحي	773336426	\N	الخزانات ج شعيب الصلوي	2408084666	113	1	52.00	52.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	145
29	910440	مصطفى محمد احمد عقلان	770713488	\N	الخزانات ج شعيب الصلوي	241016068452	114	1	249.00	264.00	22000.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	146
30	910432	منزل علي محمد علي الزغروري	96899375169	\N	الخزانات ج شعيب الصلوي	241016069965	115	1	48.00	49.00	2400.00	2400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	147
31	910537	منزل هاشم	735056847	\N	الحارثي ج شائف المخلافي	202008275485	115	1	97.00	98.00	2400.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	148
32	910475	حسام سعيد قائد سلطان	733080794	\N	الخزانات ج موقع يو	202009068733	116	1	609.00	609.00	120000.00	120000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	149
33	910524	منزل شائف علي المخلافي	730994618	\N	الخزانات ج  هاشم	202305217727	116	1	186.00	194.00	18800.00	5800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	150
34	910147	منزل رزق سعد الشبيلي	775124899	\N	الخزانات	201911061976	117	1	56.00	58.00	3800.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	151
35	910545	منزل علي شبيل	734857639	\N	الخزانات ج رزق سعد	2018 0662881	117	1	365.00	367.00	21000.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	152
36	910292	صلاح عبدالولي فضيل	734969033	\N	الخزانات ج رزق سعد	2408080635	118	1	121.00	124.00	5600.00	5600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	153
154	910131	مشترك 910131	783270260	\N	صنعاء	910131	207	1	252.00	252.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	258
37	910448	منزل مصعب سعيد سيف منصر	739933321	\N	الخزانات ج منزل هاشم	241016064898	118	1	95.00	99.00	6900.00	6900.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	154
38	910471	اكرم عبدالسلام قاسم المحياء	730014513	\N	الحارثي ج الدكتور مراد	202310052142	118	1	159.00	172.00	20200.00	8200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	155
39	910372	منزل ايمن الزواحي	771055503	\N	الخزانات ج فضل الشعبي	241016080683	119	1	279.00	285.00	10000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	156
41	910064	منزل حسام عبدالباسط علي مجلي	966543623197	\N	الحارثي جوار الشدادي	250100003315	120	1	252.00	269.00	24800.00	24800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	157
42	910080	منزل حمزة عبدة عبدالله الحبوري	734308487	\N	الخزانات ج الشدادي	215054	121	1	232.00	239.00	12400.00	12400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	158
43	910078	منزل الدكتور مراد ج الزواحي	770780828	\N	الحارثي	215178	122	1	443.00	458.00	22400.00	22400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	159
44	910079	منزل الشدادي	735748625	\N	الخزانات ج الزواحي	215575	123	1	255.00	263.00	12200.00	12200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	160
45	910381	منزل الدكتوريحيى صالح المذحجي	779179877	\N	الحارثي ج عمارةالزواحي	202508008649	124	1	144.00	160.00	24000.00	24000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	161
46	910405	مشترك 910405		\N	صنعاء	910405	125	1	685.00	685.00	3000.00	3000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	162
47	910373	منزل عبدالوارث علي محمدسيف الراعي	783270260	\N	الحارثي ج الزواحي	241016080691	126	1	427.00	430.00	5200.00	5200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	163
48	910081	منزل الزواحي عبدالله المخلافي	715238579	\N	الحارثي	219442	127	1	286.00	296.00	16000.00	16000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	164
49	910082	منزل فهد صالح العنسي	730356002	\N	الحارثي	219148	128	1	345.00	352.00	13200.00	13200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	165
50	910348	منزل فكيرعلي المعمري	738334960	\N	الحارثي ج منظمة كير	202408099259	129	1	142.00	147.00	8000.00	8000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	166
52	910073	مشترك 910073		\N	صنعاء	910073	130	1	436.00	436.00	3000.00	3000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	167
53	910085	احمد السعودي محطة صالة	736558660	\N	محطةصالة	2401043063	131	1	641.00	641.00	4800.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	168
54	910084	محطةالسلام احمد السعودي	733114741	\N	محطة السلام الحارثي	214240	132	1	865.00	879.00	20600.00	20600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	169
55	910083	بقالة الفتح رمزي عيسئ	736154845	\N	بقالة الفتح جامع الحارثي	218972	133	1	1143.00	1147.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	170
56	910086	جامع الحارثي	783270260	\N	الحارثي	3034496	134	1	1064.00	1064.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	171
57	910365	منزل لؤي عبدالحكيم سعيد العبسي	739134140	\N	الحارثي ج عبدة دبوان	202005096380	135	1	862.00	868.00	21600.00	21600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	172
58	910087	منزل عبدة دبوان	738827163	\N	الحارثي	22008278483	136	1	958.00	995.00	56000.00	56000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	173
59	910092	منزل سعيدمحمد سعد	739425205	\N	الحارثي	202305216719	137	1	230.00	240.00	15000.00	15000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	174
60	910090	منزل مبارك عبدة قاسم	736907897	\N	الحارثي	202303084793	138	1	333.00	342.00	14000.00	14000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	175
61	910089	منزل فكري منصور الفتيني	773343490	\N	الحارثي ج الكوافير	219725	139	1	128.00	135.00	14400.00	14400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	176
64	910091	منزل معاذ عبدة قاسم احمد	730513159	\N	الحارثي ج الكوافير	220659	140	1	267.00	272.00	10000.00	10000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	177
65	910452	وسيم منصور صالح الفتيني	738874150	\N	الحارثي ج رجائي	250100059770	140	1	44.00	48.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	178
66	910088	منزل رجائي فتيني	774405595	\N	الحارثي ج سعيد سعد	219111	141	1	76.00	79.00	5200.00	5200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	179
67	910384	منزل احمد محمد العميسي	777064593	\N	الحارثي ج الكوافير	241016080056	142	1	111.00	114.00	5200.00	5200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	180
68	910093	كوافير ام عمر	730513159	\N	الحارثي	9076421	143	1	417.00	419.00	3800.00	3800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	181
69	910276	منزل المهندس وثيق الاغبري	735874968	\N	الحارثي خلف الجامع	202401011605	144	1	200.00	200.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	182
70	910404	مشترك 910404		\N	صنعاء	910404	145	1	238.00	238.00	16800.00	16800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	183
71	910183	عدادصالة	783270260	\N	الحارثي ج وثيق الاغبري	202011317480	146	1	3202.00	3373.00	240400.00	240400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	184
72	910495	نصرالدين عبدة محمدعلي	737217487	\N	الحارثي ج عدادصالة	202211102217	146	1	1255.00	1280.00	69200.00	69200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	185
73	910534	حسين فواد محمد الجلال	735153519	\N	الحارثي ج عدادصالة	202508002042	146	1	29.00	33.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	186
74	910563	محمد سعيد سعيد الحميري	733122258	\N	الحارثي ج بقالة ريان	250900057179	146	1	4.00	6.00	6200.00	6200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	187
75	910250	منزل ايمن محمد سعيد	739710031	\N	صالة جوارمخبزصالة	202308014044	147	1	415.00	425.00	18000.00	18000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	189
413	910486	عمرو وجدي عبدة محمد	735591699	\N	قريش جوار محرم	202508002336	413	1	23.00	25.00	3800.00	3800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	492
76	910420	بقالة جميل محمود احمدعبدالله	736575762	\N	جوارمحطة صالة	202409049342	147	1	971.00	1034.00	92200.00	92200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	188
77	910506	شهاب الدين يحيئ/مخبزصالة	737196423	\N	صالةج ايمن محمد سعيد	202508003707	147	1	107.00	116.00	16600.00	16600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	190
78	910417	اللمنيوم بشيراحمد فارع غانم الطاهري	739913227	\N	اللمنيوم جوارمحطةصالة	202409049358	148	1	196.00	202.00	12400.00	12400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	191
79	910109	منزل محفوظ محمدعبدالرزاق العامري	783270260	\N	جوار محطة صالة	202011317407	149	1	12.00	12.00	34000.00	34000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	192
81	910107	منزل محمدعبدالله محمد الجدري	783270260	\N	جوارمحطة صالة	202011348689	150	1	555.00	578.00	66400.00	66400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	193
82	910567	قائد صالح حزام سند	771350406	\N	التوحيد ج الأبيض	202601001183	150	1	0.00	4.00	7600.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	194
83	910060	مجاهد صالح سيف الشعبي	775890769	\N	جوار محطة صالة	202011348789	151	1	180.00	184.00	9600.00	9600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	195
84	910095	فارس السكريم	735816493	\N	سكريم الحارثي.	202304019282	152	1	447.00	458.00	19400.00	5400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	196
85	910515	حمزة محمد عبدالله اليوسفي	966500115321	\N	صالة ج جامع الحميرة	202508003125	152	1	310.00	329.00	30600.00	30600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	197
86	910097	تموينات الإسلامي محمدعبدالله	737959453	\N	الحارثي ج ابويوسف	2401041720	153	1	1017.00	1052.00	50000.00	50000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	198
87	910098	بقالة ابو يوسف (هاني)	739226082	\N	الحارثي	202302015413	154	1	741.00	741.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	199
88	910099	انس محمد مسعد محمد	738364914	\N	الحارثي ج ابويوسف	202303220661	155	1	241.00	244.00	5200.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	200
89	910094	مشترك 910094		\N	صنعاء	910094	156	1	401.00	401.00	34200.00	34200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	201
90	910330	ورشة الملحم بجاش علي احمد	734407358	\N	الحارثي	202408096427	157	1	430.00	440.00	66700.00	66700.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	202
91	910100	عداد موقع الحارثي	783270260	\N	الحارثي	2003029263	158	1	3987.00	4107.00	169000.00	169000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	203
92	910389	بقالة عرفات عبدالرحمن علي سعيد	736965428	\N	الحارثي ج اللمنيوم أيوب	250100003383	159	1	480.00	480.00	163000.00	163000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	204
94	910101	اللمنيوم ايوب	733346363	\N	الحارثي	11072713	160	1	309.00	337.00	40500.00	40500.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	205
95	910544	ياسين سليم الزبيدي بدل الأمريكي	736130307	\N	الحارثي ج الزبيدي	202508006828	161	1	12.00	19.00	10800.00	10800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	206
96	910558	نشوان علي عبدالله الجلال	736540793	\N	الحارثي ج الزبيدي	202003029107	161	1	178.00	179.00	2400.00	100.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	207
97	910353	منزل عبدالرحيم فاضل عبدة بقالة الأصيل	730497408	\N	الحارثي ج مدرسة المعارف	202409033914	163	1	258.00	258.00	2800.00	2800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	208
98	910375	منزل بسام طائف عبدالله الحكيمي	770945679	\N	العسكريج طلال العامري	202011338765	164	1	251.00	266.00	55100.00	55100.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	209
99	910105	منزل الدكتور علي البصير	736215386	\N	الحارثي	22009062044	165	1	1516.00	1522.00	9400.00	9400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	210
100	910106	منزل طلال العامري	775854416	\N	الحارثي	22008277348	166	1	527.00	535.00	12200.00	12200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	211
101	910430	منزل ذاكر عبدالله احمد الطيب	734701023	\N	العسكري ج بسام الحكيمي	202209701448	167	1	112.00	113.00	17800.00	17800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	212
102	910104	مدرسة المعارف	733645813	\N	الحارثي	201911059463	168	1	342.00	354.00	30800.00	30800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	213
103	910397	ورشة لحام عبدالله عبدة غالب	739708153	\N	العسكري ج المعارف	202308026360	169	1	686.00	702.00	67200.00	67200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	214
105	910061	ورشةلحام عديل احمدعبدة	737088954	\N	الخزانات	202209700595	170	1	712.00	712.00	219600.00	219600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	215
106	910277	منزل عمادعبدالباسط النظاري1	734972321	\N	العسكري ج الاهرامات	2401045825	171	1	303.00	325.00	31800.00	31800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	216
107	910393	منزل عبدالقوي احمدعبدالحميد قحطان	736221701	\N	العسكري ج عديل	241016095140	172	1	311.00	319.00	15400.00	15400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	217
108	910304	منزل عبدالرحمن عبدالواسع الاصبحي	771394589	\N	العسكري ج الملحم عدبل	2408080834	173	1	285.00	286.00	2400.00	2400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	218
109	910368	منزل عمار عبدالحميدسيف احمدالسرؤري	734437820	\N	العسكري ج الملحم عديل	241016080684	174	1	77.00	86.00	13600.00	13600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	219
110	910433	منزل مجدي نديم محمدالاغبري	770221533	\N	العسكري جوار عديل	201910023177	175	1	1156.00	1158.00	4400.00	4400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	220
111	910493	سفيان علي عبالله	777380651	\N	العسكري ج عديل	202308026344	176	1	1479.00	1480.00	2400.00	2400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	221
112	910386	اسامةاحمد محمدالعباسي	783270260	\N	مسلخ دجاج العسكري	250100003054	177	1	267.00	267.00	53000.00	53000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	222
113	910354	منزل محمد عبدالعزيزعبدالله عبدالغني	733053030	\N	العسكري ج حلويات الخليج	202011313907	178	1	239.00	246.00	10800.00	10800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	223
114	910108	صفوان /حلويات الخليج	734432331	\N	العسكري	202308018675	179	1	1559.00	1582.00	33200.00	33200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	224
118	910110	الشاطر للصرافة العسكري	739267085	\N	العسكري	202408080523	180	1	533.00	533.00	2000.00	2000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	225
119	910111	محمد هزاع العبسي	783270260	\N	العسكري	20224289559	181	1	199.00	199.00	21000.00	21000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	226
120	910363	فؤاد العامري	783270260	\N	العسكري مقابل الشاطر لصرافة	202204289559	182	1	752.00	752.00	16000.00	16000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	227
121	910138	عارف الجرنعي بطاريات	777369764	\N	العسكري	22008089138	183	1	965.00	971.00	22800.00	22800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	228
122	910484	بسام عبدالرب عقلان السامعي	736588702	\N	جوار تموينات العسكري	250900038042	184	1	253.00	254.00	2400.00	2400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	229
123	910485	مصطفى محمد عقلان السامعي	783270260	\N	جوار تموينات العسكري	241128103612	184	1	192.00	192.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	230
124	910379	مطعم أبو خالد	783270260	\N	العسكري	20180663850	185	1	3007.00	3007.00	33600.00	33600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	231
125	910115	صيدليةالامل /اشرف عبدالعزيزاحمدسرحان	738001149	\N	العسكري	202508006294	186	1	91.00	91.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	232
126	910447	صيدلية المدينه(سليم علي سيف)	777591499	\N	العسكري	250100045941	186	1	383.00	415.00	45800.00	45800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	233
127	910116	ياسين صالة المدينة	738347149	\N	العسكري	22009282785	187	1	4576.00	4591.00	22000.00	22000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	234
128	910514	عبدالرحمن محمدعبدالله السامعي	779077336	\N	جوار تموينات العسكري	202508002096	187	1	48.00	52.00	6600.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	235
129	910117	صادق عبدالرب  عقلان السامعي	733729418	\N	العسكري	20220432916	188	1	134.00	134.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	236
130	910118	تموينات العسكري السامعي	736039878	\N	العسكري	202303082382	189	1	2462.00	2468.00	9400.00	9400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	237
131	910458	معمل لافا لانتاج الفحم المضغوط	734869062	\N	جوارتموينات العسكري	202407201025	189	1	141.00	143.00	3800.00	3800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	238
132	910503	طلال قحطان قائد/صيدليةالبركة	783270260	\N	العسكري ج التموينات	202508009794	189	1	184.00	184.00	100000.00	100000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	239
134	910114	عمادعبدالواسع  البركاني	771208996	\N	العسكري	202204289555	190	1	669.00	678.00	13600.00	13600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	240
135	910113	معاذعبدالواسع البركاني	771208996	\N	العسكري	202204310678	191	1	3522.00	3543.00	76200.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	241
136	910364	منزل عارف البركاني	736888668	\N	العسكري	241016063520	192	1	573.00	574.00	2400.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	242
137	910112	احمد عبدالرحمن صالح العمراني	777103503	\N	العسكري ج البركاني	202005104789	193	1	798.00	830.00	51100.00	100.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	243
138	910119	بقالة هيثم ناجي محمد مهيوب	734583665	\N	العسكري	202211101983	194	1	1313.00	1318.00	8000.00	8000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	244
139	910278	منزل عماد عبدالباسط النظاري 2	783270260	\N	العسكري ج بقالةهيثم المحياء	2401010762	195	1	1314.00	1314.00	46700.00	46700.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	245
140	910559	عمرو عبدالقوي عبدالواسع	733507570	\N	العسكري ج النظاري 2	25090009	195	1	32.00	39.00	10800.00	10800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	246
141	910120	صيدلية الجودة	774354086	\N	العسكري ج صيدليةالرئاسة	2009067049	196	1	1233.00	1267.00	68600.00	68600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	247
142	910121	توفيق صيدلية الرئاسة	730541344	\N	العسكري	202303086644	197	1	915.00	947.00	45800.00	45800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	248
143	910122	مختبرالمدينه مصطفئ	783270260	\N	العسكري	734541545	198	1	1205.00	1217.00	17800.00	17800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	249
144	910125	عبدالحكيم صيدليةالعميد	777925946	\N	العسكري	201911053105	199	1	664.00	668.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	250
147	910126	مكتبة سعيد اليوسفي	775002996	\N	العسكري	11053101	200	1	1945.00	1966.00	30400.00	30400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	251
148	910124	عيادة الحالمة .إسنان	734517488	\N	العسكري	402001163166	201	1	982.00	996.00	20600.00	20600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	252
149	910346	منزل محمد نعمان احمد مهدي البعداني	770601888	\N	العسكري ج عيادة الحالمة	202408097121	202	1	132.00	134.00	3800.00	3800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	253
150	910127	فكري احمد السامعي.موادبناء	783270260	\N	العسكري	201911056793	203	1	61.00	65.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	254
151	910128	بقالة محمد غالب العزعزي	783270260	\N	العسكري	202008273564	204	1	453.00	453.00	2000.00	2000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	255
152	910129	عبد الملك علي للغسالات	733021502	\N	العسكري	22003029471	205	1	321.00	324.00	8200.00	4200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	256
153	910130	إبراهيم سالم للقمريات	737617943	\N	العسكري ج الغسالات	214029	206	1	243.00	252.00	14800.00	800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	257
155	910132	وكالة محمد منصور الشدادي	770232773	\N	العسكري	201905008118	208	1	1070.00	1077.00	10800.00	10800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	259
156	910133	منزل عبدالرحمن فرحان	730510220	\N	العسكري	4329524	209	1	220.00	225.00	14600.00	14600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	260
158	910134	استديو الحسني	738255416	\N	العسكري	20195028667	210	1	594.00	605.00	16400.00	16400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	261
159	910135	صالون عارف للحلاقة	736944090	\N	العسكري	11071450	211	1	572.00	582.00	15400.00	15400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	262
160	910532	زكريا محمد راوح ناشر	736818071	\N	العسكري ج صالون عارف	219171	211	1	199.00	200.00	2400.00	2400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	263
161	910136	صالون  الاميراحمد سيف	736807612	\N	العسكري	202305219223	212	1	411.00	411.00	26000.00	26000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	264
162	910139	بلال  .تموينات الاصيل .	730497408	\N	العسكري	202303222748	213	1	2625.00	2629.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	265
163	910439	مدرسة أجيال المجد	783270260	\N	العسكري ج بقالة الأصيل	202003021089	214	1	206.00	206.00	20000.00	20000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	266
164	910137	امجد عبدالمجيد السلامي بطاريات	771165692	\N	العسكري	201911060644	215	1	823.00	827.00	7000.00	7000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	267
165	910411	مراقب بازرعة	783270260	\N	العسكري بازرعة	202310067121	216	1	2497.00	2513.00	23400.00	23400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	268
166	910472	امجد فواد احمد سيف ناشر	777024616	\N	العسكري ج احمد راوح	250900007192	216	1	158.00	172.00	20600.00	20600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	269
167	910474	صادق عبدالحميد صالح الصناعي	739365441	\N	العسكري ج احمدراوح	250900007294	216	1	366.00	381.00	22000.00	22000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	270
168	910418	منزل رائد احمد محمد العودي	734326008	\N	بازرعة جوار طحنون	2017295152	217	1	176.00	189.00	22600.00	22600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	271
169	910424	منزل صالح مصلح محمد الحاج	735917281	\N	بازرعة جوار طحنون	202310067121	218	1	90.00	93.00	5400.00	5400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	272
170	910385	منزل احمد راوح ناشر	777425025	\N	العسكري ج بقالة الأصيل	202011349146	219	1	254.00	266.00	17800.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	273
172	910306	منزل عامر عبدالله علي زيد	783270260	\N	العسكري ج شهدي الاغبري	2408080823	220	1	20.00	20.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	274
173	910504	مامون محمد حمود الشميري	736390975	\N	العسكري ج شهدي الاغبري	202508005464	220	1	266.00	284.00	26200.00	6200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	275
174	910282	منزل شهدي جمال عبدالقادر الاغبري	783270260	\N	العسكري ج بقالة الأصيل	202408080567	221	1	273.00	273.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	276
175	910305	منزل تغريد نائف	779336847	\N	التموين مقابل المحطة	2408080835	223	1	70.00	72.00	3800.00	3800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	277
176	910298	منزل ارؤئ احمد صالح الصايدي	739292554	\N	التموين مقابل المحطة	2408092838	224	1	156.00	162.00	9400.00	9400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	278
177	910141	غسان سليمان علي الضرافي	737600857	\N	التموين	21043	225	1	2393.00	2407.00	20600.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	279
178	910498	مطلق عبدالجليل عبدة الاكحلي	777339830	\N	التوحيد ج غسان الظرافي	202508009712	226	1	79.00	79.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	280
179	910528	محمد توفيق سيف سعيدالزايدي	734889129	\N	التموين ج غسان الظرافي	420170161194	226	1	357.00	399.00	163500.00	118000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	281
180	910551	محمد الانسي	730970646	\N	التوحيد ج بقالة عمار	202303082629	226	1	341.00	347.00	19000.00	19000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	282
181	910553	عمر عبدالرحمن الصلوي	739194637	\N	التوحيد ج بقالة عمار	24010813	226	1	464.00	470.00	11400.00	11400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	283
182	910450	نشوان حميد احمد اليمني	776790334	\N	التوحيد ج الزعيم	202209700178	227	1	74.00	78.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	284
183	910144	فرم محمدسهيل عبدالله الأمير	734045310	\N	التوحيد	214034	228	1	1110.00	1126.00	70600.00	70600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	285
184	910145	منزل شهير  احمد علي العذري	734045310	\N	التوحيد ج العاقل	218287	229	1	467.00	485.00	39800.00	39800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	286
186	910146	منزل مصطفئ الزعيم	783270260	\N	الجحملية	202305216706	230	1	256.00	256.00	15400.00	15400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	287
187	910148	بقالة غازي عبدالله الصبري	782413463	\N	التوحيدج الجامع	202204324145	231	1	35.00	35.00	8000.00	8000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	288
188	910332	منزل بدرية عبدالناصرعلي عبدالملك	736161145	\N	التوحيد ج منزل الزعيم	24010187	232	1	401.00	407.00	9400.00	9400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	289
189	910284	منزل نبيل صالح قائد المهتدي	770740300	\N	التوحيدجوار الجامع	201911012271	233	1	285.00	285.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	290
190	910416	منزل ايمن صادق محمد الجبري	774668651	\N	التوحيد جوار الزعيم	202409049349	234	1	135.00	140.00	8000.00	8000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	291
191	910383	منزل بندرمحمداحمد القباطي	773782365	\N	اجوارجامع لتوحيد	241016080843	235	1	122.00	126.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	292
417	910451	جامع العرضي	783270260	\N	العرضي	201911047089	426	1	1610.00	1610.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	493
192	910151	محمد ناجي قائد الدهبلي بدل الأبيض	736540474	\N	التوحيد بدل الأبيض	202003021088	236	1	5245.00	5256.00	16400.00	16400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	293
193	910149	منزل احمد سعيدالعماد	783079532	\N	التوحيدج الأبيض	215330	237	1	109.00	111.00	6200.00	6200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	294
194	910152	بقالة إبراهيم الشرعبي	776770338	\N	التوحيد	201911053281	239	1	1053.00	1056.00	32200.00	32200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	295
196	910476	عبدالحليم مقبل محمد علي	771171765	\N	الجحملية ج بقالة خضرا	250900009064	240	1	223.00	256.00	53600.00	53600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	296
197	910153	منجرة احمد عبدالله محمد علي	777054205	\N	الجحملية	201911051041	241	1	265.00	266.00	4800.00	4800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	297
198	910460	مراقب الجحملية السفلئ	783270260	\N	الجحملية ج الزعيم	202408083125	242	1	1496.00	1496.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	298
199	910156	منزل فؤاد الغضراني	783270260	\N	الجحملية	20191106499	243	1	1301.00	1311.00	15000.00	15000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	299
200	910155	منزل مطر محمد عبدالباري الفتيح	733615419	\N	الجحملية ج الغضراني	1911067179	244	1	640.00	649.00	13600.00	13600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	300
201	910413	منزل سعيد محمد محمد عامر	779892602	\N	الجحملية ج فواد الغضراني	2019540	245	1	1056.00	1060.00	13200.00	13200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	301
202	910157	الزعيم	738304407	\N	الجحملية	3029224	246	1	5880.00	5899.00	45200.00	45200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	302
203	910159	منزل مجدي امين	730209516	\N	الجحملية	827115	247	1	975.00	993.00	26200.00	26200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	303
204	910158	عبدالقادر سعيد الدبعي للخياطة	738370233	\N	الجحمليةج الزعيم	202401010772	248	1	284.00	284.00	4800.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	304
205	910161	ورشة البهلولي	733638177	\N	الجحملية	8273723	249	1	880.00	894.00	20600.00	20600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	305
207	910162	ثلاجةصدام .ابوعدي	733483388	\N	ثلاجةبوعدي الجحملية	202308026344	250	1	1044.00	1050.00	39800.00	11400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	306
208	910422	بقالة الاخوة محمد امين الابقط	736176289	\N	الجحملية جوار ابوعدي	250900102513	251	1	52.00	150.00	212000.00	138190.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	307
209	910164	مشترك 910164		\N	صنعاء	910164	252	1	1064.00	1064.00	76600.00	76600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	308
210	910165	شعير .محمد رفيق	783270260	\N	الجحملية	20180662293	253	1	2400.00	2422.00	31800.00	31800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	309
211	910496	احمد محمد علي ناصرالبعداني	735820865	\N	الجحملية مقابل الشعير	201903530012	253	1	393.00	399.00	9400.00	9400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	310
212	910169	فهيم حلويات الصقر	783270260	\N	الجحملية	201903529406	254	1	2266.00	2266.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	311
213	910490	بقالة الفهيدي /أسامة	770123030	\N	الجحملية ج حلويات الصقر	202508003857	254	1	344.00	388.00	62600.00	62600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	312
214	910410	منزل احمد نجيب الغشم	739254811	\N	الجحملية ج سعيد غالب	202310069374	255	1	358.00	370.00	23800.00	23800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	313
215	910160	منزل جمال الصبري	733516473	\N	الجحملية	201911075157	256	1	468.00	476.00	12400.00	12400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	314
216	910295	منزل عواطف عبدالله ام نشوان العريقي	779095150	\N	الجحمليةج غمدان القباطي	2008280721	257	1	101.00	102.00	4800.00	4800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	315
217	910371	منزل عرفات محمد محسن الحميضة	776326506	\N	الجحملية ج غمدان القباطي	202011339625	258	1	196.00	196.00	57700.00	57700.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	316
218	910308	منزل سليم محمد مكرد الشريف	774276336	\N	الجحملية ج غمدان القباطي	2408080827	259	1	285.00	293.00	16800.00	16800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	317
221	910344	منزل ام جلال عمة جمال الصبري	772521306	\N	الجحملية ج غمدان القباطي	202408097137	260	1	63.00	64.00	2400.00	2400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	318
222	910489	هدى عبدالله علي سلطان	772034242	\N	الجحملية ج الكابتن	202508008629	260	1	50.00	54.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	319
223	910509	احمدعبدة /بيت الطاحون	771285559	\N	الجحملية ج الحميضة	202508001530	260	1	72.00	76.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	320
224	910334	منزل طلال صادق علي المحياء	733722133	\N	الجحملية ج غمدان القباطي	201911083823	261	1	1127.00	1147.00	59400.00	34390.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	321
225	910517	جمال علي محسن الذاري	777159021	\N	الجحملية ج الحميضة	202508005837	261	1	71.00	82.00	16400.00	16400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	322
226	910520	محسن عبدالله إسماعيل	730716610	\N	الجحملية ج الحميضة	202211102977	261	1	220.00	225.00	8000.00	8000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	323
227	910168	منزل جميل الحميضة	771732152	\N	الجحملية ج الكابتن	20209068282	262	1	230.00	244.00	52600.00	52600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	324
228	910429	منزل صباح احمد قاسم الحيمي	734413856	\N	الجحملية ج الكابتن	202209701311	263	1	37.00	39.00	3800.00	3800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	325
229	910166	محمد محسن الكابتن	730989196	\N	الجحملية ج غمدان	202008089869	264	1	189.00	196.00	10800.00	1800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	326
230	910408	محمد المشولي	738762442	\N	الجحملية ج غمدان القباطي	202011336822	265	1	85.00	87.00	3800.00	3800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	327
231	910419	منزل حسين طلال ردمان القباطي	781362442	\N	الجحملية جوار المشولي	202409049346	266	1	58.00	59.00	2400.00	2400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	328
232	910163	مشترك 910163		\N	صنعاء	910163	267	1	1651.00	1651.00	149100.00	149100.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	329
233	910562	مختار عبدة سيف الحميري0بوفية	735227908	\N	الجحملية ج بقالة الفهيدي	250900100685	267	1	63.00	75.00	18500.00	18500.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	330
234	910170	مشترك 910170		\N	صنعاء	910170	268	1	296.00	296.00	10000.00	10000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	331
235	910516	صدام امين ثابت عبدالله	777318503	\N	الجحملية ج الكوكباني	202008273118	268	1	718.00	763.00	87600.00	87600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	332
236	910171	انورالكوكباني.		\N	الجحملية	2019110539620	269	1	103.00	103.00	6200.00	6200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	333
239	910172	منزل سعيد غالب ناجي	770285285	\N	الجحملية	202009079722	270	1	2162.00	2180.00	26200.00	26200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	334
240	910434	منزل محمد حسن محمد الشوافي	771419596	\N	الجحملية ج انورالكوكباني	202009180124	271	1	360.00	369.00	39000.00	39000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	335
241	910173	طرمباة عمرو عبدة حزام	736612929	\N	الجحملية	201905004630	273	1	1560.00	1573.00	19200.00	19200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	336
242	910175	محلات ماهر الكامل	776947741	\N	الجحملية	3034208	274	1	4402.00	4402.00	345300.00	345300.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	337
243	910176	اسامة بقالة الخالد	783270260	\N	الجحملية	2019501889	275	1	5564.00	5564.00	3000.00	3000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	338
244	910174	مركز الجند الطبي	779634272	\N	الجحملية	2019252825	276	1	2018.00	2053.00	52600.00	52600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	339
245	910177	مشترك 910177		\N	صنعاء	910177	277	1	641.00	641.00	17800.00	17800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	340
246	910204	مشترك 910204		\N	صنعاء	910204	278	1	1040.00	1040.00	16000.00	16000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	341
247	910178	بقالةخميس	783270260	\N	الجحملية	202303081520	279	1	269.00	269.00	2000.00	2000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	342
249	910478	اشرف محمد محمد صالح	772151188	\N	الجحملية ج مركز الجند	202408080537	280	1	218.00	223.00	8000.00	8000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	343
250	910202	ملحمة فؤاد احمدعلي	737450973	\N	الجحملية	82075761	281	1	1222.00	1230.00	13100.00	13100.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	344
251	910201	منزل محمدعبدالواحدمحمدالعزب	734389329	\N	الجحمليةج ملمحةفواد	2401010768	282	1	159.00	162.00	6000.00	6000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	345
252	910179	بوفية /عبدالحكيم ناجي محمد صالح	774917575	\N	الجحملية	11071027	283	1	1096.00	1114.00	26200.00	26200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	346
253	910180	منزل محمد عبده فرحان	783270260	\N	الجحملية	1102991	284	1	55.00	56.00	4800.00	4800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	347
254	910181	منزل نجوئ ناجي البعداني	771579980	\N	الجحملية	8284727	285	1	79.00	82.00	5200.00	5200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	348
255	910360	صالون قطر عبدة مهيوب محمد غالب	730044436	\N	الجحملية ج أبوخليل	241016060882	286	1	86.00	89.00	5200.00	5200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	349
256	910200	عبدالعزيز المحمدي	774078086	\N	الجحملية ج خالدالانسي	202008271216	287	1	106.00	109.00	5200.00	5200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	350
257	910199	منزل خالد الانسي	783016868	\N	الجحملية	663802	288	1	54.00	56.00	3800.00	3800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	351
258	910487	ليبيا عبدالرحمن محمد الاشباطا	737438309	\N	بيت الدجاج ج الكعدة	202508006287	288	1	62.00	68.00	9400.00	9400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	352
259	910198	عمر عبدالله .موادبناء	774026774	\N	الجحملية	341736	289	1	93.00	94.00	18600.00	18600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	353
260	910529	نشوان الغثيفي صاحب الغاز	783270260	\N	الجحملية ج عمرمواد البناء	202508008188	289	1	19.00	19.00	21400.00	21400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	354
262	910182	مشترك 910182		\N	صنعاء	910182	290	1	266.00	266.00	3000.00	3000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	355
263	910184	معمر اللمنيوم	783270260	\N	الجحملية	11033481	291	1	1450.00	1450.00	22200.00	22200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	356
264	910185	مشترك 910185		\N	صنعاء	910185	292	1	308.00	308.00	76800.00	76800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	357
265	910333	طاحون ياسين	777237460	\N	الجحمليةج اللمنيوم معمر	201911032050	293	1	466.00	471.00	72900.00	72900.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	358
266	910473	ااسياء محمد عبدالله الثور	774906831	\N	الجحملية ج بشار	250900007289	294	1	28.00	28.00	3400.00	3400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	359
267	910186	فواد مطبعة الثقة	776948949	\N	الجحملية ج بشار	202008140066	295	1	1016.00	1025.00	13600.00	13600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	360
268	910187	مشترك 910187		\N	صنعاء	910187	296	1	888.00	888.00	128400.00	128400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	361
269	910388	منزل حامد محمدعابدالشميري	770509593	\N	الجحملية ج الفندم احمد	250100003056	297	1	156.00	163.00	13200.00	13200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	362
270	910566	عبدالرحمن محمد عبدة البلاع	737087936	\N	الجحملية ج بشار	250100003588	297	1	243.00	250.00	14600.00	10800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	363
271	910398	منزل عبدة  حزام	779853881	\N	الجحملية جوارمعمر	62053212003	298	1	3387.00	3391.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	364
272	910197	حازم للسكريم	771003113	\N	الجحملية	20180662028	299	1	1217.00	1221.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	365
275	910193	منزل عبدالرقيب مرشد	774279789	\N	الجحملية	233334	300	1	1426.00	1435.00	13600.00	13600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	366
276	910194	ناصر حسين ج اخولاني	736917316	\N	الجحملية ج الخوالاني	202009068827	301	1	227.00	230.00	5200.00	5200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	367
277	910462	حلويات مامون فهيم عبدة القباطي	774571226	\N	الجحملية ج الانسي	241016069152	302	1	415.00	446.00	44400.00	44400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	368
278	910195	محمد غالب الخولاني	771224461	\N	الجحملية	202305218690	303	1	300.00	306.00	9400.00	9400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	369
279	910376	امين عبدالله صالح	774059468	\N	الجحملية ج حازم السكريم	202011339429	304	1	154.00	159.00	8000.00	8000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	370
280	910369	منزل امجد محمود يوسف راوح	783597575	\N	الجحملية ج حازم السكريم	202012155157	305	1	563.00	563.00	48000.00	48000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	371
281	910510	هيكل احمد عبدالرحمن زيد الصلوي	777464190	\N	الجحملية ج حازم السكريم	202508003462	305	1	54.00	59.00	8000.00	8000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	372
282	910192	منزل غالب احمد غالب الخولاني	777239462	\N	الجحملية	219148	306	1	273.00	281.00	12200.00	12200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	373
283	910299	منزل البنا محمد قاسم غالب المليكي	774153160	\N	الجحمليةج بقالة الربيع	1911052430	307	1	185.00	189.00	7600.00	7600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	374
284	910351	عامرعبدالغني سعيدمحمدالصبري	781088820	\N	الجحملية ج الكامل	202409034711	308	1	353.00	353.00	5000.00	5000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	375
285	910188	مكتبة الفرقان	783270260	\N	الجحملية	11056917	309	1	1286.00	1296.00	15000.00	15000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	376
288	910189	مغسلة التيسيرعلي عبدالله	771270119	\N	الجحمليةج مكتبةالفرقان	214269	310	1	398.00	408.00	15000.00	15000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	377
289	910526	جمال علي عبدةفاسم العزب	770899345	\N	الجحملية ج مغسلة التيسير	202508006257	310	1	24.00	40.00	24400.00	24400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	378
290	910190	ورشة حسن الخباني	783270260	\N	الجحملية	201901009565	311	1	785.00	794.00	19000.00	19000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	379
291	910191	بنشر محمدعبدالله الصرماني	738889950	\N	الجحملية	2019110130	312	1	912.00	914.00	3800.00	3800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	380
292	910359	نادي الضباط	783270260	\N	الجحملية	241016072391	313	1	88.00	88.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	381
293	910465	طاحون ياسين 2	777237460	\N	الجحمليةج نادي الضباط	241128103608	313	1	456.00	477.00	46400.00	46400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	382
294	910497	الفندم يعقوب كتيبة المهام	783270260	\N	الجحمليةج جامع العرضي	202508003482	313	1	188.00	214.00	191300.00	191300.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	383
295	910377	نادي الضباط	783270260	\N	الجحملية	202003031961	314	1	4780.00	4785.00	8000.00	8000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	384
296	910400	منزل/محمد يحيى احمد الحلك	772048030	\N	الجحملية جوارالطرمبا	20180662719	315	1	261.00	266.00	8000.00	8000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	385
297	910301	منزل وضاح عبدالله محمد جابر الابي	779657966	\N	الجحمليةج منجرةعبود	2408092839	316	1	440.00	464.00	61000.00	61000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	386
298	910205	منجرة عبود الجعفري	736800073	\N	الجحملية	20180661891	318	1	3807.00	3846.00	62300.00	62300.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	387
299	910207	منجرة الحبوش	776163107	\N	الجحملية	910207	319	1	2091.00	2109.00	26200.00	26200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	388
301	910206	منجرة صدام	770489600	\N	الجحملية	20145	320	1	598.00	598.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	389
302	910560	عبدالرحمن احمد محمدعقيل	773245776	\N	الجحملية ج الحبوش	202008272274	320	1	95.00	103.00	12200.00	7200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	390
303	910208	الأمنيوم صالح سعيد	773442550	\N	الجحملية	103856	321	1	526.00	537.00	16400.00	16400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	391
304	910507	مراد عبدة حسن السورقي	738895678	\N	الجحملية ج الحبوش	202508003660	321	1	149.00	163.00	20600.00	20600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	392
305	910211	جامع العباس	783270260	\N	الجحملية	202208282774	322	1	134.00	144.00	15000.00	15000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	393
306	910508	نجيب سلطان حزام السفياني	777018788	\N	الحجحملية ج المنيوم صالح	202508004270	322	1	59.00	65.00	9400.00	9400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	394
307	910445	عداد مراقب صاله 2	783270260	\N	جوار محطة صاله	201911063183	323	1	2410.00	2410.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	395
308	910209	محمدقاسم  فرن العربي	783270260	\N	الجحملية	202008277740	324	1	77.00	77.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	396
309	910210	منزل عبدالملك أحمد دبوان	777143801	\N	الجحملية	202302019345	325	1	170.00	177.00	10800.00	10800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	397
310	910367	منزل فاطمة صالح احمد محمد العدني	775840489	\N	الجحملية ج بقالة العزي	241016060883	326	1	274.00	281.00	10800.00	10800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	398
311	910212	منزل نجلاء عبدالله الصوفي	776195345	\N	الجحملية	2019110869993	327	1	999.00	1006.00	10800.00	10800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	399
312	910213	منزل هائل عبدالله البريهي	739204126	\N	الجحملية	202008272300	328	1	513.00	518.00	8000.00	8000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	400
313	910406	منزل محمد عبدالله 2	783270260	\N	الجحملية ج هائل البريهي	202003029096	329	1	267.00	268.00	3400.00	3400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	401
315	910214	عبدالله علي عبدة الشرماني	777163777	\N	جحملية.منجرةبن محمود	202305217499	330	1	207.00	212.00	10000.00	10000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	402
316	910362	منزل فاروق محمدسيف محمد	771094942	\N	الجحملية ج هائل البريهي	202409034718	331	1	232.00	238.00	9400.00	9400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	403
317	910302	منزل اياد عبدالله ناجي البعداني	771302096	\N	الجحملية ج الحبوش	202409045018	332	1	98.00	103.00	8000.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	404
318	910421	منزل شوقي عبدالعزيز محمد اليوسفي	+967738614271	\N	الجحملية جوار اليمني	202409029768	333	1	108.00	108.00	2000.00	2000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	405
319	910431	ماجد يحي محمد الشيباني	+00966533448339	\N	الجحملية ج العزي	241016069971	334	1	44.00	47.00	11800.00	11800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	406
320	910216	منزل شفيق هزاع	+967777216086	\N	الجحملية	20200285255	335	1	346.00	349.00	5200.00	5200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	407
321	910215	هائل الامير.ج شفيق	+967772317172	\N	الجحملية.ج شفيق	202008287361	336	1	174.00	174.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	408
322	910217	نادر عبدالوهاب الشيعاني	+967739334335	\N	جحملية.منجرةبن محمود	202305217491	337	1	581.00	590.00	23600.00	23600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	409
323	910218	منجرة بن محمود	+967738032980	\N	الجحملية	20180661967	338	1	3484.00	3511.00	38800.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	410
326	910219	طلال احمدمهيوب.  لحام	+967733346258	\N	الجحملية	202006288336	340	1	440.00	452.00	52400.00	52400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	411
327	910220	منزل علي سليمان	+967735898321	\N	الجحملية	202003027659	341	1	775.00	807.00	45800.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	412
328	910494	حبيب سعيداحمد عبدالرزاق	+967738009062	\N	الجحملية ج علي سليمان	202407039312	342	1	51.00	53.00	4800.00	4800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	413
329	910536	بليغ محفوظ محمد احمد العريقي	783270260	\N	الجحملية ج القسم	202508001379	342	1	8.00	9.00	12600.00	12600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	414
330	910543	جمال جميل محمد زيوار	783270260	\N	الجحملية ج القسم	202508008920	342	1	79.00	88.00	14200.00	14200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	415
331	910225	قسم الفقيد المغبشي	737088954	\N	قسم الجحملية	202008280581	343	1	1685.00	1691.00	157000.00	57000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	416
332	910227	منزل سترالله محمد البعداني	771580484	\N	الجحملية ج علي سليمان	20230306652	345	1	321.00	324.00	5200.00	5200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	418
333	910222	منزل ابتسام علي يحيئ الثلايا	776102209	\N	الجحمليةج علي سليمان	202401010778	346	1	446.00	470.00	34600.00	34600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	419
334	910223	منزل خالد عبدالله فارع الوتيري	773505536	\N	جحملية.جارمحمدعادل	202305218695	347	1	306.00	322.00	50900.00	20900.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	420
335	910229	منزل محمد عبدالله	783270260	\N	الجحملية	69900	348	1	542.00	551.00	16100.00	16100.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	421
336	910232	منزل محمد عبدالملك محمد اليمني	774979999	\N	الجحمليةج معمرحسن	202401010768	348	1	435.00	446.00	16400.00	16400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	422
337	910228	منزل معمر حسن	733113488	\N	الجحملية	201911064990	349	1	430.00	440.00	15000.00	15000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	423
338	910541	وائل عبدالرحمن الطيب	737665495	\N	الجحملية ج بقالة العزي	202508001384	349	1	28.00	33.00	8000.00	8000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	424
340	910231	منزل حسن محمد	733199993	\N	الجحملية	202012093714	350	1	654.00	663.00	13600.00	13600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	425
341	910230	لطف الرياشي جار منزل حسن	783270260	\N	جوارمنزل حسن	202011347276	351	1	850.00	850.00	84500.00	84500.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	426
342	910233	منزل ام احمد جمال الصبري	735651510	\N	الجحملية	202011344916	352	1	298.00	307.00	14200.00	14200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	427
343	910268	منزل خالد محمدعبدالرزاق الزبيدي	783270260	\N	الجحمليةج الحبابي	24010184	353	1	254.00	260.00	9400.00	9400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	428
344	910234	عبدالملك قائد احمد الصلوي	777240331	\N	النجاح بدل الحبابي	202008272381	354	1	288.00	294.00	11400.00	11400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	429
345	910235	منزل احمد فاضل الوصابي	770470210	\N	النجاح .الحبابي	202305218693	355	1	524.00	537.00	19200.00	19200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	430
346	910283	منزل معاذ محمد عبدالله احمد الفراري	715865607	\N	النجاح ج إبراهيم الحكيمي	241016066187	356	1	591.00	591.00	59600.00	59600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	431
347	910527	عبدالسلام عبدالرحمن الوصابي	772071676	\N	الجحملية بدل الفراري	202508006827	356	1	77.00	84.00	10800.00	10800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	432
348	910281	منزل ماجد الحاج	777771494	\N	النجاح ج الجندبي	241016072396	357	1	162.00	171.00	13600.00	13600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	433
1	910001	you قريش	739132010	\N	الجحملية	140495	0	1	56900.00	56900.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	1
2	910002	you صالة	739132010	\N	صالة	41380	0	1	44179.00	44179.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	2
3	910004	موقع يمن موبايل	773229696	\N	حارة قريش	202210200648	0	1	35078.00	35078.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	3
5	910005	منزل شروق عبدالله علي البيضاني	783270260	\N	الخزانات ج ع مصطفئ	219593	1	1	226.00	226.00	93000.00	93000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	4
145	910096	عبدالكريم الصبري	739524754	\N	الخزانات	22003021728	2	1	617.00	635.00	26200.00	26200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	5
273	910003	منزل محمدفواد الشهاري	733437874	\N	الخزانات	20220348260	3	1	294.00	300.00	10000.00	10000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	6
398	910297	منزل علي محمد ناجي فارع ماوية	734275073	\N	الخزانات ج الكهرباء	2408085749	4	1	224.00	224.00	15400.00	15400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	7
428	910006	كامل عبدة علي الظرافي	777739388	\N	الخزانات	202009067795	5	1	594.00	594.00	2000.00	2000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	8
429	910501	بدرية صالح حسن الروبي	775183737	\N	الخزانات ج رياض ماوية	202508004795	5	1	23.00	27.00	6600.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	9
440	910007	منزل علي احمد المنصوري	780375047	\N	الخزانات	202305216522	6	1	831.00	833.00	9000.00	9000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	10
441	910513	محمد صلاح الحوباني	777858560	\N	الخزانات	22335566	6	1	716.00	719.00	22600.00	22600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	11
451	910008	مدرسة اجيال السعيدة	774210359	\N	الخزانات	20223034202	7	1	631.00	644.00	226600.00	226600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	12
471	910464	منير احمد محمد حيدر	783270260	\N	عقبة ج ماجد الزرعي	250900009069	8	1	0.00	0.00	19000.00	19000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	13
486	910009	منزل مجدي الحميدي	734491414	\N	الخزانات ج رشيد	3038225	9	1	1270.00	1284.00	74000.00	23600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	14
7	910010	منزل امين عبدةحسن جنوش	730030270	\N	الخزانات ج الدكتور رشيد	214266	10	1	282.00	301.00	27700.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	15
23	910358	منزل عبدالحكيم قائد احمد العريقي	733939237	\N	الخزانات ج جنوش	202308026360	11	1	147.00	147.00	1000.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	16
40	910016	منزل إسماعيل احمد عبدة السامعي	777900589	\N	الخزانات ج جنوش	2008089744	12	1	166.00	168.00	3800.00	3800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	17
11	910570	عبدالله سعيد نعمان قائد	777997559	\N		\N	101	1	0.00	0.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	497
324	910569	خالد سالم محمد	777560722	\N		\N	339	1	0.00	0.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	498
468	910571	صهيب محمد الجريح	772033678	\N		\N	77	1	0.00	0.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	499
349	910499	محمد بلال احمد الحاج	773277987	\N	النجاح ج ماجد الحاج	202508000412	357	1	123.00	136.00	20900.00	20900.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	434
350	910502	زائد سلطان إسماعيل الحاج	777088853	\N	النجاح ج ماجد الحاج	202508005249	357	1	72.00	76.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	435
351	910237	منزل ايمن توفيق الاديمي	774129561	\N	النجاح جوارعصام السامعي	202209700129	358	1	75.00	77.00	3800.00	3800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	436
352	910236	منزل عصام عارف السامعي	775070764	\N	النجاح	202204320140	359	1	783.00	789.00	9400.00	9400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	437
354	910392	منزل عبدالرقيب/عمارعبدة علي	736977944	\N	النجاح ج عصام السامعي	250100007974	360	1	27.00	27.00	2000.00	2000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	438
355	910438	عداد لمبات الجندبي	783270260	\N	النجاح ج الجندبي	202011290417	361	1	249.00	249.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	440
356	910453	منزل جميلة احمد جمال محمد	783270260	\N	النجاح ج السماوي	910453	361	1	154.00	154.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	441
357	910467	محمد عبدالصمد قاسم حسان	771939854	\N	النجاح ج الجندبي	241016069828	361	1	259.00	268.00	25400.00	25400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	442
358	910238	منزل احمد حميد(الواء الخامس)	738525689	\N	النجاح	2200285282	362	1	5384.00	5463.00	331500.00	331500.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	443
359	910242	منزل نبيل قائد محمد فرحان	776845104	\N	جوار مدرسة النجاح	202008271851	363	1	345.00	351.00	9800.00	9800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	444
360	910240	منزل الدكتورمحمد السماوي	733749100	\N	النجاح	11103000	364	1	1291.00	1298.00	10800.00	10800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	445
361	910338	منزل امة الغفور السنيدار	776591176	\N	النجاح ج جامع نصار	202408096425	365	1	15.00	15.00	5200.00	5200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	446
362	910459	محمد صادق عبدالله السروري	735892096	\N	النجاح ج هيفاء	241016069563	366	1	80.00	82.00	3800.00	3800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	447
363	910150	منزل حمدي محمد جميل	770130489	\N	جوارجامع نصار	202003029400	367	1	510.00	510.00	3400.00	3400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	448
364	910339	محمد عبدالله قائد علي	777725153	\N	النجاح بعمارةمحمدعبدالله قائد	201910022025	369	1	831.00	838.00	10800.00	10800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	449
366	910370	منزل سامي محمد سيف فارع الصبري	778993073	\N	النجاح بعمارةمحمدعبدالله قائد	202011349774	370	1	37.00	37.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	450
367	910266	منزل ايهم خالد العريقي	770274927	\N	النجاح بعمارةمحمدعبدالله قائد	202208156628	371	1	68.00	68.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	451
368	910361	منزل هاني يوسف علي العريقي0يو	739090606	\N	النجاح بعمارةمحمدعبدالله قائد	202008274950	372	1	297.00	301.00	11800.00	800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	452
369	910394	منزل عبدالقادرعثمان مرتضى عثمان	783270260	\N	النجاح بعمارةمحمدعبدالله قائد	250100003057	373	1	198.00	198.00	8900.00	8900.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	453
370	910463	وجدان عبدة قاسم محمد	735755625	\N	النجاح ج هيفاء	241128101393	373	1	161.00	176.00	22000.00	22000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	454
371	910244	منزل صلاح محمد عايض	736060883	\N	النجاح ج جمال2	2009079515	375	1	323.00	332.00	13900.00	13900.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	455
372	910246	منزل محمدعباس 2	733355418	\N	النجاح ج 14 أكتوبر	219806	376	1	219.00	225.00	9700.00	700.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	456
373	910533	احمد عبدالحكيم محمد احمد	774568150	\N	النجاح ج محمدعباس	2509000085704	376	1	65.00	72.00	10800.00	10800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	457
374	910248	منزل حسام إبراهيم قاىدالقدسي	777171894	\N	النجاح	213974	377	1	494.00	505.00	18200.00	18200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	458
375	910245	منزل حسين طلال الشرعبي	772202924	\N	النجاح	22004328052	378	1	232.00	234.00	9000.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	459
376	910435	حمد عبدالكريم قائداليوسفي	733039523	\N	الجحملية ج القسم	1806259431	379	1	143.00	144.00	2400.00	2400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	460
378	910415	منزل سمير احمد قائد علي	736465628	\N	النجاح ج ام ايهم	202409029761	381	1	391.00	408.00	74000.00	74000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	461
379	910249	عبدالرحمن المليكي	771504958	\N	النجاح ج سميرقايد	2309027085	382	1	406.00	410.00	7000.00	7000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	462
380	910341	منزل أسامة عبدالرحمن مهيوب	730979876	\N	بيت الدجاج0ج ايمن محمدسعيد	202408096436	384	1	237.00	252.00	22000.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	463
381	910251	منزل اسامه عادل النياح	730852432	\N	بيت الدجاج	20221111622	385	1	529.00	540.00	16400.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	464
382	910469	يوسف عبدة حسن فاضل	735226671	\N	بيت الدجاج ج الكعدة	202308014026	386	1	341.00	346.00	8000.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	465
383	910350	منزل الفندم حمود ثابت	735744162	\N	بيت الدجاج  جارطحنون	202409019544	387	1	1542.00	1568.00	50700.00	50700.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	466
384	910374	الفندم اسلام	966537187872	\N	بيت الدجاج	910374	388	1	265.00	273.00	99400.00	99400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	467
385	910380	مخبز المميز تابع (شاهر سيف العامري)	777216400	\N	بيت الدجاج	241016080049	389	1	274.00	279.00	8000.00	8000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	468
387	910287	منزل هشام محمد علي مقبل	+967773443060	\N	قريش جوار الصنديد	202408083126	390	1	100.00	102.00	3800.00	3800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	469
388	910256	منزل خالد محمد البعداني	783270260	\N	حارة قريش	22008271173	391	1	892.00	902.00	15000.00	15000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	470
389	910257	منزل محمدناجي عبدالله البعداني	774252595	\N	حارة قريش	2401010769	392	1	449.00	455.00	9400.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	471
390	910436	منزل هشام عبدالملك عبدالسلام	738163506	\N	قريش ج الصنديد	241016082722	393	1	124.00	133.00	13600.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	472
391	910259	منزل إشراق محمد اليوسفي	780347422	\N	حارة قريش	22009079664	394	1	664.00	667.00	5200.00	5200.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	473
392	910296	جامع علي عبدالقادرالصبري	770562506	\N	قريش	22003028182	395	1	1856.00	1903.00	126600.00	126600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	474
393	910262	منزل احمد عبدالله اليوسفي	736849041	\N	حارة قريش	202008275411	396	1	626.00	631.00	8000.00	8000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	475
394	910347	منزل محمد منصور عبدة اليوسفي	738323388	\N	قريش ج احمد اليوسفي	202408099251	397	1	41.00	43.00	3800.00	3800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	476
395	910270	منزل طه العزي محمد مصلح	772997060	\N	جوار جامع قريش	214788	398	1	129.00	131.00	3800.00	3800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	477
396	910505	عبدالملك امين عبدالرحيم الاديمي	775093274	\N	قريش ج البعداني	202508003652	399	1	78.00	82.00	6600.00	6600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	478
397	910518	عماد نوفل عبدالواهاب اليوسفي	776434508	\N	فريش ج اليوسفي	202409049524	399	1	255.00	264.00	13600.00	13600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	479
400	910425	منزل احمد عبدالباقي حامد علي	773499949	\N	قريش ج احمدناجي	241016063714	400	1	222.00	231.00	13600.00	0.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	480
401	910449	منزل احمد ناجي عبدالله البعداني	774252590	\N	قريش ج ناجي البعداني	202401010898	400	1	337.00	346.00	13600.00	13600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	481
402	910269	رياض محمد حسن	+967780709134	\N	قريش جوارmtn	4063661	401	1	641.00	647.00	12800.00	12800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	482
403	910264	منزل احمد ناجي موبايل	777004106	\N	حارة قريش	286513	402	2	508.00	527.00	19000.00	19000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	483
404	910263	العاقل رفيق علي قائد	777604422	\N	حارة قريش	201911069456	403	1	1953.00	1962.00	13600.00	13600.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	484
405	910267	العاقل ماجد ناجي	772283389	\N	حارة قريش	202408080834	404	1	197.00	198.00	2400.00	2400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	485
406	910357	مشترك 910357		\N	الخزانات	202011336023	406	1	65.00	65.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	486
407	910470	بلال محمد عبدالله علي	776152177	\N	قريش ج احمد اليوسفي	20590007285	408	1	74.00	75.00	2400.00	2400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	487
408	910456	ام ميلاد/نورية احمدعبدالغني	773208799	\N	قريش ج الصنديد	250100059761	409	1	6.00	6.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	488
410	910483	عبدة احمد عبدالله علي البريد	735502651	\N	قريش ج بقالة اليوسفي	2019070475	410	1	93.00	95.00	3800.00	3800.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	489
411	910511	نعيم حسن حسن امير	773443060	\N	قريش ج محرم	202508008646	412	1	2.00	3.00	2400.00	2400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	490
412	910457	محرم علي سيف سعيد	783270260	\N	قريش ج هشام محمدعلي	250100059772	413	1	8.00	8.00	1000.00	1000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	491
418	910454	مراقب الجحملية	783270260	\N	الجحملية ج الزعيم	54311	429	1	83081.00	84451.00	1919000.00	1919000.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	494
420	910488	يعقوب المعمري /غاز	783270260	\N	الخزانات مدرسة الثلاياء	202211120279	435	1	918.00	918.00	232400.00	232400.00	Active	f	\N	2026-08-01 00:00:00+03	2026-09-16 22:12:12.696254+03	أغسطس 2	495
\.


--
-- Data for Name: invoices; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.invoices (id, invoice_number, customer_id, reading_id, cycle_id, billing_cycle, previous_reading, current_reading, consumption, consumption_value, kwh_price_snapshot, fixed_fee_snapshot, arrears, total_due, total_amount, paid_amount, remaining_amount, due_date, approval_status, status, is_meter_reset, created_at, updated_at, whatsapp_sent_at, is_printed) FROM stdin;
1	INV-2026-962	1	1	1	أغسطس 2	56900.00	56900.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
2	INV-2026-963	2	2	1	أغسطس 2	44179.00	44179.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
3	INV-2026-964	3	3	1	أغسطس 2	35078.00	35078.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
4	INV-2026-1378	4	4	1	أغسطس 2	1288.00	1288.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	2000.00	0.00	2000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
5	INV-2026-965	5	5	1	أغسطس 2	226.00	226.00	0.00	0.00	1400.00	1000.00	92000.00	93000.00	93000.00	0.00	93000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
7	INV-2026-976	7	7	1	أغسطس 2	282.00	301.00	19.00	26600.00	1400.00	1000.00	100.00	27700.00	27700.00	27700.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
8	INV-2026-1088	8	8	1	أغسطس 2	475.00	482.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	10800.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
9	INV-2026-1089	9	9	1	أغسطس 2	109.00	131.00	22.00	30800.00	1400.00	1000.00	36200.00	68000.00	68000.00	0.00	68000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
10	INV-2026-1090	10	10	1	أغسطس 2	272.00	277.00	5.00	7000.00	1400.00	1000.00	22200.00	30200.00	30200.00	0.00	30200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
11	INV-أغسطس-2-910570	11	11	1	أغسطس 2	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
12	INV-2026-1091	12	12	1	أغسطس 2	1282.00	1308.00	26.00	36400.00	1400.00	1000.00	0.00	37400.00	37400.00	30000.00	7400.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
13	INV-2026-1092	13	13	1	أغسطس 2	549.00	550.00	1.00	1400.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
14	INV-2026-1093	14	14	1	أغسطس 2	959.00	963.00	4.00	5600.00	1400.00	1000.00	2600.00	9200.00	9200.00	9200.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
15	INV-2026-1094	15	15	1	أغسطس 2	979.00	1002.00	23.00	32200.00	1400.00	1000.00	12200.00	45400.00	45400.00	0.00	45400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
16	INV-2026-1095	16	16	1	أغسطس 2	47.00	56.00	9.00	12600.00	1400.00	1000.00	0.00	13600.00	13600.00	13600.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
17	INV-2026-1096	17	17	1	أغسطس 2	519.00	533.00	14.00	19600.00	1400.00	1000.00	0.00	20600.00	20600.00	0.00	20600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
18	INV-2026-1097	18	18	1	أغسطس 2	1045.00	1048.00	3.00	4200.00	1400.00	1000.00	52400.00	57600.00	57600.00	0.00	57600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
19	INV-2026-1098	19	19	1	أغسطس 2	149.00	158.00	9.00	12600.00	1400.00	1000.00	10800.00	24400.00	24400.00	0.00	24400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
20	INV-2026-1099	20	20	1	أغسطس 2	308.00	310.00	2.00	2800.00	1400.00	1000.00	35100.00	38900.00	38900.00	0.00	38900.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
21	INV-2026-1100	21	21	1	أغسطس 2	1527.00	1560.00	33.00	46200.00	1400.00	1000.00	0.00	47200.00	47200.00	47200.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
22	INV-2026-1101	22	22	1	أغسطس 2	86.00	98.00	12.00	16800.00	1400.00	1000.00	0.00	17800.00	17800.00	0.00	17800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
23	INV-2026-977	23	23	1	أغسطس 2	147.00	147.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	1000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
24	INV-2026-1102	24	24	1	أغسطس 2	312.00	324.00	12.00	16800.00	1400.00	1000.00	0.00	17800.00	17800.00	17800.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
25	INV-2026-1103	25	25	1	أغسطس 2	545.00	638.00	93.00	130200.00	1400.00	1000.00	0.00	131200.00	131200.00	131200.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
26	INV-2026-1104	26	26	1	أغسطس 2	687.00	691.00	4.00	5600.00	1400.00	1000.00	9400.00	16000.00	16000.00	16000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
27	INV-2026-1105	27	27	1	أغسطس 2	630.00	642.00	12.00	16800.00	1400.00	1000.00	0.00	17800.00	17800.00	17800.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
28	INV-2026-1106	28	28	1	أغسطس 2	52.00	52.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
29	INV-2026-1107	29	29	1	أغسطس 2	249.00	264.00	15.00	21000.00	1400.00	1000.00	0.00	22000.00	22000.00	22000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
30	INV-2026-1108	30	30	1	أغسطس 2	48.00	49.00	1.00	1400.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
31	INV-2026-1109	31	31	1	أغسطس 2	97.00	98.00	1.00	1400.00	1400.00	1000.00	0.00	2400.00	2400.00	2400.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
32	INV-2026-1110	32	32	1	أغسطس 2	609.00	609.00	0.00	0.00	1400.00	1000.00	119000.00	120000.00	120000.00	0.00	120000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
33	INV-2026-1111	33	33	1	أغسطس 2	186.00	194.00	8.00	11200.00	1400.00	1000.00	6600.00	18800.00	18800.00	13000.00	5800.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
34	INV-2026-1112	34	34	1	أغسطس 2	56.00	58.00	2.00	2800.00	1400.00	1000.00	0.00	3800.00	3800.00	3800.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
35	INV-2026-1113	35	35	1	أغسطس 2	365.00	367.00	2.00	2800.00	1400.00	1000.00	17200.00	21000.00	21000.00	21000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
36	INV-2026-1114	36	36	1	أغسطس 2	121.00	124.00	3.00	4200.00	1400.00	1000.00	400.00	5600.00	5600.00	0.00	5600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
37	INV-2026-1115	37	37	1	أغسطس 2	95.00	99.00	4.00	5600.00	1400.00	1000.00	300.00	6900.00	6900.00	0.00	6900.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
38	INV-2026-1116	38	38	1	أغسطس 2	159.00	172.00	13.00	18200.00	1400.00	1000.00	1000.00	20200.00	20200.00	12000.00	8200.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
39	INV-2026-1117	39	39	1	أغسطس 2	279.00	285.00	6.00	8400.00	1400.00	1000.00	600.00	10000.00	10000.00	9000.00	1000.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
40	INV-2026-978	40	40	1	أغسطس 2	166.00	168.00	2.00	2800.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
41	INV-2026-1118	41	41	1	أغسطس 2	252.00	269.00	17.00	23800.00	1400.00	1000.00	0.00	24800.00	24800.00	0.00	24800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
42	INV-2026-1119	42	42	1	أغسطس 2	232.00	239.00	7.00	9800.00	1400.00	1000.00	1600.00	12400.00	12400.00	0.00	12400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
43	INV-2026-1120	43	43	1	أغسطس 2	443.00	458.00	15.00	21000.00	1400.00	1000.00	400.00	22400.00	22400.00	0.00	22400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
44	INV-2026-1121	44	44	1	أغسطس 2	255.00	263.00	8.00	11200.00	1400.00	1000.00	0.00	12200.00	12200.00	0.00	12200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
45	INV-2026-1122	45	45	1	أغسطس 2	144.00	160.00	16.00	22400.00	1400.00	1000.00	600.00	24000.00	24000.00	0.00	24000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
46	INV-2026-1123	46	46	1	أغسطس 2	685.00	685.00	0.00	0.00	1400.00	1000.00	2000.00	3000.00	3000.00	0.00	3000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
47	INV-2026-1124	47	47	1	أغسطس 2	427.00	430.00	3.00	4200.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
48	INV-2026-1125	48	48	1	أغسطس 2	286.00	296.00	10.00	14000.00	1400.00	1000.00	1000.00	16000.00	16000.00	0.00	16000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
49	INV-2026-1126	49	49	1	أغسطس 2	345.00	352.00	7.00	9800.00	1400.00	1000.00	2400.00	13200.00	13200.00	0.00	13200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
50	INV-2026-1127	50	50	1	أغسطس 2	142.00	147.00	5.00	7000.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
51	INV-2026-979	51	51	1	أغسطس 2	670.00	680.00	10.00	14000.00	1400.00	1000.00	20600.00	35600.00	35600.00	35600.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
52	INV-2026-1128	52	52	1	أغسطس 2	436.00	436.00	0.00	0.00	1400.00	1000.00	2000.00	3000.00	3000.00	0.00	3000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
53	INV-2026-1129	53	53	1	أغسطس 2	641.00	641.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	4800.00	4800.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
54	INV-2026-1130	54	54	1	أغسطس 2	865.00	879.00	14.00	19600.00	1400.00	1000.00	0.00	20600.00	20600.00	0.00	20600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
55	INV-2026-1131	55	55	1	أغسطس 2	1143.00	1147.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
56	INV-2026-1132	56	56	1	أغسطس 2	1064.00	1064.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
57	INV-2026-1133	57	57	1	أغسطس 2	862.00	868.00	6.00	8400.00	1400.00	1000.00	12200.00	21600.00	21600.00	0.00	21600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
58	INV-2026-1134	58	58	1	أغسطس 2	958.00	995.00	37.00	51800.00	1400.00	1000.00	3200.00	56000.00	56000.00	0.00	56000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
59	INV-2026-1135	59	59	1	أغسطس 2	230.00	240.00	10.00	14000.00	1400.00	1000.00	0.00	15000.00	15000.00	0.00	15000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
60	INV-2026-1136	60	60	1	أغسطس 2	333.00	342.00	9.00	12600.00	1400.00	1000.00	400.00	14000.00	14000.00	0.00	14000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
61	INV-2026-1137	61	61	1	أغسطس 2	128.00	135.00	7.00	9800.00	1400.00	1000.00	3600.00	14400.00	14400.00	0.00	14400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
62	INV-2026-980	62	62	1	أغسطس 2	550.00	553.00	3.00	4200.00	1400.00	1000.00	16400.00	21600.00	21600.00	0.00	21600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
63	INV-2026-981	63	63	1	أغسطس 2	169.00	169.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	1000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
64	INV-2026-1138	64	64	1	أغسطس 2	267.00	272.00	5.00	7000.00	1400.00	1000.00	2000.00	10000.00	10000.00	0.00	10000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
65	INV-2026-1139	65	65	1	أغسطس 2	44.00	48.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
66	INV-2026-1140	66	66	1	أغسطس 2	76.00	79.00	3.00	4200.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
67	INV-2026-1141	67	67	1	أغسطس 2	111.00	114.00	3.00	4200.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
68	INV-2026-1142	68	68	1	أغسطس 2	417.00	419.00	2.00	2800.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
69	INV-2026-1143	69	69	1	أغسطس 2	200.00	200.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
70	INV-2026-1144	70	70	1	أغسطس 2	238.00	238.00	0.00	0.00	1400.00	1000.00	15800.00	16800.00	16800.00	0.00	16800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
71	INV-2026-1145	71	71	1	أغسطس 2	3202.00	3373.00	171.00	239400.00	1400.00	1000.00	0.00	240400.00	240400.00	0.00	240400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
72	INV-2026-1146	72	72	1	أغسطس 2	1255.00	1280.00	25.00	35000.00	1400.00	1000.00	33200.00	69200.00	69200.00	0.00	69200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
73	INV-2026-1147	73	73	1	أغسطس 2	29.00	33.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
74	INV-2026-1148	74	74	1	أغسطس 2	4.00	6.00	2.00	2800.00	1400.00	1000.00	2400.00	6200.00	6200.00	0.00	6200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
75	INV-2026-1150	75	75	1	أغسطس 2	415.00	425.00	10.00	14000.00	1400.00	1000.00	3000.00	18000.00	18000.00	0.00	18000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
76	INV-2026-1149	76	76	1	أغسطس 2	971.00	1034.00	63.00	88200.00	1400.00	1000.00	3000.00	92200.00	92200.00	0.00	92200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
77	INV-2026-1151	77	77	1	أغسطس 2	107.00	116.00	9.00	12600.00	1400.00	1000.00	3000.00	16600.00	16600.00	0.00	16600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
78	INV-2026-1152	78	78	1	أغسطس 2	196.00	202.00	6.00	8400.00	1400.00	1000.00	3000.00	12400.00	12400.00	0.00	12400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
79	INV-2026-1153	79	79	1	أغسطس 2	12.00	12.00	0.00	0.00	1400.00	1000.00	33000.00	34000.00	34000.00	0.00	34000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
80	INV-2026-982	80	80	1	أغسطس 2	127.00	130.00	3.00	4200.00	1400.00	1000.00	7900.00	13100.00	13100.00	0.00	13100.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
81	INV-2026-1154	81	81	1	أغسطس 2	555.00	578.00	23.00	32200.00	1400.00	1000.00	33200.00	66400.00	66400.00	0.00	66400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
82	INV-2026-1155	82	82	1	أغسطس 2	0.00	4.00	4.00	5600.00	1400.00	1000.00	1000.00	7600.00	7600.00	7600.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
83	INV-2026-1156	83	83	1	أغسطس 2	180.00	184.00	4.00	5600.00	1400.00	1000.00	3000.00	9600.00	9600.00	0.00	9600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
84	INV-2026-1157	84	84	1	أغسطس 2	447.00	458.00	11.00	15400.00	1400.00	1000.00	3000.00	19400.00	19400.00	14000.00	5400.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
85	INV-2026-1158	85	85	1	أغسطس 2	310.00	329.00	19.00	26600.00	1400.00	1000.00	3000.00	30600.00	30600.00	0.00	30600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
86	INV-2026-1159	86	86	1	أغسطس 2	1017.00	1052.00	35.00	49000.00	1400.00	1000.00	0.00	50000.00	50000.00	0.00	50000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
87	INV-2026-1160	87	87	1	أغسطس 2	741.00	741.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
88	INV-2026-1161	88	88	1	أغسطس 2	241.00	244.00	3.00	4200.00	1400.00	1000.00	0.00	5200.00	5200.00	5200.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
89	INV-2026-1162	89	89	1	أغسطس 2	401.00	401.00	0.00	0.00	1400.00	1000.00	33200.00	34200.00	34200.00	0.00	34200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
90	INV-2026-1163	90	90	1	أغسطس 2	430.00	440.00	10.00	28000.00	2800.00	1000.00	37700.00	66700.00	66700.00	0.00	66700.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
91	INV-2026-1164	91	91	1	أغسطس 2	3987.00	4107.00	120.00	168000.00	1400.00	1000.00	0.00	169000.00	169000.00	0.00	169000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
92	INV-2026-1165	92	92	1	أغسطس 2	480.00	480.00	0.00	0.00	1400.00	1000.00	162000.00	163000.00	163000.00	0.00	163000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
93	INV-2026-983	93	93	1	أغسطس 2	1118.00	1127.00	9.00	12600.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
94	INV-2026-1166	94	94	1	أغسطس 2	309.00	337.00	28.00	39200.00	1400.00	1000.00	300.00	40500.00	40500.00	0.00	40500.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
95	INV-2026-1167	95	95	1	أغسطس 2	12.00	19.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
96	INV-2026-1168	96	96	1	أغسطس 2	178.00	179.00	1.00	1400.00	1400.00	1000.00	0.00	2400.00	2400.00	2300.00	100.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
97	INV-2026-1169	97	97	1	أغسطس 2	258.00	258.00	0.00	0.00	1400.00	1000.00	1800.00	2800.00	2800.00	0.00	2800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
98	INV-2026-1170	98	98	1	أغسطس 2	251.00	266.00	15.00	21000.00	1400.00	1000.00	33100.00	55100.00	55100.00	0.00	55100.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
99	INV-2026-1171	99	99	1	أغسطس 2	1516.00	1522.00	6.00	8400.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
100	INV-2026-1172	100	100	1	أغسطس 2	527.00	535.00	8.00	11200.00	1400.00	1000.00	0.00	12200.00	12200.00	0.00	12200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
101	INV-2026-1173	101	101	1	أغسطس 2	112.00	113.00	1.00	1400.00	1400.00	1000.00	15400.00	17800.00	17800.00	0.00	17800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
102	INV-2026-1174	102	102	1	أغسطس 2	342.00	354.00	12.00	16800.00	1400.00	1000.00	13000.00	30800.00	30800.00	0.00	30800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
103	INV-2026-1175	103	103	1	أغسطس 2	686.00	702.00	16.00	44800.00	2800.00	1000.00	21400.00	67200.00	67200.00	0.00	67200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
104	INV-2026-984	104	104	1	أغسطس 2	85.00	105.00	20.00	28000.00	1400.00	1000.00	0.00	29000.00	29000.00	29000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
105	INV-2026-1176	105	105	1	أغسطس 2	712.00	712.00	0.00	0.00	1400.00	1000.00	218600.00	219600.00	219600.00	0.00	219600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
106	INV-2026-1177	106	106	1	أغسطس 2	303.00	325.00	22.00	30800.00	1400.00	1000.00	0.00	31800.00	31800.00	0.00	31800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
107	INV-2026-1178	107	107	1	أغسطس 2	311.00	319.00	8.00	11200.00	1400.00	1000.00	3200.00	15400.00	15400.00	0.00	15400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
108	INV-2026-1179	108	108	1	أغسطس 2	285.00	286.00	1.00	1400.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
109	INV-2026-1180	109	109	1	أغسطس 2	77.00	86.00	9.00	12600.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
110	INV-2026-1181	110	110	1	أغسطس 2	1156.00	1158.00	2.00	2800.00	1400.00	1000.00	600.00	4400.00	4400.00	0.00	4400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
111	INV-2026-1182	111	111	1	أغسطس 2	1479.00	1480.00	1.00	1400.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
112	INV-2026-1183	112	112	1	أغسطس 2	267.00	267.00	0.00	0.00	1400.00	1000.00	52000.00	53000.00	53000.00	0.00	53000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
113	INV-2026-1184	113	113	1	أغسطس 2	239.00	246.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
114	INV-2026-1185	114	114	1	أغسطس 2	1559.00	1582.00	23.00	32200.00	1400.00	1000.00	0.00	33200.00	33200.00	0.00	33200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
115	INV-2026-985	115	115	1	أغسطس 2	96.00	100.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
116	INV-2026-986	116	116	1	أغسطس 2	58.00	59.00	1.00	1400.00	1400.00	1000.00	5800.00	8200.00	8200.00	0.00	8200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
117	INV-2026-987	117	117	1	أغسطس 2	362.00	367.00	5.00	7000.00	1400.00	1000.00	100.00	8100.00	8100.00	7000.00	1100.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
118	INV-2026-1186	118	118	1	أغسطس 2	533.00	533.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	2000.00	0.00	2000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
119	INV-2026-1187	119	119	1	أغسطس 2	199.00	199.00	0.00	0.00	1400.00	1000.00	20000.00	21000.00	21000.00	0.00	21000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
120	INV-2026-1188	120	120	1	أغسطس 2	752.00	752.00	0.00	0.00	1400.00	1000.00	15000.00	16000.00	16000.00	0.00	16000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
121	INV-2026-1189	121	121	1	أغسطس 2	965.00	971.00	6.00	8400.00	1400.00	1000.00	13400.00	22800.00	22800.00	0.00	22800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
122	INV-2026-1190	122	122	1	أغسطس 2	253.00	254.00	1.00	1400.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
123	INV-2026-1191	123	123	1	أغسطس 2	192.00	192.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
124	INV-2026-1192	124	124	1	أغسطس 2	3007.00	3007.00	0.00	0.00	1400.00	1000.00	32600.00	33600.00	33600.00	0.00	33600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
125	INV-2026-1193	125	125	1	أغسطس 2	91.00	91.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
126	INV-2026-1194	126	126	1	أغسطس 2	383.00	415.00	32.00	44800.00	1400.00	1000.00	0.00	45800.00	45800.00	0.00	45800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
127	INV-2026-1195	127	127	1	أغسطس 2	4576.00	4591.00	15.00	21000.00	1400.00	1000.00	0.00	22000.00	22000.00	0.00	22000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
128	INV-2026-1196	128	128	1	أغسطس 2	48.00	52.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	6600.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
129	INV-2026-1197	129	129	1	أغسطس 2	134.00	134.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
130	INV-2026-1198	130	130	1	أغسطس 2	2462.00	2468.00	6.00	8400.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
131	INV-2026-1199	131	131	1	أغسطس 2	141.00	143.00	2.00	2800.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
132	INV-2026-1200	132	132	1	أغسطس 2	184.00	184.00	0.00	0.00	1400.00	1000.00	99000.00	100000.00	100000.00	0.00	100000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
133	INV-2026-988	133	133	1	أغسطس 2	1857.00	1896.00	39.00	54600.00	1400.00	1000.00	0.00	55600.00	55600.00	0.00	55600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
134	INV-2026-1201	134	134	1	أغسطس 2	669.00	678.00	9.00	12600.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
135	INV-2026-1202	135	135	1	أغسطس 2	3522.00	3543.00	21.00	29400.00	1400.00	1000.00	45800.00	76200.00	76200.00	76200.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
137	INV-2026-1204	137	137	1	أغسطس 2	798.00	830.00	32.00	44800.00	1400.00	1000.00	5300.00	51100.00	51100.00	51000.00	100.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
138	INV-2026-1205	138	138	1	أغسطس 2	1313.00	1318.00	5.00	7000.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
139	INV-2026-1206	139	139	1	أغسطس 2	1314.00	1314.00	0.00	0.00	1400.00	1000.00	45700.00	46700.00	46700.00	0.00	46700.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
140	INV-2026-1207	140	140	1	أغسطس 2	32.00	39.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
141	INV-2026-1208	141	141	1	أغسطس 2	1233.00	1267.00	34.00	47600.00	1400.00	1000.00	20000.00	68600.00	68600.00	0.00	68600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
142	INV-2026-1209	142	142	1	أغسطس 2	915.00	947.00	32.00	44800.00	1400.00	1000.00	0.00	45800.00	45800.00	0.00	45800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
143	INV-2026-1210	143	143	1	أغسطس 2	1205.00	1217.00	12.00	16800.00	1400.00	1000.00	0.00	17800.00	17800.00	0.00	17800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
144	INV-2026-1211	144	144	1	أغسطس 2	664.00	668.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
145	INV-2026-966	145	145	1	أغسطس 2	617.00	635.00	18.00	25200.00	1400.00	1000.00	0.00	26200.00	26200.00	0.00	26200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
146	INV-2026-989	146	146	1	أغسطس 2	498.00	512.00	14.00	19600.00	1400.00	1000.00	0.00	20600.00	20600.00	20000.00	600.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
147	INV-2026-1212	147	147	1	أغسطس 2	1945.00	1966.00	21.00	29400.00	1400.00	1000.00	0.00	30400.00	30400.00	0.00	30400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
148	INV-2026-1213	148	148	1	أغسطس 2	982.00	996.00	14.00	19600.00	1400.00	1000.00	0.00	20600.00	20600.00	0.00	20600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
149	INV-2026-1214	149	149	1	أغسطس 2	132.00	134.00	2.00	2800.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
150	INV-2026-1215	150	150	1	أغسطس 2	61.00	65.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
151	INV-2026-1216	151	151	1	أغسطس 2	453.00	453.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	2000.00	0.00	2000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
152	INV-2026-1217	152	152	1	أغسطس 2	321.00	324.00	3.00	4200.00	1400.00	1000.00	3000.00	8200.00	8200.00	4000.00	4200.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
153	INV-2026-1218	153	153	1	أغسطس 2	243.00	252.00	9.00	12600.00	1400.00	1000.00	1200.00	14800.00	14800.00	14000.00	800.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
154	INV-2026-1219	154	154	1	أغسطس 2	252.00	252.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
155	INV-2026-1220	155	155	1	أغسطس 2	1070.00	1077.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
156	INV-2026-1221	156	156	1	أغسطس 2	220.00	225.00	5.00	7000.00	1400.00	1000.00	6600.00	14600.00	14600.00	0.00	14600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
157	INV-2026-990	157	157	1	أغسطس 2	159.00	162.00	3.00	4200.00	1400.00	1000.00	0.00	5200.00	5200.00	5200.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
158	INV-2026-1222	158	158	1	أغسطس 2	594.00	605.00	11.00	15400.00	1400.00	1000.00	0.00	16400.00	16400.00	0.00	16400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
159	INV-2026-1223	159	159	1	أغسطس 2	572.00	582.00	10.00	14000.00	1400.00	1000.00	400.00	15400.00	15400.00	0.00	15400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
160	INV-2026-1224	160	160	1	أغسطس 2	199.00	200.00	1.00	1400.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
161	INV-2026-1225	161	161	1	أغسطس 2	411.00	411.00	0.00	0.00	1400.00	1000.00	25000.00	26000.00	26000.00	0.00	26000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
162	INV-2026-1226	162	162	1	أغسطس 2	2625.00	2629.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
163	INV-2026-1227	163	163	1	أغسطس 2	206.00	206.00	0.00	0.00	1400.00	1000.00	19000.00	20000.00	20000.00	0.00	20000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
164	INV-2026-1228	164	164	1	أغسطس 2	823.00	827.00	4.00	5600.00	1400.00	1000.00	400.00	7000.00	7000.00	0.00	7000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
165	INV-2026-1229	165	165	1	أغسطس 2	2497.00	2513.00	16.00	22400.00	1400.00	1000.00	0.00	23400.00	23400.00	0.00	23400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
166	INV-2026-1230	166	166	1	أغسطس 2	158.00	172.00	14.00	19600.00	1400.00	1000.00	0.00	20600.00	20600.00	0.00	20600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
167	INV-2026-1231	167	167	1	أغسطس 2	366.00	381.00	15.00	21000.00	1400.00	1000.00	0.00	22000.00	22000.00	0.00	22000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
168	INV-2026-1232	168	168	1	أغسطس 2	176.00	189.00	13.00	18200.00	1400.00	1000.00	3400.00	22600.00	22600.00	0.00	22600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
169	INV-2026-1233	169	169	1	أغسطس 2	90.00	93.00	3.00	4200.00	1400.00	1000.00	200.00	5400.00	5400.00	0.00	5400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
170	INV-2026-1234	170	170	1	أغسطس 2	254.00	266.00	12.00	16800.00	1400.00	1000.00	0.00	17800.00	17800.00	17800.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
171	INV-2026-991	171	171	1	أغسطس 2	727.00	752.00	25.00	35000.00	1400.00	1000.00	0.00	36000.00	36000.00	0.00	36000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
172	INV-2026-1235	172	172	1	أغسطس 2	20.00	20.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
173	INV-2026-1236	173	173	1	أغسطس 2	266.00	284.00	18.00	25200.00	1400.00	1000.00	0.00	26200.00	26200.00	20000.00	6200.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
174	INV-2026-1237	174	174	1	أغسطس 2	273.00	273.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
175	INV-2026-1238	175	175	1	أغسطس 2	70.00	72.00	2.00	2800.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
176	INV-2026-1239	176	176	1	أغسطس 2	156.00	162.00	6.00	8400.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
177	INV-2026-1240	177	177	1	أغسطس 2	2393.00	2407.00	14.00	19600.00	1400.00	1000.00	0.00	20600.00	20600.00	20600.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
178	INV-2026-1241	178	178	1	أغسطس 2	79.00	79.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
179	INV-2026-1242	179	179	1	أغسطس 2	357.00	399.00	42.00	58800.00	1400.00	1000.00	103700.00	163500.00	163500.00	45500.00	118000.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
180	INV-2026-1243	180	180	1	أغسطس 2	341.00	347.00	6.00	8400.00	1400.00	1000.00	9600.00	19000.00	19000.00	0.00	19000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
181	INV-2026-1244	181	181	1	أغسطس 2	464.00	470.00	6.00	8400.00	1400.00	1000.00	2000.00	11400.00	11400.00	0.00	11400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
182	INV-2026-1245	182	182	1	أغسطس 2	74.00	78.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
183	INV-2026-1246	183	183	1	أغسطس 2	1110.00	1126.00	16.00	22400.00	1400.00	1000.00	47200.00	70600.00	70600.00	0.00	70600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
184	INV-2026-1247	184	184	1	أغسطس 2	467.00	485.00	18.00	25200.00	1400.00	1000.00	13600.00	39800.00	39800.00	0.00	39800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
185	INV-2026-992	185	185	1	أغسطس 2	325.00	332.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
186	INV-2026-1248	186	186	1	أغسطس 2	256.00	256.00	0.00	0.00	1400.00	1000.00	14400.00	15400.00	15400.00	0.00	15400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
187	INV-2026-1249	187	187	1	أغسطس 2	35.00	35.00	0.00	0.00	1400.00	1000.00	7000.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
188	INV-2026-1250	188	188	1	أغسطس 2	401.00	407.00	6.00	8400.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
189	INV-2026-1251	189	189	1	أغسطس 2	285.00	285.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
190	INV-2026-1252	190	190	1	أغسطس 2	135.00	140.00	5.00	7000.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
191	INV-2026-1253	191	191	1	أغسطس 2	122.00	126.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
192	INV-2026-1254	192	192	1	أغسطس 2	5245.00	5256.00	11.00	15400.00	1400.00	1000.00	0.00	16400.00	16400.00	0.00	16400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
193	INV-2026-1255	193	193	1	أغسطس 2	109.00	111.00	2.00	2800.00	1400.00	1000.00	2400.00	6200.00	6200.00	0.00	6200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
194	INV-2026-1256	194	194	1	أغسطس 2	1053.00	1056.00	3.00	4200.00	1400.00	1000.00	27000.00	32200.00	32200.00	0.00	32200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
195	INV-2026-993	195	195	1	أغسطس 2	2324.00	2324.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	1000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
196	INV-2026-1257	196	196	1	أغسطس 2	223.00	256.00	33.00	46200.00	1400.00	1000.00	6400.00	53600.00	53600.00	0.00	53600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
197	INV-2026-1258	197	197	1	أغسطس 2	265.00	266.00	1.00	1400.00	1400.00	1000.00	2400.00	4800.00	4800.00	0.00	4800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
198	INV-2026-1259	198	198	1	أغسطس 2	1496.00	1496.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
199	INV-2026-1260	199	199	1	أغسطس 2	1301.00	1311.00	10.00	14000.00	1400.00	1000.00	0.00	15000.00	15000.00	0.00	15000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
200	INV-2026-1261	200	200	1	أغسطس 2	640.00	649.00	9.00	12600.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
201	INV-2026-1262	201	201	1	أغسطس 2	1056.00	1060.00	4.00	5600.00	1400.00	1000.00	6600.00	13200.00	13200.00	0.00	13200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
202	INV-2026-1263	202	202	1	أغسطس 2	5880.00	5899.00	19.00	26600.00	1400.00	1000.00	17600.00	45200.00	45200.00	0.00	45200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
203	INV-2026-1264	203	203	1	أغسطس 2	975.00	993.00	18.00	25200.00	1400.00	1000.00	0.00	26200.00	26200.00	0.00	26200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
204	INV-2026-1265	204	204	1	أغسطس 2	284.00	284.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	4800.00	4800.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
205	INV-2026-1266	205	205	1	أغسطس 2	880.00	894.00	14.00	19600.00	1400.00	1000.00	0.00	20600.00	20600.00	0.00	20600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
206	INV-2026-994	206	206	1	أغسطس 2	190.00	196.00	6.00	8400.00	1400.00	1000.00	0.00	9400.00	9400.00	9400.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
207	INV-2026-1267	207	207	1	أغسطس 2	1044.00	1050.00	6.00	8400.00	1400.00	1000.00	30400.00	39800.00	39800.00	28400.00	11400.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
208	INV-2026-1268	208	208	1	أغسطس 2	52.00	150.00	98.00	137200.00	1400.00	1000.00	73800.00	212000.00	212000.00	73810.00	138190.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
209	INV-2026-1269	209	209	1	أغسطس 2	1064.00	1064.00	0.00	0.00	1400.00	1000.00	75600.00	76600.00	76600.00	0.00	76600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
210	INV-2026-1270	210	210	1	أغسطس 2	2400.00	2422.00	22.00	30800.00	1400.00	1000.00	0.00	31800.00	31800.00	0.00	31800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
211	INV-2026-1271	211	211	1	أغسطس 2	393.00	399.00	6.00	8400.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
212	INV-2026-1272	212	212	1	أغسطس 2	2266.00	2266.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
213	INV-2026-1273	213	213	1	أغسطس 2	344.00	388.00	44.00	61600.00	1400.00	1000.00	0.00	62600.00	62600.00	0.00	62600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
214	INV-2026-1274	214	214	1	أغسطس 2	358.00	370.00	12.00	16800.00	1400.00	1000.00	6000.00	23800.00	23800.00	0.00	23800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
215	INV-2026-1275	215	215	1	أغسطس 2	468.00	476.00	8.00	11200.00	1400.00	1000.00	200.00	12400.00	12400.00	0.00	12400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
216	INV-2026-1276	216	216	1	أغسطس 2	101.00	102.00	1.00	1400.00	1400.00	1000.00	2400.00	4800.00	4800.00	0.00	4800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
217	INV-2026-1277	217	217	1	أغسطس 2	196.00	196.00	0.00	0.00	1400.00	1000.00	56700.00	57700.00	57700.00	0.00	57700.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
218	INV-2026-1278	218	218	1	أغسطس 2	285.00	293.00	8.00	11200.00	1400.00	1000.00	4600.00	16800.00	16800.00	0.00	16800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
219	INV-2026-995	219	219	1	أغسطس 2	220.00	220.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	1000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
220	INV-2026-996	220	220	1	أغسطس 2	44.00	151.00	107.00	149800.00	1400.00	1000.00	0.00	150800.00	150800.00	0.00	150800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
221	INV-2026-1279	221	221	1	أغسطس 2	63.00	64.00	1.00	1400.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
222	INV-2026-1280	222	222	1	أغسطس 2	50.00	54.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
223	INV-2026-1281	223	223	1	أغسطس 2	72.00	76.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
224	INV-2026-1282	224	224	1	أغسطس 2	1127.00	1147.00	20.00	28000.00	1400.00	1000.00	30400.00	59400.00	59400.00	25010.00	34390.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
225	INV-2026-1283	225	225	1	أغسطس 2	71.00	82.00	11.00	15400.00	1400.00	1000.00	0.00	16400.00	16400.00	0.00	16400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
226	INV-2026-1284	226	226	1	أغسطس 2	220.00	225.00	5.00	7000.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
227	INV-2026-1285	227	227	1	أغسطس 2	230.00	244.00	14.00	19600.00	1400.00	1000.00	32000.00	52600.00	52600.00	0.00	52600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
228	INV-2026-1286	228	228	1	أغسطس 2	37.00	39.00	2.00	2800.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
229	INV-2026-1287	229	229	1	أغسطس 2	189.00	196.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	9000.00	1800.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
230	INV-2026-1288	230	230	1	أغسطس 2	85.00	87.00	2.00	2800.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
231	INV-2026-1289	231	231	1	أغسطس 2	58.00	59.00	1.00	1400.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
232	INV-2026-1290	232	232	1	أغسطس 2	1651.00	1651.00	0.00	0.00	1400.00	1000.00	148100.00	149100.00	149100.00	0.00	149100.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
233	INV-2026-1291	233	233	1	أغسطس 2	63.00	75.00	12.00	16800.00	1400.00	1000.00	700.00	18500.00	18500.00	0.00	18500.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
234	INV-2026-1292	234	234	1	أغسطس 2	296.00	296.00	0.00	0.00	1400.00	1000.00	9000.00	10000.00	10000.00	0.00	10000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
235	INV-2026-1293	235	235	1	أغسطس 2	718.00	763.00	45.00	63000.00	1400.00	1000.00	23600.00	87600.00	87600.00	0.00	87600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
236	INV-2026-1294	236	236	1	أغسطس 2	103.00	103.00	0.00	0.00	1400.00	1000.00	5200.00	6200.00	6200.00	0.00	6200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
237	INV-2026-998	237	237	1	أغسطس 2	337.00	343.00	6.00	8400.00	1400.00	1000.00	0.00	9400.00	9400.00	9400.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
238	INV-2026-997	238	238	1	أغسطس 2	228.00	242.00	14.00	19600.00	1400.00	1000.00	0.00	20600.00	20600.00	0.00	20600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
239	INV-2026-1295	239	239	1	أغسطس 2	2162.00	2180.00	18.00	25200.00	1400.00	1000.00	0.00	26200.00	26200.00	0.00	26200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
240	INV-2026-1296	240	240	1	أغسطس 2	360.00	369.00	9.00	12600.00	1400.00	1000.00	25400.00	39000.00	39000.00	0.00	39000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
241	INV-2026-1297	241	241	1	أغسطس 2	1560.00	1573.00	13.00	18200.00	1400.00	1000.00	0.00	19200.00	19200.00	0.00	19200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
242	INV-2026-1298	242	242	1	أغسطس 2	4402.00	4402.00	0.00	0.00	1400.00	1000.00	344300.00	345300.00	345300.00	0.00	345300.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
243	INV-2026-1299	243	243	1	أغسطس 2	5564.00	5564.00	0.00	0.00	1400.00	1000.00	2000.00	3000.00	3000.00	0.00	3000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
244	INV-2026-1300	244	244	1	أغسطس 2	2018.00	2053.00	35.00	49000.00	1400.00	1000.00	2600.00	52600.00	52600.00	0.00	52600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
245	INV-2026-1301	245	245	1	أغسطس 2	641.00	641.00	0.00	0.00	1400.00	1000.00	16800.00	17800.00	17800.00	0.00	17800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
246	INV-2026-1302	246	246	1	أغسطس 2	1040.00	1040.00	0.00	0.00	1400.00	1000.00	15000.00	16000.00	16000.00	0.00	16000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
247	INV-2026-1303	247	247	1	أغسطس 2	269.00	269.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	2000.00	0.00	2000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
248	INV-2026-999	248	248	1	أغسطس 2	566.00	574.00	8.00	11200.00	1400.00	1000.00	0.00	12200.00	12200.00	0.00	12200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
249	INV-2026-1304	249	249	1	أغسطس 2	218.00	223.00	5.00	7000.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
250	INV-2026-1305	250	250	1	أغسطس 2	1222.00	1230.00	8.00	11200.00	1400.00	1000.00	900.00	13100.00	13100.00	0.00	13100.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
251	INV-2026-1306	251	251	1	أغسطس 2	159.00	162.00	3.00	4200.00	1400.00	1000.00	800.00	6000.00	6000.00	0.00	6000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
252	INV-2026-1307	252	252	1	أغسطس 2	1096.00	1114.00	18.00	25200.00	1400.00	1000.00	0.00	26200.00	26200.00	0.00	26200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
253	INV-2026-1308	253	253	1	أغسطس 2	55.00	56.00	1.00	1400.00	1400.00	1000.00	2400.00	4800.00	4800.00	0.00	4800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
254	INV-2026-1309	254	254	1	أغسطس 2	79.00	82.00	3.00	4200.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
255	INV-2026-1310	255	255	1	أغسطس 2	86.00	89.00	3.00	4200.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
256	INV-2026-1311	256	256	1	أغسطس 2	106.00	109.00	3.00	4200.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
257	INV-2026-1312	257	257	1	أغسطس 2	54.00	56.00	2.00	2800.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
258	INV-2026-1313	258	258	1	أغسطس 2	62.00	68.00	6.00	8400.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
259	INV-2026-1314	259	259	1	أغسطس 2	93.00	94.00	1.00	1400.00	1400.00	1000.00	16200.00	18600.00	18600.00	0.00	18600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
260	INV-2026-1315	260	260	1	أغسطس 2	19.00	19.00	0.00	0.00	1400.00	1000.00	20400.00	21400.00	21400.00	0.00	21400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
261	INV-2026-1000	261	261	1	أغسطس 2	391.00	391.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	2000.00	0.00	2000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
262	INV-2026-1316	262	262	1	أغسطس 2	266.00	266.00	0.00	0.00	1400.00	1000.00	2000.00	3000.00	3000.00	0.00	3000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
263	INV-2026-1317	263	263	1	أغسطس 2	1450.00	1450.00	0.00	0.00	1400.00	1000.00	21200.00	22200.00	22200.00	0.00	22200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
264	INV-2026-1318	264	264	1	أغسطس 2	308.00	308.00	0.00	0.00	1400.00	1000.00	75800.00	76800.00	76800.00	0.00	76800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
265	INV-2026-1319	265	265	1	أغسطس 2	466.00	471.00	5.00	7000.00	1400.00	1000.00	64900.00	72900.00	72900.00	0.00	72900.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
266	INV-2026-1320	266	266	1	أغسطس 2	28.00	28.00	0.00	0.00	1400.00	1000.00	2400.00	3400.00	3400.00	0.00	3400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
267	INV-2026-1321	267	267	1	أغسطس 2	1016.00	1025.00	9.00	12600.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
268	INV-2026-1322	268	268	1	أغسطس 2	888.00	888.00	0.00	0.00	1400.00	1000.00	127400.00	128400.00	128400.00	0.00	128400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
269	INV-2026-1323	269	269	1	أغسطس 2	156.00	163.00	7.00	9800.00	1400.00	1000.00	2400.00	13200.00	13200.00	0.00	13200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
270	INV-2026-1324	270	270	1	أغسطس 2	243.00	250.00	7.00	9800.00	1400.00	1000.00	3800.00	14600.00	14600.00	3800.00	10800.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
271	INV-2026-1325	271	271	1	أغسطس 2	3387.00	3391.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
272	INV-2026-1326	272	272	1	أغسطس 2	1217.00	1221.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
273	INV-2026-967	273	273	1	أغسطس 2	294.00	300.00	6.00	8400.00	1400.00	1000.00	600.00	10000.00	10000.00	0.00	10000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
274	INV-2026-1001	274	274	1	أغسطس 2	231.00	239.00	8.00	11200.00	1400.00	1000.00	69000.00	81200.00	81200.00	0.00	81200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
275	INV-2026-1327	275	275	1	أغسطس 2	1426.00	1435.00	9.00	12600.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
276	INV-2026-1328	276	276	1	أغسطس 2	227.00	230.00	3.00	4200.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
277	INV-2026-1329	277	277	1	أغسطس 2	415.00	446.00	31.00	43400.00	1400.00	1000.00	0.00	44400.00	44400.00	0.00	44400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
278	INV-2026-1330	278	278	1	أغسطس 2	300.00	306.00	6.00	8400.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
279	INV-2026-1331	279	279	1	أغسطس 2	154.00	159.00	5.00	7000.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
280	INV-2026-1332	280	280	1	أغسطس 2	563.00	563.00	0.00	0.00	1400.00	1000.00	47000.00	48000.00	48000.00	0.00	48000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
281	INV-2026-1333	281	281	1	أغسطس 2	54.00	59.00	5.00	7000.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
282	INV-2026-1334	282	282	1	أغسطس 2	273.00	281.00	8.00	11200.00	1400.00	1000.00	0.00	12200.00	12200.00	0.00	12200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
283	INV-2026-1335	283	283	1	أغسطس 2	185.00	189.00	4.00	5600.00	1400.00	1000.00	1000.00	7600.00	7600.00	0.00	7600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
284	INV-2026-1336	284	284	1	أغسطس 2	353.00	353.00	0.00	0.00	1400.00	1000.00	4000.00	5000.00	5000.00	0.00	5000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
285	INV-2026-1337	285	285	1	أغسطس 2	1286.00	1296.00	10.00	14000.00	1400.00	1000.00	0.00	15000.00	15000.00	0.00	15000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
286	INV-2026-1002	286	286	1	أغسطس 2	1418.00	1453.00	35.00	49000.00	1400.00	1000.00	7800.00	57800.00	57800.00	50000.00	7800.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
287	INV-2026-1003	287	287	1	أغسطس 2	74.00	88.00	14.00	19600.00	1400.00	1000.00	22000.00	42600.00	42600.00	0.00	42600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
288	INV-2026-1338	288	288	1	أغسطس 2	398.00	408.00	10.00	14000.00	1400.00	1000.00	0.00	15000.00	15000.00	0.00	15000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
289	INV-2026-1339	289	289	1	أغسطس 2	24.00	40.00	16.00	22400.00	1400.00	1000.00	1000.00	24400.00	24400.00	0.00	24400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
290	INV-2026-1340	290	290	1	أغسطس 2	785.00	794.00	9.00	18000.00	2000.00	1000.00	0.00	19000.00	19000.00	0.00	19000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
291	INV-2026-1341	291	291	1	أغسطس 2	912.00	914.00	2.00	2800.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
292	INV-2026-1342	292	292	1	أغسطس 2	88.00	88.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
293	INV-2026-1343	293	293	1	أغسطس 2	456.00	477.00	21.00	29400.00	1400.00	1000.00	16000.00	46400.00	46400.00	0.00	46400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
294	INV-2026-1344	294	294	1	أغسطس 2	188.00	214.00	26.00	36400.00	1400.00	1000.00	153900.00	191300.00	191300.00	0.00	191300.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
295	INV-2026-1345	295	295	1	أغسطس 2	4780.00	4785.00	5.00	7000.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
296	INV-2026-1346	296	296	1	أغسطس 2	261.00	266.00	5.00	7000.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
297	INV-2026-1347	297	297	1	أغسطس 2	440.00	464.00	24.00	33600.00	1400.00	1000.00	26400.00	61000.00	61000.00	0.00	61000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
298	INV-2026-1348	298	298	1	أغسطس 2	3807.00	3846.00	39.00	54600.00	1400.00	1000.00	6700.00	62300.00	62300.00	0.00	62300.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
299	INV-2026-1349	299	299	1	أغسطس 2	2091.00	2109.00	18.00	25200.00	1400.00	1000.00	0.00	26200.00	26200.00	0.00	26200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
300	INV-2026-1004	300	300	1	أغسطس 2	534.00	534.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
301	INV-2026-1350	301	301	1	أغسطس 2	598.00	598.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
302	INV-2026-1351	302	302	1	أغسطس 2	95.00	103.00	8.00	11200.00	1400.00	1000.00	0.00	12200.00	12200.00	5000.00	7200.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
303	INV-2026-1352	303	303	1	أغسطس 2	526.00	537.00	11.00	15400.00	1400.00	1000.00	0.00	16400.00	16400.00	0.00	16400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
304	INV-2026-1353	304	304	1	أغسطس 2	149.00	163.00	14.00	19600.00	1400.00	1000.00	0.00	20600.00	20600.00	0.00	20600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
305	INV-2026-1354	305	305	1	أغسطس 2	134.00	144.00	10.00	14000.00	1400.00	1000.00	0.00	15000.00	15000.00	0.00	15000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
306	INV-2026-1355	306	306	1	أغسطس 2	59.00	65.00	6.00	8400.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
307	INV-2026-1356	307	307	1	أغسطس 2	2410.00	2410.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
308	INV-2026-1357	308	308	1	أغسطس 2	77.00	77.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
309	INV-2026-1358	309	309	1	أغسطس 2	170.00	177.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
310	INV-2026-1359	310	310	1	أغسطس 2	274.00	281.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
311	INV-2026-1360	311	311	1	أغسطس 2	999.00	1006.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
312	INV-2026-1361	312	312	1	أغسطس 2	513.00	518.00	5.00	7000.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
313	INV-2026-1362	313	313	1	أغسطس 2	267.00	268.00	1.00	1400.00	1400.00	1000.00	1000.00	3400.00	3400.00	0.00	3400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
314	INV-2026-1005	314	314	1	أغسطس 2	2462.00	2482.00	20.00	28000.00	1400.00	1000.00	0.00	29000.00	29000.00	0.00	29000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
315	INV-2026-1363	315	315	1	أغسطس 2	207.00	212.00	5.00	7000.00	1400.00	1000.00	2000.00	10000.00	10000.00	0.00	10000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
316	INV-2026-1364	316	316	1	أغسطس 2	232.00	238.00	6.00	8400.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
317	INV-2026-1365	317	317	1	أغسطس 2	98.00	103.00	5.00	7000.00	1400.00	1000.00	0.00	8000.00	8000.00	8000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
318	INV-2026-1366	318	318	1	أغسطس 2	108.00	108.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	2000.00	0.00	2000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
319	INV-2026-1367	319	319	1	أغسطس 2	44.00	47.00	3.00	4200.00	1400.00	1000.00	6600.00	11800.00	11800.00	0.00	11800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
320	INV-2026-1368	320	320	1	أغسطس 2	346.00	349.00	3.00	4200.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
321	INV-2026-1369	321	321	1	أغسطس 2	174.00	174.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
322	INV-2026-1370	322	322	1	أغسطس 2	581.00	590.00	9.00	12600.00	1400.00	1000.00	10000.00	23600.00	23600.00	0.00	23600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
323	INV-2026-1371	323	323	1	أغسطس 2	3484.00	3511.00	27.00	37800.00	1400.00	1000.00	0.00	38800.00	38800.00	38800.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
324	INV-أغسطس-2-910569	324	324	1	أغسطس 2	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
325	INV-2026-1006	325	325	1	أغسطس 2	752.00	775.00	23.00	32200.00	1400.00	1000.00	600.00	33800.00	33800.00	0.00	33800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
326	INV-2026-1372	326	326	1	أغسطس 2	440.00	452.00	12.00	33600.00	2800.00	1000.00	17800.00	52400.00	52400.00	0.00	52400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
327	INV-2026-1373	327	327	1	أغسطس 2	775.00	807.00	32.00	44800.00	1400.00	1000.00	0.00	45800.00	45800.00	45800.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
328	INV-2026-1374	328	328	1	أغسطس 2	51.00	53.00	2.00	2800.00	1400.00	1000.00	1000.00	4800.00	4800.00	0.00	4800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
329	INV-2026-1375	329	329	1	أغسطس 2	8.00	9.00	1.00	1400.00	1400.00	1000.00	10200.00	12600.00	12600.00	0.00	12600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
330	INV-2026-1376	330	330	1	أغسطس 2	79.00	88.00	9.00	12600.00	1400.00	1000.00	600.00	14200.00	14200.00	0.00	14200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
331	INV-2026-1377	331	331	1	أغسطس 2	1685.00	1691.00	6.00	8400.00	1400.00	1000.00	147600.00	157000.00	157000.00	100000.00	57000.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
332	INV-2026-1379	332	332	1	أغسطس 2	321.00	324.00	3.00	4200.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
333	INV-2026-1380	333	333	1	أغسطس 2	446.00	470.00	24.00	33600.00	1400.00	1000.00	0.00	34600.00	34600.00	0.00	34600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
334	INV-2026-1381	334	334	1	أغسطس 2	306.00	322.00	16.00	22400.00	1400.00	1000.00	27500.00	50900.00	50900.00	30000.00	20900.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
335	INV-2026-1382	335	335	1	أغسطس 2	542.00	551.00	9.00	12600.00	1400.00	1000.00	2500.00	16100.00	16100.00	0.00	16100.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
336	INV-2026-1383	336	336	1	أغسطس 2	435.00	446.00	11.00	15400.00	1400.00	1000.00	0.00	16400.00	16400.00	0.00	16400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
337	INV-2026-1384	337	337	1	أغسطس 2	430.00	440.00	10.00	14000.00	1400.00	1000.00	0.00	15000.00	15000.00	0.00	15000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
338	INV-2026-1385	338	338	1	أغسطس 2	28.00	33.00	5.00	7000.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
339	INV-2026-1007	339	339	1	أغسطس 2	156.00	160.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
340	INV-2026-1386	340	340	1	أغسطس 2	654.00	663.00	9.00	12600.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
341	INV-2026-1387	341	341	1	أغسطس 2	850.00	850.00	0.00	0.00	1400.00	1000.00	83500.00	84500.00	84500.00	0.00	84500.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
342	INV-2026-1388	342	342	1	أغسطس 2	298.00	307.00	9.00	12600.00	1400.00	1000.00	600.00	14200.00	14200.00	0.00	14200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
343	INV-2026-1389	343	343	1	أغسطس 2	254.00	260.00	6.00	8400.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
344	INV-2026-1390	344	344	1	أغسطس 2	288.00	294.00	6.00	8400.00	1400.00	1000.00	2000.00	11400.00	11400.00	0.00	11400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
345	INV-2026-1391	345	345	1	أغسطس 2	524.00	537.00	13.00	18200.00	1400.00	1000.00	0.00	19200.00	19200.00	0.00	19200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
346	INV-2026-1392	346	346	1	أغسطس 2	591.00	591.00	0.00	0.00	1400.00	1000.00	58600.00	59600.00	59600.00	0.00	59600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
347	INV-2026-1393	347	347	1	أغسطس 2	77.00	84.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
348	INV-2026-1394	348	348	1	أغسطس 2	162.00	171.00	9.00	12600.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
349	INV-2026-1395	349	349	1	أغسطس 2	123.00	136.00	13.00	18200.00	1400.00	1000.00	1700.00	20900.00	20900.00	0.00	20900.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
350	INV-2026-1396	350	350	1	أغسطس 2	72.00	76.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
351	INV-2026-1397	351	351	1	أغسطس 2	75.00	77.00	2.00	2800.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
352	INV-2026-1398	352	352	1	أغسطس 2	783.00	789.00	6.00	8400.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
353	INV-2026-1008	353	353	1	أغسطس 2	1872.00	1953.00	81.00	113400.00	1400.00	1000.00	19200.00	133600.00	133600.00	0.00	133600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
354	INV-2026-1399	354	354	1	أغسطس 2	27.00	27.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	2000.00	0.00	2000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
355	INV-2026-1400	355	355	1	أغسطس 2	249.00	249.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
356	INV-2026-1401	356	356	1	أغسطس 2	154.00	154.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
357	INV-2026-1402	357	357	1	أغسطس 2	259.00	268.00	9.00	12600.00	1400.00	1000.00	11800.00	25400.00	25400.00	0.00	25400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
358	INV-2026-1403	358	358	1	أغسطس 2	5384.00	5463.00	79.00	110600.00	1400.00	1000.00	219900.00	331500.00	331500.00	0.00	331500.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
359	INV-2026-1404	359	359	1	أغسطس 2	345.00	351.00	6.00	8400.00	1400.00	1000.00	400.00	9800.00	9800.00	0.00	9800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
360	INV-2026-1405	360	360	1	أغسطس 2	1291.00	1298.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
361	INV-2026-1406	361	361	1	أغسطس 2	15.00	15.00	0.00	0.00	1400.00	1000.00	4200.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
362	INV-2026-1407	362	362	1	أغسطس 2	80.00	82.00	2.00	2800.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
363	INV-2026-1408	363	363	1	أغسطس 2	510.00	510.00	0.00	0.00	1400.00	1000.00	2400.00	3400.00	3400.00	0.00	3400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
364	INV-2026-1409	364	364	1	أغسطس 2	831.00	838.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
365	INV-2026-1009	365	365	1	أغسطس 2	326.00	326.00	0.00	0.00	1400.00	1000.00	169900.00	170900.00	170900.00	0.00	170900.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
366	INV-2026-1410	366	366	1	أغسطس 2	37.00	37.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
367	INV-2026-1411	367	367	1	أغسطس 2	68.00	68.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
368	INV-2026-1412	368	368	1	أغسطس 2	297.00	301.00	4.00	5600.00	1400.00	1000.00	5200.00	11800.00	11800.00	11000.00	800.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
369	INV-2026-1413	369	369	1	أغسطس 2	198.00	198.00	0.00	0.00	1400.00	1000.00	7900.00	8900.00	8900.00	0.00	8900.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
370	INV-2026-1414	370	370	1	أغسطس 2	161.00	176.00	15.00	21000.00	1400.00	1000.00	0.00	22000.00	22000.00	0.00	22000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
371	INV-2026-1415	371	371	1	أغسطس 2	323.00	332.00	9.00	12600.00	1400.00	1000.00	300.00	13900.00	13900.00	0.00	13900.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
372	INV-2026-1416	372	372	1	أغسطس 2	219.00	225.00	6.00	8400.00	1400.00	1000.00	300.00	9700.00	9700.00	9000.00	700.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
373	INV-2026-1417	373	373	1	أغسطس 2	65.00	72.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
374	INV-2026-1418	374	374	1	أغسطس 2	494.00	505.00	11.00	15400.00	1400.00	1000.00	1800.00	18200.00	18200.00	0.00	18200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
375	INV-2026-1419	375	375	1	أغسطس 2	232.00	234.00	2.00	2800.00	1400.00	1000.00	5200.00	9000.00	9000.00	9000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
376	INV-2026-1420	376	376	1	أغسطس 2	143.00	144.00	1.00	1400.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
377	INV-2026-1010	377	377	1	أغسطس 2	553.00	559.00	6.00	8400.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
378	INV-2026-1421	378	378	1	أغسطس 2	391.00	408.00	17.00	23800.00	1400.00	1000.00	49200.00	74000.00	74000.00	0.00	74000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
379	INV-2026-1422	379	379	1	أغسطس 2	406.00	410.00	4.00	5600.00	1400.00	1000.00	400.00	7000.00	7000.00	0.00	7000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
380	INV-2026-1423	380	380	1	أغسطس 2	237.00	252.00	15.00	21000.00	1400.00	1000.00	0.00	22000.00	22000.00	22000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
381	INV-2026-1424	381	381	1	أغسطس 2	529.00	540.00	11.00	15400.00	1400.00	1000.00	0.00	16400.00	16400.00	16400.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
382	INV-2026-1425	382	382	1	أغسطس 2	341.00	346.00	5.00	7000.00	1400.00	1000.00	0.00	8000.00	8000.00	8000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
383	INV-2026-1426	383	383	1	أغسطس 2	1542.00	1568.00	26.00	36400.00	1400.00	1000.00	13300.00	50700.00	50700.00	0.00	50700.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
384	INV-2026-1427	384	384	1	أغسطس 2	265.00	273.00	8.00	11200.00	1400.00	1000.00	87200.00	99400.00	99400.00	0.00	99400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
385	INV-2026-1428	385	385	1	أغسطس 2	274.00	279.00	5.00	7000.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
386	INV-2026-1011	386	386	1	أغسطس 2	449.00	452.00	3.00	4200.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
387	INV-2026-1429	387	387	1	أغسطس 2	100.00	102.00	2.00	2800.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
388	INV-2026-1430	388	388	1	أغسطس 2	892.00	902.00	10.00	14000.00	1400.00	1000.00	0.00	15000.00	15000.00	0.00	15000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
389	INV-2026-1431	389	389	1	أغسطس 2	449.00	455.00	6.00	8400.00	1400.00	1000.00	0.00	9400.00	9400.00	9400.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
390	INV-2026-1432	390	390	1	أغسطس 2	124.00	133.00	9.00	12600.00	1400.00	1000.00	0.00	13600.00	13600.00	13600.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
391	INV-2026-1433	391	391	1	أغسطس 2	664.00	667.00	3.00	4200.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
392	INV-2026-1434	392	392	1	أغسطس 2	1856.00	1903.00	47.00	65800.00	1400.00	1000.00	59800.00	126600.00	126600.00	0.00	126600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
393	INV-2026-1435	393	393	1	أغسطس 2	626.00	631.00	5.00	7000.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
394	INV-2026-1436	394	394	1	أغسطس 2	41.00	43.00	2.00	2800.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
395	INV-2026-1437	395	395	1	أغسطس 2	129.00	131.00	2.00	2800.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
396	INV-2026-1438	396	396	1	أغسطس 2	78.00	82.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
397	INV-2026-1439	397	397	1	أغسطس 2	255.00	264.00	9.00	12600.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
398	INV-2026-968	398	398	1	أغسطس 2	224.00	224.00	0.00	0.00	1400.00	1000.00	14400.00	15400.00	15400.00	0.00	15400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
399	INV-2026-1012	399	399	1	أغسطس 2	203.00	213.00	10.00	14000.00	1400.00	1000.00	13600.00	28600.00	28600.00	28600.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
400	INV-2026-1440	400	400	1	أغسطس 2	222.00	231.00	9.00	12600.00	1400.00	1000.00	0.00	13600.00	13600.00	13600.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
401	INV-2026-1441	401	401	1	أغسطس 2	337.00	346.00	9.00	12600.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
402	INV-2026-1442	402	402	1	أغسطس 2	641.00	647.00	6.00	8400.00	1400.00	1000.00	3400.00	12800.00	12800.00	0.00	12800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
403	INV-2026-1443	403	403	1	أغسطس 2	508.00	527.00	19.00	19000.00	1000.00	1000.00	0.00	19000.00	19000.00	0.00	19000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
404	INV-2026-1444	404	404	1	أغسطس 2	1953.00	1962.00	9.00	12600.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
405	INV-2026-1445	405	405	1	أغسطس 2	197.00	198.00	1.00	1400.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
406	INV-2026-1446	406	406	1	أغسطس 2	65.00	65.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
407	INV-2026-1447	407	407	1	أغسطس 2	74.00	75.00	1.00	1400.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
408	INV-2026-1448	408	408	1	أغسطس 2	6.00	6.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
409	INV-2026-1013	409	409	1	أغسطس 2	139.00	139.00	0.00	0.00	1400.00	1000.00	8200.00	9200.00	9200.00	0.00	9200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
410	INV-2026-1449	410	410	1	أغسطس 2	93.00	95.00	2.00	2800.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
411	INV-2026-1450	411	411	1	أغسطس 2	2.00	3.00	1.00	1400.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
412	INV-2026-1451	412	412	1	أغسطس 2	8.00	8.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
413	INV-2026-1452	413	413	1	أغسطس 2	23.00	25.00	2.00	2800.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
414	INV-2026-1015	414	414	1	أغسطس 2	1729.00	1754.00	25.00	35000.00	1400.00	1000.00	0.00	36000.00	36000.00	0.00	36000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
415	INV-2026-1016	415	415	1	أغسطس 2	1580.00	1580.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
416	INV-2026-1014	416	416	1	أغسطس 2	67.00	67.00	0.00	0.00	1400.00	1000.00	3400.00	4400.00	4400.00	0.00	4400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
417	INV-2026-1453	417	417	1	أغسطس 2	1610.00	1610.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
418	INV-2026-1454	418	418	1	أغسطس 2	83081.00	84451.00	1370.00	1918000.00	1400.00	1000.00	0.00	1919000.00	1919000.00	0.00	1919000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
419	INV-2026-1017	419	419	1	أغسطس 2	227.00	227.00	0.00	0.00	1400.00	1000.00	8100.00	9100.00	9100.00	9000.00	100.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
420	INV-2026-1455	420	420	1	أغسطس 2	918.00	918.00	0.00	0.00	1400.00	1000.00	231400.00	232400.00	232400.00	0.00	232400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
421	INV-2026-1018	421	421	1	أغسطس 2	440.00	460.00	20.00	28000.00	1400.00	1000.00	0.00	29000.00	29000.00	0.00	29000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
422	INV-2026-1019	422	422	1	أغسطس 2	13.00	13.00	0.00	0.00	1400.00	1000.00	10000.00	11000.00	11000.00	0.00	11000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
423	INV-2026-1020	423	423	1	أغسطس 2	398.00	402.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
424	INV-2026-1022	424	424	1	أغسطس 2	130.00	130.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
425	INV-2026-1021	425	425	1	أغسطس 2	493.00	513.00	20.00	28000.00	1400.00	1000.00	0.00	29000.00	29000.00	0.00	29000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
426	INV-2026-1023	426	426	1	أغسطس 2	238.00	238.00	0.00	0.00	1400.00	1000.00	3400.00	4400.00	4400.00	0.00	4400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
427	INV-2026-1024	427	427	1	أغسطس 2	1.00	2.00	1.00	1400.00	1400.00	1000.00	1000.00	3400.00	3400.00	0.00	3400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
428	INV-2026-969	428	428	1	أغسطس 2	594.00	594.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	2000.00	0.00	2000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
429	INV-2026-970	429	429	1	أغسطس 2	23.00	27.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	6600.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
430	INV-2026-1025	430	430	1	أغسطس 2	104.00	104.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
431	INV-2026-1026	431	431	1	أغسطس 2	238.00	246.00	8.00	11200.00	1400.00	1000.00	0.00	12200.00	12200.00	0.00	12200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
432	INV-2026-1027	432	432	1	أغسطس 2	273.00	278.00	5.00	7000.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
433	INV-2026-1028	433	433	1	أغسطس 2	324.00	329.00	5.00	7000.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
434	INV-2026-1029	434	434	1	أغسطس 2	585.00	592.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
435	INV-2026-1030	435	435	1	أغسطس 2	699.00	722.00	23.00	32200.00	1400.00	1000.00	0.00	33200.00	33200.00	33200.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
436	INV-2026-1031	436	436	1	أغسطس 2	66.00	70.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
437	INV-2026-1032	437	437	1	أغسطس 2	458.00	465.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
438	INV-2026-1033	438	438	1	أغسطس 2	616.00	648.00	32.00	44800.00	1400.00	1000.00	0.00	45800.00	45800.00	0.00	45800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
439	INV-2026-1034	439	439	1	أغسطس 2	885.00	900.00	15.00	21000.00	1400.00	1000.00	0.00	22000.00	22000.00	0.00	22000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
440	INV-2026-971	440	440	1	أغسطس 2	831.00	833.00	2.00	2800.00	1400.00	1000.00	5200.00	9000.00	9000.00	0.00	9000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
441	INV-2026-972	441	441	1	أغسطس 2	716.00	719.00	3.00	4200.00	1400.00	1000.00	17400.00	22600.00	22600.00	0.00	22600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
442	INV-2026-1035	442	442	1	أغسطس 2	57.00	57.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	1000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
443	INV-2026-1036	443	443	1	أغسطس 2	168.00	172.00	4.00	5600.00	1400.00	1000.00	1000.00	7600.00	7600.00	0.00	7600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
444	INV-2026-1037	444	444	1	أغسطس 2	112.00	112.00	0.00	0.00	1400.00	1000.00	27000.00	28000.00	28000.00	0.00	28000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
445	INV-2026-1038	445	445	1	أغسطس 2	330.00	337.00	7.00	9800.00	1400.00	1000.00	28800.00	39600.00	39600.00	0.00	39600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
446	INV-2026-1039	446	446	1	أغسطس 2	264.00	264.00	0.00	0.00	1400.00	1000.00	70600.00	71600.00	71600.00	0.00	71600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
447	INV-2026-1040	447	447	1	أغسطس 2	589.00	589.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
448	INV-2026-1041	448	448	1	أغسطس 2	83.00	88.00	5.00	7000.00	1400.00	1000.00	200.00	8200.00	8200.00	0.00	8200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
449	INV-2026-1042	449	449	1	أغسطس 2	239.00	239.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
450	INV-2026-1043	450	450	1	أغسطس 2	4016.00	4107.00	91.00	127400.00	1400.00	1000.00	0.00	128400.00	128400.00	0.00	128400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
451	INV-2026-973	451	451	1	أغسطس 2	631.00	644.00	13.00	18200.00	1400.00	1000.00	207400.00	226600.00	226600.00	0.00	226600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
452	INV-2026-1044	452	452	1	أغسطس 2	134.00	149.00	15.00	21000.00	1400.00	1000.00	0.00	22000.00	22000.00	0.00	22000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
453	INV-2026-1045	453	453	1	أغسطس 2	1174.00	1174.00	0.00	0.00	1400.00	1000.00	18600.00	19600.00	19600.00	0.00	19600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
454	INV-2026-1046	454	454	1	أغسطس 2	851.00	851.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
455	INV-2026-1047	455	455	1	أغسطس 2	627.00	645.00	18.00	25200.00	1400.00	1000.00	0.00	26200.00	26200.00	0.00	26200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
456	INV-2026-1048	456	456	1	أغسطس 2	356.00	370.00	14.00	19600.00	1400.00	1000.00	21700.00	42300.00	42300.00	0.00	42300.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
457	INV-2026-1049	457	457	1	أغسطس 2	44.00	48.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
458	INV-2026-1050	458	458	1	أغسطس 2	566.00	579.00	13.00	18200.00	1400.00	1000.00	0.00	19200.00	19200.00	0.00	19200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
459	INV-2026-1051	459	459	1	أغسطس 2	286.00	295.00	9.00	12600.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
460	INV-2026-1052	460	460	1	أغسطس 2	48.00	48.00	0.00	0.00	1400.00	1000.00	44600.00	45600.00	45600.00	0.00	45600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
461	INV-2026-1053	461	461	1	أغسطس 2	132.00	135.00	3.00	4200.00	1400.00	1000.00	4300.00	9500.00	9500.00	0.00	9500.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
462	INV-2026-1054	462	462	1	أغسطس 2	389.00	389.00	0.00	0.00	1400.00	1000.00	200.00	1200.00	1200.00	0.00	1200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
463	INV-2026-1055	463	463	1	أغسطس 2	340.00	347.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
464	INV-2026-1056	464	464	1	أغسطس 2	55.00	62.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	10800.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
465	INV-2026-1057	465	465	1	أغسطس 2	145.00	156.00	11.00	15400.00	1400.00	1000.00	21000.00	37400.00	37400.00	0.00	37400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
466	INV-2026-1058	466	466	1	أغسطس 2	907.00	925.00	18.00	25200.00	1400.00	1000.00	596700.00	622900.00	622900.00	0.00	622900.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
467	INV-2026-1059	467	467	1	أغسطس 2	312.00	327.00	15.00	21000.00	1400.00	1000.00	8000.00	30000.00	30000.00	0.00	30000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
468	INV-أغسطس-2-910571	468	468	1	أغسطس 2	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
469	INV-2026-1060	469	469	1	أغسطس 2	1322.00	1337.00	15.00	21000.00	1400.00	1000.00	5600.00	27600.00	27600.00	0.00	27600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
470	INV-2026-1061	470	470	1	أغسطس 2	1614.00	1614.00	0.00	0.00	1400.00	1000.00	153600.00	154600.00	154600.00	0.00	154600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
471	INV-2026-974	471	471	1	أغسطس 2	0.00	0.00	0.00	0.00	1400.00	1000.00	18000.00	19000.00	19000.00	0.00	19000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
472	INV-2026-1062	472	472	1	أغسطس 2	191.00	197.00	6.00	8400.00	1400.00	1000.00	6600.00	16000.00	16000.00	0.00	16000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
473	INV-2026-1064	473	473	1	أغسطس 2	249.00	249.00	0.00	0.00	1400.00	1000.00	24600.00	25600.00	25600.00	0.00	25600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
474	INV-2026-1063	474	474	1	أغسطس 2	110.00	110.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	2000.00	0.00	2000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
475	INV-2026-1065	475	475	1	أغسطس 2	421.00	450.00	29.00	40600.00	1400.00	1000.00	0.00	41600.00	41600.00	0.00	41600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
476	INV-2026-1066	476	476	1	أغسطس 2	33.00	44.00	11.00	15400.00	1400.00	1000.00	0.00	16400.00	16400.00	0.00	16400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
477	INV-2026-1067	477	477	1	أغسطس 2	40.00	48.00	8.00	11200.00	1400.00	1000.00	11000.00	23200.00	23200.00	0.00	23200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
478	INV-2026-1068	478	478	1	أغسطس 2	93.00	97.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
479	INV-2026-1069	479	479	1	أغسطس 2	23.00	28.00	5.00	7000.00	1400.00	1000.00	800.00	8800.00	8800.00	0.00	8800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
480	INV-2026-1070	480	480	1	أغسطس 2	764.00	792.00	28.00	39200.00	1400.00	1000.00	0.00	40200.00	40200.00	0.00	40200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
481	INV-2026-1071	481	481	1	أغسطس 2	138.00	145.00	7.00	9800.00	1400.00	1000.00	9400.00	20200.00	20200.00	0.00	20200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
482	INV-2026-1072	482	482	1	أغسطس 2	2207.00	2235.00	28.00	39200.00	1400.00	1000.00	0.00	40200.00	40200.00	0.00	40200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
483	INV-2026-1073	483	483	1	أغسطس 2	913.00	920.00	7.00	9800.00	1400.00	1000.00	1100.00	11900.00	11900.00	0.00	11900.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
484	INV-2026-1074	484	484	1	أغسطس 2	1312.00	1360.00	48.00	67200.00	1400.00	1000.00	0.00	68200.00	68200.00	0.00	68200.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
485	INV-2026-1075	485	485	1	أغسطس 2	532.00	540.00	8.00	11200.00	1400.00	1000.00	14600.00	26800.00	26800.00	0.00	26800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
486	INV-2026-975	486	486	1	أغسطس 2	1270.00	1284.00	14.00	19600.00	1400.00	1000.00	53400.00	74000.00	74000.00	50400.00	23600.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
487	INV-2026-1076	487	487	1	أغسطس 2	385.00	392.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	10800.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
488	INV-2026-1077	488	488	1	أغسطس 2	203.00	205.00	2.00	2800.00	1400.00	1000.00	5200.00	9000.00	9000.00	9000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
489	INV-2026-1078	489	489	1	أغسطس 2	328.00	347.00	19.00	26600.00	1400.00	1000.00	0.00	27600.00	27600.00	0.00	27600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
490	INV-2026-1079	490	490	1	أغسطس 2	37.00	41.00	4.00	5600.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
491	INV-2026-1080	491	491	1	أغسطس 2	357.00	364.00	7.00	9800.00	1400.00	1000.00	400.00	11200.00	11200.00	10000.00	1200.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
492	INV-2026-1081	492	492	1	أغسطس 2	368.00	375.00	7.00	9800.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
493	INV-2026-1082	493	493	1	أغسطس 2	65.00	65.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
494	INV-2026-1083	494	494	1	أغسطس 2	175.00	179.00	4.00	5600.00	1400.00	1000.00	800.00	7400.00	7400.00	0.00	7400.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
495	INV-2026-1084	495	495	1	أغسطس 2	150.00	150.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
496	INV-2026-1085	496	496	1	أغسطس 2	234.00	240.00	6.00	8400.00	1400.00	1000.00	6600.00	16000.00	16000.00	0.00	16000.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
497	INV-2026-1086	497	497	1	أغسطس 2	867.00	885.00	18.00	25200.00	1400.00	1000.00	47900.00	74100.00	74100.00	0.00	74100.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
498	INV-2026-1087	498	498	1	أغسطس 2	365.00	377.00	12.00	16800.00	1400.00	1000.00	0.00	17800.00	17800.00	0.00	17800.00	2026-09-10	APPROVED	Unpaid	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03	\N	f
588	INV-سبتمبر-1-910001	1	\N	\N	سبتمبر 1	56900.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.317924+03	\N	f
589	INV-سبتمبر-1-910002	2	\N	\N	سبتمبر 1	44179.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.322714+03	\N	f
590	INV-سبتمبر-1-910004	3	\N	\N	سبتمبر 1	35078.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.326793+03	\N	f
591	INV-سبتمبر-1-910226	4	\N	\N	سبتمبر 1	1288.00	0.00	0.00	0.00	1400.00	1000.00	2000.00	3000.00	1000.00	0.00	3000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.329843+03	\N	f
592	INV-سبتمبر-1-910005	5	\N	\N	سبتمبر 1	226.00	0.00	0.00	0.00	1400.00	1000.00	93000.00	94000.00	1000.00	0.00	94000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.335184+03	\N	f
594	INV-سبتمبر-1-910010	7	\N	\N	سبتمبر 1	301.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.347621+03	\N	f
595	INV-سبتمبر-1-910062	8	\N	\N	سبتمبر 1	482.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.353828+03	\N	f
596	INV-سبتمبر-1-910552	9	\N	\N	سبتمبر 1	131.00	0.00	0.00	0.00	1400.00	1000.00	68000.00	69000.00	1000.00	0.00	69000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.358624+03	\N	f
597	INV-سبتمبر-1-910065	10	\N	\N	سبتمبر 1	277.00	0.00	0.00	0.00	1400.00	1000.00	30200.00	31200.00	1000.00	0.00	31200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.363251+03	\N	f
598	INV-سبتمبر-1-910570	11	\N	\N	سبتمبر 1	0.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.368159+03	\N	f
599	INV-سبتمبر-1-910063	12	\N	\N	سبتمبر 1	1308.00	0.00	0.00	0.00	1400.00	1000.00	7400.00	8400.00	1000.00	0.00	8400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.371809+03	\N	f
600	INV-سبتمبر-1-910066	13	\N	\N	سبتمبر 1	550.00	0.00	0.00	0.00	1400.00	1000.00	2400.00	3400.00	1000.00	0.00	3400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.375759+03	\N	f
601	INV-سبتمبر-1-910070	14	\N	\N	سبتمبر 1	963.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.379659+03	\N	f
602	INV-سبتمبر-1-910069	15	\N	\N	سبتمبر 1	1002.00	0.00	0.00	0.00	1400.00	1000.00	45400.00	46400.00	1000.00	0.00	46400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.384522+03	\N	f
603	INV-سبتمبر-1-910542	16	\N	\N	سبتمبر 1	56.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.38859+03	\N	f
604	INV-سبتمبر-1-910068	17	\N	\N	سبتمبر 1	533.00	0.00	0.00	0.00	1400.00	1000.00	20600.00	21600.00	1000.00	0.00	21600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.392232+03	\N	f
605	INV-سبتمبر-1-910067	18	\N	\N	سبتمبر 1	1048.00	0.00	0.00	0.00	1400.00	1000.00	57600.00	58600.00	1000.00	0.00	58600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.396273+03	\N	f
606	INV-سبتمبر-1-910492	19	\N	\N	سبتمبر 1	158.00	0.00	0.00	0.00	1400.00	1000.00	24400.00	25400.00	1000.00	0.00	25400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.403477+03	\N	f
607	INV-سبتمبر-1-910071	20	\N	\N	سبتمبر 1	310.00	0.00	0.00	0.00	1400.00	1000.00	38900.00	39900.00	1000.00	0.00	39900.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.409002+03	\N	f
608	INV-سبتمبر-1-910072	21	\N	\N	سبتمبر 1	1560.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.413447+03	\N	f
609	INV-سبتمبر-1-910491	22	\N	\N	سبتمبر 1	98.00	0.00	0.00	0.00	1400.00	1000.00	17800.00	18800.00	1000.00	0.00	18800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.419679+03	\N	f
610	INV-سبتمبر-1-910358	23	\N	\N	سبتمبر 1	147.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.424641+03	\N	f
611	INV-سبتمبر-1-910291	24	\N	\N	سبتمبر 1	324.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.43414+03	\N	f
612	INV-سبتمبر-1-910546	25	\N	\N	سبتمبر 1	638.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.440658+03	\N	f
613	INV-سبتمبر-1-910074	26	\N	\N	سبتمبر 1	691.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.446185+03	\N	f
614	INV-سبتمبر-1-910075	27	\N	\N	سبتمبر 1	642.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.453762+03	\N	f
615	INV-سبتمبر-1-910294	28	\N	\N	سبتمبر 1	52.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.459998+03	\N	f
616	INV-سبتمبر-1-910440	29	\N	\N	سبتمبر 1	264.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.466344+03	\N	f
617	INV-سبتمبر-1-910432	30	\N	\N	سبتمبر 1	49.00	0.00	0.00	0.00	1400.00	1000.00	2400.00	3400.00	1000.00	0.00	3400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.473913+03	\N	f
618	INV-سبتمبر-1-910537	31	\N	\N	سبتمبر 1	98.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.478972+03	\N	f
619	INV-سبتمبر-1-910475	32	\N	\N	سبتمبر 1	609.00	0.00	0.00	0.00	1400.00	1000.00	120000.00	121000.00	1000.00	0.00	121000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.488014+03	\N	f
620	INV-سبتمبر-1-910524	33	\N	\N	سبتمبر 1	194.00	0.00	0.00	0.00	1400.00	1000.00	5800.00	6800.00	1000.00	0.00	6800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.49409+03	\N	f
621	INV-سبتمبر-1-910147	34	\N	\N	سبتمبر 1	58.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.498492+03	\N	f
622	INV-سبتمبر-1-910545	35	\N	\N	سبتمبر 1	367.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.505052+03	\N	f
623	INV-سبتمبر-1-910292	36	\N	\N	سبتمبر 1	124.00	0.00	0.00	0.00	1400.00	1000.00	5600.00	6600.00	1000.00	0.00	6600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.509539+03	\N	f
624	INV-سبتمبر-1-910448	37	\N	\N	سبتمبر 1	99.00	0.00	0.00	0.00	1400.00	1000.00	6900.00	7900.00	1000.00	0.00	7900.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.516853+03	\N	f
625	INV-سبتمبر-1-910471	38	\N	\N	سبتمبر 1	172.00	0.00	0.00	0.00	1400.00	1000.00	8200.00	9200.00	1000.00	0.00	9200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.523615+03	\N	f
626	INV-سبتمبر-1-910372	39	\N	\N	سبتمبر 1	285.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.528675+03	\N	f
627	INV-سبتمبر-1-910016	40	\N	\N	سبتمبر 1	168.00	0.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	1000.00	0.00	4800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.534166+03	\N	f
628	INV-سبتمبر-1-910064	41	\N	\N	سبتمبر 1	269.00	0.00	0.00	0.00	1400.00	1000.00	24800.00	25800.00	1000.00	0.00	25800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.537835+03	\N	f
629	INV-سبتمبر-1-910080	42	\N	\N	سبتمبر 1	239.00	0.00	0.00	0.00	1400.00	1000.00	12400.00	13400.00	1000.00	0.00	13400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.541269+03	\N	f
630	INV-سبتمبر-1-910078	43	\N	\N	سبتمبر 1	458.00	0.00	0.00	0.00	1400.00	1000.00	22400.00	23400.00	1000.00	0.00	23400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.545944+03	\N	f
631	INV-سبتمبر-1-910079	44	\N	\N	سبتمبر 1	263.00	0.00	0.00	0.00	1400.00	1000.00	12200.00	13200.00	1000.00	0.00	13200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.549311+03	\N	f
632	INV-سبتمبر-1-910381	45	\N	\N	سبتمبر 1	160.00	0.00	0.00	0.00	1400.00	1000.00	24000.00	25000.00	1000.00	0.00	25000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.554156+03	\N	f
633	INV-سبتمبر-1-910405	46	\N	\N	سبتمبر 1	685.00	0.00	0.00	0.00	1400.00	1000.00	3000.00	4000.00	1000.00	0.00	4000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.561575+03	\N	f
634	INV-سبتمبر-1-910373	47	\N	\N	سبتمبر 1	430.00	0.00	0.00	0.00	1400.00	1000.00	5200.00	6200.00	1000.00	0.00	6200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.568224+03	\N	f
635	INV-سبتمبر-1-910081	48	\N	\N	سبتمبر 1	296.00	0.00	0.00	0.00	1400.00	1000.00	16000.00	17000.00	1000.00	0.00	17000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.572293+03	\N	f
636	INV-سبتمبر-1-910082	49	\N	\N	سبتمبر 1	352.00	0.00	0.00	0.00	1400.00	1000.00	13200.00	14200.00	1000.00	0.00	14200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.577111+03	\N	f
637	INV-سبتمبر-1-910348	50	\N	\N	سبتمبر 1	147.00	0.00	0.00	0.00	1400.00	1000.00	8000.00	9000.00	1000.00	0.00	9000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.581056+03	\N	f
638	INV-سبتمبر-1-910011	51	\N	\N	سبتمبر 1	680.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.586626+03	\N	f
639	INV-سبتمبر-1-910073	52	\N	\N	سبتمبر 1	436.00	0.00	0.00	0.00	1400.00	1000.00	3000.00	4000.00	1000.00	0.00	4000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.590725+03	\N	f
640	INV-سبتمبر-1-910085	53	\N	\N	سبتمبر 1	641.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.59374+03	\N	f
641	INV-سبتمبر-1-910084	54	\N	\N	سبتمبر 1	879.00	0.00	0.00	0.00	1400.00	1000.00	20600.00	21600.00	1000.00	0.00	21600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.597508+03	\N	f
642	INV-سبتمبر-1-910083	55	\N	\N	سبتمبر 1	1147.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.604038+03	\N	f
643	INV-سبتمبر-1-910086	56	\N	\N	سبتمبر 1	1064.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.607701+03	\N	f
644	INV-سبتمبر-1-910365	57	\N	\N	سبتمبر 1	868.00	0.00	0.00	0.00	1400.00	1000.00	21600.00	22600.00	1000.00	0.00	22600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.610876+03	\N	f
645	INV-سبتمبر-1-910087	58	\N	\N	سبتمبر 1	995.00	0.00	0.00	0.00	1400.00	1000.00	56000.00	57000.00	1000.00	0.00	57000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.614069+03	\N	f
646	INV-سبتمبر-1-910092	59	\N	\N	سبتمبر 1	240.00	0.00	0.00	0.00	1400.00	1000.00	15000.00	16000.00	1000.00	0.00	16000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.618466+03	\N	f
647	INV-سبتمبر-1-910090	60	\N	\N	سبتمبر 1	342.00	0.00	0.00	0.00	1400.00	1000.00	14000.00	15000.00	1000.00	0.00	15000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.622711+03	\N	f
648	INV-سبتمبر-1-910089	61	\N	\N	سبتمبر 1	135.00	0.00	0.00	0.00	1400.00	1000.00	14400.00	15400.00	1000.00	0.00	15400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.625853+03	\N	f
649	INV-سبتمبر-1-910012	62	\N	\N	سبتمبر 1	553.00	0.00	0.00	0.00	1400.00	1000.00	21600.00	22600.00	1000.00	0.00	22600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.628252+03	\N	f
650	INV-سبتمبر-1-910525	63	\N	\N	سبتمبر 1	169.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.633385+03	\N	f
651	INV-سبتمبر-1-910091	64	\N	\N	سبتمبر 1	272.00	0.00	0.00	0.00	1400.00	1000.00	10000.00	11000.00	1000.00	0.00	11000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.63699+03	\N	f
652	INV-سبتمبر-1-910452	65	\N	\N	سبتمبر 1	48.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.640899+03	\N	f
653	INV-سبتمبر-1-910088	66	\N	\N	سبتمبر 1	79.00	0.00	0.00	0.00	1400.00	1000.00	5200.00	6200.00	1000.00	0.00	6200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.644227+03	\N	f
654	INV-سبتمبر-1-910384	67	\N	\N	سبتمبر 1	114.00	0.00	0.00	0.00	1400.00	1000.00	5200.00	6200.00	1000.00	0.00	6200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.647609+03	\N	f
655	INV-سبتمبر-1-910093	68	\N	\N	سبتمبر 1	419.00	0.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	1000.00	0.00	4800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.652277+03	\N	f
656	INV-سبتمبر-1-910276	69	\N	\N	سبتمبر 1	200.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.656463+03	\N	f
657	INV-سبتمبر-1-910404	70	\N	\N	سبتمبر 1	238.00	0.00	0.00	0.00	1400.00	1000.00	16800.00	17800.00	1000.00	0.00	17800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.659597+03	\N	f
658	INV-سبتمبر-1-910183	71	\N	\N	سبتمبر 1	3373.00	0.00	0.00	0.00	1400.00	1000.00	240400.00	241400.00	1000.00	0.00	241400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.662394+03	\N	f
659	INV-سبتمبر-1-910495	72	\N	\N	سبتمبر 1	1280.00	0.00	0.00	0.00	1400.00	1000.00	69200.00	70200.00	1000.00	0.00	70200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.66711+03	\N	f
660	INV-سبتمبر-1-910534	73	\N	\N	سبتمبر 1	33.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.670928+03	\N	f
661	INV-سبتمبر-1-910563	74	\N	\N	سبتمبر 1	6.00	0.00	0.00	0.00	1400.00	1000.00	6200.00	7200.00	1000.00	0.00	7200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.674771+03	\N	f
662	INV-سبتمبر-1-910250	75	\N	\N	سبتمبر 1	425.00	0.00	0.00	0.00	1400.00	1000.00	18000.00	19000.00	1000.00	0.00	19000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.677474+03	\N	f
663	INV-سبتمبر-1-910420	76	\N	\N	سبتمبر 1	1034.00	0.00	0.00	0.00	1400.00	1000.00	92200.00	93200.00	1000.00	0.00	93200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.681129+03	\N	f
664	INV-سبتمبر-1-910506	77	\N	\N	سبتمبر 1	116.00	0.00	0.00	0.00	1400.00	1000.00	16600.00	17600.00	1000.00	0.00	17600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.685492+03	\N	f
665	INV-سبتمبر-1-910417	78	\N	\N	سبتمبر 1	202.00	0.00	0.00	0.00	1400.00	1000.00	12400.00	13400.00	1000.00	0.00	13400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.688596+03	\N	f
666	INV-سبتمبر-1-910109	79	\N	\N	سبتمبر 1	12.00	0.00	0.00	0.00	1400.00	1000.00	34000.00	35000.00	1000.00	0.00	35000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.691771+03	\N	f
667	INV-سبتمبر-1-910307	80	\N	\N	سبتمبر 1	130.00	0.00	0.00	0.00	1400.00	1000.00	13100.00	14100.00	1000.00	0.00	14100.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.694774+03	\N	f
668	INV-سبتمبر-1-910107	81	\N	\N	سبتمبر 1	578.00	0.00	0.00	0.00	1400.00	1000.00	66400.00	67400.00	1000.00	0.00	67400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.698653+03	\N	f
669	INV-سبتمبر-1-910567	82	\N	\N	سبتمبر 1	4.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.702621+03	\N	f
670	INV-سبتمبر-1-910060	83	\N	\N	سبتمبر 1	184.00	0.00	0.00	0.00	1400.00	1000.00	9600.00	10600.00	1000.00	0.00	10600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.705913+03	\N	f
671	INV-سبتمبر-1-910095	84	\N	\N	سبتمبر 1	458.00	0.00	0.00	0.00	1400.00	1000.00	5400.00	6400.00	1000.00	0.00	6400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.708685+03	\N	f
672	INV-سبتمبر-1-910515	85	\N	\N	سبتمبر 1	329.00	0.00	0.00	0.00	1400.00	1000.00	30600.00	31600.00	1000.00	0.00	31600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.713422+03	\N	f
673	INV-سبتمبر-1-910097	86	\N	\N	سبتمبر 1	1052.00	0.00	0.00	0.00	1400.00	1000.00	50000.00	51000.00	1000.00	0.00	51000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.718114+03	\N	f
674	INV-سبتمبر-1-910098	87	\N	\N	سبتمبر 1	741.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.720919+03	\N	f
675	INV-سبتمبر-1-910099	88	\N	\N	سبتمبر 1	244.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.725146+03	\N	f
676	INV-سبتمبر-1-910094	89	\N	\N	سبتمبر 1	401.00	0.00	0.00	0.00	1400.00	1000.00	34200.00	35200.00	1000.00	0.00	35200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.728171+03	\N	f
677	INV-سبتمبر-1-910330	90	\N	\N	سبتمبر 1	440.00	0.00	0.00	0.00	1400.00	1000.00	66700.00	67700.00	1000.00	0.00	67700.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.733015+03	\N	f
678	INV-سبتمبر-1-910100	91	\N	\N	سبتمبر 1	4107.00	0.00	0.00	0.00	1400.00	1000.00	169000.00	170000.00	1000.00	0.00	170000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.737051+03	\N	f
679	INV-سبتمبر-1-910389	92	\N	\N	سبتمبر 1	480.00	0.00	0.00	0.00	1400.00	1000.00	163000.00	164000.00	1000.00	0.00	164000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.739829+03	\N	f
680	INV-سبتمبر-1-910015	93	\N	\N	سبتمبر 1	1127.00	0.00	0.00	0.00	1400.00	1000.00	13600.00	14600.00	1000.00	0.00	14600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.742947+03	\N	f
681	INV-سبتمبر-1-910101	94	\N	\N	سبتمبر 1	337.00	0.00	0.00	0.00	1400.00	1000.00	40500.00	41500.00	1000.00	0.00	41500.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.747124+03	\N	f
682	INV-سبتمبر-1-910544	95	\N	\N	سبتمبر 1	19.00	0.00	0.00	0.00	1400.00	1000.00	10800.00	11800.00	1000.00	0.00	11800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.751864+03	\N	f
683	INV-سبتمبر-1-910558	96	\N	\N	سبتمبر 1	179.00	0.00	0.00	0.00	1400.00	1000.00	100.00	1100.00	1000.00	0.00	1100.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.755309+03	\N	f
684	INV-سبتمبر-1-910353	97	\N	\N	سبتمبر 1	258.00	0.00	0.00	0.00	1400.00	1000.00	2800.00	3800.00	1000.00	0.00	3800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.759108+03	\N	f
685	INV-سبتمبر-1-910375	98	\N	\N	سبتمبر 1	266.00	0.00	0.00	0.00	1400.00	1000.00	55100.00	56100.00	1000.00	0.00	56100.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.762529+03	\N	f
686	INV-سبتمبر-1-910105	99	\N	\N	سبتمبر 1	1522.00	0.00	0.00	0.00	1400.00	1000.00	9400.00	10400.00	1000.00	0.00	10400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.766937+03	\N	f
687	INV-سبتمبر-1-910106	100	\N	\N	سبتمبر 1	535.00	0.00	0.00	0.00	1400.00	1000.00	12200.00	13200.00	1000.00	0.00	13200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.770733+03	\N	f
688	INV-سبتمبر-1-910430	101	\N	\N	سبتمبر 1	113.00	0.00	0.00	0.00	1400.00	1000.00	17800.00	18800.00	1000.00	0.00	18800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.774312+03	\N	f
689	INV-سبتمبر-1-910104	102	\N	\N	سبتمبر 1	354.00	0.00	0.00	0.00	1400.00	1000.00	30800.00	31800.00	1000.00	0.00	31800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.777813+03	\N	f
690	INV-سبتمبر-1-910397	103	\N	\N	سبتمبر 1	702.00	0.00	0.00	0.00	1400.00	1000.00	67200.00	68200.00	1000.00	0.00	68200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.781834+03	\N	f
691	INV-سبتمبر-1-910437	104	\N	\N	سبتمبر 1	105.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.78685+03	\N	f
692	INV-سبتمبر-1-910061	105	\N	\N	سبتمبر 1	712.00	0.00	0.00	0.00	1400.00	1000.00	219600.00	220600.00	1000.00	0.00	220600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.790469+03	\N	f
693	INV-سبتمبر-1-910277	106	\N	\N	سبتمبر 1	325.00	0.00	0.00	0.00	1400.00	1000.00	31800.00	32800.00	1000.00	0.00	32800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.794095+03	\N	f
694	INV-سبتمبر-1-910393	107	\N	\N	سبتمبر 1	319.00	0.00	0.00	0.00	1400.00	1000.00	15400.00	16400.00	1000.00	0.00	16400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.797686+03	\N	f
695	INV-سبتمبر-1-910304	108	\N	\N	سبتمبر 1	286.00	0.00	0.00	0.00	1400.00	1000.00	2400.00	3400.00	1000.00	0.00	3400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.802232+03	\N	f
696	INV-سبتمبر-1-910368	109	\N	\N	سبتمبر 1	86.00	0.00	0.00	0.00	1400.00	1000.00	13600.00	14600.00	1000.00	0.00	14600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.80553+03	\N	f
697	INV-سبتمبر-1-910433	110	\N	\N	سبتمبر 1	1158.00	0.00	0.00	0.00	1400.00	1000.00	4400.00	5400.00	1000.00	0.00	5400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.809871+03	\N	f
698	INV-سبتمبر-1-910493	111	\N	\N	سبتمبر 1	1480.00	0.00	0.00	0.00	1400.00	1000.00	2400.00	3400.00	1000.00	0.00	3400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.813731+03	\N	f
699	INV-سبتمبر-1-910386	112	\N	\N	سبتمبر 1	267.00	0.00	0.00	0.00	1400.00	1000.00	53000.00	54000.00	1000.00	0.00	54000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.81833+03	\N	f
700	INV-سبتمبر-1-910354	113	\N	\N	سبتمبر 1	246.00	0.00	0.00	0.00	1400.00	1000.00	10800.00	11800.00	1000.00	0.00	11800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.824575+03	\N	f
701	INV-سبتمبر-1-910108	114	\N	\N	سبتمبر 1	1582.00	0.00	0.00	0.00	1400.00	1000.00	33200.00	34200.00	1000.00	0.00	34200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.828627+03	\N	f
702	INV-سبتمبر-1-910390	115	\N	\N	سبتمبر 1	100.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.831616+03	\N	f
703	INV-سبتمبر-1-910442	116	\N	\N	سبتمبر 1	59.00	0.00	0.00	0.00	1400.00	1000.00	8200.00	9200.00	1000.00	0.00	9200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.835981+03	\N	f
704	INV-سبتمبر-1-910444	117	\N	\N	سبتمبر 1	367.00	0.00	0.00	0.00	1400.00	1000.00	1100.00	2100.00	1000.00	0.00	2100.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.839533+03	\N	f
705	INV-سبتمبر-1-910110	118	\N	\N	سبتمبر 1	533.00	0.00	0.00	0.00	1400.00	1000.00	2000.00	3000.00	1000.00	0.00	3000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.842905+03	\N	f
706	INV-سبتمبر-1-910111	119	\N	\N	سبتمبر 1	199.00	0.00	0.00	0.00	1400.00	1000.00	21000.00	22000.00	1000.00	0.00	22000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.845676+03	\N	f
707	INV-سبتمبر-1-910363	120	\N	\N	سبتمبر 1	752.00	0.00	0.00	0.00	1400.00	1000.00	16000.00	17000.00	1000.00	0.00	17000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.849634+03	\N	f
708	INV-سبتمبر-1-910138	121	\N	\N	سبتمبر 1	971.00	0.00	0.00	0.00	1400.00	1000.00	22800.00	23800.00	1000.00	0.00	23800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.853961+03	\N	f
709	INV-سبتمبر-1-910484	122	\N	\N	سبتمبر 1	254.00	0.00	0.00	0.00	1400.00	1000.00	2400.00	3400.00	1000.00	0.00	3400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.85703+03	\N	f
710	INV-سبتمبر-1-910485	123	\N	\N	سبتمبر 1	192.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.860672+03	\N	f
711	INV-سبتمبر-1-910379	124	\N	\N	سبتمبر 1	3007.00	0.00	0.00	0.00	1400.00	1000.00	33600.00	34600.00	1000.00	0.00	34600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.863483+03	\N	f
712	INV-سبتمبر-1-910115	125	\N	\N	سبتمبر 1	91.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.868249+03	\N	f
713	INV-سبتمبر-1-910447	126	\N	\N	سبتمبر 1	415.00	0.00	0.00	0.00	1400.00	1000.00	45800.00	46800.00	1000.00	0.00	46800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.872265+03	\N	f
714	INV-سبتمبر-1-910116	127	\N	\N	سبتمبر 1	4591.00	0.00	0.00	0.00	1400.00	1000.00	22000.00	23000.00	1000.00	0.00	23000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.875709+03	\N	f
715	INV-سبتمبر-1-910514	128	\N	\N	سبتمبر 1	52.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.881489+03	\N	f
716	INV-سبتمبر-1-910117	129	\N	\N	سبتمبر 1	134.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.886135+03	\N	f
717	INV-سبتمبر-1-910118	130	\N	\N	سبتمبر 1	2468.00	0.00	0.00	0.00	1400.00	1000.00	9400.00	10400.00	1000.00	0.00	10400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.889167+03	\N	f
718	INV-سبتمبر-1-910458	131	\N	\N	سبتمبر 1	143.00	0.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	1000.00	0.00	4800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.892721+03	\N	f
719	INV-سبتمبر-1-910503	132	\N	\N	سبتمبر 1	184.00	0.00	0.00	0.00	1400.00	1000.00	100000.00	101000.00	1000.00	0.00	101000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.896669+03	\N	f
720	INV-سبتمبر-1-910382	133	\N	\N	سبتمبر 1	1896.00	0.00	0.00	0.00	1400.00	1000.00	55600.00	56600.00	1000.00	0.00	56600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.901599+03	\N	f
721	INV-سبتمبر-1-910114	134	\N	\N	سبتمبر 1	678.00	0.00	0.00	0.00	1400.00	1000.00	13600.00	14600.00	1000.00	0.00	14600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.90449+03	\N	f
722	INV-سبتمبر-1-910113	135	\N	\N	سبتمبر 1	3543.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.908803+03	\N	f
136	INV-2026-1203	136	136	1	أغسطس 2	573.00	574.00	1.00	1400.00	1400.00	1000.00	0.00	2400.00	2400.00	21600.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-01 10:00:00+03	2026-09-17 07:44:11.911682+03	\N	f
724	INV-سبتمبر-1-910112	137	\N	\N	سبتمبر 1	830.00	0.00	0.00	0.00	1400.00	1000.00	100.00	1100.00	1000.00	0.00	1100.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.919473+03	\N	f
725	INV-سبتمبر-1-910119	138	\N	\N	سبتمبر 1	1318.00	0.00	0.00	0.00	1400.00	1000.00	8000.00	9000.00	1000.00	0.00	9000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.923086+03	\N	f
726	INV-سبتمبر-1-910278	139	\N	\N	سبتمبر 1	1314.00	0.00	0.00	0.00	1400.00	1000.00	46700.00	47700.00	1000.00	0.00	47700.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.927849+03	\N	f
727	INV-سبتمبر-1-910559	140	\N	\N	سبتمبر 1	39.00	0.00	0.00	0.00	1400.00	1000.00	10800.00	11800.00	1000.00	0.00	11800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.931523+03	\N	f
728	INV-سبتمبر-1-910120	141	\N	\N	سبتمبر 1	1267.00	0.00	0.00	0.00	1400.00	1000.00	68600.00	69600.00	1000.00	0.00	69600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.935831+03	\N	f
729	INV-سبتمبر-1-910121	142	\N	\N	سبتمبر 1	947.00	0.00	0.00	0.00	1400.00	1000.00	45800.00	46800.00	1000.00	0.00	46800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.938725+03	\N	f
730	INV-سبتمبر-1-910122	143	\N	\N	سبتمبر 1	1217.00	0.00	0.00	0.00	1400.00	1000.00	17800.00	18800.00	1000.00	0.00	18800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.942374+03	\N	f
731	INV-سبتمبر-1-910125	144	\N	\N	سبتمبر 1	668.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.9465+03	\N	f
732	INV-سبتمبر-1-910096	145	\N	\N	سبتمبر 1	635.00	0.00	0.00	0.00	1400.00	1000.00	26200.00	27200.00	1000.00	0.00	27200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.951725+03	\N	f
733	INV-سبتمبر-1-910288	146	\N	\N	سبتمبر 1	512.00	0.00	0.00	0.00	1400.00	1000.00	600.00	1600.00	1000.00	0.00	1600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.956433+03	\N	f
734	INV-سبتمبر-1-910126	147	\N	\N	سبتمبر 1	1966.00	0.00	0.00	0.00	1400.00	1000.00	30400.00	31400.00	1000.00	0.00	31400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.96025+03	\N	f
735	INV-سبتمبر-1-910124	148	\N	\N	سبتمبر 1	996.00	0.00	0.00	0.00	1400.00	1000.00	20600.00	21600.00	1000.00	0.00	21600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.964404+03	\N	f
736	INV-سبتمبر-1-910346	149	\N	\N	سبتمبر 1	134.00	0.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	1000.00	0.00	4800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.968998+03	\N	f
737	INV-سبتمبر-1-910127	150	\N	\N	سبتمبر 1	65.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.972463+03	\N	f
738	INV-سبتمبر-1-910128	151	\N	\N	سبتمبر 1	453.00	0.00	0.00	0.00	1400.00	1000.00	2000.00	3000.00	1000.00	0.00	3000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.977231+03	\N	f
739	INV-سبتمبر-1-910129	152	\N	\N	سبتمبر 1	324.00	0.00	0.00	0.00	1400.00	1000.00	4200.00	5200.00	1000.00	0.00	5200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.983504+03	\N	f
740	INV-سبتمبر-1-910130	153	\N	\N	سبتمبر 1	252.00	0.00	0.00	0.00	1400.00	1000.00	800.00	1800.00	1000.00	0.00	1800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.989109+03	\N	f
741	INV-سبتمبر-1-910131	154	\N	\N	سبتمبر 1	252.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.993357+03	\N	f
742	INV-سبتمبر-1-910132	155	\N	\N	سبتمبر 1	1077.00	0.00	0.00	0.00	1400.00	1000.00	10800.00	11800.00	1000.00	0.00	11800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:11.996654+03	\N	f
743	INV-سبتمبر-1-910133	156	\N	\N	سبتمبر 1	225.00	0.00	0.00	0.00	1400.00	1000.00	14600.00	15600.00	1000.00	0.00	15600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.003026+03	\N	f
744	INV-سبتمبر-1-910414	157	\N	\N	سبتمبر 1	162.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.007524+03	\N	f
723	INV-سبتمبر-1-910364	136	\N	\N	سبتمبر 1	574.00	0.00	0.00	0.00	1400.00	1000.00	-19200.00	-18200.00	1000.00	0.00	0.00	2026-09-27	PENDING	Paid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:49:39.81329+03	\N	f
745	INV-سبتمبر-1-910134	158	\N	\N	سبتمبر 1	605.00	0.00	0.00	0.00	1400.00	1000.00	16400.00	17400.00	1000.00	0.00	17400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.011463+03	\N	f
746	INV-سبتمبر-1-910135	159	\N	\N	سبتمبر 1	582.00	0.00	0.00	0.00	1400.00	1000.00	15400.00	16400.00	1000.00	0.00	16400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.018018+03	\N	f
747	INV-سبتمبر-1-910532	160	\N	\N	سبتمبر 1	200.00	0.00	0.00	0.00	1400.00	1000.00	2400.00	3400.00	1000.00	0.00	3400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.022958+03	\N	f
748	INV-سبتمبر-1-910136	161	\N	\N	سبتمبر 1	411.00	0.00	0.00	0.00	1400.00	1000.00	26000.00	27000.00	1000.00	0.00	27000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.026821+03	\N	f
749	INV-سبتمبر-1-910139	162	\N	\N	سبتمبر 1	2629.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.02978+03	\N	f
750	INV-سبتمبر-1-910439	163	\N	\N	سبتمبر 1	206.00	0.00	0.00	0.00	1400.00	1000.00	20000.00	21000.00	1000.00	0.00	21000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.036343+03	\N	f
751	INV-سبتمبر-1-910137	164	\N	\N	سبتمبر 1	827.00	0.00	0.00	0.00	1400.00	1000.00	7000.00	8000.00	1000.00	0.00	8000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.040436+03	\N	f
752	INV-سبتمبر-1-910411	165	\N	\N	سبتمبر 1	2513.00	0.00	0.00	0.00	1400.00	1000.00	23400.00	24400.00	1000.00	0.00	24400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.04465+03	\N	f
753	INV-سبتمبر-1-910472	166	\N	\N	سبتمبر 1	172.00	0.00	0.00	0.00	1400.00	1000.00	20600.00	21600.00	1000.00	0.00	21600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.049892+03	\N	f
754	INV-سبتمبر-1-910474	167	\N	\N	سبتمبر 1	381.00	0.00	0.00	0.00	1400.00	1000.00	22000.00	23000.00	1000.00	0.00	23000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.055458+03	\N	f
755	INV-سبتمبر-1-910418	168	\N	\N	سبتمبر 1	189.00	0.00	0.00	0.00	1400.00	1000.00	22600.00	23600.00	1000.00	0.00	23600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.059539+03	\N	f
756	INV-سبتمبر-1-910424	169	\N	\N	سبتمبر 1	93.00	0.00	0.00	0.00	1400.00	1000.00	5400.00	6400.00	1000.00	0.00	6400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.064394+03	\N	f
757	INV-سبتمبر-1-910385	170	\N	\N	سبتمبر 1	266.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.070185+03	\N	f
758	INV-سبتمبر-1-910289	171	\N	\N	سبتمبر 1	752.00	0.00	0.00	0.00	1400.00	1000.00	36000.00	37000.00	1000.00	0.00	37000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.074178+03	\N	f
759	INV-سبتمبر-1-910306	172	\N	\N	سبتمبر 1	20.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.077461+03	\N	f
760	INV-سبتمبر-1-910504	173	\N	\N	سبتمبر 1	284.00	0.00	0.00	0.00	1400.00	1000.00	6200.00	7200.00	1000.00	0.00	7200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.080432+03	\N	f
761	INV-سبتمبر-1-910282	174	\N	\N	سبتمبر 1	273.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.086294+03	\N	f
762	INV-سبتمبر-1-910305	175	\N	\N	سبتمبر 1	72.00	0.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	1000.00	0.00	4800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.089458+03	\N	f
763	INV-سبتمبر-1-910298	176	\N	\N	سبتمبر 1	162.00	0.00	0.00	0.00	1400.00	1000.00	9400.00	10400.00	1000.00	0.00	10400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.092626+03	\N	f
764	INV-سبتمبر-1-910141	177	\N	\N	سبتمبر 1	2407.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.096232+03	\N	f
765	INV-سبتمبر-1-910498	178	\N	\N	سبتمبر 1	79.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.10108+03	\N	f
766	INV-سبتمبر-1-910528	179	\N	\N	سبتمبر 1	399.00	0.00	0.00	0.00	1400.00	1000.00	118000.00	119000.00	1000.00	0.00	119000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.105405+03	\N	f
767	INV-سبتمبر-1-910551	180	\N	\N	سبتمبر 1	347.00	0.00	0.00	0.00	1400.00	1000.00	19000.00	20000.00	1000.00	0.00	20000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.108661+03	\N	f
768	INV-سبتمبر-1-910553	181	\N	\N	سبتمبر 1	470.00	0.00	0.00	0.00	1400.00	1000.00	11400.00	12400.00	1000.00	0.00	12400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.111539+03	\N	f
769	INV-سبتمبر-1-910450	182	\N	\N	سبتمبر 1	78.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.116976+03	\N	f
770	INV-سبتمبر-1-910144	183	\N	\N	سبتمبر 1	1126.00	0.00	0.00	0.00	1400.00	1000.00	70600.00	71600.00	1000.00	0.00	71600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.121716+03	\N	f
771	INV-سبتمبر-1-910145	184	\N	\N	سبتمبر 1	485.00	0.00	0.00	0.00	1400.00	1000.00	39800.00	40800.00	1000.00	0.00	40800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.125067+03	\N	f
772	INV-سبتمبر-1-910337	185	\N	\N	سبتمبر 1	332.00	0.00	0.00	0.00	1400.00	1000.00	10800.00	11800.00	1000.00	0.00	11800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.128616+03	\N	f
773	INV-سبتمبر-1-910146	186	\N	\N	سبتمبر 1	256.00	0.00	0.00	0.00	1400.00	1000.00	15400.00	16400.00	1000.00	0.00	16400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.132924+03	\N	f
774	INV-سبتمبر-1-910148	187	\N	\N	سبتمبر 1	35.00	0.00	0.00	0.00	1400.00	1000.00	8000.00	9000.00	1000.00	0.00	9000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.138211+03	\N	f
775	INV-سبتمبر-1-910332	188	\N	\N	سبتمبر 1	407.00	0.00	0.00	0.00	1400.00	1000.00	9400.00	10400.00	1000.00	0.00	10400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.141171+03	\N	f
776	INV-سبتمبر-1-910284	189	\N	\N	سبتمبر 1	285.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.144864+03	\N	f
777	INV-سبتمبر-1-910416	190	\N	\N	سبتمبر 1	140.00	0.00	0.00	0.00	1400.00	1000.00	8000.00	9000.00	1000.00	0.00	9000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.148741+03	\N	f
778	INV-سبتمبر-1-910383	191	\N	\N	سبتمبر 1	126.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.155432+03	\N	f
779	INV-سبتمبر-1-910151	192	\N	\N	سبتمبر 1	5256.00	0.00	0.00	0.00	1400.00	1000.00	16400.00	17400.00	1000.00	0.00	17400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.159331+03	\N	f
780	INV-سبتمبر-1-910149	193	\N	\N	سبتمبر 1	111.00	0.00	0.00	0.00	1400.00	1000.00	6200.00	7200.00	1000.00	0.00	7200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.162232+03	\N	f
781	INV-سبتمبر-1-910152	194	\N	\N	سبتمبر 1	1056.00	0.00	0.00	0.00	1400.00	1000.00	32200.00	33200.00	1000.00	0.00	33200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.166298+03	\N	f
782	INV-سبتمبر-1-910028	195	\N	\N	سبتمبر 1	2324.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.17051+03	\N	f
783	INV-سبتمبر-1-910476	196	\N	\N	سبتمبر 1	256.00	0.00	0.00	0.00	1400.00	1000.00	53600.00	54600.00	1000.00	0.00	54600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.173896+03	\N	f
784	INV-سبتمبر-1-910153	197	\N	\N	سبتمبر 1	266.00	0.00	0.00	0.00	1400.00	1000.00	4800.00	5800.00	1000.00	0.00	5800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.176778+03	\N	f
785	INV-سبتمبر-1-910460	198	\N	\N	سبتمبر 1	1496.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.179561+03	\N	f
786	INV-سبتمبر-1-910156	199	\N	\N	سبتمبر 1	1311.00	0.00	0.00	0.00	1400.00	1000.00	15000.00	16000.00	1000.00	0.00	16000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.184989+03	\N	f
787	INV-سبتمبر-1-910155	200	\N	\N	سبتمبر 1	649.00	0.00	0.00	0.00	1400.00	1000.00	13600.00	14600.00	1000.00	0.00	14600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.188124+03	\N	f
788	INV-سبتمبر-1-910413	201	\N	\N	سبتمبر 1	1060.00	0.00	0.00	0.00	1400.00	1000.00	13200.00	14200.00	1000.00	0.00	14200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.190934+03	\N	f
789	INV-سبتمبر-1-910157	202	\N	\N	سبتمبر 1	5899.00	0.00	0.00	0.00	1400.00	1000.00	45200.00	46200.00	1000.00	0.00	46200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.194897+03	\N	f
790	INV-سبتمبر-1-910159	203	\N	\N	سبتمبر 1	993.00	0.00	0.00	0.00	1400.00	1000.00	26200.00	27200.00	1000.00	0.00	27200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.198989+03	\N	f
791	INV-سبتمبر-1-910158	204	\N	\N	سبتمبر 1	284.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.20344+03	\N	f
792	INV-سبتمبر-1-910161	205	\N	\N	سبتمبر 1	894.00	0.00	0.00	0.00	1400.00	1000.00	20600.00	21600.00	1000.00	0.00	21600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.206596+03	\N	f
793	INV-سبتمبر-1-910285	206	\N	\N	سبتمبر 1	196.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.209493+03	\N	f
794	INV-سبتمبر-1-910162	207	\N	\N	سبتمبر 1	1050.00	0.00	0.00	0.00	1400.00	1000.00	11400.00	12400.00	1000.00	0.00	12400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.212923+03	\N	f
795	INV-سبتمبر-1-910422	208	\N	\N	سبتمبر 1	150.00	0.00	0.00	0.00	1400.00	1000.00	138190.00	139190.00	1000.00	0.00	139190.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.217146+03	\N	f
796	INV-سبتمبر-1-910164	209	\N	\N	سبتمبر 1	1064.00	0.00	0.00	0.00	1400.00	1000.00	76600.00	77600.00	1000.00	0.00	77600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.221094+03	\N	f
797	INV-سبتمبر-1-910165	210	\N	\N	سبتمبر 1	2422.00	0.00	0.00	0.00	1400.00	1000.00	31800.00	32800.00	1000.00	0.00	32800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.224851+03	\N	f
798	INV-سبتمبر-1-910496	211	\N	\N	سبتمبر 1	399.00	0.00	0.00	0.00	1400.00	1000.00	9400.00	10400.00	1000.00	0.00	10400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.227735+03	\N	f
799	INV-سبتمبر-1-910169	212	\N	\N	سبتمبر 1	2266.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.231181+03	\N	f
800	INV-سبتمبر-1-910490	213	\N	\N	سبتمبر 1	388.00	0.00	0.00	0.00	1400.00	1000.00	62600.00	63600.00	1000.00	0.00	63600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.238918+03	\N	f
801	INV-سبتمبر-1-910410	214	\N	\N	سبتمبر 1	370.00	0.00	0.00	0.00	1400.00	1000.00	23800.00	24800.00	1000.00	0.00	24800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.242196+03	\N	f
802	INV-سبتمبر-1-910160	215	\N	\N	سبتمبر 1	476.00	0.00	0.00	0.00	1400.00	1000.00	12400.00	13400.00	1000.00	0.00	13400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.245546+03	\N	f
803	INV-سبتمبر-1-910295	216	\N	\N	سبتمبر 1	102.00	0.00	0.00	0.00	1400.00	1000.00	4800.00	5800.00	1000.00	0.00	5800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.24992+03	\N	f
804	INV-سبتمبر-1-910371	217	\N	\N	سبتمبر 1	196.00	0.00	0.00	0.00	1400.00	1000.00	57700.00	58700.00	1000.00	0.00	58700.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.254033+03	\N	f
805	INV-سبتمبر-1-910308	218	\N	\N	سبتمبر 1	293.00	0.00	0.00	0.00	1400.00	1000.00	16800.00	17800.00	1000.00	0.00	17800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.257102+03	\N	f
806	INV-سبتمبر-1-910461	219	\N	\N	سبتمبر 1	220.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.260895+03	\N	f
807	INV-سبتمبر-1-910547	220	\N	\N	سبتمبر 1	151.00	0.00	0.00	0.00	1400.00	1000.00	150800.00	151800.00	1000.00	0.00	151800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.264397+03	\N	f
808	INV-سبتمبر-1-910344	221	\N	\N	سبتمبر 1	64.00	0.00	0.00	0.00	1400.00	1000.00	2400.00	3400.00	1000.00	0.00	3400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.269868+03	\N	f
809	INV-سبتمبر-1-910489	222	\N	\N	سبتمبر 1	54.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.274636+03	\N	f
810	INV-سبتمبر-1-910509	223	\N	\N	سبتمبر 1	76.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.277889+03	\N	f
811	INV-سبتمبر-1-910334	224	\N	\N	سبتمبر 1	1147.00	0.00	0.00	0.00	1400.00	1000.00	34390.00	35390.00	1000.00	0.00	35390.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.281689+03	\N	f
812	INV-سبتمبر-1-910517	225	\N	\N	سبتمبر 1	82.00	0.00	0.00	0.00	1400.00	1000.00	16400.00	17400.00	1000.00	0.00	17400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.286869+03	\N	f
813	INV-سبتمبر-1-910520	226	\N	\N	سبتمبر 1	225.00	0.00	0.00	0.00	1400.00	1000.00	8000.00	9000.00	1000.00	0.00	9000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.291236+03	\N	f
814	INV-سبتمبر-1-910168	227	\N	\N	سبتمبر 1	244.00	0.00	0.00	0.00	1400.00	1000.00	52600.00	53600.00	1000.00	0.00	53600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.29444+03	\N	f
815	INV-سبتمبر-1-910429	228	\N	\N	سبتمبر 1	39.00	0.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	1000.00	0.00	4800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.298337+03	\N	f
816	INV-سبتمبر-1-910166	229	\N	\N	سبتمبر 1	196.00	0.00	0.00	0.00	1400.00	1000.00	1800.00	2800.00	1000.00	0.00	2800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.303419+03	\N	f
817	INV-سبتمبر-1-910408	230	\N	\N	سبتمبر 1	87.00	0.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	1000.00	0.00	4800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.306676+03	\N	f
818	INV-سبتمبر-1-910419	231	\N	\N	سبتمبر 1	59.00	0.00	0.00	0.00	1400.00	1000.00	2400.00	3400.00	1000.00	0.00	3400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.310513+03	\N	f
819	INV-سبتمبر-1-910163	232	\N	\N	سبتمبر 1	1651.00	0.00	0.00	0.00	1400.00	1000.00	149100.00	150100.00	1000.00	0.00	150100.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.313869+03	\N	f
820	INV-سبتمبر-1-910562	233	\N	\N	سبتمبر 1	75.00	0.00	0.00	0.00	1400.00	1000.00	18500.00	19500.00	1000.00	0.00	19500.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.319788+03	\N	f
821	INV-سبتمبر-1-910170	234	\N	\N	سبتمبر 1	296.00	0.00	0.00	0.00	1400.00	1000.00	10000.00	11000.00	1000.00	0.00	11000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.323698+03	\N	f
822	INV-سبتمبر-1-910516	235	\N	\N	سبتمبر 1	763.00	0.00	0.00	0.00	1400.00	1000.00	87600.00	88600.00	1000.00	0.00	88600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.327872+03	\N	f
823	INV-سبتمبر-1-910171	236	\N	\N	سبتمبر 1	103.00	0.00	0.00	0.00	1400.00	1000.00	6200.00	7200.00	1000.00	0.00	7200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.331916+03	\N	f
824	INV-سبتمبر-1-910030	237	\N	\N	سبتمبر 1	343.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.336711+03	\N	f
825	INV-سبتمبر-1-910535	238	\N	\N	سبتمبر 1	242.00	0.00	0.00	0.00	1400.00	1000.00	20600.00	21600.00	1000.00	0.00	21600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.340188+03	\N	f
826	INV-سبتمبر-1-910172	239	\N	\N	سبتمبر 1	2180.00	0.00	0.00	0.00	1400.00	1000.00	26200.00	27200.00	1000.00	0.00	27200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.343353+03	\N	f
827	INV-سبتمبر-1-910434	240	\N	\N	سبتمبر 1	369.00	0.00	0.00	0.00	1400.00	1000.00	39000.00	40000.00	1000.00	0.00	40000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.347834+03	\N	f
828	INV-سبتمبر-1-910173	241	\N	\N	سبتمبر 1	1573.00	0.00	0.00	0.00	1400.00	1000.00	19200.00	20200.00	1000.00	0.00	20200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.354198+03	\N	f
829	INV-سبتمبر-1-910175	242	\N	\N	سبتمبر 1	4402.00	0.00	0.00	0.00	1400.00	1000.00	345300.00	346300.00	1000.00	0.00	346300.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.358419+03	\N	f
830	INV-سبتمبر-1-910176	243	\N	\N	سبتمبر 1	5564.00	0.00	0.00	0.00	1400.00	1000.00	3000.00	4000.00	1000.00	0.00	4000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.362036+03	\N	f
831	INV-سبتمبر-1-910174	244	\N	\N	سبتمبر 1	2053.00	0.00	0.00	0.00	1400.00	1000.00	52600.00	53600.00	1000.00	0.00	53600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.367208+03	\N	f
832	INV-سبتمبر-1-910177	245	\N	\N	سبتمبر 1	641.00	0.00	0.00	0.00	1400.00	1000.00	17800.00	18800.00	1000.00	0.00	18800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.371418+03	\N	f
833	INV-سبتمبر-1-910204	246	\N	\N	سبتمبر 1	1040.00	0.00	0.00	0.00	1400.00	1000.00	16000.00	17000.00	1000.00	0.00	17000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.375247+03	\N	f
834	INV-سبتمبر-1-910178	247	\N	\N	سبتمبر 1	269.00	0.00	0.00	0.00	1400.00	1000.00	2000.00	3000.00	1000.00	0.00	3000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.379848+03	\N	f
835	INV-سبتمبر-1-910336	248	\N	\N	سبتمبر 1	574.00	0.00	0.00	0.00	1400.00	1000.00	12200.00	13200.00	1000.00	0.00	13200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.384661+03	\N	f
836	INV-سبتمبر-1-910478	249	\N	\N	سبتمبر 1	223.00	0.00	0.00	0.00	1400.00	1000.00	8000.00	9000.00	1000.00	0.00	9000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.388974+03	\N	f
837	INV-سبتمبر-1-910202	250	\N	\N	سبتمبر 1	1230.00	0.00	0.00	0.00	1400.00	1000.00	13100.00	14100.00	1000.00	0.00	14100.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.392721+03	\N	f
838	INV-سبتمبر-1-910201	251	\N	\N	سبتمبر 1	162.00	0.00	0.00	0.00	1400.00	1000.00	6000.00	7000.00	1000.00	0.00	7000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.396918+03	\N	f
839	INV-سبتمبر-1-910179	252	\N	\N	سبتمبر 1	1114.00	0.00	0.00	0.00	1400.00	1000.00	26200.00	27200.00	1000.00	0.00	27200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.402344+03	\N	f
840	INV-سبتمبر-1-910180	253	\N	\N	سبتمبر 1	56.00	0.00	0.00	0.00	1400.00	1000.00	4800.00	5800.00	1000.00	0.00	5800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.406523+03	\N	f
841	INV-سبتمبر-1-910181	254	\N	\N	سبتمبر 1	82.00	0.00	0.00	0.00	1400.00	1000.00	5200.00	6200.00	1000.00	0.00	6200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.410327+03	\N	f
842	INV-سبتمبر-1-910360	255	\N	\N	سبتمبر 1	89.00	0.00	0.00	0.00	1400.00	1000.00	5200.00	6200.00	1000.00	0.00	6200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.41502+03	\N	f
843	INV-سبتمبر-1-910200	256	\N	\N	سبتمبر 1	109.00	0.00	0.00	0.00	1400.00	1000.00	5200.00	6200.00	1000.00	0.00	6200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.420246+03	\N	f
844	INV-سبتمبر-1-910199	257	\N	\N	سبتمبر 1	56.00	0.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	1000.00	0.00	4800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.424417+03	\N	f
845	INV-سبتمبر-1-910487	258	\N	\N	سبتمبر 1	68.00	0.00	0.00	0.00	1400.00	1000.00	9400.00	10400.00	1000.00	0.00	10400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.427489+03	\N	f
846	INV-سبتمبر-1-910198	259	\N	\N	سبتمبر 1	94.00	0.00	0.00	0.00	1400.00	1000.00	18600.00	19600.00	1000.00	0.00	19600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.43316+03	\N	f
847	INV-سبتمبر-1-910529	260	\N	\N	سبتمبر 1	19.00	0.00	0.00	0.00	1400.00	1000.00	21400.00	22400.00	1000.00	0.00	22400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.437707+03	\N	f
848	INV-سبتمبر-1-910258	261	\N	\N	سبتمبر 1	391.00	0.00	0.00	0.00	1400.00	1000.00	2000.00	3000.00	1000.00	0.00	3000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.441529+03	\N	f
849	INV-سبتمبر-1-910182	262	\N	\N	سبتمبر 1	266.00	0.00	0.00	0.00	1400.00	1000.00	3000.00	4000.00	1000.00	0.00	4000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.445891+03	\N	f
850	INV-سبتمبر-1-910184	263	\N	\N	سبتمبر 1	1450.00	0.00	0.00	0.00	1400.00	1000.00	22200.00	23200.00	1000.00	0.00	23200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.450443+03	\N	f
851	INV-سبتمبر-1-910185	264	\N	\N	سبتمبر 1	308.00	0.00	0.00	0.00	1400.00	1000.00	76800.00	77800.00	1000.00	0.00	77800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.454141+03	\N	f
852	INV-سبتمبر-1-910333	265	\N	\N	سبتمبر 1	471.00	0.00	0.00	0.00	1400.00	1000.00	72900.00	73900.00	1000.00	0.00	73900.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.458353+03	\N	f
853	INV-سبتمبر-1-910473	266	\N	\N	سبتمبر 1	28.00	0.00	0.00	0.00	1400.00	1000.00	3400.00	4400.00	1000.00	0.00	4400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.461401+03	\N	f
854	INV-سبتمبر-1-910186	267	\N	\N	سبتمبر 1	1025.00	0.00	0.00	0.00	1400.00	1000.00	13600.00	14600.00	1000.00	0.00	14600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.465011+03	\N	f
855	INV-سبتمبر-1-910187	268	\N	\N	سبتمبر 1	888.00	0.00	0.00	0.00	1400.00	1000.00	128400.00	129400.00	1000.00	0.00	129400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.469824+03	\N	f
856	INV-سبتمبر-1-910388	269	\N	\N	سبتمبر 1	163.00	0.00	0.00	0.00	1400.00	1000.00	13200.00	14200.00	1000.00	0.00	14200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.473933+03	\N	f
857	INV-سبتمبر-1-910566	270	\N	\N	سبتمبر 1	250.00	0.00	0.00	0.00	1400.00	1000.00	10800.00	11800.00	1000.00	0.00	11800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.477851+03	\N	f
858	INV-سبتمبر-1-910398	271	\N	\N	سبتمبر 1	3391.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.484365+03	\N	f
859	INV-سبتمبر-1-910197	272	\N	\N	سبتمبر 1	1221.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.488006+03	\N	f
860	INV-سبتمبر-1-910003	273	\N	\N	سبتمبر 1	300.00	0.00	0.00	0.00	1400.00	1000.00	10000.00	11000.00	1000.00	0.00	11000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.491619+03	\N	f
861	INV-سبتمبر-1-910033	274	\N	\N	سبتمبر 1	239.00	0.00	0.00	0.00	1400.00	1000.00	81200.00	82200.00	1000.00	0.00	82200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.495182+03	\N	f
862	INV-سبتمبر-1-910193	275	\N	\N	سبتمبر 1	1435.00	0.00	0.00	0.00	1400.00	1000.00	13600.00	14600.00	1000.00	0.00	14600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.498934+03	\N	f
863	INV-سبتمبر-1-910194	276	\N	\N	سبتمبر 1	230.00	0.00	0.00	0.00	1400.00	1000.00	5200.00	6200.00	1000.00	0.00	6200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.504162+03	\N	f
864	INV-سبتمبر-1-910462	277	\N	\N	سبتمبر 1	446.00	0.00	0.00	0.00	1400.00	1000.00	44400.00	45400.00	1000.00	0.00	45400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.507644+03	\N	f
865	INV-سبتمبر-1-910195	278	\N	\N	سبتمبر 1	306.00	0.00	0.00	0.00	1400.00	1000.00	9400.00	10400.00	1000.00	0.00	10400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.511547+03	\N	f
866	INV-سبتمبر-1-910376	279	\N	\N	سبتمبر 1	159.00	0.00	0.00	0.00	1400.00	1000.00	8000.00	9000.00	1000.00	0.00	9000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.516482+03	\N	f
867	INV-سبتمبر-1-910369	280	\N	\N	سبتمبر 1	563.00	0.00	0.00	0.00	1400.00	1000.00	48000.00	49000.00	1000.00	0.00	49000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.520556+03	\N	f
868	INV-سبتمبر-1-910510	281	\N	\N	سبتمبر 1	59.00	0.00	0.00	0.00	1400.00	1000.00	8000.00	9000.00	1000.00	0.00	9000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.52544+03	\N	f
869	INV-سبتمبر-1-910192	282	\N	\N	سبتمبر 1	281.00	0.00	0.00	0.00	1400.00	1000.00	12200.00	13200.00	1000.00	0.00	13200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.529459+03	\N	f
870	INV-سبتمبر-1-910299	283	\N	\N	سبتمبر 1	189.00	0.00	0.00	0.00	1400.00	1000.00	7600.00	8600.00	1000.00	0.00	8600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.534239+03	\N	f
871	INV-سبتمبر-1-910351	284	\N	\N	سبتمبر 1	353.00	0.00	0.00	0.00	1400.00	1000.00	5000.00	6000.00	1000.00	0.00	6000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.538019+03	\N	f
872	INV-سبتمبر-1-910188	285	\N	\N	سبتمبر 1	1296.00	0.00	0.00	0.00	1400.00	1000.00	15000.00	16000.00	1000.00	0.00	16000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.541685+03	\N	f
873	INV-سبتمبر-1-910034	286	\N	\N	سبتمبر 1	1453.00	0.00	0.00	0.00	1400.00	1000.00	7800.00	8800.00	1000.00	0.00	8800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.546176+03	\N	f
874	INV-سبتمبر-1-910538	287	\N	\N	سبتمبر 1	88.00	0.00	0.00	0.00	1400.00	1000.00	42600.00	43600.00	1000.00	0.00	43600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.55111+03	\N	f
875	INV-سبتمبر-1-910189	288	\N	\N	سبتمبر 1	408.00	0.00	0.00	0.00	1400.00	1000.00	15000.00	16000.00	1000.00	0.00	16000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.555231+03	\N	f
876	INV-سبتمبر-1-910526	289	\N	\N	سبتمبر 1	40.00	0.00	0.00	0.00	1400.00	1000.00	24400.00	25400.00	1000.00	0.00	25400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.558435+03	\N	f
877	INV-سبتمبر-1-910190	290	\N	\N	سبتمبر 1	794.00	0.00	0.00	0.00	1400.00	1000.00	19000.00	20000.00	1000.00	0.00	20000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.563146+03	\N	f
878	INV-سبتمبر-1-910191	291	\N	\N	سبتمبر 1	914.00	0.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	1000.00	0.00	4800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.569447+03	\N	f
879	INV-سبتمبر-1-910359	292	\N	\N	سبتمبر 1	88.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.573168+03	\N	f
880	INV-سبتمبر-1-910465	293	\N	\N	سبتمبر 1	477.00	0.00	0.00	0.00	1400.00	1000.00	46400.00	47400.00	1000.00	0.00	47400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.577628+03	\N	f
881	INV-سبتمبر-1-910497	294	\N	\N	سبتمبر 1	214.00	0.00	0.00	0.00	1400.00	1000.00	191300.00	192300.00	1000.00	0.00	192300.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.581344+03	\N	f
882	INV-سبتمبر-1-910377	295	\N	\N	سبتمبر 1	4785.00	0.00	0.00	0.00	1400.00	1000.00	8000.00	9000.00	1000.00	0.00	9000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.586522+03	\N	f
883	INV-سبتمبر-1-910400	296	\N	\N	سبتمبر 1	266.00	0.00	0.00	0.00	1400.00	1000.00	8000.00	9000.00	1000.00	0.00	9000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.590865+03	\N	f
884	INV-سبتمبر-1-910301	297	\N	\N	سبتمبر 1	464.00	0.00	0.00	0.00	1400.00	1000.00	61000.00	62000.00	1000.00	0.00	62000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.594331+03	\N	f
885	INV-سبتمبر-1-910205	298	\N	\N	سبتمبر 1	3846.00	0.00	0.00	0.00	1400.00	1000.00	62300.00	63300.00	1000.00	0.00	63300.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.597644+03	\N	f
886	INV-سبتمبر-1-910207	299	\N	\N	سبتمبر 1	2109.00	0.00	0.00	0.00	1400.00	1000.00	26200.00	27200.00	1000.00	0.00	27200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.602255+03	\N	f
887	INV-سبتمبر-1-910036	300	\N	\N	سبتمبر 1	534.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.606792+03	\N	f
888	INV-سبتمبر-1-910206	301	\N	\N	سبتمبر 1	598.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.611704+03	\N	f
889	INV-سبتمبر-1-910560	302	\N	\N	سبتمبر 1	103.00	0.00	0.00	0.00	1400.00	1000.00	7200.00	8200.00	1000.00	0.00	8200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.616208+03	\N	f
890	INV-سبتمبر-1-910208	303	\N	\N	سبتمبر 1	537.00	0.00	0.00	0.00	1400.00	1000.00	16400.00	17400.00	1000.00	0.00	17400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.620855+03	\N	f
891	INV-سبتمبر-1-910507	304	\N	\N	سبتمبر 1	163.00	0.00	0.00	0.00	1400.00	1000.00	20600.00	21600.00	1000.00	0.00	21600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.62454+03	\N	f
892	INV-سبتمبر-1-910211	305	\N	\N	سبتمبر 1	144.00	0.00	0.00	0.00	1400.00	1000.00	15000.00	16000.00	1000.00	0.00	16000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.628755+03	\N	f
893	INV-سبتمبر-1-910508	306	\N	\N	سبتمبر 1	65.00	0.00	0.00	0.00	1400.00	1000.00	9400.00	10400.00	1000.00	0.00	10400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.633221+03	\N	f
894	INV-سبتمبر-1-910445	307	\N	\N	سبتمبر 1	2410.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.637609+03	\N	f
895	INV-سبتمبر-1-910209	308	\N	\N	سبتمبر 1	77.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.641197+03	\N	f
896	INV-سبتمبر-1-910210	309	\N	\N	سبتمبر 1	177.00	0.00	0.00	0.00	1400.00	1000.00	10800.00	11800.00	1000.00	0.00	11800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.644634+03	\N	f
897	INV-سبتمبر-1-910367	310	\N	\N	سبتمبر 1	281.00	0.00	0.00	0.00	1400.00	1000.00	10800.00	11800.00	1000.00	0.00	11800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.649381+03	\N	f
898	INV-سبتمبر-1-910212	311	\N	\N	سبتمبر 1	1006.00	0.00	0.00	0.00	1400.00	1000.00	10800.00	11800.00	1000.00	0.00	11800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.654518+03	\N	f
899	INV-سبتمبر-1-910213	312	\N	\N	سبتمبر 1	518.00	0.00	0.00	0.00	1400.00	1000.00	8000.00	9000.00	1000.00	0.00	9000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.658567+03	\N	f
900	INV-سبتمبر-1-910406	313	\N	\N	سبتمبر 1	268.00	0.00	0.00	0.00	1400.00	1000.00	3400.00	4400.00	1000.00	0.00	4400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.66252+03	\N	f
901	INV-سبتمبر-1-910037	314	\N	\N	سبتمبر 1	2482.00	0.00	0.00	0.00	1400.00	1000.00	29000.00	30000.00	1000.00	0.00	30000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.66775+03	\N	f
902	INV-سبتمبر-1-910214	315	\N	\N	سبتمبر 1	212.00	0.00	0.00	0.00	1400.00	1000.00	10000.00	11000.00	1000.00	0.00	11000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.672706+03	\N	f
903	INV-سبتمبر-1-910362	316	\N	\N	سبتمبر 1	238.00	0.00	0.00	0.00	1400.00	1000.00	9400.00	10400.00	1000.00	0.00	10400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.676932+03	\N	f
904	INV-سبتمبر-1-910302	317	\N	\N	سبتمبر 1	103.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.681216+03	\N	f
905	INV-سبتمبر-1-910421	318	\N	\N	سبتمبر 1	108.00	0.00	0.00	0.00	1400.00	1000.00	2000.00	3000.00	1000.00	0.00	3000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.686296+03	\N	f
906	INV-سبتمبر-1-910431	319	\N	\N	سبتمبر 1	47.00	0.00	0.00	0.00	1400.00	1000.00	11800.00	12800.00	1000.00	0.00	12800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.690565+03	\N	f
907	INV-سبتمبر-1-910216	320	\N	\N	سبتمبر 1	349.00	0.00	0.00	0.00	1400.00	1000.00	5200.00	6200.00	1000.00	0.00	6200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.694082+03	\N	f
908	INV-سبتمبر-1-910215	321	\N	\N	سبتمبر 1	174.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.697051+03	\N	f
909	INV-سبتمبر-1-910217	322	\N	\N	سبتمبر 1	590.00	0.00	0.00	0.00	1400.00	1000.00	23600.00	24600.00	1000.00	0.00	24600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.70173+03	\N	f
910	INV-سبتمبر-1-910218	323	\N	\N	سبتمبر 1	3511.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.705788+03	\N	f
911	INV-سبتمبر-1-910569	324	\N	\N	سبتمبر 1	0.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.708962+03	\N	f
912	INV-سبتمبر-1-910035	325	\N	\N	سبتمبر 1	775.00	0.00	0.00	0.00	1400.00	1000.00	33800.00	34800.00	1000.00	0.00	34800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.713603+03	\N	f
913	INV-سبتمبر-1-910219	326	\N	\N	سبتمبر 1	452.00	0.00	0.00	0.00	1400.00	1000.00	52400.00	53400.00	1000.00	0.00	53400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.719548+03	\N	f
914	INV-سبتمبر-1-910220	327	\N	\N	سبتمبر 1	807.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.724174+03	\N	f
915	INV-سبتمبر-1-910494	328	\N	\N	سبتمبر 1	53.00	0.00	0.00	0.00	1400.00	1000.00	4800.00	5800.00	1000.00	0.00	5800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.727936+03	\N	f
916	INV-سبتمبر-1-910536	329	\N	\N	سبتمبر 1	9.00	0.00	0.00	0.00	1400.00	1000.00	12600.00	13600.00	1000.00	0.00	13600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.73287+03	\N	f
917	INV-سبتمبر-1-910543	330	\N	\N	سبتمبر 1	88.00	0.00	0.00	0.00	1400.00	1000.00	14200.00	15200.00	1000.00	0.00	15200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.737116+03	\N	f
918	INV-سبتمبر-1-910225	331	\N	\N	سبتمبر 1	1691.00	0.00	0.00	0.00	1400.00	1000.00	57000.00	58000.00	1000.00	0.00	58000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.740352+03	\N	f
919	INV-سبتمبر-1-910227	332	\N	\N	سبتمبر 1	324.00	0.00	0.00	0.00	1400.00	1000.00	5200.00	6200.00	1000.00	0.00	6200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.74618+03	\N	f
920	INV-سبتمبر-1-910222	333	\N	\N	سبتمبر 1	470.00	0.00	0.00	0.00	1400.00	1000.00	34600.00	35600.00	1000.00	0.00	35600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.750708+03	\N	f
921	INV-سبتمبر-1-910223	334	\N	\N	سبتمبر 1	322.00	0.00	0.00	0.00	1400.00	1000.00	20900.00	21900.00	1000.00	0.00	21900.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.754747+03	\N	f
922	INV-سبتمبر-1-910229	335	\N	\N	سبتمبر 1	551.00	0.00	0.00	0.00	1400.00	1000.00	16100.00	17100.00	1000.00	0.00	17100.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.75927+03	\N	f
923	INV-سبتمبر-1-910232	336	\N	\N	سبتمبر 1	446.00	0.00	0.00	0.00	1400.00	1000.00	16400.00	17400.00	1000.00	0.00	17400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.762656+03	\N	f
924	INV-سبتمبر-1-910228	337	\N	\N	سبتمبر 1	440.00	0.00	0.00	0.00	1400.00	1000.00	15000.00	16000.00	1000.00	0.00	16000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.768162+03	\N	f
925	INV-سبتمبر-1-910541	338	\N	\N	سبتمبر 1	33.00	0.00	0.00	0.00	1400.00	1000.00	8000.00	9000.00	1000.00	0.00	9000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.772484+03	\N	f
926	INV-سبتمبر-1-910265	339	\N	\N	سبتمبر 1	160.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.775679+03	\N	f
927	INV-سبتمبر-1-910231	340	\N	\N	سبتمبر 1	663.00	0.00	0.00	0.00	1400.00	1000.00	13600.00	14600.00	1000.00	0.00	14600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.77998+03	\N	f
928	INV-سبتمبر-1-910230	341	\N	\N	سبتمبر 1	850.00	0.00	0.00	0.00	1400.00	1000.00	84500.00	85500.00	1000.00	0.00	85500.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.784717+03	\N	f
929	INV-سبتمبر-1-910233	342	\N	\N	سبتمبر 1	307.00	0.00	0.00	0.00	1400.00	1000.00	14200.00	15200.00	1000.00	0.00	15200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.788762+03	\N	f
930	INV-سبتمبر-1-910268	343	\N	\N	سبتمبر 1	260.00	0.00	0.00	0.00	1400.00	1000.00	9400.00	10400.00	1000.00	0.00	10400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.792255+03	\N	f
931	INV-سبتمبر-1-910234	344	\N	\N	سبتمبر 1	294.00	0.00	0.00	0.00	1400.00	1000.00	11400.00	12400.00	1000.00	0.00	12400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.796068+03	\N	f
932	INV-سبتمبر-1-910235	345	\N	\N	سبتمبر 1	537.00	0.00	0.00	0.00	1400.00	1000.00	19200.00	20200.00	1000.00	0.00	20200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.801107+03	\N	f
933	INV-سبتمبر-1-910283	346	\N	\N	سبتمبر 1	591.00	0.00	0.00	0.00	1400.00	1000.00	59600.00	60600.00	1000.00	0.00	60600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.804499+03	\N	f
934	INV-سبتمبر-1-910527	347	\N	\N	سبتمبر 1	84.00	0.00	0.00	0.00	1400.00	1000.00	10800.00	11800.00	1000.00	0.00	11800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.808821+03	\N	f
935	INV-سبتمبر-1-910281	348	\N	\N	سبتمبر 1	171.00	0.00	0.00	0.00	1400.00	1000.00	13600.00	14600.00	1000.00	0.00	14600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.812201+03	\N	f
936	INV-سبتمبر-1-910499	349	\N	\N	سبتمبر 1	136.00	0.00	0.00	0.00	1400.00	1000.00	20900.00	21900.00	1000.00	0.00	21900.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.816285+03	\N	f
937	INV-سبتمبر-1-910502	350	\N	\N	سبتمبر 1	76.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.820662+03	\N	f
938	INV-سبتمبر-1-910237	351	\N	\N	سبتمبر 1	77.00	0.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	1000.00	0.00	4800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.824418+03	\N	f
939	INV-سبتمبر-1-910236	352	\N	\N	سبتمبر 1	789.00	0.00	0.00	0.00	1400.00	1000.00	9400.00	10400.00	1000.00	0.00	10400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.828429+03	\N	f
940	INV-سبتمبر-1-910412	353	\N	\N	سبتمبر 1	1953.00	0.00	0.00	0.00	1400.00	1000.00	133600.00	134600.00	1000.00	0.00	134600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.832312+03	\N	f
941	INV-سبتمبر-1-910392	354	\N	\N	سبتمبر 1	27.00	0.00	0.00	0.00	1400.00	1000.00	2000.00	3000.00	1000.00	0.00	3000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.836707+03	\N	f
942	INV-سبتمبر-1-910438	355	\N	\N	سبتمبر 1	249.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.83989+03	\N	f
943	INV-سبتمبر-1-910453	356	\N	\N	سبتمبر 1	154.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.8438+03	\N	f
944	INV-سبتمبر-1-910467	357	\N	\N	سبتمبر 1	268.00	0.00	0.00	0.00	1400.00	1000.00	25400.00	26400.00	1000.00	0.00	26400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.847442+03	\N	f
945	INV-سبتمبر-1-910238	358	\N	\N	سبتمبر 1	5463.00	0.00	0.00	0.00	1400.00	1000.00	331500.00	332500.00	1000.00	0.00	332500.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.85292+03	\N	f
946	INV-سبتمبر-1-910242	359	\N	\N	سبتمبر 1	351.00	0.00	0.00	0.00	1400.00	1000.00	9800.00	10800.00	1000.00	0.00	10800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.857282+03	\N	f
947	INV-سبتمبر-1-910240	360	\N	\N	سبتمبر 1	1298.00	0.00	0.00	0.00	1400.00	1000.00	10800.00	11800.00	1000.00	0.00	11800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.861376+03	\N	f
948	INV-سبتمبر-1-910338	361	\N	\N	سبتمبر 1	15.00	0.00	0.00	0.00	1400.00	1000.00	5200.00	6200.00	1000.00	0.00	6200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.865045+03	\N	f
949	INV-سبتمبر-1-910459	362	\N	\N	سبتمبر 1	82.00	0.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	1000.00	0.00	4800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.870794+03	\N	f
950	INV-سبتمبر-1-910150	363	\N	\N	سبتمبر 1	510.00	0.00	0.00	0.00	1400.00	1000.00	3400.00	4400.00	1000.00	0.00	4400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.874222+03	\N	f
951	INV-سبتمبر-1-910339	364	\N	\N	سبتمبر 1	838.00	0.00	0.00	0.00	1400.00	1000.00	10800.00	11800.00	1000.00	0.00	11800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.878107+03	\N	f
952	INV-سبتمبر-1-910479	365	\N	\N	سبتمبر 1	326.00	0.00	0.00	0.00	1400.00	1000.00	170900.00	171900.00	1000.00	0.00	171900.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.881919+03	\N	f
953	INV-سبتمبر-1-910370	366	\N	\N	سبتمبر 1	37.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.886361+03	\N	f
954	INV-سبتمبر-1-910266	367	\N	\N	سبتمبر 1	68.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.889537+03	\N	f
955	INV-سبتمبر-1-910361	368	\N	\N	سبتمبر 1	301.00	0.00	0.00	0.00	1400.00	1000.00	800.00	1800.00	1000.00	0.00	1800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.89321+03	\N	f
956	INV-سبتمبر-1-910394	369	\N	\N	سبتمبر 1	198.00	0.00	0.00	0.00	1400.00	1000.00	8900.00	9900.00	1000.00	0.00	9900.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.896185+03	\N	f
957	INV-سبتمبر-1-910463	370	\N	\N	سبتمبر 1	176.00	0.00	0.00	0.00	1400.00	1000.00	22000.00	23000.00	1000.00	0.00	23000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.902927+03	\N	f
958	INV-سبتمبر-1-910244	371	\N	\N	سبتمبر 1	332.00	0.00	0.00	0.00	1400.00	1000.00	13900.00	14900.00	1000.00	0.00	14900.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.906175+03	\N	f
959	INV-سبتمبر-1-910246	372	\N	\N	سبتمبر 1	225.00	0.00	0.00	0.00	1400.00	1000.00	700.00	1700.00	1000.00	0.00	1700.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.909972+03	\N	f
960	INV-سبتمبر-1-910533	373	\N	\N	سبتمبر 1	72.00	0.00	0.00	0.00	1400.00	1000.00	10800.00	11800.00	1000.00	0.00	11800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.913857+03	\N	f
961	INV-سبتمبر-1-910248	374	\N	\N	سبتمبر 1	505.00	0.00	0.00	0.00	1400.00	1000.00	18200.00	19200.00	1000.00	0.00	19200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.919444+03	\N	f
962	INV-سبتمبر-1-910245	375	\N	\N	سبتمبر 1	234.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.922584+03	\N	f
963	INV-سبتمبر-1-910435	376	\N	\N	سبتمبر 1	144.00	0.00	0.00	0.00	1400.00	1000.00	2400.00	3400.00	1000.00	0.00	3400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.926268+03	\N	f
964	INV-سبتمبر-1-910038	377	\N	\N	سبتمبر 1	559.00	0.00	0.00	0.00	1400.00	1000.00	9400.00	10400.00	1000.00	0.00	10400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.9303+03	\N	f
965	INV-سبتمبر-1-910415	378	\N	\N	سبتمبر 1	408.00	0.00	0.00	0.00	1400.00	1000.00	74000.00	75000.00	1000.00	0.00	75000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.935236+03	\N	f
966	INV-سبتمبر-1-910249	379	\N	\N	سبتمبر 1	410.00	0.00	0.00	0.00	1400.00	1000.00	7000.00	8000.00	1000.00	0.00	8000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.938215+03	\N	f
967	INV-سبتمبر-1-910341	380	\N	\N	سبتمبر 1	252.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.943018+03	\N	f
968	INV-سبتمبر-1-910251	381	\N	\N	سبتمبر 1	540.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.949572+03	\N	f
969	INV-سبتمبر-1-910469	382	\N	\N	سبتمبر 1	346.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.953751+03	\N	f
970	INV-سبتمبر-1-910350	383	\N	\N	سبتمبر 1	1568.00	0.00	0.00	0.00	1400.00	1000.00	50700.00	51700.00	1000.00	0.00	51700.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.957618+03	\N	f
971	INV-سبتمبر-1-910374	384	\N	\N	سبتمبر 1	273.00	0.00	0.00	0.00	1400.00	1000.00	99400.00	100400.00	1000.00	0.00	100400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.961062+03	\N	f
972	INV-سبتمبر-1-910380	385	\N	\N	سبتمبر 1	279.00	0.00	0.00	0.00	1400.00	1000.00	8000.00	9000.00	1000.00	0.00	9000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.96512+03	\N	f
973	INV-سبتمبر-1-910039	386	\N	\N	سبتمبر 1	452.00	0.00	0.00	0.00	1400.00	1000.00	5200.00	6200.00	1000.00	0.00	6200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.969944+03	\N	f
974	INV-سبتمبر-1-910287	387	\N	\N	سبتمبر 1	102.00	0.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	1000.00	0.00	4800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.974375+03	\N	f
975	INV-سبتمبر-1-910256	388	\N	\N	سبتمبر 1	902.00	0.00	0.00	0.00	1400.00	1000.00	15000.00	16000.00	1000.00	0.00	16000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.97826+03	\N	f
976	INV-سبتمبر-1-910257	389	\N	\N	سبتمبر 1	455.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.983678+03	\N	f
977	INV-سبتمبر-1-910436	390	\N	\N	سبتمبر 1	133.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.987521+03	\N	f
978	INV-سبتمبر-1-910259	391	\N	\N	سبتمبر 1	667.00	0.00	0.00	0.00	1400.00	1000.00	5200.00	6200.00	1000.00	0.00	6200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.991452+03	\N	f
979	INV-سبتمبر-1-910296	392	\N	\N	سبتمبر 1	1903.00	0.00	0.00	0.00	1400.00	1000.00	126600.00	127600.00	1000.00	0.00	127600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.995033+03	\N	f
980	INV-سبتمبر-1-910262	393	\N	\N	سبتمبر 1	631.00	0.00	0.00	0.00	1400.00	1000.00	8000.00	9000.00	1000.00	0.00	9000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:12.999411+03	\N	f
981	INV-سبتمبر-1-910347	394	\N	\N	سبتمبر 1	43.00	0.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	1000.00	0.00	4800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.003498+03	\N	f
982	INV-سبتمبر-1-910270	395	\N	\N	سبتمبر 1	131.00	0.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	1000.00	0.00	4800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.007184+03	\N	f
983	INV-سبتمبر-1-910505	396	\N	\N	سبتمبر 1	82.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.010457+03	\N	f
984	INV-سبتمبر-1-910518	397	\N	\N	سبتمبر 1	264.00	0.00	0.00	0.00	1400.00	1000.00	13600.00	14600.00	1000.00	0.00	14600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.015042+03	\N	f
985	INV-سبتمبر-1-910297	398	\N	\N	سبتمبر 1	224.00	0.00	0.00	0.00	1400.00	1000.00	15400.00	16400.00	1000.00	0.00	16400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.019402+03	\N	f
986	INV-سبتمبر-1-910407	399	\N	\N	سبتمبر 1	213.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.022916+03	\N	f
987	INV-سبتمبر-1-910425	400	\N	\N	سبتمبر 1	231.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.026873+03	\N	f
988	INV-سبتمبر-1-910449	401	\N	\N	سبتمبر 1	346.00	0.00	0.00	0.00	1400.00	1000.00	13600.00	14600.00	1000.00	0.00	14600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.030757+03	\N	f
989	INV-سبتمبر-1-910269	402	\N	\N	سبتمبر 1	647.00	0.00	0.00	0.00	1400.00	1000.00	12800.00	13800.00	1000.00	0.00	13800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.035228+03	\N	f
990	INV-سبتمبر-1-910264	403	\N	\N	سبتمبر 1	527.00	0.00	0.00	0.00	1200.00	500.00	19000.00	19500.00	500.00	0.00	19500.00	2026-09-22	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.038664+03	\N	f
991	INV-سبتمبر-1-910263	404	\N	\N	سبتمبر 1	1962.00	0.00	0.00	0.00	1400.00	1000.00	13600.00	14600.00	1000.00	0.00	14600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.04175+03	\N	f
992	INV-سبتمبر-1-910267	405	\N	\N	سبتمبر 1	198.00	0.00	0.00	0.00	1400.00	1000.00	2400.00	3400.00	1000.00	0.00	3400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.045636+03	\N	f
993	INV-سبتمبر-1-910357	406	\N	\N	سبتمبر 1	65.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.050243+03	\N	f
994	INV-سبتمبر-1-910470	407	\N	\N	سبتمبر 1	75.00	0.00	0.00	0.00	1400.00	1000.00	2400.00	3400.00	1000.00	0.00	3400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.056638+03	\N	f
995	INV-سبتمبر-1-910456	408	\N	\N	سبتمبر 1	6.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.06114+03	\N	f
996	INV-سبتمبر-1-910032	409	\N	\N	سبتمبر 1	139.00	0.00	0.00	0.00	1400.00	1000.00	9200.00	10200.00	1000.00	0.00	10200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.06489+03	\N	f
997	INV-سبتمبر-1-910483	410	\N	\N	سبتمبر 1	95.00	0.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	1000.00	0.00	4800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.070015+03	\N	f
998	INV-سبتمبر-1-910511	411	\N	\N	سبتمبر 1	3.00	0.00	0.00	0.00	1400.00	1000.00	2400.00	3400.00	1000.00	0.00	3400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.074261+03	\N	f
999	INV-سبتمبر-1-910457	412	\N	\N	سبتمبر 1	8.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.077875+03	\N	f
1000	INV-سبتمبر-1-910486	413	\N	\N	سبتمبر 1	25.00	0.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	1000.00	0.00	4800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.081289+03	\N	f
1001	INV-سبتمبر-1-910102	414	\N	\N	سبتمبر 1	1754.00	0.00	0.00	0.00	1400.00	1000.00	36000.00	37000.00	1000.00	0.00	37000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.086146+03	\N	f
1002	INV-سبتمبر-1-910519	415	\N	\N	سبتمبر 1	1580.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.089992+03	\N	f
1003	INV-سبتمبر-1-910523	416	\N	\N	سبتمبر 1	67.00	0.00	0.00	0.00	1400.00	1000.00	4400.00	5400.00	1000.00	0.00	5400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.093937+03	\N	f
1004	INV-سبتمبر-1-910451	417	\N	\N	سبتمبر 1	1610.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.098765+03	\N	f
1005	INV-سبتمبر-1-910454	418	\N	\N	سبتمبر 1	84451.00	0.00	0.00	0.00	1400.00	1000.00	1919000.00	1920000.00	1000.00	0.00	1920000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.1037+03	\N	f
1006	INV-سبتمبر-1-910293	419	\N	\N	سبتمبر 1	227.00	0.00	0.00	0.00	1400.00	1000.00	100.00	1100.00	1000.00	0.00	1100.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.1074+03	\N	f
1007	INV-سبتمبر-1-910488	420	\N	\N	سبتمبر 1	918.00	0.00	0.00	0.00	1400.00	1000.00	232400.00	233400.00	1000.00	0.00	233400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.111523+03	\N	f
1008	INV-سبتمبر-1-910260	421	\N	\N	سبتمبر 1	460.00	0.00	0.00	0.00	1400.00	1000.00	29000.00	30000.00	1000.00	0.00	30000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.115722+03	\N	f
1009	INV-سبتمبر-1-910522	422	\N	\N	سبتمبر 1	13.00	0.00	0.00	0.00	1400.00	1000.00	11000.00	12000.00	1000.00	0.00	12000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.120593+03	\N	f
1010	INV-سبتمبر-1-910027	423	\N	\N	سبتمبر 1	402.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.124351+03	\N	f
1011	INV-سبتمبر-1-910331	424	\N	\N	سبتمبر 1	130.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.128522+03	\N	f
1012	INV-سبتمبر-1-910356	425	\N	\N	سبتمبر 1	513.00	0.00	0.00	0.00	1400.00	1000.00	29000.00	30000.00	1000.00	0.00	30000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.133273+03	\N	f
1013	INV-سبتمبر-1-910423	426	\N	\N	سبتمبر 1	238.00	0.00	0.00	0.00	1400.00	1000.00	4400.00	5400.00	1000.00	0.00	5400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.137733+03	\N	f
1014	INV-سبتمبر-1-910564	427	\N	\N	سبتمبر 1	2.00	0.00	0.00	0.00	1400.00	1000.00	3400.00	4400.00	1000.00	0.00	4400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.141496+03	\N	f
1015	INV-سبتمبر-1-910006	428	\N	\N	سبتمبر 1	594.00	0.00	0.00	0.00	1400.00	1000.00	2000.00	3000.00	1000.00	0.00	3000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.145512+03	\N	f
1016	INV-سبتمبر-1-910501	429	\N	\N	سبتمبر 1	27.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.150777+03	\N	f
1017	INV-سبتمبر-1-910355	430	\N	\N	سبتمبر 1	104.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.154534+03	\N	f
1018	INV-سبتمبر-1-910352	431	\N	\N	سبتمبر 1	246.00	0.00	0.00	0.00	1400.00	1000.00	12200.00	13200.00	1000.00	0.00	13200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.157997+03	\N	f
1019	INV-سبتمبر-1-910024	432	\N	\N	سبتمبر 1	278.00	0.00	0.00	0.00	1400.00	1000.00	8000.00	9000.00	1000.00	0.00	9000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.161388+03	\N	f
1020	INV-سبتمبر-1-910023	433	\N	\N	سبتمبر 1	329.00	0.00	0.00	0.00	1400.00	1000.00	8000.00	9000.00	1000.00	0.00	9000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.165437+03	\N	f
1021	INV-سبتمبر-1-910021	434	\N	\N	سبتمبر 1	592.00	0.00	0.00	0.00	1400.00	1000.00	10800.00	11800.00	1000.00	0.00	11800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.170123+03	\N	f
1022	INV-سبتمبر-1-910022	435	\N	\N	سبتمبر 1	722.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.17342+03	\N	f
1023	INV-سبتمبر-1-910247	436	\N	\N	سبتمبر 1	70.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.177459+03	\N	f
1024	INV-سبتمبر-1-910020	437	\N	\N	سبتمبر 1	465.00	0.00	0.00	0.00	1400.00	1000.00	10800.00	11800.00	1000.00	0.00	11800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.180928+03	\N	f
1025	INV-سبتمبر-1-910561	438	\N	\N	سبتمبر 1	648.00	0.00	0.00	0.00	1400.00	1000.00	45800.00	46800.00	1000.00	0.00	46800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.185452+03	\N	f
1026	INV-سبتمبر-1-910018	439	\N	\N	سبتمبر 1	900.00	0.00	0.00	0.00	1400.00	1000.00	22000.00	23000.00	1000.00	0.00	23000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.190003+03	\N	f
1027	INV-سبتمبر-1-910007	440	\N	\N	سبتمبر 1	833.00	0.00	0.00	0.00	1400.00	1000.00	9000.00	10000.00	1000.00	0.00	10000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.193474+03	\N	f
1028	INV-سبتمبر-1-910513	441	\N	\N	سبتمبر 1	719.00	0.00	0.00	0.00	1400.00	1000.00	22600.00	23600.00	1000.00	0.00	23600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.196855+03	\N	f
1029	INV-سبتمبر-1-910019	442	\N	\N	سبتمبر 1	57.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.20179+03	\N	f
1030	INV-سبتمبر-1-910017	443	\N	\N	سبتمبر 1	172.00	0.00	0.00	0.00	1400.00	1000.00	7600.00	8600.00	1000.00	0.00	8600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.205874+03	\N	f
1031	INV-سبتمبر-1-910013	444	\N	\N	سبتمبر 1	112.00	0.00	0.00	0.00	1400.00	1000.00	28000.00	29000.00	1000.00	0.00	29000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.210575+03	\N	f
1032	INV-سبتمبر-1-910309	445	\N	\N	سبتمبر 1	337.00	0.00	0.00	0.00	1400.00	1000.00	39600.00	40600.00	1000.00	0.00	40600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.214821+03	\N	f
1033	INV-سبتمبر-1-910556	446	\N	\N	سبتمبر 1	264.00	0.00	0.00	0.00	1400.00	1000.00	71600.00	72600.00	1000.00	0.00	72600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.220505+03	\N	f
1034	INV-سبتمبر-1-910043	447	\N	\N	سبتمبر 1	589.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.226599+03	\N	f
1035	INV-سبتمبر-1-910395	448	\N	\N	سبتمبر 1	88.00	0.00	0.00	0.00	1400.00	1000.00	8200.00	9200.00	1000.00	0.00	9200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.230767+03	\N	f
1036	INV-سبتمبر-1-910343	449	\N	\N	سبتمبر 1	239.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.237582+03	\N	f
1037	INV-سبتمبر-1-910058	450	\N	\N	سبتمبر 1	4107.00	0.00	0.00	0.00	1400.00	1000.00	128400.00	129400.00	1000.00	0.00	129400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.241569+03	\N	f
1038	INV-سبتمبر-1-910008	451	\N	\N	سبتمبر 1	644.00	0.00	0.00	0.00	1400.00	1000.00	226600.00	227600.00	1000.00	0.00	227600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.24521+03	\N	f
1039	INV-سبتمبر-1-910441	452	\N	\N	سبتمبر 1	149.00	0.00	0.00	0.00	1400.00	1000.00	22000.00	23000.00	1000.00	0.00	23000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.250399+03	\N	f
1040	INV-سبتمبر-1-910540	453	\N	\N	سبتمبر 1	1174.00	0.00	0.00	0.00	1400.00	1000.00	19600.00	20600.00	1000.00	0.00	20600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.255881+03	\N	f
1041	INV-سبتمبر-1-910565	454	\N	\N	سبتمبر 1	851.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.259468+03	\N	f
1042	INV-سبتمبر-1-910057	455	\N	\N	سبتمبر 1	645.00	0.00	0.00	0.00	1400.00	1000.00	26200.00	27200.00	1000.00	0.00	27200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.263687+03	\N	f
1043	INV-سبتمبر-1-910455	456	\N	\N	سبتمبر 1	370.00	0.00	0.00	0.00	1400.00	1000.00	42300.00	43300.00	1000.00	0.00	43300.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.268913+03	\N	f
1044	INV-سبتمبر-1-910477	457	\N	\N	سبتمبر 1	48.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.273018+03	\N	f
1045	INV-سبتمبر-1-910041	458	\N	\N	سبتمبر 1	579.00	0.00	0.00	0.00	1400.00	1000.00	19200.00	20200.00	1000.00	0.00	20200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.277645+03	\N	f
1046	INV-سبتمبر-1-910446	459	\N	\N	سبتمبر 1	295.00	0.00	0.00	0.00	1400.00	1000.00	13600.00	14600.00	1000.00	0.00	14600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.28074+03	\N	f
1047	INV-سبتمبر-1-910468	460	\N	\N	سبتمبر 1	48.00	0.00	0.00	0.00	1400.00	1000.00	45600.00	46600.00	1000.00	0.00	46600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.286443+03	\N	f
1048	INV-سبتمبر-1-910040	461	\N	\N	سبتمبر 1	135.00	0.00	0.00	0.00	1400.00	1000.00	9500.00	10500.00	1000.00	0.00	10500.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.290144+03	\N	f
1049	INV-سبتمبر-1-910530	462	\N	\N	سبتمبر 1	389.00	0.00	0.00	0.00	1400.00	1000.00	1200.00	2200.00	1000.00	0.00	2200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.294307+03	\N	f
1050	INV-سبتمبر-1-910275	463	\N	\N	سبتمبر 1	347.00	0.00	0.00	0.00	1400.00	1000.00	10800.00	11800.00	1000.00	0.00	11800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.298821+03	\N	f
1051	INV-سبتمبر-1-910500	464	\N	\N	سبتمبر 1	62.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.304108+03	\N	f
1052	INV-سبتمبر-1-910521	465	\N	\N	سبتمبر 1	156.00	0.00	0.00	0.00	1400.00	1000.00	37400.00	38400.00	1000.00	0.00	38400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.308148+03	\N	f
1053	INV-سبتمبر-1-910300	466	\N	\N	سبتمبر 1	925.00	0.00	0.00	0.00	1400.00	1000.00	622900.00	623900.00	1000.00	0.00	623900.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.311373+03	\N	f
1054	INV-سبتمبر-1-910531	467	\N	\N	سبتمبر 1	327.00	0.00	0.00	0.00	1400.00	1000.00	30000.00	31000.00	1000.00	0.00	31000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.316422+03	\N	f
1055	INV-سبتمبر-1-910571	468	\N	\N	سبتمبر 1	0.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.321767+03	\N	f
1056	INV-سبتمبر-1-910279	469	\N	\N	سبتمبر 1	1337.00	0.00	0.00	0.00	1400.00	1000.00	27600.00	28600.00	1000.00	0.00	28600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.325573+03	\N	f
1057	INV-سبتمبر-1-910280	470	\N	\N	سبتمبر 1	1614.00	0.00	0.00	0.00	1400.00	1000.00	154600.00	155600.00	1000.00	0.00	155600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.329008+03	\N	f
1058	INV-سبتمبر-1-910464	471	\N	\N	سبتمبر 1	0.00	0.00	0.00	0.00	1400.00	1000.00	19000.00	20000.00	1000.00	0.00	20000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.334202+03	\N	f
1059	INV-سبتمبر-1-910044	472	\N	\N	سبتمبر 1	197.00	0.00	0.00	0.00	1400.00	1000.00	16000.00	17000.00	1000.00	0.00	17000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.338792+03	\N	f
1060	INV-سبتمبر-1-910045	473	\N	\N	سبتمبر 1	249.00	0.00	0.00	0.00	1400.00	1000.00	25600.00	26600.00	1000.00	0.00	26600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.341756+03	\N	f
1061	INV-سبتمبر-1-910303	474	\N	\N	سبتمبر 1	110.00	0.00	0.00	0.00	1400.00	1000.00	2000.00	3000.00	1000.00	0.00	3000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.346485+03	\N	f
1062	INV-سبتمبر-1-910046	475	\N	\N	سبتمبر 1	450.00	0.00	0.00	0.00	1400.00	1000.00	41600.00	42600.00	1000.00	0.00	42600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.352062+03	\N	f
1063	INV-سبتمبر-1-910554	476	\N	\N	سبتمبر 1	44.00	0.00	0.00	0.00	1400.00	1000.00	16400.00	17400.00	1000.00	0.00	17400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.355994+03	\N	f
1064	INV-سبتمبر-1-910555	477	\N	\N	سبتمبر 1	48.00	0.00	0.00	0.00	1400.00	1000.00	23200.00	24200.00	1000.00	0.00	24200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.360118+03	\N	f
1065	INV-سبتمبر-1-910273	478	\N	\N	سبتمبر 1	97.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.364007+03	\N	f
1066	INV-سبتمبر-1-910557	479	\N	\N	سبتمبر 1	28.00	0.00	0.00	0.00	1400.00	1000.00	8800.00	9800.00	1000.00	0.00	9800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.370059+03	\N	f
1067	INV-سبتمبر-1-910047	480	\N	\N	سبتمبر 1	792.00	0.00	0.00	0.00	1400.00	1000.00	40200.00	41200.00	1000.00	0.00	41200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.374067+03	\N	f
1068	INV-سبتمبر-1-910048	481	\N	\N	سبتمبر 1	145.00	0.00	0.00	0.00	1400.00	1000.00	20200.00	21200.00	1000.00	0.00	21200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.377346+03	\N	f
1069	INV-سبتمبر-1-910049	482	\N	\N	سبتمبر 1	2235.00	0.00	0.00	0.00	1400.00	1000.00	40200.00	41200.00	1000.00	0.00	41200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.380729+03	\N	f
1070	INV-سبتمبر-1-910050	483	\N	\N	سبتمبر 1	920.00	0.00	0.00	0.00	1400.00	1000.00	11900.00	12900.00	1000.00	0.00	12900.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.386265+03	\N	f
1071	INV-سبتمبر-1-910051	484	\N	\N	سبتمبر 1	1360.00	0.00	0.00	0.00	1400.00	1000.00	68200.00	69200.00	1000.00	0.00	69200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.389686+03	\N	f
1072	INV-سبتمبر-1-910053	485	\N	\N	سبتمبر 1	540.00	0.00	0.00	0.00	1400.00	1000.00	26800.00	27800.00	1000.00	0.00	27800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.393436+03	\N	f
1073	INV-سبتمبر-1-910009	486	\N	\N	سبتمبر 1	1284.00	0.00	0.00	0.00	1400.00	1000.00	23600.00	24600.00	1000.00	0.00	24600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.397489+03	\N	f
1074	INV-سبتمبر-1-910052	487	\N	\N	سبتمبر 1	392.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.402442+03	\N	f
1075	INV-سبتمبر-1-910340	488	\N	\N	سبتمبر 1	205.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.406438+03	\N	f
1076	INV-سبتمبر-1-910481	489	\N	\N	سبتمبر 1	347.00	0.00	0.00	0.00	1400.00	1000.00	27600.00	28600.00	1000.00	0.00	28600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.41071+03	\N	f
1077	INV-سبتمبر-1-910482	490	\N	\N	سبتمبر 1	41.00	0.00	0.00	0.00	1400.00	1000.00	6600.00	7600.00	1000.00	0.00	7600.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.41502+03	\N	f
1078	INV-سبتمبر-1-910056	491	\N	\N	سبتمبر 1	364.00	0.00	0.00	0.00	1400.00	1000.00	1200.00	2200.00	1000.00	0.00	2200.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.419309+03	\N	f
1079	INV-سبتمبر-1-910054	492	\N	\N	سبتمبر 1	375.00	0.00	0.00	0.00	1400.00	1000.00	10800.00	11800.00	1000.00	0.00	11800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.423706+03	\N	f
1080	INV-سبتمبر-1-910426	493	\N	\N	سبتمبر 1	65.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.426636+03	\N	f
1081	INV-سبتمبر-1-910055	494	\N	\N	سبتمبر 1	179.00	0.00	0.00	0.00	1400.00	1000.00	7400.00	8400.00	1000.00	0.00	8400.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.430721+03	\N	f
1082	INV-سبتمبر-1-910335	495	\N	\N	سبتمبر 1	150.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	1000.00	0.00	2000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.435786+03	\N	f
1083	INV-سبتمبر-1-910271	496	\N	\N	سبتمبر 1	240.00	0.00	0.00	0.00	1400.00	1000.00	16000.00	17000.00	1000.00	0.00	17000.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.440024+03	\N	f
1084	INV-سبتمبر-1-910272	497	\N	\N	سبتمبر 1	885.00	0.00	0.00	0.00	1400.00	1000.00	74100.00	75100.00	1000.00	0.00	75100.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.444123+03	\N	f
1085	INV-سبتمبر-1-910403	498	\N	\N	سبتمبر 1	377.00	0.00	0.00	0.00	1400.00	1000.00	17800.00	18800.00	1000.00	0.00	18800.00	2026-09-27	PENDING	Unpaid	f	2026-09-17 07:44:11.29504+03	2026-09-17 07:44:13.447924+03	\N	f
\.


--
-- Data for Name: meter_readings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.meter_readings (id, customer_id, cycle_id, reading_value, previous_reading, consumption, reading_date, collector_name, collector_user_id, approval_status, client_mutation_id, rejection_reason, whatsapp_sent, is_meter_reset, created_at, updated_at) FROM stdin;
1	1	1	56900.00	56900.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a0a7fb9d-6ea0-4792-80de-408a3ae87f87	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
2	2	1	44179.00	44179.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ee3ca86e-4ba7-41f9-80a6-f6dc1ae79581	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
3	3	1	35078.00	35078.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d7bece07-8dbf-401b-8eb0-7ef45b8ec70e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
4	4	1	1288.00	1288.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	aa15771d-2381-493c-bc20-210bd35a7cf4	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
5	5	1	226.00	226.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	903fad99-0e79-4f21-9f12-238bf9d65409	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
7	7	1	301.00	282.00	19.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	025f19f9-65f4-4306-ae92-7845853623bd	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
8	8	1	482.00	475.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f7bb000c-e23d-4172-91bd-4e1fa477813d	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
9	9	1	131.00	109.00	22.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f90a4e65-b0ba-4237-b71e-f9e21ef4ae31	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
10	10	1	277.00	272.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	c81fc582-e522-4c34-adad-b14b5fa99c43	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
11	11	1	0.00	0.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	c905d8a0-af0b-4f49-8cee-4c9fa52ce331	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
12	12	1	1308.00	1282.00	26.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d9b0e70c-a149-4a48-9b91-126422ee83dc	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
13	13	1	550.00	549.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d533e27d-0780-4d96-8845-e5937340e614	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
14	14	1	963.00	959.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	b1319025-a954-4755-a858-5205e67e97e6	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
15	15	1	1002.00	979.00	23.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	299ce2a0-141d-48fa-a488-ac5b894c8860	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
16	16	1	56.00	47.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d9858826-05ea-4c95-9585-32baf4db46c0	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
17	17	1	533.00	519.00	14.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	1c183945-0b0d-4017-acff-237738f09e4a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
18	18	1	1048.00	1045.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a55ab100-0f62-417d-82f1-03c18c133fe9	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
19	19	1	158.00	149.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d4d479fd-f5fe-4a25-9cb3-e831702d977b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
20	20	1	310.00	308.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	c740ae94-b9a9-4484-a199-68d9309391ab	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
21	21	1	1560.00	1527.00	33.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	2063bc87-4570-4dec-b2ca-112b39c21875	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
22	22	1	98.00	86.00	12.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	60e715f0-5c95-46d3-9474-8690ce5bfd26	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
23	23	1	147.00	147.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	357a5cb7-eecb-4319-8902-0525709cf710	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
24	24	1	324.00	312.00	12.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5a06f3ad-b0cd-4188-ba02-e36eb46cdfab	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
25	25	1	638.00	545.00	93.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	68bc4e4c-1053-4ed4-8a5b-4e672e8155f9	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
26	26	1	691.00	687.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	b7d6d5d4-77ac-45bd-87ba-45a3db8f3689	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
27	27	1	642.00	630.00	12.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5a4b7e9b-83dc-4025-9d5f-fbbcae657cde	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
28	28	1	52.00	52.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	05ca6bca-d4f5-4b60-ad9e-32ae4c4f2b6c	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
29	29	1	264.00	249.00	15.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	1e708f80-ee2e-4b61-82be-d66220936bf9	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
30	30	1	49.00	48.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	2579b513-a214-4462-997d-8af8d4235b40	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
31	31	1	98.00	97.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	83c18ca8-8f50-437d-bc47-e781c9fb5b96	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
32	32	1	609.00	609.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	cddcef20-15e1-4aac-a6d7-ec2ff01dcd47	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
33	33	1	194.00	186.00	8.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	bb3b3018-7c92-4333-b21d-c064192a6b03	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
34	34	1	58.00	56.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a64a66f0-6365-4174-b1c1-0d55961a1eff	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
35	35	1	367.00	365.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	90b23cfc-90ad-4d68-bf0f-0b57ffb2b226	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
36	36	1	124.00	121.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	49de697b-d43b-4067-963b-a50d65a114a7	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
37	37	1	99.00	95.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5a48e2f4-2509-4151-b292-e7eadc1aa35d	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
38	38	1	172.00	159.00	13.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	0fa62ef6-f1be-4082-9437-44ec7571a205	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
39	39	1	285.00	279.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	21755499-40d4-40b5-a222-4fab810ebd82	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
40	40	1	168.00	166.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f159e02a-307b-4627-aef2-eb2733eba854	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
41	41	1	269.00	252.00	17.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	b7fd76d7-68f6-4eed-9744-eac6efac3dd3	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
42	42	1	239.00	232.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	32b20c75-61ca-478a-8cd2-0862211c3485	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
43	43	1	458.00	443.00	15.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	209d2fb2-df7a-4e74-bb64-9d1cf65e53e1	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
44	44	1	263.00	255.00	8.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	30296504-ec75-42fa-88a1-90c5275db1fb	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
45	45	1	160.00	144.00	16.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	63706b12-1912-4848-9775-f27ef1b079e9	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
46	46	1	685.00	685.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a334c102-a982-4d47-8f0a-ee4ffbf138f8	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
47	47	1	430.00	427.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	dab4f160-0a68-4bf2-a3b0-c47576dad978	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
48	48	1	296.00	286.00	10.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	2e024b11-3f42-464d-be74-4db3ff8f0f03	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
49	49	1	352.00	345.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	19a4b43a-f999-4040-ab1c-f002c0970011	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
50	50	1	147.00	142.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	c6dcab2d-179d-4932-b7a6-4fa87c63b03f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
51	51	1	680.00	670.00	10.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	27af4bb4-fa38-434b-8a3c-932c15111105	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
52	52	1	436.00	436.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	1084fb44-0c1f-4aac-962a-76967933a6b8	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
53	53	1	641.00	641.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	7275d863-af2c-495e-9621-ebf8f7c81408	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
54	54	1	879.00	865.00	14.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	4681e588-e9de-4b73-8dfd-3a7670988029	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
55	55	1	1147.00	1143.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d307bc42-d671-4518-8c95-771f468d71a2	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
56	56	1	1064.00	1064.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	80ac27eb-520c-4cfa-8a1c-296263f345fb	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
57	57	1	868.00	862.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	c8a1c438-1e3a-4451-9824-c443b53ac0aa	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
58	58	1	995.00	958.00	37.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ffee2792-788a-4ea5-9f76-fae90fee24fc	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
59	59	1	240.00	230.00	10.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	c3d46b1c-da97-4dfa-a755-85cd7f0a86b0	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
60	60	1	342.00	333.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	eaaeeac1-1304-4cbc-a7ec-380424c9523e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
61	61	1	135.00	128.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d48a710d-7778-45c4-ae4e-f09e0c54b5ac	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
62	62	1	553.00	550.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	b30e1d5f-1957-4883-abe3-c7d07fdbac15	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
63	63	1	169.00	169.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	4c2def77-6c1c-47e2-9a2f-7084587c0256	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
64	64	1	272.00	267.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	76fe2a26-61bd-4cb1-a9a6-92cadaea0372	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
65	65	1	48.00	44.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	2530fed8-f733-4cd8-85ff-b154c9585a1a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
66	66	1	79.00	76.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	8a749e4a-d5ce-49cb-9c86-76a9f5cd6f71	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
67	67	1	114.00	111.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ddb63db4-5ab3-4be5-98bc-325ed8eef7b4	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
68	68	1	419.00	417.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ac3a5b50-ced6-4dd0-9497-3e2b0bb9b6d6	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
69	69	1	200.00	200.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	aeb93114-1405-4370-bcf7-cf18bae45a33	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
70	70	1	238.00	238.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	227a9b1b-4bcb-4e90-b440-686ccbce61ee	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
71	71	1	3373.00	3202.00	171.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	741b7265-15fe-4bb6-9659-fc20d32b8883	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
72	72	1	1280.00	1255.00	25.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	274f20d5-7845-4b8c-a3da-3fa2a58c0d1e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
73	73	1	33.00	29.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	10f871ff-b27e-4edd-926c-25a4a1ffe193	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
74	74	1	6.00	4.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d419b429-13a7-4c45-9478-1a800b554dc2	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
75	75	1	425.00	415.00	10.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	de8d6f6c-8e3a-4910-9a82-39a3aa6dd40e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
76	76	1	1034.00	971.00	63.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d974cc45-7440-4bb1-a74d-5cd6ff4f11dc	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
77	77	1	116.00	107.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	2b11f346-493f-4f33-a0da-0430c7a24d1a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
78	78	1	202.00	196.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3d3bf44b-34c4-4070-8de1-3140fbac86b3	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
79	79	1	12.00	12.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ff14b85a-fd12-44b7-ad79-4abcfc914dd3	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
80	80	1	130.00	127.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	9b53eebb-ff88-45f9-81b7-29bdf98df15b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
81	81	1	578.00	555.00	23.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	baaceefa-7362-4100-8401-16faa89b45d0	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
82	82	1	4.00	0.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	9d9dbdb4-0579-476c-8dd1-d6d924b8a66e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
83	83	1	184.00	180.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5cfc7792-c3b4-440c-8e19-1c2cce4d0486	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
84	84	1	458.00	447.00	11.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	10f2c1c7-3d39-427c-8afb-460b9d7a667b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
85	85	1	329.00	310.00	19.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	e88df8c5-eba1-46bb-96ad-5e74ea64ec41	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
86	86	1	1052.00	1017.00	35.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5459f9bb-0b99-4927-bb99-b239e1baf614	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
87	87	1	741.00	741.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a33309bb-b3d9-4b13-8690-7a346460add7	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
88	88	1	244.00	241.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3d9897a8-d955-494e-9d59-f0e3b7b42485	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
89	89	1	401.00	401.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a8d50484-c1bc-4e2b-a5d6-1bef7f146e07	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
90	90	1	440.00	430.00	10.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	904baba7-8402-4fd6-9f4b-ee4609d4e77d	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
91	91	1	4107.00	3987.00	120.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	aab85fa1-7837-469e-a026-0b4e546ed818	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
92	92	1	480.00	480.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	cda3a760-f04f-4bd5-9907-6c03b0f40fc3	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
93	93	1	1127.00	1118.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	9880cbc7-7410-48b9-9145-21ef5b948e24	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
94	94	1	337.00	309.00	28.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f955b289-4b6e-4b9e-bd8b-0c26848c616c	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
95	95	1	19.00	12.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	2d3105e8-d091-46dd-b774-cebc438d9d95	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
96	96	1	179.00	178.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a5a92353-b077-431b-b1e1-3f1ddcabb00f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
97	97	1	258.00	258.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	e534bbba-811d-49ca-86fb-4d2b255681ac	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
98	98	1	266.00	251.00	15.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	84db7594-028f-4c8f-97da-b4679f54a087	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
99	99	1	1522.00	1516.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	8189d1f0-cc81-49d2-adb8-44da04f2afc3	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
100	100	1	535.00	527.00	8.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	2bd7b15c-21df-4073-bf8a-62594e70150b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
101	101	1	113.00	112.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	12eb9dfe-186f-4b58-a039-038122b30b2e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
102	102	1	354.00	342.00	12.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	0ffa39c5-81bb-48b7-a8f2-fd97f944c04b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
103	103	1	702.00	686.00	16.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	93e2a829-8811-48b5-a1d0-a581c86781df	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
104	104	1	105.00	85.00	20.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	37a44a6f-bdc6-49ae-bdd9-931bf065815d	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
105	105	1	712.00	712.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	551cfd82-a7f8-46c6-9c39-0da9ebb1a170	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
106	106	1	325.00	303.00	22.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	116e2bf1-3030-4d48-b510-040efb691b89	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
107	107	1	319.00	311.00	8.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d367ca0e-2fc6-42f4-9436-9e865174d04b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
108	108	1	286.00	285.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5725c418-e0ca-4069-8c2b-61d2416edc98	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
109	109	1	86.00	77.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	936d7b10-15f5-41fc-94fe-69c139f544e8	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
110	110	1	1158.00	1156.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	982e1b07-f8ab-46ab-aa1b-16f5c64a90c0	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
111	111	1	1480.00	1479.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	c7ef635a-7991-4fd4-b3d2-ae47351a7ed3	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
112	112	1	267.00	267.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	cdf05400-3e1f-4fbb-ae2d-6c0854942fec	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
113	113	1	246.00	239.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	4ed89aa9-f71e-4e72-82ed-f20f295ab0a6	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
114	114	1	1582.00	1559.00	23.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	93f184bb-6c7c-4647-b8bd-c76f9af8a46f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
115	115	1	100.00	96.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ba469dad-2c50-4d22-9c86-7dc7dd37685f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
116	116	1	59.00	58.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	25f6d77e-1b20-4fb6-a749-31bd3b7020b0	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
117	117	1	367.00	362.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a2abe899-9904-457c-b6b2-8fe7e9605eb7	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
118	118	1	533.00	533.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	eb906e93-2101-4622-a902-8d60a8045a54	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
119	119	1	199.00	199.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	90cca171-e6a9-4ed2-8d67-6ca73809bb18	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
120	120	1	752.00	752.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	968f38af-24d6-461b-b886-acf387eb79b9	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
121	121	1	971.00	965.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	64e4fdbc-5aaa-4c64-990f-a0163dd59ea3	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
122	122	1	254.00	253.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	e3544a5a-ab6f-40f2-bb8f-44bbb30506de	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
123	123	1	192.00	192.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5973140d-fd52-4113-9579-1203a3b5f3fa	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
124	124	1	3007.00	3007.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	6e8e1b52-d13e-48c7-adc8-8bb9d9226ab2	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
125	125	1	91.00	91.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	87460f34-ae7d-47ed-b770-4fed4ffdf094	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
126	126	1	415.00	383.00	32.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	7b306cd1-53ab-4979-aa7f-7d6737c61f2e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
127	127	1	4591.00	4576.00	15.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	90c2db14-e819-4941-8fac-38962399ffc3	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
128	128	1	52.00	48.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	29c93153-ff98-4b0c-b78e-8092224e9b97	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
129	129	1	134.00	134.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d1b0f969-fe6f-4c5b-845a-7e0f80aa6704	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
130	130	1	2468.00	2462.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f056ec97-6e8c-483c-bb5f-55ed3e2ff253	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
131	131	1	143.00	141.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	7f33a6ae-60d4-4f61-886f-09661ded403e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
132	132	1	184.00	184.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3e0b0ae7-e676-4896-a128-d9e7a3d64211	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
133	133	1	1896.00	1857.00	39.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d2ad505b-36dc-44f9-936e-cddca15d9a78	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
134	134	1	678.00	669.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	318b3a4a-41d2-4805-ae9f-41918a333ca7	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
135	135	1	3543.00	3522.00	21.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ea9d17e3-ef27-4644-a820-4eedceb2e3bc	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
136	136	1	574.00	573.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	89a0db06-1293-46e8-9371-dc30eae00dec	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
137	137	1	830.00	798.00	32.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	90af139b-ee73-4885-b147-ed0219ca4ba2	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
138	138	1	1318.00	1313.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	e9181626-88af-4db8-8b42-2c6725be78b1	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
139	139	1	1314.00	1314.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	89e0a927-baca-437b-9a2a-bf059395f7ee	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
140	140	1	39.00	32.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	98522f5c-fefa-432f-bfa1-a3b822ef64eb	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
141	141	1	1267.00	1233.00	34.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3d2f86f5-6739-43ab-9f64-7994afe0f105	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
142	142	1	947.00	915.00	32.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	bd0fef22-4b33-4e42-8ce5-4ddd6b5c3f4b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
143	143	1	1217.00	1205.00	12.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	dbe69796-31d2-482a-b288-e1d9f5d00223	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
144	144	1	668.00	664.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	eae0a977-f027-4992-9dbf-4cefa975b50a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
145	145	1	635.00	617.00	18.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	67902150-5c38-4e6f-91df-0ae0f54948aa	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
146	146	1	512.00	498.00	14.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	053ee805-7547-4580-b2c6-bc26ff97704c	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
147	147	1	1966.00	1945.00	21.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	719f56b9-6d14-45d4-a23e-becab0cc4744	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
148	148	1	996.00	982.00	14.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	da877847-5c0f-4aec-a762-626703a5eda1	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
149	149	1	134.00	132.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a1d19e00-99fe-4063-9750-37c9f0a0ca00	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
150	150	1	65.00	61.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	15fab50f-b0c7-41b6-a80a-e91682b025f7	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
151	151	1	453.00	453.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	0ad311ee-957d-46af-ab59-42ebdfe70aaf	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
152	152	1	324.00	321.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	409cba7a-d175-440e-b964-01d51f48caef	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
153	153	1	252.00	243.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	219162a9-388c-4d1c-9e9c-1896922a076a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
154	154	1	252.00	252.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	42a1ef95-7ff4-4ac4-9d7c-ccfc1d24ed6b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
155	155	1	1077.00	1070.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	96e1b975-e838-4fa1-bd49-a89f8a4f2b8f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
156	156	1	225.00	220.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	0a5956db-243c-4e42-be6e-80e3b741fbf0	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
157	157	1	162.00	159.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	35a82ea2-8eb7-4977-b089-6c6c2df47fd8	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
158	158	1	605.00	594.00	11.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d2a73d6a-8d6f-4d25-bdc5-012b6d5bb2c4	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
159	159	1	582.00	572.00	10.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	af47feec-28e6-4aa1-a321-7434fe0e9084	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
160	160	1	200.00	199.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	9ccd4bd9-e9b8-4276-9138-0e7cf6bfaa1d	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
161	161	1	411.00	411.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	bb60277f-0a80-4eaa-a3ad-c5cea86fc7b9	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
162	162	1	2629.00	2625.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	7161ed46-03b5-4a9f-8187-af96fac83066	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
163	163	1	206.00	206.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	0eb064aa-7800-4e22-baac-6cc12f437b16	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
164	164	1	827.00	823.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	829eade5-b191-4b00-bdd7-9283acf795bb	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
165	165	1	2513.00	2497.00	16.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5fb45a3e-6835-4f57-b99b-c693aac4c6cd	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
166	166	1	172.00	158.00	14.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	c5733af4-8864-43af-bf02-38d880f8e07a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
167	167	1	381.00	366.00	15.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	cbff8fb1-1cc0-4782-be99-ebb5f7fd8bc5	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
168	168	1	189.00	176.00	13.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	4f557144-7ce9-41bd-887e-005e0cb915fb	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
169	169	1	93.00	90.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	e62b7591-c623-45ec-9535-96cfca91da24	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
170	170	1	266.00	254.00	12.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	76f6dd0c-989a-453b-8f7f-4149ef55ce32	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
171	171	1	752.00	727.00	25.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	203c38fe-8c61-411c-a064-8186b3200bf6	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
172	172	1	20.00	20.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f8b25c78-4d8b-498f-94b6-d4acded962b9	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
173	173	1	284.00	266.00	18.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ccc13b25-49a9-452f-bc44-dea3d8fb8f16	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
174	174	1	273.00	273.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	79c28aa9-1b00-41d5-b061-28eeef563ded	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
175	175	1	72.00	70.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f582a0d6-4e35-4246-bf0f-11836d7b6761	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
176	176	1	162.00	156.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	260d7b10-9c04-4672-b942-b1ff0b2ea522	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
177	177	1	2407.00	2393.00	14.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	4bb5c8cd-93e1-4b47-9b61-7e1ebecd3fd7	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
178	178	1	79.00	79.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3212eab6-c6dd-4862-bec6-1e59954a45f2	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
179	179	1	399.00	357.00	42.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	936f5aea-f57f-4cb6-be19-340719527b19	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
180	180	1	347.00	341.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	827014d6-dee1-46fb-8e11-7cff5557c04f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
181	181	1	470.00	464.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f25a425f-af5c-480d-aca0-050667d32466	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
182	182	1	78.00	74.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	067e0215-9d60-4dd4-b86a-3b45594bf443	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
183	183	1	1126.00	1110.00	16.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a20078d7-2cd2-4068-b719-f7cd3b2f08ed	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
184	184	1	485.00	467.00	18.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	34e54f44-9365-4f16-b0db-b6be1285b443	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
185	185	1	332.00	325.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	4186a483-3f89-4a41-812c-1e356f05b875	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
186	186	1	256.00	256.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	fddfe75f-ce9c-4101-bef0-143eb4de6427	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
187	187	1	35.00	35.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	594e3420-081f-48d5-ad52-e5658bf45d34	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
188	188	1	407.00	401.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5534eba8-4ea0-49c1-b7a9-c84e8d4cdeff	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
189	189	1	285.00	285.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	34bb5f03-0e74-47ef-b16a-79f75345adb9	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
190	190	1	140.00	135.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	e9c3368f-9779-477d-a426-367b2a3d3270	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
191	191	1	126.00	122.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f7ebf57d-bdb8-4c10-a40a-c15ed8b52469	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
192	192	1	5256.00	5245.00	11.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	30d8eaba-2b2c-4915-8f94-7e045c23ae92	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
193	193	1	111.00	109.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	4850a190-b0df-42a9-874d-b453be0dd8c0	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
194	194	1	1056.00	1053.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	12db3a50-a461-40e1-a7b7-e7097111eed4	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
195	195	1	2324.00	2324.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ac59e9c6-ecfc-4681-a903-fed01b17376a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
196	196	1	256.00	223.00	33.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ae4335d0-29da-4301-89da-faff61e5e8bb	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
197	197	1	266.00	265.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	78c35155-0868-4799-b828-c952b1bbbdd4	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
198	198	1	1496.00	1496.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	8472f508-f341-45d8-b757-b50faa963db5	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
199	199	1	1311.00	1301.00	10.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	e6d830d3-2f69-44dc-9595-2e013465f506	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
200	200	1	649.00	640.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	125592d7-2518-4b38-bfc2-f591725aad62	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
201	201	1	1060.00	1056.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	376b4dd2-aec9-44a9-b17f-95dedc66f29e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
202	202	1	5899.00	5880.00	19.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	23f7e52f-de47-4fb5-a808-95586e299810	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
203	203	1	993.00	975.00	18.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a330d815-c469-4dec-ab21-a82bba54107b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
204	204	1	284.00	284.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f4ca017d-a476-4613-b813-e003e1ce8be8	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
205	205	1	894.00	880.00	14.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	46876ddc-ee69-49f5-b51b-4701a86b95dd	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
206	206	1	196.00	190.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	fc765ad2-a218-4f42-b1c4-2abc52b489ff	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
207	207	1	1050.00	1044.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	2daccbf5-6470-40ba-864a-cba69653cae7	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
208	208	1	150.00	52.00	98.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	93b09283-5e89-460b-b15d-ff89d084aaee	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
209	209	1	1064.00	1064.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	66bf7979-78f9-47ee-bbd9-554f5647d9b5	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
210	210	1	2422.00	2400.00	22.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	23bf1f4c-00c4-4112-94dd-f0d18c5c2efd	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
211	211	1	399.00	393.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	81913147-87da-4874-87b0-3effd26f3c67	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
212	212	1	2266.00	2266.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3835c361-0e32-4806-8dfe-445ad3c796f5	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
213	213	1	388.00	344.00	44.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	c1bc5f71-4283-45f6-8d74-b75bda37156f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
214	214	1	370.00	358.00	12.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	9adbbf9c-7213-4022-9e4a-94be93174d22	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
215	215	1	476.00	468.00	8.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	aee4b680-239b-480e-bccf-637b3d2d3487	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
216	216	1	102.00	101.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	92ec1c5b-6527-4dd1-98d3-f77fdb012f1d	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
217	217	1	196.00	196.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	e1b864a3-7aaa-4220-a8dc-b3e19c6d5f04	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
218	218	1	293.00	285.00	8.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	6eda1868-ee47-4ae4-a2f5-f5765b95bda6	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
219	219	1	220.00	220.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a7712de0-e4ce-49c3-a231-50c9b86772d8	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
220	220	1	151.00	44.00	107.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	4f6b9bbf-e48e-471d-ac89-f559c6a18d59	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
221	221	1	64.00	63.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ee9bbd9a-1dd5-4c27-9a1f-cd38491688a2	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
222	222	1	54.00	50.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f2a9c109-0f6e-492f-bd63-98e6bbe42dd4	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
223	223	1	76.00	72.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	074237e3-43e9-4f1a-86b8-6c9c8e44b357	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
224	224	1	1147.00	1127.00	20.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	132b124c-566a-43a8-a844-2a393f19bb24	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
225	225	1	82.00	71.00	11.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	da281035-0774-4d80-b5f4-176300432df0	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
226	226	1	225.00	220.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	40df0bdb-b560-4619-a166-0729eee78852	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
227	227	1	244.00	230.00	14.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	68303820-21f8-40bf-b132-6c0c006a4c05	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
228	228	1	39.00	37.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	b3e2f00e-4c64-4a9d-abc0-65ddb379b8bc	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
229	229	1	196.00	189.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	90d8d1c3-dd1e-4c63-9c20-65dc3f40fd49	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
230	230	1	87.00	85.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	dafcbd16-da11-414b-b409-44c2ebe6a7d8	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
231	231	1	59.00	58.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d7c9cf97-f765-4e12-ab04-5feea11e22ad	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
232	232	1	1651.00	1651.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	c6c476e7-3564-48d3-87cb-6140daebba92	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
233	233	1	75.00	63.00	12.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	605bb7fd-9a36-4454-905e-0cfd0d1b3554	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
234	234	1	296.00	296.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3ce31009-aee2-4283-83bb-a8ff35ada882	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
235	235	1	763.00	718.00	45.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a3eece73-5e2f-432a-aeb3-203d135e12af	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
236	236	1	103.00	103.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	9699b10f-430b-4058-916e-ca0269c94d1f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
237	237	1	343.00	337.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	9baa75c9-f5d6-4821-998d-c586b70e7ecd	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
238	238	1	242.00	228.00	14.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ca819daf-3a6f-4ff7-84ad-491f4592a490	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
239	239	1	2180.00	2162.00	18.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	b549a369-fe4d-4c96-a987-010630140e73	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
240	240	1	369.00	360.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	683fca7c-a804-4e65-8f33-8ec161800da4	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
241	241	1	1573.00	1560.00	13.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f32c72ff-bfce-4b41-af8c-a9bf23b15df8	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
242	242	1	4402.00	4402.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ee641a26-f9dd-4f79-a2c2-27e474104030	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
243	243	1	5564.00	5564.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	6a4f7d7b-9c23-4583-810a-6444da558468	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
244	244	1	2053.00	2018.00	35.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	0027be29-03b8-400e-93f5-b1f7e55ed3d7	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
245	245	1	641.00	641.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	8545be19-37ae-44e1-8afa-20dc71c30fe9	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
246	246	1	1040.00	1040.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	00f534cd-463f-4803-ab78-199fe0d599a0	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
247	247	1	269.00	269.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	be8e173a-baad-4180-bd45-b76846131a80	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
248	248	1	574.00	566.00	8.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	24fc5f4f-182d-4631-84dd-be924c74064b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
249	249	1	223.00	218.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	c86cffaf-6a29-45da-9ac8-907d8563141c	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
250	250	1	1230.00	1222.00	8.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	c000a3e4-4a6c-4ec9-834c-b70b28e0e135	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
251	251	1	162.00	159.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	24881a27-f80c-4d78-b6a6-96da383c7405	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
252	252	1	1114.00	1096.00	18.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5112ec91-a590-40fc-a835-2139c9aca3bb	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
253	253	1	56.00	55.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3d64e2ad-38d5-4cd6-b558-6903bd29927e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
254	254	1	82.00	79.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5d187a5f-0978-4f08-94c4-b2037777ae05	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
255	255	1	89.00	86.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	08f2a0bf-37a2-4300-8fad-75c809f21c0b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
256	256	1	109.00	106.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3013b873-53cf-41fc-b62f-727ce252537c	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
257	257	1	56.00	54.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d8d7af16-b7a6-4115-9124-9832cf94ce0f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
258	258	1	68.00	62.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f04cb71d-cc5d-4521-9151-0b49c9ceb10b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
259	259	1	94.00	93.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	7377033d-5fc9-4341-8404-98efe260b59d	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
260	260	1	19.00	19.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	917d0e38-3f1e-425f-b036-bebd9744b205	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
261	261	1	391.00	391.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	9f95e8e8-5e3d-482c-b9da-4f8c5cf5d0f4	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
262	262	1	266.00	266.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	8bb6b76e-0eb6-4076-b3e3-bbb7f42ca099	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
263	263	1	1450.00	1450.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	074aa94e-a1f2-477b-a53a-b9217597558f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
264	264	1	308.00	308.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a449a2ca-2d5a-4de4-a84e-3d235147edca	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
265	265	1	471.00	466.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	adbe4091-8a68-4780-81f5-dccdc0d6aa69	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
266	266	1	28.00	28.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	12c869bc-e0d6-4c9b-8b69-f31a4b25a347	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
267	267	1	1025.00	1016.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	7037610a-5555-41c0-934f-dd73ddcce900	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
268	268	1	888.00	888.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f676e04c-55e7-4731-8ad4-15fafdb7a9ae	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
269	269	1	163.00	156.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	557808af-425f-430b-b162-2fe00430d8a2	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
270	270	1	250.00	243.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	c02f0010-966e-4835-8d68-d963b5dcf10e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
271	271	1	3391.00	3387.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ac78fba0-1cf0-4749-8b11-7d7da873c11f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
272	272	1	1221.00	1217.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	78ddcf82-2398-43db-b287-a20c2cd8b693	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
273	273	1	300.00	294.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	7873cd9a-4e17-465c-9b90-4eda14c55f7f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
274	274	1	239.00	231.00	8.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	1f50b7ca-f156-4e35-96ec-27006db7cc6f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
275	275	1	1435.00	1426.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	08472d38-0366-4b1b-b5e0-3a73f0f1e520	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
276	276	1	230.00	227.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ce797dce-03c3-4905-82d0-9f48d9e6f96d	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
277	277	1	446.00	415.00	31.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	8d5ca28a-7ee2-403e-9301-ee5667805854	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
278	278	1	306.00	300.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5e8dc0cb-767f-4601-a035-0cb4274850d5	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
279	279	1	159.00	154.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	cda952d7-9c43-47f9-b17d-3a7888fd81f3	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
280	280	1	563.00	563.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	4eae3d91-efab-4cf6-a3a4-de26470dea5b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
281	281	1	59.00	54.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	40630b00-14a7-42f0-975d-c87f598dfb19	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
282	282	1	281.00	273.00	8.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ab08637d-85df-432a-9a25-24f481e4d27a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
283	283	1	189.00	185.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	2975d7b2-1309-4742-ac15-070e6b16f236	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
284	284	1	353.00	353.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	4834b8d2-50d5-4024-9886-fe98a652b989	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
285	285	1	1296.00	1286.00	10.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	43adfe12-71af-41d8-a147-877b471ff8bd	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
286	286	1	1453.00	1418.00	35.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	bf9dbc93-842e-4216-b0f0-0b2290cf59a6	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
287	287	1	88.00	74.00	14.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	24aa5e06-aee2-49f1-a0b6-ef43e43fc0b4	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
288	288	1	408.00	398.00	10.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	559b4675-6337-4471-b4f3-2551ec056c29	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
289	289	1	40.00	24.00	16.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	8e312a60-a3b2-49fe-83f1-f217d3278712	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
290	290	1	794.00	785.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ce4f0a3d-cf9c-4516-874f-475c05cbddc6	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
291	291	1	914.00	912.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	8ba7243b-441f-4ec3-85c8-f59822fbc29e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
292	292	1	88.00	88.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	29d42020-0e03-4139-8338-114c0b109200	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
293	293	1	477.00	456.00	21.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	90125064-1f68-4b83-9760-fe27bcab6736	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
294	294	1	214.00	188.00	26.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d6122d15-43e6-491d-98a9-625d59c903e8	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
295	295	1	4785.00	4780.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	7ece182b-1a41-40b0-b2fe-83c15cfc327a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
296	296	1	266.00	261.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	0b705ff2-08de-42ad-a359-fd98466476b5	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
297	297	1	464.00	440.00	24.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	0804f458-fbfd-43aa-aa86-6d00dd8519ce	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
298	298	1	3846.00	3807.00	39.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d56aa7cd-fb05-42b0-8d28-01bd4673ae37	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
299	299	1	2109.00	2091.00	18.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ad94c2ff-8ddc-4a6e-8eb6-9fb321b1989c	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
300	300	1	534.00	534.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d46244a1-466c-428d-bfa2-bb0923c7eadb	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
301	301	1	598.00	598.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	621d7076-77f6-4d4d-9084-b53ce81ab026	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
302	302	1	103.00	95.00	8.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	e47d4223-147f-4cb4-9a03-331961821582	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
303	303	1	537.00	526.00	11.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	9f10603e-3789-47c1-b864-ee69d5deceef	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
304	304	1	163.00	149.00	14.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	87c33c69-f64f-443a-8a63-2767e93f9363	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
305	305	1	144.00	134.00	10.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d608e5c0-d66d-492c-b859-f3db6088345e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
306	306	1	65.00	59.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5c8d5d46-2a9b-4bf2-adfc-2fd673fec4ff	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
307	307	1	2410.00	2410.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	19c21a44-32e9-4930-be9a-33dcf9a07fb0	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
308	308	1	77.00	77.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	52cbb3ec-a3ce-401a-bb05-b196fd178829	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
309	309	1	177.00	170.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	e63af8c6-13b5-47bc-96f1-99c7bf05c5c4	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
310	310	1	281.00	274.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	89bfafc8-dd7e-49ac-87ec-3297e023d7b9	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
311	311	1	1006.00	999.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	b5423b95-6ac3-40e4-ad4c-e01d0f5935a7	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
312	312	1	518.00	513.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	32d93078-f999-44fb-8a0f-a71eaf658274	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
313	313	1	268.00	267.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	fbe2a2b8-f145-4b9a-b409-44bb15fcfb11	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
314	314	1	2482.00	2462.00	20.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	b271ab58-3317-44fc-9383-4129f001d53c	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
315	315	1	212.00	207.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	407dab47-9ad9-4511-82e7-657fc2493fa6	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
316	316	1	238.00	232.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	39894b13-0b02-482d-9a6f-ee6a99451658	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
317	317	1	103.00	98.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ec68c084-126d-428f-a216-af611518c40a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
318	318	1	108.00	108.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	50243504-39d8-4bec-955b-798da121a783	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
319	319	1	47.00	44.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3cd113df-79a3-4b48-a582-9b88e6bdb19b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
320	320	1	349.00	346.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d9786e12-7d7f-4e32-be6d-24d639fa6d6b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
321	321	1	174.00	174.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3c66c720-f322-4122-9c87-c3af0b4ca6f4	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
322	322	1	590.00	581.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	024a29a3-4664-4995-b35c-5f658f58a800	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
323	323	1	3511.00	3484.00	27.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3ec84a7d-9550-4531-9748-f916697548b3	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
324	324	1	0.00	0.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	00fe0978-77f0-40da-a565-1837f9b3da33	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
325	325	1	775.00	752.00	23.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	c91244c1-7fd8-4706-a5af-b96fa7efc6cb	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
326	326	1	452.00	440.00	12.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	303da503-8f10-4c93-bea2-06d0b72c9930	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
327	327	1	807.00	775.00	32.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	76770c8b-a08a-46b9-ae81-6fabc8e3cfa7	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
328	328	1	53.00	51.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a0a7acd5-31c8-479c-bf6b-5786383e6d4b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
329	329	1	9.00	8.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	bb19f676-d38e-4be7-a74f-48338002263e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
330	330	1	88.00	79.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a143093a-d1a7-4f78-892c-78710b7eae65	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
331	331	1	1691.00	1685.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	4e3a0ccf-01ed-4273-9421-82fa2c5e734b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
332	332	1	324.00	321.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	8d2a5354-2220-4907-9975-f97004c587fe	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
333	333	1	470.00	446.00	24.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	afbe0d15-a524-4e04-87b1-63e0cb96df1a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
334	334	1	322.00	306.00	16.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	c0789199-f506-4574-be08-e74ba34a07ec	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
335	335	1	551.00	542.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	67ed2f57-9a95-4edc-9a83-f750d0243932	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
336	336	1	446.00	435.00	11.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	c7e53fe6-1141-40ac-a732-b91ed433e180	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
337	337	1	440.00	430.00	10.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	47057cfe-adb3-4022-8de5-c30cd081f521	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
338	338	1	33.00	28.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	dd3f6325-c954-4119-ab61-b0914346e28e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
339	339	1	160.00	156.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	417f93ae-3bae-4adf-a139-fee90bf25c66	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
340	340	1	663.00	654.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	0cf9f8e2-35c8-4751-8985-459d0d508f4c	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
341	341	1	850.00	850.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	9febeef1-b9a6-477f-b6e5-09030063cb1d	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
342	342	1	307.00	298.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	124db311-2bbf-4699-8230-ee1accecfefa	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
343	343	1	260.00	254.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3bbb64cf-7b76-47c2-9c72-d47a44aef749	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
344	344	1	294.00	288.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	14365d30-7f90-4af3-91e8-f9ef6fbd847d	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
345	345	1	537.00	524.00	13.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	0fd1db51-c799-4639-9714-dc99f01a94fc	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
346	346	1	591.00	591.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ec8ce018-d965-4091-9daa-5942496a92b4	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
347	347	1	84.00	77.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	b5680cd0-e1d4-4227-9a8a-02606aa5cb78	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
348	348	1	171.00	162.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	1579890d-2fb0-4eb2-ae8d-a3486d2cb2b3	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
349	349	1	136.00	123.00	13.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d46976ef-731a-41ec-a6cf-70412dd7864d	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
350	350	1	76.00	72.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a83542dc-a086-444c-bedc-e8d750aef5d8	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
351	351	1	77.00	75.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a4d8cac5-cb20-4bfb-8005-d9b494d71608	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
352	352	1	789.00	783.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	45b10ba2-6a36-4ffa-be6d-01fe5e7e7d7b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
353	353	1	1953.00	1872.00	81.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	52729a1c-5984-4e34-9d56-8fc9a2a5345e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
354	354	1	27.00	27.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	bfc2c35b-67be-4314-9974-05a58bb9b9cb	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
355	355	1	249.00	249.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3f711947-8c3d-4f21-b0b4-cd0ab3e771e4	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
356	356	1	154.00	154.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	8577318c-e8f8-4ccd-b2e7-90fd28279841	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
357	357	1	268.00	259.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	1578bace-5dba-4d78-8ca7-2d9089c36a8c	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
358	358	1	5463.00	5384.00	79.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	deb9c041-b108-4a5c-9032-11b0bec18628	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
359	359	1	351.00	345.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	e927592b-b92e-4eb8-9036-48b05c86488c	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
360	360	1	1298.00	1291.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	18a05f8a-cdfd-41bb-b4b1-b08b5b539e3b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
361	361	1	15.00	15.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5096cf05-6193-4eae-a2f6-882ae2b1cc24	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
362	362	1	82.00	80.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	9516562c-b810-4b12-9ce8-b6d88dc9bf3c	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
363	363	1	510.00	510.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	03dcf8d7-46c7-450b-8f9b-8b9efac324a9	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
364	364	1	838.00	831.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	803012c0-accb-4486-8d55-bc08e81aa94f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
365	365	1	326.00	326.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a7e2fbe8-eb31-47da-b4b5-6781b2fcc25f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
366	366	1	37.00	37.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a0825b9a-6be5-418e-b3fc-3cf982490aa3	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
367	367	1	68.00	68.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3dd0f565-79a3-43e3-8a61-18a134079563	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
368	368	1	301.00	297.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	2a7bf3e6-881b-4695-b87f-3c298d062798	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
369	369	1	198.00	198.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	fe764856-4433-4b04-a57b-a143b904d6e9	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
370	370	1	176.00	161.00	15.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	4927bdb9-198a-41b5-8b9b-23f5c71eb50f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
371	371	1	332.00	323.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	daf859e4-b7e3-42fd-849c-d4bbf0a93256	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
372	372	1	225.00	219.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	486dd5b4-3db4-44d0-a2a9-de6f90b2d21c	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
373	373	1	72.00	65.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d226d6b5-11ef-4b1b-bf28-08e75dc6cc79	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
374	374	1	505.00	494.00	11.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f8c4a85e-be7b-451b-953d-3541348bebbb	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
375	375	1	234.00	232.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	478ccb0b-78cc-4bb2-9273-c56314b86d88	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
376	376	1	144.00	143.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	7accb5b7-0bd6-4717-bc2e-77af3fcab6a5	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
377	377	1	559.00	553.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	8329f1df-ca88-4f1a-b05e-add99ed7e4f5	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
378	378	1	408.00	391.00	17.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3222caa3-fcca-47c5-a84e-c02d793f903a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
379	379	1	410.00	406.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	91119c59-abce-4fcd-a797-cd6300fb08ee	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
380	380	1	252.00	237.00	15.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	49a6cc78-f71a-4a12-a721-684631e86047	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
381	381	1	540.00	529.00	11.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f68ffd59-8184-48f3-a7dc-2f9a74630084	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
382	382	1	346.00	341.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	abb5a99a-c00b-441d-a32c-25fbdad73512	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
383	383	1	1568.00	1542.00	26.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	e769519a-e773-454e-b069-6a72166500c6	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
384	384	1	273.00	265.00	8.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	6a658681-ffae-4688-97e6-13a303969e99	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
385	385	1	279.00	274.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d78a9295-230b-4d54-9b3e-fbbdcf510012	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
386	386	1	452.00	449.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	02c31736-04aa-4084-9704-79c6d43b615b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
387	387	1	102.00	100.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	4d974d14-50f9-4b15-a217-ee9e945152ba	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
388	388	1	902.00	892.00	10.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f833a247-ab84-458c-856b-8d0614d693a9	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
389	389	1	455.00	449.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3c61104c-0769-430c-a989-4558b54263c8	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
390	390	1	133.00	124.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	11008cd7-1fd4-44d7-9e3a-f9325e50266b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
391	391	1	667.00	664.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	885a699f-90d7-43c7-a1a9-7c470dc368e2	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
392	392	1	1903.00	1856.00	47.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	c9ef3817-53d4-431a-97b7-4bfdfba0f448	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
393	393	1	631.00	626.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	25105b71-c678-4f07-a087-249e0a3fbdaf	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
394	394	1	43.00	41.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	1dfdf7f6-4834-46a6-961a-91796995f192	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
395	395	1	131.00	129.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	b342285e-5d79-4bb4-8b9a-2ea5610dca1e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
396	396	1	82.00	78.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	17edc494-791e-448a-9584-a5a1559e3bb4	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
397	397	1	264.00	255.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	68a8a1c2-b287-4d68-9870-6194ed51ba59	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
398	398	1	224.00	224.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ff8ce3a1-852f-4f2c-b8d5-16b73aa32da1	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
399	399	1	213.00	203.00	10.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	b96998eb-2d52-4583-a196-7b890b1d9d4f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
400	400	1	231.00	222.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	2a03c092-9080-45d8-8012-eecfa26d179a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
401	401	1	346.00	337.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a80ba6c2-25be-49df-898d-a59d59c30505	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
402	402	1	647.00	641.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	2cb67af6-7517-475e-9849-ac421b442d25	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
403	403	1	527.00	508.00	19.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	b092a3e8-23b6-4bfd-ae2d-4ed57597cb1e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
404	404	1	1962.00	1953.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	55eb0739-1fa6-45c1-8740-a4b43e7f9a6b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
405	405	1	198.00	197.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	6e77352d-93cf-4734-becc-c262c6b76697	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
406	406	1	65.00	65.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	be82ef6c-68ba-4e72-9bab-6dacc4e816cf	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
407	407	1	75.00	74.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5b123fb7-9928-4c09-9a45-4ec1861a1c7d	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
408	408	1	6.00	6.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	adeb719e-0afa-4e1e-bb3b-040a2538e97a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
409	409	1	139.00	139.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ea39a4e0-da78-4276-9645-045072292b32	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
410	410	1	95.00	93.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	b2c4df1c-cf12-463a-9028-cba1484a5e5b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
411	411	1	3.00	2.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	9c704764-ae16-4e8e-94e4-c1a1febf5277	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
412	412	1	8.00	8.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	0770ecde-b3b0-42a4-b04a-d20193458a1e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
413	413	1	25.00	23.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	381971eb-c737-4def-b306-55ed472a9bb3	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
414	414	1	1754.00	1729.00	25.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3f3a5340-c9fd-4aa9-9ceb-dba1b2e99d4b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
415	415	1	1580.00	1580.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f8b98438-3fc4-440d-adef-376b8dc2081b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
416	416	1	67.00	67.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3a76afdb-7934-44ec-a538-dc1dbe562ff2	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
417	417	1	1610.00	1610.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	535d5c42-2eb8-4856-ab9b-3e48186eb3c7	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
418	418	1	84451.00	83081.00	1370.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	224c8de8-5a3a-4a29-9058-62d157b8c017	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
419	419	1	227.00	227.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	bb626d4d-1ddf-462d-bbd0-2dab1e1f47c0	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
420	420	1	918.00	918.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5f53fb0b-9ca3-4849-8696-acdac9f4399d	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
421	421	1	460.00	440.00	20.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	7e46e849-9d0f-45d9-8278-f918d0a17911	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
422	422	1	13.00	13.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	6048f279-a175-48e4-8eab-80caba9e525a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
423	423	1	402.00	398.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	cb6d63b9-0417-4950-93b9-aeb855354ce8	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
424	424	1	130.00	130.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	b2917872-f111-4a62-b131-0a0543504257	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
425	425	1	513.00	493.00	20.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3c8d25c3-bb6a-4ab6-9424-078aa2b5f63d	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
426	426	1	238.00	238.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	10ad3de4-2356-4c64-b7eb-5a5e9d454d0a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
427	427	1	2.00	1.00	1.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	6463b3ac-9cae-4080-8bfb-49276484a189	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
428	428	1	594.00	594.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	8e005601-21ea-4d2a-a31f-022af14f19fe	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
429	429	1	27.00	23.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5f4cc42d-9a03-44ca-908a-b10d26bd3122	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
430	430	1	104.00	104.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	9e253da7-3828-4ecd-9579-4663ea2b5f00	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
431	431	1	246.00	238.00	8.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5bf4acd6-a355-4023-a094-878c9dfacc89	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
432	432	1	278.00	273.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	34212c82-b248-41d2-9388-1b45e1814379	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
433	433	1	329.00	324.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	1756b624-d82c-4fa2-97a8-99dcd1ac1364	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
434	434	1	592.00	585.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ce46047c-6655-4be0-96c5-02c220bd8f21	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
435	435	1	722.00	699.00	23.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	3ffdc55d-f416-466d-a048-5d888797c764	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
436	436	1	70.00	66.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	71b6708e-707a-4b43-be7b-403e53add9bd	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
437	437	1	465.00	458.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f78ed6e0-631b-42ae-a57d-2f1bae0a5f5f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
438	438	1	648.00	616.00	32.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5893e953-9881-453a-a16b-357dadddf259	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
439	439	1	900.00	885.00	15.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	68f7c737-1a7a-460a-9bd2-76bd37116b27	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
440	440	1	833.00	831.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	cb46fff5-0935-42c5-a95f-c048aa6e251d	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
441	441	1	719.00	716.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	2d5a13ae-b191-42be-a844-45807cb4b414	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
442	442	1	57.00	57.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	10e19c7c-addf-465a-9468-ae80739173d3	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
443	443	1	172.00	168.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	48563bdd-9d92-467a-80a4-85d4cf2b74c2	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
444	444	1	112.00	112.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	f6994eb1-0d56-48a3-9b77-765d5fb4d91f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
445	445	1	337.00	330.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	83b966e7-e4f5-4a99-a1ef-03152dd166fb	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
446	446	1	264.00	264.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	612f9457-bb54-4af3-800b-15256dde76de	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
447	447	1	589.00	589.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	4ba3ee78-90dc-4520-b6c5-2fe95ef734e7	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
448	448	1	88.00	83.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5b02dafe-103c-40d7-9064-d625c0257a5a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
449	449	1	239.00	239.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	18c8cfe5-1149-488c-b246-fcf4d31a358f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
450	450	1	4107.00	4016.00	91.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	fd74ef31-6d9b-42ad-886c-a12904cea1ed	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
451	451	1	644.00	631.00	13.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	7351b48f-4ee9-42b1-a4a3-24f0093329bf	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
452	452	1	149.00	134.00	15.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	7c2075ff-1756-4c73-8eb3-c47f3eccaa45	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
453	453	1	1174.00	1174.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	916f04f4-d43a-41c6-b12b-abb4263cccb5	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
454	454	1	851.00	851.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	4525e80a-23cd-43be-8e91-e8733088aae8	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
455	455	1	645.00	627.00	18.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	49600c14-cdd2-44ac-b615-d4c304a2603f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
456	456	1	370.00	356.00	14.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	0512e793-a8d5-4fa2-89dd-21e8c834ff55	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
457	457	1	48.00	44.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	179a5ada-060d-4c90-a674-b5bc9d4e8764	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
458	458	1	579.00	566.00	13.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	74c69c8a-e325-4c49-96a1-718e1fdafeec	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
459	459	1	295.00	286.00	9.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	09266f3c-58c1-491b-be62-8120673d229a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
460	460	1	48.00	48.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	2d20ebcf-92d1-41ab-8425-6b1e8bf0c845	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
461	461	1	135.00	132.00	3.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	5fead648-1a1d-4701-bbb0-cbbd7d58ceed	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
462	462	1	389.00	389.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	982aaf87-2206-4ac7-a3a9-89bc2280903e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
463	463	1	347.00	340.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	29d9f9f4-35c1-4646-b205-9bce89b90523	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
464	464	1	62.00	55.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	06071d2f-c69a-47cf-acd7-13fdc3846713	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
465	465	1	156.00	145.00	11.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	38d0e8d0-a2d8-4452-ae7f-7c9f59a69b92	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
466	466	1	925.00	907.00	18.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	acf58cd7-9c06-4f8c-a680-2adc9a6e1401	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
467	467	1	327.00	312.00	15.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	2651eee6-c2d4-49bb-ac70-5b80121ffe44	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
468	468	1	0.00	0.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	36607e31-c9d1-4277-aa23-e46b322af3aa	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
469	469	1	1337.00	1322.00	15.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	b7dcf84c-e06d-44da-ae7a-737c4c02e84f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
470	470	1	1614.00	1614.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	9cd6750e-eba4-4045-b121-2e0ecffb0379	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
471	471	1	0.00	0.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a3d7f849-0f4e-4dc2-93b5-8aefbf33ae2d	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
472	472	1	197.00	191.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	38fbed28-3840-416a-a048-5d17a863491f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
473	473	1	249.00	249.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	8ba6cc96-daa4-4227-a7eb-79b56bb90332	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
474	474	1	110.00	110.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	7246e81c-b39d-4d61-b52e-348dd9e785f0	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
475	475	1	450.00	421.00	29.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	874fcbd1-3e70-4f38-9563-d6bdc6d9fe8a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
476	476	1	44.00	33.00	11.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	70f098e5-9c46-46cb-93d2-d1657bb4a314	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
477	477	1	48.00	40.00	8.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	0254cd8b-24fc-491c-a196-695ef42e6e17	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
478	478	1	97.00	93.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	a2d65d87-3861-401f-9be6-a4048a548460	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
479	479	1	28.00	23.00	5.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d549836c-4680-40b5-b541-c0286d4239f7	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
480	480	1	792.00	764.00	28.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	6fe3d2a0-4a39-4c19-a859-e84b5c57a393	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
481	481	1	145.00	138.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	678f5698-2aa9-4b95-bcc5-ade61a78680a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
482	482	1	2235.00	2207.00	28.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	9da510e2-4c59-4154-85e0-3f3c0ebcaa04	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
483	483	1	920.00	913.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	78085579-0964-43ea-98eb-ea11c653503f	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
484	484	1	1360.00	1312.00	48.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	d58d6a16-49e2-429f-a803-2088d2fe6ecf	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
485	485	1	540.00	532.00	8.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	1f353104-303e-40b8-9f67-fb566d715102	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
486	486	1	1284.00	1270.00	14.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	07d91972-0d20-4fdd-a591-bb31c66abaed	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
487	487	1	392.00	385.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	fae6d687-b5b9-4b40-9413-0c2bd6d6644b	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
488	488	1	205.00	203.00	2.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	0dc36f51-4c23-4ff0-8aba-3902869499d9	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
489	489	1	347.00	328.00	19.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	12e81aeb-7db9-4cac-ad7c-6b7b3c222557	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
490	490	1	41.00	37.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	87d482c1-be62-4dfc-a216-01a93965f02d	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
491	491	1	364.00	357.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	9d2de548-2319-42c4-981e-603492df067d	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
492	492	1	375.00	368.00	7.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	b46b33ab-bd38-4e04-8dbb-78caa6193b6e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
493	493	1	65.00	65.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	85eec3ec-f8dd-45c0-9434-bf37ffb13b3e	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
494	494	1	179.00	175.00	4.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	ebd11ce5-4638-4b4c-a1ba-e18a6521878a	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
495	495	1	150.00	150.00	0.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	2a72d4ce-e98d-4c8c-a36a-54dbc89a3cf1	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
496	496	1	240.00	234.00	6.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	0a1be4c0-ab87-4468-ae76-6108fafe35f4	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
497	497	1	885.00	867.00	18.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	2b4236d1-18f7-4fda-aaf2-7074a6e8e06c	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
498	498	1	377.00	365.00	12.00	2026-09-01 10:00:00+03	النظام	\N	APPROVED	7304d7db-1ca0-40fb-aa75-33d53ea2216d	\N	f	f	2026-09-01 10:00:00+03	2026-09-16 22:12:12.696254+03
\.


--
-- Data for Name: payment_allocations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.payment_allocations (id, payment_id, invoice_id, amount_allocated, is_reversed, reversed_at, reversal_reason, created_at) FROM stdin;
1	1	400	13600.00	f	\N	\N	2026-09-10 00:28:43+03
2	2	389	9400.00	f	\N	\N	2026-09-10 00:23:21+03
3	3	372	9000.00	f	\N	\N	2026-09-10 00:21:24+03
4	4	195	1000.00	f	\N	\N	2026-09-09 23:56:20+03
5	5	128	6600.00	f	\N	\N	2026-09-09 22:08:56+03
6	6	152	4000.00	f	\N	\N	2026-09-09 22:06:27+03
7	7	334	30000.00	f	\N	\N	2026-09-09 22:04:34+03
8	8	177	20600.00	f	\N	\N	2026-09-09 22:03:33+03
9	9	327	45800.00	f	\N	\N	2026-09-09 20:09:35+03
10	10	399	15000.00	f	\N	\N	2026-09-08 21:06:59+03
11	11	323	38800.00	f	\N	\N	2026-09-08 21:03:58+03
12	12	207	28400.00	f	\N	\N	2026-09-08 21:03:04+03
13	13	39	9000.00	f	\N	\N	2026-09-08 21:01:04+03
14	14	153	14000.00	f	\N	\N	2026-09-08 20:53:52+03
15	15	135	76200.00	f	\N	\N	2026-09-08 20:52:47+03
16	16	390	13600.00	f	\N	\N	2026-09-08 20:51:38+03
17	17	419	9000.00	f	\N	\N	2026-09-08 18:22:09+03
18	18	82	7600.00	f	\N	\N	2026-09-08 00:17:55+03
19	19	491	10000.00	f	\N	\N	2026-09-08 00:14:06+03
20	20	206	9400.00	f	\N	\N	2026-09-08 00:12:53+03
21	21	38	12000.00	f	\N	\N	2026-09-07 23:57:53+03
22	22	96	2300.00	f	\N	\N	2026-09-07 23:53:43+03
23	23	31	2400.00	f	\N	\N	2026-09-07 23:47:39+03
24	24	35	21000.00	f	\N	\N	2026-09-07 23:39:06+03
25	25	14	9200.00	f	\N	\N	2026-09-07 23:36:43+03
26	26	29	22000.00	f	\N	\N	2026-09-07 23:34:57+03
27	27	24	17800.00	f	\N	\N	2026-09-07 23:31:50+03
28	28	21	47200.00	f	\N	\N	2026-09-07 23:30:25+03
29	29	16	13600.00	f	\N	\N	2026-09-07 23:29:29+03
30	30	12	30000.00	f	\N	\N	2026-09-07 23:19:51+03
31	31	7	27700.00	f	\N	\N	2026-09-07 23:17:44+03
32	32	136	21600.00	f	\N	\N	2026-09-07 23:08:39+03
33	33	137	51000.00	f	\N	\N	2026-09-07 23:07:16+03
34	34	84	14000.00	f	\N	\N	2026-09-07 22:00:22+03
35	35	34	3800.00	f	\N	\N	2026-09-07 20:56:15+03
37	37	88	7000.00	f	\N	\N	2026-09-04 15:22:35+03
38	38	302	5000.00	f	\N	\N	2026-09-04 16:58:55+03
39	39	380	22000.00	f	\N	\N	2026-09-04 17:12:27+03
40	40	270	3800.00	f	\N	\N	2026-09-04 17:31:14+03
41	41	179	45500.00	f	\N	\N	2026-09-04 17:39:30+03
42	42	27	17800.00	f	\N	\N	2026-09-04 17:48:47+03
43	43	286	50000.00	f	\N	\N	2026-09-04 17:50:48+03
44	44	442	1000.00	f	\N	\N	2026-09-04 18:12:38+03
45	45	464	10800.00	f	\N	\N	2026-09-04 18:21:26+03
46	46	487	10800.00	f	\N	\N	2026-09-04 18:24:20+03
47	47	488	9000.00	f	\N	\N	2026-09-04 18:25:27+03
48	48	157	5200.00	f	\N	\N	2026-09-04 18:27:22+03
49	49	26	16000.00	f	\N	\N	2026-09-04 18:56:15+03
50	50	375	9000.00	f	\N	\N	2026-09-04 19:00:02+03
51	51	53	6800.00	f	\N	\N	2026-09-04 19:03:19+03
52	52	429	6600.00	f	\N	\N	2026-09-04 19:12:24+03
53	53	486	50400.00	f	\N	\N	2026-09-04 19:13:36+03
54	54	23	1000.00	f	\N	\N	2026-09-04 19:14:21+03
55	55	51	20000.00	f	\N	\N	2026-09-04 19:16:18+03
56	56	63	1000.00	f	\N	\N	2026-09-04 19:17:06+03
57	57	104	29000.00	f	\N	\N	2026-09-04 19:17:47+03
58	58	117	7000.00	f	\N	\N	2026-09-04 19:18:21+03
59	59	146	20000.00	f	\N	\N	2026-09-04 19:18:54+03
60	60	219	1000.00	f	\N	\N	2026-09-04 19:20:51+03
61	61	237	9400.00	f	\N	\N	2026-09-04 19:21:37+03
62	62	399	13600.00	f	\N	\N	2026-09-04 19:23:32+03
63	63	51	15000.00	f	\N	\N	2026-09-05 02:33:41+03
64	64	51	600.00	f	\N	\N	2026-09-05 02:34:21+03
65	65	8	10800.00	f	\N	\N	2026-09-05 02:47:19+03
66	66	224	25000.00	f	\N	\N	2026-09-05 02:49:47+03
67	67	229	9000.00	f	\N	\N	2026-09-05 02:51:44+03
68	68	25	131200.00	f	\N	\N	2026-09-05 03:03:42+03
69	69	33	13000.00	f	\N	\N	2026-09-05 03:06:21+03
70	70	27	17800.00	f	\N	\N	2026-09-05 03:08:38+03
71	71	208	73800.00	f	\N	\N	2026-09-06 00:36:03+03
72	72	381	16400.00	f	\N	\N	2026-09-06 01:05:36+03
73	73	382	8000.00	f	\N	\N	2026-09-06 01:08:00+03
74	74	368	11000.00	f	\N	\N	2026-09-06 01:15:12+03
75	75	331	100000.00	f	\N	\N	2026-09-06 01:22:04+03
76	76	317	8000.00	f	\N	\N	2026-09-06 01:22:49+03
77	77	224	10.00	f	\N	\N	2026-09-06 01:54:23+03
78	78	208	10.00	f	\N	\N	2026-09-06 01:55:22+03
79	79	204	4800.00	f	\N	\N	2026-09-06 02:17:20+03
80	80	435	33200.00	f	\N	\N	2026-09-06 02:30:31+03
81	81	173	20000.00	f	\N	\N	2026-09-06 02:40:04+03
82	82	170	17800.00	f	\N	\N	2026-09-06 02:41:13+03
\.


--
-- Data for Name: payment_receipt_counters; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.payment_receipt_counters (year, last_value) FROM stdin;
2026	63
\.


--
-- Data for Name: payments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.payments (id, receipt_number, customer_id, invoice_id, shift_id, payment_method, amount_paid, payment_date, accountant_name, accountant_user_id, approval_status, notes, client_mutation_id, rejection_reason, whatsapp_sent, created_at, updated_at) FROM stdin;
1	REC-2026-000047	400	400	\N	CASH	13600.00	2026-09-10 00:28:43+03	مدير النظام	\N	APPROVED	\N	35475974-4da1-47cf-8575-d3448ce9fed5	\N	f	2026-09-10 00:28:43+03	2026-09-10 00:28:43+03
2	REC-2026-000046	389	389	\N	CASH	9400.00	2026-09-10 00:23:21+03	مدير النظام	\N	APPROVED	\N	76df7ed0-7353-44e5-9823-d4725bb0da98	\N	f	2026-09-10 00:23:21+03	2026-09-10 00:23:21+03
3	REC-2026-000045	372	372	\N	CASH	9000.00	2026-09-10 00:21:24+03	مدير النظام	\N	APPROVED	\N	2407aa50-1b1f-47d2-88c9-52b05fa8107a	\N	f	2026-09-10 00:21:24+03	2026-09-10 00:21:24+03
4	REC-2026-000044	195	195	\N	CASH	1000.00	2026-09-09 23:56:20+03	مدير النظام	\N	APPROVED	\N	1939b3fe-0693-478e-9951-6e81f277cda8	\N	f	2026-09-09 23:56:20+03	2026-09-09 23:56:20+03
5	REC-2026-000043	128	128	\N	CASH	6600.00	2026-09-09 22:08:56+03	مدير النظام	\N	APPROVED	\N	8e911766-9407-44bf-93d6-2f33c56332d3	\N	f	2026-09-09 22:08:56+03	2026-09-09 22:08:56+03
6	REC-2026-000042	152	152	\N	CASH	4000.00	2026-09-09 22:06:27+03	مدير النظام	\N	APPROVED	\N	8aa56c62-2d43-4d13-b935-7b650a597634	\N	f	2026-09-09 22:06:27+03	2026-09-09 22:06:27+03
7	REC-2026-000041	334	334	\N	CASH	30000.00	2026-09-09 22:04:34+03	مدير النظام	\N	APPROVED	\N	b87a14ed-846d-4559-8468-c87ca05c3970	\N	f	2026-09-09 22:04:34+03	2026-09-09 22:04:34+03
8	REC-2026-000040	177	177	\N	CASH	20600.00	2026-09-09 22:03:33+03	مدير النظام	\N	APPROVED	\N	31a9ff42-6192-4dd1-af7d-ab126b7aec7e	\N	f	2026-09-09 22:03:33+03	2026-09-09 22:03:33+03
9	REC-2026-000039	327	327	\N	CASH	45800.00	2026-09-09 20:09:35+03	مدير النظام	\N	APPROVED	\N	f5bb4931-0437-4587-9b2e-b46ee6f37688	\N	f	2026-09-09 20:09:35+03	2026-09-09 20:09:35+03
10	REC-2026-000038	399	399	\N	CASH	15000.00	2026-09-08 21:06:59+03	مدير النظام	\N	APPROVED	\N	5b8d1720-defa-4018-9c89-1601301b8f41	\N	f	2026-09-08 21:06:59+03	2026-09-08 21:06:59+03
11	REC-2026-000037	323	323	\N	CASH	38800.00	2026-09-08 21:03:58+03	مدير النظام	\N	APPROVED	\N	5fb9eddd-d23c-4434-b7cf-d006014ce300	\N	f	2026-09-08 21:03:58+03	2026-09-08 21:03:58+03
12	REC-2026-000036	207	207	\N	CASH	28400.00	2026-09-08 21:03:04+03	مدير النظام	\N	APPROVED	\N	e601f8ac-f6eb-4779-9107-12d5933f04f1	\N	f	2026-09-08 21:03:04+03	2026-09-08 21:03:04+03
13	REC-2026-000035	39	39	\N	CASH	9000.00	2026-09-08 21:01:04+03	مدير النظام	\N	APPROVED	\N	ffb6e554-ee55-4af3-bd86-0fedefc1d14c	\N	f	2026-09-08 21:01:04+03	2026-09-08 21:01:04+03
14	REC-2026-000034	153	153	\N	CASH	14000.00	2026-09-08 20:53:52+03	مدير النظام	\N	APPROVED	\N	579e5ec8-da2e-45f0-9bc7-226e34c6d850	\N	f	2026-09-08 20:53:52+03	2026-09-08 20:53:52+03
15	REC-2026-000033	135	135	\N	CASH	76200.00	2026-09-08 20:52:47+03	مدير النظام	\N	APPROVED	\N	3a8ad417-747b-4230-b2ac-d20ea911daaa	\N	f	2026-09-08 20:52:47+03	2026-09-08 20:52:47+03
16	REC-2026-000032	390	390	\N	CASH	13600.00	2026-09-08 20:51:38+03	مدير النظام	\N	APPROVED	\N	73a748f8-5e35-4b12-bcfc-7b108b65d24e	\N	f	2026-09-08 20:51:38+03	2026-09-08 20:51:38+03
17	REC-2026-000031	419	419	\N	CASH	9000.00	2026-09-08 18:22:09+03	مدير النظام	\N	APPROVED	\N	35ac6246-dfc1-4158-9a7b-63e4c60a9ccc	\N	f	2026-09-08 18:22:09+03	2026-09-08 18:22:09+03
18	REC-2026-000030	82	82	\N	CASH	7600.00	2026-09-08 00:17:55+03	مدير النظام	\N	APPROVED	\N	6d5dd781-0160-47ba-b254-d238cc9ff0bf	\N	f	2026-09-08 00:17:55+03	2026-09-08 00:17:55+03
19	REC-2026-000029	491	491	\N	CASH	10000.00	2026-09-08 00:14:06+03	مدير النظام	\N	APPROVED	\N	8610e9fd-eda5-464a-a733-2905b16285e4	\N	f	2026-09-08 00:14:06+03	2026-09-08 00:14:06+03
20	REC-2026-000028	206	206	\N	CASH	9400.00	2026-09-08 00:12:53+03	مدير النظام	\N	APPROVED	\N	8937078b-f749-4eed-a82d-2e2dd5ed2aee	\N	f	2026-09-08 00:12:53+03	2026-09-08 00:12:53+03
21	REC-2026-000027	38	38	\N	CASH	12000.00	2026-09-07 23:57:53+03	مدير النظام	\N	APPROVED	\N	a5289723-f442-4176-91e1-7655765ab8a1	\N	f	2026-09-07 23:57:53+03	2026-09-07 23:57:53+03
22	REC-2026-000026	96	96	\N	CASH	2300.00	2026-09-07 23:53:43+03	مدير النظام	\N	APPROVED	\N	75bc525e-17d7-4472-bf24-6b083369afe0	\N	f	2026-09-07 23:53:43+03	2026-09-07 23:53:43+03
23	REC-2026-000025	31	31	\N	CASH	2400.00	2026-09-07 23:47:39+03	مدير النظام	\N	APPROVED	\N	ca31ef66-04ae-4a8a-a70c-a1e4ed899fcc	\N	f	2026-09-07 23:47:39+03	2026-09-07 23:47:39+03
24	REC-2026-000024	35	35	\N	CASH	21000.00	2026-09-07 23:39:06+03	مدير النظام	\N	APPROVED	\N	a034dd24-b429-4d6f-a46f-5a2581df009f	\N	f	2026-09-07 23:39:06+03	2026-09-07 23:39:06+03
25	REC-2026-000023	14	14	\N	CASH	9200.00	2026-09-07 23:36:43+03	مدير النظام	\N	APPROVED	\N	31de0f57-2ce3-4c73-8015-07ed88a27b81	\N	f	2026-09-07 23:36:43+03	2026-09-07 23:36:43+03
26	REC-2026-000022	29	29	\N	CASH	22000.00	2026-09-07 23:34:57+03	مدير النظام	\N	APPROVED	\N	bd97ebae-021d-4be4-a397-66a1f1648887	\N	f	2026-09-07 23:34:57+03	2026-09-07 23:34:57+03
27	REC-2026-000021	24	24	\N	CASH	17800.00	2026-09-07 23:31:50+03	مدير النظام	\N	APPROVED	\N	3e56e85a-6041-4be0-b568-65cf04fea566	\N	f	2026-09-07 23:31:50+03	2026-09-07 23:31:50+03
28	REC-2026-000020	21	21	\N	CASH	47200.00	2026-09-07 23:30:25+03	مدير النظام	\N	APPROVED	\N	1d368ee8-261d-49e1-8d31-7a749ab0252d	\N	f	2026-09-07 23:30:25+03	2026-09-07 23:30:25+03
29	REC-2026-000019	16	16	\N	CASH	13600.00	2026-09-07 23:29:29+03	مدير النظام	\N	APPROVED	\N	07e3bba4-2a21-44ef-a6fa-6c3ec06876b6	\N	f	2026-09-07 23:29:29+03	2026-09-07 23:29:29+03
30	REC-2026-000018	12	12	\N	CASH	30000.00	2026-09-07 23:19:51+03	مدير النظام	\N	APPROVED	\N	b55de91a-4104-4e58-b820-f9e29eb3aa31	\N	f	2026-09-07 23:19:51+03	2026-09-07 23:19:51+03
31	REC-2026-000017	7	7	\N	CASH	27700.00	2026-09-07 23:17:44+03	مدير النظام	\N	APPROVED	\N	428f01ca-5348-419f-b5c7-27ddde689b7f	\N	f	2026-09-07 23:17:44+03	2026-09-07 23:17:44+03
32	REC-2026-000016	136	136	\N	CASH	21600.00	2026-09-07 23:08:39+03	مدير النظام	\N	APPROVED	\N	6f7d32eb-8edc-4bf5-a24c-c88b804f1a43	\N	f	2026-09-07 23:08:39+03	2026-09-07 23:08:39+03
33	REC-2026-000015	137	137	\N	CASH	51000.00	2026-09-07 23:07:16+03	مدير النظام	\N	APPROVED	\N	40ed4b4f-3b4b-458b-93b2-93e9937d0dac	\N	f	2026-09-07 23:07:16+03	2026-09-07 23:07:16+03
34	REC-2026-000014	84	84	\N	CASH	14000.00	2026-09-07 22:00:22+03	مدير النظام	\N	APPROVED	\N	b8bc2284-fbcd-43d2-9646-0d3b72b68bb0	\N	f	2026-09-07 22:00:22+03	2026-09-07 22:00:22+03
35	REC-2026-000013	34	34	\N	CASH	3800.00	2026-09-07 20:56:15+03	مدير النظام	\N	APPROVED	\N	f471d974-c56a-4fb2-9c3d-466c620603bd	\N	f	2026-09-07 20:56:15+03	2026-09-07 20:56:15+03
37	REC-2026-0018	88	88	\N	CASH	7000.00	2026-09-04 15:22:35+03	مدير المحطة	\N	APPROVED	\N	8c336c20-1cef-4f8b-ad94-6386a8d17dbf	\N	f	2026-09-04 15:22:35+03	2026-09-04 15:22:35+03
38	REC-2026-0019	302	302	\N	CASH	5000.00	2026-09-04 16:58:55+03	مدير المحطة	\N	APPROVED	\N	aacd7a0b-17b0-431d-a4d2-865d6d935ca2	\N	f	2026-09-04 16:58:55+03	2026-09-04 16:58:55+03
39	REC-2026-0020	380	380	\N	CASH	22000.00	2026-09-04 17:12:27+03	مدير المحطة	\N	APPROVED	\N	3a37659e-976a-4b46-8b65-2183177c53cd	\N	f	2026-09-04 17:12:27+03	2026-09-04 17:12:27+03
40	REC-2026-0021	270	270	\N	CASH	3800.00	2026-09-04 17:31:14+03	مدير المحطة	\N	APPROVED	\N	0e3c5df0-49a7-4f5d-8a0e-b4ae30fe07f5	\N	f	2026-09-04 17:31:14+03	2026-09-04 17:31:14+03
41	REC-2026-0022	179	179	\N	CASH	45500.00	2026-09-04 17:39:30+03	مدير المحطة	\N	APPROVED	\N	2ca34929-8fa6-4f08-8477-1fd163019fdd	\N	f	2026-09-04 17:39:30+03	2026-09-04 17:39:30+03
42	REC-2026-0023	27	27	\N	CASH	17800.00	2026-09-04 17:48:47+03	مدير المحطة	\N	APPROVED	\N	a6ea6a1c-2410-4811-8b2b-62b7ed0689e5	\N	f	2026-09-04 17:48:47+03	2026-09-04 17:48:47+03
43	REC-2026-0024	286	286	\N	CASH	50000.00	2026-09-04 17:50:48+03	مدير المحطة	\N	APPROVED	\N	e6d4310d-f890-436f-92d1-141e443d9527	\N	f	2026-09-04 17:50:48+03	2026-09-04 17:50:48+03
44	REC-2026-0025	442	442	\N	CASH	1000.00	2026-09-04 18:12:38+03	مدير المحطة	\N	APPROVED	\N	c06b9349-4cf4-4249-bd31-78ee4df56ead	\N	f	2026-09-04 18:12:38+03	2026-09-04 18:12:38+03
45	REC-2026-0026	464	464	\N	CASH	10800.00	2026-09-04 18:21:26+03	مدير المحطة	\N	APPROVED	\N	a08f941e-bc31-4769-b39d-84ce4b1b810b	\N	f	2026-09-04 18:21:26+03	2026-09-04 18:21:26+03
46	REC-2026-0027	487	487	\N	CASH	10800.00	2026-09-04 18:24:20+03	مدير المحطة	\N	APPROVED	\N	b941f37e-fc09-4540-bbc8-5eeb43d38179	\N	f	2026-09-04 18:24:20+03	2026-09-04 18:24:20+03
47	REC-2026-0028	488	488	\N	CASH	9000.00	2026-09-04 18:25:27+03	مدير المحطة	\N	APPROVED	\N	498d366c-a642-4815-9ddf-1f49fbc159ca	\N	f	2026-09-04 18:25:27+03	2026-09-04 18:25:27+03
48	REC-2026-0029	157	157	\N	CASH	5200.00	2026-09-04 18:27:22+03	مدير المحطة	\N	APPROVED	\N	db80e544-131b-4a33-a952-26aa0978796e	\N	f	2026-09-04 18:27:22+03	2026-09-04 18:27:22+03
49	REC-2026-0030	26	26	\N	CASH	16000.00	2026-09-04 18:56:15+03	مدير المحطة	\N	APPROVED	\N	0d555dfc-f1fb-4faa-8680-fce815ca3c32	\N	f	2026-09-04 18:56:15+03	2026-09-04 18:56:15+03
50	REC-2026-0031	375	375	\N	CASH	9000.00	2026-09-04 19:00:02+03	مدير المحطة	\N	APPROVED	\N	755f6a1a-c13e-444f-af03-5a97bdc2c649	\N	f	2026-09-04 19:00:02+03	2026-09-04 19:00:02+03
51	REC-2026-0032	53	53	\N	CASH	6800.00	2026-09-04 19:03:19+03	مدير المحطة	\N	APPROVED	\N	fcb2018f-4c80-40d6-937a-68e2db4e8881	\N	f	2026-09-04 19:03:19+03	2026-09-04 19:03:19+03
52	REC-2026-0033	429	429	\N	CASH	6600.00	2026-09-04 19:12:24+03	مدير المحطة	\N	APPROVED	\N	a00fda5f-9008-4008-922f-626326b0b702	\N	f	2026-09-04 19:12:24+03	2026-09-04 19:12:24+03
53	REC-2026-0034	486	486	\N	CASH	50400.00	2026-09-04 19:13:36+03	مدير المحطة	\N	APPROVED	\N	1a0527f6-fb4c-424c-b9aa-82fc8ea21934	\N	f	2026-09-04 19:13:36+03	2026-09-04 19:13:36+03
54	REC-2026-0035	23	23	\N	CASH	1000.00	2026-09-04 19:14:21+03	مدير المحطة	\N	APPROVED	\N	ffdddfc7-88b7-4d5c-aee6-3e217c7b7acc	\N	f	2026-09-04 19:14:21+03	2026-09-04 19:14:21+03
55	REC-2026-0036	51	51	\N	CASH	20000.00	2026-09-04 19:16:18+03	مدير المحطة	\N	APPROVED	\N	6bb618cb-ad4f-471b-9191-16a25db36ff5	\N	f	2026-09-04 19:16:18+03	2026-09-04 19:16:18+03
56	REC-2026-0037	63	63	\N	CASH	1000.00	2026-09-04 19:17:06+03	مدير المحطة	\N	APPROVED	\N	af757e19-2007-4faa-8c8a-3803f2b6b6be	\N	f	2026-09-04 19:17:06+03	2026-09-04 19:17:06+03
57	REC-2026-0038	104	104	\N	CASH	29000.00	2026-09-04 19:17:47+03	مدير المحطة	\N	APPROVED	\N	94cb3973-76bd-47d0-85b3-0e6ff711fa18	\N	f	2026-09-04 19:17:47+03	2026-09-04 19:17:47+03
58	REC-2026-0039	117	117	\N	CASH	7000.00	2026-09-04 19:18:21+03	مدير المحطة	\N	APPROVED	\N	56f359eb-0694-4113-9313-37b6a598aed5	\N	f	2026-09-04 19:18:21+03	2026-09-04 19:18:21+03
59	REC-2026-0040	146	146	\N	CASH	20000.00	2026-09-04 19:18:54+03	مدير المحطة	\N	APPROVED	\N	4c94b08d-38b4-406a-890a-1b492eba1a37	\N	f	2026-09-04 19:18:54+03	2026-09-04 19:18:54+03
60	REC-2026-0041	219	219	\N	CASH	1000.00	2026-09-04 19:20:51+03	مدير المحطة	\N	APPROVED	\N	23480f5e-b7cc-4584-85af-48c016b2abe5	\N	f	2026-09-04 19:20:51+03	2026-09-04 19:20:51+03
61	REC-2026-0042	237	237	\N	CASH	9400.00	2026-09-04 19:21:37+03	مدير المحطة	\N	APPROVED	\N	ede0f573-25f2-4e88-ab25-280371f8cbf7	\N	f	2026-09-04 19:21:37+03	2026-09-04 19:21:37+03
62	REC-2026-0043	399	399	\N	CASH	13600.00	2026-09-04 19:23:32+03	مدير المحطة	\N	APPROVED	\N	b32e743b-e6af-44a3-8a45-e30caabf7d2a	\N	f	2026-09-04 19:23:32+03	2026-09-04 19:23:32+03
63	REC-2026-0044	51	51	\N	CASH	15000.00	2026-09-05 02:33:41+03	مدير المحطة	\N	APPROVED	\N	465e4938-446c-4c9b-80d9-5fb4ea147771	\N	f	2026-09-05 02:33:41+03	2026-09-05 02:33:41+03
64	REC-2026-0045	51	51	\N	CASH	600.00	2026-09-05 02:34:21+03	مدير المحطة	\N	APPROVED	\N	59ebabb4-b906-4db7-8200-44185fd09b84	\N	f	2026-09-05 02:34:21+03	2026-09-05 02:34:21+03
65	REC-2026-0046	8	8	\N	CASH	10800.00	2026-09-05 02:47:19+03	مدير المحطة	\N	APPROVED	\N	e7dc5d31-2556-42ff-91dd-fc9d882bfd75	\N	f	2026-09-05 02:47:19+03	2026-09-05 02:47:19+03
66	REC-2026-0047	224	224	\N	CASH	25000.00	2026-09-05 02:49:47+03	مدير المحطة	\N	APPROVED	\N	8d56787a-fbd1-4a83-bfa2-3192f2e2fd74	\N	f	2026-09-05 02:49:47+03	2026-09-05 02:49:47+03
67	REC-2026-0048	229	229	\N	CASH	9000.00	2026-09-05 02:51:44+03	مدير المحطة	\N	APPROVED	\N	e5c91b32-1025-4364-86e0-55445b7758e7	\N	f	2026-09-05 02:51:44+03	2026-09-05 02:51:44+03
68	REC-2026-0049	25	25	\N	CASH	131200.00	2026-09-05 03:03:42+03	مدير المحطة	\N	APPROVED	\N	8ce82e13-60f7-407d-816c-a2f2233f8688	\N	f	2026-09-05 03:03:42+03	2026-09-05 03:03:42+03
69	REC-2026-0050	33	33	\N	CASH	13000.00	2026-09-05 03:06:21+03	مدير المحطة	\N	APPROVED	\N	ec8a5445-322d-45cc-a756-ca4fad6fb4e3	\N	f	2026-09-05 03:06:21+03	2026-09-05 03:06:21+03
70	REC-2026-0051	27	27	\N	CASH	17800.00	2026-09-05 03:08:38+03	مدير المحطة	\N	APPROVED	\N	837d6d21-5069-4f51-a232-2f80f0635977	\N	f	2026-09-05 03:08:38+03	2026-09-05 03:08:38+03
71	REC-2026-0052	208	208	\N	CASH	73800.00	2026-09-06 00:36:03+03	مدير المحطة	\N	APPROVED	\N	da83e010-c882-448a-bd3b-152b697a848d	\N	f	2026-09-06 00:36:03+03	2026-09-06 00:36:03+03
72	REC-2026-0053	381	381	\N	CASH	16400.00	2026-09-06 01:05:36+03	مدير المحطة	\N	APPROVED	\N	9c4ee6fd-36fe-446f-a52a-1af1e40aca5b	\N	f	2026-09-06 01:05:36+03	2026-09-06 01:05:36+03
73	REC-2026-0054	382	382	\N	CASH	8000.00	2026-09-06 01:08:00+03	مدير المحطة	\N	APPROVED	\N	a92a4ddd-10d7-413e-8aff-689fd6d32dde	\N	f	2026-09-06 01:08:00+03	2026-09-06 01:08:00+03
74	REC-2026-0055	368	368	\N	CASH	11000.00	2026-09-06 01:15:12+03	مدير المحطة	\N	APPROVED	\N	52a3c037-df79-48a2-a531-bff339bab8ee	\N	f	2026-09-06 01:15:12+03	2026-09-06 01:15:12+03
75	REC-2026-0056	331	331	\N	CASH	100000.00	2026-09-06 01:22:04+03	مدير المحطة	\N	APPROVED	\N	da702b7e-14af-4601-ab55-4fc72e38057e	\N	f	2026-09-06 01:22:04+03	2026-09-06 01:22:04+03
76	REC-2026-0057	317	317	\N	CASH	8000.00	2026-09-06 01:22:49+03	مدير المحطة	\N	APPROVED	\N	5692bacd-9ed1-4804-8c20-8c44330810ba	\N	f	2026-09-06 01:22:49+03	2026-09-06 01:22:49+03
77	REC-2026-0058	224	224	\N	CASH	10.00	2026-09-06 01:54:23+03	مدير المحطة	\N	APPROVED	\N	bc9e4d5e-06a5-452a-89c9-4dd0380998e4	\N	f	2026-09-06 01:54:23+03	2026-09-06 01:54:23+03
78	REC-2026-0059	208	208	\N	CASH	10.00	2026-09-06 01:55:22+03	مدير المحطة	\N	APPROVED	\N	e3961e89-6aa2-4489-b484-d69dcfaf8de5	\N	f	2026-09-06 01:55:22+03	2026-09-06 01:55:22+03
79	REC-2026-0060	204	204	\N	CASH	4800.00	2026-09-06 02:17:20+03	مدير المحطة	\N	APPROVED	\N	4fc1350b-6b15-4f42-a081-8b4f0ffe44bc	\N	f	2026-09-06 02:17:20+03	2026-09-06 02:17:20+03
80	REC-2026-0061	435	435	\N	CASH	33200.00	2026-09-06 02:30:31+03	مدير المحطة	\N	APPROVED	\N	9e7613ed-5d3b-4e1f-8cb0-8cf7bf1ed9cd	\N	f	2026-09-06 02:30:31+03	2026-09-06 02:30:31+03
81	REC-2026-0062	173	173	\N	CASH	20000.00	2026-09-06 02:40:04+03	مدير المحطة	\N	APPROVED	\N	51a56180-1a9c-4bb2-ab96-0f7c1955ac2d	\N	f	2026-09-06 02:40:04+03	2026-09-06 02:40:04+03
82	REC-2026-0063	170	170	\N	CASH	17800.00	2026-09-06 02:41:13+03	مدير المحطة	\N	APPROVED	\N	d7cff51a-9c4a-4506-b03c-169b7a1f70e3	\N	f	2026-09-06 02:41:13+03	2026-09-06 02:41:13+03
\.


--
-- Data for Name: shifts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.shifts (id, user_id, cashier_name, start_time, end_time, starting_cash, ending_cash, total_collected, status, created_at) FROM stdin;
\.


--
-- Data for Name: subscription_plans; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.subscription_plans (id, plan_name, kwh_price, fixed_fee, grace_period_days, description, is_active, created_at, updated_at) FROM stdin;
3	باقة خاصة 1000	1000.00	0.00	10	باقة استهلاك مخفض	t	2026-09-09 16:32:52.240752+03	2026-09-09 16:32:52.240752+03
4	باقة خاصة 2000	2000.00	1000.00	10	باقة تجارية 2000	t	2026-09-09 16:32:52.240752+03	2026-09-09 16:32:52.240752+03
5	باقة خاصة 2800	2800.00	1000.00	10	باقة تجارية 2800	t	2026-09-09 16:32:52.240752+03	2026-09-09 16:32:52.240752+03
1	باقة تجارية	1400.00	1000.00	10	\N	t	2026-09-06 12:44:31.723041+03	2026-09-06 12:44:31.723041+03
2	الاشتراك الصناعي عالي الجهد	1200.00	500.00	5	\N	t	2026-09-06 12:44:31.723041+03	2026-09-06 12:44:31.723041+03
\.


--
-- Data for Name: sync_checkpoints; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.sync_checkpoints (table_name, last_synced_id, last_synced_at) FROM stdin;
\.


--
-- Data for Name: sync_outbox; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.sync_outbox (id, table_name, record_id, operation, payload, status, attempts, last_error, created_at, synced_at) FROM stdin;
\.


--
-- Data for Name: system_settings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.system_settings (id, station_name, station_logo_url, station_phone, station_phone_alt, bank_accounts, invoice_policy_text, whatsapp_status, receipt_footer, arrears_threshold, default_kwh_price, default_fixed_fee, max_overdue_days, currency, created_at, updated_at) FROM stdin;
1	محطة الضياء لتوليد الطاقة الكهربائية	\N	+967 783270260	+967 736955883	بنك الكريمي: 3052001225	1- نرجو تسديد الفاتورة خلال فترة السماح المحددة تفادياً لفصل التيار.\n2- في حال وجود أي اعتراض على القراءة يرجى مراجعة إدارة المحطة خلال 48 ساعة.\n3- إعادة التيار بعد الفصل تتطلب سداد الرسوم المقررة.\n4- المشترك مسؤول عن سلامة العداد والوصلات التابعة له.\n5- استخدام الطاقة في غير الغرض المخصص يعرض المشترك للمساءلة.	Disconnected	شكراً لاختياركم خدماتنا - نرجو المحافظة على الطاقة	0.00	1000.00	1000.00	7	YER	2026-09-06 12:44:31.704319+03	2026-09-06 12:44:31.704319+03
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, username, password_hash, full_name, role, phone_number, is_active, supabase_uid, created_at, updated_at) FROM stdin;
1	admin	$2a$10$qTS36FZ/kK4Isy.OZTYgMuROb3XMvLds/97lo9VtAuxmU77E7KZ6m	مدير النظام	ADMIN	+967 783270260	t	\N	2026-09-06 12:44:31.690358+03	2026-09-06 12:44:31.690358+03
\.


--
-- Data for Name: whatsapp_queue_messages; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.whatsapp_queue_messages (id, phone_number, type, message, image_base64, caption, media_path, status, retries, max_retries, error_msg, source_entity, source_id, client_mutation_id, scheduled_at, processing_started_at, sent_at, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: whatsapp_sessions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.whatsapp_sessions (session_id, jid, status, qr_code, push_name, auth_data, device_props, keys_data, is_active, last_connected_at, last_heartbeat_at, created_at, updated_at) FROM stdin;
default	\N	SCAN_QR_CODE	data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAQAAAAEAAQMAAABmvDolAAAABlBMVEX///8AAABVwtN+AAAE60lEQVR42uyZMa6uOBaEy3LgDG8A4W0QILElQjI7I2RLlgjYBujfgMkcWK7R4e/bejPp4xFMtxN00SdddGyfqjo//l3/rKXIipEsvraGZ4ElQx3DdYxkfAaIaHSeVDHqwNSNC4tJagup7aHeAjY2GMMB8BOnbjDASGCube/PBwFDtWX72dduDI2OqACPl4FxVSQwBpJVU7jUPgdENC08me0xrofOV+knFjT4ZS/+NEDWtp/ObWn+5/HLmfw94LtsHWZbehx6UZ9ouRHtf12fPwqoOMuVOjBXvZOk5b6eG5Pew1MAqe57OleXAXhVYFX0gFnrSwDgG5h0FlwHLLdQXfbH4Hn09iFAWoGLk5NywHcjr0+0jrTFhOMlANKVel8Hk9resnjL7F30PMZ0xkcAtWW4fa0jLZk6vVyHCccwJ/QWeAfAgKrzVHVObk8Vc3IMjovivjI+AqgtKEZ/lhmA7wZUiPD4RscJeAmQHtWj04Qm1Ub7yV5tWR29P54C5usYQx3ZQM7QLP/cbUEV4C0A4y0H8nB7ALz65KnT4Sq9ZXwGAK4DXsVZtBujnKj1GLMi2eEdQEXYD8MtpfB1XGwZV7UROk9nfASA3JFxBTy+MnYdhioiwST1FqBz05r15CKd8YyyF57kVTBVPAOMIek9nWXmh3QFyUWoYmqLv+rwAjCYqqPcpYtc3Ua5ym5j437Ow28Dilkx+0MvDTBVvaTWpDMadYzra0CBLb1VG6vbbyvq9iDeV1Z8BACM9HdXfNMC3eDh8sToVTFBvQSoLbDAnlxU6XGSlD7JnBzTgUcADB7tGFw0PODPODduZ3dXfMVrgCEZKubr6C0ZRF9d9HDkGR8C7uJ2WnKDPXTm7R/m1EpvfAdQ8d5naNFXnBsvMlA2v5/OZwDAw+0kl+uTcYjUYPqedu/eAuQSZX9uAcBEhuT2VW33kevwDKBz0tkeMPIprni0vVURtR0D41sAG5c9YOwnWsBcJF30qR0D8AigyNQC9waLsPIqJrDMqf0x3i8A0Vepw+Ab3P7BfiLUxuQyXHwGuDc4SdhlthgAmLUbfNL7CrwD3IE/WsUgd6mDF0fqynx99vAQoBjUJ3qRcABn9LbIyyU5rmd8BwAMyXRuZOmnW9X3lcXIBMk9A6gISUlSBx19p6k+JAZUly3wDgAtOgeK+Mk5NlcZw8ml0TufAoYZrQn1a6jVtgAmAEaV7/e9AoxLdWIXfIMe3WBupy/e8OcjHwAyfkZ/TBgzJfOOiz3gGd8BxKOJv+VSYYIYb97607S9Vw8B0QCwHZDEm4zLVUw6BsDln7T4xwGM2R6GZ/QX90TZbkznRjj+FWF+Hxi8SGk3LqoYVr1AZ9vBp5/p4guAOFLm6SQbnW2Fl1zq4szDJOARAEDSMgWb4TLOLUvCl4r/PWZ5Abj9H2R87LJVZNV7OgbTyF/PACrOcGQd8A2DUvjU6XvY8BYgcl7MKq8ASy6Wu1yw5u988fsAgHZcK2bJ3Yd0+z10mH9xpH8c+FafVd/jIRmW611ymyr9VPEMcE/+p1MCwz0Sv4TjIo3reAvY2KCfHLMtYyKp5FHuGPUg4PIk8aiYxC1/h6iA2wPje4BU/xZ3YgwyvsIwX5/o1UNAhAAnF364VphGc1XRyCCjw0sAef/soBfLaM9o7uxfUB2fAv5d/z/rPwMAKq14z5X1UUoAAAAASUVORK5CYII=	\N	\N	\N	\N	f	\N	\N	2026-09-13 16:52:50.032291+03	2026-09-17 17:48:41.489997+03
\.


--
-- Data for Name: whatsmeow_app_state_mutation_macs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.whatsmeow_app_state_mutation_macs (jid, name, version, index_mac, value_mac) FROM stdin;
\.


--
-- Data for Name: whatsmeow_app_state_sync_keys; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.whatsmeow_app_state_sync_keys (jid, key_id, key_data, "timestamp", fingerprint) FROM stdin;
\.


--
-- Data for Name: whatsmeow_app_state_version; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.whatsmeow_app_state_version (jid, name, version, hash) FROM stdin;
\.


--
-- Data for Name: whatsmeow_chat_settings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.whatsmeow_chat_settings (our_jid, chat_jid, muted_until, pinned, archived) FROM stdin;
\.


--
-- Data for Name: whatsmeow_contacts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.whatsmeow_contacts (our_jid, their_jid, first_name, full_name, push_name, business_name, redacted_phone) FROM stdin;
\.


--
-- Data for Name: whatsmeow_device; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.whatsmeow_device (jid, lid, facebook_uuid, registration_id, noise_key, identity_key, signed_pre_key, signed_pre_key_id, signed_pre_key_sig, adv_key, adv_details, adv_account_sig, adv_account_sig_key, adv_device_sig, platform, business_name, push_name, lid_migration_ts, companion_meta_nonce) FROM stdin;
\.


--
-- Data for Name: whatsmeow_event_buffer; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.whatsmeow_event_buffer (our_jid, ciphertext_hash, plaintext, server_timestamp, insert_timestamp) FROM stdin;
\.


--
-- Data for Name: whatsmeow_identity_keys; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.whatsmeow_identity_keys (our_jid, their_id, identity) FROM stdin;
\.


--
-- Data for Name: whatsmeow_lid_map; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.whatsmeow_lid_map (lid, pn) FROM stdin;
\.


--
-- Data for Name: whatsmeow_message_secrets; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.whatsmeow_message_secrets (our_jid, chat_jid, sender_jid, message_id, key) FROM stdin;
\.


--
-- Data for Name: whatsmeow_nct_salt; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.whatsmeow_nct_salt (our_jid, salt) FROM stdin;
\.


--
-- Data for Name: whatsmeow_pre_keys; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.whatsmeow_pre_keys (jid, key_id, key, uploaded) FROM stdin;
\.


--
-- Data for Name: whatsmeow_privacy_tokens; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.whatsmeow_privacy_tokens (our_jid, their_jid, token, "timestamp", sender_timestamp) FROM stdin;
\.


--
-- Data for Name: whatsmeow_retry_buffer; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.whatsmeow_retry_buffer (our_jid, chat_jid, message_id, format, plaintext, "timestamp") FROM stdin;
\.


--
-- Data for Name: whatsmeow_sender_keys; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.whatsmeow_sender_keys (our_jid, chat_id, sender_id, sender_key) FROM stdin;
\.


--
-- Data for Name: whatsmeow_sessions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.whatsmeow_sessions (our_jid, their_id, session) FROM stdin;
\.


--
-- Data for Name: whatsmeow_version; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.whatsmeow_version (version, compat) FROM stdin;
\.


--
-- Name: audit_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.audit_logs_id_seq', 109, true);


--
-- Name: billing_cycles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.billing_cycles_id_seq', 6, true);


--
-- Name: collector_customer_assignments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.collector_customer_assignments_id_seq', 1, false);


--
-- Name: customer_credits_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.customer_credits_id_seq', 2, true);


--
-- Name: customers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.customers_id_seq', 515, true);


--
-- Name: invoices_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.invoices_id_seq', 1085, true);


--
-- Name: meter_readings_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.meter_readings_id_seq', 574, true);


--
-- Name: payment_allocations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.payment_allocations_id_seq', 106, true);


--
-- Name: payments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.payments_id_seq', 125, true);


--
-- Name: shifts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.shifts_id_seq', 1, false);


--
-- Name: subscription_plans_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.subscription_plans_id_seq', 21, true);


--
-- Name: sync_outbox_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.sync_outbox_id_seq', 1, false);


--
-- Name: system_settings_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.system_settings_id_seq', 1, true);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_id_seq', 1, true);


--
-- Name: whatsapp_queue_messages_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.whatsapp_queue_messages_id_seq', 1, false);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: billing_cycles billing_cycles_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.billing_cycles
    ADD CONSTRAINT billing_cycles_code_key UNIQUE (code);


--
-- Name: billing_cycles billing_cycles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.billing_cycles
    ADD CONSTRAINT billing_cycles_pkey PRIMARY KEY (id);


--
-- Name: collector_customer_assignments collector_customer_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.collector_customer_assignments
    ADD CONSTRAINT collector_customer_assignments_pkey PRIMARY KEY (id);


--
-- Name: customer_credits customer_credits_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_pkey PRIMARY KEY (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: customers customers_subscriber_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_subscriber_number_key UNIQUE (subscriber_number);


--
-- Name: invoices invoices_invoice_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_invoice_number_key UNIQUE (invoice_number);


--
-- Name: invoices invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_pkey PRIMARY KEY (id);


--
-- Name: meter_readings meter_readings_client_mutation_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_client_mutation_id_key UNIQUE (client_mutation_id);


--
-- Name: meter_readings meter_readings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_pkey PRIMARY KEY (id);


--
-- Name: payment_allocations payment_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payment_allocations
    ADD CONSTRAINT payment_allocations_pkey PRIMARY KEY (id);


--
-- Name: payment_receipt_counters payment_receipt_counters_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payment_receipt_counters
    ADD CONSTRAINT payment_receipt_counters_pkey PRIMARY KEY (year);


--
-- Name: payments payments_client_mutation_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_client_mutation_id_key UNIQUE (client_mutation_id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: payments payments_receipt_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_receipt_number_key UNIQUE (receipt_number);


--
-- Name: shifts shifts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.shifts
    ADD CONSTRAINT shifts_pkey PRIMARY KEY (id);


--
-- Name: subscription_plans subscription_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscription_plans
    ADD CONSTRAINT subscription_plans_pkey PRIMARY KEY (id);


--
-- Name: subscription_plans subscription_plans_plan_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscription_plans
    ADD CONSTRAINT subscription_plans_plan_name_key UNIQUE (plan_name);


--
-- Name: sync_checkpoints sync_checkpoints_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sync_checkpoints
    ADD CONSTRAINT sync_checkpoints_pkey PRIMARY KEY (table_name);


--
-- Name: sync_outbox sync_outbox_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sync_outbox
    ADD CONSTRAINT sync_outbox_pkey PRIMARY KEY (id);


--
-- Name: system_settings system_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.system_settings
    ADD CONSTRAINT system_settings_pkey PRIMARY KEY (id);


--
-- Name: collector_customer_assignments uq_collector_customer; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.collector_customer_assignments
    ADD CONSTRAINT uq_collector_customer UNIQUE (collector_user_id, customer_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_supabase_uid_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_supabase_uid_key UNIQUE (supabase_uid);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: whatsapp_queue_messages whatsapp_queue_messages_client_mutation_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsapp_queue_messages
    ADD CONSTRAINT whatsapp_queue_messages_client_mutation_id_key UNIQUE (client_mutation_id);


--
-- Name: whatsapp_queue_messages whatsapp_queue_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsapp_queue_messages
    ADD CONSTRAINT whatsapp_queue_messages_pkey PRIMARY KEY (id);


--
-- Name: whatsapp_sessions whatsapp_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsapp_sessions
    ADD CONSTRAINT whatsapp_sessions_pkey PRIMARY KEY (session_id);


--
-- Name: whatsmeow_app_state_mutation_macs whatsmeow_app_state_mutation_macs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_app_state_mutation_macs
    ADD CONSTRAINT whatsmeow_app_state_mutation_macs_pkey PRIMARY KEY (jid, name, version, index_mac);


--
-- Name: whatsmeow_app_state_sync_keys whatsmeow_app_state_sync_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_app_state_sync_keys
    ADD CONSTRAINT whatsmeow_app_state_sync_keys_pkey PRIMARY KEY (jid, key_id);


--
-- Name: whatsmeow_app_state_version whatsmeow_app_state_version_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_app_state_version
    ADD CONSTRAINT whatsmeow_app_state_version_pkey PRIMARY KEY (jid, name);


--
-- Name: whatsmeow_chat_settings whatsmeow_chat_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_chat_settings
    ADD CONSTRAINT whatsmeow_chat_settings_pkey PRIMARY KEY (our_jid, chat_jid);


--
-- Name: whatsmeow_contacts whatsmeow_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_contacts
    ADD CONSTRAINT whatsmeow_contacts_pkey PRIMARY KEY (our_jid, their_jid);


--
-- Name: whatsmeow_device whatsmeow_device_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_device
    ADD CONSTRAINT whatsmeow_device_pkey PRIMARY KEY (jid);


--
-- Name: whatsmeow_event_buffer whatsmeow_event_buffer_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_event_buffer
    ADD CONSTRAINT whatsmeow_event_buffer_pkey PRIMARY KEY (our_jid, ciphertext_hash);


--
-- Name: whatsmeow_identity_keys whatsmeow_identity_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_identity_keys
    ADD CONSTRAINT whatsmeow_identity_keys_pkey PRIMARY KEY (our_jid, their_id);


--
-- Name: whatsmeow_lid_map whatsmeow_lid_map_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_lid_map
    ADD CONSTRAINT whatsmeow_lid_map_pkey PRIMARY KEY (lid);


--
-- Name: whatsmeow_lid_map whatsmeow_lid_map_pn_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_lid_map
    ADD CONSTRAINT whatsmeow_lid_map_pn_key UNIQUE (pn);


--
-- Name: whatsmeow_message_secrets whatsmeow_message_secrets_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_message_secrets
    ADD CONSTRAINT whatsmeow_message_secrets_pkey PRIMARY KEY (our_jid, chat_jid, sender_jid, message_id);


--
-- Name: whatsmeow_nct_salt whatsmeow_nct_salt_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_nct_salt
    ADD CONSTRAINT whatsmeow_nct_salt_pkey PRIMARY KEY (our_jid);


--
-- Name: whatsmeow_pre_keys whatsmeow_pre_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_pre_keys
    ADD CONSTRAINT whatsmeow_pre_keys_pkey PRIMARY KEY (jid, key_id);


--
-- Name: whatsmeow_privacy_tokens whatsmeow_privacy_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_privacy_tokens
    ADD CONSTRAINT whatsmeow_privacy_tokens_pkey PRIMARY KEY (our_jid, their_jid);


--
-- Name: whatsmeow_retry_buffer whatsmeow_retry_buffer_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_retry_buffer
    ADD CONSTRAINT whatsmeow_retry_buffer_pkey PRIMARY KEY (our_jid, chat_jid, message_id);


--
-- Name: whatsmeow_sender_keys whatsmeow_sender_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_sender_keys
    ADD CONSTRAINT whatsmeow_sender_keys_pkey PRIMARY KEY (our_jid, chat_id, sender_id);


--
-- Name: whatsmeow_sessions whatsmeow_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_sessions
    ADD CONSTRAINT whatsmeow_sessions_pkey PRIMARY KEY (our_jid, their_id);


--
-- Name: idx_allocations_invoice_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_allocations_invoice_id ON public.payment_allocations USING btree (invoice_id);


--
-- Name: idx_allocations_payment_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_allocations_payment_id ON public.payment_allocations USING btree (payment_id);


--
-- Name: idx_audit_logs_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_audit_logs_created_at ON public.audit_logs USING btree (created_at DESC);


--
-- Name: idx_audit_logs_entity; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_audit_logs_entity ON public.audit_logs USING btree (entity, entity_id);


--
-- Name: idx_audit_logs_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_audit_logs_user_id ON public.audit_logs USING btree (user_id);


--
-- Name: idx_billing_cycles_code; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_billing_cycles_code ON public.billing_cycles USING btree (code);


--
-- Name: idx_billing_cycles_dates; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_billing_cycles_dates ON public.billing_cycles USING btree (start_date, end_date);


--
-- Name: idx_billing_cycles_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_billing_cycles_status ON public.billing_cycles USING btree (status);


--
-- Name: idx_collector_assign_collector; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_collector_assign_collector ON public.collector_customer_assignments USING btree (collector_user_id);


--
-- Name: idx_collector_assign_customer; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_collector_assign_customer ON public.collector_customer_assignments USING btree (customer_id);


--
-- Name: idx_customer_credits_customer; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customer_credits_customer ON public.customer_credits USING btree (customer_id, status);


--
-- Name: idx_customers_address; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customers_address ON public.customers USING btree (address);


--
-- Name: idx_customers_phone_number; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customers_phone_number ON public.customers USING btree (phone_number);


--
-- Name: idx_customers_route_number; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customers_route_number ON public.customers USING btree (route_number);


--
-- Name: idx_customers_route_subscriber; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customers_route_subscriber ON public.customers USING btree (route_number, subscriber_number);


--
-- Name: idx_customers_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customers_status ON public.customers USING btree (status);


--
-- Name: idx_customers_subscriber_number; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customers_subscriber_number ON public.customers USING btree (subscriber_number);


--
-- Name: idx_invoices_billing_cycle; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_invoices_billing_cycle ON public.invoices USING btree (billing_cycle);


--
-- Name: idx_invoices_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_invoices_created_at ON public.invoices USING btree (created_at DESC);


--
-- Name: idx_invoices_customer_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_invoices_customer_id ON public.invoices USING btree (customer_id);


--
-- Name: idx_invoices_customer_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_invoices_customer_status ON public.invoices USING btree (customer_id, status);


--
-- Name: idx_invoices_cycle_customer; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_invoices_cycle_customer ON public.invoices USING btree (billing_cycle, customer_id);


--
-- Name: idx_invoices_cycle_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_invoices_cycle_id ON public.invoices USING btree (cycle_id);


--
-- Name: idx_invoices_due_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_invoices_due_date ON public.invoices USING btree (due_date);


--
-- Name: idx_invoices_status_remaining; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_invoices_status_remaining ON public.invoices USING btree (status, remaining_amount);


--
-- Name: idx_meter_readings_approval_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_meter_readings_approval_date ON public.meter_readings USING btree (approval_status, reading_date DESC);


--
-- Name: idx_meter_readings_customer_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_meter_readings_customer_id ON public.meter_readings USING btree (customer_id);


--
-- Name: idx_meter_readings_customer_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_meter_readings_customer_status ON public.meter_readings USING btree (customer_id, approval_status);


--
-- Name: idx_meter_readings_cycle_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_meter_readings_cycle_id ON public.meter_readings USING btree (cycle_id);


--
-- Name: idx_meter_readings_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_meter_readings_date ON public.meter_readings USING btree (reading_date DESC);


--
-- Name: idx_meter_readings_mutation_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_meter_readings_mutation_id ON public.meter_readings USING btree (client_mutation_id);


--
-- Name: idx_payments_customer_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_payments_customer_id ON public.payments USING btree (customer_id);


--
-- Name: idx_payments_customer_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_payments_customer_status ON public.payments USING btree (customer_id, approval_status);


--
-- Name: idx_payments_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_payments_date ON public.payments USING btree (payment_date DESC);


--
-- Name: idx_payments_mutation_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_payments_mutation_id ON public.payments USING btree (client_mutation_id);


--
-- Name: idx_payments_receipt_number; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_payments_receipt_number ON public.payments USING btree (receipt_number);


--
-- Name: idx_payments_shift_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_payments_shift_id ON public.payments USING btree (shift_id);


--
-- Name: idx_shifts_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_shifts_status ON public.shifts USING btree (status);


--
-- Name: idx_shifts_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_shifts_user_id ON public.shifts USING btree (user_id);


--
-- Name: idx_sync_outbox_pending; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_sync_outbox_pending ON public.sync_outbox USING btree (status, id);


--
-- Name: idx_users_role_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_users_role_active ON public.users USING btree (role, is_active);


--
-- Name: idx_users_username; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_users_username ON public.users USING btree (username);


--
-- Name: idx_wa_queue_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wa_queue_created ON public.whatsapp_queue_messages USING btree (created_at DESC);


--
-- Name: idx_wa_queue_source; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wa_queue_source ON public.whatsapp_queue_messages USING btree (source_entity, source_id);


--
-- Name: idx_wa_queue_status_sched; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wa_queue_status_sched ON public.whatsapp_queue_messages USING btree (status, scheduled_at);


--
-- Name: idx_wa_sessions_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wa_sessions_active ON public.whatsapp_sessions USING btree (is_active);


--
-- Name: idx_wa_sessions_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wa_sessions_status ON public.whatsapp_sessions USING btree (status);


--
-- Name: idx_whatsmeow_privacy_tokens_our_jid_timestamp; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_whatsmeow_privacy_tokens_our_jid_timestamp ON public.whatsmeow_privacy_tokens USING btree (our_jid, "timestamp");


--
-- Name: uq_customers_subscriber_number_clean; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX uq_customers_subscriber_number_clean ON public.customers USING btree (COALESCE(NULLIF(regexp_replace(TRIM(BOTH FROM lower((subscriber_number)::text)), '^0+'::text, ''::text), ''::text), '0'::text)) WHERE (is_deleted = false);


--
-- Name: uq_invoices_customer_cycle; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX uq_invoices_customer_cycle ON public.invoices USING btree (customer_id, billing_cycle) WHERE ((approval_status)::text <> 'REJECTED'::text);


--
-- Name: whatsmeow_retry_buffer_timestamp_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX whatsmeow_retry_buffer_timestamp_idx ON public.whatsmeow_retry_buffer USING btree (our_jid, "timestamp");


--
-- Name: invoices trg_invoices_set_invoice_number; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_invoices_set_invoice_number BEFORE INSERT OR UPDATE OF customer_id, billing_cycle, invoice_number ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.fn_trg_invoices_set_invoice_number();


--
-- Name: meter_readings trg_meter_readings_monotonic; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_meter_readings_monotonic BEFORE INSERT OR UPDATE OF reading_value, is_meter_reset, customer_id ON public.meter_readings FOR EACH ROW EXECUTE FUNCTION public.fn_trg_meter_readings_monotonic();


--
-- Name: audit_logs audit_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: collector_customer_assignments collector_customer_assignments_assigned_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.collector_customer_assignments
    ADD CONSTRAINT collector_customer_assignments_assigned_by_user_id_fkey FOREIGN KEY (assigned_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: collector_customer_assignments collector_customer_assignments_collector_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.collector_customer_assignments
    ADD CONSTRAINT collector_customer_assignments_collector_user_id_fkey FOREIGN KEY (collector_user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: collector_customer_assignments collector_customer_assignments_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.collector_customer_assignments
    ADD CONSTRAINT collector_customer_assignments_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;


--
-- Name: customer_credits customer_credits_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;


--
-- Name: customer_credits customer_credits_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.payments(id) ON DELETE CASCADE;


--
-- Name: customers customers_subscription_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_subscription_plan_id_fkey FOREIGN KEY (subscription_plan_id) REFERENCES public.subscription_plans(id) ON DELETE RESTRICT;


--
-- Name: invoices invoices_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE RESTRICT;


--
-- Name: invoices invoices_cycle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_cycle_id_fkey FOREIGN KEY (cycle_id) REFERENCES public.billing_cycles(id) ON DELETE RESTRICT;


--
-- Name: invoices invoices_reading_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_reading_id_fkey FOREIGN KEY (reading_id) REFERENCES public.meter_readings(id) ON DELETE SET NULL;


--
-- Name: meter_readings meter_readings_collector_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_collector_user_id_fkey FOREIGN KEY (collector_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: meter_readings meter_readings_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE RESTRICT;


--
-- Name: meter_readings meter_readings_cycle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_cycle_id_fkey FOREIGN KEY (cycle_id) REFERENCES public.billing_cycles(id) ON DELETE RESTRICT;


--
-- Name: payment_allocations payment_allocations_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payment_allocations
    ADD CONSTRAINT payment_allocations_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id) ON DELETE CASCADE;


--
-- Name: payment_allocations payment_allocations_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payment_allocations
    ADD CONSTRAINT payment_allocations_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.payments(id) ON DELETE CASCADE;


--
-- Name: payments payments_accountant_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_accountant_user_id_fkey FOREIGN KEY (accountant_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: payments payments_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE RESTRICT;


--
-- Name: payments payments_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id) ON DELETE SET NULL;


--
-- Name: payments payments_shift_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_shift_id_fkey FOREIGN KEY (shift_id) REFERENCES public.shifts(id) ON DELETE SET NULL;


--
-- Name: shifts shifts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.shifts
    ADD CONSTRAINT shifts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: whatsmeow_app_state_mutation_macs whatsmeow_app_state_mutation_macs_jid_name_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_app_state_mutation_macs
    ADD CONSTRAINT whatsmeow_app_state_mutation_macs_jid_name_fkey FOREIGN KEY (jid, name) REFERENCES public.whatsmeow_app_state_version(jid, name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_app_state_sync_keys whatsmeow_app_state_sync_keys_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_app_state_sync_keys
    ADD CONSTRAINT whatsmeow_app_state_sync_keys_jid_fkey FOREIGN KEY (jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_app_state_version whatsmeow_app_state_version_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_app_state_version
    ADD CONSTRAINT whatsmeow_app_state_version_jid_fkey FOREIGN KEY (jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_chat_settings whatsmeow_chat_settings_our_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_chat_settings
    ADD CONSTRAINT whatsmeow_chat_settings_our_jid_fkey FOREIGN KEY (our_jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_contacts whatsmeow_contacts_our_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_contacts
    ADD CONSTRAINT whatsmeow_contacts_our_jid_fkey FOREIGN KEY (our_jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_event_buffer whatsmeow_event_buffer_our_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_event_buffer
    ADD CONSTRAINT whatsmeow_event_buffer_our_jid_fkey FOREIGN KEY (our_jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_identity_keys whatsmeow_identity_keys_our_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_identity_keys
    ADD CONSTRAINT whatsmeow_identity_keys_our_jid_fkey FOREIGN KEY (our_jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_message_secrets whatsmeow_message_secrets_our_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_message_secrets
    ADD CONSTRAINT whatsmeow_message_secrets_our_jid_fkey FOREIGN KEY (our_jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_nct_salt whatsmeow_nct_salt_our_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_nct_salt
    ADD CONSTRAINT whatsmeow_nct_salt_our_jid_fkey FOREIGN KEY (our_jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_pre_keys whatsmeow_pre_keys_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_pre_keys
    ADD CONSTRAINT whatsmeow_pre_keys_jid_fkey FOREIGN KEY (jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_retry_buffer whatsmeow_retry_buffer_our_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_retry_buffer
    ADD CONSTRAINT whatsmeow_retry_buffer_our_jid_fkey FOREIGN KEY (our_jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_sender_keys whatsmeow_sender_keys_our_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_sender_keys
    ADD CONSTRAINT whatsmeow_sender_keys_our_jid_fkey FOREIGN KEY (our_jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_sessions whatsmeow_sessions_our_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.whatsmeow_sessions
    ADD CONSTRAINT whatsmeow_sessions_our_jid_fkey FOREIGN KEY (our_jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict meXbHGDVwU8d5ZLnmvQInaeaMKMTXc2A7svWoxgkSVwJbHvPdF5H7AHASXdLxpA

