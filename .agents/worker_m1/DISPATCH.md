# Dispatch for worker_m1

## Milestone: M1 — Backend Lifecycle Wiring & Anti-Duplication Core

## Objective
Implement all backend lifecycle wiring, graceful shutdown, subscriber anti-duplication with leading-zero stripping, and clean the initial database schema to 494 customers.

## Context & Explorer Findings
Read:
- `d:/elctercity/PROJECT.md`
- `d:/elctercity/.agents/explorer_survey_1/handoff.md`
- `d:/elctercity/.agents/explorer_survey_2/handoff.md`
- `d:/elctercity/.agents/explorer_survey_3/handoff.md`
- `d:/elctercity/.agents/ORIGINAL_REQUEST.md` (section `## 2026-09-07T14:25:29Z`)

## Mandatory Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Write Ownership & Scope
You exclusively own and may edit:
1. `server/cmd/server/main.go`
2. `server/internal/services/customer_service.go`
3. `dist_portable/schema/init_schema.sql`
4. `database/02_tables_and_constraints.sql`

## Concrete Tasks
1. **Wire DBLifecycleManager in `server/cmd/server/main.go`**:
   - Before `database.InitDB(cfg)`, instantiate `dbManager := database.NewDBLifecycleManager()`.
   - Call `dbURL, err := dbManager.EnsureDatabaseReady()`. Handle error gracefully.
   - Override `cfg.DatabaseURL = dbURL` (connecting to embedded PostgreSQL on `127.0.0.1:15432`).
   - Setup signal notification on `os.Interrupt`, `syscall.SIGTERM`. On signal, call `dbManager.Stop()` to stop PostgreSQL with `pg_ctl stop -m fast`.
2. **Strict Anti-Duplication in `server/internal/services/customer_service.go`**:
   - Add a helper to normalize subscriber numbers by removing leading zeros:
     e.g., `cleanSub := regexp.MustCompile("^0+").ReplaceAllString(strings.TrimSpace(sub), "")`
   - In `CreateCustomer`, `UpdateCustomer`, and `UpdateGridCell`:
     Check for existing customer using normalized subscriber number:
     `REGEXP_REPLACE(TRIM(LOWER(subscriber_number)), '^0+', '') = ?`
     Ensure error message clearly prevents duplicate subscriber numbers.
3. **Database Schema & Index Update**:
   - In `dist_portable/schema/init_schema.sql`:
     - Update index `uq_customers_subscriber_number_clean`:
       `CREATE UNIQUE INDEX uq_customers_subscriber_number_clean ON public.customers USING btree (REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')) WHERE (is_deleted = false);`
     - Remove test customer 495 (`اختبار نظام`) from `customers` table so exactly 494 authentic customers remain.
     - Clean out test invoices for Sept 1, Sept 2, Oct 1 and any test readings/payments/audit logs associated with customer 495, leaving a clean August 2 cycle state.
   - In `database/02_tables_and_constraints.sql`:
     - Ensure the clean index `uq_customers_subscriber_number_clean` on `REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')` is present.
4. **Compile & Verify**:
   - Run `go test ./...` in `server/`.
   - Run `go build -o server.exe ./cmd/server` in `server/` to verify compilation.

## Output
Write report to `d:/elctercity/.agents/worker_m1/handoff.md`.

## 2026-09-07T14:45:44Z
<USER_REQUEST>
You are worker_m1.
Your working directory is d:/elctercity/.agents/worker_m1.
Read your task assignment in d:/elctercity/.agents/worker_m1/DISPATCH.md.
MANDATORY: Read d:/elctercity/.agents/ORIGINAL_REQUEST.md before starting work.

DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Scope & exclusive write ownership:
1. `server/cmd/server/main.go`
2. `server/internal/services/customer_service.go`
3. `dist_portable/schema/init_schema.sql`
4. `database/02_tables_and_constraints.sql`

Implement:
1. Wire `DBLifecycleManager` in `server/cmd/server/main.go`: initialize, call `EnsureDatabaseReady()`, set `cfg.DatabaseURL = dbURL`, intercept SIGINT/SIGTERM to call `dbManager.Stop()`.
2. Implement strict anti-duplication in `server/internal/services/customer_service.go`: strip leading zeros in `CreateCustomer`, `UpdateCustomer`, and `UpdateGridCell` using regex/clean check.
3. Update `dist_portable/schema/init_schema.sql` and `database/02_tables_and_constraints.sql`:
   - Update unique index `uq_customers_subscriber_number_clean` to `REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')`.
   - Clean test customer 495 and test invoices/logs so that exactly 494 authentic customers and clean August 2 cycle state remain.
4. Verify by running `go test ./...` in `server/` and `go build -o server.exe ./cmd/server`.

Document all changes, file paths, diffs, and test commands/outputs in `d:/elctercity/.agents/worker_m1/handoff.md`. Send completion message when done.
</USER_REQUEST>
