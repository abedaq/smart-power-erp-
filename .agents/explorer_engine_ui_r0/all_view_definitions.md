# PostgreSQL View Definitions

## user_profiles
```sql
 SELECT id,
    username,
    full_name,
    role,
    is_active,
    supabase_uid,
    created_at
   FROM users;
```

## view_collector_daily_kpis
```sql
 WITH today_readings AS (
         SELECT COALESCE(meter_readings.collector_name, 'غير معروف'::character varying) AS collector_name,
            count(*) AS readings
           FROM meter_readings
          WHERE meter_readings.reading_date >= CURRENT_DATE
          GROUP BY (COALESCE(meter_readings.collector_name, 'غير معروف'::character varying))
        ), today_payments AS (
         SELECT COALESCE(payments.accountant_name, 'غير معروف'::character varying) AS collector_name,
            sum(payments.amount_paid) AS cash,
            count(DISTINCT payments.customer_id) AS customers_paid
           FROM payments
          WHERE payments.payment_date >= CURRENT_DATE
          GROUP BY (COALESCE(payments.accountant_name, 'غير معروف'::character varying))
        )
 SELECT COALESCE(r.collector_name, p.collector_name) AS collector_name,
    COALESCE(r.readings, 0::bigint) AS readings,
    COALESCE(p.cash, 0::numeric) AS cash,
    COALESCE(p.customers_paid, 0::bigint) AS customers_paid
   FROM today_readings r
     FULL JOIN today_payments p ON r.collector_name::text = p.collector_name::text;
```

## view_customers_mobile_sync
```sql
 SELECT c.id,
    c.subscriber_number,
    c.full_name,
    c.phone_number,
    c.address,
    c.meter_number,
    c.route_number,
    c.subscription_plan_id,
    c.initial_reading,
    c.status,
    c.is_deleted,
    p.plan_name,
    p.kwh_price,
    COALESCE(( SELECT mr.reading_value
           FROM meter_readings mr
          WHERE mr.customer_id = c.id AND mr.approval_status::text <> 'REJECTED'::text
          ORDER BY mr.reading_date DESC, mr.id DESC
         LIMIT 1), c.initial_reading) AS last_reading,
    COALESCE(( SELECT sum(i.remaining_amount) AS sum
           FROM invoices i
          WHERE i.customer_id = c.id AND i.approval_status::text <> 'REJECTED'::text AND (i.status::text <> ALL (ARRAY['Void'::character varying, 'Pending_Approval'::character varying, 'Paid'::character varying]::text[]))), 0::numeric) AS total_due
   FROM customers c
     LEFT JOIN subscription_plans p ON c.subscription_plan_id = p.id
  WHERE c.is_deleted = false;
```

## view_dashboard_summary
```sql
 SELECT ( SELECT count(*) AS count
           FROM customers
          WHERE customers.is_deleted = false) AS total_customers,
    ( SELECT count(*) AS count
           FROM customers
          WHERE customers.status::text = 'Active'::text AND customers.is_deleted = false) AS active_customers,
    ( SELECT COALESCE(sum(invoices.remaining_amount), 0::numeric) AS "coalesce"
           FROM invoices
          WHERE invoices.status::text = ANY (ARRAY['Unpaid'::character varying, 'Partially_Paid'::character varying]::text[])) AS total_outstanding_debt,
    ( SELECT COALESCE(sum(payments.amount_paid), 0::numeric) AS "coalesce"
           FROM payments
          WHERE payments.approval_status::text = 'APPROVED'::text) AS total_cash_collected,
    ( SELECT count(*) AS count
           FROM meter_readings
          WHERE meter_readings.approval_status::text = 'PENDING'::text) AS pending_readings_count,
    ( SELECT count(*) AS count
           FROM payments
          WHERE payments.approval_status::text = 'PENDING'::text) AS pending_payments_count;
```

## view_monthly_performance
```sql
 SELECT billing_cycle,
    count(id) AS total_invoices,
    COALESCE(sum(total_due), 0::numeric) AS total_billed,
    COALESCE(sum(paid_amount), 0::numeric) AS total_collected,
    COALESCE(sum(remaining_amount), 0::numeric) AS total_remaining,
        CASE
            WHEN sum(total_due) > 0::numeric THEN round(sum(paid_amount) / sum(total_due) * 100::numeric, 1)
            ELSE 0.0
        END AS collection_rate
   FROM invoices
  WHERE status::text <> 'Void'::text
  GROUP BY billing_cycle
  ORDER BY (min(created_at)) DESC;
```

## view_overdue_report
```sql
 SELECT c.id AS customer_id,
    c.full_name,
    c.subscriber_number,
    c.route_number,
    c.address AS region,
    sum(i.remaining_amount) AS total_arrears,
    min(COALESCE(i.due_date, i.created_at::date)) AS oldest_due_date,
    CURRENT_DATE - min(COALESCE(i.due_date, i.created_at::date)) AS days_overdue
   FROM customers c
     JOIN invoices i ON c.id = i.customer_id
  WHERE i.remaining_amount > 0::numeric
  GROUP BY c.id, c.full_name, c.subscriber_number, c.route_number, c.address;
```

## view_recent_transactions
```sql
 SELECT 'Meter_Reading'::text AS type,
    m.id,
    c.id AS customer_id,
    c.full_name AS customer_name,
    c.subscriber_number,
    c.route_number,
    m.collector_name AS actor_name,
    m.reading_value::text || ' kWh'::text AS value_display,
    m.reading_value AS raw_value,
    m.reading_date AS operation_date,
    m.approval_status
   FROM meter_readings m
     JOIN customers c ON m.customer_id = c.id
UNION ALL
 SELECT 'Payment'::text AS type,
    p.id,
    COALESCE(p.customer_id, i.customer_id) AS customer_id,
    c.full_name AS customer_name,
    c.subscriber_number,
    c.route_number,
    p.accountant_name AS actor_name,
    p.amount_paid::text || ' ر.ي'::text AS value_display,
    p.amount_paid AS raw_value,
    p.payment_date AS operation_date,
    p.approval_status
   FROM payments p
     LEFT JOIN invoices i ON p.invoice_id = i.id
     LEFT JOIN customers c ON COALESCE(p.customer_id, i.customer_id) = c.id;
```

## view_routes_progress
```sql
 WITH current_cycle_invoices AS (
         SELECT DISTINCT invoices.customer_id
           FROM invoices
          WHERE date_trunc('month'::text, invoices.created_at) = date_trunc('month'::text, CURRENT_DATE::timestamp with time zone)
        ), route_stats AS (
         SELECT COALESCE(c.route_number, 'بدون خط'::character varying) AS route,
            count(c.id) AS total_customers,
            count(cci.customer_id) AS read_customers
           FROM customers c
             LEFT JOIN current_cycle_invoices cci ON c.id = cci.customer_id
          GROUP BY (COALESCE(c.route_number, 'بدون خط'::character varying))
        )
 SELECT route,
    total_customers,
    read_customers,
        CASE
            WHEN total_customers > 0 THEN round(read_customers::numeric / total_customers::numeric * 100::numeric)
            ELSE 0::numeric
        END AS percentage
   FROM route_stats;
```

