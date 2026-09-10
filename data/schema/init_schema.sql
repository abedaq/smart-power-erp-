--
-- PostgreSQL database dump
--

\restrict GGeRs1Bc6Mve6Z1VkOflu8VGhFodlSSM0wgGf6UA1HWIrKlVLGbk2KKVCvr2lL4

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
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS '';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: fn_calculate_cycle_financials(numeric, numeric, numeric, numeric, numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_calculate_cycle_financials(p_current_reading numeric, p_previous_reading numeric, p_lost_units numeric, p_unit_price numeric, p_service_fee numeric, p_arrears numeric, p_paid_amount numeric) RETURNS TABLE(consumption numeric, consumption_cost numeric, lost_units_cost numeric, total_due numeric, remaining_amount numeric, status text)
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
DECLARE
  v_curr     NUMERIC(12,2) := COALESCE(p_current_reading, 0.00);
  v_prev     NUMERIC(12,2) := COALESCE(p_previous_reading, 0.00);
  v_lost     NUMERIC(12,2) := GREATEST(0.00, COALESCE(p_lost_units, 0.00));
  v_price    NUMERIC(12,2) := GREATEST(0.00, COALESCE(p_unit_price, 0.00));
  v_fee      NUMERIC(12,2) := GREATEST(0.00, COALESCE(p_service_fee, 0.00));
  v_arrears  NUMERIC(12,2) := COALESCE(p_arrears, 0.00);
  v_paid     NUMERIC(12,2) := GREATEST(0.00, COALESCE(p_paid_amount, 0.00));
  
  v_cons     NUMERIC(12,2);
  v_cons_val NUMERIC(12,2);
  v_lost_val NUMERIC(12,2);
  v_due      NUMERIC(12,2);
  v_rem      NUMERIC(12,2);
  v_status   TEXT;
BEGIN
  -- 1. Net Consumption
  v_cons := GREATEST(0.00, ROUND(v_curr - v_prev, 2));
  
  -- 2. Net Consumption Cost & Lost Units Cost
  v_cons_val := ROUND(v_cons * v_price, 2);
  v_lost_val := ROUND(v_lost * v_price, 2);
  
  -- 3. Total Due = Consumption Cost + Lost Units Cost + Service Fee + Arrears
  v_due := ROUND(v_cons_val + v_lost_val + v_fee + v_arrears, 2);
  
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

  RETURN QUERY SELECT v_cons, v_cons_val, v_lost_val, v_due, v_rem, v_status;
END;
$$;


--
-- Name: fn_generate_invoice_number(text, text); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: fn_trg_invoices_set_invoice_number(); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: fn_trg_meter_readings_monotonic(); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: rpc_recalculate_customer_cascade(integer, integer, integer, jsonb, integer, boolean); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: rpc_recalculate_customer_cascade(bigint, bigint, bigint, jsonb, bigint, boolean); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: rpc_submit_meter_reading(integer, numeric, text, uuid, boolean, timestamp with time zone, text, boolean, numeric, integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: rpc_submit_meter_reading(bigint, numeric, text, uuid, boolean, timestamp with time zone, text, boolean, numeric, bigint); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: rpc_submit_payment(integer, numeric, text, text, uuid, text, timestamp with time zone, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: rpc_submit_payment(bigint, numeric, text, text, uuid, text, timestamp with time zone, bigint, bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
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


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_logs_id_seq OWNED BY public.audit_logs.id;


--
-- Name: billing_cycles; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: billing_cycles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.billing_cycles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: billing_cycles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.billing_cycles_id_seq OWNED BY public.billing_cycles.id;


--
-- Name: collector_customer_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.collector_customer_assignments (
    id bigint NOT NULL,
    collector_user_id bigint NOT NULL,
    customer_id bigint NOT NULL,
    assigned_by_user_id bigint,
    assigned_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: collector_customer_assignments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.collector_customer_assignments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: collector_customer_assignments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.collector_customer_assignments_id_seq OWNED BY public.collector_customer_assignments.id;


--
-- Name: customer_credits; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: customer_credits_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.customer_credits_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: customer_credits_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.customer_credits_id_seq OWNED BY public.customer_credits.id;


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
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
    CONSTRAINT chk_customers_balance CHECK ((balance >= (0)::numeric)),
    CONSTRAINT chk_customers_readings CHECK (((initial_reading >= (0)::numeric) AND (last_reading >= (0)::numeric))),
    CONSTRAINT chk_customers_status CHECK (((status)::text = ANY (ARRAY[('Active'::character varying)::text, ('Suspended'::character varying)::text, ('Disconnected'::character varying)::text, ('Terminated'::character varying)::text])))
);


--
-- Name: customers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.customers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: customers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.customers_id_seq OWNED BY public.customers.id;


--
-- Name: invoices; Type: TABLE; Schema: public; Owner: -
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
    lost_units numeric(12,2) DEFAULT 0.00 NOT NULL,
    consumption_value numeric(12,2) DEFAULT 0.00 NOT NULL,
    lost_units_value numeric(12,2) DEFAULT 0.00 NOT NULL,
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
    CONSTRAINT chk_invoices_approval CHECK (((approval_status)::text = ANY (ARRAY[('APPROVED'::character varying)::text, ('PENDING'::character varying)::text, ('REJECTED'::character varying)::text]))),
    CONSTRAINT chk_invoices_financials CHECK (((consumption_value >= (0)::numeric) AND (lost_units_value >= (0)::numeric) AND (kwh_price_snapshot >= (0)::numeric) AND (fixed_fee_snapshot >= (0)::numeric) AND (paid_amount >= (0)::numeric))),
    CONSTRAINT chk_invoices_monotonic CHECK (((is_meter_reset = true) OR (current_reading = (0)::numeric) OR (current_reading >= previous_reading))),
    CONSTRAINT chk_invoices_number_pattern CHECK (((invoice_number)::text ~ '^INV-[A-Za-z0-9_ء-ي\-]+-[A-Za-z0-9_\-]+$'::text)),
    CONSTRAINT chk_invoices_readings CHECK (((previous_reading >= (0)::numeric) AND (current_reading >= (0)::numeric) AND (consumption >= (0)::numeric) AND (lost_units >= (0)::numeric))),
    CONSTRAINT chk_invoices_status CHECK (((status)::text = ANY (ARRAY[('Unpaid'::character varying)::text, ('Partially_Paid'::character varying)::text, ('Paid'::character varying)::text, ('Cancelled'::character varying)::text, ('Void'::character varying)::text, ('Pending_Approval'::character varying)::text])))
);


--
-- Name: invoices_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.invoices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: invoices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.invoices_id_seq OWNED BY public.invoices.id;


--
-- Name: meter_readings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.meter_readings (
    id bigint NOT NULL,
    customer_id bigint NOT NULL,
    cycle_id bigint,
    reading_value numeric(12,2) NOT NULL,
    previous_reading numeric(12,2) DEFAULT 0.00 NOT NULL,
    consumption numeric(12,2) DEFAULT 0.00 NOT NULL,
    lost_units numeric(12,2) DEFAULT 0.00 NOT NULL,
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
    CONSTRAINT chk_meter_readings_amounts CHECK (((reading_value >= (0)::numeric) AND (previous_reading >= (0)::numeric) AND (consumption >= (0)::numeric) AND (lost_units >= (0)::numeric))),
    CONSTRAINT chk_meter_readings_approval CHECK (((approval_status)::text = ANY (ARRAY[('APPROVED'::character varying)::text, ('PENDING'::character varying)::text, ('REJECTED'::character varying)::text]))),
    CONSTRAINT chk_meter_readings_monotonic CHECK (((is_meter_reset = true) OR (reading_value = (0)::numeric) OR (reading_value >= previous_reading)))
);


--
-- Name: meter_readings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.meter_readings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: meter_readings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.meter_readings_id_seq OWNED BY public.meter_readings.id;


--
-- Name: payment_allocations; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: payment_allocations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.payment_allocations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: payment_allocations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.payment_allocations_id_seq OWNED BY public.payment_allocations.id;


--
-- Name: payment_receipt_counters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_receipt_counters (
    year integer NOT NULL,
    last_value bigint DEFAULT 0 NOT NULL,
    CONSTRAINT chk_receipt_counter_val CHECK ((last_value >= 0))
);


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
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
    CONSTRAINT chk_payments_method CHECK (((payment_method)::text = ANY ((ARRAY['CASH'::character varying, 'TRANSFER'::character varying, 'BANK_TRANSFER'::character varying, 'BANK'::character varying, 'KURAMI'::character varying, 'KURSHI'::character varying, 'OTHER'::character varying])::text[])))
);


--
-- Name: payments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.payments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: payments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.payments_id_seq OWNED BY public.payments.id;


--
-- Name: subscription_plans; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: plans; Type: VIEW; Schema: public; Owner: -
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


--
-- Name: system_settings; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: settings; Type: VIEW; Schema: public; Owner: -
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


--
-- Name: shifts; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: shifts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.shifts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: shifts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.shifts_id_seq OWNED BY public.shifts.id;


--
-- Name: subscription_plans_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.subscription_plans_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscription_plans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.subscription_plans_id_seq OWNED BY public.subscription_plans.id;


--
-- Name: system_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.system_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: system_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.system_settings_id_seq OWNED BY public.system_settings.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: whatsapp_queue_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsapp_queue_messages (
    id bigint NOT NULL,
    phone_number character varying(30) NOT NULL,
    type character varying(20) DEFAULT 'TEXT'::character varying NOT NULL,
    message text,
    image_base64 text,
    caption text,
    media_path text,
    status character varying(20) DEFAULT 'PENDING'::character varying NOT NULL,
    retries integer DEFAULT 0 NOT NULL,
    max_retries integer DEFAULT 3 NOT NULL,
    error_msg text,
    source_entity character varying(30),
    source_id bigint,
    client_mutation_id uuid DEFAULT gen_random_uuid(),
    scheduled_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    processing_started_at timestamp with time zone,
    sent_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_wa_queue_retries CHECK (((retries >= 0) AND (max_retries >= 0))),
    CONSTRAINT chk_wa_queue_status CHECK (((status)::text = ANY (ARRAY[('PENDING'::character varying)::text, ('PROCESSING'::character varying)::text, ('SENT'::character varying)::text, ('FAILED'::character varying)::text, ('CANCELLED'::character varying)::text]))),
    CONSTRAINT chk_wa_queue_type CHECK (((type)::text = ANY (ARRAY[('TEXT'::character varying)::text, ('IMAGE'::character varying)::text, ('INVOICE_PDF'::character varying)::text, ('PAYMENT_RECEIPT'::character varying)::text])))
);


--
-- Name: whatsapp_queue_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.whatsapp_queue_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: whatsapp_queue_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.whatsapp_queue_messages_id_seq OWNED BY public.whatsapp_queue_messages.id;


--
-- Name: whatsapp_sessions; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: whatsmeow_app_state_mutation_macs; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: whatsmeow_app_state_sync_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsmeow_app_state_sync_keys (
    jid text NOT NULL,
    key_id bytea NOT NULL,
    key_data bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    fingerprint bytea NOT NULL
);


--
-- Name: whatsmeow_app_state_version; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsmeow_app_state_version (
    jid text NOT NULL,
    name text NOT NULL,
    version bigint NOT NULL,
    hash bytea NOT NULL,
    CONSTRAINT whatsmeow_app_state_version_hash_check CHECK ((length(hash) = 128))
);


--
-- Name: whatsmeow_chat_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsmeow_chat_settings (
    our_jid text NOT NULL,
    chat_jid text NOT NULL,
    muted_until bigint DEFAULT 0 NOT NULL,
    pinned boolean DEFAULT false NOT NULL,
    archived boolean DEFAULT false NOT NULL
);


--
-- Name: whatsmeow_contacts; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: whatsmeow_device; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: whatsmeow_event_buffer; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsmeow_event_buffer (
    our_jid text NOT NULL,
    ciphertext_hash bytea NOT NULL,
    plaintext bytea,
    server_timestamp bigint NOT NULL,
    insert_timestamp bigint NOT NULL,
    CONSTRAINT whatsmeow_event_buffer_ciphertext_hash_check CHECK ((length(ciphertext_hash) = 32))
);


--
-- Name: whatsmeow_identity_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsmeow_identity_keys (
    our_jid text NOT NULL,
    their_id text NOT NULL,
    identity bytea NOT NULL,
    CONSTRAINT whatsmeow_identity_keys_identity_check CHECK ((length(identity) = 32))
);


--
-- Name: whatsmeow_lid_map; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsmeow_lid_map (
    lid text NOT NULL,
    pn text NOT NULL
);


--
-- Name: whatsmeow_message_secrets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsmeow_message_secrets (
    our_jid text NOT NULL,
    chat_jid text NOT NULL,
    sender_jid text NOT NULL,
    message_id text NOT NULL,
    key bytea NOT NULL
);


--
-- Name: whatsmeow_nct_salt; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsmeow_nct_salt (
    our_jid text NOT NULL,
    salt bytea NOT NULL
);


--
-- Name: whatsmeow_pre_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsmeow_pre_keys (
    jid text NOT NULL,
    key_id integer NOT NULL,
    key bytea NOT NULL,
    uploaded boolean NOT NULL,
    CONSTRAINT whatsmeow_pre_keys_key_check CHECK ((length(key) = 32)),
    CONSTRAINT whatsmeow_pre_keys_key_id_check CHECK (((key_id >= 0) AND (key_id < 16777216)))
);


--
-- Name: whatsmeow_privacy_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsmeow_privacy_tokens (
    our_jid text NOT NULL,
    their_jid text NOT NULL,
    token bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    sender_timestamp bigint
);


--
-- Name: whatsmeow_retry_buffer; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsmeow_retry_buffer (
    our_jid text NOT NULL,
    chat_jid text NOT NULL,
    message_id text NOT NULL,
    format text NOT NULL,
    plaintext bytea NOT NULL,
    "timestamp" bigint NOT NULL
);


--
-- Name: whatsmeow_sender_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsmeow_sender_keys (
    our_jid text NOT NULL,
    chat_id text NOT NULL,
    sender_id text NOT NULL,
    sender_key bytea NOT NULL
);


--
-- Name: whatsmeow_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsmeow_sessions (
    our_jid text NOT NULL,
    their_id text NOT NULL,
    session bytea
);


--
-- Name: whatsmeow_version; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsmeow_version (
    version integer,
    compat integer
);


--
-- Name: audit_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs ALTER COLUMN id SET DEFAULT nextval('public.audit_logs_id_seq'::regclass);


--
-- Name: billing_cycles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_cycles ALTER COLUMN id SET DEFAULT nextval('public.billing_cycles_id_seq'::regclass);


--
-- Name: collector_customer_assignments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collector_customer_assignments ALTER COLUMN id SET DEFAULT nextval('public.collector_customer_assignments_id_seq'::regclass);


--
-- Name: customer_credits id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_credits ALTER COLUMN id SET DEFAULT nextval('public.customer_credits_id_seq'::regclass);


--
-- Name: customers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers ALTER COLUMN id SET DEFAULT nextval('public.customers_id_seq'::regclass);


--
-- Name: invoices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices ALTER COLUMN id SET DEFAULT nextval('public.invoices_id_seq'::regclass);


--
-- Name: meter_readings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings ALTER COLUMN id SET DEFAULT nextval('public.meter_readings_id_seq'::regclass);


--
-- Name: payment_allocations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_allocations ALTER COLUMN id SET DEFAULT nextval('public.payment_allocations_id_seq'::regclass);


--
-- Name: payments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments ALTER COLUMN id SET DEFAULT nextval('public.payments_id_seq'::regclass);


--
-- Name: shifts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shifts ALTER COLUMN id SET DEFAULT nextval('public.shifts_id_seq'::regclass);


--
-- Name: subscription_plans id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_plans ALTER COLUMN id SET DEFAULT nextval('public.subscription_plans_id_seq'::regclass);


--
-- Name: system_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_settings ALTER COLUMN id SET DEFAULT nextval('public.system_settings_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: whatsapp_queue_messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_queue_messages ALTER COLUMN id SET DEFAULT nextval('public.whatsapp_queue_messages_id_seq'::regclass);


--
-- Data for Name: audit_logs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.audit_logs (id, user_id, action, entity, entity_id, details, ip_address, created_at) FROM stdin;
6	\N	READING_CREATE_RPC	MeterReading	10	تسجيل قراءة عداد (180.00) للمشترك: عبدالله أحمد الصنعاني (فاتورة رقم: INV-2026-08-10001)	\N	2026-08-10 10:00:00+03
7	\N	READING_CREATE_RPC	MeterReading	11	تسجيل قراءة عداد (360.00) للمشترك: محمد علي الأهدل (فاتورة رقم: INV-2026-08-10002)	\N	2026-08-10 10:15:00+03
8	\N	READING_CREATE_RPC	MeterReading	12	تسجيل قراءة عداد (290.00) للمشترك: حسين يحيى الحوثي (فاتورة رقم: INV-2026-08-10003)	\N	2026-08-10 10:30:00+03
9	\N	READING_CREATE_RPC	MeterReading	13	تسجيل قراءة عداد (550.00) للمشترك: صالح ناصر المهدي (فاتورة رقم: INV-2026-08-10004)	\N	2026-08-10 10:45:00+03
10	\N	READING_CREATE_RPC	MeterReading	14	تسجيل قراءة عداد (120.00) للمشترك: فؤاد قاسم الشميري (فاتورة رقم: INV-2026-08-10005)	\N	2026-08-10 11:00:00+03
25	1	LOGIN	USER	\N	User logged in successfully	\N	2026-09-06 13:28:24.598759+03
26	1	LOGIN	USER	\N	User logged in successfully	\N	2026-09-06 13:28:31.35429+03
27	1	LOGIN	USER	\N	User logged in successfully	\N	2026-09-06 13:29:10.22898+03
28	1	LOGIN	USER	\N	User logged in successfully	\N	2026-09-06 13:29:44.216321+03
29	1	LOGIN	USER	\N	User logged in successfully	\N	2026-09-06 13:31:30.084053+03
30	1	CREATE_PAYMENT	PAYMENT	REC-2026-000001	Payment of 30000.00 processed with 1 allocations	\N	2026-09-06 13:31:30.24803+03
31	1	LOGIN	USER	\N	User logged in successfully	\N	2026-09-06 13:32:00.553736+03
32	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-07 09:29:16.806824+03
33	1	GRID_CELL_UPDATE	CUSTOMER	70	تعديل فوري في الجدول للمشترك رقم [70]	\N	2026-09-07 09:29:16.903724+03
34	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-07 09:29:20.604591+03
35	1	GRID_CELL_UPDATE	CUSTOMER	71	تعديل فوري في الجدول للمشترك رقم [71]	\N	2026-09-07 09:29:20.663346+03
36	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-07 09:29:24.531478+03
37	1	GRID_CELL_UPDATE	CUSTOMER	70	تعديل فوري في الجدول للمشترك رقم [70]	\N	2026-09-07 09:29:24.606609+03
38	1	GRID_CELL_UPDATE	CUSTOMER	71	تعديل فوري في الجدول للمشترك رقم [71]	\N	2026-09-07 09:29:24.621025+03
39	1	CREATE_PAYMENT	PAYMENT	REC-2026-000002	تم تحصيل سند قبض وسداد بمبلغ 106000.00 ريال وتوزيعه آلياً على 1 فاتورة مستحقة	\N	2026-09-07 09:35:26.796402+03
40	1	CREATE_PAYMENT	PAYMENT	REC-2026-000003	تم تحصيل سند قبض وسداد بمبلغ 100000.00 ريال وتوزيعه آلياً على 2 فاتورة مستحقة	\N	2026-09-07 09:35:43.884113+03
41	1	GRID_CELL_UPDATE	CUSTOMER	175	تعديل فوري في الجدول للمشترك رقم [175]	\N	2026-09-07 10:07:44.56329+03
42	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-07 10:24:44.163115+03
43	1	CUSTOMER_CREATE	CUSTOMER	16	تمت إضافة مشترك جديد [مشترك الفحص والتدقيق الآلي] برقم اشتراك [TEST-1788765884]	\N	2026-09-07 10:24:44.182237+03
44	1	GRID_CELL_UPDATE	CUSTOMER	221	تعديل فوري في الجدول للمشترك رقم [221]	\N	2026-09-07 10:24:45.377644+03
45	1	GRID_CELL_UPDATE	CUSTOMER	222	تعديل فوري في الجدول للمشترك رقم [222]	\N	2026-09-07 10:24:45.39243+03
46	1	GRID_CELL_UPDATE	CUSTOMER	223	تعديل فوري في الجدول للمشترك رقم [223]	\N	2026-09-07 10:24:45.408087+03
47	1	GRID_CELL_UPDATE	CUSTOMER	224	تعديل فوري في الجدول للمشترك رقم [224]	\N	2026-09-07 10:24:45.423863+03
48	1	GRID_CELL_UPDATE	CUSTOMER	225	تعديل فوري في الجدول للمشترك رقم [225]	\N	2026-09-07 10:24:45.439456+03
49	1	GRID_CELL_UPDATE	CUSTOMER	226	تعديل فوري في الجدول للمشترك رقم [226]	\N	2026-09-07 10:24:45.452921+03
50	1	CREATE_PAYMENT	PAYMENT	REC-2026-000004	تم تحصيل سند قبض وسداد بمبلغ 71500.00 ريال وتوزيعه آلياً على 1 فاتورة مستحقة	\N	2026-09-07 10:24:45.463212+03
51	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-07 10:25:39.122505+03
52	1	CUSTOMER_CREATE	CUSTOMER	17	تمت إضافة مشترك جديد [مشترك الفحص والتدقيق الآلي] برقم اشتراك [TEST-1788765939]	\N	2026-09-07 10:25:39.150955+03
53	1	GRID_CELL_UPDATE	CUSTOMER	228	تعديل فوري في الجدول للمشترك رقم [228]	\N	2026-09-07 10:25:40.353927+03
54	1	GRID_CELL_UPDATE	CUSTOMER	229	تعديل فوري في الجدول للمشترك رقم [229]	\N	2026-09-07 10:25:40.372404+03
55	1	GRID_CELL_UPDATE	CUSTOMER	230	تعديل فوري في الجدول للمشترك رقم [230]	\N	2026-09-07 10:25:40.391508+03
56	1	GRID_CELL_UPDATE	CUSTOMER	231	تعديل فوري في الجدول للمشترك رقم [231]	\N	2026-09-07 10:25:40.405558+03
57	1	GRID_CELL_UPDATE	CUSTOMER	232	تعديل فوري في الجدول للمشترك رقم [232]	\N	2026-09-07 10:25:40.419762+03
58	1	GRID_CELL_UPDATE	CUSTOMER	233	تعديل فوري في الجدول للمشترك رقم [233]	\N	2026-09-07 10:25:40.434946+03
59	1	CREATE_PAYMENT	PAYMENT	REC-2026-000005	تم تحصيل سند قبض وسداد بمبلغ 71500.00 ريال وتوزيعه آلياً على 1 فاتورة مستحقة	\N	2026-09-07 10:25:40.44901+03
60	1	CREATE_PAYMENT	PAYMENT	REC-2026-000006	تم تحصيل سند قبض وسداد بمبلغ 49500.00 ريال وتوزيعه آلياً على 1 فاتورة مستحقة	\N	2026-09-07 10:25:40.476565+03
61	1	CREATE_PAYMENT	PAYMENT	REC-2026-000007	تم تحصيل سند قبض وسداد بمبلغ 226500.00 ريال وتوزيعه آلياً على 1 فاتورة مستحقة	\N	2026-09-07 10:25:40.498456+03
62	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-07 10:25:52.922514+03
63	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-07 10:34:11.18026+03
64	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-07 10:34:57.161981+03
65	1	CUSTOMER_CREATE	CUSTOMER	18	تمت إضافة مشترك جديد [????? ?????? ???? ??????] برقم اشتراك [SUB-761200]	\N	2026-09-07 10:34:57.212042+03
66	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-07 10:35:34.861559+03
67	1	CUSTOMER_CREATE	CUSTOMER	19	تمت إضافة مشترك جديد [مشترك اختبار دورة أكتوبر] برقم اشتراك [SUB-437100]	\N	2026-09-07 10:35:34.908046+03
68	1	CUSTOMER_CREATE	CUSTOMER	20	تمت إضافة مشترك جديد [محمد سغيد احمد] برقم اشتراك [SUB-799000]	\N	2026-09-07 10:48:13.57027+03
69	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-07 10:55:25.447594+03
70	1	CREATE_PAYMENT	PAYMENT	REC-2026-000008	تم تحصيل سند قبض وسداد بمبلغ 180000.00 ريال وتوزيعه آلياً على 1 فاتورة مستحقة	\N	2026-09-07 11:18:45.529427+03
71	1	CREATE_PAYMENT	PAYMENT	REC-2026-000009	تم تحصيل سند قبض وسداد بمبلغ 180000.00 ريال وتوزيعه آلياً على 1 فاتورة مستحقة	\N	2026-09-07 11:20:17.488609+03
72	\N	WHATSAPP_CANCEL_QUEUE	WHATSAPP	\N	تم إلغاء وتفريغ 0 رسالة معلقة من طابور الواتساب بنجاح	\N	2026-09-07 11:49:36.978661+03
73	1	CREATE_PAYMENT	PAYMENT	REC-2026-000010	تم تحصيل سند قبض وسداد بمبلغ 50000.00 ريال وتوزيعه آلياً على 1 فاتورة مستحقة	\N	2026-09-07 11:53:49.373028+03
74	1	WHATSAPP_SEND_INVOICE	INVOICE	55	إرسال فاتورة رقم [INV-2026-08-2-10001] للمشترك [عبدالله أحمد الصنعاني] عبر الواتساب	\N	2026-09-07 12:45:09.218779+03
75	1	WHATSAPP_SEND_INVOICE	INVOICE	56	إرسال فاتورة رقم [INV-2026-08-2-10002] للمشترك [محمد علي الأهدل] عبر الواتساب	\N	2026-09-07 12:45:11.897757+03
76	1	WHATSAPP_SEND_INVOICE	INVOICE	55	إرسال فاتورة رقم [INV-2026-08-2-10001] للمشترك [عبدالله أحمد الصنعاني] عبر الواتساب	\N	2026-09-07 13:29:09.842126+03
77	1	WHATSAPP_SEND_INVOICE	INVOICE	55	إرسال فاتورة رقم [INV-2026-08-2-10001] للمشترك [عبدالله أحمد الصنعاني] عبر الواتساب	\N	2026-09-07 13:37:47.367713+03
78	1	WHATSAPP_SEND_PAYMENT	PAYMENT	21	إرسال سند قبض رقم [REC-2026-000010] للمشترك [عبدالله أحمد الصنعاني] عبر الواتساب	\N	2026-09-07 13:38:24.931504+03
79	1	WHATSAPP_SEND_PAYMENT	PAYMENT	21	إرسال سند قبض رقم [REC-2026-000010] للمشترك [عبدالله أحمد الصنعاني] عبر الواتساب	\N	2026-09-07 13:38:48.759124+03
80	1	WHATSAPP_SEND_PAYMENT	PAYMENT	20	إرسال سند قبض رقم [REC-2026-000009] للمشترك [هشام شرف القاسمي] عبر الواتساب	\N	2026-09-07 13:39:40.967868+03
81	1	WHATSAPP_SEND_PAYMENT	PAYMENT	21	إرسال سند قبض رقم [REC-2026-000010] للمشترك [عبدالله أحمد الصنعاني] عبر الواتساب	\N	2026-09-07 13:46:47.47509+03
82	1	CUSTOMER_CREATE	CUSTOMER	21	تمت إضافة مشترك جديد [محمد سعيد احمد خالد] برقم اشتراك [10017]	\N	2026-09-07 14:11:02.029829+03
83	1	GRID_CELL_UPDATE	CUSTOMER	284	تعديل فوري في الجدول للمشترك رقم [284]	\N	2026-09-07 14:11:31.925852+03
84	1	GRID_CELL_UPDATE	CUSTOMER	284	تعديل فوري في الجدول للمشترك رقم [284]	\N	2026-09-07 14:11:38.797744+03
85	1	WHATSAPP_SEND_INVOICE	INVOICE	284	إرسال فاتورة رقم [INV-أغسطس-2-10017] للمشترك [محمد سعيد احمد خالد] عبر الواتساب	\N	2026-09-07 14:11:38.86823+03
86	1	CREATE_PAYMENT	PAYMENT	REC-2026-000011	تم تحصيل سند قبض وسداد بمبلغ 10000.00 ريال وتوزيعه آلياً على 1 فاتورة مستحقة	\N	2026-09-07 14:12:14.408035+03
87	1	WHATSAPP_SEND_PAYMENT	PAYMENT	22	إرسال سند قبض رقم [REC-2026-000011] للمشترك [محمد سعيد احمد خالد] عبر الواتساب	\N	2026-09-07 14:12:25.273801+03
88	1	GRID_CELL_UPDATE	CUSTOMER	285	تعديل فوري في الجدول للمشترك رقم [285]	\N	2026-09-07 14:32:48.039542+03
89	1	GRID_CELL_UPDATE	CUSTOMER	286	تعديل فوري في الجدول للمشترك رقم [286]	\N	2026-09-07 14:32:55.85666+03
92	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-07 15:31:41.420373+03
93	1	LOGIN	USER	\N	تسجيل دخول ناجح لمستخدم النظام	\N	2026-09-07 15:31:55.542739+03
\.


--
-- Data for Name: billing_cycles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.billing_cycles (id, code, name, start_date, end_date, due_date, status, total_consumption, total_amount, total_paid, total_arrears, created_at, updated_at) FROM stdin;
1	2026-08-2	أغسطس 2	2026-08-01	2026-08-31	2026-09-10	OPEN	6057.00	15250700.00	872520.00	0.00	2026-09-06 12:44:31.741142+03	2026-09-06 12:44:31.741142+03
\.


--
-- Data for Name: collector_customer_assignments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.collector_customer_assignments (id, collector_user_id, customer_id, assigned_by_user_id, assigned_at) FROM stdin;
\.


--
-- Data for Name: customer_credits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.customer_credits (id, customer_id, payment_id, amount, remaining_amount, status, created_at, updated_at) FROM stdin;
1	169	32	2000.00	2000.00	AVAILABLE	2026-09-04 19:03:19+03	2026-09-04 19:03:19+03
2	145	41	17800.00	17800.00	AVAILABLE	2026-09-04 17:48:47+03	2026-09-04 17:48:47+03
3	201	46	1800.00	1800.00	AVAILABLE	2026-09-04 15:22:35+03	2026-09-04 15:22:35+03
\.


--
-- Data for Name: customers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.customers (id, subscriber_number, full_name, phone_number, id_card_url, address, meter_number, route_number, subscription_plan_id, initial_reading, last_reading, total_due, balance, status, is_deleted, test_run_id, created_at, updated_at, start_cycle) FROM stdin;
1	910001	you قريش	739132010	\N	الجحملية	140495	0	1	56900.00	56900.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
2	910002	you صالة	739132010	\N	صالة	41380	0	1	44179.00	44179.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
3	910004	موقع يمن موبايل	773229696	\N	حارة قريش	202210200648	0	1	35078.00	35078.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
4	910226	مشترك 910226		\N	صنعاء	910226	0	1	1288.00	1288.00	2000.00	2000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
5	910005	منزل شروق عبدالله علي البيضاني	783270260	\N	الخزانات ج ع مصطفئ	219593	1	1	226.00	226.00	93000.00	93000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
6	910096	عبدالكريم الصبري	739524754	\N	الخزانات	22003021728	2	1	617.00	635.00	26200.00	26200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
7	910003	منزل محمدفواد الشهاري	733437874	\N	الخزانات	20220348260	3	1	294.00	300.00	10000.00	10000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
8	910297	منزل علي محمد ناجي فارع ماوية	734275073	\N	الخزانات ج الكهرباء	2408085749	4	1	224.00	224.00	15400.00	15400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
9	910006	كامل عبدة علي الظرافي	777739388	\N	الخزانات	202009067795	5	1	594.00	594.00	2000.00	2000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
11	910007	منزل علي احمد المنصوري	780375047	\N	الخزانات	202305216522	6	1	831.00	833.00	9000.00	9000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
12	910513	محمد صلاح الحوباني	777858560	\N	الخزانات	22335566	6	1	716.00	719.00	22600.00	22600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
13	910008	مدرسة اجيال السعيدة	774210359	\N	الخزانات	20223034202	7	1	631.00	644.00	226600.00	226600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
14	910464	منير احمد محمد حيدر	783270260	\N	عقبة ج ماجد الزرعي	250900009069	8	1	0.00	0.00	19000.00	19000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
16	910010	منزل امين عبدةحسن جنوش	730030270	\N	الخزانات ج الدكتور رشيد	214266	10	1	282.00	301.00	27700.00	27700.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
18	910016	منزل إسماعيل احمد عبدة السامعي	777900589	\N	الخزانات ج جنوش	2008089744	12	1	166.00	168.00	3800.00	3800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
20	910012	منزل الدكتور رشيد	777739388	\N	الخزانات	202003034225	14	1	550.00	553.00	21600.00	21600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
22	910307	منزل محمد البارقي	730876328	\N	الخزانات ج الدكتور رشيد	2408092824	15	1	127.00	130.00	13100.00	13100.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
23	910015	منزل وجدي عصام	777889331	\N	الخزانات	200321239	16	1	1118.00	1127.00	13600.00	13600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
25	910390	منزل عبدالله صغير حمود	739751153	\N	عقبة ج فاروق عبدالقدوس	241016065843	18	1	96.00	100.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
26	910442	حبيب عبدالغني 2	774325012	\N	عقبه ج فاروق عبدالقدوس	910442	18	1	58.00	59.00	8200.00	8200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
28	910382	منزل عبدالملك سليمان	775390908	\N	عقبة ج فاروق عبدالقدوس	202005104789	19	1	1857.00	1896.00	55600.00	55600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
31	910289	منزل وليد احمد عبدالجليل الاغبري	738482282	\N	عقبة جوارفاروق عبدالقدوس	2408080630	22	1	727.00	752.00	36000.00	36000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
32	910337	منزل ماجدعبدالله قائد الزرعي	735047834	\N	عقبة ج حذيفة الاجعش	202408096422	23	1	325.00	332.00	10800.00	10800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
33	910028	بقالة يوسف شعبان	774368015	\N	عقبة	2019110784	24	1	2324.00	2324.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
34	910285	منزل ابتسام 0ام محمدنجيب	735603805	\N	عقبة مقابل بقالةشعبان	202408080573	25	1	190.00	196.00	9400.00	9400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
36	910547	فضل علي احمد الجهيم	735842567	\N	عقبة ج عمارة فهد	250900092539	26	1	44.00	151.00	150800.00	150800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
38	910535	فهد عبدالله احمد سعيد	777327600	\N	عقبة ج جامع الهدئ	2401010774	27	1	228.00	242.00	20600.00	20600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
39	910336	بقالة عبدالجليل محمدالشرعبي	738905666	\N	عقبة ج حذيفة الاجعش	202009064748	28	1	566.00	574.00	12200.00	12200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
40	910258	منزل وهيب عبدالعزيزالصلوي	738001289	\N	عقبةج  يوسف شعبان	202401059500	29	1	391.00	391.00	2000.00	2000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
41	910033	منزل احمد علي راجح	734927701	\N	عقبة	2210106289	30	1	231.00	239.00	81200.00	81200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
43	910538	عاهد محمد عبالله احمد	775204317	\N	عقبة ج سمير الصامت	202508000840	31	1	74.00	88.00	42600.00	42600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
44	910036	منزل هيثم ناجي المحيا	734583665	\N	عقبة	22008273564	32	1	534.00	534.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
45	910037	اللمنيوم اسامة الحاج	733929451	\N	عقبة	13285	33	1	2462.00	2482.00	29000.00	29000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
46	910035	منزل بلال عبدالحميداحمدالحاج	008619-8221-57943	\N	عقبة	219153	34	1	752.00	775.00	33800.00	33800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
47	910265	منزل ماجد الحاج عقبة	777771494	\N	عقبة ج أسامة الحاج	24101607396	35	1	156.00	160.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
48	910412	منزل هشام ناجي محمد سعيد غالب	772750752	\N	عقبة ج أسامة الحاج	24010696	36	1	1872.00	1953.00	133600.00	133600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
49	910479	احمد نبيل الكدهي	773824282	\N	عقبة ج هشام ناجي	202408095987	37	1	326.00	326.00	170900.00	170900.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
50	910038	منزل هاني قاىد الشريف	737236776	\N	عقبةج المحطة	214008	38	1	553.00	559.00	9400.00	9400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
51	910039	منزل عمراحمدمهيوب	737088954	\N	عقبة	202008285783	39	1	449.00	452.00	5200.00	5200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
53	910032	ديني دحان.محطة عقبة	771366890	\N	عقبة	202204289650	41	1	139.00	139.00	9200.00	9200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
54	910102	منزل محمد الزبيدي	738062237	\N	الحارثي	327325	42	1	1729.00	1754.00	36000.00	36000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
55	910519	محمد احمد محمود طاهر	736508006	\N	بقالة عقبة ج الجامع	202003038624	42	1	1580.00	1580.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
56	910523	مروان محمد بجاش	770153175	\N	عقبة ج الجامع	202508006551	42	1	67.00	67.00	4400.00	4400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
57	910293	منزل ناجح عبدالله محمدهراش	737461986	\N	عقبة جوار الفرن	2088277131	43	1	227.00	227.00	9100.00	9100.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
58	910260	عمرمحمد عبدالله حزام	714701653	\N	عقبةجوارناجح	202310068966	44	1	440.00	460.00	29000.00	29000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
59	910522	يحيئ محمد ناجي حسام	777784454	\N	عقبة ج ناجح	202508007220	45	1	13.00	13.00	11000.00	11000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
60	910027	منزل وليد الهمداني	739674447	\N	عقبة	22009065166	46	1	398.00	402.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
61	910331	منزل اصيل عبدالمومن الصبري	734715400	\N	عقبة جار بلال الغنام	202408096439	47	1	130.00	130.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
62	910356	منزل جديس محمد علي المحلوي	777451051	\N	عقبةج جامع التقوئ	241016060884	47	1	493.00	513.00	29000.00	29000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
63	910423	منزل محمد احمدسعيدنصاري	737625840	\N	عقبةجوار جديس	202409049360	48	1	238.00	238.00	4400.00	4400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
64	910564	محمد عبدة صلاح بجاش	733408020	\N	عقبة ج مصطفئ عبدةبجاش	250900102498	49	1	1.00	2.00	3400.00	3400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
65	910355	منزل مامون يحيئ عبدالله محمد الابي	773193232	\N	عقبة جوار جامع التقوئ	202409016476	50	1	104.00	104.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
66	910352	منزل مصطفئ عبدة صلاح بجاش	774949202	\N	عقبة جوار جامع التقوئ	202409034712	51	1	238.00	246.00	12200.00	12200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
67	910024	منزل فارس علي عبدالمجيدالدبعي	734137110	\N	عقبة ج جامع التقوى	214254	52	1	273.00	278.00	8000.00	8000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
68	910023	منزل تمام منصورمحمد الفاتش	771435180	\N	عقبةج جامع التقوى	215563	54	1	324.00	329.00	8000.00	8000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
69	910021	يوسف المخلافي ج مسجد التقوى	733502821	\N	الخزانات	201905008582	55	1	585.00	592.00	10800.00	10800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
71	910247	منزل حاتم محمد احمد محمد	734926699	\N	عقبة ج فوادالمليكي	202409028591	57	1	66.00	70.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
72	910020	منزل فواد المليكي	777556899	\N	عقبة	22009079753	58	1	458.00	465.00	10800.00	10800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
73	910561	فائز شبكة السعيد	770273486	\N	عقبة ج فوادالمليكي	202008271197	58	1	616.00	648.00	45800.00	45800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
74	910018	منزل ذي يزن	739493871	\N	عقبة	20200280066	59	1	885.00	900.00	22000.00	22000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
76	910017	منير سرحان محمد	777123124	\N	جواروليدالهمداني	202204317601	61	1	168.00	172.00	7600.00	7600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
77	910013	منزل عبدالرحمن قاسم	783270260	\N	صنعاء	910013	62	1	112.00	112.00	28000.00	28000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
78	910309	منزل الصلوي ج الماطور	783270260	\N	فوق بيت نزار هائل	910309	63	1	330.00	337.00	39600.00	39600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
79	910556	جارنا محمد الزبيدي	783270260	\N	جوار المولد	910556	64	1	264.00	264.00	71600.00	71600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
80	910043	بقالةبسام يحيئ	783270260	\N	الخزانات	22003029263	65	1	589.00	589.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
81	910395	منزل إسماعيل ج المستهلك	+967737858686	\N	الخزانات ج المستهلك	241016095128	67	1	83.00	88.00	8200.00	8200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
82	910343	منزل ماجد علي حسن محمد	779516487	\N	الخزانات ج بقالة المستهلك	202408080826	68	1	239.00	239.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
83	910058	كندم الزبيدي	738062237	\N	الخزانات	257335	69	1	4016.00	4107.00	128400.00	128400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
84	910441	شهاب سعيد قائد سلطان	776690044	\N	الخزانات مقابل المشروع	241016068454	70	1	134.00	149.00	22000.00	22000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
85	910540	أسامة محطة الغاز	783270260	\N	الخزانات مدرسة الثلاياء	202210201407	70	1	1174.00	1174.00	19600.00	19600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
86	910565	محمد الزبيدي لحام	738062237	\N	كندم الزبيدي	202302028300	70	1	851.00	851.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
87	910057	مدرسة الثلاياء/طلال الفهيدي	775624241	\N	الخزانات	219142	71	1	627.00	645.00	26200.00	26200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
88	910455	علي عبدالله قائدالشوافي	735271027	\N	الخزانات ج إسماعيل	202303220673	72	1	356.00	370.00	42300.00	42300.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
89	910477	عبدالمولئ احمد عبدالفتاح المنيفي	777752106	\N	الخزانات ج المستهلك	250900006653	72	1	44.00	48.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
90	910041	وائل ثابت للخياطة	735036021	\N	العسكري	3034038	73	1	566.00	579.00	19200.00	19200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
91	910446	جميل محمد علي العبد	730873035	\N	الخزانات ج المستهلك	202401044088	74	1	286.00	295.00	13600.00	13600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
92	910468	نصر عمار احمدالثوبة	783270260	\N	الخزانات ج المستهلك	241128101399	74	1	48.00	48.00	45600.00	45600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
93	910040	منزل اكرم محمدعبدالله الراسني	730613351	\N	العسكري ج الضالعي	2304151626	75	1	132.00	135.00	9500.00	9500.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
94	910530	انس منير عبدالحافظ الهتاري	778882274	\N	العسكري ج وائل الخياط	202305217684	75	1	389.00	389.00	1200.00	1200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
95	910275	منزل محمدعبدالله احمد التبعي	774627557	\N	العسكري ج وائل الخياط	202401011615	76	1	340.00	347.00	10800.00	10800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
97	910521	اكرم قائد احمد الاعجم	775599558	\N	العسكري ج التبعي	202508006876	76	1	145.00	156.00	37400.00	37400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
98	910300	منزل حمزة عبدالمغني الصلاحي	770600465	\N	العسكري ج جامع السلام	910300	77	1	907.00	925.00	622900.00	622900.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
99	910531	عرفات اللهبي	774106774	\N	العسكري ج رضا الهتاري	202303090303	77	1	312.00	327.00	30000.00	30000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
100	910279	منزل عبدالجبار محمد عبدالفتاح الهتاري 1	778848182	\N	العسكري ج جامع السلام	202408080833	78	1	1322.00	1337.00	27600.00	27600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
101	910280	منزل عبدالجبار محمد عبدالفتاح الهتاري 2	733502350	\N	العسكري ج جامع السلام	202408080625	79	1	1614.00	1614.00	154600.00	154600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
102	910044	بوفية عبدالرحمن عبدة إسماعيل	730114142	\N	بوفية الخزانات	202401010771	80	1	191.00	197.00	16000.00	16000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
103	910045	بقالة ياسين محمد العريقي	783270260	\N	مقابل جامع الحميري	214033	81	1	249.00	249.00	25600.00	25600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
104	910303	منزل مياس هائل سعيد	783270260	\N	الخزانات ج جامع الحميري	20180664004	81	1	110.00	110.00	2000.00	2000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
105	910046	جامع الحميري	783270260	\N	صنعاء	202209701898	82	1	421.00	450.00	41600.00	41600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
106	910554	فواد الصبيحي السعيدة 1	777238977	\N	مبنا السعيدة	250900086323	82	1	33.00	44.00	16400.00	16400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
107	910555	عبدالحكيم السعيدة 2	739008141	\N	مبنا السعيدة	250900086239	82	1	40.00	48.00	23200.00	23200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
108	910273	منزل ام احمد0عفاف سليم العدني	774271401	\N	الخزانات ج عارف الشميري	2012154163	83	1	93.00	97.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
109	910557	هائل حميد حسن السعيدة 3	714747481	\N	مبنا السعيدة	250900086324	83	1	23.00	28.00	8800.00	8800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
110	910047	منزل  عارف نصرعلي الشميري	777102434	\N	جوار مبنا السعيدة	24010187	84	1	764.00	792.00	40200.00	40200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
111	910048	منزل محمدعبدالجبار دبوان الشميري	772759468	\N	مبنى السعيدة	214783	85	1	138.00	145.00	20200.00	20200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
112	910049	منزل احمد شيبان1	777211848	\N	السعيدة	3021077	86	1	2207.00	2235.00	40200.00	40200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
113	910050	منزل احمد شيبان2	777211848	\N	السعيدة	3035418	87	1	913.00	920.00	11900.00	11900.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
114	910051	منزل احمد شيبان3.	777211848	\N	السعيدة	3040118	88	1	1312.00	1360.00	68200.00	68200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
115	910053	احمد شيبان 4	770119626	\N	السعيدة	202008282038	89	1	532.00	540.00	26800.00	26800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
118	910481	نجيب احمد عبدالرحمن منصر	783270260	\N	بيت الدجاج  ج وسيم قاسم	202508002321	91	1	328.00	347.00	27600.00	27600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
119	910482	حميد علي صالح عبدالرحمن	734655468	\N	بيت الجاج ج وسيم قاسم	202508002546	91	1	37.00	41.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
120	910056	منزل حبيب عبدالغني عبدة علي	730457493	\N	بيت الدجاج	202305217740	92	1	357.00	364.00	11200.00	11200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
121	910054	منزل محمد عبدة عاقل سمير	771909975	\N	السعيد	202009078919	93	1	368.00	375.00	10800.00	10800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
122	910426	منزل علاءثابت مصلح صويلح	774937300	\N	السعيدة ج هاني الشدادي	241016063715	94	1	65.00	65.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
123	910055	منزل هاني محمدمنصورالشدادي	772781914	\N	السعيدةج عاقل سمير	219606	95	1	175.00	179.00	7400.00	7400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
124	910335	منزل عادل محمد الحناني	777639417	\N	الخزانات مقابل بقالة صدام	202408080822	96	1	150.00	150.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
125	910271	منزل احمدعلي محمد الفلي	770506820	\N	الخزانات ج بقالةصدام	2208156215	97	1	234.00	240.00	16000.00	16000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
126	910272	شبكة فارس الربيعي	735816493	\N	الخزانات ج بقالة صدام	142306	98	1	867.00	885.00	74100.00	74100.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
127	910403	منزل امين احمد مدهش الخرباش	734159028	\N	الخزانات جوار الفلي	24010256	99	1	365.00	377.00	17800.00	17800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
129	910552	منزل شكري عون	773835019	\N	الخزانات ج الفلي	241128101399	100	1	109.00	131.00	68000.00	68000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
130	910065	منزل حبيب غالب محمدالجرادي	738567036	\N	الخزانات ج عصام الوجية	219788	101	1	272.00	277.00	30200.00	30200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
131	910063	منزل احمدمحمدعبدالله الغريبي	777004024	\N	الخزانات ج عصام الوجية	2003034231	102	1	1282.00	1308.00	37400.00	37400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
132	910066	بقالة هشام هاشم	735335545	\N	الخزانات	202211102987	103	1	549.00	550.00	2400.00	2400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
133	910070	اسماعيل محمد العزي	777339043	\N	الخزانات	202305218685	104	1	959.00	963.00	9200.00	9200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
134	910069	منزل القاضي علي احمدعكروت	733389897	\N	الخزانات ج الوصابي	234152488	105	1	979.00	1002.00	45400.00	45400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
135	910542	محمد عبدالله احمد الرشيدي	735919469	\N	مقابل بقالة هشام هاشم	202508006690	105	1	47.00	56.00	13600.00	13600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
136	910068	منزل عبدالرحمن محمد الوصابي	771100430	\N	الخزانات ج إسماعيل العزي	214008	106	1	519.00	533.00	20600.00	20600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
137	910067	عبدالقادر طارش الزبيري	778917695	\N	الخزنات.ج.حسامmtn	202008272559	107	1	1045.00	1048.00	57600.00	57600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
138	910492	وليد العمراني	772198216	\N	الخزانات ج الزبيري	202508004773	107	1	149.00	158.00	24400.00	24400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
139	910071	منزل بسام يحي	738638241	\N	الخزانات	202204324206	108	1	308.00	310.00	38900.00	38900.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
140	910072	منزل ياسر محمد بخيت	738136720	\N	الخزانات	202211102983	109	1	1527.00	1560.00	47200.00	47200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
141	910491	ياسر عبدة محمد غالب	735832323	\N	الخزانات ج موقع صالة	202508004263	109	1	86.00	98.00	17800.00	17800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
142	910291	منزل احمد منصور محمدقاسم	733528656	\N	الخزانات ج ياسربخيت	2408083127	110	1	312.00	324.00	17800.00	17800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
146	910294	منزل محمد عبدالله حسن الصلاحي	773336426	\N	الخزانات ج شعيب الصلوي	2408084666	113	1	52.00	52.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
147	910440	مصطفى محمد احمد عقلان	770713488	\N	الخزانات ج شعيب الصلوي	241016068452	114	1	249.00	264.00	22000.00	22000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
148	910432	منزل علي محمد علي الزغروري	96899375169	\N	الخزانات ج شعيب الصلوي	241016069965	115	1	48.00	49.00	2400.00	2400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
149	910537	منزل هاشم	735056847	\N	الحارثي ج شائف المخلافي	202008275485	115	1	97.00	98.00	2400.00	2400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
150	910475	حسام سعيد قائد سلطان	733080794	\N	الخزانات ج موقع يو	202009068733	116	1	609.00	609.00	120000.00	120000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
152	910147	منزل رزق سعد الشبيلي	775124899	\N	الخزانات	201911061976	117	1	56.00	58.00	3800.00	3800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
153	910545	منزل علي شبيل	734857639	\N	الخزانات ج رزق سعد	2018 0662881	117	1	365.00	367.00	21000.00	21000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
154	910292	صلاح عبدالولي فضيل	734969033	\N	الخزانات ج رزق سعد	2408080635	118	1	121.00	124.00	5600.00	5600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
155	910448	منزل مصعب سعيد سيف منصر	739933321	\N	الخزانات ج منزل هاشم	241016064898	118	1	95.00	99.00	6900.00	6900.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
156	910471	اكرم عبدالسلام قاسم المحياء	730014513	\N	الحارثي ج الدكتور مراد	202310052142	118	1	159.00	172.00	20200.00	20200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
157	910372	منزل ايمن الزواحي	771055503	\N	الخزانات ج فضل الشعبي	241016080683	119	1	279.00	285.00	10000.00	10000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
158	910064	منزل حسام عبدالباسط علي مجلي	966543623197	\N	الحارثي جوار الشدادي	250100003315	120	1	252.00	269.00	24800.00	24800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
159	910080	منزل حمزة عبدة عبدالله الحبوري	734308487	\N	الخزانات ج الشدادي	215054	121	1	232.00	239.00	12400.00	12400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
160	910078	منزل الدكتور مراد ج الزواحي	770780828	\N	الحارثي	215178	122	1	443.00	458.00	22400.00	22400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
161	910079	منزل الشدادي	735748625	\N	الخزانات ج الزواحي	215575	123	1	255.00	263.00	12200.00	12200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
162	910381	منزل الدكتوريحيى صالح المذحجي	779179877	\N	الحارثي ج عمارةالزواحي	202508008649	124	1	144.00	160.00	24000.00	24000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
163	910405	مشترك 910405		\N	صنعاء	910405	125	1	685.00	685.00	3000.00	3000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
164	910373	منزل عبدالوارث علي محمدسيف الراعي	783270260	\N	الحارثي ج الزواحي	241016080691	126	1	427.00	430.00	5200.00	5200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
165	910081	منزل الزواحي عبدالله المخلافي	715238579	\N	الحارثي	219442	127	1	286.00	296.00	16000.00	16000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
166	910082	منزل فهد صالح العنسي	730356002	\N	الحارثي	219148	128	1	345.00	352.00	13200.00	13200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
167	910348	منزل فكيرعلي المعمري	738334960	\N	الحارثي ج منظمة كير	202408099259	129	1	142.00	147.00	8000.00	8000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
168	910073	مشترك 910073		\N	صنعاء	910073	130	1	436.00	436.00	3000.00	3000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
170	910084	محطةالسلام احمد السعودي	733114741	\N	محطة السلام الحارثي	214240	132	1	865.00	879.00	20600.00	20600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
171	910083	بقالة الفتح رمزي عيسئ	736154845	\N	بقالة الفتح جامع الحارثي	218972	133	1	1143.00	1147.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
172	910086	جامع الحارثي	783270260	\N	الحارثي	3034496	134	1	1064.00	1064.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
173	910365	منزل لؤي عبدالحكيم سعيد العبسي	739134140	\N	الحارثي ج عبدة دبوان	202005096380	135	1	862.00	868.00	21600.00	21600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
174	910087	منزل عبدة دبوان	738827163	\N	الحارثي	22008278483	136	1	958.00	995.00	56000.00	56000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
175	910092	منزل سعيدمحمد سعد	739425205	\N	الحارثي	202305216719	137	1	230.00	240.00	15000.00	15000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
176	910090	منزل مبارك عبدة قاسم	736907897	\N	الحارثي	202303084793	138	1	333.00	342.00	14000.00	14000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
177	910089	منزل فكري منصور الفتيني	773343490	\N	الحارثي ج الكوافير	219725	139	1	128.00	135.00	14400.00	14400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
178	910091	منزل معاذ عبدة قاسم احمد	730513159	\N	الحارثي ج الكوافير	220659	140	1	267.00	272.00	10000.00	10000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
179	910452	وسيم منصور صالح الفتيني	738874150	\N	الحارثي ج رجائي	250100059770	140	1	44.00	48.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
180	910088	منزل رجائي فتيني	774405595	\N	الحارثي ج سعيد سعد	219111	141	1	76.00	79.00	5200.00	5200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
181	910384	منزل احمد محمد العميسي	777064593	\N	الحارثي ج الكوافير	241016080056	142	1	111.00	114.00	5200.00	5200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
182	910093	كوافير ام عمر	730513159	\N	الحارثي	9076421	143	1	417.00	419.00	3800.00	3800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
183	910276	منزل المهندس وثيق الاغبري	735874968	\N	الحارثي خلف الجامع	202401011605	144	1	200.00	200.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
184	910404	مشترك 910404		\N	صنعاء	910404	145	1	238.00	238.00	16800.00	16800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
185	910183	عدادصالة	783270260	\N	الحارثي ج وثيق الاغبري	202011317480	146	1	3202.00	3373.00	240400.00	240400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
186	910495	نصرالدين عبدة محمدعلي	737217487	\N	الحارثي ج عدادصالة	202211102217	146	1	1255.00	1280.00	69200.00	69200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
187	910534	حسين فواد محمد الجلال	735153519	\N	الحارثي ج عدادصالة	202508002042	146	1	29.00	33.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
188	910563	محمد سعيد سعيد الحميري	733122258	\N	الحارثي ج بقالة ريان	250900057179	146	1	4.00	6.00	6200.00	6200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
189	910250	منزل ايمن محمد سعيد	739710031	\N	صالة جوارمخبزصالة	202308014044	147	1	415.00	425.00	18000.00	18000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
190	910420	بقالة جميل محمود احمدعبدالله	736575762	\N	جوارمحطة صالة	202409049342	147	1	971.00	1034.00	92200.00	92200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
191	910506	شهاب الدين يحيئ/مخبزصالة	737196423	\N	صالةج ايمن محمد سعيد	202508003707	147	1	107.00	116.00	16600.00	16600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
192	910417	اللمنيوم بشيراحمد فارع غانم الطاهري	739913227	\N	اللمنيوم جوارمحطةصالة	202409049358	148	1	196.00	202.00	12400.00	12400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
193	910109	منزل محفوظ محمدعبدالرزاق العامري	783270260	\N	جوار محطة صالة	202011317407	149	1	12.00	12.00	34000.00	34000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
194	910107	منزل محمدعبدالله محمد الجدري	783270260	\N	جوارمحطة صالة	202011348689	150	1	555.00	578.00	66400.00	66400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
195	910567	قائد صالح حزام سند	771350406	\N	التوحيد ج الأبيض	202601001183	150	1	0.00	4.00	7600.00	7600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
196	910060	مجاهد صالح سيف الشعبي	775890769	\N	جوار محطة صالة	202011348789	151	1	180.00	184.00	9600.00	9600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
197	910095	فارس السكريم	735816493	\N	سكريم الحارثي.	202304019282	152	1	447.00	458.00	19400.00	19400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
198	910515	حمزة محمد عبدالله اليوسفي	966500115321	\N	صالة ج جامع الحميرة	202508003125	152	1	310.00	329.00	30600.00	30600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
199	910097	تموينات الإسلامي محمدعبدالله	737959453	\N	الحارثي ج ابويوسف	2401041720	153	1	1017.00	1052.00	50000.00	50000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
200	910098	بقالة ابو يوسف (هاني)	739226082	\N	الحارثي	202302015413	154	1	741.00	741.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
202	910094	مشترك 910094		\N	صنعاء	910094	156	1	401.00	401.00	34200.00	34200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
203	910330	ورشة الملحم بجاش علي احمد	734407358	\N	الحارثي	202408096427	157	1	430.00	440.00	66700.00	66700.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
204	910100	عداد موقع الحارثي	783270260	\N	الحارثي	2003029263	158	1	3987.00	4107.00	169000.00	169000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
205	910389	بقالة عرفات عبدالرحمن علي سعيد	736965428	\N	الحارثي ج اللمنيوم أيوب	250100003383	159	1	480.00	480.00	163000.00	163000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
206	910101	اللمنيوم ايوب	733346363	\N	الحارثي	11072713	160	1	309.00	337.00	40500.00	40500.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
207	910544	ياسين سليم الزبيدي بدل الأمريكي	736130307	\N	الحارثي ج الزبيدي	202508006828	161	1	12.00	19.00	10800.00	10800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
208	910558	نشوان علي عبدالله الجلال	736540793	\N	الحارثي ج الزبيدي	202003029107	161	1	178.00	179.00	2400.00	2400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
209	910353	منزل عبدالرحيم فاضل عبدة بقالة الأصيل	730497408	\N	الحارثي ج مدرسة المعارف	202409033914	163	1	258.00	258.00	2800.00	2800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
210	910375	منزل بسام طائف عبدالله الحكيمي	770945679	\N	العسكريج طلال العامري	202011338765	164	1	251.00	266.00	55100.00	55100.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
211	910105	منزل الدكتور علي البصير	736215386	\N	الحارثي	22009062044	165	1	1516.00	1522.00	9400.00	9400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
212	910106	منزل طلال العامري	775854416	\N	الحارثي	22008277348	166	1	527.00	535.00	12200.00	12200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
213	910430	منزل ذاكر عبدالله احمد الطيب	734701023	\N	العسكري ج بسام الحكيمي	202209701448	167	1	112.00	113.00	17800.00	17800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
214	910104	مدرسة المعارف	733645813	\N	الحارثي	201911059463	168	1	342.00	354.00	30800.00	30800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
215	910397	ورشة لحام عبدالله عبدة غالب	739708153	\N	العسكري ج المعارف	202308026360	169	1	686.00	702.00	67200.00	67200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
216	910061	ورشةلحام عديل احمدعبدة	737088954	\N	الخزانات	202209700595	170	1	712.00	712.00	219600.00	219600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
217	910277	منزل عمادعبدالباسط النظاري1	734972321	\N	العسكري ج الاهرامات	2401045825	171	1	303.00	325.00	31800.00	31800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
218	910393	منزل عبدالقوي احمدعبدالحميد قحطان	736221701	\N	العسكري ج عديل	241016095140	172	1	311.00	319.00	15400.00	15400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
219	910304	منزل عبدالرحمن عبدالواسع الاصبحي	771394589	\N	العسكري ج الملحم عدبل	2408080834	173	1	285.00	286.00	2400.00	2400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
220	910368	منزل عمار عبدالحميدسيف احمدالسرؤري	734437820	\N	العسكري ج الملحم عديل	241016080684	174	1	77.00	86.00	13600.00	13600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
221	910433	منزل مجدي نديم محمدالاغبري	770221533	\N	العسكري جوار عديل	201910023177	175	1	1156.00	1158.00	4400.00	4400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
222	910493	سفيان علي عبالله	777380651	\N	العسكري ج عديل	202308026344	176	1	1479.00	1480.00	2400.00	2400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
223	910386	اسامةاحمد محمدالعباسي	783270260	\N	مسلخ دجاج العسكري	250100003054	177	1	267.00	267.00	53000.00	53000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
224	910354	منزل محمد عبدالعزيزعبدالله عبدالغني	733053030	\N	العسكري ج حلويات الخليج	202011313907	178	1	239.00	246.00	10800.00	10800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
225	910108	صفوان /حلويات الخليج	734432331	\N	العسكري	202308018675	179	1	1559.00	1582.00	33200.00	33200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
226	910110	الشاطر للصرافة العسكري	739267085	\N	العسكري	202408080523	180	1	533.00	533.00	2000.00	2000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
227	910111	محمد هزاع العبسي	783270260	\N	العسكري	20224289559	181	1	199.00	199.00	21000.00	21000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
228	910363	فؤاد العامري	783270260	\N	العسكري مقابل الشاطر لصرافة	202204289559	182	1	752.00	752.00	16000.00	16000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
229	910138	عارف الجرنعي بطاريات	777369764	\N	العسكري	22008089138	183	1	965.00	971.00	22800.00	22800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
230	910484	بسام عبدالرب عقلان السامعي	736588702	\N	جوار تموينات العسكري	250900038042	184	1	253.00	254.00	2400.00	2400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
231	910485	مصطفى محمد عقلان السامعي	783270260	\N	جوار تموينات العسكري	241128103612	184	1	192.00	192.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
232	910379	مطعم أبو خالد	783270260	\N	العسكري	20180663850	185	1	3007.00	3007.00	33600.00	33600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
233	910115	صيدليةالامل /اشرف عبدالعزيزاحمدسرحان	738001149	\N	العسكري	202508006294	186	1	91.00	91.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
234	910447	صيدلية المدينه(سليم علي سيف)	777591499	\N	العسكري	250100045941	186	1	383.00	415.00	45800.00	45800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
235	910116	ياسين صالة المدينة	738347149	\N	العسكري	22009282785	187	1	4576.00	4591.00	22000.00	22000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
236	910514	عبدالرحمن محمدعبدالله السامعي	779077336	\N	جوار تموينات العسكري	202508002096	187	1	48.00	52.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
237	910117	صادق عبدالرب  عقلان السامعي	733729418	\N	العسكري	20220432916	188	1	134.00	134.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
238	910118	تموينات العسكري السامعي	736039878	\N	العسكري	202303082382	189	1	2462.00	2468.00	9400.00	9400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
239	910458	معمل لافا لانتاج الفحم المضغوط	734869062	\N	جوارتموينات العسكري	202407201025	189	1	141.00	143.00	3800.00	3800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
240	910503	طلال قحطان قائد/صيدليةالبركة	783270260	\N	العسكري ج التموينات	202508009794	189	1	184.00	184.00	100000.00	100000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
241	910114	عمادعبدالواسع  البركاني	771208996	\N	العسكري	202204289555	190	1	669.00	678.00	13600.00	13600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
242	910113	معاذعبدالواسع البركاني	771208996	\N	العسكري	202204310678	191	1	3522.00	3543.00	76200.00	76200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
243	910364	منزل عارف البركاني	736888668	\N	العسكري	241016063520	192	1	573.00	574.00	2400.00	2400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
244	910112	احمد عبدالرحمن صالح العمراني	777103503	\N	العسكري ج البركاني	202005104789	193	1	798.00	830.00	51100.00	51100.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
245	910119	بقالة هيثم ناجي محمد مهيوب	734583665	\N	العسكري	202211101983	194	1	1313.00	1318.00	8000.00	8000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
246	910278	منزل عماد عبدالباسط النظاري 2	783270260	\N	العسكري ج بقالةهيثم المحياء	2401010762	195	1	1314.00	1314.00	46700.00	46700.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
247	910559	عمرو عبدالقوي عبدالواسع	733507570	\N	العسكري ج النظاري 2	25090009	195	1	32.00	39.00	10800.00	10800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
248	910120	صيدلية الجودة	774354086	\N	العسكري ج صيدليةالرئاسة	2009067049	196	1	1233.00	1267.00	68600.00	68600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
249	910121	توفيق صيدلية الرئاسة	730541344	\N	العسكري	202303086644	197	1	915.00	947.00	45800.00	45800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
250	910122	مختبرالمدينه مصطفئ	783270260	\N	العسكري	734541545	198	1	1205.00	1217.00	17800.00	17800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
251	910125	عبدالحكيم صيدليةالعميد	777925946	\N	العسكري	201911053105	199	1	664.00	668.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
252	910126	مكتبة سعيد اليوسفي	775002996	\N	العسكري	11053101	200	1	1945.00	1966.00	30400.00	30400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
253	910124	عيادة الحالمة .إسنان	734517488	\N	العسكري	402001163166	201	1	982.00	996.00	20600.00	20600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
254	910346	منزل محمد نعمان احمد مهدي البعداني	770601888	\N	العسكري ج عيادة الحالمة	202408097121	202	1	132.00	134.00	3800.00	3800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
255	910127	فكري احمد السامعي.موادبناء	783270260	\N	العسكري	201911056793	203	1	61.00	65.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
256	910128	بقالة محمد غالب العزعزي	783270260	\N	العسكري	202008273564	204	1	453.00	453.00	2000.00	2000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
257	910129	عبد الملك علي للغسالات	733021502	\N	العسكري	22003029471	205	1	321.00	324.00	8200.00	8200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
258	910130	إبراهيم سالم للقمريات	737617943	\N	العسكري ج الغسالات	214029	206	1	243.00	252.00	14800.00	14800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
259	910131	مشترك 910131	783270260	\N	صنعاء	910131	207	1	252.00	252.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
260	910132	وكالة محمد منصور الشدادي	770232773	\N	العسكري	201905008118	208	1	1070.00	1077.00	10800.00	10800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
261	910133	منزل عبدالرحمن فرحان	730510220	\N	العسكري	4329524	209	1	220.00	225.00	14600.00	14600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
262	910134	استديو الحسني	738255416	\N	العسكري	20195028667	210	1	594.00	605.00	16400.00	16400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
263	910135	صالون عارف للحلاقة	736944090	\N	العسكري	11071450	211	1	572.00	582.00	15400.00	15400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
264	910532	زكريا محمد راوح ناشر	736818071	\N	العسكري ج صالون عارف	219171	211	1	199.00	200.00	2400.00	2400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
265	910136	صالون  الاميراحمد سيف	736807612	\N	العسكري	202305219223	212	1	411.00	411.00	26000.00	26000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
266	910139	بلال  .تموينات الاصيل .	730497408	\N	العسكري	202303222748	213	1	2625.00	2629.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
267	910439	مدرسة أجيال المجد	783270260	\N	العسكري ج بقالة الأصيل	202003021089	214	1	206.00	206.00	20000.00	20000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
268	910137	امجد عبدالمجيد السلامي بطاريات	771165692	\N	العسكري	201911060644	215	1	823.00	827.00	7000.00	7000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
269	910411	مراقب بازرعة	783270260	\N	العسكري بازرعة	202310067121	216	1	2497.00	2513.00	23400.00	23400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
270	910472	امجد فواد احمد سيف ناشر	777024616	\N	العسكري ج احمد راوح	250900007192	216	1	158.00	172.00	20600.00	20600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
271	910474	صادق عبدالحميد صالح الصناعي	739365441	\N	العسكري ج احمدراوح	250900007294	216	1	366.00	381.00	22000.00	22000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
272	910418	منزل رائد احمد محمد العودي	734326008	\N	بازرعة جوار طحنون	2017295152	217	1	176.00	189.00	22600.00	22600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
273	910424	منزل صالح مصلح محمد الحاج	735917281	\N	بازرعة جوار طحنون	202310067121	218	1	90.00	93.00	5400.00	5400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
275	910306	منزل عامر عبدالله علي زيد	783270260	\N	العسكري ج شهدي الاغبري	2408080823	220	1	20.00	20.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
277	910282	منزل شهدي جمال عبدالقادر الاغبري	783270260	\N	العسكري ج بقالة الأصيل	202408080567	221	1	273.00	273.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
278	910305	منزل تغريد نائف	779336847	\N	التموين مقابل المحطة	2408080835	223	1	70.00	72.00	3800.00	3800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
279	910298	منزل ارؤئ احمد صالح الصايدي	739292554	\N	التموين مقابل المحطة	2408092838	224	1	156.00	162.00	9400.00	9400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
280	910141	غسان سليمان علي الضرافي	737600857	\N	التموين	21043	225	1	2393.00	2407.00	20600.00	20600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
281	910498	مطلق عبدالجليل عبدة الاكحلي	777339830	\N	التوحيد ج غسان الظرافي	202508009712	226	1	79.00	79.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
283	910551	محمد الانسي	730970646	\N	التوحيد ج بقالة عمار	202303082629	226	1	341.00	347.00	19000.00	19000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
284	910553	عمر عبدالرحمن الصلوي	739194637	\N	التوحيد ج بقالة عمار	24010813	226	1	464.00	470.00	11400.00	11400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
285	910450	نشوان حميد احمد اليمني	776790334	\N	التوحيد ج الزعيم	202209700178	227	1	74.00	78.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
286	910144	فرم محمدسهيل عبدالله الأمير	734045310	\N	التوحيد	214034	228	1	1110.00	1126.00	70600.00	70600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
287	910145	منزل شهير  احمد علي العذري	734045310	\N	التوحيد ج العاقل	218287	229	1	467.00	485.00	39800.00	39800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
288	910146	منزل مصطفئ الزعيم	783270260	\N	الجحملية	202305216706	230	1	256.00	256.00	15400.00	15400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
289	910148	بقالة غازي عبدالله الصبري	782413463	\N	التوحيدج الجامع	202204324145	231	1	35.00	35.00	8000.00	8000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
290	910332	منزل بدرية عبدالناصرعلي عبدالملك	736161145	\N	التوحيد ج منزل الزعيم	24010187	232	1	401.00	407.00	9400.00	9400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
291	910284	منزل نبيل صالح قائد المهتدي	770740300	\N	التوحيدجوار الجامع	201911012271	233	1	285.00	285.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
292	910416	منزل ايمن صادق محمد الجبري	774668651	\N	التوحيد جوار الزعيم	202409049349	234	1	135.00	140.00	8000.00	8000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
293	910383	منزل بندرمحمداحمد القباطي	773782365	\N	اجوارجامع لتوحيد	241016080843	235	1	122.00	126.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
294	910151	محمد ناجي قائد الدهبلي بدل الأبيض	736540474	\N	التوحيد بدل الأبيض	202003021088	236	1	5245.00	5256.00	16400.00	16400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
295	910149	منزل احمد سعيدالعماد	783079532	\N	التوحيدج الأبيض	215330	237	1	109.00	111.00	6200.00	6200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
296	910152	بقالة إبراهيم الشرعبي	776770338	\N	التوحيد	201911053281	239	1	1053.00	1056.00	32200.00	32200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
297	910476	عبدالحليم مقبل محمد علي	771171765	\N	الجحملية ج بقالة خضرا	250900009064	240	1	223.00	256.00	53600.00	53600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
298	910153	منجرة احمد عبدالله محمد علي	777054205	\N	الجحملية	201911051041	241	1	265.00	266.00	4800.00	4800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
299	910460	مراقب الجحملية السفلئ	783270260	\N	الجحملية ج الزعيم	202408083125	242	1	1496.00	1496.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
300	910156	منزل فؤاد الغضراني	783270260	\N	الجحملية	20191106499	243	1	1301.00	1311.00	15000.00	15000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
301	910155	منزل مطر محمد عبدالباري الفتيح	733615419	\N	الجحملية ج الغضراني	1911067179	244	1	640.00	649.00	13600.00	13600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
302	910413	منزل سعيد محمد محمد عامر	779892602	\N	الجحملية ج فواد الغضراني	2019540	245	1	1056.00	1060.00	13200.00	13200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
303	910157	الزعيم	738304407	\N	الجحملية	3029224	246	1	5880.00	5899.00	45200.00	45200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
304	910159	منزل مجدي امين	730209516	\N	الجحملية	827115	247	1	975.00	993.00	26200.00	26200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
306	910161	ورشة البهلولي	733638177	\N	الجحملية	8273723	249	1	880.00	894.00	20600.00	20600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
307	910162	ثلاجةصدام .ابوعدي	733483388	\N	ثلاجةبوعدي الجحملية	202308026344	250	1	1044.00	1050.00	39800.00	39800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
309	910164	مشترك 910164		\N	صنعاء	910164	252	1	1064.00	1064.00	76600.00	76600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
310	910165	شعير .محمد رفيق	783270260	\N	الجحملية	20180662293	253	1	2400.00	2422.00	31800.00	31800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
311	910496	احمد محمد علي ناصرالبعداني	735820865	\N	الجحملية مقابل الشعير	201903530012	253	1	393.00	399.00	9400.00	9400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
312	910169	فهيم حلويات الصقر	783270260	\N	الجحملية	201903529406	254	1	2266.00	2266.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
313	910490	بقالة الفهيدي /أسامة	770123030	\N	الجحملية ج حلويات الصقر	202508003857	254	1	344.00	388.00	62600.00	62600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
314	910410	منزل احمد نجيب الغشم	739254811	\N	الجحملية ج سعيد غالب	202310069374	255	1	358.00	370.00	23800.00	23800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
315	910160	منزل جمال الصبري	733516473	\N	الجحملية	201911075157	256	1	468.00	476.00	12400.00	12400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
316	910295	منزل عواطف عبدالله ام نشوان العريقي	779095150	\N	الجحمليةج غمدان القباطي	2008280721	257	1	101.00	102.00	4800.00	4800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
317	910371	منزل عرفات محمد محسن الحميضة	776326506	\N	الجحملية ج غمدان القباطي	202011339625	258	1	196.00	196.00	57700.00	57700.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
318	910308	منزل سليم محمد مكرد الشريف	774276336	\N	الجحملية ج غمدان القباطي	2408080827	259	1	285.00	293.00	16800.00	16800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
319	910344	منزل ام جلال عمة جمال الصبري	772521306	\N	الجحملية ج غمدان القباطي	202408097137	260	1	63.00	64.00	2400.00	2400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
320	910489	هدى عبدالله علي سلطان	772034242	\N	الجحملية ج الكابتن	202508008629	260	1	50.00	54.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
321	910509	احمدعبدة /بيت الطاحون	771285559	\N	الجحملية ج الحميضة	202508001530	260	1	72.00	76.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
323	910517	جمال علي محسن الذاري	777159021	\N	الجحملية ج الحميضة	202508005837	261	1	71.00	82.00	16400.00	16400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
324	910520	محسن عبدالله إسماعيل	730716610	\N	الجحملية ج الحميضة	202211102977	261	1	220.00	225.00	8000.00	8000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
325	910168	منزل جميل الحميضة	771732152	\N	الجحملية ج الكابتن	20209068282	262	1	230.00	244.00	52600.00	52600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
326	910429	منزل صباح احمد قاسم الحيمي	734413856	\N	الجحملية ج الكابتن	202209701311	263	1	37.00	39.00	3800.00	3800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
328	910408	محمد المشولي	738762442	\N	الجحملية ج غمدان القباطي	202011336822	265	1	85.00	87.00	3800.00	3800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
329	910419	منزل حسين طلال ردمان القباطي	781362442	\N	الجحملية جوار المشولي	202409049346	266	1	58.00	59.00	2400.00	2400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
330	910163	مشترك 910163		\N	صنعاء	910163	267	1	1651.00	1651.00	149100.00	149100.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
331	910562	مختار عبدة سيف الحميري0بوفية	735227908	\N	الجحملية ج بقالة الفهيدي	250900100685	267	1	63.00	75.00	18500.00	18500.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
332	910170	مشترك 910170		\N	صنعاء	910170	268	1	296.00	296.00	10000.00	10000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
333	910516	صدام امين ثابت عبدالله	777318503	\N	الجحملية ج الكوكباني	202008273118	268	1	718.00	763.00	87600.00	87600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
334	910171	انورالكوكباني.		\N	الجحملية	2019110539620	269	1	103.00	103.00	6200.00	6200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
335	910172	منزل سعيد غالب ناجي	770285285	\N	الجحملية	202009079722	270	1	2162.00	2180.00	26200.00	26200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
336	910434	منزل محمد حسن محمد الشوافي	771419596	\N	الجحملية ج انورالكوكباني	202009180124	271	1	360.00	369.00	39000.00	39000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
337	910173	طرمباة عمرو عبدة حزام	736612929	\N	الجحملية	201905004630	273	1	1560.00	1573.00	19200.00	19200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
338	910175	محلات ماهر الكامل	776947741	\N	الجحملية	3034208	274	1	4402.00	4402.00	345300.00	345300.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
339	910176	اسامة بقالة الخالد	783270260	\N	الجحملية	2019501889	275	1	5564.00	5564.00	3000.00	3000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
340	910174	مركز الجند الطبي	779634272	\N	الجحملية	2019252825	276	1	2018.00	2053.00	52600.00	52600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
341	910177	مشترك 910177		\N	صنعاء	910177	277	1	641.00	641.00	17800.00	17800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
342	910204	مشترك 910204		\N	صنعاء	910204	278	1	1040.00	1040.00	16000.00	16000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
343	910178	بقالةخميس	783270260	\N	الجحملية	202303081520	279	1	269.00	269.00	2000.00	2000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
344	910478	اشرف محمد محمد صالح	772151188	\N	الجحملية ج مركز الجند	202408080537	280	1	218.00	223.00	8000.00	8000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
345	910202	ملحمة فؤاد احمدعلي	737450973	\N	الجحملية	82075761	281	1	1222.00	1230.00	13100.00	13100.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
346	910201	منزل محمدعبدالواحدمحمدالعزب	734389329	\N	الجحمليةج ملمحةفواد	2401010768	282	1	159.00	162.00	6000.00	6000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
347	910179	بوفية /عبدالحكيم ناجي محمد صالح	774917575	\N	الجحملية	11071027	283	1	1096.00	1114.00	26200.00	26200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
348	910180	منزل محمد عبده فرحان	783270260	\N	الجحملية	1102991	284	1	55.00	56.00	4800.00	4800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
349	910181	منزل نجوئ ناجي البعداني	771579980	\N	الجحملية	8284727	285	1	79.00	82.00	5200.00	5200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
350	910360	صالون قطر عبدة مهيوب محمد غالب	730044436	\N	الجحملية ج أبوخليل	241016060882	286	1	86.00	89.00	5200.00	5200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
351	910200	عبدالعزيز المحمدي	774078086	\N	الجحملية ج خالدالانسي	202008271216	287	1	106.00	109.00	5200.00	5200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
352	910199	منزل خالد الانسي	783016868	\N	الجحملية	663802	288	1	54.00	56.00	3800.00	3800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
353	910487	ليبيا عبدالرحمن محمد الاشباطا	737438309	\N	بيت الدجاج ج الكعدة	202508006287	288	1	62.00	68.00	9400.00	9400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
354	910198	عمر عبدالله .موادبناء	774026774	\N	الجحملية	341736	289	1	93.00	94.00	18600.00	18600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
355	910529	نشوان الغثيفي صاحب الغاز	783270260	\N	الجحملية ج عمرمواد البناء	202508008188	289	1	19.00	19.00	21400.00	21400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
356	910182	مشترك 910182		\N	صنعاء	910182	290	1	266.00	266.00	3000.00	3000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
357	910184	معمر اللمنيوم	783270260	\N	الجحملية	11033481	291	1	1450.00	1450.00	22200.00	22200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
358	910185	مشترك 910185		\N	صنعاء	910185	292	1	308.00	308.00	76800.00	76800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
359	910333	طاحون ياسين	777237460	\N	الجحمليةج اللمنيوم معمر	201911032050	293	1	466.00	471.00	72900.00	72900.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
360	910473	ااسياء محمد عبدالله الثور	774906831	\N	الجحملية ج بشار	250900007289	294	1	28.00	28.00	3400.00	3400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
361	910186	فواد مطبعة الثقة	776948949	\N	الجحملية ج بشار	202008140066	295	1	1016.00	1025.00	13600.00	13600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
362	910187	مشترك 910187		\N	صنعاء	910187	296	1	888.00	888.00	128400.00	128400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
363	910388	منزل حامد محمدعابدالشميري	770509593	\N	الجحملية ج الفندم احمد	250100003056	297	1	156.00	163.00	13200.00	13200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
365	910398	منزل عبدة  حزام	771773161	\N	الجحملية جوارمعمر	62053212003	298	1	3387.00	3391.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
366	910197	حازم للسكريم	771003113	\N	الجحملية	20180662028	299	1	1217.00	1221.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
367	910193	منزل عبدالرقيب مرشد	774279789	\N	الجحملية	233334	300	1	1426.00	1435.00	13600.00	13600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
368	910194	ناصر حسين ج اخولاني	736917216	\N	الجحملية ج الخوالاني	202009068827	301	1	227.00	230.00	5200.00	5200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
369	910462	حلويات مامون فهيم عبدة القباطي	774571226	\N	الجحملية ج الانسي	241016069152	302	1	415.00	446.00	44400.00	44400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
370	910195	محمد غالب الخولاني	771224461	\N	الجحملية	202305218690	303	1	300.00	306.00	9400.00	9400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
371	910376	امين عبدالله صالح	774059468	\N	الجحملية ج حازم السكريم	202011339429	304	1	154.00	159.00	8000.00	8000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
372	910369	منزل امجد محمود يوسف راوح	783597575	\N	الجحملية ج حازم السكريم	202012155157	305	1	563.00	563.00	48000.00	48000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
373	910510	هيكل احمد عبدالرحمن زيد الصلوي	777464190	\N	الجحملية ج حازم السكريم	202508003462	305	1	54.00	59.00	8000.00	8000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
374	910192	منزل غالب احمد غالب الخولاني	777239462	\N	الجحملية	219148	306	1	273.00	281.00	12200.00	12200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
375	910299	منزل البنا محمد قاسم غالب المليكي	774153160	\N	الجحمليةج بقالة الربيع	1911052430	307	1	185.00	189.00	7600.00	7600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
376	910351	عامرعبدالغني سعيدمحمدالصبري	781088820	\N	الجحملية ج الكامل	202409034711	308	1	353.00	353.00	5000.00	5000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
377	910188	مكتبة الفرقان	783270260	\N	الجحملية	11056917	309	1	1286.00	1296.00	15000.00	15000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
378	910189	مغسلة التيسيرعلي عبدالله	771270119	\N	الجحمليةج مكتبةالفرقان	214269	310	1	398.00	408.00	15000.00	15000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
379	910526	جمال علي عبدةفاسم العزب	770899345	\N	الجحملية ج مغسلة التيسير	202508006257	310	1	24.00	40.00	24400.00	24400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
380	910190	ورشة حسن الخباني	783270260	\N	الجحملية	201901009565	311	1	785.00	794.00	19000.00	19000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
381	910191	بنشر محمدعبدالله الصرماني	738889950	\N	الجحملية	2019110130	312	1	912.00	914.00	3800.00	3800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
382	910359	نادي الضباط	783270260	\N	الجحملية	241016072391	313	1	88.00	88.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
383	910465	طاحون ياسين 2	777237460	\N	الجحمليةج نادي الضباط	241128103608	313	1	456.00	477.00	46400.00	46400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
384	910497	الفندم يعقوب كتيبة المهام	783270260	\N	الجحمليةج جامع العرضي	202508003482	313	1	188.00	214.00	191300.00	191300.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
385	910377	نادي الضباط	783270260	\N	الجحملية	202003031961	314	1	4780.00	4785.00	8000.00	8000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
386	910400	منزل/محمد يحيى احمد الحلك	772048030	\N	الجحملية جوارالطرمبا	20180662719	315	1	261.00	266.00	8000.00	8000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
387	910301	منزل وضاح عبدالله محمد جابر الابي	779657966	\N	الجحمليةج منجرةعبود	2408092839	316	1	440.00	464.00	61000.00	61000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
388	910205	منجرة عبود الجعفري	736800073	\N	الجحملية	20180661891	318	1	3807.00	3846.00	62300.00	62300.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
389	910207	منجرة الحبوش	776163107	\N	الجحملية	910207	319	1	2091.00	2109.00	26200.00	26200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
390	910206	منجرة صدام	770489600	\N	الجحملية	20145	320	1	598.00	598.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
392	910208	الأمنيوم صالح سعيد	773442550	\N	الجحملية	103856	321	1	526.00	537.00	16400.00	16400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
393	910507	مراد عبدة حسن السورقي	738895678	\N	الجحملية ج الحبوش	202508003660	321	1	149.00	163.00	20600.00	20600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
394	910211	جامع العباس	783270260	\N	الجحملية	202208282774	322	1	134.00	144.00	15000.00	15000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
395	910508	نجيب سلطان حزام السفياني	777018788	\N	الحجحملية ج المنيوم صالح	202508004270	322	1	59.00	65.00	9400.00	9400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
396	910445	عداد مراقب صاله 2	783270260	\N	جوار محطة صاله	201911063183	323	1	2410.00	2410.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
397	910209	محمدقاسم  فرن العربي	783270260	\N	الجحملية	202008277740	324	1	77.00	77.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
398	910210	منزل عبدالملك أحمد دبوان	777143801	\N	الجحملية	202302019345	325	1	170.00	177.00	10800.00	10800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
399	910367	منزل فاطمة صالح احمد محمد العدني	775840489	\N	الجحملية ج بقالة العزي	241016060883	326	1	274.00	281.00	10800.00	10800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
400	910212	منزل نجلاء عبدالله الصوفي	776195345	\N	الجحملية	2019110869993	327	1	999.00	1006.00	10800.00	10800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
401	910213	منزل هائل عبدالله البريهي	739204126	\N	الجحملية	202008272300	328	1	513.00	518.00	8000.00	8000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
402	910406	منزل محمد عبدالله 2	783270260	\N	الجحملية ج هائل البريهي	202003029096	329	1	267.00	268.00	3400.00	3400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
403	910214	عبدالله علي عبدة الشرماني	777163777	\N	جحملية.منجرةبن محمود	202305217499	330	1	207.00	212.00	10000.00	10000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
404	910362	منزل فاروق محمدسيف محمد	771094942	\N	الجحملية ج هائل البريهي	202409034718	331	1	232.00	238.00	9400.00	9400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
406	910421	منزل شوقي عبدالعزيز محمد اليوسفي	+967738614271	\N	الجحملية جوار اليمني	202409029768	333	1	108.00	108.00	2000.00	2000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
407	910431	ماجد يحي محمد الشيباني	+00966533448339	\N	الجحملية ج العزي	241016069971	334	1	44.00	47.00	11800.00	11800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
408	910216	منزل شفيق هزاع	+967777216086	\N	الجحملية	20200285255	335	1	346.00	349.00	5200.00	5200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
409	910215	هائل الامير.ج شفيق	+967772317172	\N	الجحملية.ج شفيق	202008287361	336	1	174.00	174.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
410	910217	نادر عبدالوهاب الشيعاني	+967739334335	\N	جحملية.منجرةبن محمود	202305217491	337	1	581.00	590.00	23600.00	23600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
411	910218	منجرة بن محمود	+967738032980	\N	الجحملية	20180661967	338	1	3484.00	3511.00	38800.00	38800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
412	910219	طلال احمدمهيوب.  لحام	+967733346258	\N	الجحملية	202006288336	340	1	440.00	452.00	52400.00	52400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
413	910220	منزل علي سليمان	+967735898321	\N	الجحملية	202003027659	341	1	775.00	807.00	45800.00	45800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
414	910494	حبيب سعيداحمد عبدالرزاق	+967738009062	\N	الجحملية ج علي سليمان	202407039312	342	1	51.00	53.00	4800.00	4800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
415	910536	بليغ محفوظ محمد احمد العريقي	783270260	\N	الجحملية ج القسم	202508001379	342	1	8.00	9.00	12600.00	12600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
416	910543	جمال جميل محمد زيوار	783270260	\N	الجحملية ج القسم	202508008920	342	1	79.00	88.00	14200.00	14200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
418	910227	منزل سترالله محمد البعداني	771580484	\N	الجحملية ج علي سليمان	20230306652	345	1	321.00	324.00	5200.00	5200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
419	910222	منزل ابتسام علي يحيئ الثلايا	776102209	\N	الجحمليةج علي سليمان	202401010778	346	1	446.00	470.00	34600.00	34600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
420	910223	منزل خالد عبدالله فارع الوتيري	773505536	\N	جحملية.جارمحمدعادل	202305218695	347	1	306.00	322.00	50900.00	50900.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
421	910229	منزل محمد عبدالله	783270260	\N	الجحملية	69900	348	1	542.00	551.00	16100.00	16100.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
422	910232	منزل محمد عبدالملك محمد اليمني	774979999	\N	الجحمليةج معمرحسن	202401010768	348	1	435.00	446.00	16400.00	16400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
423	910228	منزل معمر حسن	733113488	\N	الجحملية	201911064990	349	1	430.00	440.00	15000.00	15000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
424	910541	وائل عبدالرحمن الطيب	737665495	\N	الجحملية ج بقالة العزي	202508001384	349	1	28.00	33.00	8000.00	8000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
425	910231	منزل حسن محمد	733199993	\N	الجحملية	202012093714	350	1	654.00	663.00	13600.00	13600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
426	910230	لطف الرياشي جار منزل حسن	783270260	\N	جوارمنزل حسن	202011347276	351	1	850.00	850.00	84500.00	84500.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
427	910233	منزل ام احمد جمال الصبري	735651510	\N	الجحملية	202011344916	352	1	298.00	307.00	14200.00	14200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
428	910268	منزل خالد محمدعبدالرزاق الزبيدي	783270260	\N	الجحمليةج الحبابي	24010184	353	1	254.00	260.00	9400.00	9400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
429	910234	عبدالملك قائد احمد الصلوي	777240331	\N	النجاح بدل الحبابي	202008272381	354	1	288.00	294.00	11400.00	11400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
430	910235	منزل احمد فاضل الوصابي	770470210	\N	النجاح .الحبابي	202305218693	355	1	524.00	537.00	19200.00	19200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
431	910283	منزل معاذ محمد عبدالله احمد الفراري	715865607	\N	النجاح ج إبراهيم الحكيمي	241016066187	356	1	591.00	591.00	59600.00	59600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
432	910527	عبدالسلام عبدالرحمن الوصابي	772071676	\N	الجحملية بدل الفراري	202508006827	356	1	77.00	84.00	10800.00	10800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
433	910281	منزل ماجد الحاج	777771494	\N	النجاح ج الجندبي	241016072396	357	1	162.00	171.00	13600.00	13600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
434	910499	محمد بلال احمد الحاج	773277987	\N	النجاح ج ماجد الحاج	202508000412	357	1	123.00	136.00	20900.00	20900.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
435	910502	زائد سلطان إسماعيل الحاج	777088853	\N	النجاح ج ماجد الحاج	202508005249	357	1	72.00	76.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
436	910237	منزل ايمن توفيق الاديمي	774129561	\N	النجاح جوارعصام السامعي	202209700129	358	1	75.00	77.00	3800.00	3800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
437	910236	منزل عصام عارف السامعي	775070764	\N	النجاح	202204320140	359	1	783.00	789.00	9400.00	9400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
438	910392	منزل عبدالرقيب/عمارعبدة علي	736977944	\N	النجاح ج عصام السامعي	250100007974	360	1	27.00	27.00	2000.00	2000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
439	910438	عداد لمبات الجندبي	783270260	\N	النجاح ج الجندبي	202011290417	361	1	249.00	249.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
440	910453	منزل جميلة احمد جمال محمد	783270260	\N	النجاح ج السماوي	910453	361	1	154.00	154.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
441	910467	محمد عبدالصمد قاسم حسان	771939854	\N	النجاح ج الجندبي	241016069828	361	1	259.00	268.00	25400.00	25400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
442	910238	منزل احمد حميد(الواء الخامس)	738525689	\N	النجاح	2200285282	362	1	5384.00	5463.00	331500.00	331500.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
443	910242	منزل نبيل قائد محمد فرحان	776845104	\N	جوار مدرسة النجاح	202008271851	363	1	345.00	351.00	9800.00	9800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
444	910240	منزل الدكتورمحمد السماوي	733749100	\N	النجاح	11103000	364	1	1291.00	1298.00	10800.00	10800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
445	910338	منزل امة الغفور السنيدار	776591176	\N	النجاح ج جامع نصار	202408096425	365	1	15.00	15.00	5200.00	5200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
446	910459	محمد صادق عبدالله السروري	735892096	\N	النجاح ج هيفاء	241016069563	366	1	80.00	82.00	3800.00	3800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
447	910150	منزل حمدي محمد جميل	770130489	\N	جوارجامع نصار	202003029400	367	1	510.00	510.00	3400.00	3400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
448	910339	محمد عبدالله قائد علي	777725153	\N	النجاح بعمارةمحمدعبدالله قائد	201910022025	369	1	831.00	838.00	10800.00	10800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
449	910370	منزل سامي محمد سيف فارع الصبري	778993073	\N	النجاح بعمارةمحمدعبدالله قائد	202011349774	370	1	37.00	37.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
450	910266	منزل ايهم خالد العريقي	770274927	\N	النجاح بعمارةمحمدعبدالله قائد	202208156628	371	1	68.00	68.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
452	910394	منزل عبدالقادرعثمان مرتضى عثمان	783270260	\N	النجاح بعمارةمحمدعبدالله قائد	250100003057	373	1	198.00	198.00	8900.00	8900.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
453	910463	وجدان عبدة قاسم محمد	735755625	\N	النجاح ج هيفاء	241128101393	373	1	161.00	176.00	22000.00	22000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
454	910244	منزل صلاح محمد عايض	736060883	\N	النجاح ج جمال2	2009079515	375	1	323.00	332.00	13900.00	13900.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
455	910246	منزل محمدعباس 2	733355418	\N	النجاح ج 14 أكتوبر	219806	376	1	219.00	225.00	9700.00	9700.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
456	910533	احمد عبدالحكيم محمد احمد	774768150	\N	النجاح ج محمدعباس	2509000085704	376	1	65.00	72.00	10800.00	10800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
457	910248	منزل حسام إبراهيم قاىدالقدسي	777171894	\N	النجاح	213974	377	1	494.00	505.00	18200.00	18200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
459	910435	حمد عبدالكريم قائداليوسفي	733039523	\N	الجحملية ج القسم	1806259431	379	1	143.00	144.00	2400.00	2400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
460	910415	منزل سمير احمد قائد علي	736465628	\N	النجاح ج ام ايهم	202409029761	381	1	391.00	408.00	74000.00	74000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
461	910249	عبدالرحمن المليكي	771504958	\N	النجاح ج سميرقايد	2309027085	382	1	406.00	410.00	7000.00	7000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
465	910350	منزل الفندم حمود ثابت	735744162	\N	بيت الدجاج  جارطحنون	202409019544	387	1	1542.00	1568.00	50700.00	50700.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
466	910374	الفندم اسلام	966537187872	\N	بيت الدجاج	910374	388	1	265.00	273.00	99400.00	99400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
467	910380	مخبز المميز تابع (شاهر سيف العامري)	777216400	\N	بيت الدجاج	241016080049	389	1	274.00	279.00	8000.00	8000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
468	910287	منزل هشام محمد علي مقبل	+967773443060	\N	قريش جوار الصنديد	202408083126	390	1	100.00	102.00	3800.00	3800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
469	910256	منزل خالد محمد البعداني	783270260	\N	حارة قريش	22008271173	391	1	892.00	902.00	15000.00	15000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
470	910257	منزل محمدناجي عبدالله البعداني	774252595	\N	حارة قريش	2401010769	392	1	449.00	455.00	9400.00	9400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
471	910436	منزل هشام عبدالملك عبدالسلام	738162516	\N	قريش ج الصنديد	241016082722	393	1	124.00	133.00	13600.00	13600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
472	910259	منزل إشراق محمد اليوسفي	780347422	\N	حارة قريش	22009079664	394	1	664.00	667.00	5200.00	5200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
473	910296	جامع علي عبدالقادرالصبري	770562506	\N	قريش	22003028182	395	1	1856.00	1903.00	126600.00	126600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
474	910262	منزل احمد عبدالله اليوسفي	736849041	\N	حارة قريش	202008275411	396	1	626.00	631.00	8000.00	8000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
475	910347	منزل محمد منصور عبدة اليوسفي	738323388	\N	قريش ج احمد اليوسفي	202408099251	397	1	41.00	43.00	3800.00	3800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
476	910270	منزل طه العزي محمد مصلح	772997060	\N	جوار جامع قريش	214788	398	1	129.00	131.00	3800.00	3800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
477	910505	عبدالملك امين عبدالرحيم الاديمي	775093274	\N	قريش ج البعداني	202508003652	399	1	78.00	82.00	6600.00	6600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
478	910518	عماد نوفل عبدالواهاب اليوسفي	776434508	\N	فريش ج اليوسفي	202409049524	399	1	255.00	264.00	13600.00	13600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
479	910425	منزل خالد عبدالباقي حامد علي	777745680	\N	قريش ج احمدناجي	241016063714	400	1	222.00	231.00	13600.00	13600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
480	910449	منزل احمد ناجي عبدالله البعداني	774252590	\N	قريش ج ناجي البعداني	202401010898	400	1	337.00	346.00	13600.00	13600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
481	910269	رياض محمد حسن	+967780709134	\N	قريش جوارmtn	4063661	401	1	641.00	647.00	12800.00	12800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
482	910264	منزل احمد ناجي موبايل	777004106	\N	حارة قريش	286513	402	1	508.00	527.00	19000.00	19000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
483	910263	العاقل رفيق علي قائد	777604422	\N	حارة قريش	201911069456	403	1	1953.00	1962.00	13600.00	13600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
484	910267	العاقل ماجد ناجي	772283389	\N	حارة قريش	202408080834	404	1	197.00	198.00	2400.00	2400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
485	910357	مشترك 910357		\N	الخزانات	202011336023	406	1	65.00	65.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
486	910470	بلال محمد عبدالله علي	776152177	\N	قريش ج احمد اليوسفي	20590007285	408	1	74.00	75.00	2400.00	2400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
487	910456	ام ميلاد/نورية احمدعبدالغني	773208799	\N	قريش ج الصنديد	250100059761	409	1	6.00	6.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
488	910483	عبدة احمد عبدالله علي البريد	735502651	\N	قريش ج بقالة اليوسفي	2019070475	410	1	93.00	95.00	3800.00	3800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
489	910511	نعيم حسن حسن امير	773443060	\N	قريش ج محرم	202508008646	412	1	2.00	3.00	2400.00	2400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
490	910457	محرم علي سيف سعيد	783270260	\N	قريش ج هشام محمدعلي	250100059772	413	1	8.00	8.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
491	910486	عمرو وجدي عبدة محمد	735591699	\N	قريش جوار محرم	202508002336	413	1	23.00	25.00	3800.00	3800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
492	910451	جامع العرضي	783270260	\N	العرضي	201911047089	426	1	1610.00	1610.00	1000.00	1000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
493	910454	مراقب الجحملية	783270260	\N	الجحملية ج الزعيم	54311	429	1	83081.00	84451.00	1919000.00	1919000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
494	910488	يعقوب المعمري /غاز	783270260	\N	الخزانات مدرسة الثلاياء	202211120279	435	1	918.00	918.00	232400.00	232400.00	Active	f	\N	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03	أغسطس 2
274	910385	منزل احمد راوح ناشر	777425025	\N	العسكري ج بقالة الأصيل	202011349146	219	1	254.00	266.00	17800.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.866063+03	أغسطس 2
276	910504	مامون محمد حمود الشميري	736390975	\N	العسكري ج شهدي الاغبري	202508005464	220	1	266.00	284.00	26200.00	6200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.868514+03	أغسطس 2
70	910022	منزل عزمي قائداحمدج يوسف المخلافي	734716637	\N	جوار مدرسة العز	202003028395	56	1	699.00	722.00	33200.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.870411+03	أغسطس 2
305	910158	عبدالقادر سعيد الدبعي للخياطة	738370233	\N	الجحمليةج الزعيم	202401010772	248	1	284.00	284.00	4800.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.872416+03	أغسطس 2
405	910302	منزل اياد عبدالله ناجي البعداني	771302096	\N	الجحملية ج الحبوش	202409045018	332	1	98.00	103.00	8000.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.87807+03	أغسطس 2
417	910225	قسم الفقيد المغبشي	737088954	\N	قسم الجحملية	202008280581	343	1	1685.00	1691.00	157000.00	57000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.879392+03	أغسطس 2
451	910361	منزل هاني يوسف علي العريقي0يو	739090606	\N	النجاح بعمارةمحمدعبدالله قائد	202008274950	372	1	297.00	301.00	11800.00	800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.880535+03	أغسطس 2
464	910469	يوسف عبدة حسن فاضل	735226671	\N	بيت الدجاج ج الكعدة	202308014026	386	1	341.00	346.00	8000.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.882327+03	أغسطس 2
463	910251	منزل اسامه عادل النياح	730852432	\N	بيت الدجاج	20221111622	385	1	529.00	540.00	16400.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.883559+03	أغسطس 2
308	910422	بقالة الاخوة محمد امين الابقط	736176289	\N	الجحملية جوار ابوعدي	250900102513	251	1	52.00	150.00	212000.00	138190.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.884832+03	أغسطس 2
145	910075	منزل احمدحسن بخيت الزرنوقي	735425479	\N	الخزانات ج شعيب الصلوي	2401010780	112	1	630.00	642.00	17800.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.886007+03	أغسطس 2
151	910524	منزل شائف علي المخلافي	730994618	\N	الخزانات ج  هاشم	202305217727	116	1	186.00	194.00	18800.00	5800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.887179+03	أغسطس 2
143	910546	عبدالباسط معمر عبدالحميد	739519511	\N	الخزانات ج موقع 73	250900092539	110	1	545.00	638.00	131200.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.88909+03	أغسطس 2
327	910166	محمد محسن الكابتن	730989196	\N	الجحملية ج غمدان	202008089869	264	1	189.00	196.00	10800.00	1800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.890424+03	أغسطس 2
322	910334	منزل طلال صادق علي المحياء	733722133	\N	الجحملية ج غمدان القباطي	201911083823	261	1	1127.00	1147.00	59400.00	34390.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.891684+03	أغسطس 2
128	910062	عصام عبد الواسع الوجية	736042531	\N	الخزانات	20200823701	100	1	475.00	482.00	10800.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.892854+03	أغسطس 2
52	910407	منزل مصطفئ نجيب مصطفئ الاديمي	775268423	\N	عقبة جوار محطة ديني	202303081435	40	1	203.00	213.00	28600.00	15000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.896259+03	أغسطس 2
37	910030	منزل حذيفه الاجعش	775042103	\N	عقبة	202308014076	27	1	337.00	343.00	9400.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.89739+03	أغسطس 2
35	910461	محمد علي احمد سيف المعمري	771298426	\N	عقبةج  فاروق عبدالقدوس	202003029209	26	1	220.00	220.00	1000.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.898534+03	أغسطس 2
29	910288	ماجد احمد مسعد الطيار	773485109	\N	عقبة بدل فاروق عبدالقدوس	202408083136	20	1	498.00	512.00	20600.00	600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.8997+03	أغسطس 2
27	910444	صقر مختار عبدالله الشريف	739123770	\N	الخزانات جار بشير العريفي	241016064895	18	1	362.00	367.00	8100.00	1100.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.900924+03	أغسطس 2
24	910437	محمد عبدالله عبدالرحمن احمد	735889404	\N	جوار المهندس عصام	241016068447	17	1	85.00	105.00	29000.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.90206+03	أغسطس 2
21	910525	حسان عبدالكريم هزاع	770523605	\N	الخزانات ج رشيد	20230527604	14	1	169.00	169.00	1000.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.903171+03	أغسطس 2
19	910011	منزل عمار المحسن ج رشيد	772281276	\N	الخزانات	202003034236	13	1	670.00	680.00	35600.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.904869+03	أغسطس 2
17	910358	منزل عبدالحكيم قائد احمد العريقي	733939237	\N	الخزانات ج جنوش	202308026360	11	1	147.00	147.00	1000.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.905928+03	أغسطس 2
15	910009	منزل مجدي الحميدي	734491414	\N	الخزانات ج رشيد	3038225	9	1	1270.00	1284.00	74000.00	23600.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.907669+03	أغسطس 2
10	910501	بدرية صالح حسن الروبي	775183737	\N	الخزانات ج رياض ماوية	202508004795	5	1	23.00	27.00	6600.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.908887+03	أغسطس 2
169	910085	احمد السعودي محطة صالة	736558660	\N	محطةصالة	2401043063	131	1	641.00	641.00	4800.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.910134+03	أغسطس 2
458	910245	منزل حسين طلال الشرعبي	772202924	\N	النجاح	22004328052	378	1	232.00	234.00	9000.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.913896+03	أغسطس 2
144	910074	منزل شعيب الصلوي	736582760	\N	الخزانات	9079505	111	1	687.00	691.00	16000.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.91562+03	أغسطس 2
30	910414	منزل محمد عبداللطيف محمد البعداني	739780283	\N	عقبة ج فاروق عبدالقدوس	202409029780	21	1	159.00	162.00	5200.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.916943+03	أغسطس 2
117	910340	منزل وسيم قاسم احمد سنان	774944131	\N	بيت الدجاج ج حبيب عبدالغني	202408096440	91	1	203.00	205.00	9000.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.918193+03	أغسطس 2
116	910052	منزل خالدمطهر السدمي	733264485	\N	السعيدة	202302019369	90	1	385.00	392.00	10800.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.919578+03	أغسطس 2
96	910500	رضاء منير عبدالحافظ الهتاري	770900693	\N	العسكري ج الهتاري	202508007252	76	1	55.00	62.00	10800.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.921348+03	أغسطس 2
75	910019	منزل محمد عبدالجبارعبدة	770549454	\N	عقبةج ذي يزن	202401010762	60	1	57.00	57.00	1000.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.922422+03	أغسطس 2
42	910034	منزل سمير الصامت	733114459	\N	عقبة	2008287422	31	1	1418.00	1453.00	57800.00	7800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.924349+03	أغسطس 2
282	910528	محمد توفيق سيف سعيدالزايدي	734889129	\N	التموين ج غسان الظرافي	420170161194	226	1	357.00	399.00	163500.00	118000.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.926123+03	أغسطس 2
364	910566	عبدالرحمن محمد عبدة البلاع	737087936	\N	الجحملية ج بشار	250100003588	297	1	243.00	250.00	14600.00	10800.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.927364+03	أغسطس 2
462	910341	منزل أسامة عبدالرحمن مهيوب	730979876	\N	بيت الدجاج0ج ايمن محمدسعيد	202408096436	384	1	237.00	252.00	22000.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.928588+03	أغسطس 2
391	910560	عبدالرحمن احمد محمدعقيل	773245776	\N	الجحملية ج الحبوش	202008272274	320	1	95.00	103.00	12200.00	7200.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.929756+03	أغسطس 2
201	910099	انس محمد مسعد محمد	738364914	\N	الحارثي ج ابويوسف	202303220661	155	1	241.00	244.00	5200.00	0.00	Active	f	\N	2026-08-30 13:00:00+03	2026-09-07 15:00:22.930944+03	أغسطس 2
\.


--
-- Data for Name: invoices; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.invoices (id, invoice_number, customer_id, reading_id, cycle_id, billing_cycle, previous_reading, current_reading, consumption, lost_units, consumption_value, lost_units_value, kwh_price_snapshot, fixed_fee_snapshot, arrears, total_due, total_amount, paid_amount, remaining_amount, due_date, approval_status, status, is_meter_reset, created_at, updated_at) FROM stdin;
1	INV-2026-962	1	1	1	أغسطس 2	56900.00	56900.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
2	INV-2026-963	2	2	1	أغسطس 2	44179.00	44179.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
3	INV-2026-964	3	3	1	أغسطس 2	35078.00	35078.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
4	INV-2026-1378	4	4	1	أغسطس 2	1288.00	1288.00	0.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	2000.00	0.00	2000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
5	INV-2026-965	5	5	1	أغسطس 2	226.00	226.00	0.00	0.00	0.00	0.00	1400.00	1000.00	92000.00	93000.00	93000.00	0.00	93000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
6	INV-2026-966	6	6	1	أغسطس 2	617.00	635.00	18.00	0.00	25200.00	0.00	1400.00	1000.00	0.00	26200.00	26200.00	0.00	26200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
7	INV-2026-967	7	7	1	أغسطس 2	294.00	300.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	600.00	10000.00	10000.00	0.00	10000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
8	INV-2026-968	8	8	1	أغسطس 2	224.00	224.00	0.00	0.00	0.00	0.00	1400.00	1000.00	14400.00	15400.00	15400.00	0.00	15400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
9	INV-2026-969	9	9	1	أغسطس 2	594.00	594.00	0.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	2000.00	0.00	2000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
11	INV-2026-971	11	11	1	أغسطس 2	831.00	833.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	5200.00	9000.00	9000.00	0.00	9000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
12	INV-2026-972	12	12	1	أغسطس 2	716.00	719.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	17400.00	22600.00	22600.00	0.00	22600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
13	INV-2026-973	13	13	1	أغسطس 2	631.00	644.00	13.00	0.00	18200.00	0.00	1400.00	1000.00	207400.00	226600.00	226600.00	0.00	226600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
14	INV-2026-974	14	14	1	أغسطس 2	0.00	0.00	0.00	0.00	0.00	0.00	1400.00	1000.00	18000.00	19000.00	19000.00	0.00	19000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
16	INV-2026-976	16	16	1	أغسطس 2	282.00	301.00	19.00	0.00	26600.00	0.00	1400.00	1000.00	100.00	27700.00	27700.00	0.00	27700.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
18	INV-2026-978	18	18	1	أغسطس 2	166.00	168.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
20	INV-2026-980	20	20	1	أغسطس 2	550.00	553.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	16400.00	21600.00	21600.00	0.00	21600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
22	INV-2026-982	22	22	1	أغسطس 2	127.00	130.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	7900.00	13100.00	13100.00	0.00	13100.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
23	INV-2026-983	23	23	1	أغسطس 2	1118.00	1127.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
25	INV-2026-985	25	25	1	أغسطس 2	96.00	100.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
26	INV-2026-986	26	26	1	أغسطس 2	58.00	59.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	5800.00	8200.00	8200.00	0.00	8200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
28	INV-2026-988	28	28	1	أغسطس 2	1857.00	1896.00	39.00	0.00	54600.00	0.00	1400.00	1000.00	0.00	55600.00	55600.00	0.00	55600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
31	INV-2026-991	31	31	1	أغسطس 2	727.00	752.00	25.00	0.00	35000.00	0.00	1400.00	1000.00	0.00	36000.00	36000.00	0.00	36000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
32	INV-2026-992	32	32	1	أغسطس 2	325.00	332.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
33	INV-2026-993	33	33	1	أغسطس 2	2324.00	2324.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
34	INV-2026-994	34	34	1	أغسطس 2	190.00	196.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
36	INV-2026-996	36	36	1	أغسطس 2	44.00	151.00	107.00	0.00	149800.00	0.00	1400.00	1000.00	0.00	150800.00	150800.00	0.00	150800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
38	INV-2026-997	38	38	1	أغسطس 2	228.00	242.00	14.00	0.00	19600.00	0.00	1400.00	1000.00	0.00	20600.00	20600.00	0.00	20600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
39	INV-2026-999	39	39	1	أغسطس 2	566.00	574.00	8.00	0.00	11200.00	0.00	1400.00	1000.00	0.00	12200.00	12200.00	0.00	12200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
40	INV-2026-1000	40	40	1	أغسطس 2	391.00	391.00	0.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	2000.00	0.00	2000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
41	INV-2026-1001	41	41	1	أغسطس 2	231.00	239.00	8.00	0.00	11200.00	0.00	1400.00	1000.00	69000.00	81200.00	81200.00	0.00	81200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
43	INV-2026-1003	43	43	1	أغسطس 2	74.00	88.00	14.00	0.00	19600.00	0.00	1400.00	1000.00	22000.00	42600.00	42600.00	0.00	42600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
44	INV-2026-1004	44	44	1	أغسطس 2	534.00	534.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
45	INV-2026-1005	45	45	1	أغسطس 2	2462.00	2482.00	20.00	0.00	28000.00	0.00	1400.00	1000.00	0.00	29000.00	29000.00	0.00	29000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
46	INV-2026-1006	46	46	1	أغسطس 2	752.00	775.00	23.00	0.00	32200.00	0.00	1400.00	1000.00	600.00	33800.00	33800.00	0.00	33800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
47	INV-2026-1007	47	47	1	أغسطس 2	156.00	160.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
48	INV-2026-1008	48	48	1	أغسطس 2	1872.00	1953.00	81.00	0.00	113400.00	0.00	1400.00	1000.00	19200.00	133600.00	133600.00	0.00	133600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
49	INV-2026-1009	49	49	1	أغسطس 2	326.00	326.00	0.00	0.00	0.00	0.00	1400.00	1000.00	169900.00	170900.00	170900.00	0.00	170900.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
50	INV-2026-1010	50	50	1	أغسطس 2	553.00	559.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
51	INV-2026-1011	51	51	1	أغسطس 2	449.00	452.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
53	INV-2026-1013	53	53	1	أغسطس 2	139.00	139.00	0.00	0.00	0.00	0.00	1400.00	1000.00	8200.00	9200.00	9200.00	0.00	9200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
54	INV-2026-1015	54	54	1	أغسطس 2	1729.00	1754.00	25.00	0.00	35000.00	0.00	1400.00	1000.00	0.00	36000.00	36000.00	0.00	36000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
55	INV-2026-1016	55	55	1	أغسطس 2	1580.00	1580.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
56	INV-2026-1014	56	56	1	أغسطس 2	67.00	67.00	0.00	0.00	0.00	0.00	1400.00	1000.00	3400.00	4400.00	4400.00	0.00	4400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
57	INV-2026-1017	57	57	1	أغسطس 2	227.00	227.00	0.00	0.00	0.00	0.00	1400.00	1000.00	8100.00	9100.00	9100.00	0.00	9100.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
58	INV-2026-1018	58	58	1	أغسطس 2	440.00	460.00	20.00	0.00	28000.00	0.00	1400.00	1000.00	0.00	29000.00	29000.00	0.00	29000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
59	INV-2026-1019	59	59	1	أغسطس 2	13.00	13.00	0.00	0.00	0.00	0.00	1400.00	1000.00	10000.00	11000.00	11000.00	0.00	11000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
60	INV-2026-1020	60	60	1	أغسطس 2	398.00	402.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
61	INV-2026-1022	61	61	1	أغسطس 2	130.00	130.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
62	INV-2026-1021	62	62	1	أغسطس 2	493.00	513.00	20.00	0.00	28000.00	0.00	1400.00	1000.00	0.00	29000.00	29000.00	0.00	29000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
63	INV-2026-1023	63	63	1	أغسطس 2	238.00	238.00	0.00	0.00	0.00	0.00	1400.00	1000.00	3400.00	4400.00	4400.00	0.00	4400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
64	INV-2026-1024	64	64	1	أغسطس 2	1.00	2.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	1000.00	3400.00	3400.00	0.00	3400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
65	INV-2026-1025	65	65	1	أغسطس 2	104.00	104.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
66	INV-2026-1026	66	66	1	أغسطس 2	238.00	246.00	8.00	0.00	11200.00	0.00	1400.00	1000.00	0.00	12200.00	12200.00	0.00	12200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
67	INV-2026-1027	67	67	1	أغسطس 2	273.00	278.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
68	INV-2026-1028	68	68	1	أغسطس 2	324.00	329.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
69	INV-2026-1029	69	69	1	أغسطس 2	585.00	592.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
71	INV-2026-1031	71	71	1	أغسطس 2	66.00	70.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
72	INV-2026-1032	72	72	1	أغسطس 2	458.00	465.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
73	INV-2026-1033	73	73	1	أغسطس 2	616.00	648.00	32.00	0.00	44800.00	0.00	1400.00	1000.00	0.00	45800.00	45800.00	0.00	45800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
74	INV-2026-1034	74	74	1	أغسطس 2	885.00	900.00	15.00	0.00	21000.00	0.00	1400.00	1000.00	0.00	22000.00	22000.00	0.00	22000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
76	INV-2026-1036	76	76	1	أغسطس 2	168.00	172.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	1000.00	7600.00	7600.00	0.00	7600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
77	INV-2026-1037	77	77	1	أغسطس 2	112.00	112.00	0.00	0.00	0.00	0.00	1400.00	1000.00	27000.00	28000.00	28000.00	0.00	28000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
78	INV-2026-1038	78	78	1	أغسطس 2	330.00	337.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	28800.00	39600.00	39600.00	0.00	39600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
79	INV-2026-1039	79	79	1	أغسطس 2	264.00	264.00	0.00	0.00	0.00	0.00	1400.00	1000.00	70600.00	71600.00	71600.00	0.00	71600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
80	INV-2026-1040	80	80	1	أغسطس 2	589.00	589.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
81	INV-2026-1041	81	81	1	أغسطس 2	83.00	88.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	200.00	8200.00	8200.00	0.00	8200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
82	INV-2026-1042	82	82	1	أغسطس 2	239.00	239.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
83	INV-2026-1043	83	83	1	أغسطس 2	4016.00	4107.00	91.00	0.00	127400.00	0.00	1400.00	1000.00	0.00	128400.00	128400.00	0.00	128400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
84	INV-2026-1044	84	84	1	أغسطس 2	134.00	149.00	15.00	0.00	21000.00	0.00	1400.00	1000.00	0.00	22000.00	22000.00	0.00	22000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
85	INV-2026-1045	85	85	1	أغسطس 2	1174.00	1174.00	0.00	0.00	0.00	0.00	1400.00	1000.00	18600.00	19600.00	19600.00	0.00	19600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
86	INV-2026-1046	86	86	1	أغسطس 2	851.00	851.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
87	INV-2026-1047	87	87	1	أغسطس 2	627.00	645.00	18.00	0.00	25200.00	0.00	1400.00	1000.00	0.00	26200.00	26200.00	0.00	26200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
88	INV-2026-1048	88	88	1	أغسطس 2	356.00	370.00	14.00	0.00	19600.00	0.00	1400.00	1000.00	21700.00	42300.00	42300.00	0.00	42300.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
89	INV-2026-1049	89	89	1	أغسطس 2	44.00	48.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
90	INV-2026-1050	90	90	1	أغسطس 2	566.00	579.00	13.00	0.00	18200.00	0.00	1400.00	1000.00	0.00	19200.00	19200.00	0.00	19200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
91	INV-2026-1051	91	91	1	أغسطس 2	286.00	295.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
92	INV-2026-1052	92	92	1	أغسطس 2	48.00	48.00	0.00	0.00	0.00	0.00	1400.00	1000.00	44600.00	45600.00	45600.00	0.00	45600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
93	INV-2026-1053	93	93	1	أغسطس 2	132.00	135.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	4300.00	9500.00	9500.00	0.00	9500.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
94	INV-2026-1054	94	94	1	أغسطس 2	389.00	389.00	0.00	0.00	0.00	0.00	1400.00	1000.00	200.00	1200.00	1200.00	0.00	1200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
95	INV-2026-1055	95	95	1	أغسطس 2	340.00	347.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
97	INV-2026-1057	97	97	1	أغسطس 2	145.00	156.00	11.00	0.00	15400.00	0.00	1400.00	1000.00	21000.00	37400.00	37400.00	0.00	37400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
98	INV-2026-1058	98	98	1	أغسطس 2	907.00	925.00	18.00	0.00	25200.00	0.00	1400.00	1000.00	596700.00	622900.00	622900.00	0.00	622900.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
99	INV-2026-1059	99	99	1	أغسطس 2	312.00	327.00	15.00	0.00	21000.00	0.00	1400.00	1000.00	8000.00	30000.00	30000.00	0.00	30000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
100	INV-2026-1060	100	100	1	أغسطس 2	1322.00	1337.00	15.00	0.00	21000.00	0.00	1400.00	1000.00	5600.00	27600.00	27600.00	0.00	27600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
101	INV-2026-1061	101	101	1	أغسطس 2	1614.00	1614.00	0.00	0.00	0.00	0.00	1400.00	1000.00	153600.00	154600.00	154600.00	0.00	154600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
102	INV-2026-1062	102	102	1	أغسطس 2	191.00	197.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	6600.00	16000.00	16000.00	0.00	16000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
103	INV-2026-1064	103	103	1	أغسطس 2	249.00	249.00	0.00	0.00	0.00	0.00	1400.00	1000.00	24600.00	25600.00	25600.00	0.00	25600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
104	INV-2026-1063	104	104	1	أغسطس 2	110.00	110.00	0.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	2000.00	0.00	2000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
105	INV-2026-1065	105	105	1	أغسطس 2	421.00	450.00	29.00	0.00	40600.00	0.00	1400.00	1000.00	0.00	41600.00	41600.00	0.00	41600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
106	INV-2026-1066	106	106	1	أغسطس 2	33.00	44.00	11.00	0.00	15400.00	0.00	1400.00	1000.00	0.00	16400.00	16400.00	0.00	16400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
107	INV-2026-1067	107	107	1	أغسطس 2	40.00	48.00	8.00	0.00	11200.00	0.00	1400.00	1000.00	11000.00	23200.00	23200.00	0.00	23200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
108	INV-2026-1068	108	108	1	أغسطس 2	93.00	97.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
109	INV-2026-1069	109	109	1	أغسطس 2	23.00	28.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	800.00	8800.00	8800.00	0.00	8800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
110	INV-2026-1070	110	110	1	أغسطس 2	764.00	792.00	28.00	0.00	39200.00	0.00	1400.00	1000.00	0.00	40200.00	40200.00	0.00	40200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
111	INV-2026-1071	111	111	1	أغسطس 2	138.00	145.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	9400.00	20200.00	20200.00	0.00	20200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
112	INV-2026-1072	112	112	1	أغسطس 2	2207.00	2235.00	28.00	0.00	39200.00	0.00	1400.00	1000.00	0.00	40200.00	40200.00	0.00	40200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
113	INV-2026-1073	113	113	1	أغسطس 2	913.00	920.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	1100.00	11900.00	11900.00	0.00	11900.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
114	INV-2026-1074	114	114	1	أغسطس 2	1312.00	1360.00	48.00	0.00	67200.00	0.00	1400.00	1000.00	0.00	68200.00	68200.00	0.00	68200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
115	INV-2026-1075	115	115	1	أغسطس 2	532.00	540.00	8.00	0.00	11200.00	0.00	1400.00	1000.00	14600.00	26800.00	26800.00	0.00	26800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
118	INV-2026-1078	118	118	1	أغسطس 2	328.00	347.00	19.00	0.00	26600.00	0.00	1400.00	1000.00	0.00	27600.00	27600.00	0.00	27600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
119	INV-2026-1079	119	119	1	أغسطس 2	37.00	41.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
120	INV-2026-1080	120	120	1	أغسطس 2	357.00	364.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	400.00	11200.00	11200.00	0.00	11200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
121	INV-2026-1081	121	121	1	أغسطس 2	368.00	375.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
122	INV-2026-1082	122	122	1	أغسطس 2	65.00	65.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
123	INV-2026-1083	123	123	1	أغسطس 2	175.00	179.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	800.00	7400.00	7400.00	0.00	7400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
124	INV-2026-1084	124	124	1	أغسطس 2	150.00	150.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
125	INV-2026-1085	125	125	1	أغسطس 2	234.00	240.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	6600.00	16000.00	16000.00	0.00	16000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
117	INV-2026-1077	117	117	1	أغسطس 2	203.00	205.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	5200.00	9000.00	9000.00	9000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.917575+03	2026-09-07 15:00:22.917575+03
126	INV-2026-1086	126	126	1	أغسطس 2	867.00	885.00	18.00	0.00	25200.00	0.00	1400.00	1000.00	47900.00	74100.00	74100.00	0.00	74100.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
127	INV-2026-1087	127	127	1	أغسطس 2	365.00	377.00	12.00	0.00	16800.00	0.00	1400.00	1000.00	0.00	17800.00	17800.00	0.00	17800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
129	INV-2026-1089	129	129	1	أغسطس 2	109.00	131.00	22.00	0.00	30800.00	0.00	1400.00	1000.00	36200.00	68000.00	68000.00	0.00	68000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
130	INV-2026-1090	130	130	1	أغسطس 2	272.00	277.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	22200.00	30200.00	30200.00	0.00	30200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
131	INV-2026-1091	131	131	1	أغسطس 2	1282.00	1308.00	26.00	0.00	36400.00	0.00	1400.00	1000.00	0.00	37400.00	37400.00	0.00	37400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
132	INV-2026-1092	132	132	1	أغسطس 2	549.00	550.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
133	INV-2026-1093	133	133	1	أغسطس 2	959.00	963.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	2600.00	9200.00	9200.00	0.00	9200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
134	INV-2026-1094	134	134	1	أغسطس 2	979.00	1002.00	23.00	0.00	32200.00	0.00	1400.00	1000.00	12200.00	45400.00	45400.00	0.00	45400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
135	INV-2026-1095	135	135	1	أغسطس 2	47.00	56.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
136	INV-2026-1096	136	136	1	أغسطس 2	519.00	533.00	14.00	0.00	19600.00	0.00	1400.00	1000.00	0.00	20600.00	20600.00	0.00	20600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
137	INV-2026-1097	137	137	1	أغسطس 2	1045.00	1048.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	52400.00	57600.00	57600.00	0.00	57600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
138	INV-2026-1098	138	138	1	أغسطس 2	149.00	158.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	10800.00	24400.00	24400.00	0.00	24400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
139	INV-2026-1099	139	139	1	أغسطس 2	308.00	310.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	35100.00	38900.00	38900.00	0.00	38900.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
140	INV-2026-1100	140	140	1	أغسطس 2	1527.00	1560.00	33.00	0.00	46200.00	0.00	1400.00	1000.00	0.00	47200.00	47200.00	0.00	47200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
141	INV-2026-1101	141	141	1	أغسطس 2	86.00	98.00	12.00	0.00	16800.00	0.00	1400.00	1000.00	0.00	17800.00	17800.00	0.00	17800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
142	INV-2026-1102	142	142	1	أغسطس 2	312.00	324.00	12.00	0.00	16800.00	0.00	1400.00	1000.00	0.00	17800.00	17800.00	0.00	17800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
146	INV-2026-1106	146	146	1	أغسطس 2	52.00	52.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
147	INV-2026-1107	147	147	1	أغسطس 2	249.00	264.00	15.00	0.00	21000.00	0.00	1400.00	1000.00	0.00	22000.00	22000.00	0.00	22000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
148	INV-2026-1108	148	148	1	أغسطس 2	48.00	49.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
149	INV-2026-1109	149	149	1	أغسطس 2	97.00	98.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
150	INV-2026-1110	150	150	1	أغسطس 2	609.00	609.00	0.00	0.00	0.00	0.00	1400.00	1000.00	119000.00	120000.00	120000.00	0.00	120000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
152	INV-2026-1112	152	152	1	أغسطس 2	56.00	58.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
153	INV-2026-1113	153	153	1	أغسطس 2	365.00	367.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	17200.00	21000.00	21000.00	0.00	21000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
154	INV-2026-1114	154	154	1	أغسطس 2	121.00	124.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	400.00	5600.00	5600.00	0.00	5600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
155	INV-2026-1115	155	155	1	أغسطس 2	95.00	99.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	300.00	6900.00	6900.00	0.00	6900.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
156	INV-2026-1116	156	156	1	أغسطس 2	159.00	172.00	13.00	0.00	18200.00	0.00	1400.00	1000.00	1000.00	20200.00	20200.00	0.00	20200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
157	INV-2026-1117	157	157	1	أغسطس 2	279.00	285.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	600.00	10000.00	10000.00	0.00	10000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
158	INV-2026-1118	158	158	1	أغسطس 2	252.00	269.00	17.00	0.00	23800.00	0.00	1400.00	1000.00	0.00	24800.00	24800.00	0.00	24800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
159	INV-2026-1119	159	159	1	أغسطس 2	232.00	239.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	1600.00	12400.00	12400.00	0.00	12400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
160	INV-2026-1120	160	160	1	أغسطس 2	443.00	458.00	15.00	0.00	21000.00	0.00	1400.00	1000.00	400.00	22400.00	22400.00	0.00	22400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
161	INV-2026-1121	161	161	1	أغسطس 2	255.00	263.00	8.00	0.00	11200.00	0.00	1400.00	1000.00	0.00	12200.00	12200.00	0.00	12200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
162	INV-2026-1122	162	162	1	أغسطس 2	144.00	160.00	16.00	0.00	22400.00	0.00	1400.00	1000.00	600.00	24000.00	24000.00	0.00	24000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
163	INV-2026-1123	163	163	1	أغسطس 2	685.00	685.00	0.00	0.00	0.00	0.00	1400.00	1000.00	2000.00	3000.00	3000.00	0.00	3000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
164	INV-2026-1124	164	164	1	أغسطس 2	427.00	430.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
165	INV-2026-1125	165	165	1	أغسطس 2	286.00	296.00	10.00	0.00	14000.00	0.00	1400.00	1000.00	1000.00	16000.00	16000.00	0.00	16000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
166	INV-2026-1126	166	166	1	أغسطس 2	345.00	352.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	2400.00	13200.00	13200.00	0.00	13200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
167	INV-2026-1127	167	167	1	أغسطس 2	142.00	147.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
168	INV-2026-1128	168	168	1	أغسطس 2	436.00	436.00	0.00	0.00	0.00	0.00	1400.00	1000.00	2000.00	3000.00	3000.00	0.00	3000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
170	INV-2026-1130	170	170	1	أغسطس 2	865.00	879.00	14.00	0.00	19600.00	0.00	1400.00	1000.00	0.00	20600.00	20600.00	0.00	20600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
171	INV-2026-1131	171	171	1	أغسطس 2	1143.00	1147.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
172	INV-2026-1132	172	172	1	أغسطس 2	1064.00	1064.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
173	INV-2026-1133	173	173	1	أغسطس 2	862.00	868.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	12200.00	21600.00	21600.00	0.00	21600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
174	INV-2026-1134	174	174	1	أغسطس 2	958.00	995.00	37.00	0.00	51800.00	0.00	1400.00	1000.00	3200.00	56000.00	56000.00	0.00	56000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
175	INV-2026-1135	175	175	1	أغسطس 2	230.00	240.00	10.00	0.00	14000.00	0.00	1400.00	1000.00	0.00	15000.00	15000.00	0.00	15000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
176	INV-2026-1136	176	176	1	أغسطس 2	333.00	342.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	400.00	14000.00	14000.00	0.00	14000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
177	INV-2026-1137	177	177	1	أغسطس 2	128.00	135.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	3600.00	14400.00	14400.00	0.00	14400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
178	INV-2026-1138	178	178	1	أغسطس 2	267.00	272.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	2000.00	10000.00	10000.00	0.00	10000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
179	INV-2026-1139	179	179	1	أغسطس 2	44.00	48.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
180	INV-2026-1140	180	180	1	أغسطس 2	76.00	79.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
181	INV-2026-1141	181	181	1	أغسطس 2	111.00	114.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
182	INV-2026-1142	182	182	1	أغسطس 2	417.00	419.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
183	INV-2026-1143	183	183	1	أغسطس 2	200.00	200.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
184	INV-2026-1144	184	184	1	أغسطس 2	238.00	238.00	0.00	0.00	0.00	0.00	1400.00	1000.00	15800.00	16800.00	16800.00	0.00	16800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
185	INV-2026-1145	185	185	1	أغسطس 2	3202.00	3373.00	171.00	0.00	239400.00	0.00	1400.00	1000.00	0.00	240400.00	240400.00	0.00	240400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
186	INV-2026-1146	186	186	1	أغسطس 2	1255.00	1280.00	25.00	0.00	35000.00	0.00	1400.00	1000.00	33200.00	69200.00	69200.00	0.00	69200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
187	INV-2026-1147	187	187	1	أغسطس 2	29.00	33.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
188	INV-2026-1148	188	188	1	أغسطس 2	4.00	6.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	2400.00	6200.00	6200.00	0.00	6200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
189	INV-2026-1150	189	189	1	أغسطس 2	415.00	425.00	10.00	0.00	14000.00	0.00	1400.00	1000.00	3000.00	18000.00	18000.00	0.00	18000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
190	INV-2026-1149	190	190	1	أغسطس 2	971.00	1034.00	63.00	0.00	88200.00	0.00	1400.00	1000.00	3000.00	92200.00	92200.00	0.00	92200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
191	INV-2026-1151	191	191	1	أغسطس 2	107.00	116.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	3000.00	16600.00	16600.00	0.00	16600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
192	INV-2026-1152	192	192	1	أغسطس 2	196.00	202.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	3000.00	12400.00	12400.00	0.00	12400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
193	INV-2026-1153	193	193	1	أغسطس 2	12.00	12.00	0.00	0.00	0.00	0.00	1400.00	1000.00	33000.00	34000.00	34000.00	0.00	34000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
194	INV-2026-1154	194	194	1	أغسطس 2	555.00	578.00	23.00	0.00	32200.00	0.00	1400.00	1000.00	33200.00	66400.00	66400.00	0.00	66400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
195	INV-2026-1155	195	195	1	أغسطس 2	0.00	4.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	1000.00	7600.00	7600.00	0.00	7600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
196	INV-2026-1156	196	196	1	أغسطس 2	180.00	184.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	3000.00	9600.00	9600.00	0.00	9600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
197	INV-2026-1157	197	197	1	أغسطس 2	447.00	458.00	11.00	0.00	15400.00	0.00	1400.00	1000.00	3000.00	19400.00	19400.00	0.00	19400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
198	INV-2026-1158	198	198	1	أغسطس 2	310.00	329.00	19.00	0.00	26600.00	0.00	1400.00	1000.00	3000.00	30600.00	30600.00	0.00	30600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
199	INV-2026-1159	199	199	1	أغسطس 2	1017.00	1052.00	35.00	0.00	49000.00	0.00	1400.00	1000.00	0.00	50000.00	50000.00	0.00	50000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
200	INV-2026-1160	200	200	1	أغسطس 2	741.00	741.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
202	INV-2026-1162	202	202	1	أغسطس 2	401.00	401.00	0.00	0.00	0.00	0.00	1400.00	1000.00	33200.00	34200.00	34200.00	0.00	34200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
203	INV-2026-1163	203	203	1	أغسطس 2	430.00	440.00	10.00	0.00	28000.00	0.00	2800.00	1000.00	37700.00	66700.00	66700.00	0.00	66700.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
204	INV-2026-1164	204	204	1	أغسطس 2	3987.00	4107.00	120.00	0.00	168000.00	0.00	1400.00	1000.00	0.00	169000.00	169000.00	0.00	169000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
205	INV-2026-1165	205	205	1	أغسطس 2	480.00	480.00	0.00	0.00	0.00	0.00	1400.00	1000.00	162000.00	163000.00	163000.00	0.00	163000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
206	INV-2026-1166	206	206	1	أغسطس 2	309.00	337.00	28.00	0.00	39200.00	0.00	1400.00	1000.00	300.00	40500.00	40500.00	0.00	40500.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
207	INV-2026-1167	207	207	1	أغسطس 2	12.00	19.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
208	INV-2026-1168	208	208	1	أغسطس 2	178.00	179.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
209	INV-2026-1169	209	209	1	أغسطس 2	258.00	258.00	0.00	0.00	0.00	0.00	1400.00	1000.00	1800.00	2800.00	2800.00	0.00	2800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
210	INV-2026-1170	210	210	1	أغسطس 2	251.00	266.00	15.00	0.00	21000.00	0.00	1400.00	1000.00	33100.00	55100.00	55100.00	0.00	55100.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
211	INV-2026-1171	211	211	1	أغسطس 2	1516.00	1522.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
212	INV-2026-1172	212	212	1	أغسطس 2	527.00	535.00	8.00	0.00	11200.00	0.00	1400.00	1000.00	0.00	12200.00	12200.00	0.00	12200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
213	INV-2026-1173	213	213	1	أغسطس 2	112.00	113.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	15400.00	17800.00	17800.00	0.00	17800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
214	INV-2026-1174	214	214	1	أغسطس 2	342.00	354.00	12.00	0.00	16800.00	0.00	1400.00	1000.00	13000.00	30800.00	30800.00	0.00	30800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
215	INV-2026-1175	215	215	1	أغسطس 2	686.00	702.00	16.00	0.00	44800.00	0.00	2800.00	1000.00	21400.00	67200.00	67200.00	0.00	67200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
216	INV-2026-1176	216	216	1	أغسطس 2	712.00	712.00	0.00	0.00	0.00	0.00	1400.00	1000.00	218600.00	219600.00	219600.00	0.00	219600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
217	INV-2026-1177	217	217	1	أغسطس 2	303.00	325.00	22.00	0.00	30800.00	0.00	1400.00	1000.00	0.00	31800.00	31800.00	0.00	31800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
218	INV-2026-1178	218	218	1	أغسطس 2	311.00	319.00	8.00	0.00	11200.00	0.00	1400.00	1000.00	3200.00	15400.00	15400.00	0.00	15400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
219	INV-2026-1179	219	219	1	أغسطس 2	285.00	286.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
220	INV-2026-1180	220	220	1	أغسطس 2	77.00	86.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
221	INV-2026-1181	221	221	1	أغسطس 2	1156.00	1158.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	600.00	4400.00	4400.00	0.00	4400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
222	INV-2026-1182	222	222	1	أغسطس 2	1479.00	1480.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
223	INV-2026-1183	223	223	1	أغسطس 2	267.00	267.00	0.00	0.00	0.00	0.00	1400.00	1000.00	52000.00	53000.00	53000.00	0.00	53000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
224	INV-2026-1184	224	224	1	أغسطس 2	239.00	246.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
225	INV-2026-1185	225	225	1	أغسطس 2	1559.00	1582.00	23.00	0.00	32200.00	0.00	1400.00	1000.00	0.00	33200.00	33200.00	0.00	33200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
226	INV-2026-1186	226	226	1	أغسطس 2	533.00	533.00	0.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	2000.00	0.00	2000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
227	INV-2026-1187	227	227	1	أغسطس 2	199.00	199.00	0.00	0.00	0.00	0.00	1400.00	1000.00	20000.00	21000.00	21000.00	0.00	21000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
228	INV-2026-1188	228	228	1	أغسطس 2	752.00	752.00	0.00	0.00	0.00	0.00	1400.00	1000.00	15000.00	16000.00	16000.00	0.00	16000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
229	INV-2026-1189	229	229	1	أغسطس 2	965.00	971.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	13400.00	22800.00	22800.00	0.00	22800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
230	INV-2026-1190	230	230	1	أغسطس 2	253.00	254.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
231	INV-2026-1191	231	231	1	أغسطس 2	192.00	192.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
232	INV-2026-1192	232	232	1	أغسطس 2	3007.00	3007.00	0.00	0.00	0.00	0.00	1400.00	1000.00	32600.00	33600.00	33600.00	0.00	33600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
233	INV-2026-1193	233	233	1	أغسطس 2	91.00	91.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
234	INV-2026-1194	234	234	1	أغسطس 2	383.00	415.00	32.00	0.00	44800.00	0.00	1400.00	1000.00	0.00	45800.00	45800.00	0.00	45800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
235	INV-2026-1195	235	235	1	أغسطس 2	4576.00	4591.00	15.00	0.00	21000.00	0.00	1400.00	1000.00	0.00	22000.00	22000.00	0.00	22000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
236	INV-2026-1196	236	236	1	أغسطس 2	48.00	52.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
237	INV-2026-1197	237	237	1	أغسطس 2	134.00	134.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
238	INV-2026-1198	238	238	1	أغسطس 2	2462.00	2468.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
239	INV-2026-1199	239	239	1	أغسطس 2	141.00	143.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
240	INV-2026-1200	240	240	1	أغسطس 2	184.00	184.00	0.00	0.00	0.00	0.00	1400.00	1000.00	99000.00	100000.00	100000.00	0.00	100000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
241	INV-2026-1201	241	241	1	أغسطس 2	669.00	678.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
242	INV-2026-1202	242	242	1	أغسطس 2	3522.00	3543.00	21.00	0.00	29400.00	0.00	1400.00	1000.00	45800.00	76200.00	76200.00	0.00	76200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
243	INV-2026-1203	243	243	1	أغسطس 2	573.00	574.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
244	INV-2026-1204	244	244	1	أغسطس 2	798.00	830.00	32.00	0.00	44800.00	0.00	1400.00	1000.00	5300.00	51100.00	51100.00	0.00	51100.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
245	INV-2026-1205	245	245	1	أغسطس 2	1313.00	1318.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
246	INV-2026-1206	246	246	1	أغسطس 2	1314.00	1314.00	0.00	0.00	0.00	0.00	1400.00	1000.00	45700.00	46700.00	46700.00	0.00	46700.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
247	INV-2026-1207	247	247	1	أغسطس 2	32.00	39.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
248	INV-2026-1208	248	248	1	أغسطس 2	1233.00	1267.00	34.00	0.00	47600.00	0.00	1400.00	1000.00	20000.00	68600.00	68600.00	0.00	68600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
249	INV-2026-1209	249	249	1	أغسطس 2	915.00	947.00	32.00	0.00	44800.00	0.00	1400.00	1000.00	0.00	45800.00	45800.00	0.00	45800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
250	INV-2026-1210	250	250	1	أغسطس 2	1205.00	1217.00	12.00	0.00	16800.00	0.00	1400.00	1000.00	0.00	17800.00	17800.00	0.00	17800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
251	INV-2026-1211	251	251	1	أغسطس 2	664.00	668.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
252	INV-2026-1212	252	252	1	أغسطس 2	1945.00	1966.00	21.00	0.00	29400.00	0.00	1400.00	1000.00	0.00	30400.00	30400.00	0.00	30400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
253	INV-2026-1213	253	253	1	أغسطس 2	982.00	996.00	14.00	0.00	19600.00	0.00	1400.00	1000.00	0.00	20600.00	20600.00	0.00	20600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
254	INV-2026-1214	254	254	1	أغسطس 2	132.00	134.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
255	INV-2026-1215	255	255	1	أغسطس 2	61.00	65.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
256	INV-2026-1216	256	256	1	أغسطس 2	453.00	453.00	0.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	2000.00	0.00	2000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
257	INV-2026-1217	257	257	1	أغسطس 2	321.00	324.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	3000.00	8200.00	8200.00	0.00	8200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
258	INV-2026-1218	258	258	1	أغسطس 2	243.00	252.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	1200.00	14800.00	14800.00	0.00	14800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
259	INV-2026-1219	259	259	1	أغسطس 2	252.00	252.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
260	INV-2026-1220	260	260	1	أغسطس 2	1070.00	1077.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
261	INV-2026-1221	261	261	1	أغسطس 2	220.00	225.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	6600.00	14600.00	14600.00	0.00	14600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
262	INV-2026-1222	262	262	1	أغسطس 2	594.00	605.00	11.00	0.00	15400.00	0.00	1400.00	1000.00	0.00	16400.00	16400.00	0.00	16400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
263	INV-2026-1223	263	263	1	أغسطس 2	572.00	582.00	10.00	0.00	14000.00	0.00	1400.00	1000.00	400.00	15400.00	15400.00	0.00	15400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
264	INV-2026-1224	264	264	1	أغسطس 2	199.00	200.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
265	INV-2026-1225	265	265	1	أغسطس 2	411.00	411.00	0.00	0.00	0.00	0.00	1400.00	1000.00	25000.00	26000.00	26000.00	0.00	26000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
266	INV-2026-1226	266	266	1	أغسطس 2	2625.00	2629.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
267	INV-2026-1227	267	267	1	أغسطس 2	206.00	206.00	0.00	0.00	0.00	0.00	1400.00	1000.00	19000.00	20000.00	20000.00	0.00	20000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
268	INV-2026-1228	268	268	1	أغسطس 2	823.00	827.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	400.00	7000.00	7000.00	0.00	7000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
269	INV-2026-1229	269	269	1	أغسطس 2	2497.00	2513.00	16.00	0.00	22400.00	0.00	1400.00	1000.00	0.00	23400.00	23400.00	0.00	23400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
270	INV-2026-1230	270	270	1	أغسطس 2	158.00	172.00	14.00	0.00	19600.00	0.00	1400.00	1000.00	0.00	20600.00	20600.00	0.00	20600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
271	INV-2026-1231	271	271	1	أغسطس 2	366.00	381.00	15.00	0.00	21000.00	0.00	1400.00	1000.00	0.00	22000.00	22000.00	0.00	22000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
272	INV-2026-1232	272	272	1	أغسطس 2	176.00	189.00	13.00	0.00	18200.00	0.00	1400.00	1000.00	3400.00	22600.00	22600.00	0.00	22600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
273	INV-2026-1233	273	273	1	أغسطس 2	90.00	93.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	200.00	5400.00	5400.00	0.00	5400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
275	INV-2026-1235	275	275	1	أغسطس 2	20.00	20.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
277	INV-2026-1237	277	277	1	أغسطس 2	273.00	273.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
278	INV-2026-1238	278	278	1	أغسطس 2	70.00	72.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
279	INV-2026-1239	279	279	1	أغسطس 2	156.00	162.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
280	INV-2026-1240	280	280	1	أغسطس 2	2393.00	2407.00	14.00	0.00	19600.00	0.00	1400.00	1000.00	0.00	20600.00	20600.00	0.00	20600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
281	INV-2026-1241	281	281	1	أغسطس 2	79.00	79.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
283	INV-2026-1243	283	283	1	أغسطس 2	341.00	347.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	9600.00	19000.00	19000.00	0.00	19000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
284	INV-2026-1244	284	284	1	أغسطس 2	464.00	470.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	2000.00	11400.00	11400.00	0.00	11400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
285	INV-2026-1245	285	285	1	أغسطس 2	74.00	78.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
286	INV-2026-1246	286	286	1	أغسطس 2	1110.00	1126.00	16.00	0.00	22400.00	0.00	1400.00	1000.00	47200.00	70600.00	70600.00	0.00	70600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
287	INV-2026-1247	287	287	1	أغسطس 2	467.00	485.00	18.00	0.00	25200.00	0.00	1400.00	1000.00	13600.00	39800.00	39800.00	0.00	39800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
288	INV-2026-1248	288	288	1	أغسطس 2	256.00	256.00	0.00	0.00	0.00	0.00	1400.00	1000.00	14400.00	15400.00	15400.00	0.00	15400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
289	INV-2026-1249	289	289	1	أغسطس 2	35.00	35.00	0.00	0.00	0.00	0.00	1400.00	1000.00	7000.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
290	INV-2026-1250	290	290	1	أغسطس 2	401.00	407.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
291	INV-2026-1251	291	291	1	أغسطس 2	285.00	285.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
292	INV-2026-1252	292	292	1	أغسطس 2	135.00	140.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
293	INV-2026-1253	293	293	1	أغسطس 2	122.00	126.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
294	INV-2026-1254	294	294	1	أغسطس 2	5245.00	5256.00	11.00	0.00	15400.00	0.00	1400.00	1000.00	0.00	16400.00	16400.00	0.00	16400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
295	INV-2026-1255	295	295	1	أغسطس 2	109.00	111.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	2400.00	6200.00	6200.00	0.00	6200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
296	INV-2026-1256	296	296	1	أغسطس 2	1053.00	1056.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	27000.00	32200.00	32200.00	0.00	32200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
297	INV-2026-1257	297	297	1	أغسطس 2	223.00	256.00	33.00	0.00	46200.00	0.00	1400.00	1000.00	6400.00	53600.00	53600.00	0.00	53600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
298	INV-2026-1258	298	298	1	أغسطس 2	265.00	266.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	2400.00	4800.00	4800.00	0.00	4800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
299	INV-2026-1259	299	299	1	أغسطس 2	1496.00	1496.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
300	INV-2026-1260	300	300	1	أغسطس 2	1301.00	1311.00	10.00	0.00	14000.00	0.00	1400.00	1000.00	0.00	15000.00	15000.00	0.00	15000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
301	INV-2026-1261	301	301	1	أغسطس 2	640.00	649.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
302	INV-2026-1262	302	302	1	أغسطس 2	1056.00	1060.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	6600.00	13200.00	13200.00	0.00	13200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
303	INV-2026-1263	303	303	1	أغسطس 2	5880.00	5899.00	19.00	0.00	26600.00	0.00	1400.00	1000.00	17600.00	45200.00	45200.00	0.00	45200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
304	INV-2026-1264	304	304	1	أغسطس 2	975.00	993.00	18.00	0.00	25200.00	0.00	1400.00	1000.00	0.00	26200.00	26200.00	0.00	26200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
306	INV-2026-1266	306	306	1	أغسطس 2	880.00	894.00	14.00	0.00	19600.00	0.00	1400.00	1000.00	0.00	20600.00	20600.00	0.00	20600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
307	INV-2026-1267	307	307	1	أغسطس 2	1044.00	1050.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	30400.00	39800.00	39800.00	0.00	39800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
309	INV-2026-1269	309	309	1	أغسطس 2	1064.00	1064.00	0.00	0.00	0.00	0.00	1400.00	1000.00	75600.00	76600.00	76600.00	0.00	76600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
310	INV-2026-1270	310	310	1	أغسطس 2	2400.00	2422.00	22.00	0.00	30800.00	0.00	1400.00	1000.00	0.00	31800.00	31800.00	0.00	31800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
311	INV-2026-1271	311	311	1	أغسطس 2	393.00	399.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
312	INV-2026-1272	312	312	1	أغسطس 2	2266.00	2266.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
313	INV-2026-1273	313	313	1	أغسطس 2	344.00	388.00	44.00	0.00	61600.00	0.00	1400.00	1000.00	0.00	62600.00	62600.00	0.00	62600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
314	INV-2026-1274	314	314	1	أغسطس 2	358.00	370.00	12.00	0.00	16800.00	0.00	1400.00	1000.00	6000.00	23800.00	23800.00	0.00	23800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
315	INV-2026-1275	315	315	1	أغسطس 2	468.00	476.00	8.00	0.00	11200.00	0.00	1400.00	1000.00	200.00	12400.00	12400.00	0.00	12400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
316	INV-2026-1276	316	316	1	أغسطس 2	101.00	102.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	2400.00	4800.00	4800.00	0.00	4800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
317	INV-2026-1277	317	317	1	أغسطس 2	196.00	196.00	0.00	0.00	0.00	0.00	1400.00	1000.00	56700.00	57700.00	57700.00	0.00	57700.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
318	INV-2026-1278	318	318	1	أغسطس 2	285.00	293.00	8.00	0.00	11200.00	0.00	1400.00	1000.00	4600.00	16800.00	16800.00	0.00	16800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
319	INV-2026-1279	319	319	1	أغسطس 2	63.00	64.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
320	INV-2026-1280	320	320	1	أغسطس 2	50.00	54.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
321	INV-2026-1281	321	321	1	أغسطس 2	72.00	76.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
323	INV-2026-1283	323	323	1	أغسطس 2	71.00	82.00	11.00	0.00	15400.00	0.00	1400.00	1000.00	0.00	16400.00	16400.00	0.00	16400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
324	INV-2026-1284	324	324	1	أغسطس 2	220.00	225.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
325	INV-2026-1285	325	325	1	أغسطس 2	230.00	244.00	14.00	0.00	19600.00	0.00	1400.00	1000.00	32000.00	52600.00	52600.00	0.00	52600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
326	INV-2026-1286	326	326	1	أغسطس 2	37.00	39.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
328	INV-2026-1288	328	328	1	أغسطس 2	85.00	87.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
329	INV-2026-1289	329	329	1	أغسطس 2	58.00	59.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
330	INV-2026-1290	330	330	1	أغسطس 2	1651.00	1651.00	0.00	0.00	0.00	0.00	1400.00	1000.00	148100.00	149100.00	149100.00	0.00	149100.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
331	INV-2026-1291	331	331	1	أغسطس 2	63.00	75.00	12.00	0.00	16800.00	0.00	1400.00	1000.00	700.00	18500.00	18500.00	0.00	18500.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
332	INV-2026-1292	332	332	1	أغسطس 2	296.00	296.00	0.00	0.00	0.00	0.00	1400.00	1000.00	9000.00	10000.00	10000.00	0.00	10000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
333	INV-2026-1293	333	333	1	أغسطس 2	718.00	763.00	45.00	0.00	63000.00	0.00	1400.00	1000.00	23600.00	87600.00	87600.00	0.00	87600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
334	INV-2026-1294	334	334	1	أغسطس 2	103.00	103.00	0.00	0.00	0.00	0.00	1400.00	1000.00	5200.00	6200.00	6200.00	0.00	6200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
335	INV-2026-1295	335	335	1	أغسطس 2	2162.00	2180.00	18.00	0.00	25200.00	0.00	1400.00	1000.00	0.00	26200.00	26200.00	0.00	26200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
336	INV-2026-1296	336	336	1	أغسطس 2	360.00	369.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	25400.00	39000.00	39000.00	0.00	39000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
337	INV-2026-1297	337	337	1	أغسطس 2	1560.00	1573.00	13.00	0.00	18200.00	0.00	1400.00	1000.00	0.00	19200.00	19200.00	0.00	19200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
338	INV-2026-1298	338	338	1	أغسطس 2	4402.00	4402.00	0.00	0.00	0.00	0.00	1400.00	1000.00	344300.00	345300.00	345300.00	0.00	345300.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
339	INV-2026-1299	339	339	1	أغسطس 2	5564.00	5564.00	0.00	0.00	0.00	0.00	1400.00	1000.00	2000.00	3000.00	3000.00	0.00	3000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
340	INV-2026-1300	340	340	1	أغسطس 2	2018.00	2053.00	35.00	0.00	49000.00	0.00	1400.00	1000.00	2600.00	52600.00	52600.00	0.00	52600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
341	INV-2026-1301	341	341	1	أغسطس 2	641.00	641.00	0.00	0.00	0.00	0.00	1400.00	1000.00	16800.00	17800.00	17800.00	0.00	17800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
342	INV-2026-1302	342	342	1	أغسطس 2	1040.00	1040.00	0.00	0.00	0.00	0.00	1400.00	1000.00	15000.00	16000.00	16000.00	0.00	16000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
343	INV-2026-1303	343	343	1	أغسطس 2	269.00	269.00	0.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	2000.00	0.00	2000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
344	INV-2026-1304	344	344	1	أغسطس 2	218.00	223.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
345	INV-2026-1305	345	345	1	أغسطس 2	1222.00	1230.00	8.00	0.00	11200.00	0.00	1400.00	1000.00	900.00	13100.00	13100.00	0.00	13100.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
346	INV-2026-1306	346	346	1	أغسطس 2	159.00	162.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	800.00	6000.00	6000.00	0.00	6000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
347	INV-2026-1307	347	347	1	أغسطس 2	1096.00	1114.00	18.00	0.00	25200.00	0.00	1400.00	1000.00	0.00	26200.00	26200.00	0.00	26200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
348	INV-2026-1308	348	348	1	أغسطس 2	55.00	56.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	2400.00	4800.00	4800.00	0.00	4800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
349	INV-2026-1309	349	349	1	أغسطس 2	79.00	82.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
350	INV-2026-1310	350	350	1	أغسطس 2	86.00	89.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
351	INV-2026-1311	351	351	1	أغسطس 2	106.00	109.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
352	INV-2026-1312	352	352	1	أغسطس 2	54.00	56.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
353	INV-2026-1313	353	353	1	أغسطس 2	62.00	68.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
354	INV-2026-1314	354	354	1	أغسطس 2	93.00	94.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	16200.00	18600.00	18600.00	0.00	18600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
355	INV-2026-1315	355	355	1	أغسطس 2	19.00	19.00	0.00	0.00	0.00	0.00	1400.00	1000.00	20400.00	21400.00	21400.00	0.00	21400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
356	INV-2026-1316	356	356	1	أغسطس 2	266.00	266.00	0.00	0.00	0.00	0.00	1400.00	1000.00	2000.00	3000.00	3000.00	0.00	3000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
357	INV-2026-1317	357	357	1	أغسطس 2	1450.00	1450.00	0.00	0.00	0.00	0.00	1400.00	1000.00	21200.00	22200.00	22200.00	0.00	22200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
358	INV-2026-1318	358	358	1	أغسطس 2	308.00	308.00	0.00	0.00	0.00	0.00	1400.00	1000.00	75800.00	76800.00	76800.00	0.00	76800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
359	INV-2026-1319	359	359	1	أغسطس 2	466.00	471.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	64900.00	72900.00	72900.00	0.00	72900.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
360	INV-2026-1320	360	360	1	أغسطس 2	28.00	28.00	0.00	0.00	0.00	0.00	1400.00	1000.00	2400.00	3400.00	3400.00	0.00	3400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
361	INV-2026-1321	361	361	1	أغسطس 2	1016.00	1025.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
362	INV-2026-1322	362	362	1	أغسطس 2	888.00	888.00	0.00	0.00	0.00	0.00	1400.00	1000.00	127400.00	128400.00	128400.00	0.00	128400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
363	INV-2026-1323	363	363	1	أغسطس 2	156.00	163.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	2400.00	13200.00	13200.00	0.00	13200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
365	INV-2026-1325	365	365	1	أغسطس 2	3387.00	3391.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
366	INV-2026-1326	366	366	1	أغسطس 2	1217.00	1221.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
367	INV-2026-1327	367	367	1	أغسطس 2	1426.00	1435.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
368	INV-2026-1328	368	368	1	أغسطس 2	227.00	230.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
369	INV-2026-1329	369	369	1	أغسطس 2	415.00	446.00	31.00	0.00	43400.00	0.00	1400.00	1000.00	0.00	44400.00	44400.00	0.00	44400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
370	INV-2026-1330	370	370	1	أغسطس 2	300.00	306.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
371	INV-2026-1331	371	371	1	أغسطس 2	154.00	159.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
372	INV-2026-1332	372	372	1	أغسطس 2	563.00	563.00	0.00	0.00	0.00	0.00	1400.00	1000.00	47000.00	48000.00	48000.00	0.00	48000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
373	INV-2026-1333	373	373	1	أغسطس 2	54.00	59.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
374	INV-2026-1334	374	374	1	أغسطس 2	273.00	281.00	8.00	0.00	11200.00	0.00	1400.00	1000.00	0.00	12200.00	12200.00	0.00	12200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
375	INV-2026-1335	375	375	1	أغسطس 2	185.00	189.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	1000.00	7600.00	7600.00	0.00	7600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
376	INV-2026-1336	376	376	1	أغسطس 2	353.00	353.00	0.00	0.00	0.00	0.00	1400.00	1000.00	4000.00	5000.00	5000.00	0.00	5000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
377	INV-2026-1337	377	377	1	أغسطس 2	1286.00	1296.00	10.00	0.00	14000.00	0.00	1400.00	1000.00	0.00	15000.00	15000.00	0.00	15000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
378	INV-2026-1338	378	378	1	أغسطس 2	398.00	408.00	10.00	0.00	14000.00	0.00	1400.00	1000.00	0.00	15000.00	15000.00	0.00	15000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
379	INV-2026-1339	379	379	1	أغسطس 2	24.00	40.00	16.00	0.00	22400.00	0.00	1400.00	1000.00	1000.00	24400.00	24400.00	0.00	24400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
380	INV-2026-1340	380	380	1	أغسطس 2	785.00	794.00	9.00	0.00	18000.00	0.00	2000.00	1000.00	0.00	19000.00	19000.00	0.00	19000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
381	INV-2026-1341	381	381	1	أغسطس 2	912.00	914.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
382	INV-2026-1342	382	382	1	أغسطس 2	88.00	88.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
383	INV-2026-1343	383	383	1	أغسطس 2	456.00	477.00	21.00	0.00	29400.00	0.00	1400.00	1000.00	16000.00	46400.00	46400.00	0.00	46400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
384	INV-2026-1344	384	384	1	أغسطس 2	188.00	214.00	26.00	0.00	36400.00	0.00	1400.00	1000.00	153900.00	191300.00	191300.00	0.00	191300.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
385	INV-2026-1345	385	385	1	أغسطس 2	4780.00	4785.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
386	INV-2026-1346	386	386	1	أغسطس 2	261.00	266.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
387	INV-2026-1347	387	387	1	أغسطس 2	440.00	464.00	24.00	0.00	33600.00	0.00	1400.00	1000.00	26400.00	61000.00	61000.00	0.00	61000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
388	INV-2026-1348	388	388	1	أغسطس 2	3807.00	3846.00	39.00	0.00	54600.00	0.00	1400.00	1000.00	6700.00	62300.00	62300.00	0.00	62300.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
389	INV-2026-1349	389	389	1	أغسطس 2	2091.00	2109.00	18.00	0.00	25200.00	0.00	1400.00	1000.00	0.00	26200.00	26200.00	0.00	26200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
390	INV-2026-1350	390	390	1	أغسطس 2	598.00	598.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
392	INV-2026-1352	392	392	1	أغسطس 2	526.00	537.00	11.00	0.00	15400.00	0.00	1400.00	1000.00	0.00	16400.00	16400.00	0.00	16400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
393	INV-2026-1353	393	393	1	أغسطس 2	149.00	163.00	14.00	0.00	19600.00	0.00	1400.00	1000.00	0.00	20600.00	20600.00	0.00	20600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
394	INV-2026-1354	394	394	1	أغسطس 2	134.00	144.00	10.00	0.00	14000.00	0.00	1400.00	1000.00	0.00	15000.00	15000.00	0.00	15000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
395	INV-2026-1355	395	395	1	أغسطس 2	59.00	65.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
396	INV-2026-1356	396	396	1	أغسطس 2	2410.00	2410.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
397	INV-2026-1357	397	397	1	أغسطس 2	77.00	77.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
398	INV-2026-1358	398	398	1	أغسطس 2	170.00	177.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
399	INV-2026-1359	399	399	1	أغسطس 2	274.00	281.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
400	INV-2026-1360	400	400	1	أغسطس 2	999.00	1006.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
401	INV-2026-1361	401	401	1	أغسطس 2	513.00	518.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
402	INV-2026-1362	402	402	1	أغسطس 2	267.00	268.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	1000.00	3400.00	3400.00	0.00	3400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
403	INV-2026-1363	403	403	1	أغسطس 2	207.00	212.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	2000.00	10000.00	10000.00	0.00	10000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
404	INV-2026-1364	404	404	1	أغسطس 2	232.00	238.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
406	INV-2026-1366	406	406	1	أغسطس 2	108.00	108.00	0.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	2000.00	0.00	2000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
407	INV-2026-1367	407	407	1	أغسطس 2	44.00	47.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	6600.00	11800.00	11800.00	0.00	11800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
408	INV-2026-1368	408	408	1	أغسطس 2	346.00	349.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
409	INV-2026-1369	409	409	1	أغسطس 2	174.00	174.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
410	INV-2026-1370	410	410	1	أغسطس 2	581.00	590.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	10000.00	23600.00	23600.00	0.00	23600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
411	INV-2026-1371	411	411	1	أغسطس 2	3484.00	3511.00	27.00	0.00	37800.00	0.00	1400.00	1000.00	0.00	38800.00	38800.00	0.00	38800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
412	INV-2026-1372	412	412	1	أغسطس 2	440.00	452.00	12.00	0.00	33600.00	0.00	2800.00	1000.00	17800.00	52400.00	52400.00	0.00	52400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
413	INV-2026-1373	413	413	1	أغسطس 2	775.00	807.00	32.00	0.00	44800.00	0.00	1400.00	1000.00	0.00	45800.00	45800.00	0.00	45800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
414	INV-2026-1374	414	414	1	أغسطس 2	51.00	53.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	1000.00	4800.00	4800.00	0.00	4800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
415	INV-2026-1375	415	415	1	أغسطس 2	8.00	9.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	10200.00	12600.00	12600.00	0.00	12600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
416	INV-2026-1376	416	416	1	أغسطس 2	79.00	88.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	600.00	14200.00	14200.00	0.00	14200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
418	INV-2026-1379	418	418	1	أغسطس 2	321.00	324.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
419	INV-2026-1380	419	419	1	أغسطس 2	446.00	470.00	24.00	0.00	33600.00	0.00	1400.00	1000.00	0.00	34600.00	34600.00	0.00	34600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
420	INV-2026-1381	420	420	1	أغسطس 2	306.00	322.00	16.00	0.00	22400.00	0.00	1400.00	1000.00	27500.00	50900.00	50900.00	0.00	50900.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
421	INV-2026-1382	421	421	1	أغسطس 2	542.00	551.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	2500.00	16100.00	16100.00	0.00	16100.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
422	INV-2026-1383	422	422	1	أغسطس 2	435.00	446.00	11.00	0.00	15400.00	0.00	1400.00	1000.00	0.00	16400.00	16400.00	0.00	16400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
423	INV-2026-1384	423	423	1	أغسطس 2	430.00	440.00	10.00	0.00	14000.00	0.00	1400.00	1000.00	0.00	15000.00	15000.00	0.00	15000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
424	INV-2026-1385	424	424	1	أغسطس 2	28.00	33.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
425	INV-2026-1386	425	425	1	أغسطس 2	654.00	663.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
426	INV-2026-1387	426	426	1	أغسطس 2	850.00	850.00	0.00	0.00	0.00	0.00	1400.00	1000.00	83500.00	84500.00	84500.00	0.00	84500.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
427	INV-2026-1388	427	427	1	أغسطس 2	298.00	307.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	600.00	14200.00	14200.00	0.00	14200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
428	INV-2026-1389	428	428	1	أغسطس 2	254.00	260.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
429	INV-2026-1390	429	429	1	أغسطس 2	288.00	294.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	2000.00	11400.00	11400.00	0.00	11400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
430	INV-2026-1391	430	430	1	أغسطس 2	524.00	537.00	13.00	0.00	18200.00	0.00	1400.00	1000.00	0.00	19200.00	19200.00	0.00	19200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
431	INV-2026-1392	431	431	1	أغسطس 2	591.00	591.00	0.00	0.00	0.00	0.00	1400.00	1000.00	58600.00	59600.00	59600.00	0.00	59600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
432	INV-2026-1393	432	432	1	أغسطس 2	77.00	84.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
433	INV-2026-1394	433	433	1	أغسطس 2	162.00	171.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
434	INV-2026-1395	434	434	1	أغسطس 2	123.00	136.00	13.00	0.00	18200.00	0.00	1400.00	1000.00	1700.00	20900.00	20900.00	0.00	20900.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
435	INV-2026-1396	435	435	1	أغسطس 2	72.00	76.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
436	INV-2026-1397	436	436	1	أغسطس 2	75.00	77.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
437	INV-2026-1398	437	437	1	أغسطس 2	783.00	789.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
438	INV-2026-1399	438	438	1	أغسطس 2	27.00	27.00	0.00	0.00	0.00	0.00	1400.00	1000.00	1000.00	2000.00	2000.00	0.00	2000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
439	INV-2026-1400	439	439	1	أغسطس 2	249.00	249.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
440	INV-2026-1401	440	440	1	أغسطس 2	154.00	154.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
441	INV-2026-1402	441	441	1	أغسطس 2	259.00	268.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	11800.00	25400.00	25400.00	0.00	25400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
442	INV-2026-1403	442	442	1	أغسطس 2	5384.00	5463.00	79.00	0.00	110600.00	0.00	1400.00	1000.00	219900.00	331500.00	331500.00	0.00	331500.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
443	INV-2026-1404	443	443	1	أغسطس 2	345.00	351.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	400.00	9800.00	9800.00	0.00	9800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
444	INV-2026-1405	444	444	1	أغسطس 2	1291.00	1298.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
445	INV-2026-1406	445	445	1	أغسطس 2	15.00	15.00	0.00	0.00	0.00	0.00	1400.00	1000.00	4200.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
446	INV-2026-1407	446	446	1	أغسطس 2	80.00	82.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
447	INV-2026-1408	447	447	1	أغسطس 2	510.00	510.00	0.00	0.00	0.00	0.00	1400.00	1000.00	2400.00	3400.00	3400.00	0.00	3400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
448	INV-2026-1409	448	448	1	أغسطس 2	831.00	838.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
449	INV-2026-1410	449	449	1	أغسطس 2	37.00	37.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
450	INV-2026-1411	450	450	1	أغسطس 2	68.00	68.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
452	INV-2026-1413	452	452	1	أغسطس 2	198.00	198.00	0.00	0.00	0.00	0.00	1400.00	1000.00	7900.00	8900.00	8900.00	0.00	8900.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
453	INV-2026-1414	453	453	1	أغسطس 2	161.00	176.00	15.00	0.00	21000.00	0.00	1400.00	1000.00	0.00	22000.00	22000.00	0.00	22000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
454	INV-2026-1415	454	454	1	أغسطس 2	323.00	332.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	300.00	13900.00	13900.00	0.00	13900.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
455	INV-2026-1416	455	455	1	أغسطس 2	219.00	225.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	300.00	9700.00	9700.00	0.00	9700.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
456	INV-2026-1417	456	456	1	أغسطس 2	65.00	72.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	0.00	10800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
457	INV-2026-1418	457	457	1	أغسطس 2	494.00	505.00	11.00	0.00	15400.00	0.00	1400.00	1000.00	1800.00	18200.00	18200.00	0.00	18200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
459	INV-2026-1420	459	459	1	أغسطس 2	143.00	144.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
460	INV-2026-1421	460	460	1	أغسطس 2	391.00	408.00	17.00	0.00	23800.00	0.00	1400.00	1000.00	49200.00	74000.00	74000.00	0.00	74000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
461	INV-2026-1422	461	461	1	أغسطس 2	406.00	410.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	400.00	7000.00	7000.00	0.00	7000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
465	INV-2026-1426	465	465	1	أغسطس 2	1542.00	1568.00	26.00	0.00	36400.00	0.00	1400.00	1000.00	13300.00	50700.00	50700.00	0.00	50700.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
466	INV-2026-1427	466	466	1	أغسطس 2	265.00	273.00	8.00	0.00	11200.00	0.00	1400.00	1000.00	87200.00	99400.00	99400.00	0.00	99400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
467	INV-2026-1428	467	467	1	أغسطس 2	274.00	279.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
468	INV-2026-1429	468	468	1	أغسطس 2	100.00	102.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
469	INV-2026-1430	469	469	1	أغسطس 2	892.00	902.00	10.00	0.00	14000.00	0.00	1400.00	1000.00	0.00	15000.00	15000.00	0.00	15000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
470	INV-2026-1431	470	470	1	أغسطس 2	449.00	455.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	0.00	9400.00	9400.00	0.00	9400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
471	INV-2026-1432	471	471	1	أغسطس 2	124.00	133.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
472	INV-2026-1433	472	472	1	أغسطس 2	664.00	667.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	0.00	5200.00	5200.00	0.00	5200.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
473	INV-2026-1434	473	473	1	أغسطس 2	1856.00	1903.00	47.00	0.00	65800.00	0.00	1400.00	1000.00	59800.00	126600.00	126600.00	0.00	126600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
474	INV-2026-1435	474	474	1	أغسطس 2	626.00	631.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	0.00	8000.00	8000.00	0.00	8000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
475	INV-2026-1436	475	475	1	أغسطس 2	41.00	43.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
476	INV-2026-1437	476	476	1	أغسطس 2	129.00	131.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
477	INV-2026-1438	477	477	1	أغسطس 2	78.00	82.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	0.00	6600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
478	INV-2026-1439	478	478	1	أغسطس 2	255.00	264.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
479	INV-2026-1440	479	479	1	أغسطس 2	222.00	231.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
480	INV-2026-1441	480	480	1	أغسطس 2	337.00	346.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
481	INV-2026-1442	481	481	1	أغسطس 2	641.00	647.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	3400.00	12800.00	12800.00	0.00	12800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
482	INV-2026-1443	482	482	1	أغسطس 2	508.00	527.00	19.00	0.00	19000.00	0.00	1000.00	0.00	0.00	19000.00	19000.00	0.00	19000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
483	INV-2026-1444	483	483	1	أغسطس 2	1953.00	1962.00	9.00	0.00	12600.00	0.00	1400.00	1000.00	0.00	13600.00	13600.00	0.00	13600.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
484	INV-2026-1445	484	484	1	أغسطس 2	197.00	198.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
485	INV-2026-1446	485	485	1	أغسطس 2	65.00	65.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
486	INV-2026-1447	486	486	1	أغسطس 2	74.00	75.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
487	INV-2026-1448	487	487	1	أغسطس 2	6.00	6.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
488	INV-2026-1449	488	488	1	أغسطس 2	93.00	95.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
489	INV-2026-1450	489	489	1	أغسطس 2	2.00	3.00	1.00	0.00	1400.00	0.00	1400.00	1000.00	0.00	2400.00	2400.00	0.00	2400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
490	INV-2026-1451	490	490	1	أغسطس 2	8.00	8.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
491	INV-2026-1452	491	491	1	أغسطس 2	23.00	25.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	0.00	3800.00	3800.00	0.00	3800.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
492	INV-2026-1453	492	492	1	أغسطس 2	1610.00	1610.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	0.00	1000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
493	INV-2026-1454	493	493	1	أغسطس 2	83081.00	84451.00	1370.00	0.00	1918000.00	0.00	1400.00	1000.00	0.00	1919000.00	1919000.00	0.00	1919000.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
494	INV-2026-1455	494	494	1	أغسطس 2	918.00	918.00	0.00	0.00	0.00	0.00	1400.00	1000.00	231400.00	232400.00	232400.00	0.00	232400.00	2026-09-10	APPROVED	Unpaid	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
274	INV-2026-1234	274	274	1	أغسطس 2	254.00	266.00	12.00	0.00	16800.00	0.00	1400.00	1000.00	0.00	17800.00	17800.00	17800.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.865556+03	2026-09-07 15:00:22.865556+03
276	INV-2026-1236	276	276	1	أغسطس 2	266.00	284.00	18.00	0.00	25200.00	0.00	1400.00	1000.00	0.00	26200.00	26200.00	20000.00	6200.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-07 15:00:22.867614+03	2026-09-07 15:00:22.867614+03
70	INV-2026-1030	70	70	1	أغسطس 2	699.00	722.00	23.00	0.00	32200.00	0.00	1400.00	1000.00	0.00	33200.00	33200.00	33200.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.869418+03	2026-09-07 15:00:22.869418+03
305	INV-2026-1265	305	305	1	أغسطس 2	284.00	284.00	0.00	0.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	4800.00	4800.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.871894+03	2026-09-07 15:00:22.871894+03
405	INV-2026-1365	405	405	1	أغسطس 2	98.00	103.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	0.00	8000.00	8000.00	8000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.877434+03	2026-09-07 15:00:22.877434+03
417	INV-2026-1377	417	417	1	أغسطس 2	1685.00	1691.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	147600.00	157000.00	157000.00	100000.00	57000.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-07 15:00:22.878807+03	2026-09-07 15:00:22.878807+03
451	INV-2026-1412	451	451	1	أغسطس 2	297.00	301.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	5200.00	11800.00	11800.00	11000.00	800.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-07 15:00:22.880007+03	2026-09-07 15:00:22.880007+03
464	INV-2026-1425	464	464	1	أغسطس 2	341.00	346.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	0.00	8000.00	8000.00	8000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.881226+03	2026-09-07 15:00:22.881226+03
463	INV-2026-1424	463	463	1	أغسطس 2	529.00	540.00	11.00	0.00	15400.00	0.00	1400.00	1000.00	0.00	16400.00	16400.00	16400.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.882833+03	2026-09-07 15:00:22.882833+03
308	INV-2026-1268	308	308	1	أغسطس 2	52.00	150.00	98.00	0.00	137200.00	0.00	1400.00	1000.00	73800.00	212000.00	212000.00	73810.00	138190.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-07 15:00:22.884273+03	2026-09-07 15:00:22.884273+03
145	INV-2026-1105	145	145	1	أغسطس 2	630.00	642.00	12.00	0.00	16800.00	0.00	1400.00	1000.00	0.00	17800.00	17800.00	17800.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.885474+03	2026-09-07 15:00:22.885474+03
151	INV-2026-1111	151	151	1	أغسطس 2	186.00	194.00	8.00	0.00	11200.00	0.00	1400.00	1000.00	6600.00	18800.00	18800.00	13000.00	5800.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-07 15:00:22.88665+03	2026-09-07 15:00:22.88665+03
143	INV-2026-1103	143	143	1	أغسطس 2	545.00	638.00	93.00	0.00	130200.00	0.00	1400.00	1000.00	0.00	131200.00	131200.00	131200.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.888418+03	2026-09-07 15:00:22.888418+03
327	INV-2026-1287	327	327	1	أغسطس 2	189.00	196.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	9000.00	1800.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-07 15:00:22.889716+03	2026-09-07 15:00:22.889716+03
322	INV-2026-1282	322	322	1	أغسطس 2	1127.00	1147.00	20.00	0.00	28000.00	0.00	1400.00	1000.00	30400.00	59400.00	59400.00	25010.00	34390.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-07 15:00:22.891121+03	2026-09-07 15:00:22.891121+03
128	INV-2026-1088	128	128	1	أغسطس 2	475.00	482.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	10800.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.892303+03	2026-09-07 15:00:22.892303+03
52	INV-2026-1012	52	52	1	أغسطس 2	203.00	213.00	10.00	0.00	14000.00	0.00	1400.00	1000.00	13600.00	28600.00	28600.00	13600.00	15000.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-07 15:00:22.895734+03	2026-09-07 15:00:22.895734+03
37	INV-2026-998	37	37	1	أغسطس 2	337.00	343.00	6.00	0.00	8400.00	0.00	1400.00	1000.00	0.00	9400.00	9400.00	9400.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.896858+03	2026-09-07 15:00:22.896858+03
35	INV-2026-995	35	35	1	أغسطس 2	220.00	220.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	1000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.89801+03	2026-09-07 15:00:22.89801+03
29	INV-2026-989	29	29	1	أغسطس 2	498.00	512.00	14.00	0.00	19600.00	0.00	1400.00	1000.00	0.00	20600.00	20600.00	20000.00	600.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-07 15:00:22.899115+03	2026-09-07 15:00:22.899115+03
27	INV-2026-987	27	27	1	أغسطس 2	362.00	367.00	5.00	0.00	7000.00	0.00	1400.00	1000.00	100.00	8100.00	8100.00	7000.00	1100.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-07 15:00:22.90037+03	2026-09-07 15:00:22.90037+03
24	INV-2026-984	24	24	1	أغسطس 2	85.00	105.00	20.00	0.00	28000.00	0.00	1400.00	1000.00	0.00	29000.00	29000.00	29000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.901534+03	2026-09-07 15:00:22.901534+03
21	INV-2026-981	21	21	1	أغسطس 2	169.00	169.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	1000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.90264+03	2026-09-07 15:00:22.90264+03
19	INV-2026-979	19	19	1	أغسطس 2	670.00	680.00	10.00	0.00	14000.00	0.00	1400.00	1000.00	20600.00	35600.00	35600.00	35600.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.903788+03	2026-09-07 15:00:22.903788+03
17	INV-2026-977	17	17	1	أغسطس 2	147.00	147.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	1000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.905928+03	2026-09-07 15:00:22.905928+03
15	INV-2026-975	15	15	1	أغسطس 2	1270.00	1284.00	14.00	0.00	19600.00	0.00	1400.00	1000.00	53400.00	74000.00	74000.00	50400.00	23600.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-07 15:00:22.907074+03	2026-09-07 15:00:22.907074+03
10	INV-2026-970	10	10	1	أغسطس 2	23.00	27.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	0.00	6600.00	6600.00	6600.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.908319+03	2026-09-07 15:00:22.908319+03
169	INV-2026-1129	169	169	1	أغسطس 2	641.00	641.00	0.00	0.00	0.00	0.00	1400.00	1000.00	3800.00	4800.00	4800.00	4800.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.909582+03	2026-09-07 15:00:22.909582+03
458	INV-2026-1419	458	458	1	أغسطس 2	232.00	234.00	2.00	0.00	2800.00	0.00	1400.00	1000.00	5200.00	9000.00	9000.00	9000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.913896+03	2026-09-07 15:00:22.913896+03
144	INV-2026-1104	144	144	1	أغسطس 2	687.00	691.00	4.00	0.00	5600.00	0.00	1400.00	1000.00	9400.00	16000.00	16000.00	16000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.915082+03	2026-09-07 15:00:22.915082+03
30	INV-2026-990	30	30	1	أغسطس 2	159.00	162.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	0.00	5200.00	5200.00	5200.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.916259+03	2026-09-07 15:00:22.916259+03
116	INV-2026-1076	116	116	1	أغسطس 2	385.00	392.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	10800.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.918907+03	2026-09-07 15:00:22.918907+03
96	INV-2026-1056	96	96	1	أغسطس 2	55.00	62.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	0.00	10800.00	10800.00	10800.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.920262+03	2026-09-07 15:00:22.920262+03
75	INV-2026-1035	75	75	1	أغسطس 2	57.00	57.00	0.00	0.00	0.00	0.00	1400.00	1000.00	0.00	1000.00	1000.00	1000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.922422+03	2026-09-07 15:00:22.922422+03
42	INV-2026-1002	42	42	1	أغسطس 2	1418.00	1453.00	35.00	0.00	49000.00	0.00	1400.00	1000.00	7800.00	57800.00	57800.00	50000.00	7800.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-07 15:00:22.923642+03	2026-09-07 15:00:22.923642+03
282	INV-2026-1242	282	282	1	أغسطس 2	357.00	399.00	42.00	0.00	58800.00	0.00	1400.00	1000.00	103700.00	163500.00	163500.00	45500.00	118000.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-07 15:00:22.925593+03	2026-09-07 15:00:22.925593+03
364	INV-2026-1324	364	364	1	أغسطس 2	243.00	250.00	7.00	0.00	9800.00	0.00	1400.00	1000.00	3800.00	14600.00	14600.00	3800.00	10800.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-07 15:00:22.927364+03	2026-09-07 15:00:22.927364+03
462	INV-2026-1423	462	462	1	أغسطس 2	237.00	252.00	15.00	0.00	21000.00	0.00	1400.00	1000.00	0.00	22000.00	22000.00	22000.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.927902+03	2026-09-07 15:00:22.927902+03
391	INV-2026-1351	391	391	1	أغسطس 2	95.00	103.00	8.00	0.00	11200.00	0.00	1400.00	1000.00	0.00	12200.00	12200.00	5000.00	7200.00	2026-09-10	APPROVED	Partially_Paid	f	2026-09-07 15:00:22.92915+03	2026-09-07 15:00:22.92915+03
201	INV-2026-1161	201	201	1	أغسطس 2	241.00	244.00	3.00	0.00	4200.00	0.00	1400.00	1000.00	0.00	5200.00	5200.00	5200.00	0.00	2026-09-10	APPROVED	Paid	f	2026-09-07 15:00:22.930359+03	2026-09-07 15:00:22.930359+03
\.


--
-- Data for Name: meter_readings; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.meter_readings (id, customer_id, cycle_id, reading_value, previous_reading, consumption, lost_units, reading_date, collector_name, collector_user_id, approval_status, client_mutation_id, rejection_reason, whatsapp_sent, is_meter_reset, created_at, updated_at) FROM stdin;
1	1	1	56900.00	56900.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	ca3ae5a5-6946-43be-a04e-8ded5f431518	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
2	2	1	44179.00	44179.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	62e27d0e-d985-4403-92ec-3e9e0affd65d	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
3	3	1	35078.00	35078.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	1c3f8092-3056-402b-864e-3915fb4426f9	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
4	4	1	1288.00	1288.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	c8f3b26e-44af-4574-ab22-9823aedd652c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
5	5	1	226.00	226.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	afda83ca-cf61-44ce-a066-f99a3688a2f9	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
6	6	1	635.00	617.00	18.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	e8d20008-ab6c-48b3-b22d-6c729c035a71	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
7	7	1	300.00	294.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	62fb3ce9-4393-4ac3-b2d5-dde8d4cad5da	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
8	8	1	224.00	224.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	0bf37d0f-3791-4a79-bb5b-5ef7068333c0	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
9	9	1	594.00	594.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	fc59cc1a-6f24-46f4-908d-372873b6a27f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
10	10	1	27.00	23.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	5f5e53fa-eb6a-441d-823e-45342aa8710d	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
11	11	1	833.00	831.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	be2cf499-530d-417e-a630-6977cad9ceef	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
12	12	1	719.00	716.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	0134f628-cbb6-426a-bc73-754d5d88aa05	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
13	13	1	644.00	631.00	13.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	1a53d4ff-6b5e-4a7d-b69f-2fe2f92c800b	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
14	14	1	0.00	0.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	84095e70-8122-468f-8b72-1f317fed2b49	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
15	15	1	1284.00	1270.00	14.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2d81634e-df62-4081-8f8d-a5eaf7e0801e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
16	16	1	301.00	282.00	19.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	67dc792d-deb1-4f8a-aa97-a681265eeb7d	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
17	17	1	147.00	147.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	efb13c2f-20c6-4370-bafb-8d93878f749f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
18	18	1	168.00	166.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	0209f2b2-3e0e-491d-8cbd-eab8dfdb51a8	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
19	19	1	680.00	670.00	10.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	5cf270f2-f8d7-4cd3-89c0-504ae77de097	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
20	20	1	553.00	550.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a2576d4a-35a1-4d9a-86d5-dcbb2f51d8f6	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
21	21	1	169.00	169.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	49ae3cf1-9b45-4dc6-8e44-5bdc62d22b35	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
22	22	1	130.00	127.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	6fe7de98-220d-4fae-8263-1d79a79e0258	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
23	23	1	1127.00	1118.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	74627ab3-e874-47bd-8ea1-a7408792a31c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
24	24	1	105.00	85.00	20.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	3968b063-d91c-4c1f-8e15-caa8cd031b5c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
25	25	1	100.00	96.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	3da216f8-141c-4dd2-8d16-15036a369cd1	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
26	26	1	59.00	58.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	e13f4c4d-613f-4656-917b-54418f7dd48e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
27	27	1	367.00	362.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	18bb2409-ed31-49fa-82e4-abf8b1f886d1	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
28	28	1	1896.00	1857.00	39.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	cacbc244-778c-45a4-888d-918abc3e2630	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
29	29	1	512.00	498.00	14.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2f5da106-a782-40ec-bdab-1e239470926e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
30	30	1	162.00	159.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	ba12a56b-b81d-4474-bf56-4dc3ade0538b	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
31	31	1	752.00	727.00	25.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b0e18df2-b1ce-411a-9f7c-29975c04be00	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
32	32	1	332.00	325.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f47fb9f9-a782-4d23-a68d-e49bef2e3204	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
33	33	1	2324.00	2324.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	1772d1a6-c022-457d-b9ca-53a571b2340a	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
34	34	1	196.00	190.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	3cc3b13f-761a-4641-b19c-d4b6800c3490	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
35	35	1	220.00	220.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	3151c744-1766-4787-8482-fa9eb4aabafa	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
36	36	1	151.00	44.00	107.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8b14be98-f4be-42d7-920c-f85f479dc799	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
37	37	1	343.00	337.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a35c77d9-2be2-475b-b4ca-0665a6ab3976	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
38	38	1	242.00	228.00	14.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	55554e42-e4a2-4dc8-8669-a462799266a9	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
39	39	1	574.00	566.00	8.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f0e05443-15f9-45c4-9bc4-2ef48cc7a667	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
40	40	1	391.00	391.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2fad355d-15e4-4a43-8e59-02ab3f3628ee	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
41	41	1	239.00	231.00	8.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	9a52fc33-f9a8-4a1a-8da3-47800251076b	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
42	42	1	1453.00	1418.00	35.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a3e815b9-245b-45ec-a7cc-03771dcf782d	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
43	43	1	88.00	74.00	14.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	dc579fbe-e111-4fd8-8147-353ad2ae4c62	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
44	44	1	534.00	534.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	0babc30e-96d0-487e-9e3a-0f58b97b890e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
45	45	1	2482.00	2462.00	20.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	652cc912-c3c5-438c-a354-5b8c8c5b1999	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
46	46	1	775.00	752.00	23.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	3d7e0eeb-49ab-4fa1-9ea4-e8f6866c7fdb	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
47	47	1	160.00	156.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	51dcd717-c7d5-45b9-a5f0-d35a3f5a7af5	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
48	48	1	1953.00	1872.00	81.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	9242605c-d7a7-40d6-8e4a-e4aec451d921	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
49	49	1	326.00	326.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	399fd2dc-a41d-466f-b8ae-32bdc55b406b	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
50	50	1	559.00	553.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b6a3dbb0-5b87-405a-b7ad-52ab133bc9e0	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
51	51	1	452.00	449.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	250262c3-a87a-4251-9821-b3a8294952ab	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
52	52	1	213.00	203.00	10.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f718952f-ea63-453e-999a-acdd35dd9a0f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
53	53	1	139.00	139.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	ca932952-fc45-414d-90e0-059eeb4591c9	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
54	54	1	1754.00	1729.00	25.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b73c7b7d-1109-4ba6-a480-d9b529e981b3	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
55	55	1	1580.00	1580.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	4106e381-42f7-490a-86b6-2b80186f2e0f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
56	56	1	67.00	67.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	25e7be21-fc67-4caa-9eda-dffa5ec458ea	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
57	57	1	227.00	227.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	38033c28-5cb2-4f2f-a0e3-5d4d6e7d44c2	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
58	58	1	460.00	440.00	20.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	e72e4bc1-793f-4e95-a84f-b127b4ab4969	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
59	59	1	13.00	13.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	c49a51b4-dc27-4485-b361-2b5c2b3b233f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
60	60	1	402.00	398.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	474c374c-ef58-4934-9135-cd49454bba09	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
61	61	1	130.00	130.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	fdf20569-3773-4720-bf04-725a2ae953da	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
62	62	1	513.00	493.00	20.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	05021997-de26-4f55-844a-2dde3007c48c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
63	63	1	238.00	238.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	705c5273-89ab-4308-aaf2-8c0384e3041c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
64	64	1	2.00	1.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	bab08906-6e1d-45ae-b53c-85e31546f70c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
65	65	1	104.00	104.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	923a3df4-9da6-4d1f-a2bb-cbb480d0d34f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
66	66	1	246.00	238.00	8.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	e6eaf128-3bd4-4d60-8882-ff89ea75e417	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
67	67	1	278.00	273.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	bb8f48f2-7450-4744-8149-a131925a0783	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
68	68	1	329.00	324.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	51a92219-e581-4b72-8985-b4d6a17a358b	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
69	69	1	592.00	585.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8d6f9de9-f756-4737-8474-d987c422594c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
70	70	1	722.00	699.00	23.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	76adedff-d23c-40a7-b2cd-a96961a2919c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
71	71	1	70.00	66.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	ec5ae82a-137e-43ea-bcbc-60c2b09e18d7	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
72	72	1	465.00	458.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	14682171-bb4f-4b40-b60b-480486824c3e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
73	73	1	648.00	616.00	32.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	5af39f11-b747-498e-a0fe-399b49d80cca	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
74	74	1	900.00	885.00	15.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	0042542a-c846-4c8c-93fc-c974bbc0c0e2	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
75	75	1	57.00	57.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	d6740fa3-4edf-441a-8994-3d7fd924374a	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
76	76	1	172.00	168.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a6e9d4c2-fea1-4a03-9073-c2875aad4405	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
77	77	1	112.00	112.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	efebd6a8-d9d8-439a-9c40-c8b28f29eebf	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
78	78	1	337.00	330.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8df8dce0-95d8-41ec-b03f-85103483cd01	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
79	79	1	264.00	264.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	1c60bdd7-2471-4580-a211-653e12cfa8ff	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
80	80	1	589.00	589.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	3fdde8d6-e315-4c0b-9392-f194fc7f3d86	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
81	81	1	88.00	83.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	80dc9ff5-3a75-4c50-b3e8-f73b4203c247	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
82	82	1	239.00	239.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	6ddeace1-fc54-4a43-bbca-8e0be63f7be3	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
83	83	1	4107.00	4016.00	91.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	7cbd0f28-3a62-42ea-96d7-59fefd18a340	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
84	84	1	149.00	134.00	15.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	3238b739-5eb9-4afe-8ed1-ebcee1a704c0	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
85	85	1	1174.00	1174.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2a6315e6-fde8-4827-9da1-9c8f5efa0b96	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
86	86	1	851.00	851.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f1656de2-e705-476e-9fe8-413a3b4a3cd2	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
87	87	1	645.00	627.00	18.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	5c24bdd7-76d6-46de-94bd-f0f4db5905d5	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
88	88	1	370.00	356.00	14.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	14c08afd-ef7f-41dd-be8b-f5d727df5535	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
89	89	1	48.00	44.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	4165f5c7-01d1-4aa0-afea-07f8362cf055	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
90	90	1	579.00	566.00	13.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a737686c-33fa-41b1-a0a6-012cc811dc86	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
91	91	1	295.00	286.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	5bffb5d0-0233-4d47-bfb3-79805cdf66ee	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
92	92	1	48.00	48.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	9bb23723-1dae-4bd9-ad68-115c50a4ab06	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
93	93	1	135.00	132.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	92151df2-b8b1-46b6-a979-a26c28494c84	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
94	94	1	389.00	389.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	dfd2425c-9f29-4f51-8959-895f60eede15	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
95	95	1	347.00	340.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	1e816e24-4f89-4316-ae51-da11d201cc82	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
96	96	1	62.00	55.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	30e81e26-42c4-4273-adb1-45bf1863922a	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
97	97	1	156.00	145.00	11.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	213e1621-510f-4c28-961f-0ed501ff563a	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
98	98	1	925.00	907.00	18.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	dabec3a9-f92c-43a4-bd5d-6c2cc6ee69c4	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
99	99	1	327.00	312.00	15.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	538fc779-c229-48b6-9efb-6063cfc263ef	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
100	100	1	1337.00	1322.00	15.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8a8c9ffc-13d5-4ac1-81ab-7582ed490c9b	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
101	101	1	1614.00	1614.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8fa2a312-de48-4cca-a634-41f55c156ea4	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
102	102	1	197.00	191.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	cc680f2d-2357-4e00-af22-79583eb01d1a	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
103	103	1	249.00	249.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	13ecc7bf-826a-4c2d-8a4c-5b2ec320bafd	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
104	104	1	110.00	110.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	0abb2627-9803-4d52-bfa0-c91774c977bd	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
105	105	1	450.00	421.00	29.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f586af64-1732-47d2-9bab-5c7a0a4c46a8	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
106	106	1	44.00	33.00	11.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	eb664280-a0df-4976-b425-446ded1fe041	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
107	107	1	48.00	40.00	8.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	79cb6bcd-e3d5-4d4e-b634-804ea87b8788	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
108	108	1	97.00	93.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	cff565bc-be3e-42e5-971e-0097a2d96e55	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
109	109	1	28.00	23.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	571a3a98-38ce-4a20-bee3-ab333c3ac983	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
110	110	1	792.00	764.00	28.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2621bd93-9976-44c2-b986-993f8775e8b0	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
111	111	1	145.00	138.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	00576159-caf1-4242-99f0-65afe068b773	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
112	112	1	2235.00	2207.00	28.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b90c003d-b4c2-43f2-bc9b-0b3f67ff581c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
113	113	1	920.00	913.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a4b70c2e-cad7-40e7-8635-ed25e619b17a	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
114	114	1	1360.00	1312.00	48.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	de695760-5836-4e81-9399-4a9518ec0ae8	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
115	115	1	540.00	532.00	8.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	cc67f4ac-5c7e-451d-a27a-a8111a8358e3	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
116	116	1	392.00	385.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	c196171c-7671-4f62-9b45-7f755a718e40	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
117	117	1	205.00	203.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	74a6890d-81a8-40e3-8abf-9ac87ac4d776	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
118	118	1	347.00	328.00	19.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	10039185-5402-4a06-aa26-6bc0c7e259c4	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
119	119	1	41.00	37.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	13fabace-5bdf-4acc-a6f5-1d0c9c3973c4	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
120	120	1	364.00	357.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b1fd0337-41e9-4ee3-9bed-53227d5f5435	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
121	121	1	375.00	368.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	79057b8a-2dd3-4738-8699-af72dcdb2d48	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
122	122	1	65.00	65.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	95fb99ae-d12d-4dd1-aaa4-a968a3f91cd7	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
123	123	1	179.00	175.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8a687055-49d5-4e74-af8e-3290a0693769	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
124	124	1	150.00	150.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b2fe71c0-8d51-4aa2-9ddb-671471193a84	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
125	125	1	240.00	234.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	0e3f376e-9d15-4e17-8117-110d88185ee8	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
126	126	1	885.00	867.00	18.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	93836991-7a17-4132-aeba-0f3dd5e24333	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
127	127	1	377.00	365.00	12.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	aa711748-84a9-408d-b6cb-4ea7414f67b5	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
128	128	1	482.00	475.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	480f937a-2b87-4082-bd4a-14c09498b13e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
129	129	1	131.00	109.00	22.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f2ab5824-3350-4180-a360-cc8ab75f0af1	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
130	130	1	277.00	272.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	0cc561aa-f916-41f1-a728-a47a30f97bf4	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
131	131	1	1308.00	1282.00	26.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	df7c7582-4d9a-4047-8ea6-7703f704dca4	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
132	132	1	550.00	549.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	dee8c266-e461-44df-b176-3db9c8d04a00	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
133	133	1	963.00	959.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	ed5b511f-2a5f-4783-811c-47612e60b156	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
134	134	1	1002.00	979.00	23.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	e8d8acf8-fd61-480c-bb75-163452cd89b0	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
135	135	1	56.00	47.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	44ba4d67-986d-4e5a-a8bc-a66d79a29243	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
136	136	1	533.00	519.00	14.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	db00f697-14b0-4142-8055-7dbabad6af3c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
137	137	1	1048.00	1045.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	56220126-132d-489d-b5a6-635eba84a61a	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
138	138	1	158.00	149.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	4036c0b9-e164-4642-9183-fdf987466891	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
139	139	1	310.00	308.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	467c4085-66c0-404e-a65a-86a3efe2b4ee	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
140	140	1	1560.00	1527.00	33.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	edcdedf7-f541-4303-ba1c-bc522f2990c6	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
141	141	1	98.00	86.00	12.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f2297c9e-8a7d-4e17-90d3-16c4a86edad2	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
142	142	1	324.00	312.00	12.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	9eb91c0c-bb9b-40ca-9f24-3ef007f0db80	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
143	143	1	638.00	545.00	93.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	395ec30b-5543-4f6b-85c0-e257fa3ad647	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
144	144	1	691.00	687.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	656f8489-bb6f-4e76-8f92-4a774866e7e5	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
145	145	1	642.00	630.00	12.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8c30a127-2bd4-4504-bc6e-9dfa136bb208	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
146	146	1	52.00	52.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	5ef69c7b-2ccb-4354-8569-4c5b59ca0ddf	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
147	147	1	264.00	249.00	15.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b86dfd97-c57a-4eb8-880b-666cb9371e44	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
148	148	1	49.00	48.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	6208d658-90e5-4585-918a-05e13677e302	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
149	149	1	98.00	97.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	4044c3ff-56ef-4c83-ba95-d70eee85cdab	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
150	150	1	609.00	609.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	d705c45b-c475-4a46-aa75-a67e7e28c833	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
151	151	1	194.00	186.00	8.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	fcc92e58-e89f-4a66-9bba-d170ab71742a	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
152	152	1	58.00	56.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	09408caf-b1f8-484c-a78f-97ddbc3c0431	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
153	153	1	367.00	365.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a3bd75f9-fa78-4769-ab7f-e66cbce8fed8	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
154	154	1	124.00	121.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	3c246da4-127d-4816-9f84-376dd960d095	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
155	155	1	99.00	95.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	607e90ce-15c0-4694-9311-259d24d1cac6	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
156	156	1	172.00	159.00	13.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b1b76ee8-25b1-45e9-8bce-6cda6049c0ad	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
157	157	1	285.00	279.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	270a81b4-765c-4311-8636-352816556536	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
158	158	1	269.00	252.00	17.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	31503953-f363-486a-8bdc-c13d907abea7	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
159	159	1	239.00	232.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	225c0cff-21e8-47f9-9681-1e0577a684a1	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
160	160	1	458.00	443.00	15.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a59557c2-ac81-4b84-821f-27b2e1e8f439	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
161	161	1	263.00	255.00	8.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b5c3e9b3-ead4-4004-b3e9-dd927db6702c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
162	162	1	160.00	144.00	16.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	3ca2ef7f-af71-4872-922f-4511239282e9	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
163	163	1	685.00	685.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f1f41254-b63b-4771-b92a-3a999ac433ad	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
164	164	1	430.00	427.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	92b2713c-beff-4308-854e-40547523b0b4	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
165	165	1	296.00	286.00	10.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	bcc00d06-18e2-440d-a87e-7aa33dd8318d	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
166	166	1	352.00	345.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	47ae318b-7634-4410-873d-dad2ad878f3b	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
167	167	1	147.00	142.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2aa3f6d3-d399-45ef-87ad-a380281b306d	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
168	168	1	436.00	436.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	4b5b1eb1-a119-41d4-98ea-2fd6f1d306b2	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
169	169	1	641.00	641.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	5de0af3d-0a48-4f55-af7c-72715625165c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
170	170	1	879.00	865.00	14.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	d28f07c2-10dd-4ac3-a2d0-45473ccad66b	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
171	171	1	1147.00	1143.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	c5e973a7-5798-4410-a3f3-d44882638b07	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
172	172	1	1064.00	1064.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	6003d417-65df-436b-a09e-852de111abb6	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
173	173	1	868.00	862.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	e453c14b-c56b-4368-a43d-b8fafdb8892c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
174	174	1	995.00	958.00	37.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	3746b41c-d51d-47c6-a86a-46004048c4fb	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
175	175	1	240.00	230.00	10.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	4962a381-c698-47bd-bb4a-b72f0f0dd69b	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
176	176	1	342.00	333.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a7d29079-6621-476d-bec5-37194cdc669d	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
177	177	1	135.00	128.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	9297b6b2-d9c0-4745-8526-51a3d099d8ee	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
178	178	1	272.00	267.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	c09cd38b-9875-4181-b9a1-1dc21d98298e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
179	179	1	48.00	44.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f8210c12-351a-4551-8c4f-71b15a830f69	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
180	180	1	79.00	76.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	fe147161-4e2b-4b20-ae26-a564fdc31013	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
181	181	1	114.00	111.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	4eba8de5-8d26-4640-a068-dc59cbd9dbe0	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
182	182	1	419.00	417.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	9c687047-1587-4361-a2dd-489d0a4ae937	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
183	183	1	200.00	200.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a93abceb-9c68-4dba-9f99-5d388133ae91	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
184	184	1	238.00	238.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	e2ca37b4-7a53-4152-8758-953b7a6d8626	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
185	185	1	3373.00	3202.00	171.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	bb4d3249-c197-4524-8c16-5fb522fdbb5e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
186	186	1	1280.00	1255.00	25.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	060fd754-e097-4c66-8cd0-96d964407b64	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
187	187	1	33.00	29.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	22276ed1-5c32-4152-9708-a6c7f11e27b9	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
188	188	1	6.00	4.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	bed7f1c3-b463-48e2-8d66-e4650c98953f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
189	189	1	425.00	415.00	10.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	6332bfa8-133b-4a9a-a646-6a7d323f2946	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
190	190	1	1034.00	971.00	63.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	5f1ead9f-872b-4955-b0cc-ba7fdebac660	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
191	191	1	116.00	107.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	d62745dd-3bf9-467e-9989-8ad874fc39b9	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
192	192	1	202.00	196.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	97576606-1e49-4f42-9a2a-8d9348b2be8f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
193	193	1	12.00	12.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	da076831-4e7f-4421-9ec1-621a262deaa6	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
194	194	1	578.00	555.00	23.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8d4bf98b-70c7-4de0-8d6c-947b58f1fd69	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
195	195	1	4.00	0.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	0ed4c8cc-dc82-47df-a651-004357570610	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
196	196	1	184.00	180.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	d16200d6-05e9-4984-81f5-1f2b5f26dd27	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
197	197	1	458.00	447.00	11.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	811b6989-e02c-4bd0-ac18-25726dd238f8	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
198	198	1	329.00	310.00	19.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b9590fbf-f13f-4ac1-bde0-8ab6b383e35e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
199	199	1	1052.00	1017.00	35.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	6425fadb-5cf1-4737-b6d4-495ad38e1b67	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
200	200	1	741.00	741.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8b555043-dc41-41ad-a9a5-db87bc327be8	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
201	201	1	244.00	241.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	48813a9d-e300-4555-80f6-3f88d58cc648	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
202	202	1	401.00	401.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	5b00d3f4-cfe9-4949-8e3d-138b0029bb42	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
203	203	1	440.00	430.00	10.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	30cb0729-1c34-4d6a-8c4e-71e189464573	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
204	204	1	4107.00	3987.00	120.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	dcbd2d76-4713-4f4d-8dc6-faff42fa1607	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
205	205	1	480.00	480.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a23588ae-7811-40ca-9835-55a98eca5546	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
206	206	1	337.00	309.00	28.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	e34154ec-8fff-44f3-a6a1-7a22d6ddad7f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
207	207	1	19.00	12.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	60e7dd51-9ff5-4e66-84fe-2b95cc59ea3d	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
208	208	1	179.00	178.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	6daa3f6b-7c2f-465e-93de-21a9612924f7	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
209	209	1	258.00	258.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f60a9614-8fde-497c-823e-ec0f76724ba8	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
210	210	1	266.00	251.00	15.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	c4c28bf5-08c8-4157-a688-e45fa5a837e5	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
211	211	1	1522.00	1516.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	9e65b421-2075-4c16-940e-98384d352d88	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
212	212	1	535.00	527.00	8.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	14499ac1-7f35-432c-81fb-80d9db349198	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
213	213	1	113.00	112.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	144853b4-f538-4729-8b70-a55f4ea474ec	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
214	214	1	354.00	342.00	12.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	7619c7f5-bca1-49b1-b079-03d78fb99a6e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
215	215	1	702.00	686.00	16.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	aa24f957-8e60-45fd-ad0c-00caaec86fe9	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
216	216	1	712.00	712.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	d2ca6212-3002-4d3b-9b25-ba787fc63e57	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
217	217	1	325.00	303.00	22.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	e6bd0149-e636-4b9d-9c6f-e35966f18c93	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
218	218	1	319.00	311.00	8.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	5bd136c9-6521-4a4e-9c3e-0bd7387cd267	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
219	219	1	286.00	285.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	7329f1ef-79e4-4cfa-a31a-5c7e61586be8	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
220	220	1	86.00	77.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	fdecb89b-e8b4-45ac-bccc-bed3ea0739ea	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
221	221	1	1158.00	1156.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	e72209b1-81cf-45a7-9ed8-9ea91ba9d468	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
222	222	1	1480.00	1479.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	d04eb8a2-15a6-4b1d-9ea4-07a8ea279573	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
223	223	1	267.00	267.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	23872657-b264-401e-85ad-3e4ba96e0c60	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
224	224	1	246.00	239.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	eddd7803-5552-4340-b5a0-6bd2af3d2e69	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
225	225	1	1582.00	1559.00	23.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	28e6a8bb-b025-47b5-b612-649b1d4b2a47	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
226	226	1	533.00	533.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	29adc4da-ee55-4a85-83db-6c3b435613e1	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
227	227	1	199.00	199.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	fa0a7d9f-6e46-470b-ae2e-9d6bc224c1f7	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
228	228	1	752.00	752.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	c0a2b4f8-1f1f-400c-a282-2e402ceb6699	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
229	229	1	971.00	965.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	40ca14b9-8313-4d4f-bbfe-537dab83ced7	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
230	230	1	254.00	253.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	bbf2edf7-f3df-45ff-8074-2a71fe0159f0	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
231	231	1	192.00	192.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	908b4125-52dc-4fe0-9133-84c10b54cfda	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
232	232	1	3007.00	3007.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	37f31a92-29bd-4c4b-81f5-25ee4aefa1e8	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
233	233	1	91.00	91.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	e6ca8e5b-1fd6-4739-80ee-b4b4e39472ad	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
234	234	1	415.00	383.00	32.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	36fefd89-7e2b-4b75-925e-0a08cd5871d6	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
235	235	1	4591.00	4576.00	15.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	dcf9c5ff-383d-4cab-ac79-29d9a472ccca	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
236	236	1	52.00	48.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	dc385603-1650-41a6-ba2f-3292e3a8b2e3	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
237	237	1	134.00	134.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	9858fec3-d7cd-4fc3-aa6c-033355e82a4d	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
238	238	1	2468.00	2462.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b6ced552-279b-4899-b0e4-eceb2ac2bf56	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
239	239	1	143.00	141.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	aea3ba13-f2d0-4158-9fa5-ee70a089136c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
240	240	1	184.00	184.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	747d6d18-7f3e-4371-84a4-b7ff0b70b9ac	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
241	241	1	678.00	669.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a3e79052-bef1-483a-848b-2827d264dc0e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
242	242	1	3543.00	3522.00	21.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	0636593a-6719-416b-b2ae-c155197a9ba5	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
243	243	1	574.00	573.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	7de0f160-1021-4a04-96e5-89c231b2a355	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
244	244	1	830.00	798.00	32.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8ec93437-080b-4685-a4bf-83388ed4f5bf	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
245	245	1	1318.00	1313.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	bc246177-2385-4d64-b017-dd72f5790cb5	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
246	246	1	1314.00	1314.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b723397b-f7a9-4fc8-a0e0-f521660ff78a	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
247	247	1	39.00	32.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	0b0a7576-59dc-441c-8dfa-397d87948dcd	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
248	248	1	1267.00	1233.00	34.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	607d8d43-789e-4681-bc9b-16f9e395e03e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
249	249	1	947.00	915.00	32.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2cea086f-5ce3-4053-a147-253e95257989	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
250	250	1	1217.00	1205.00	12.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	01291046-1925-432d-a6c6-3e90d5dfc43f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
251	251	1	668.00	664.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	168a79fe-e42c-407f-b1df-0e4ec5d39919	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
252	252	1	1966.00	1945.00	21.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	55c36a53-ecac-48f2-928f-9a135a6649b7	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
253	253	1	996.00	982.00	14.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	d786f38e-1bc4-4887-aec5-d04a2fab3fd5	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
254	254	1	134.00	132.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	5a95a573-cf9d-4b78-9ce1-9f2421759d45	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
255	255	1	65.00	61.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	ca1cc4c3-4ed7-4fa2-980e-b351041c1671	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
256	256	1	453.00	453.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	4031a20a-706c-4d7f-81b1-52ce5d8a63f7	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
257	257	1	324.00	321.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	ecdb87d5-eb3f-445a-87f7-8fca0d7e6efd	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
258	258	1	252.00	243.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	21e50884-0ff1-4df0-9528-377a210085a8	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
259	259	1	252.00	252.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	55c1bda5-d771-4a74-bdd9-cb3db31fc2cf	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
260	260	1	1077.00	1070.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	9fb5c51c-754b-47ee-8883-c6729ffe3751	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
261	261	1	225.00	220.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	60d4f29d-39ae-4aa4-a077-9799a1285aa9	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
262	262	1	605.00	594.00	11.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2f6e35af-3523-4abe-b425-1713a14df739	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
263	263	1	582.00	572.00	10.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	c749ac8a-57ec-42e1-bb5e-b487f8239e5f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
264	264	1	200.00	199.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a52b98c9-28b3-456b-bb0c-0cf010bbbfe6	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
265	265	1	411.00	411.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	be9c7be2-36c8-49ff-8ecf-07a424addb70	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
266	266	1	2629.00	2625.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f537487e-c822-4713-929f-0e09fdf1e7b2	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
267	267	1	206.00	206.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	5d236b09-cfa8-4e32-ae53-84f2e6d1a779	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
268	268	1	827.00	823.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f78521a5-9ff2-463b-ad29-35548f42f614	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
269	269	1	2513.00	2497.00	16.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	63454bcb-5eac-4d26-806f-6f8b509ff245	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
270	270	1	172.00	158.00	14.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f1fbd4cb-9935-4ba4-82ab-24a5141d9b0a	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
271	271	1	381.00	366.00	15.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2f711adc-e6da-477f-9895-b949d1eba468	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
272	272	1	189.00	176.00	13.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	dd07bb61-3856-4b54-814c-f925c57cf7fd	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
273	273	1	93.00	90.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	698d7e4c-419e-4000-b6fa-17266f6caceb	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
274	274	1	266.00	254.00	12.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a41f403d-129b-469a-bbe0-c93f4a013510	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
275	275	1	20.00	20.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	cc6ce033-ea92-4aec-8b97-cdbdceb4e9b6	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
276	276	1	284.00	266.00	18.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	04585095-60a8-40b2-814c-81861f71150e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
277	277	1	273.00	273.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	6c1acccc-1eae-4473-9e83-4917e46d4c2e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
278	278	1	72.00	70.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2c1f5439-2248-4e77-a0e7-f26af14a38cd	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
279	279	1	162.00	156.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	e7831ad6-a9c0-4a04-b72f-385fdd83718c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
280	280	1	2407.00	2393.00	14.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	6d960429-9798-4545-adf7-6d8072c4263b	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
281	281	1	79.00	79.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	4715ca18-702d-4d1b-8987-780170614635	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
282	282	1	399.00	357.00	42.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	1f143eb7-4462-453e-a9fb-cbf449fa0aa8	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
283	283	1	347.00	341.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	ec1f820a-6852-4f1b-944e-81a9703699ee	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
284	284	1	470.00	464.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	aff72dd9-c850-485e-88ba-36f111fb501a	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
285	285	1	78.00	74.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	75eeb2f7-46f8-40c8-a7f8-ffa2dd52df94	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
286	286	1	1126.00	1110.00	16.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8006d5e7-0c7d-40ce-b8d3-8ee53ffefd77	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
287	287	1	485.00	467.00	18.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	90408f79-a58b-42f2-ab7e-25449b222125	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
288	288	1	256.00	256.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a1f246c3-535a-441b-b30c-95c43af08ae8	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
289	289	1	35.00	35.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	47ecfed3-3854-4e26-b604-795af79c1ce6	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
290	290	1	407.00	401.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	53baf967-3044-49e9-9020-cd05870b47c8	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
291	291	1	285.00	285.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	af2e8b74-14d1-4ccf-b09d-35856b78d914	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
292	292	1	140.00	135.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	5e47a59d-bb34-430d-8b87-7d7dd13af9b1	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
293	293	1	126.00	122.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f9a492f2-0e1d-4cce-8174-b485ad4a253a	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
294	294	1	5256.00	5245.00	11.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	1d03dbc9-5573-427d-bcc3-432f8010ed06	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
295	295	1	111.00	109.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	0abc8418-39da-446a-880a-41f7181e0c77	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
296	296	1	1056.00	1053.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8beae212-7941-490e-a0ee-b50e3887eb3a	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
297	297	1	256.00	223.00	33.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	88090fdf-fc1f-4909-b8bc-2bd4dcd5ebd0	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
298	298	1	266.00	265.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	d4caaf9a-3de0-4359-9a79-63344f1e28cc	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
299	299	1	1496.00	1496.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	d3336b11-01fd-4f8f-97db-31e0153271eb	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
300	300	1	1311.00	1301.00	10.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8adb7e0b-9f32-4ab9-afdd-660a75ea8a5b	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
301	301	1	649.00	640.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	df068829-24a0-4207-acdf-6d3530101e75	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
302	302	1	1060.00	1056.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	dcb269dc-ebd7-4ad8-8458-26b34c67de69	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
303	303	1	5899.00	5880.00	19.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	ebe66f75-80ba-45aa-9ab1-193ca7cf67d0	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
304	304	1	993.00	975.00	18.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f278c3cd-abbc-4277-882c-35621b3450c8	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
305	305	1	284.00	284.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a297ef87-4cdb-41e4-b2aa-7947d9980d62	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
306	306	1	894.00	880.00	14.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2f983f0b-2262-49f5-8641-ca789ded1d35	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
307	307	1	1050.00	1044.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	75cbce27-6591-4cee-8370-d048a89fbf46	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
308	308	1	150.00	52.00	98.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	424315db-d60f-4e58-8a91-632047853bb0	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
309	309	1	1064.00	1064.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2ebad34d-7ef3-4e98-afdd-fdb0f0385875	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
310	310	1	2422.00	2400.00	22.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8bac01aa-56d6-4809-9a07-3a008d600576	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
311	311	1	399.00	393.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8c6d26ba-a404-4ff2-acf7-3ab1f56d9cd5	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
312	312	1	2266.00	2266.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b358808c-c223-4345-b151-2ec81a60d80d	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
313	313	1	388.00	344.00	44.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b3f1a600-b841-4e96-bd4d-f2d9f0dfee5e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
314	314	1	370.00	358.00	12.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	5831b73c-a3f0-455d-b882-da23a2a93e48	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
315	315	1	476.00	468.00	8.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a91cf208-6877-4470-bd6f-def6ceecc83e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
316	316	1	102.00	101.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	9b4fe5da-46f3-49f7-9270-bbbea973ca19	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
317	317	1	196.00	196.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a061c0c8-1bf1-46f3-b529-906e80f80d6c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
318	318	1	293.00	285.00	8.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	504fc2ce-8809-4f15-82d0-f066ef3b1bb3	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
319	319	1	64.00	63.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8ed66280-44aa-49f3-9026-c2e4021e5fe1	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
320	320	1	54.00	50.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	6e2bfd27-7e4d-4d78-b7c0-edf49e136de3	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
321	321	1	76.00	72.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	28fd5172-2e52-4136-a9cb-f015a5c68d1f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
322	322	1	1147.00	1127.00	20.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	0952aecc-bb70-4c0a-964c-5e64bcc07b6a	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
323	323	1	82.00	71.00	11.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	7b60395b-3967-42dd-9cea-ad476b7abd54	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
324	324	1	225.00	220.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	d42ab8c6-d312-4685-b135-5f0b3e87e7a3	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
325	325	1	244.00	230.00	14.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	cfd92d0f-7bf3-43a0-841b-d02cbd95aeff	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
326	326	1	39.00	37.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	5a748aa2-6403-4e67-a930-01ed0119f01b	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
327	327	1	196.00	189.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	fbc55ba9-72c8-4619-9e38-ab6b21fc8a97	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
328	328	1	87.00	85.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b3a3f814-a886-4205-b5ec-d2a8f948de4f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
329	329	1	59.00	58.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	6e307a49-c69e-4b8c-906c-f56c2c956738	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
330	330	1	1651.00	1651.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	1865dd2d-7dc5-4544-9809-2078424f64aa	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
331	331	1	75.00	63.00	12.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2e9f3006-8d85-4acd-a589-6aca37243b57	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
332	332	1	296.00	296.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	4cb8244f-6b6f-41b1-98f3-3cf638d9ade1	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
333	333	1	763.00	718.00	45.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	cb45c874-ac43-4d1a-8353-2611f41aa836	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
334	334	1	103.00	103.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8df80722-f5a8-4fab-aaae-fca16003fcf9	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
335	335	1	2180.00	2162.00	18.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	9a90c354-fd64-4b03-a25c-a5116b42e190	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
336	336	1	369.00	360.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	bc45c617-c502-47c1-9050-c37d6a703ee6	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
337	337	1	1573.00	1560.00	13.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	81d86021-16b0-4a2d-b570-46dce221ac4c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
338	338	1	4402.00	4402.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	e59893d7-b83e-4590-aeb0-4ab04adad5d2	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
339	339	1	5564.00	5564.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	c4c752a2-cf98-4561-91d9-a954e363d613	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
340	340	1	2053.00	2018.00	35.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	de0faf75-ebb4-48b3-b148-4fe452c71a28	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
341	341	1	641.00	641.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	dfb62a34-3c36-42a6-8f84-19410c2fa8aa	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
342	342	1	1040.00	1040.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	04daafdb-3f23-4dce-a992-8b685a73c0e7	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
343	343	1	269.00	269.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	c23c51a4-f72d-408b-9a56-b41cb9d03e1a	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
344	344	1	223.00	218.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	1513b030-9ad9-446f-9425-8dedc0e9b849	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
345	345	1	1230.00	1222.00	8.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2cddd0c6-ee41-4538-976e-0301aed68a05	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
346	346	1	162.00	159.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	6344604a-af85-478b-a222-5a1c1c767066	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
347	347	1	1114.00	1096.00	18.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	ba1c3805-8873-4f65-8a2e-7195f939d08c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
348	348	1	56.00	55.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	422b93cd-afe1-4464-b1c0-b0412c23869a	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
349	349	1	82.00	79.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a3fdc5ea-dc4d-4949-a5c8-d0a005c84b03	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
350	350	1	89.00	86.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	107c63e8-717f-4a66-ad6b-23f220b40a84	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
351	351	1	109.00	106.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	21a99235-861c-40ae-a6f2-ba60864e32e3	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
352	352	1	56.00	54.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	3a1a9baf-dbd9-4764-9bbb-0f29859f4634	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
353	353	1	68.00	62.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	56d8a4a1-7a8f-40e3-9512-ec8cb58a9f37	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
354	354	1	94.00	93.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	dd5f27ce-2c15-4738-a0f8-1eb28fa78327	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
355	355	1	19.00	19.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	3b6de8a2-6d64-41e1-b47e-3dc7572cd41e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
356	356	1	266.00	266.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	90b83575-f4f8-4912-8103-9bf6d589e408	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
357	357	1	1450.00	1450.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	594095ea-97f8-4ae1-9c62-3d2d172a0e43	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
358	358	1	308.00	308.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	38241b1d-970c-4d61-9d78-10669dbab81e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
359	359	1	471.00	466.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	bd0c82d9-4dcc-4664-8bb1-35227c703966	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
360	360	1	28.00	28.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b5394845-b10b-4351-8e54-456cbec8094b	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
361	361	1	1025.00	1016.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	007a2fb7-adb9-4a65-870f-af149bb30b65	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
362	362	1	888.00	888.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	c05f50b7-64c7-468d-ab4a-2d460f506791	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
363	363	1	163.00	156.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	456b3e66-4c63-4d91-a5e7-174191fa4d92	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
364	364	1	250.00	243.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	64b77152-07e2-4d40-9900-215b2d5a0a60	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
365	365	1	3391.00	3387.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2a95711e-c574-4dd7-971b-26ba8501654e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
366	366	1	1221.00	1217.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	c0ac3bb5-d2f5-45a5-9f60-4e62c58d728c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
367	367	1	1435.00	1426.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	4e71a9f1-124a-4761-a447-5cbc30a64717	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
368	368	1	230.00	227.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	49ce5d56-bf24-467d-97b1-e00e98b93caa	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
369	369	1	446.00	415.00	31.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	becf45bb-b1f5-4bf8-9fb2-caa7e1e94d7b	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
370	370	1	306.00	300.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b358cd8a-8d89-427d-bba9-22c67844931b	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
371	371	1	159.00	154.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	cf9a7987-0fb3-4194-965a-83ecab480604	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
372	372	1	563.00	563.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	639f682d-3222-4416-9aac-2e542411be5f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
373	373	1	59.00	54.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8d6e75f9-721f-4f03-8058-ca1852852b9b	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
374	374	1	281.00	273.00	8.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f67ba687-297c-44c8-8967-e55bd25c5232	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
375	375	1	189.00	185.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	3b1a1c1e-2682-491b-9691-a6978d9d2785	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
376	376	1	353.00	353.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	79f24ae2-b04b-4fb5-9a0b-34d8234d7417	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
377	377	1	1296.00	1286.00	10.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f3185237-decd-4f7d-947d-ab82f8af926f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
378	378	1	408.00	398.00	10.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2e3fb068-2f8b-43fd-854d-2015de1ecac7	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
379	379	1	40.00	24.00	16.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	44d411c3-c787-44a5-8bf6-487324b728aa	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
380	380	1	794.00	785.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	d8192c23-d4a7-4fa0-8b0b-1f10e5129474	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
381	381	1	914.00	912.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	79c12f2a-2cd8-4e86-8d82-b9c932528502	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
382	382	1	88.00	88.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b73941d1-3fff-4afe-a822-2ae8a75f9385	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
383	383	1	477.00	456.00	21.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8956fb34-d589-44e6-9d02-7cd0f964e38e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
384	384	1	214.00	188.00	26.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b112eb35-8917-4caa-af1e-4cbaf5c00701	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
385	385	1	4785.00	4780.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	35c5dde9-ff61-4d42-baa0-d20613866611	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
386	386	1	266.00	261.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	0e8aef67-a4b7-4360-87cc-3aa0c9df42a5	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
387	387	1	464.00	440.00	24.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	3bb72d9e-9132-45e6-b63c-4ec252df1cbc	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
388	388	1	3846.00	3807.00	39.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b1ed7e46-cdf5-48cd-90c1-d723b4ec9e2a	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
389	389	1	2109.00	2091.00	18.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	7a56fb44-0424-4678-b61d-d2873868446f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
390	390	1	598.00	598.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	3dc8e642-49fc-45d6-981c-cdfff74e6536	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
391	391	1	103.00	95.00	8.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	e6e5c155-9ef0-41e4-8d7a-1b72ba202d82	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
392	392	1	537.00	526.00	11.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	673c48ff-944a-46dc-9dd2-c2ce054181da	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
393	393	1	163.00	149.00	14.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	6037657c-d6b4-4e27-a4d6-263c12e8cf2e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
394	394	1	144.00	134.00	10.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	53664268-ba5c-4461-bf59-7b73aa233dbc	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
395	395	1	65.00	59.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	52f67d54-0bcf-4a0d-b7af-9f5c3b8bd31e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
396	396	1	2410.00	2410.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b974f9a3-92ac-422b-9e0f-dc96686a5c87	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
397	397	1	77.00	77.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	d72155fc-fe09-47b7-a268-f86b0f2b5b9d	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
398	398	1	177.00	170.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	c0a28f26-8b59-4698-939f-c30da8cddeae	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
399	399	1	281.00	274.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	56aea50c-19cc-4bac-9f3f-068bd7447ba2	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
400	400	1	1006.00	999.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	c99c9eb3-d1a6-4bd7-816c-60a80abc9bba	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
401	401	1	518.00	513.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	7f1c8071-8138-4c12-8dea-8ae685a4ede7	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
402	402	1	268.00	267.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	cd2d87e7-ff6a-4909-aacf-c38e15c6a210	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
403	403	1	212.00	207.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	76814b79-96bf-4465-8bee-7df07a63f11c	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
404	404	1	238.00	232.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b2b1231f-93d4-4276-bd6b-f7326c236cfe	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
405	405	1	103.00	98.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	278629ad-27c1-4146-b324-474c12e37144	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
406	406	1	108.00	108.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	30f7aa93-c133-446b-98bc-5c9b0a742567	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
407	407	1	47.00	44.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	3f068093-3f91-4773-8eb4-23d26d144ed2	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
408	408	1	349.00	346.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	130f5f9e-d6a0-4cba-9790-eb420acb87bf	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
409	409	1	174.00	174.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	e0047e9b-80fa-42f8-85fa-894abd7aba66	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
410	410	1	590.00	581.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	9008e09e-c42e-4fd4-9686-f232a7e40f54	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
411	411	1	3511.00	3484.00	27.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	934fdc5d-c50c-48f2-8940-7dee901fb5d2	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
412	412	1	452.00	440.00	12.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	db129551-6669-49d4-811f-bd4f524797f7	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
413	413	1	807.00	775.00	32.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	506c8f8e-cddd-4547-a8e0-c9bcef2c1fe5	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
414	414	1	53.00	51.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	27c2e7eb-e4f4-4432-9dd7-9328b2a26b3f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
415	415	1	9.00	8.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	72191b8d-6d9c-4740-8e54-58a63f68cefe	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
416	416	1	88.00	79.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	1cb38d68-baa9-4573-ad1b-c83321ae51e3	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
417	417	1	1691.00	1685.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	d684a4e2-97b7-4500-be4f-32f18cd88f28	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
418	418	1	324.00	321.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2bfc7f6f-ecf4-464c-858a-587c7b8368f4	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
419	419	1	470.00	446.00	24.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	6bc076b9-5c31-426b-a812-15b2489f6511	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
420	420	1	322.00	306.00	16.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	222d235f-f194-4ffc-8ecf-073d2041f0df	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
421	421	1	551.00	542.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a4b80cd5-9edd-4165-8b5c-4859231ab5d7	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
422	422	1	446.00	435.00	11.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8ee264a4-201d-4c8c-928c-783db535c2ee	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
423	423	1	440.00	430.00	10.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f6bb5f20-ad9f-42f9-9f49-cb35f91c297d	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
424	424	1	33.00	28.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	9dc9dbc1-3855-4fe3-832f-9727744ee0e8	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
425	425	1	663.00	654.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	d9592c66-7506-47a1-aa09-d63aa882392e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
426	426	1	850.00	850.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	21825eb4-1cca-467b-9df1-935dd975624d	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
427	427	1	307.00	298.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8aa2b819-5bd9-4e59-ad74-a4c4f65c0a4f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
428	428	1	260.00	254.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	175bd61a-4cd6-4e97-bc34-6c5769783c15	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
429	429	1	294.00	288.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a41b0d08-0067-4b22-a4fc-64075f90f09f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
430	430	1	537.00	524.00	13.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	ef29a98c-fef8-405c-89a6-3620fed11e85	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
431	431	1	591.00	591.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	526b99b0-177d-42b4-bf0b-93ac0536c913	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
432	432	1	84.00	77.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	ac32e10c-d96c-48cd-b017-5b201175cece	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
433	433	1	171.00	162.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	984c5400-cdad-45fc-b24c-645f62305859	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
434	434	1	136.00	123.00	13.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	4ff161d1-df01-4ac4-97f0-d11b3c68ed2b	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
435	435	1	76.00	72.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	16ba07df-9291-4eb2-92b7-2114ae796e24	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
436	436	1	77.00	75.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	d435ca8b-0da5-400c-addc-1b0aeaf2c984	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
437	437	1	789.00	783.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	079449cf-26c5-4777-bde9-40bf727a8bfb	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
438	438	1	27.00	27.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	5aa9b289-77b9-498b-b393-b8cd995de316	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
439	439	1	249.00	249.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	6b5abade-f6f1-417b-bbe6-a3d140b26190	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
440	440	1	154.00	154.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	76e0d3b4-884f-4b19-a3fc-8c4955405114	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
441	441	1	268.00	259.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	bd3f10f2-9c55-4fa0-957a-5d9486dfc088	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
442	442	1	5463.00	5384.00	79.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	ca1dd46a-1d57-495f-9db0-239672f7500f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
443	443	1	351.00	345.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f6fb1e4c-1e9a-4d34-9d09-817896592bdf	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
444	444	1	1298.00	1291.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	bcfa54ee-2aa1-45e7-9070-d23571f12a00	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
445	445	1	15.00	15.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	ed46148a-56a8-4f5a-b3d5-451f2dd6d9c6	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
446	446	1	82.00	80.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	8e3a40b7-ce7e-441d-9b19-7e97220a6aef	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
447	447	1	510.00	510.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	412b9f76-8be5-4ae7-a4c4-c2fcdd93dc81	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
448	448	1	838.00	831.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	c19a8f47-e10c-4347-b69e-61c5afcadef1	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
449	449	1	37.00	37.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	cb16f5f1-0df7-4d73-8ec2-0e106508d8b4	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
450	450	1	68.00	68.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b390d89e-2edf-4e99-9f2a-9b9b21c8daf9	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
451	451	1	301.00	297.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	756c0aea-55a2-43bd-a391-59f45eeccbea	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
452	452	1	198.00	198.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	465deb29-c54b-410e-a9b3-5a6b537602ca	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
453	453	1	176.00	161.00	15.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	320e6b45-4878-4f54-bca8-ea084253ce38	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
454	454	1	332.00	323.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	5c8cf712-5e56-4751-bad8-276d4f3c58f7	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
455	455	1	225.00	219.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	28b3ad02-765a-468f-b031-56d86f7abd85	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
456	456	1	72.00	65.00	7.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	e307eab1-c1ab-4048-b354-5f8ad6500028	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
457	457	1	505.00	494.00	11.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	f31158cc-3347-4b21-bf19-69695828b00f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
458	458	1	234.00	232.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	6af35339-8bcb-432f-857a-710772d5d856	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
459	459	1	144.00	143.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	38392c4e-3635-40bf-a377-6e47ed73fb16	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
460	460	1	408.00	391.00	17.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	4d4ad0e2-961b-4ec6-a4a5-ef16b372349d	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
461	461	1	410.00	406.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	15222604-5a4a-4c3e-9707-55739adeb94b	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
462	462	1	252.00	237.00	15.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	be4f7f33-4261-4913-bd41-c5f3e1f14678	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
463	463	1	540.00	529.00	11.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	1f91f963-9fed-4e81-b9f8-78cc926e3adb	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
464	464	1	346.00	341.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	dd84fd1e-a4d2-40e1-8514-e207b9854bfe	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
465	465	1	1568.00	1542.00	26.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b253ae91-0864-4cb0-bdc5-d153245e4a9d	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
466	466	1	273.00	265.00	8.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	ca4f552c-0215-41b5-b2b8-d9f5d54c2642	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
467	467	1	279.00	274.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	60e5c90a-8d25-497b-bacf-730d8cb90cee	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
468	468	1	102.00	100.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	771ea3fc-43ca-4e2b-b552-4710d619acfd	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
469	469	1	902.00	892.00	10.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2bce04e4-0f24-4e15-a58f-47837ba4c0f5	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
470	470	1	455.00	449.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	4327ce1a-a250-4873-a241-ae24e491daca	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
471	471	1	133.00	124.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	1ca402e7-cf97-4e09-90f6-226293a3cb62	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
472	472	1	667.00	664.00	3.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	7cd7376c-f95f-475b-9ab8-38a50ed0bd9a	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
473	473	1	1903.00	1856.00	47.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	9e7cef57-72bd-411b-ab35-66c67346497e	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
474	474	1	631.00	626.00	5.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	0189f9f9-27e4-4204-a6fb-8ce12e1430d1	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
475	475	1	43.00	41.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	0d0a5863-51f8-4939-b301-0f47a164c4d5	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
476	476	1	131.00	129.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	97f3e9df-2c0e-4fff-96c5-59d7ca26701f	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
477	477	1	82.00	78.00	4.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2580952f-b0d4-457f-83f1-1c1d3a2d4b35	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
478	478	1	264.00	255.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a5688082-6cbe-4d22-88db-4f41f3922ff6	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
479	479	1	231.00	222.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	a2add5fd-06a0-4c7a-b343-8c74add1f4f3	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
480	480	1	346.00	337.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	72e51409-19b0-4856-b465-9083fc96d945	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
481	481	1	647.00	641.00	6.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	3cef25f8-3f78-42f8-b3f9-497439ca0bff	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
482	482	1	527.00	508.00	19.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	0798aead-d1eb-4ff1-ac1d-65aaeb2eff63	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
483	483	1	1962.00	1953.00	9.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	6fc8f3a9-5d21-4f07-9caa-431dd59fd81a	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
484	484	1	198.00	197.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	e37d9a28-6ef0-4ca5-820e-ba25ec9145cc	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
485	485	1	65.00	65.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	e02f1077-4bbd-4da7-b0a7-1e4e9bbd72b2	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
486	486	1	75.00	74.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	c565dc75-13c1-479e-bbdd-429e41497cf9	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
487	487	1	6.00	6.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	86bd554a-0a82-48d2-9f0f-f9b481af1e18	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
488	488	1	95.00	93.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	4be887d0-6027-4f7d-b205-4ab0fae0213d	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
489	489	1	3.00	2.00	1.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	db9e48d7-257c-4fc0-abe3-744a8d1a5021	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
490	490	1	8.00	8.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2be8c15d-5b78-41bd-8402-ee4a8c5e9c68	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
491	491	1	25.00	23.00	2.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	0f099148-f4a6-42ac-bdba-87c2c2333608	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
492	492	1	1610.00	1610.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	b84a889a-c047-4a97-9dce-ea3487f8c7bc	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
493	493	1	84451.00	83081.00	1370.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	2c520a48-bfe7-41bd-ad8a-ea497e29b155	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
494	494	1	918.00	918.00	0.00	0.00	2026-08-30 13:00:00+03	مدير المحطة	\N	APPROVED	15039ae0-e77e-4637-9699-3e683098c502	\N	f	f	2026-08-30 13:00:00+03	2026-08-30 13:00:00+03
\.


--
-- Data for Name: payment_allocations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.payment_allocations (id, payment_id, invoice_id, amount_allocated, is_reversed, reversed_at, reversal_reason, created_at) FROM stdin;
1	1	274	17800.00	f	\N	\N	2026-09-06 02:41:13+03
2	2	276	20000.00	f	\N	\N	2026-09-06 02:40:04+03
3	3	70	33200.00	f	\N	\N	2026-09-06 02:30:31+03
4	4	305	4800.00	f	\N	\N	2026-09-06 02:17:20+03
5	5	308	10.00	f	\N	\N	2026-09-06 01:55:22+03
6	6	322	10.00	f	\N	\N	2026-09-06 01:54:23+03
7	7	405	8000.00	f	\N	\N	2026-09-06 01:22:49+03
8	8	417	100000.00	f	\N	\N	2026-09-06 01:22:04+03
9	9	451	11000.00	f	\N	\N	2026-09-06 01:15:12+03
10	10	464	8000.00	f	\N	\N	2026-09-06 01:08:00+03
11	11	463	16400.00	f	\N	\N	2026-09-06 01:05:36+03
12	12	308	73800.00	f	\N	\N	2026-09-06 00:36:03+03
13	13	145	17800.00	f	\N	\N	2026-09-05 03:08:38+03
14	14	151	13000.00	f	\N	\N	2026-09-05 03:06:21+03
15	15	143	131200.00	f	\N	\N	2026-09-05 03:03:42+03
16	16	327	9000.00	f	\N	\N	2026-09-05 02:51:44+03
17	17	322	25000.00	f	\N	\N	2026-09-05 02:49:47+03
18	18	128	10800.00	f	\N	\N	2026-09-05 02:47:19+03
19	19	19	600.00	f	\N	\N	2026-09-05 02:34:21+03
20	20	19	15000.00	f	\N	\N	2026-09-05 02:33:41+03
21	21	52	13600.00	f	\N	\N	2026-09-04 19:23:32+03
22	22	37	9400.00	f	\N	\N	2026-09-04 19:21:37+03
23	23	35	1000.00	f	\N	\N	2026-09-04 19:20:51+03
24	24	29	20000.00	f	\N	\N	2026-09-04 19:18:54+03
25	25	27	7000.00	f	\N	\N	2026-09-04 19:18:21+03
26	26	24	29000.00	f	\N	\N	2026-09-04 19:17:47+03
27	27	21	1000.00	f	\N	\N	2026-09-04 19:17:06+03
28	28	19	20000.00	f	\N	\N	2026-09-04 19:16:18+03
29	29	17	1000.00	f	\N	\N	2026-09-04 19:14:21+03
30	30	15	50400.00	f	\N	\N	2026-09-04 19:13:36+03
31	31	10	6600.00	f	\N	\N	2026-09-04 19:12:24+03
32	32	169	4800.00	f	\N	\N	2026-09-04 19:03:19+03
33	33	458	9000.00	f	\N	\N	2026-09-04 19:00:02+03
34	34	144	16000.00	f	\N	\N	2026-09-04 18:56:15+03
35	35	30	5200.00	f	\N	\N	2026-09-04 18:27:22+03
36	36	117	9000.00	f	\N	\N	2026-09-04 18:25:27+03
37	37	116	10800.00	f	\N	\N	2026-09-04 18:24:20+03
38	38	96	10800.00	f	\N	\N	2026-09-04 18:21:26+03
39	39	75	1000.00	f	\N	\N	2026-09-04 18:12:38+03
40	40	42	50000.00	f	\N	\N	2026-09-04 17:50:48+03
41	42	282	45500.00	f	\N	\N	2026-09-04 17:39:30+03
42	43	364	3800.00	f	\N	\N	2026-09-04 17:31:14+03
43	44	462	22000.00	f	\N	\N	2026-09-04 17:12:27+03
44	45	391	5000.00	f	\N	\N	2026-09-04 16:58:55+03
45	46	201	5200.00	f	\N	\N	2026-09-04 15:22:35+03
\.


--
-- Data for Name: payment_receipt_counters; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.payment_receipt_counters (year, last_value) FROM stdin;
2026	11
\.


--
-- Data for Name: payments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.payments (id, receipt_number, customer_id, invoice_id, shift_id, payment_method, amount_paid, payment_date, accountant_name, accountant_user_id, approval_status, notes, client_mutation_id, rejection_reason, whatsapp_sent, created_at, updated_at) FROM stdin;
1	REC-2026-0063	274	274	\N	CASH	17800.00	2026-09-06 02:41:13+03	مدير المحطة	\N	APPROVED	\N	82ad84a4-3d07-4f98-8c53-2ec13345842e	\N	f	2026-09-06 02:41:13+03	2026-09-06 02:41:13+03
2	REC-2026-0062	276	276	\N	CASH	20000.00	2026-09-06 02:40:04+03	مدير المحطة	\N	APPROVED	\N	ad79410b-c66e-4e8f-bcae-ca4300f30d46	\N	f	2026-09-06 02:40:04+03	2026-09-06 02:40:04+03
3	REC-2026-0061	70	70	\N	CASH	33200.00	2026-09-06 02:30:31+03	مدير المحطة	\N	APPROVED	\N	6b6f95e2-4967-4eaa-abfc-11aefbd6f883	\N	f	2026-09-06 02:30:31+03	2026-09-06 02:30:31+03
4	REC-2026-0060	305	305	\N	CASH	4800.00	2026-09-06 02:17:20+03	مدير المحطة	\N	APPROVED	\N	3ef90188-a8bf-492c-bc3e-ab404ac37757	\N	f	2026-09-06 02:17:20+03	2026-09-06 02:17:20+03
5	REC-2026-0059	308	308	\N	CASH	10.00	2026-09-06 01:55:22+03	مدير المحطة	\N	APPROVED	\N	6dc0b646-0dd6-422f-bb7c-ced9af4c1d89	\N	f	2026-09-06 01:55:22+03	2026-09-06 01:55:22+03
6	REC-2026-0058	322	322	\N	CASH	10.00	2026-09-06 01:54:23+03	مدير المحطة	\N	APPROVED	\N	e5b2a9a6-f5b3-4022-a1a6-b408404c83d7	\N	f	2026-09-06 01:54:23+03	2026-09-06 01:54:23+03
7	REC-2026-0057	405	405	\N	CASH	8000.00	2026-09-06 01:22:49+03	مدير المحطة	\N	APPROVED	\N	9003337a-13ef-4049-9e19-fa56b167155a	\N	f	2026-09-06 01:22:49+03	2026-09-06 01:22:49+03
8	REC-2026-0056	417	417	\N	CASH	100000.00	2026-09-06 01:22:04+03	مدير المحطة	\N	APPROVED	\N	15fa2bcc-cddc-4b8f-9849-7c4e82099c45	\N	f	2026-09-06 01:22:04+03	2026-09-06 01:22:04+03
9	REC-2026-0055	451	451	\N	CASH	11000.00	2026-09-06 01:15:12+03	مدير المحطة	\N	APPROVED	\N	30ba8ece-1eb9-48f9-9efc-9fec379e7832	\N	f	2026-09-06 01:15:12+03	2026-09-06 01:15:12+03
10	REC-2026-0054	464	464	\N	CASH	8000.00	2026-09-06 01:08:00+03	مدير المحطة	\N	APPROVED	\N	341a8d34-1981-42f9-9a45-0cbab720f74f	\N	f	2026-09-06 01:08:00+03	2026-09-06 01:08:00+03
11	REC-2026-0053	463	463	\N	CASH	16400.00	2026-09-06 01:05:36+03	مدير المحطة	\N	APPROVED	\N	80801ee3-6d22-44c3-94dd-cd9bfcc1e801	\N	f	2026-09-06 01:05:36+03	2026-09-06 01:05:36+03
12	REC-2026-0052	308	308	\N	CASH	73800.00	2026-09-06 00:36:03+03	مدير المحطة	\N	APPROVED	\N	b5b14657-4287-4a20-9fb4-647ee560d220	\N	f	2026-09-06 00:36:03+03	2026-09-06 00:36:03+03
13	REC-2026-0051	145	145	\N	CASH	17800.00	2026-09-05 03:08:38+03	مدير المحطة	\N	APPROVED	\N	7e8c6e77-cad2-4eb6-af30-19bc7472a566	\N	f	2026-09-05 03:08:38+03	2026-09-05 03:08:38+03
14	REC-2026-0050	151	151	\N	CASH	13000.00	2026-09-05 03:06:21+03	مدير المحطة	\N	APPROVED	\N	748521dd-9898-4c23-8f4d-a0b85b69a8cb	\N	f	2026-09-05 03:06:21+03	2026-09-05 03:06:21+03
15	REC-2026-0049	143	143	\N	CASH	131200.00	2026-09-05 03:03:42+03	مدير المحطة	\N	APPROVED	\N	37b5ea87-929c-4033-afd0-5e65937354a2	\N	f	2026-09-05 03:03:42+03	2026-09-05 03:03:42+03
16	REC-2026-0048	327	327	\N	CASH	9000.00	2026-09-05 02:51:44+03	مدير المحطة	\N	APPROVED	\N	53bc8dcc-9d09-4523-92e7-ebe36287b855	\N	f	2026-09-05 02:51:44+03	2026-09-05 02:51:44+03
17	REC-2026-0047	322	322	\N	CASH	25000.00	2026-09-05 02:49:47+03	مدير المحطة	\N	APPROVED	\N	f7b0f5fb-e576-4870-9dea-f57b92a73b0e	\N	f	2026-09-05 02:49:47+03	2026-09-05 02:49:47+03
18	REC-2026-0046	128	128	\N	CASH	10800.00	2026-09-05 02:47:19+03	مدير المحطة	\N	APPROVED	\N	4fe077b5-0101-453d-99fb-4e0ffaa71e5c	\N	f	2026-09-05 02:47:19+03	2026-09-05 02:47:19+03
19	REC-2026-0045	19	19	\N	CASH	600.00	2026-09-05 02:34:21+03	مدير المحطة	\N	APPROVED	\N	b6c20482-4c7a-41bb-885a-4a7c855ef5cd	\N	f	2026-09-05 02:34:21+03	2026-09-05 02:34:21+03
20	REC-2026-0044	19	19	\N	CASH	15000.00	2026-09-05 02:33:41+03	مدير المحطة	\N	APPROVED	\N	467a6bea-e718-4232-89da-961091e2845d	\N	f	2026-09-05 02:33:41+03	2026-09-05 02:33:41+03
21	REC-2026-0043	52	52	\N	CASH	13600.00	2026-09-04 19:23:32+03	مدير المحطة	\N	APPROVED	\N	26d4da6e-4ba6-4086-a161-2ad4e7d03da2	\N	f	2026-09-04 19:23:32+03	2026-09-04 19:23:32+03
22	REC-2026-0042	37	37	\N	CASH	9400.00	2026-09-04 19:21:37+03	مدير المحطة	\N	APPROVED	\N	e7042080-62ce-4eff-aa4d-36b5108cc198	\N	f	2026-09-04 19:21:37+03	2026-09-04 19:21:37+03
23	REC-2026-0041	35	35	\N	CASH	1000.00	2026-09-04 19:20:51+03	مدير المحطة	\N	APPROVED	\N	fc4a168d-04c0-4911-82c5-db0a7f886ac8	\N	f	2026-09-04 19:20:51+03	2026-09-04 19:20:51+03
24	REC-2026-0040	29	29	\N	CASH	20000.00	2026-09-04 19:18:54+03	مدير المحطة	\N	APPROVED	\N	1ff12445-2f44-4235-87cc-79861ce485c2	\N	f	2026-09-04 19:18:54+03	2026-09-04 19:18:54+03
25	REC-2026-0039	27	27	\N	CASH	7000.00	2026-09-04 19:18:21+03	مدير المحطة	\N	APPROVED	\N	cb7af07d-7c78-45de-a991-e8e4b162d876	\N	f	2026-09-04 19:18:21+03	2026-09-04 19:18:21+03
26	REC-2026-0038	24	24	\N	CASH	29000.00	2026-09-04 19:17:47+03	مدير المحطة	\N	APPROVED	\N	62589e3e-2f0b-4ca5-8780-d223a702c9d0	\N	f	2026-09-04 19:17:47+03	2026-09-04 19:17:47+03
27	REC-2026-0037	21	21	\N	CASH	1000.00	2026-09-04 19:17:06+03	مدير المحطة	\N	APPROVED	\N	d2c5596a-403f-4c3a-b8d5-3c7d824a9a14	\N	f	2026-09-04 19:17:06+03	2026-09-04 19:17:06+03
28	REC-2026-0036	19	19	\N	CASH	20000.00	2026-09-04 19:16:18+03	مدير المحطة	\N	APPROVED	\N	5f6fc992-2d39-4990-95b4-a675f3cb7962	\N	f	2026-09-04 19:16:18+03	2026-09-04 19:16:18+03
29	REC-2026-0035	17	17	\N	CASH	1000.00	2026-09-04 19:14:21+03	مدير المحطة	\N	APPROVED	\N	c8d09e23-f4ad-4ed2-9b16-48b62bba8d5b	\N	f	2026-09-04 19:14:21+03	2026-09-04 19:14:21+03
30	REC-2026-0034	15	15	\N	CASH	50400.00	2026-09-04 19:13:36+03	مدير المحطة	\N	APPROVED	\N	bee2b4b4-4be3-43ef-ae06-dec00f84e7f9	\N	f	2026-09-04 19:13:36+03	2026-09-04 19:13:36+03
31	REC-2026-0033	10	10	\N	CASH	6600.00	2026-09-04 19:12:24+03	مدير المحطة	\N	APPROVED	\N	32fde91c-6009-4a20-8cde-997ea4f3ff87	\N	f	2026-09-04 19:12:24+03	2026-09-04 19:12:24+03
32	REC-2026-0032	169	169	\N	CASH	6800.00	2026-09-04 19:03:19+03	مدير المحطة	\N	APPROVED	\N	95342e9e-075f-4767-bd2b-808c4c62c762	\N	f	2026-09-04 19:03:19+03	2026-09-04 19:03:19+03
33	REC-2026-0031	458	458	\N	CASH	9000.00	2026-09-04 19:00:02+03	مدير المحطة	\N	APPROVED	\N	ce55bda6-85f4-449c-ac64-650ce78362d0	\N	f	2026-09-04 19:00:02+03	2026-09-04 19:00:02+03
34	REC-2026-0030	144	144	\N	CASH	16000.00	2026-09-04 18:56:15+03	مدير المحطة	\N	APPROVED	\N	1968f491-985e-4786-9be6-40b5e44e064c	\N	f	2026-09-04 18:56:15+03	2026-09-04 18:56:15+03
35	REC-2026-0029	30	30	\N	CASH	5200.00	2026-09-04 18:27:22+03	مدير المحطة	\N	APPROVED	\N	efdf1407-85ca-4c8d-9e1e-38e039489e71	\N	f	2026-09-04 18:27:22+03	2026-09-04 18:27:22+03
36	REC-2026-0028	117	117	\N	CASH	9000.00	2026-09-04 18:25:27+03	مدير المحطة	\N	APPROVED	\N	9d050860-27c9-4bba-9eb9-c651ef1671f7	\N	f	2026-09-04 18:25:27+03	2026-09-04 18:25:27+03
37	REC-2026-0027	116	116	\N	CASH	10800.00	2026-09-04 18:24:20+03	مدير المحطة	\N	APPROVED	\N	4bd48c13-c952-4ab3-a38c-e4060ff76f76	\N	f	2026-09-04 18:24:20+03	2026-09-04 18:24:20+03
38	REC-2026-0026	96	96	\N	CASH	10800.00	2026-09-04 18:21:26+03	مدير المحطة	\N	APPROVED	\N	52c692c9-b3d5-4533-a5ab-b3b5652a8ccd	\N	f	2026-09-04 18:21:26+03	2026-09-04 18:21:26+03
39	REC-2026-0025	75	75	\N	CASH	1000.00	2026-09-04 18:12:38+03	مدير المحطة	\N	APPROVED	\N	c9b82a32-d92c-41b6-97ac-0169920e0c65	\N	f	2026-09-04 18:12:38+03	2026-09-04 18:12:38+03
40	REC-2026-0024	42	42	\N	CASH	50000.00	2026-09-04 17:50:48+03	مدير المحطة	\N	APPROVED	\N	dede7a0c-d151-4f3c-b280-4d4d20a1cbde	\N	f	2026-09-04 17:50:48+03	2026-09-04 17:50:48+03
41	REC-2026-0023	145	145	\N	CASH	17800.00	2026-09-04 17:48:47+03	مدير المحطة	\N	APPROVED	\N	f4ff7ed0-ad0a-423c-8310-1eace7689b25	\N	f	2026-09-04 17:48:47+03	2026-09-04 17:48:47+03
42	REC-2026-0022	282	282	\N	CASH	45500.00	2026-09-04 17:39:30+03	مدير المحطة	\N	APPROVED	\N	94985b5a-f922-4b37-8f39-d30296b5e69c	\N	f	2026-09-04 17:39:30+03	2026-09-04 17:39:30+03
43	REC-2026-0021	364	364	\N	CASH	3800.00	2026-09-04 17:31:14+03	مدير المحطة	\N	APPROVED	\N	b099f7f9-8ec4-40ae-bd26-8ace52a77580	\N	f	2026-09-04 17:31:14+03	2026-09-04 17:31:14+03
44	REC-2026-0020	462	462	\N	CASH	22000.00	2026-09-04 17:12:27+03	مدير المحطة	\N	APPROVED	\N	93cf1235-6f9f-4cd5-a766-86785074e95d	\N	f	2026-09-04 17:12:27+03	2026-09-04 17:12:27+03
45	REC-2026-0019	391	391	\N	CASH	5000.00	2026-09-04 16:58:55+03	مدير المحطة	\N	APPROVED	\N	23341f3a-b5bb-4f94-b4d6-094a7204682e	\N	f	2026-09-04 16:58:55+03	2026-09-04 16:58:55+03
46	REC-2026-0018	201	201	\N	CASH	7000.00	2026-09-04 15:22:35+03	مدير المحطة	\N	APPROVED	\N	eb63b8ca-00a2-4c53-a40e-83215ffc1fac	\N	f	2026-09-04 15:22:35+03	2026-09-04 15:22:35+03
\.


--
-- Data for Name: shifts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.shifts (id, user_id, cashier_name, start_time, end_time, starting_cash, ending_cash, total_collected, status, created_at) FROM stdin;
\.


--
-- Data for Name: subscription_plans; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.subscription_plans (id, plan_name, kwh_price, fixed_fee, grace_period_days, description, is_active, created_at, updated_at) FROM stdin;
2	الاشتراك الصناعي عالي الجهد	1200.00	3000.00	5	\N	t	2026-09-06 12:44:31.723041+03	2026-09-06 12:44:31.723041+03
1	باقة تجارية	1400.00	1000.00	10	\N	t	2026-09-06 12:44:31.723041+03	2026-09-06 12:44:31.723041+03
\.


--
-- Data for Name: system_settings; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.system_settings (id, station_name, station_logo_url, station_phone, station_phone_alt, bank_accounts, invoice_policy_text, whatsapp_status, receipt_footer, arrears_threshold, default_kwh_price, default_fixed_fee, max_overdue_days, currency, created_at, updated_at) FROM stdin;
1	محطة الضياء لتوليد الطاقة الكهربائية	\N	+967 783270260	+967 736955883	بنك الكريمي: 3052001225	1- نرجو تسديد الفاتورة خلال فترة السماح المحددة تفادياً لفصل التيار.\n2- في حال وجود أي اعتراض على القراءة يرجى مراجعة إدارة المحطة خلال 48 ساعة.\n3- إعادة التيار بعد الفصل تتطلب سداد الرسوم المقررة.\n4- المشترك مسؤول عن سلامة العداد والوصلات التابعة له.\n5- استخدام الطاقة في غير الغرض المخصص يعرض المشترك للمساءلة.	Disconnected	شكراً لاختياركم خدماتنا - نرجو المحافظة على الطاقة	0.00	1000.00	1000.00	7	YER	2026-09-06 12:44:31.704319+03	2026-09-06 12:44:31.704319+03
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.users (id, username, password_hash, full_name, role, phone_number, is_active, supabase_uid, created_at, updated_at) FROM stdin;
1	admin	$2a$10$qTS36FZ/kK4Isy.OZTYgMuROb3XMvLds/97lo9VtAuxmU77E7KZ6m	مدير النظام	ADMIN	+967 783270260	t	\N	2026-09-06 12:44:31.690358+03	2026-09-06 12:44:31.690358+03
\.


--
-- Data for Name: whatsapp_queue_messages; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.whatsapp_queue_messages (id, phone_number, type, message, image_base64, caption, media_path, status, retries, max_retries, error_msg, source_entity, source_id, client_mutation_id, scheduled_at, processing_started_at, sent_at, created_at, updated_at) FROM stdin;
9	967771234567	PAYMENT_RECEIPT	تم استلام دفعة بقيمة: 49500.00 ريال بنجاح. رقم السند: REC-2026-000006. المشترك: مشترك الفحص والتدقيق الآلي. شكراً لكم.	\N	\N	\N	FAILED	3	3	failed to get user info for 967771234567@s.whatsapp.net to fill LID cache: failed to send usync query: info query returned status 429: rate-overlimit	PAYMENT	17	5e654b4d-5195-4a93-83d0-81d374615031	2026-09-07 10:25:40.477849+03	\N	\N	2026-09-07 10:25:40.477849+03	2026-09-07 11:49:10.753418+03
10	967771234567	PAYMENT_RECEIPT	تم استلام دفعة بقيمة: 226500.00 ريال بنجاح. رقم السند: REC-2026-000007. المشترك: مشترك الفحص والتدقيق الآلي. شكراً لكم.	\N	\N	\N	FAILED	3	3	no LID found for 967771234567@s.whatsapp.net from server	PAYMENT	18	0937d0f7-044f-4372-a79b-2f4cd987e924	2026-09-07 10:25:40.499779+03	\N	\N	2026-09-07 10:25:40.499779+03	2026-09-07 11:49:14.912143+03
12	967734019059	TEXT	رسالة تجريبية لفحص طابور الإرسال في نظام SmartPower	\N	\N	\N	SENT	0	3	\N	\N	\N	\N	2026-09-07 10:34:11.185082+03	\N	2026-09-07 11:48:16.175475+03	2026-09-07 10:34:11.185082+03	2026-09-07 11:48:16.175475+03
5	967773245776	PAYMENT_RECEIPT	تم استلام دفعة بقيمة: 106000.00 ريال بنجاح. رقم السند: REC-2026-000002. المشترك: محمد علي الأهدل. شكراً لكم.	\N	\N	\N	SENT	0	3	\N	PAYMENT	12	1e5fb6d4-13e1-4204-87b3-68533b7a943a	2026-09-07 09:35:26.803927+03	\N	2026-09-07 11:47:38.758023+03	2026-09-07 09:35:26.803927+03	2026-09-07 11:47:38.758023+03
6	967734019059	PAYMENT_RECEIPT	تم استلام دفعة بقيمة: 100000.00 ريال بنجاح. رقم السند: REC-2026-000003. المشترك: حسين يحيى الحوثي. شكراً لكم.	\N	\N	\N	SENT	0	3	\N	PAYMENT	13	560e5bc2-7d21-4a97-9e50-cae35cfb27f8	2026-09-07 09:35:43.886857+03	\N	2026-09-07 11:47:47.232958+03	2026-09-07 09:35:43.886857+03	2026-09-07 11:47:47.232958+03
15	967734019059	PAYMENT_RECEIPT	تم استلام دفعة بقيمة: 50000.00 ريال بنجاح. رقم السند: REC-2026-000010. المشترك: عبدالله أحمد الصنعاني. شكراً لكم.	\N	\N	\N	SENT	0	3	\N	PAYMENT	21	91f073af-ea55-4535-a8e9-bfc76debb3fe	2026-09-07 11:53:49.37603+03	\N	2026-09-07 11:53:50.755874+03	2026-09-07 11:53:49.37603+03	2026-09-07 11:53:50.755874+03
13	967773245776	PAYMENT_RECEIPT	تم استلام دفعة بقيمة: 180000.00 ريال بنجاح. رقم السند: REC-2026-000008. المشترك: هشام شرف القاسمي. شكراً لكم.	\N	\N	\N	SENT	0	3	\N	PAYMENT	19	99e43df0-346c-42a1-b399-21c760d73e48	2026-09-07 11:18:45.531977+03	\N	2026-09-07 11:48:21.888471+03	2026-09-07 11:18:45.531977+03	2026-09-07 11:48:21.888471+03
14	967773245776	PAYMENT_RECEIPT	تم استلام دفعة بقيمة: 180000.00 ريال بنجاح. رقم السند: REC-2026-000009. المشترك: هشام شرف القاسمي. شكراً لكم.	\N	\N	\N	SENT	0	3	\N	PAYMENT	20	dd87e5e5-470e-49bb-9515-c300aff4579b	2026-09-07 11:20:17.489826+03	\N	2026-09-07 11:48:28.323017+03	2026-09-07 11:20:17.489826+03	2026-09-07 11:48:28.323017+03
23	967734019059	IMAGE	⚡ *محطة الضياء لتوليد الطاقة الكهربائية* ⚡\n📋 *سند قبض وتسديد رسمي*\n────────────────────\n👤 *المشترك:* عبدالله أحمد الصنعاني\n🔢 *رقم الاشتراك:* 10001\n📄 *رقم السند:* REC-2026-000010\n💵 *المبلغ المسدد:* 50000.00 ر.ي\n📅 *التاريخ:* 2026-09-07 11:53\n💼 *المحصل/المستلم:* مدير النظام\n💳 *الرصيد المتبقي:* 540000.00 ر.ي\n────────────────────\n🙏 شكراً لالتزامكم بالسداد.\n📞 للاستفسار: +967 783270260	\N	\N	\N	SENT	0	3	\N	PAYMENT	21	\N	2026-09-07 13:46:47.471303+03	\N	2026-09-07 13:46:50.756741+03	2026-09-07 13:46:47.471303+03	2026-09-07 13:46:50.756741+03
7	967771234567	PAYMENT_RECEIPT	تم استلام دفعة بقيمة: 71500.00 ريال بنجاح. رقم السند: REC-2026-000004. المشترك: مشترك الفحص والتدقيق الآلي. شكراً لكم.	\N	\N	\N	FAILED	3	3	no LID found for 967771234567@s.whatsapp.net from server	PAYMENT	14	61a29912-c79b-4387-a51c-5cf14948d74d	2026-09-07 10:24:45.466157+03	\N	\N	2026-09-07 10:24:45.466157+03	2026-09-07 11:48:58.467072+03
8	967771234567	PAYMENT_RECEIPT	تم استلام دفعة بقيمة: 71500.00 ريال بنجاح. رقم السند: REC-2026-000005. المشترك: مشترك الفحص والتدقيق الآلي. شكراً لكم.	\N	\N	\N	FAILED	3	3	no LID found for 967771234567@s.whatsapp.net from server	PAYMENT	16	d1068754-c540-4065-83b5-341df37ff8be	2026-09-07 10:25:40.452605+03	\N	\N	2026-09-07 10:25:40.452605+03	2026-09-07 11:49:04.654865+03
16	967734019059	TEXT	⚡ *محطة الضياء لتوليد الطاقة الكهربائية* ⚡\n🧾 *فاتورة استهلاك الكهرباء الرسمية*\n────────────────────\n👤 *المشترك:* عبدالله أحمد الصنعاني\n🔢 *رقم المشترك:* 10001\n📄 *رقم الفاتورة:* INV-2026-08-2-10001\n📅 *الدورة:* 2026-08-2\n🔌 *القراءة السابقة:* 135.00\n⚡ *القراءة الحالية:* 185.00\n📊 *كمية الاستهلاك:* 50.00 ك.و.ت\n💰 *قيمة الاستهلاك:* 70000.00 ر.ي (سعر الوحدة: 1400.00)\n🛠️ *رسوم الاشتراك:* 1000.00 ر.ي\n⏳ *المتأخرات السابقة:* 0.00 ر.ي\n💳 *إجمالي المستحق:* 71000.00 ر.ي\n💵 *المسدد:* 50000.00 ر.ي\n⚠️ *المتبقي للدفع:* 21000.00 ر.ي\n📅 *تاريخ الاستحقاق:* 2026-08-31\n────────────────────\n📞 للاستفسار أو السداد: +967 783270260	\N	\N	\N	SENT	0	3	\N	INVOICE	55	\N	2026-09-07 12:45:09.21741+03	\N	2026-09-07 12:45:09.772285+03	2026-09-07 12:45:09.21741+03	2026-09-07 12:45:09.772285+03
17	967773245776	TEXT	⚡ *محطة الضياء لتوليد الطاقة الكهربائية* ⚡\n🧾 *فاتورة استهلاك الكهرباء الرسمية*\n────────────────────\n👤 *المشترك:* محمد علي الأهدل\n🔢 *رقم المشترك:* 10002\n📄 *رقم الفاتورة:* INV-2026-08-2-10002\n📅 *الدورة:* 2026-08-2\n🔌 *القراءة السابقة:* 285.00\n⚡ *القراءة الحالية:* 360.00\n📊 *كمية الاستهلاك:* 75.00 ك.و.ت\n💰 *قيمة الاستهلاك:* 105000.00 ر.ي (سعر الوحدة: 1400.00)\n🛠️ *رسوم الاشتراك:* 1000.00 ر.ي\n⏳ *المتأخرات السابقة:* 0.00 ر.ي\n💳 *إجمالي المستحق:* 106000.00 ر.ي\n💵 *المسدد:* 106000.00 ر.ي\n⚠️ *المتبقي للدفع:* 0.00 ر.ي\n📅 *تاريخ الاستحقاق:* 2026-08-31\n────────────────────\n📞 للاستفسار أو السداد: +967 783270260	\N	\N	\N	SENT	0	3	\N	INVOICE	56	\N	2026-09-07 12:45:11.894436+03	\N	2026-09-07 12:45:12.062453+03	2026-09-07 12:45:11.894436+03	2026-09-07 12:45:12.062453+03
18	967734019059	IMAGE	⚡ *محطة الضياء لتوليد الطاقة الكهربائية* ⚡\n🧾 *فاتورة استهلاك الكهرباء الرسمية*\n────────────────────\n👤 *المشترك:* عبدالله أحمد الصنعاني\n🔢 *رقم المشترك:* 10001\n📄 *رقم الفاتورة:* INV-2026-08-2-10001\n📅 *الدورة:* 2026-08-2\n🔌 *القراءة السابقة:* 135.00\n⚡ *القراءة الحالية:* 185.00\n📊 *كمية الاستهلاك:* 50.00 ك.و.ت\n💰 *قيمة الاستهلاك:* 70000.00 ر.ي (سعر الوحدة: 1400.00)\n🛠️ *رسوم الاشتراك:* 1000.00 ر.ي\n⏳ *المتأخرات السابقة:* 0.00 ر.ي\n💳 *إجمالي المستحق:* 71000.00 ر.ي\n💵 *المسدد:* 50000.00 ر.ي\n⚠️ *المتبقي للدفع:* 21000.00 ر.ي\n📅 *تاريخ الاستحقاق:* 2026-08-31\n────────────────────\n📞 للاستفسار أو السداد: +967 783270260	\N	\N	\N	SENT	0	3	\N	INVOICE	55	\N	2026-09-07 13:29:09.836248+03	\N	2026-09-07 13:29:14.894952+03	2026-09-07 13:29:09.836248+03	2026-09-07 13:29:14.894952+03
19	967734019059	IMAGE	⚡ *محطة الضياء لتوليد الطاقة الكهربائية* ⚡\n🧾 *فاتورة استهلاك الكهرباء الرسمية*\n────────────────────\n👤 *المشترك:* عبدالله أحمد الصنعاني\n🔢 *رقم المشترك:* 10001\n📄 *رقم الفاتورة:* INV-2026-08-2-10001\n📅 *الدورة:* 2026-08-2\n🔌 *القراءة السابقة:* 135.00\n⚡ *القراءة الحالية:* 185.00\n📊 *كمية الاستهلاك:* 50.00 ك.و.ت\n💰 *قيمة الاستهلاك:* 70000.00 ر.ي (سعر الوحدة: 1400.00)\n🛠️ *رسوم الاشتراك:* 1000.00 ر.ي\n⏳ *المتأخرات السابقة:* 0.00 ر.ي\n💳 *إجمالي المستحق:* 71000.00 ر.ي\n💵 *المسدد:* 50000.00 ر.ي\n⚠️ *المتبقي للدفع:* 21000.00 ر.ي\n📅 *تاريخ الاستحقاق:* 2026-08-31\n────────────────────\n📞 للاستفسار أو السداد: +967 783270260	\N	\N	\N	SENT	0	3	\N	INVOICE	55	\N	2026-09-07 13:37:47.365239+03	\N	2026-09-07 13:37:52.088797+03	2026-09-07 13:37:47.365239+03	2026-09-07 13:37:52.088797+03
20	967734019059	IMAGE	⚡ *محطة الضياء لتوليد الطاقة الكهربائية* ⚡\n📋 *سند قبض وتسديد رسمي*\n────────────────────\n👤 *المشترك:* عبدالله أحمد الصنعاني\n🔢 *رقم الاشتراك:* 10001\n📄 *رقم السند:* REC-2026-000010\n💵 *المبلغ المسدد:* 50000.00 ر.ي\n📅 *التاريخ:* 2026-09-07 11:53\n💼 *المحصل/المستلم:* مدير النظام\n💳 *الرصيد المتبقي:* 540000.00 ر.ي\n────────────────────\n🙏 شكراً لالتزامكم بالسداد.\n📞 للاستفسار: +967 783270260	\N	\N	\N	SENT	0	3	\N	PAYMENT	21	\N	2026-09-07 13:38:24.930032+03	\N	2026-09-07 13:38:33.165539+03	2026-09-07 13:38:24.930032+03	2026-09-07 13:38:33.165539+03
21	967734019059	IMAGE	⚡ *محطة الضياء لتوليد الطاقة الكهربائية* ⚡\n📋 *سند قبض وتسديد رسمي*\n────────────────────\n👤 *المشترك:* عبدالله أحمد الصنعاني\n🔢 *رقم الاشتراك:* 10001\n📄 *رقم السند:* REC-2026-000010\n💵 *المبلغ المسدد:* 50000.00 ر.ي\n📅 *التاريخ:* 2026-09-07 11:53\n💼 *المحصل/المستلم:* مدير النظام\n💳 *الرصيد المتبقي:* 540000.00 ر.ي\n────────────────────\n🙏 شكراً لالتزامكم بالسداد.\n📞 للاستفسار: +967 783270260	\N	\N	\N	SENT	0	3	\N	PAYMENT	21	\N	2026-09-07 13:38:48.758091+03	\N	2026-09-07 13:38:53.468602+03	2026-09-07 13:38:48.758091+03	2026-09-07 13:38:53.468602+03
22	967773245776	IMAGE	⚡ *محطة الضياء لتوليد الطاقة الكهربائية* ⚡\n📋 *سند قبض وتسديد رسمي*\n────────────────────\n👤 *المشترك:* هشام شرف القاسمي\n🔢 *رقم الاشتراك:* 10012\n📄 *رقم السند:* REC-2026-000009\n💵 *المبلغ المسدد:* 180000.00 ر.ي\n📅 *التاريخ:* 2026-09-07 11:20\n💼 *المحصل/المستلم:* مدير النظام\n💳 *الرصيد المتبقي:* -1947000.00 ر.ي\n────────────────────\n🙏 شكراً لالتزامكم بالسداد.\n📞 للاستفسار: +967 783270260	\N	\N	\N	SENT	0	3	\N	PAYMENT	20	\N	2026-09-07 13:39:40.966708+03	\N	2026-09-07 13:39:46.456926+03	2026-09-07 13:39:40.966708+03	2026-09-07 13:39:46.456926+03
24	967773245776	IMAGE	⚡ *محطة الضياء لتوليد الطاقة الكهربائية* ⚡\n🧾 *فاتورة استهلاك الكهرباء الرسمية*\n────────────────────\n👤 *المشترك:* محمد سعيد احمد خالد\n🔢 *رقم المشترك:* 10017\n📄 *رقم الفاتورة:* INV-أغسطس-2-10017\n📅 *الدورة:* أغسطس 2\n🔌 *القراءة السابقة:* 10.00\n⚡ *القراءة الحالية:* 20.00\n📊 *كمية الاستهلاك:* 10.00 ك.و.ت\n💰 *قيمة الاستهلاك:* 14000.00 ر.ي (سعر الوحدة: 1400.00)\n🛠️ *رسوم الاشتراك:* 1000.00 ر.ي\n⏳ *المتأخرات السابقة:* 5000.00 ر.ي\n💳 *إجمالي المستحق:* 20000.00 ر.ي\n💵 *المسدد:* 0.00 ر.ي\n⚠️ *المتبقي للدفع:* 20000.00 ر.ي\n📅 *تاريخ الاستحقاق:* 2026-09-22\n────────────────────\n📞 للاستفسار أو السداد: +967 783270260	\N	\N	\N	SENT	0	3	\N	INVOICE	284	\N	2026-09-07 14:11:38.862088+03	\N	2026-09-07 14:11:44.766759+03	2026-09-07 14:11:38.862088+03	2026-09-07 14:11:44.766759+03
25	967773245776	PAYMENT_RECEIPT	تم استلام دفعة بقيمة: 10000.00 ريال بنجاح. رقم السند: REC-2026-000011. المشترك: محمد سعيد احمد خالد. شكراً لكم.	\N	\N	\N	SENT	0	3	\N	PAYMENT	22	1079c6ed-359a-461d-86cd-22d500e8b064	2026-09-07 14:12:14.413348+03	\N	2026-09-07 14:12:14.716382+03	2026-09-07 14:12:14.413348+03	2026-09-07 14:12:14.716382+03
26	967773245776	IMAGE	⚡ *محطة الضياء لتوليد الطاقة الكهربائية* ⚡\n📋 *سند قبض وتسديد رسمي*\n────────────────────\n👤 *المشترك:* محمد سعيد احمد خالد\n🔢 *رقم الاشتراك:* 10017\n📄 *رقم السند:* REC-2026-000011\n💵 *المبلغ المسدد:* 10000.00 ر.ي\n📅 *التاريخ:* 2026-09-07 14:12\n💼 *المحصل/المستلم:* مدير النظام\n💳 *الرصيد المتبقي:* 10000.00 ر.ي\n────────────────────\n🙏 شكراً لالتزامكم بالسداد.\n📞 للاستفسار: +967 783270260	\N	\N	\N	SENT	0	3	\N	PAYMENT	22	\N	2026-09-07 14:12:25.272519+03	\N	2026-09-07 14:12:29.373531+03	2026-09-07 14:12:25.272519+03	2026-09-07 14:12:29.373531+03
\.


--
-- Data for Name: whatsapp_sessions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.whatsapp_sessions (session_id, jid, status, qr_code, push_name, auth_data, device_props, keys_data, is_active, last_connected_at, last_heartbeat_at, created_at, updated_at) FROM stdin;
default	\N	CONNECTED	\N	\N	\N	\N	\N	t	\N	\N	2026-09-07 09:29:02.707293+03	2026-09-07 15:59:00.957578+03
\.


--
-- Data for Name: whatsmeow_app_state_mutation_macs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.whatsmeow_app_state_mutation_macs (jid, name, version, index_mac, value_mac) FROM stdin;
\.


--
-- Data for Name: whatsmeow_app_state_sync_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.whatsmeow_app_state_sync_keys (jid, key_id, key_data, "timestamp", fingerprint) FROM stdin;
\.


--
-- Data for Name: whatsmeow_app_state_version; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.whatsmeow_app_state_version (jid, name, version, hash) FROM stdin;
\.


--
-- Data for Name: whatsmeow_chat_settings; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.whatsmeow_chat_settings (our_jid, chat_jid, muted_until, pinned, archived) FROM stdin;
\.


--
-- Data for Name: whatsmeow_contacts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.whatsmeow_contacts (our_jid, their_jid, first_name, full_name, push_name, business_name, redacted_phone) FROM stdin;
\.


--
-- Data for Name: whatsmeow_device; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.whatsmeow_device (jid, lid, facebook_uuid, registration_id, noise_key, identity_key, signed_pre_key, signed_pre_key_id, signed_pre_key_sig, adv_key, adv_details, adv_account_sig, adv_account_sig_key, adv_device_sig, platform, business_name, push_name, lid_migration_ts, companion_meta_nonce) FROM stdin;
\.


--
-- Data for Name: whatsmeow_event_buffer; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.whatsmeow_event_buffer (our_jid, ciphertext_hash, plaintext, server_timestamp, insert_timestamp) FROM stdin;
\.


--
-- Data for Name: whatsmeow_identity_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.whatsmeow_identity_keys (our_jid, their_id, identity) FROM stdin;
\.


--
-- Data for Name: whatsmeow_lid_map; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.whatsmeow_lid_map (lid, pn) FROM stdin;
107065112543457	967773245776
131542265364518	967734019059
48009480003590	967775835545
187596319793287	967730236125
167323436589308	967730519437
209663660445848	967771490777
251247013658648	967735597599
224579578507397	967778149050
80011063234693	967776952497
105493389381839	967735250061
81518563197172	967774167665
28042009256116	967737190150
5871539064853	967779219044
265248808407088	967776205244
186294240059635	967771286402
122093219876884	967736625293
155340494610460	967774874843
196546293415997	967776776487
267293263171663	967733928960
112622766710923	967739884850
73938080129242	967775845496
86947368272110	967774590799
277360783966247	967737234660
215414084780137	967736916563
274513052856373	967770697066
70197146824836	967778875293
46038006112460	967780546967
5304536289315	967734197270
105781017985252	967773059161
8559987277934	967714512107
243172743590038	212771574897
234921960456257	967777656768
63853647945836	967736883207
40196749975589	967773440094
154064855814237	967738633102
190074146844774	967739976062
83086226272262	967773009199
46356286677240	967735969625
152780694114470	967777676609
275071767683312	967783494957
265197201653794	967776364540
3028102963239	967775314098
203345495113982	967780547624
127878758977658	967781692934
52828148080660	967773540827
31091553493136	967780803946
100317702148157	967774689557
75643148570851	967777888278
124768833544218	967737755278
23901493002286	967773516960
44904084451373	967734530863
171764399272031	967775301969
95151007482068	967735309184
233856758243362	967773145959
128789409448143	12035948956
258957016830154	967776671365
130962746777702	967734699405
126504386224163	967779839858
227745288208638	967774201508
207541409722418	967775959064
270364483563766	966556940185
26423024681076	967730661583
99734022836273	967733904934
100197543710934	967774553583
49723306205400	967738963850
232607006650541	967777390344
112837531836670	967736748360
105613564596436	967735253864
164939813667046	967772196480
100914752958518	967774224945
43658711711807	967733479453
19941768036578	967734662398
199153858650139	967730863662
220611129401598	967777796073
54778046468229	967773935385
269960236499110	967772190023
277326642311319	967782934821
97028143079674	967773610292
133024247218411	967778361803
132010769178675	967737208695
70875952996582	967774527847
42907109212355	967774918406
231271305322563	967737670326
156113504891100	967774450003
237718219005993	967734258309
279791836098712	967733483388
127534977016004	967770693580
140054706057437	967736639182
83911262646304	967738021990
151964566450410	967776383387
261026805227613	967733556909
8624478908584	967736358726
210818503315677	967713544424
76807537688617	967734417234
13404844601469	967774125338
137503864549428	967714201479
110359587352655	967739188425
103246769160361	967779174516
165502739595359	967781782164
244834812092479	967774150900
16381173080306	967733094909
76695382032467	967772356204
51145208770761	967784872690
160374129172608	967772706028
93346869596287	967776589417
146505830793339	967778925698
210839961378947	967776953597
266038931365899	967775704523
1099830460416	967778546120
36047912206457	967777273034
157397733666865	967777600885
112330759254197	967738721085
153472418721835	966553148326
75579093180446	967733605198
67023317016778	967775835791
76776969621713	967772679392
231593763422461	967737549482
183670031827087	967735187298
255859892420727	967733801718
193420043800595	967712331386
274732247179331	967737466065
233002579824771	967772511473
279860085833854	967775915640
87364047220760	967777362415
4234871349473	967739936553
211381378928862	967777118064
191122370515095	967738952575
157389462454335	967781583540
18743807737920	967774874825
10587127959806	967777775201
25920479973475	967776513748
138018941886476	967770188822
272352617230443	967778158340
108559643738214	967775985863
132624731349025	967736680343
270622282223819	967778475074
202439223423062	967770561130
8645836316726	967772807671
15921494110352	967774173232
151586676469841	967775973958
95387062956156	967775677815
188068296425621	967773922232
184804003848312	967734708228
272232324542608	967773573777
277463594721477	967735979148
152978178728150	967770390393
234260485136407	967776846666
242158913249475	967773954154
110789033742373	967776303960
266163787448555	905314735903
172146936524879	447974904959
89357029474371	967777505861
143108343877840	967736248596
170656499019832	967736581249
73556113227971	967739392890
186105429242080	967778190067
55714466799723	967779355543
30542116466911	967784497692
202915797016654	967736487030
128334277177512	967733308542
4643295862996	967782324517
164536019599377	967738949173
141042464628894	967770536294
120727504220296	967776898970
245496136380608	967779498108
14053267218649	967772404587
102336219365628	967774813344
248459613438171	967778920898
21655527129291	967780010286
12816182431999	967738295007
213111999099093	967776143057
121693704040535	967777000111
24872440828014	967779345612
29605243187320	967774599959
115943313293502	967782733815
109882577522717	967738803627
148893866168511	967733323868
195390947225855	967735672004
94352210702578	967781103952
217282848542935	967774408227
73263770296532	967712584498
138483335204993	967730785398
247742488166648	967734216075
42429981921302	967774888442
21998973546557	967772460768
48370055938116	967735662556
94077164982422	967776576301
171781562318946	967771668910
128123203018776	967777246919
227319935430716	967774859711
183159383716059	967739410849
231756586311811	967776102999
109346243498083	967730905634
151896115388525	967774452390
280281294569633	967737150589
67048818352176	967776600383
36898466721904	967730715283
14560274698351	967739435529
17128413470828	967776843545
206059696337023	967772221841
236648436654151	967770342614
94562747953161	967775147078
13057002582096	967777680410
121942862483623	967737682947
5570606186538	967775279624
214018321051741	967738899128
29798835458246	967739472725
97749311713381	967712888955
35446801359093	967777026725
248597052424342	967770284689
175153279434831	967772157905
27062974820502	967736336750
182626421895237	967771077368
268263707639922	967730631741
77868562432161	967730682870
237451561975884	967714534870
277313690333270	967782101577
222612819022000	967739138025
268207889874996	967738717383
269419204894750	967772258987
98380705484927	9671503888
56315728634081	967776121387
15552563179683	967736955883
275776192651300	967735450637
139195611934831	967771200824
43310735466669	967776027396
248442500698142	967774739001
184366001037359	967739099035
67899221889083	967777184621
101348527841477	967770070385
195159186788375	967739067142
33226303266904	967738086188
225636274729141	967775164271
86230410780807	967730189640
25684391026889	967735227458
219503027855480	967770411325
6081690476614	967736044517
7245676982462	967772103752
217359805579339	967776014433
67624427880525	967733542047
195343820034212	967777450001
109453181477039	967711695698
253974301147196	967736067210
42481823535123	967772921501
151105874976877	967781133817
110720112979987	967738999786
22329920872517	967777444555
63110417248361	967778945125
166172418928653	967735745987
30408653672467	967739937202
198303455174867	967781132419
27148572209204	967778888230
184091005743323	967773653701
2470277316830	967781783939
92668516417785	967736653223
107361331097753	967739149085
17480751804629	967778527078
145977566605342	967770508651
47571577921670	967735937128
274577745785081	967777054864
158154268631166	967784334483
266073660256387	84919952812
101954084684013	967770657489
79461542309974	967770792849
277463561203887	967775977855
201468376272986	967735586354
233041100324897	967730659319
9509091188762	967772860555
167203177550057	967736559803
12154908446825	967778876100
192844367175763	967739593203
2719150522622	967733175389
88721324011540	967779337342
116432721424475	967737980155
154855280771235	967780018563
276377236406329	967775981873
259158393786405	967777682860
58970253332726	967781469569
236098982793353	967714829577
172236929552616	967774881855
279606850490521	967775913140
243365899681821	967733243048
263719816814768	967779009630
122626416599274	201037759262
146514655580355	967782625070
188025564860571	967772198044
79689209085993	967775296692
25391997681892	967779673198
20457264799785	967715110619
232920941862934	967739159025
210118541099024	967772209809
203930013307112	967781663145
76429597393092	967739666116
210221486096625	967777710515
32624840040495	967716696093
78138591711285	967776752772
218880542810301	967779327106
194270564757706	967738372991
105523068309533	967774039887
90563764338772	967737244112
233968930693170	967730556091
144539054510205	967771467483
99003593162811	967735092599
199617782263987	967771539600
53790371803389	967735692789
95159345782824	967779241926
194334519468270	967777004166
12030287335449	994400425843
196872828379366	967736221852
218970653257966	967781243953
178056861851795	967772890449
57123736186994	967736143563
72731613728886	967771447341
129488969064579	967774280744
215014803771606	967775949168
265523585646598	967773805959
124021559549980	967736651035
209306741948586	967735809444
36589463978176	967733836323
69037455315155	967774443029
85594537517081	967774055403
50878585290833	967781370951
160163692581111	967776278243
154558810562659	967772764318
152446173204614	967772742886
150474716102887	967736717517
33350706274394	967772520449
171231806525559	967775945451
7701144842476	967776400025
33406809301123	967775593351
223703421956162	967738442444
6709359693865	967738225022
60211196915772	967733219184
198260606124229	967773296824
44698345427061	967733521072
203242281693390	967777418334
7340115923049	967773282077
212292113318008	967778432986
105093554782423	967775148927
253600991318105	967771358911
251186984783928	967779169645
248021828796468	967736252585
36107974656238	967733799352
94700438569045	967737918899
224970521190530	967739204643
78259152752807	967739341261
216651656126615	967734263854
80900322754783	967735618943
226130732798192	967736331427
272584444764224	967774581090
268762158743615	967780750531
116634316472448	967777216542
78275795767463	967711858345
45857768534248	967739274816
53682964066372	967736102227
11454711365781	967773245748
150357430342	967739019976
150066258014214	967717318734
67186341204031	967779617543
122608968306892	967739949048
141386062016701	967773067722
276806464716879	967777561925
231920097095915	967781772543
153686915416073	967771099131
241240293556468	967733214913
72521076494373	967713156029
267684004507655	967770740444
220121587011820	201554497134
11849965826114	967715444014
210033161822329	967780000285
17016794669293	967774083986
201885273354453	967738201809
53292205924512	967778901263
162277420490994	967734367618
217432954249216	967771689869
270149231861960	967738249538
164398597427335	967736595797
157522438668358	967780292057
70352185126971	967776900176
150358332563471	967774220562
155220503970028	967772447658
23781384949988	967738362160
147704059588826	967739893892
26216715313269	967735357277
212309309923477	967782569000
244224977051650	967777171869
192457954316467	967773245565
22282458165273	967771302096
141240737767668	966573752578
9170409492516	967734270407
16411103625255	967713668006
245277160140858	967730641723
222118696472736	967716798253
3698117885976	967772117190
43555414401160	967734118176
155473789587669	967770899115
219701149978879	967738023566
44191069507598	967739388106
117948995891287	967778016636
261580755316967	967775711837
267770172313667	967777756100
68135428337779	967773635182
6704527835146	967774181200
106472591651045	967736505711
250564432642159	967778934620
17747509518509	967773557985
248717512814729	967776438752
22205215858756	967773959109
142760954847377	967776280624
89627478241316	967714133945
207700457685122	967774785152
19525038829671	967771336941
17991735464138	967776602131
232010459148377	967714453112
127019547377760	967771604615
227666882620	967777644435
113997089128555	967773307418
154202781261996	967735815342
63669148860591	967739707469
259961535889413	967772064359
243701477593169	967736176289
242125023228089	967738727997
135476656738372	447723442693
45702864453874	967774442944
99308569415854	967774703898
169183123890352	967775406066
71223610466486	967738349152
268723487252716	967777581853
256083583045807	967782536858
152849463902249	967773928813
84370505347306	967771939854
145779897401556	967777904522
267434929995897	967775818308
105656497533144	967715200134
118030096961708	967730590287
94532532207783	967780774413
74114358358063	967713079291
66563805819050	967711308183
205282407874714	967737594017
115204176273604	967774228851
174921317658670	966570358208
200472145195138	967730081955
52892992049164	967777334095
43237620318261	967776353423
96280768467041	967774231182
80823231504542	967774471818
196164175556714	967771338329
162500087689423	967737714222
36206708564118	967775254473
68234179010655	967777316849
220392572612665	966509142457
31229328019710	967737280788
96684075962619	967772949401
87695028154440	967776214538
62599400034524	19716786701
165674085257321	967772572032
64618001096902	967772106777
58918864720007	967734781691
274538705199145	967775780633
106184929448173	967781999269
52415948677198	967775816485
110694712238138	967778485132
161452618952718	967730382840
97422894174285	967779269529
218485170954469	967738416527
130657401483423	967735457078
121591128174621	967733388080
71532814545123	967712538718
81544802775149	967772897474
183537458258111	967735553756
105351454154978	967773522078
82223055278224	967772040942
11060044144700	967739662604
88936189796538	967736570081
95730609991686	967734997756
243344324210876	967738624231
176025476555003	967733230634
240672854515715	967730481753
69432541991041	967775151399
171596912304376	967774331774
125370548375668	967770225002
230086196363374	967775738686
2937824796838	967773883557
169608644399293	967781525711
147914714271936	967739264089
240436983636168	967736327870
274169421938886	967738908827
21719733514406	967779500919
178052332032164	967771969429
146253014921460	967730585543
237339959906509	967774563173
65838073798659	967779708617
266426065641539	967730804248
39286485328102	967776380717
82751789256944	967730985355
185427294216282	967739276671
104634580517020	967739960239
61753543151657	967733483021
196796022304941	967783470913
137791728050293	967734008148
94416316428491	967716469295
26474211999881	967737039885
237718168686688	967773196964
238602999083260	967776696972
249945856675874	967777504082
183344318963963	967781164424
47627261485250	967780304567
195713522757666	967736478357
189713050775623	967774618937
2555723645011	967733387141
270214210002957	967784683057
266584409006131	967776613851
195425692848284	967733624200
132710446194733	967714070957
110007265845269	967772901288
33763056693279	967780656546
185383790850149	966555431868
56620805542102	967780392981
227852897276013	967783160384
110591498825756	967736561856
273822083211445	967781646162
269432358223971	967779141630
227814125097042	967738057853
176034116800697	967736119966
43688877117469	967770785894
3629801070691	967738369989
260125415763974	967739704919
29455019958495	967777243959
125933323350128	967783831468
141922932895890	967770654475
259047026651149	967730663364
183249628356819	967772131581
235652725645510	967738038003
29592324690139	967770857939
250482895368204	967739272300
103697740767464	967737730086
5867546112055	967736803073
65872014139413	967776460524
112459776053295	967739143779
104428220760262	967780875301
136223494508546	967774568150
76699593081006	967711171104
239577621090534	967776474748
54958904836223	967773140757
182923412172896	967737725747
39775826354398	967773959752
255095975465019	967734174565
224549496979586	967774831383
264527606218944	967736678103
153339509661928	967780854998
118713332285477	967773675221
256745091895370	967738856773
19005666533578	967774617620
45733549998085	967784558518
174672058568739	967775051987
72576558747685	967771279100
73190890021081	967779945274
197728080556260	967730036626
81969685778586	967737203429
25323211071594	967771625940
245449512485011	967739309338
167954780029140	967779666076
215741055897748	967739675663
29167190069490	967776087099
257345934368790	967775772719
91281594282099	967730889446
219301583835383	967777726029
19611441455258	967736119933
225679559893083	967777369032
69634875240557	967771428299
173130802819162	967783101054
24468512612605	967779456912
115478903164960	967771490202
96379468824696	967779557562
225490229055673	967776945145
131108339499100	967772033087
123751211528385	967770750287
242575894151335	967774311653
156676783120494	967783137406
6799000354995	967776386948
208104302084176	967770634549
136283993157751	967781954340
45415051301094	967778198819
106116310667451	967774465821
66701077024878	967737029998
9917733814367	967773585811
272872476024861	967737218662
82695820452081	967782797853
123064486514817	967780783913
63544695492773	967783521276
257448980037685	967770963016
76798796820485	967780592801
20809166905536	967772046650
49641852768295	967772434322
267250296701010	967735783425
242764486828131	967777439292
81952740774117	967735775610
203199466238145	967773249538
196005177856030	967779641340
244285324677325	967730777494
206957948440741	967730713487
269874454614198	967739577281
122574642110517	967737671167
84521030570194	967770129194
211063836553391	967770537194
258123239575783	967774276336
133934780276866	967733870901
129059908546691	967735162286
79268419768428	967739802752
147880186802240	967778367928
94227656638492	967711982655
44393050423420	967738471736
106709167169736	6288976467989
231890049048749	967734514470
62049459638301	967772449481
230966530453737	967775712648
206987677671431	967773493711
133071575761079	967783099180
180041220645028	967715634964
39453821296692	967737083039
15071627505692	967738610974
247489554821278	967739764955
25100309012668	967780662626
19301650174158	201005395145
227316160585798	2349081343289
274277299450088	967730395934
275977536045170	967773525353
269256499441699	967778529024
122037469245543	967781069898
74741473906732	967737011043
240488607162606	967738358446
87725227167827	967778043741
218833365241941	967735166777
73328597463111	967774881886
274148400042097	967730809417
9741069733946	967774330876
79337004998757	967739412454
77791001346231	967738539656
57140295262303	967776934020
36400183435465	967774656989
111347446595627	967733997184
48855320154142	967772436299
254331286716583	967778074666
92183319285953	967778969898
196795955150940	967733599670
168187027038215	967713570527
231808293720084	967778128941
133496425209888	967738563857
176360265887799	967773279966
195700520443952	967780347963
122458745106572	967779820556
175213694189613	967771632996
124502931464359	967733345874
70175739133995	967776298499
236639947325642	967730027115
206240537911475	967779448062
248592975581191	967777769451
2745088114920	967715227049
149258854523123	967737601070
98174966464530	967770566221
270896992366705	967739745832
45711521513553	967733512947
13297655013503	967776756868
137357718224997	967734265704
178331840450783	967738905787
25641474883678	967774875579
257298723254513	967737425883
150904112197753	967775936290
24520220004378	967780623232
141940196647026	967774806089
166769385820409	967775338729
166563160272913	967770044654
274792661946582	967775349088
182226872438964	967735564462
44942705614991	967739070937
242880954278128	967734307303
102868929511670	967775388700
161482515951831	967733246928
152098062745655	967736296848
35257973796930	967772029494
129906151313467	967770661466
77236564676791	967739319094
220971772444700	967775531586
272318374879418	967739047185
227762132512774	967770681000
80865728139396	967775933139
17266338963555	967772614626
226843563131127	967773908236
239478937542814	967772756239
62380239278148	967772980820
69304078860432	967737208978
177287676879037	967774562825
154168035664085	967779066329
188325977698370	967773621391
190434689191988	967773943529
254107478696157	967734500302
241845783281702	967776472301
153223495180522	967774963086
173057637409007	967778949278
277974645506124	967775924646
131417610706958	967779448884
277305100382242	967736612558
154288764530898	967736191428
186260316516571	967781490730
266945169510624	967736016660
171240581001256	967734707891
159777447526417	967775296908
263741492981845	967734823256
166005317865629	967736732353
257406030323947	967779010865
67053163704421	967734753223
33896469160173	967772547138
171425214238820	967778335628
192797407764578	967776427885
173168903892998	967772052276
167203664076821	967739273561
174882964914323	967733728369
192513386233869	967717188820
176609357213784	967779820261
19796242473041	967737837072
168362768379962	967733907794
40579253669946	967711037851
70235935760555	967779024296
74874617868450	967739817161
265708655124627	967712894217
152991063662695	967773026315
90340593811527	967780716034
112614059319418	967737893037
240307950104735	967735573187
160477325856997	967774572927
223986923393124	967776244226
53382316327094	967772397619
\.


--
-- Data for Name: whatsmeow_message_secrets; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.whatsmeow_message_secrets (our_jid, chat_jid, sender_jid, message_id, key) FROM stdin;
\.


--
-- Data for Name: whatsmeow_nct_salt; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.whatsmeow_nct_salt (our_jid, salt) FROM stdin;
\.


--
-- Data for Name: whatsmeow_pre_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.whatsmeow_pre_keys (jid, key_id, key, uploaded) FROM stdin;
\.


--
-- Data for Name: whatsmeow_privacy_tokens; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.whatsmeow_privacy_tokens (our_jid, their_jid, token, "timestamp", sender_timestamp) FROM stdin;
967773245776:15@s.whatsapp.net	107065112543457@lid	\\x04013659d07c8411a4e8f6	1788770859	1788770859
967773245776:15@s.whatsapp.net	243701477593169@lid	\\x040135408a8b7054ee947c	1787692682	1787601648
967773245776:15@s.whatsapp.net	152780694114470@lid	\\x04013678cad0065c774edc	1787946215	1787413587
967773245776:15@s.whatsapp.net	46356286677240@lid	\\x040136850989804d2a91c3	1788689456	1785175114
967773245776:15@s.whatsapp.net	157397733666865@lid	\\x0401358f4fd6a3df7224eb	1787813565	1787738206
967773245776:15@s.whatsapp.net	15552563179683@lid	\\x0401361c6ce4ce4e4df100	1788643760	1787424516
967773245776:15@s.whatsapp.net	131542265364518@lid	\\x0401360501d195e05acc53	1788697372	1788774309
967773245776:15@s.whatsapp.net	54778046468229@lid	\\x04013661866546869e64f8	1788629032	1788629029
967773245776:15@s.whatsapp.net	167323436589308@lid	\\x04013650c41c269eba3f8e	1788456422	1787930203
967773245776:15@s.whatsapp.net	206240537911475@lid	\\x0401351b76599aa7882b6f	1788149566	1788547410
967773245776:15@s.whatsapp.net	80011063234693@lid	\\x04013601f5761c944dcecb	1788529941	1788529967
967773245776:15@s.whatsapp.net	19525038829671@lid	\\x0401356b0284e7520add59	1787306791	0
967773245776:15@s.whatsapp.net	30408653672467@lid	\\x040136d53b463bc4f11aeb	1788378214	1788431455
967773245776:15@s.whatsapp.net	74741473906732@lid	\\x0401364988a0e879f06e4e	1788262284	1788263672
967773245776:15@s.whatsapp.net	201468376272986@lid	\\x0401368c85fabd62213fa8	1788275887	1788276142
967773245776:15@s.whatsapp.net	171781562318946@lid	\\x0401357c840e5c21cd1fe5	1788008978	1788178266
967773245776:15@s.whatsapp.net	70197146824836@lid	\\x040135bddda30326daea67	1788126436	1788151098
967773245776:15@s.whatsapp.net	52892992049164@lid	\\x040135267adfbc624e6f5a	1788115584	1788115268
967773245776:15@s.whatsapp.net	129488969064579@lid	\\x0401354c9f9fb87fe1ab2a	1788115527	1788115394
967773245776:15@s.whatsapp.net	17480751804629@lid	\\x040135d0e26337728bc54c	1788030912	1788030202
967773245776:15@s.whatsapp.net	117948995891287@lid	\\x040136d5358fba1f87eba8	1787983907	1787715201
967773245776:15@s.whatsapp.net	155220503970028@lid	\\x040135248fbeeef757607f	1787870553	1787599357
967773245776:15@s.whatsapp.net	67899221889083@lid	\\x040136a78aef530e7856df	1787834027	1787774928
967773245776:15@s.whatsapp.net	36047912206457@lid	\\x040136e16c12aabbf87787	1787836184	1787812356
967773245776:15@s.whatsapp.net	269960236499110@lid	\\x040135ff5f25b61d25c8cb	1787680707	1787598213
967773245776:15@s.whatsapp.net	234921960456257@lid	\\x040135da9859b83a8d9c3f	1787596015	1787584935
967773245776:15@s.whatsapp.net	105416130351225@lid	\\x040135ffb654eefa3a7308	1787521670	1787540873
967773245776:15@s.whatsapp.net	199153858650139@lid	\\x0401356fa676f93d83d463	1787434647	1787462323
967773245776:15@s.whatsapp.net	248459613438171@lid	\\x040135aea877a6567e49cd	1787419138	1787420715
967773245776:15@s.whatsapp.net	165674085257321@lid	\\x040136fd3f19fb37417ebf	1787106862	1787423234
967773245776:15@s.whatsapp.net	12154908446825@lid	\\x0401352008fac11f95a11c	1787373899	1787378893
967773245776:15@s.whatsapp.net	78138591711285@lid	\\x040134b0fffca385bc6372	1787322789	1787327713
967773245776:15@s.whatsapp.net	75579093180446@lid	\\x0401344003aa1040629c55	1787329872	1787329855
967773245776:15@s.whatsapp.net	135476656738372@lid	\\x040134b2ab44603dbbb16b	1787258133	0
967773245776:15@s.whatsapp.net	184366001037359@lid	\\x0401344f359a7e69a023ae	1787241654	1782325078
967773245776:15@s.whatsapp.net	153472418721835@lid	\\x0401342d730f78835fc792	1787214658	1787212705
967773245776:15@s.whatsapp.net	6081690476614@lid	\\x040134aaee97ffca04c30a	1787209996	1787204151
967773245776:15@s.whatsapp.net	4643295862996@lid	\\x0401348e4efbbf413026e0	1787155342	1786712184
967773245776:15@s.whatsapp.net	152446173204614@lid	\\x040134a99ea72a040bb420	1787083888	1787108744
967773245776:15@s.whatsapp.net	22282458165273@lid	\\x040134a3b0bc7b505505e4	1787087308	1785717863
967773245776:15@s.whatsapp.net	45780559732908@lid	\\x040134466b3615f56b5566	1786628478	1786620447
967773245776:15@s.whatsapp.net	266038931365899@lid	\\x04013481a82394984dfc22	1786861848	1783924433
967773245776:15@s.whatsapp.net	165502739595359@lid	\\x040136594d2a298b6fcf2a	1788771120	1788618580
967773245776:15@s.whatsapp.net	243365899681821@lid	\\x0401347521e4a5528830ae	1786915055	0
\.


--
-- Data for Name: whatsmeow_retry_buffer; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.whatsmeow_retry_buffer (our_jid, chat_jid, message_id, format, plaintext, "timestamp") FROM stdin;
\.


--
-- Data for Name: whatsmeow_sender_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.whatsmeow_sender_keys (our_jid, chat_id, sender_id, sender_key) FROM stdin;
\.


--
-- Data for Name: whatsmeow_sessions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.whatsmeow_sessions (our_jid, their_id, session) FROM stdin;
\.


--
-- Data for Name: whatsmeow_version; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.whatsmeow_version (version, compat) FROM stdin;
15	8
\.


--
-- Name: audit_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.audit_logs_id_seq', 93, true);


--
-- Name: billing_cycles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.billing_cycles_id_seq', 1, true);


--
-- Name: collector_customer_assignments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.collector_customer_assignments_id_seq', 1, false);


--
-- Name: customer_credits_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.customer_credits_id_seq', 3, true);


--
-- Name: customers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.customers_id_seq', 494, true);


--
-- Name: invoices_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.invoices_id_seq', 494, true);


--
-- Name: meter_readings_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.meter_readings_id_seq', 494, true);


--
-- Name: payment_allocations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.payment_allocations_id_seq', 45, true);


--
-- Name: payments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.payments_id_seq', 46, true);


--
-- Name: shifts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.shifts_id_seq', 1, false);


--
-- Name: subscription_plans_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.subscription_plans_id_seq', 5, true);


--
-- Name: system_settings_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.system_settings_id_seq', 1, true);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.users_id_seq', 1, true);


--
-- Name: whatsapp_queue_messages_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.whatsapp_queue_messages_id_seq', 26, true);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: billing_cycles billing_cycles_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_cycles
    ADD CONSTRAINT billing_cycles_code_key UNIQUE (code);


--
-- Name: billing_cycles billing_cycles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_cycles
    ADD CONSTRAINT billing_cycles_pkey PRIMARY KEY (id);


--
-- Name: collector_customer_assignments collector_customer_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collector_customer_assignments
    ADD CONSTRAINT collector_customer_assignments_pkey PRIMARY KEY (id);


--
-- Name: customer_credits customer_credits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_pkey PRIMARY KEY (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: customers customers_subscriber_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_subscriber_number_key UNIQUE (subscriber_number);


--
-- Name: invoices invoices_invoice_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_invoice_number_key UNIQUE (invoice_number);


--
-- Name: invoices invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_pkey PRIMARY KEY (id);


--
-- Name: meter_readings meter_readings_client_mutation_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_client_mutation_id_key UNIQUE (client_mutation_id);


--
-- Name: meter_readings meter_readings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_pkey PRIMARY KEY (id);


--
-- Name: payment_allocations payment_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_allocations
    ADD CONSTRAINT payment_allocations_pkey PRIMARY KEY (id);


--
-- Name: payment_receipt_counters payment_receipt_counters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_receipt_counters
    ADD CONSTRAINT payment_receipt_counters_pkey PRIMARY KEY (year);


--
-- Name: payments payments_client_mutation_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_client_mutation_id_key UNIQUE (client_mutation_id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: payments payments_receipt_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_receipt_number_key UNIQUE (receipt_number);


--
-- Name: shifts shifts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shifts
    ADD CONSTRAINT shifts_pkey PRIMARY KEY (id);


--
-- Name: subscription_plans subscription_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_plans
    ADD CONSTRAINT subscription_plans_pkey PRIMARY KEY (id);


--
-- Name: subscription_plans subscription_plans_plan_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_plans
    ADD CONSTRAINT subscription_plans_plan_name_key UNIQUE (plan_name);


--
-- Name: system_settings system_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_settings
    ADD CONSTRAINT system_settings_pkey PRIMARY KEY (id);


--
-- Name: collector_customer_assignments uq_collector_customer; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collector_customer_assignments
    ADD CONSTRAINT uq_collector_customer UNIQUE (collector_user_id, customer_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_supabase_uid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_supabase_uid_key UNIQUE (supabase_uid);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: whatsapp_queue_messages whatsapp_queue_messages_client_mutation_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_queue_messages
    ADD CONSTRAINT whatsapp_queue_messages_client_mutation_id_key UNIQUE (client_mutation_id);


--
-- Name: whatsapp_queue_messages whatsapp_queue_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_queue_messages
    ADD CONSTRAINT whatsapp_queue_messages_pkey PRIMARY KEY (id);


--
-- Name: whatsapp_sessions whatsapp_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_sessions
    ADD CONSTRAINT whatsapp_sessions_pkey PRIMARY KEY (session_id);


--
-- Name: whatsmeow_app_state_mutation_macs whatsmeow_app_state_mutation_macs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_app_state_mutation_macs
    ADD CONSTRAINT whatsmeow_app_state_mutation_macs_pkey PRIMARY KEY (jid, name, version, index_mac);


--
-- Name: whatsmeow_app_state_sync_keys whatsmeow_app_state_sync_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_app_state_sync_keys
    ADD CONSTRAINT whatsmeow_app_state_sync_keys_pkey PRIMARY KEY (jid, key_id);


--
-- Name: whatsmeow_app_state_version whatsmeow_app_state_version_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_app_state_version
    ADD CONSTRAINT whatsmeow_app_state_version_pkey PRIMARY KEY (jid, name);


--
-- Name: whatsmeow_chat_settings whatsmeow_chat_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_chat_settings
    ADD CONSTRAINT whatsmeow_chat_settings_pkey PRIMARY KEY (our_jid, chat_jid);


--
-- Name: whatsmeow_contacts whatsmeow_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_contacts
    ADD CONSTRAINT whatsmeow_contacts_pkey PRIMARY KEY (our_jid, their_jid);


--
-- Name: whatsmeow_device whatsmeow_device_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_device
    ADD CONSTRAINT whatsmeow_device_pkey PRIMARY KEY (jid);


--
-- Name: whatsmeow_event_buffer whatsmeow_event_buffer_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_event_buffer
    ADD CONSTRAINT whatsmeow_event_buffer_pkey PRIMARY KEY (our_jid, ciphertext_hash);


--
-- Name: whatsmeow_identity_keys whatsmeow_identity_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_identity_keys
    ADD CONSTRAINT whatsmeow_identity_keys_pkey PRIMARY KEY (our_jid, their_id);


--
-- Name: whatsmeow_lid_map whatsmeow_lid_map_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_lid_map
    ADD CONSTRAINT whatsmeow_lid_map_pkey PRIMARY KEY (lid);


--
-- Name: whatsmeow_lid_map whatsmeow_lid_map_pn_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_lid_map
    ADD CONSTRAINT whatsmeow_lid_map_pn_key UNIQUE (pn);


--
-- Name: whatsmeow_message_secrets whatsmeow_message_secrets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_message_secrets
    ADD CONSTRAINT whatsmeow_message_secrets_pkey PRIMARY KEY (our_jid, chat_jid, sender_jid, message_id);


--
-- Name: whatsmeow_nct_salt whatsmeow_nct_salt_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_nct_salt
    ADD CONSTRAINT whatsmeow_nct_salt_pkey PRIMARY KEY (our_jid);


--
-- Name: whatsmeow_pre_keys whatsmeow_pre_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_pre_keys
    ADD CONSTRAINT whatsmeow_pre_keys_pkey PRIMARY KEY (jid, key_id);


--
-- Name: whatsmeow_privacy_tokens whatsmeow_privacy_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_privacy_tokens
    ADD CONSTRAINT whatsmeow_privacy_tokens_pkey PRIMARY KEY (our_jid, their_jid);


--
-- Name: whatsmeow_retry_buffer whatsmeow_retry_buffer_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_retry_buffer
    ADD CONSTRAINT whatsmeow_retry_buffer_pkey PRIMARY KEY (our_jid, chat_jid, message_id);


--
-- Name: whatsmeow_sender_keys whatsmeow_sender_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_sender_keys
    ADD CONSTRAINT whatsmeow_sender_keys_pkey PRIMARY KEY (our_jid, chat_id, sender_id);


--
-- Name: whatsmeow_sessions whatsmeow_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_sessions
    ADD CONSTRAINT whatsmeow_sessions_pkey PRIMARY KEY (our_jid, their_id);


--
-- Name: idx_allocations_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_allocations_invoice_id ON public.payment_allocations USING btree (invoice_id);


--
-- Name: idx_allocations_payment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_allocations_payment_id ON public.payment_allocations USING btree (payment_id);


--
-- Name: idx_audit_logs_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_created_at ON public.audit_logs USING btree (created_at DESC);


--
-- Name: idx_audit_logs_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_entity ON public.audit_logs USING btree (entity, entity_id);


--
-- Name: idx_audit_logs_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_user_id ON public.audit_logs USING btree (user_id);


--
-- Name: idx_billing_cycles_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_cycles_code ON public.billing_cycles USING btree (code);


--
-- Name: idx_billing_cycles_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_cycles_dates ON public.billing_cycles USING btree (start_date, end_date);


--
-- Name: idx_billing_cycles_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_cycles_status ON public.billing_cycles USING btree (status);


--
-- Name: idx_collector_assign_collector; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_collector_assign_collector ON public.collector_customer_assignments USING btree (collector_user_id);


--
-- Name: idx_collector_assign_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_collector_assign_customer ON public.collector_customer_assignments USING btree (customer_id);


--
-- Name: idx_customer_credits_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_credits_customer ON public.customer_credits USING btree (customer_id, status);


--
-- Name: idx_customers_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_address ON public.customers USING btree (address);


--
-- Name: idx_customers_phone_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_phone_number ON public.customers USING btree (phone_number);


--
-- Name: idx_customers_route_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_route_number ON public.customers USING btree (route_number);


--
-- Name: idx_customers_route_subscriber; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_route_subscriber ON public.customers USING btree (route_number, subscriber_number);


--
-- Name: idx_customers_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_status ON public.customers USING btree (status);


--
-- Name: idx_customers_subscriber_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_subscriber_number ON public.customers USING btree (subscriber_number);


--
-- Name: idx_invoices_billing_cycle; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_billing_cycle ON public.invoices USING btree (billing_cycle);


--
-- Name: idx_invoices_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_created_at ON public.invoices USING btree (created_at DESC);


--
-- Name: idx_invoices_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_customer_id ON public.invoices USING btree (customer_id);


--
-- Name: idx_invoices_customer_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_customer_status ON public.invoices USING btree (customer_id, status);


--
-- Name: idx_invoices_cycle_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_cycle_customer ON public.invoices USING btree (billing_cycle, customer_id);


--
-- Name: idx_invoices_cycle_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_cycle_id ON public.invoices USING btree (cycle_id);


--
-- Name: idx_invoices_due_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_due_date ON public.invoices USING btree (due_date);


--
-- Name: idx_invoices_status_remaining; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_status_remaining ON public.invoices USING btree (status, remaining_amount);


--
-- Name: idx_meter_readings_approval_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meter_readings_approval_date ON public.meter_readings USING btree (approval_status, reading_date DESC);


--
-- Name: idx_meter_readings_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meter_readings_customer_id ON public.meter_readings USING btree (customer_id);


--
-- Name: idx_meter_readings_customer_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meter_readings_customer_status ON public.meter_readings USING btree (customer_id, approval_status);


--
-- Name: idx_meter_readings_cycle_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meter_readings_cycle_id ON public.meter_readings USING btree (cycle_id);


--
-- Name: idx_meter_readings_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meter_readings_date ON public.meter_readings USING btree (reading_date DESC);


--
-- Name: idx_meter_readings_mutation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meter_readings_mutation_id ON public.meter_readings USING btree (client_mutation_id);


--
-- Name: idx_payments_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_customer_id ON public.payments USING btree (customer_id);


--
-- Name: idx_payments_customer_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_customer_status ON public.payments USING btree (customer_id, approval_status);


--
-- Name: idx_payments_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_date ON public.payments USING btree (payment_date DESC);


--
-- Name: idx_payments_mutation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_mutation_id ON public.payments USING btree (client_mutation_id);


--
-- Name: idx_payments_receipt_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_receipt_number ON public.payments USING btree (receipt_number);


--
-- Name: idx_payments_shift_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_shift_id ON public.payments USING btree (shift_id);


--
-- Name: idx_shifts_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shifts_status ON public.shifts USING btree (status);


--
-- Name: idx_shifts_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shifts_user_id ON public.shifts USING btree (user_id);


--
-- Name: idx_users_role_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_role_active ON public.users USING btree (role, is_active);


--
-- Name: idx_users_username; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_username ON public.users USING btree (username);


--
-- Name: idx_wa_queue_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_queue_created ON public.whatsapp_queue_messages USING btree (created_at DESC);


--
-- Name: idx_wa_queue_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_queue_source ON public.whatsapp_queue_messages USING btree (source_entity, source_id);


--
-- Name: idx_wa_queue_status_sched; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_queue_status_sched ON public.whatsapp_queue_messages USING btree (status, scheduled_at);


--
-- Name: idx_wa_sessions_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_sessions_active ON public.whatsapp_sessions USING btree (is_active);


--
-- Name: idx_wa_sessions_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_sessions_status ON public.whatsapp_sessions USING btree (status);


--
-- Name: idx_whatsmeow_privacy_tokens_our_jid_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_whatsmeow_privacy_tokens_our_jid_timestamp ON public.whatsmeow_privacy_tokens USING btree (our_jid, "timestamp");


--
-- Name: uq_customers_subscriber_number_clean; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_customers_subscriber_number_clean ON public.customers USING btree (REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')) WHERE (is_deleted = false);


--
-- Name: whatsmeow_retry_buffer_timestamp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX whatsmeow_retry_buffer_timestamp_idx ON public.whatsmeow_retry_buffer USING btree (our_jid, "timestamp");


--
-- Name: invoices trg_invoices_set_invoice_number; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_invoices_set_invoice_number BEFORE INSERT OR UPDATE OF customer_id, billing_cycle, invoice_number ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.fn_trg_invoices_set_invoice_number();


--
-- Name: meter_readings trg_meter_readings_monotonic; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_meter_readings_monotonic BEFORE INSERT OR UPDATE OF reading_value, is_meter_reset, customer_id ON public.meter_readings FOR EACH ROW EXECUTE FUNCTION public.fn_trg_meter_readings_monotonic();


--
-- Name: audit_logs audit_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: collector_customer_assignments collector_customer_assignments_assigned_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collector_customer_assignments
    ADD CONSTRAINT collector_customer_assignments_assigned_by_user_id_fkey FOREIGN KEY (assigned_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: collector_customer_assignments collector_customer_assignments_collector_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collector_customer_assignments
    ADD CONSTRAINT collector_customer_assignments_collector_user_id_fkey FOREIGN KEY (collector_user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: collector_customer_assignments collector_customer_assignments_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collector_customer_assignments
    ADD CONSTRAINT collector_customer_assignments_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;


--
-- Name: customer_credits customer_credits_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;


--
-- Name: customer_credits customer_credits_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.payments(id) ON DELETE CASCADE;


--
-- Name: customers customers_subscription_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_subscription_plan_id_fkey FOREIGN KEY (subscription_plan_id) REFERENCES public.subscription_plans(id) ON DELETE RESTRICT;


--
-- Name: invoices invoices_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE RESTRICT;


--
-- Name: invoices invoices_cycle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_cycle_id_fkey FOREIGN KEY (cycle_id) REFERENCES public.billing_cycles(id) ON DELETE RESTRICT;


--
-- Name: invoices invoices_reading_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_reading_id_fkey FOREIGN KEY (reading_id) REFERENCES public.meter_readings(id) ON DELETE SET NULL;


--
-- Name: meter_readings meter_readings_collector_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_collector_user_id_fkey FOREIGN KEY (collector_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: meter_readings meter_readings_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE RESTRICT;


--
-- Name: meter_readings meter_readings_cycle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_cycle_id_fkey FOREIGN KEY (cycle_id) REFERENCES public.billing_cycles(id) ON DELETE RESTRICT;


--
-- Name: payment_allocations payment_allocations_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_allocations
    ADD CONSTRAINT payment_allocations_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id) ON DELETE CASCADE;


--
-- Name: payment_allocations payment_allocations_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_allocations
    ADD CONSTRAINT payment_allocations_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.payments(id) ON DELETE CASCADE;


--
-- Name: payments payments_accountant_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_accountant_user_id_fkey FOREIGN KEY (accountant_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: payments payments_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE RESTRICT;


--
-- Name: payments payments_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id) ON DELETE SET NULL;


--
-- Name: payments payments_shift_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_shift_id_fkey FOREIGN KEY (shift_id) REFERENCES public.shifts(id) ON DELETE SET NULL;


--
-- Name: shifts shifts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shifts
    ADD CONSTRAINT shifts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: whatsmeow_app_state_mutation_macs whatsmeow_app_state_mutation_macs_jid_name_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_app_state_mutation_macs
    ADD CONSTRAINT whatsmeow_app_state_mutation_macs_jid_name_fkey FOREIGN KEY (jid, name) REFERENCES public.whatsmeow_app_state_version(jid, name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_app_state_sync_keys whatsmeow_app_state_sync_keys_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_app_state_sync_keys
    ADD CONSTRAINT whatsmeow_app_state_sync_keys_jid_fkey FOREIGN KEY (jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_app_state_version whatsmeow_app_state_version_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_app_state_version
    ADD CONSTRAINT whatsmeow_app_state_version_jid_fkey FOREIGN KEY (jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_chat_settings whatsmeow_chat_settings_our_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_chat_settings
    ADD CONSTRAINT whatsmeow_chat_settings_our_jid_fkey FOREIGN KEY (our_jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_contacts whatsmeow_contacts_our_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_contacts
    ADD CONSTRAINT whatsmeow_contacts_our_jid_fkey FOREIGN KEY (our_jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_event_buffer whatsmeow_event_buffer_our_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_event_buffer
    ADD CONSTRAINT whatsmeow_event_buffer_our_jid_fkey FOREIGN KEY (our_jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_identity_keys whatsmeow_identity_keys_our_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_identity_keys
    ADD CONSTRAINT whatsmeow_identity_keys_our_jid_fkey FOREIGN KEY (our_jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_message_secrets whatsmeow_message_secrets_our_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_message_secrets
    ADD CONSTRAINT whatsmeow_message_secrets_our_jid_fkey FOREIGN KEY (our_jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_nct_salt whatsmeow_nct_salt_our_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_nct_salt
    ADD CONSTRAINT whatsmeow_nct_salt_our_jid_fkey FOREIGN KEY (our_jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_pre_keys whatsmeow_pre_keys_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_pre_keys
    ADD CONSTRAINT whatsmeow_pre_keys_jid_fkey FOREIGN KEY (jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_retry_buffer whatsmeow_retry_buffer_our_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_retry_buffer
    ADD CONSTRAINT whatsmeow_retry_buffer_our_jid_fkey FOREIGN KEY (our_jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_sender_keys whatsmeow_sender_keys_our_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_sender_keys
    ADD CONSTRAINT whatsmeow_sender_keys_our_jid_fkey FOREIGN KEY (our_jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: whatsmeow_sessions whatsmeow_sessions_our_jid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsmeow_sessions
    ADD CONSTRAINT whatsmeow_sessions_our_jid_fkey FOREIGN KEY (our_jid) REFERENCES public.whatsmeow_device(jid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict GGeRs1Bc6Mve6Z1VkOflu8VGhFodlSSM0wgGf6UA1HWIrKlVLGbk2KKVCvr2lL4

