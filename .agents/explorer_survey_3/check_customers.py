import re

with open(r"d:\elctercity\dist_portable\schema\init_schema.sql", "r", encoding="utf-8", errors="ignore") as f:
    in_customers = False
    rows = []
    for line in f:
        if line.startswith("COPY public.customers "):
            in_customers = True
            continue
        if in_customers:
            if line.strip() == r"\.":
                break
            if line.strip():
                rows.append(line.strip().split("\t"))

print(f"Total customer rows in init_schema.sql: {len(rows)}")

exact_subs = {}
clean_subs = {}
exact_dups = []
clean_dups = []

for r in rows:
    cid = r[0]
    sub = r[1]
    is_del = r[14]
    
    if sub in exact_subs:
        exact_dups.append((sub, cid, exact_subs[sub]))
    else:
        exact_subs[sub] = cid
        
    clean = re.sub(r"^0+", "", sub)
    if clean == "":
        clean = "0"
    if clean in clean_subs:
        clean_dups.append((clean, sub, cid, clean_subs[clean]))
    else:
        clean_subs[clean] = (sub, cid)

print(f"Exact duplicates found: {len(exact_dups)}")
for d in exact_dups:
    print(f"  Exact dup: {d[0]} in ID {d[1]} vs ID {d[2]}")

print(f"Clean (leading-zero stripped) duplicates found: {len(clean_dups)}")
for d in clean_dups:
    print(f"  Clean dup: {d[0]} (Sub {d[1]}, ID {d[2]} vs Sub {d[3][0]}, ID {d[3][1]})")

deleted_count = sum(1 for r in rows if r[14] == 't')
print(f"Deleted customers: {deleted_count}, Active customers: {len(rows) - deleted_count}")
