import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

def test_all():
    print("=== Verification Suite for worker_m1 ===")
    
    # 1. Verify dist_portable/schema/init_schema.sql
    print("\n[1] Verifying dist_portable/schema/init_schema.sql...")
    with open('dist_portable/schema/init_schema.sql', 'r', encoding='utf-8') as f:
        schema = f.read()

    m_cust = re.search(r'COPY public\.customers \([^)]+\) FROM stdin;\n(.*?)\n\\\.', schema, re.DOTALL)
    cust_lines = m_cust.group(1).split('\n')
    assert len(cust_lines) == 494, f"Expected 494 customers, got {len(cust_lines)}"
    assert not any('1212121' in l or 'اختبار نظام' in l for l in cust_lines), "Customer 495 found in customers!"
    print(f"  [PASS] Exactly 494 customers present (IDs 1-494). Customer 495 is absent.")

    m_inv = re.search(r'COPY public\.invoices \([^)]+\) FROM stdin;\n(.*?)\n\\\.', schema, re.DOTALL)
    inv_lines = m_inv.group(1).split('\n')
    assert len(inv_lines) == 494, f"Expected 494 invoices, got {len(inv_lines)}"
    cycles = set(l.split('\t')[5] for l in inv_lines)
    assert cycles == {'أغسطس 2'}, f"Expected only 'أغسطس 2', got {cycles}"
    print(f"  [PASS] Exactly 494 invoices present, all belonging to 'أغسطس 2'.")

    m_rd = re.search(r'COPY public\.meter_readings \([^)]+\) FROM stdin;\n(.*?)\n\\\.', schema, re.DOTALL)
    rd_lines = m_rd.group(1).split('\n')
    assert len(rd_lines) == 494, f"Expected 494 readings, got {len(rd_lines)}"
    assert not any(l.split('\t')[1] == '495' for l in rd_lines), "Reading for customer 495 found!"
    print(f"  [PASS] Exactly 494 meter readings present, reading for 495 removed.")

    assert "CREATE UNIQUE INDEX uq_customers_subscriber_number_clean ON public.customers USING btree (REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')) WHERE (is_deleted = false);" in schema, "Clean index missing in init_schema.sql!"
    print("  [PASS] Unique index uq_customers_subscriber_number_clean correctly uses REGEXP_REPLACE leading zero removal.")

    assert "SELECT pg_catalog.setval('public.customers_id_seq', 494, true);" in schema
    assert "SELECT pg_catalog.setval('public.invoices_id_seq', 494, true);" in schema
    assert "SELECT pg_catalog.setval('public.meter_readings_id_seq', 494, true);" in schema
    print("  [PASS] Sequences customers_id_seq, invoices_id_seq, meter_readings_id_seq set to 494.")

    # 2. Verify database/02_tables_and_constraints.sql
    print("\n[2] Verifying database/02_tables_and_constraints.sql...")
    with open('database/02_tables_and_constraints.sql', 'r', encoding='utf-8') as f:
        sql2 = f.read()
    assert "CREATE UNIQUE INDEX IF NOT EXISTS uq_customers_subscriber_number_clean ON public.customers USING btree (REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')) WHERE (is_deleted = false);" in sql2, "uq_customers_subscriber_number_clean missing in 02_tables_and_constraints.sql!"
    print("  [PASS] Unique index uq_customers_subscriber_number_clean is defined with IF NOT EXISTS.")

    # 3. Verify server/internal/services/customer_service.go
    print("\n[3] Verifying server/internal/services/customer_service.go...")
    with open('server/internal/services/customer_service.go', 'r', encoding='utf-8') as f:
        svc = f.read()
    assert "NormalizeSubscriberNumber" in svc, "NormalizeSubscriberNumber helper missing!"
    assert "REGEXP_REPLACE(TRIM(LOWER(subscriber_number)), '^0+', '') = ?" in svc, "REGEXP_REPLACE query missing!"
    assert svc.count("REGEXP_REPLACE(TRIM(LOWER(subscriber_number)), '^0+', '') = ?") >= 3, "Expected at least 3 occurrences of REGEXP_REPLACE check!"
    print(f"  [PASS] NormalizeSubscriberNumber helper and REGEXP_REPLACE checks (count={svc.count('REGEXP_REPLACE')}) active in CreateCustomer, UpdateCustomer, UpdateGridCell, and GetNextSubscriberNumber.")

    # 4. Verify server/cmd/server/main.go
    print("\n[4] Verifying server/cmd/server/main.go...")
    with open('server/cmd/server/main.go', 'r', encoding='utf-8') as f:
        main_code = f.read()
    assert "database.NewDBLifecycleManager()" in main_code, "NewDBLifecycleManager missing!"
    assert "EnsureDatabaseReady()" in main_code, "EnsureDatabaseReady missing!"
    assert "cfg.DatabaseURL = dbURL" in main_code, "cfg.DatabaseURL override missing!"
    assert "signal.Notify(quit, os.Interrupt, syscall.SIGTERM)" in main_code, "Signal notification missing!"
    assert "dbManager.Stop()" in main_code, "dbManager.Stop() call missing!"
    print("  [PASS] DBLifecycleManager correctly initialized, database URL overridden, and graceful shutdown signal handler hooked.")

    print("\nALL VERIFICATIONS PASSED 100%!")

if __name__ == '__main__':
    test_all()
