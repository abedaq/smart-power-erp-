import re

def clean_schema():
    with open('dist_portable/schema/init_schema.sql', 'r', encoding='utf-8') as f:
        content = f.read()

    # 1. Update index
    old_idx = "CREATE UNIQUE INDEX uq_customers_subscriber_number_clean ON public.customers USING btree (TRIM(BOTH FROM lower((subscriber_number)::text))) WHERE (is_deleted = false);"
    new_idx = "CREATE UNIQUE INDEX uq_customers_subscriber_number_clean ON public.customers USING btree (REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')) WHERE (is_deleted = false);"
    if old_idx not in content:
        raise ValueError("Old index definition not found in init_schema.sql")
    content = content.replace(old_idx, new_idx)

    # 2. Clean customers: remove customer 495
    m_cust = re.search(r'(COPY public\.customers \([^)]+\) FROM stdin;\n)(.*?)(\n\\\.)', content, re.DOTALL)
    if not m_cust:
        raise ValueError("customers COPY block not found")
    cust_lines = m_cust.group(2).split('\n')
    print(f"Original customers count: {len(cust_lines)}")
    clean_cust_lines = [l for l in cust_lines if not l.startswith('495\t')]
    print(f"Cleaned customers count: {len(clean_cust_lines)}")
    if len(clean_cust_lines) != 494:
        raise ValueError(f"Expected 494 customers, got {len(clean_cust_lines)}")
    content = content[:m_cust.start(2)] + '\n'.join(clean_cust_lines) + content[m_cust.end(2):]

    # 3. Clean invoices: keep only 'أغسطس 2'
    m_inv = re.search(r'(COPY public\.invoices \([^)]+\) FROM stdin;\n)(.*?)(\n\\\.)', content, re.DOTALL)
    if not m_inv:
        raise ValueError("invoices COPY block not found")
    inv_lines = m_inv.group(2).split('\n')
    print(f"Original invoices count: {len(inv_lines)}")
    clean_inv_lines = [l for l in inv_lines if 'أغسطس 2' in l]
    print(f"Cleaned invoices count: {len(clean_inv_lines)}")
    if len(clean_inv_lines) != 494:
        raise ValueError(f"Expected 494 invoices, got {len(clean_inv_lines)}")
    content = content[:m_inv.start(2)] + '\n'.join(clean_inv_lines) + content[m_inv.end(2):]

    # 4. Clean meter_readings: remove reading for customer 495
    m_rd = re.search(r'(COPY public\.meter_readings \([^)]+\) FROM stdin;\n)(.*?)(\n\\\.)', content, re.DOTALL)
    if not m_rd:
        raise ValueError("meter_readings COPY block not found")
    rd_lines = m_rd.group(2).split('\n')
    print(f"Original readings count: {len(rd_lines)}")
    clean_rd_lines = [l for l in rd_lines if not l.startswith('495\t')]
    print(f"Cleaned readings count: {len(clean_rd_lines)}")
    if len(clean_rd_lines) != 494:
        raise ValueError(f"Expected 494 readings, got {len(clean_rd_lines)}")
    content = content[:m_rd.start(2)] + '\n'.join(clean_rd_lines) + content[m_rd.end(2):]

    # 5. Clean audit_logs: remove logs associated with 495
    m_log = re.search(r'(COPY public\.audit_logs \([^)]+\) FROM stdin;\n)(.*?)(\n\\\.)', content, re.DOTALL)
    if not m_log:
        raise ValueError("audit_logs COPY block not found")
    log_lines = m_log.group(2).split('\n')
    print(f"Original audit logs count: {len(log_lines)}")
    clean_log_lines = [l for l in log_lines if not (l.startswith('90\t') or l.startswith('91\t') or l.startswith('94\t') or '1212121' in l or 'اختبار نظام' in l)]
    print(f"Cleaned audit logs count: {len(clean_log_lines)}")
    max_log_id = max(int(l.split('\t')[0]) for l in clean_log_lines)
    print(f"Max remaining log id: {max_log_id}")
    content = content[:m_log.start(2)] + '\n'.join(clean_log_lines) + content[m_log.end(2):]

    # 6. Update setval for sequences
    content = re.sub(r"SELECT pg_catalog\.setval\('public\.customers_id_seq', \d+, true\);", "SELECT pg_catalog.setval('public.customers_id_seq', 494, true);", content)
    content = re.sub(r"SELECT pg_catalog\.setval\('public\.invoices_id_seq', \d+, true\);", "SELECT pg_catalog.setval('public.invoices_id_seq', 494, true);", content)
    content = re.sub(r"SELECT pg_catalog\.setval\('public\.meter_readings_id_seq', \d+, true\);", "SELECT pg_catalog.setval('public.meter_readings_id_seq', 494, true);", content)
    content = re.sub(r"SELECT pg_catalog\.setval\('public\.audit_logs_id_seq', \d+, true\);", f"SELECT pg_catalog.setval('public.audit_logs_id_seq', {max_log_id}, true);", content)

    # Write cleaned content back
    with open('dist_portable/schema/init_schema.sql', 'w', encoding='utf-8') as f:
        f.write(content)

    print("SUCCESS: init_schema.sql updated and verified!")

if __name__ == '__main__':
    clean_schema()
