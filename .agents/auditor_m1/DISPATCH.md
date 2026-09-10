# Dispatch for auditor_m1

## Milestone M1 Forensic Audit
Read:
- `d:/elctercity/.agents/ORIGINAL_REQUEST.md` (section `## 2026-09-07T14:25:29Z`)
- `d:/elctercity/PROJECT.md`
- `d:/elctercity/.agents/worker_m1/handoff.md`
- Changed files: `server/cmd/server/main.go`, `server/internal/services/customer_service.go`, `dist_portable/schema/init_schema.sql`, `database/02_tables_and_constraints.sql`

Audit tasks:
1. Forensic integrity checks:
   - Check if any test results, customer IDs, or error messages are hardcoded to fool tests.
   - Check if `NormalizeSubscriberNumber` and `REGEXP_REPLACE` are genuine implementations.
   - Check if `init_schema.sql` contains genuine 494 customers and genuine August 2 data.
   - Check if `DBLifecycleManager` calls in `main.go` are genuine and not dummy mocks.
2. Provide a strict binary verdict: `CLEAN` or `INTEGRITY VIOLATION`.

Write full evidence report in `d:/elctercity/.agents/auditor_m1/handoff.md`.

## 2026-09-07T15:03:43Z
You are auditor_m1.
Your working directory is d:/elctercity/.agents/auditor_m1.
Read your task assignment in d:/elctercity/.agents/auditor_m1/DISPATCH.md.
MANDATORY: Read d:/elctercity/.agents/ORIGINAL_REQUEST.md before starting work.
Perform a forensic integrity audit on all changes made by worker_m1. Verify that there are no hardcoded mocks, facade implementations, or circumventions. Verify authentic logic in `main.go`, `customer_service.go`, and `init_schema.sql`.
Write your full evidence report and binary verdict (CLEAN or INTEGRITY VIOLATION) in `d:/elctercity/.agents/auditor_m1/handoff.md` and send a completion message.
