# BRIEFING — 2026-09-07T14:28:50Z

## Mission
Survey customer data integrity, anti-duplication enforcement (subscriber numbers and normalized regex index), and runtime execution (auto-launch browser, idempotent restart DB preservation, test suites).

## 🔒 My Identity
- Archetype: explorer
- Roles: read-only investigator, synthesizer
- Working directory: d:/elctercity/.agents/explorer_survey_3
- Original parent: 84698da9-7fdd-447b-9ddf-2971e3ed92b4
- Milestone: survey_data_integrity_and_runtime

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Do NOT write or modify application code or run build commands
- Write reports and metadata only in own folder: d:/elctercity/.agents/explorer_survey_3
- Arabic language and RTL formatting for user-facing responses
- English numerals only (0-9)

## Current Parent
- Conversation ID: 84698da9-7fdd-447b-9ddf-2971e3ed92b4
- Updated: 2026-09-07T14:41:35Z

## Investigation State
- **Explored paths**:
  - `dist_portable/schema/init_schema.sql` (Customer table, indexes, COPY data)
  - `database/02_tables_and_constraints.sql` (Customer table schema, indexes)
  - `server/internal/services/customer_service.go` (`CreateCustomer`, `UpdateCustomer`, `UpdateGridCell`, `GetNextSubscriberNumber`)
  - `server/internal/handlers/handlers.go` (`CreateCustomer`, `UpdateCustomer`, `UpdateGridCell`)
  - `server/cmd/server/main.go` (Server lifecycle, routes, browser launch `openURL`)
  - `server/internal/database/db_lifecycle.go` (`NewDBLifecycleManager`, `EnsureDatabaseReady`, `initdb`, `cleanStalePID`, `.db_initialized`)
  - `server/internal/database/db.go` (`InitDB`)
  - Test suites: `test_financial_suite.py`, `test_whatsapp_and_ui.py`, `database/tests/*.sql`, `server/internal/services/financial_test.go`, `server/cmd/seed_and_verify/main.go`
- **Key findings**:
  1. Customer unique index: in `dist_portable/schema/init_schema.sql:7524`, `uq_customers_subscriber_number_clean` is `ON public.customers USING btree (TRIM(BOTH FROM lower((subscriber_number)::text))) WHERE (is_deleted = false)`. In `database/02_tables_and_constraints.sql`, only table UNIQUE constraint and regular index exist. Neither has `REGEXP_REPLACE(subscriber_number, '^0+', '')`.
  2. Go backend anti-duplication: `CreateCustomer` (L152), `UpdateCustomer` (L325), and `UpdateGridCell` (L426) check `TRIM(LOWER(subscriber_number)) = TRIM(LOWER(?))` and check error strings for duplicate key. They do NOT normalize leading zeros (e.g. '0123' vs '123' will pass).
  3. Browser auto-launch: in `server/cmd/server/main.go:222-225`, a goroutine sleeps 800ms and invokes `openURL("http://localhost:" + cfg.Port)` using `rundll32 url.dll,FileProtocolHandler` on Windows.
  4. Database lifecycle & restart idempotency: `db_lifecycle.go:86-118` implements `.db_initialized` check, skips `initdb` and schema seeding on restart, and cleans stale `postmaster.pid`. However, `server/cmd/server/main.go` currently calls `database.InitDB(cfg)` directly and does NOT call `EnsureDatabaseReady()`.
  5. Test suites: Python E2E financial test suite (`test_financial_suite.py`), WhatsApp & analytics test (`test_whatsapp_and_ui.py`), SQL regression test scripts (`database/tests/test_*.sql`), and Go tests (`financial_test.go`, `auth_service_test.go`).
  6. Data state: `init_schema.sql` contains 495 active customers (0 duplicates), 495 meter readings, 1979 invoices, 46 payments.
- **Unexplored areas**: None within survey scope.

## Key Decisions Made
- Confirmed concrete discrepancy between requirement for `REGEXP_REPLACE(subscriber_number, '^0+', '')` and current database/code implementation.
- Identified that Go backend requires `db_lifecycle.go` integration in `cmd/server/main.go`.

## Artifact Index
- `d:/elctercity/.agents/explorer_survey_3/handoff.md` — Final structured survey report
- `d:/elctercity/.agents/explorer_survey_3/check_customers.py` — Verification script for customer records & duplicates

