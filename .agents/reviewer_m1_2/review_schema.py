import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

def main():
    print("=== Independent Review & Forensic Analysis of Database Schema ===")
    
    with open('dist_portable/schema/init_schema.sql', 'r', encoding='utf-8') as f:
        schema = f.read()

    print(f"Total size of init_schema.sql: {len(schema)} bytes")

    # 1. Search for test artifacts
    print("\n--- Artifact & Leakage Checks ---")
    for term in ['1212121', 'اختبار نظام', 'سبتمبر', 'أكتوبر']:
        # Check where these terms appear
        matches = [m.start() for m in re.finditer(re.escape(term), schema)]
        print(f"Term '{term}': {len(matches)} matches")
        for m in matches:
            start = max(0, m - 50)
            end = min(len(schema), m + 50)
            print(f"  Context: {schema[start:end]!r}")

    # 2. Customers Table Analysis
    print("\n--- Customers Table Analysis ---")
    m_cust = re.search(r'COPY public\.customers \((.*?)\) FROM stdin;\n(.*?)\n\\\.', schema, re.DOTALL)
    if not m_cust:
        print("FAIL: COPY public.customers block not found!")
        return
    cust_cols = [c.strip() for c in m_cust.group(1).split(',')]
    cust_rows = [l.split('\t') for l in m_cust.group(2).strip().split('\n') if l]
    print(f"Customer columns count: {len(cust_cols)}")
    print(f"Customer rows count: {len(cust_rows)}")
    
    id_idx = cust_cols.index('id')
    sub_idx = cust_cols.index('subscriber_number')
    name_idx = cust_cols.index('full_name') if 'full_name' in cust_cols else cust_cols.index('name')
    status_idx = cust_cols.index('status')
    
    cust_ids = [int(r[id_idx]) for r in cust_rows]
    print(f"Customer IDs range: min={min(cust_ids)}, max={max(cust_ids)}, count={len(cust_ids)}")
    print(f"Is customer 495 in cust_ids? {495 in cust_ids}")
    
    # Check uniqueness under clean rule:
    # REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')
    clean_map = {}
    clean_collisions = []
    leading_zero_subs = []
    for r in cust_rows:
        cid = int(r[id_idx])
        sub = r[sub_idx]
        name = r[name_idx]
        trimmed_lower = sub.strip().lower()
        cleaned = re.sub(r'^0+', '', trimmed_lower)
        if re.match(r'^0+', sub.strip()):
            leading_zero_subs.append((cid, sub, cleaned))
        if cleaned in clean_map:
            clean_collisions.append((cleaned, (cid, sub, name), clean_map[cleaned]))
        else:
            clean_map[cleaned] = (cid, sub, name)

    print(f"Leading zero subscriber numbers found in initial data: {len(leading_zero_subs)}")
    for lz in leading_zero_subs:
        print(f"  ID={lz[0]}: raw={lz[1]!r} -> cleaned={lz[2]!r}")
    
    print(f"Clean index collisions: {len(clean_collisions)}")
    if clean_collisions:
        for c in clean_collisions:
            print(f"  Collision on '{c[0]}': {c[1]} vs {c[2]}")

    # Check for empty cleaned strings (e.g. if subscriber number was '0' or '00')
    if '' in clean_map:
        print(f"WARNING: An empty cleaned subscriber number exists: {clean_map['']}")
    else:
        print("Cleaned subscriber numbers: No empty string ('') found.")

    # 3. Invoices Table Analysis
    print("\n--- Invoices Table Analysis ---")
    m_inv = re.search(r'COPY public\.invoices \((.*?)\) FROM stdin;\n(.*?)\n\\\.', schema, re.DOTALL)
    if not m_inv:
        print("FAIL: COPY public.invoices block not found!")
        return
    inv_cols = [c.strip() for c in m_inv.group(1).split(',')]
    inv_rows = [l.split('\t') for l in m_inv.group(2).strip().split('\n') if l]
    print(f"Invoices columns count: {len(inv_cols)}")
    print(f"Invoices rows count: {len(inv_rows)}")
    
    print(f"Invoices columns: {inv_cols}")
    inv_id_idx = inv_cols.index('id')
    inv_cust_idx = inv_cols.index('customer_id')
    inv_cycle_idx = inv_cols.index('cycle_name') if 'cycle_name' in inv_cols else (inv_cols.index('billing_cycle') if 'billing_cycle' in inv_cols else 5)
    inv_status_idx = inv_cols.index('status')
    
    inv_ids = [int(r[inv_id_idx]) for r in inv_rows]
    inv_cust_ids = [int(r[inv_cust_idx]) for r in inv_rows]
    cycles = set(r[inv_cycle_idx] for r in inv_rows)
    statuses = set(r[inv_status_idx] for r in inv_rows)
    
    print(f"Invoice IDs range: min={min(inv_ids)}, max={max(inv_ids)}, count={len(inv_ids)}")
    print(f"Distinct billing cycles in invoices: {cycles}")
    print(f"Distinct statuses in invoices: {statuses}")
    print(f"Are all invoice customer_ids in customers (1..494)? {all(cid in set(cust_ids) for cid in inv_cust_ids)}")
    print(f"Is customer 495 referenced in invoices? {495 in inv_cust_ids}")

    # 4. Meter Readings Analysis
    print("\n--- Meter Readings Analysis ---")
    m_rd = re.search(r'COPY public\.meter_readings \((.*?)\) FROM stdin;\n(.*?)\n\\\.', schema, re.DOTALL)
    rd_cols = [c.strip() for c in m_rd.group(1).split(',')]
    rd_rows = [l.split('\t') for l in m_rd.group(2).strip().split('\n') if l]
    print(f"Meter readings rows count: {len(rd_rows)}")
    rd_id_idx = rd_cols.index('id')
    rd_cust_idx = rd_cols.index('customer_id')
    rd_ids = [int(r[rd_id_idx]) for r in rd_rows]
    rd_cust_ids = [int(r[rd_cust_idx]) for r in rd_rows]
    print(f"Meter reading IDs: min={min(rd_ids)}, max={max(rd_ids)}, count={len(rd_ids)}")
    print(f"Are all reading customer_ids in customers (1..494)? {all(cid in set(cust_ids) for cid in rd_cust_ids)}")
    print(f"Is customer 495 referenced in meter_readings? {495 in rd_cust_ids}")

    # 5. Payments and Allocations Analysis
    print("\n--- Payments & Allocations Analysis ---")
    m_pmt = re.search(r'COPY public\.payments \((.*?)\) FROM stdin;\n(.*?)\n\\\.', schema, re.DOTALL)
    pmt_cols = [c.strip() for c in m_pmt.group(1).split(',')]
    pmt_rows = [l.split('\t') for l in m_pmt.group(2).strip().split('\n') if l]
    print(f"Payments rows count: {len(pmt_rows)}")
    pmt_cust_idx = pmt_cols.index('customer_id')
    pmt_cust_ids = [int(r[pmt_cust_idx]) for r in pmt_rows]
    print(f"Are all payment customer_ids in customers (1..494)? {all(cid in set(cust_ids) for cid in pmt_cust_ids)}")
    print(f"Is customer 495 referenced in payments? {495 in pmt_cust_ids}")

    m_alloc = re.search(r'COPY public\.payment_allocations \((.*?)\) FROM stdin;\n(.*?)\n\\\.', schema, re.DOTALL)
    alloc_cols = [c.strip() for c in m_alloc.group(1).split(',')]
    alloc_rows = [l.split('\t') for l in m_alloc.group(2).strip().split('\n') if l]
    print(f"Payment allocations rows count: {len(alloc_rows)}")
    alloc_inv_idx = alloc_cols.index('invoice_id')
    alloc_inv_ids = [int(r[alloc_inv_idx]) for r in alloc_rows]
    print(f"Are all allocated invoice_ids in valid invoices (1..494)? {all(iid in set(inv_ids) for iid in alloc_inv_ids)}")

    # 6. Audit Logs Analysis
    print("\n--- Audit Logs Analysis ---")
    m_audit = re.search(r'COPY public\.audit_logs \((.*?)\) FROM stdin;\n(.*?)\n\\\.', schema, re.DOTALL)
    audit_cols = [c.strip() for c in m_audit.group(1).split(',')]
    audit_rows = [l.split('\t') for l in m_audit.group(2).strip().split('\n') if l]
    print(f"Audit logs rows count: {len(audit_rows)}")
    # Check if any audit log has entity_id = 495 or mentions 1212121 or test invoices
    audit_matches_495 = []
    for r in audit_rows:
        line_str = '\t'.join(r)
        if '495' in line_str or '1212121' in line_str or 'اختبار نظام' in line_str:
            audit_matches_495.append(line_str)
    print(f"Audit logs mentioning 495 or 1212121: {len(audit_matches_495)}")
    if audit_matches_495:
        for am in audit_matches_495:
            print("  Match:", am)

    # 7. Billing Cycles Analysis
    print("\n--- Billing Cycles Analysis ---")
    m_cycles = re.search(r'COPY public\.billing_cycles \((.*?)\) FROM stdin;\n(.*?)\n\\\.', schema, re.DOTALL)
    cycle_cols = [c.strip() for c in m_cycles.group(1).split(',')]
    cycle_rows = [l.split('\t') for l in m_cycles.group(2).strip().split('\n') if l]
    print(f"Billing cycles count: {len(cycle_rows)}")
    for r in cycle_rows:
        print("  Cycle row:", dict(zip(cycle_cols, r)))

    # 8. Sequences Analysis
    print("\n--- Sequences setval Analysis ---")
    setvals = re.findall(r'SELECT pg_catalog\.setval\([^;]+;', schema)
    for s in setvals:
        print(" ", s)

    # 9. Unique Index Definition in init_schema.sql and 02_tables_and_constraints.sql
    print("\n--- Index Definition Analysis ---")
    idx_match_init = re.search(r'CREATE UNIQUE INDEX\s+uq_customers_subscriber_number_clean\s+ON\s+public\.customers\s+USING\s+btree\s+\((.*?)\)\s+WHERE\s+\((.*?)\);', schema, re.IGNORECASE)
    if idx_match_init:
        print("init_schema.sql index expression:", idx_match_init.group(1).strip())
        print("init_schema.sql index where:", idx_match_init.group(2).strip())
    else:
        print("FAIL: uq_customers_subscriber_number_clean not found in init_schema.sql!")

    with open('database/02_tables_and_constraints.sql', 'r', encoding='utf-8') as f:
        sql2 = f.read()
    idx_match_02 = re.search(r'CREATE UNIQUE INDEX\s+(?:IF NOT EXISTS\s+)?uq_customers_subscriber_number_clean\s+ON\s+public\.customers\s+USING\s+btree\s+\((.*?)\)\s+WHERE\s+\((.*?)\);', sql2, re.IGNORECASE)
    if idx_match_02:
        print("02_tables_and_constraints.sql index expression:", idx_match_02.group(1).strip())
        print("02_tables_and_constraints.sql index where:", idx_match_02.group(2).strip())
    else:
        print("FAIL: uq_customers_subscriber_number_clean not found in 02_tables_and_constraints.sql!")

    # Check for any other unique constraints on customers(subscriber_number)
    all_indexes_customers = re.findall(r'CREATE(?:\s+UNIQUE)?\s+INDEX.*ON\s+public\.customers.*?;', schema, re.IGNORECASE)
    print(f"\nAll customer indexes in init_schema.sql ({len(all_indexes_customers)}):")
    for idx in all_indexes_customers:
        print(" ", idx.strip())

    all_indexes_customers_02 = re.findall(r'CREATE(?:\s+UNIQUE)?\s+INDEX.*ON\s+public\.customers.*?;', sql2, re.IGNORECASE)
    print(f"\nAll customer indexes in 02_tables_and_constraints.sql ({len(all_indexes_customers_02)}):")
    for idx in all_indexes_customers_02:
        print(" ", idx.strip())

if __name__ == '__main__':
    main()
