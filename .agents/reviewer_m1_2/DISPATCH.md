# Dispatch for reviewer_m1_2

## Milestone M1 Review: Database Schema Review
Read:
- `d:/elctercity/.agents/ORIGINAL_REQUEST.md` (section `## 2026-09-07T14:25:29Z`)
- `d:/elctercity/PROJECT.md`
- `d:/elctercity/.agents/worker_m1/handoff.md`
- Code files: `dist_portable/schema/init_schema.sql`, `database/02_tables_and_constraints.sql`

Review tasks:
1. Verify `dist_portable/schema/init_schema.sql`:
   - Unique index `uq_customers_subscriber_number_clean` uses `REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')`.
   - Customer count is exactly 494 (test customer 495 is removed).
   - Invoices count is exactly 494 (test invoices for Sept/Oct are removed).
   - Sequences (`setval`) are correctly set to 494.
   - Clean August 2 cycle state.
2. Verify `database/02_tables_and_constraints.sql`:
   - Unique clean index is properly declared.

Provide verdict (`APPROVE` or `REQUEST_CHANGES`) in `d:/elctercity/.agents/reviewer_m1_2/handoff.md`.
