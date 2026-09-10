import os
import re
import subprocess
import sys

sys.stdout.reconfigure(encoding='utf-8')

def run_comprehensive_audit():
    print("=================================================================")
    print("     FORENSIC INTEGRITY AUDIT - MILESTONE M1 (worker_m1)")
    print("=================================================================")
    
    results = {}

    # -------------------------------------------------------------
    # Check 1: DBLifecycleManager in main.go
    # -------------------------------------------------------------
    print("\n--- [CHECK 1] DBLifecycleManager in server/cmd/server/main.go ---")
    with open('server/cmd/server/main.go', 'r', encoding='utf-8') as f:
        main_content = f.read()

    has_new_mgr = "database.NewDBLifecycleManager()" in main_content
    has_ensure = "dbManager.EnsureDatabaseReady()" in main_content
    has_defer_stop = "dbManager.Stop()" in main_content
    has_signals = "signal.Notify(quit, os.Interrupt, syscall.SIGTERM)" in main_content
    has_mock = any(w in main_content.lower() for w in ["mockdb", "fakedb", "dummydb"])

    print(f"  * NewDBLifecycleManager called: {has_new_mgr}")
    print(f"  * EnsureDatabaseReady called: {has_ensure}")
    print(f"  * Graceful stop hook & defer: {has_defer_stop}")
    print(f"  * Signal notification (SIGINT/SIGTERM): {has_signals}")
    print(f"  * No mock/fake keywords: {not has_mock}")

    c1_pass = has_new_mgr and has_ensure and has_defer_stop and has_signals and (not has_mock)
    results['CHECK_1_DB_LIFECYCLE_MAIN'] = 'PASS' if c1_pass else 'FAIL'

    # -------------------------------------------------------------
    # Check 2: Anti-Duplication & Normalization in customer_service.go
    # -------------------------------------------------------------
    print("\n--- [CHECK 2] Anti-Duplication in server/internal/services/customer_service.go ---")
    with open('server/internal/services/customer_service.go', 'r', encoding='utf-8') as f:
        cust_content = f.read()

    has_norm_func = "func NormalizeSubscriberNumber(sub string) string" in cust_content
    has_regex_def = "leadingZeroRegex = regexp.MustCompile(`^0+`)" in cust_content
    regexp_replace_occurrences = cust_content.count("REGEXP_REPLACE(TRIM(LOWER(subscriber_number)), '^0+', '') = ?")
    
    # Check specific methods
    in_create = "cleanSub := NormalizeSubscriberNumber(trimmedSubNo)" in cust_content
    in_update = "cleanSub := NormalizeSubscriberNumber(trimmedSubNo)" in cust_content and "currentClean := NormalizeSubscriberNumber(customer.SubscriberNumber)" in cust_content
    in_grid = "cleanSub := NormalizeSubscriberNumber(newSubNum)" in cust_content and "currentClean := NormalizeSubscriberNumber(customer.SubscriberNumber)" in cust_content
    in_next = "NormalizeSubscriberNumber(candidateStr)" in cust_content

    # Check for hardcoded bypasses
    has_hardcoded_ids = any(bid in cust_content for bid in ["1212121", "495", "fake", "bypass", "mock"])

    print(f"  * NormalizeSubscriberNumber function defined: {has_norm_func}")
    print(f"  * leadingZeroRegex defined with ^0+: {has_regex_def}")
    print(f"  * REGEXP_REPLACE SQL queries count: {regexp_replace_occurrences} (expected >= 3)")
    print(f"  * CreateCustomer anti-duplicate check: {in_create}")
    print(f"  * UpdateCustomer anti-duplicate check: {in_update}")
    print(f"  * UpdateGridCell anti-duplicate check: {in_grid}")
    print(f"  * GetNextSubscriberNumber collision check: {in_next}")
    print(f"  * Hardcoded bypasses absent: {not has_hardcoded_ids}")

    c2_pass = (has_norm_func and has_regex_def and regexp_replace_occurrences >= 3 and 
               in_create and in_update and in_grid and in_next and not has_hardcoded_ids)
    results['CHECK_2_ANTI_DUPLICATION_CODE'] = 'PASS' if c2_pass else 'FAIL'

    # -------------------------------------------------------------
    # Check 3: Schema Constraints in database/02_tables_and_constraints.sql
    # -------------------------------------------------------------
    print("\n--- [CHECK 3] Unique Index in database/02_tables_and_constraints.sql ---")
    with open('database/02_tables_and_constraints.sql', 'r', encoding='utf-8') as f:
        schema2_content = f.read()

    expected_sql_idx = "CREATE UNIQUE INDEX IF NOT EXISTS uq_customers_subscriber_number_clean ON public.customers USING btree (REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')) WHERE (is_deleted = false);"
    has_clean_idx = expected_sql_idx in schema2_content
    print(f"  * Clean unique index present: {has_clean_idx}")

    results['CHECK_3_SCHEMA_CONSTRAINTS_SQL'] = 'PASS' if has_clean_idx else 'FAIL'

    # -------------------------------------------------------------
    # Check 4: Clean Database Dump in dist_portable/schema/init_schema.sql
    # -------------------------------------------------------------
    print("\n--- [CHECK 4] Dump Integrity in dist_portable/schema/init_schema.sql ---")
    with open('dist_portable/schema/init_schema.sql', 'r', encoding='utf-8', errors='ignore') as f:
        dump_text = f.read()

    # Verify customers
    m_cust = re.search(r'COPY public\.customers \([^)]+\) FROM stdin;\n(.*?)\n\\\.', dump_text, re.DOTALL)
    cust_lines = [l for l in m_cust.group(1).split('\n') if l.strip()]
    cust_count = len(cust_lines)
    has_test_cust = any('1212121' in l or 'اختبار نظام' in l for l in cust_lines)
    cust_ids = [int(l.split('\t')[0]) for l in cust_lines]

    print(f"  * Customer count: {cust_count} (expected 494)")
    print(f"  * Customer IDs range: {min(cust_ids)} to {max(cust_ids)}")
    print(f"  * Test customer 495 removed: {not has_test_cust}")

    # Verify invoices
    m_inv = re.search(r'COPY public\.invoices \([^)]+\) FROM stdin;\n(.*?)\n\\\.', dump_text, re.DOTALL)
    inv_lines = [l for l in m_inv.group(1).split('\n') if l.strip()]
    inv_count = len(inv_lines)
    inv_cycles = set(l.split('\t')[5] for l in inv_lines)
    print(f"  * Invoice count: {inv_count} (expected 494)")
    print(f"  * Invoice billing cycles: {inv_cycles} (expected {{'أغسطس 2'}})")

    # Verify meter readings
    m_rd = re.search(r'COPY public\.meter_readings \([^)]+\) FROM stdin;\n(.*?)\n\\\.', dump_text, re.DOTALL)
    rd_lines = [l for l in m_rd.group(1).split('\n') if l.strip()]
    rd_count = len(rd_lines)
    has_495_rd = any(l.split('\t')[1] == '495' for l in rd_lines)
    print(f"  * Reading count: {rd_count} (expected 494)")
    print(f"  * Reading for 495 removed: {not has_495_rd}")

    # Verify audit logs
    m_al = re.search(r'COPY public\.audit_logs \([^)]+\) FROM stdin;\n(.*?)\n\\\.', dump_text, re.DOTALL)
    al_lines = [l for l in m_al.group(1).split('\n') if l.strip()]
    al_count = len(al_lines)
    al_ids = [int(l.split('\t')[0]) for l in al_lines]
    has_bad_al = any(i in al_ids for i in [90, 91, 94])
    print(f"  * Audit logs count: {al_count} (expected 72)")
    print(f"  * Test audit logs (90, 91, 94) removed: {not has_bad_al}")

    # Verify sequences
    has_cust_seq = "SELECT pg_catalog.setval('public.customers_id_seq', 494, true);" in dump_text
    has_inv_seq = "SELECT pg_catalog.setval('public.invoices_id_seq', 494, true);" in dump_text
    has_rd_seq = "SELECT pg_catalog.setval('public.meter_readings_id_seq', 494, true);" in dump_text
    has_al_seq = "SELECT pg_catalog.setval('public.audit_logs_id_seq', 93, true);" in dump_text
    print(f"  * customers_id_seq set to 494: {has_cust_seq}")
    print(f"  * invoices_id_seq set to 494: {has_inv_seq}")
    print(f"  * meter_readings_id_seq set to 494: {has_rd_seq}")
    print(f"  * audit_logs_id_seq set to 93: {has_al_seq}")

    # Verify index in dump
    expected_dump_idx = "CREATE UNIQUE INDEX uq_customers_subscriber_number_clean ON public.customers USING btree (REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')) WHERE (is_deleted = false);"
    has_dump_idx = expected_dump_idx in dump_text
    print(f"  * Clean unique index in dump: {has_dump_idx}")

    c4_pass = (cust_count == 494 and not has_test_cust and 
               inv_count == 494 and inv_cycles == {'أغسطس 2'} and 
               rd_count == 494 and not has_495_rd and 
               al_count == 72 and not has_bad_al and 
               has_cust_seq and has_inv_seq and has_rd_seq and has_al_seq and 
               has_dump_idx)
    results['CHECK_4_INIT_SCHEMA_SQL_INTEGRITY'] = 'PASS' if c4_pass else 'FAIL'

    # -------------------------------------------------------------
    # Check 5: Independent Go Tests and Compilation
    # -------------------------------------------------------------
    print("\n--- [CHECK 5] Independent Go Build & Test Execution ---")
    test_run = subprocess.run(['go', 'test', './...'], cwd='server', capture_output=True, text=True)
    build_run = subprocess.run(['go', 'build', '-o', 'test_audit_bin.exe', './cmd/server'], cwd='server', capture_output=True, text=True)
    
    # clean up test bin
    if os.path.exists('server/test_audit_bin.exe'):
        os.remove('server/test_audit_bin.exe')

    print(f"  * Go test returncode: {test_run.returncode}")
    print(f"  * Go test stdout: {test_run.stdout.strip()}")
    print(f"  * Go build returncode: {build_run.returncode}")

    c5_pass = test_run.returncode == 0 and build_run.returncode == 0
    results['CHECK_5_BUILD_AND_TESTS'] = 'PASS' if c5_pass else 'FAIL'

    # -------------------------------------------------------------
    # FINAL AUDIT SUMMARY
    # -------------------------------------------------------------
    print("\n=================================================================")
    print("                    FINAL AUDIT RESULTS")
    print("=================================================================")
    all_clean = True
    for check, status in results.items():
        print(f"  {check:35}: {status}")
        if status != 'PASS':
            all_clean = False

    verdict = "CLEAN" if all_clean else "INTEGRITY VIOLATION"
    print(f"\nOVERALL FORENSIC VERDICT: >>> {verdict} <<<")
    print("=================================================================")
    return verdict

if __name__ == '__main__':
    verdict = run_comprehensive_audit()
    sys.exit(0 if verdict == 'CLEAN' else 1)
