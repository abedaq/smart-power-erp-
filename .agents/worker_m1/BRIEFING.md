# BRIEFING — 2026-09-07T15:01:00Z

## Mission
Implement backend lifecycle wiring, graceful shutdown, subscriber anti-duplication with leading-zero stripping, and clean the initial database schema to 494 customers for the standalone offline installer.

## 🔒 My Identity
- Archetype: implementer
- Roles: implementer, qa, specialist
- Working directory: d:\elctercity\.agents\worker_m1
- Original parent: 84698da9-7fdd-447b-9ddf-2971e3ed92b4
- Milestone: M1 (Backend Lifecycle Wiring & Anti-Duplication Core)

## 🔒 Key Constraints
- Exclusive write ownership:
  1. `server/cmd/server/main.go`
  2. `server/internal/services/customer_service.go`
  3. `dist_portable/schema/init_schema.sql`
  4. `database/02_tables_and_constraints.sql`
- DO NOT CHEAT: Genuine logic, no hardcoded results, no dummy implementations.
- 100% English numerals in all documents and code.
- Arabic language with <div dir="rtl"> for conversation responses.

## Current Parent
- Conversation ID: 84698da9-7fdd-447b-9ddf-2971e3ed92b4
- Updated: 2026-09-07T15:01:00Z

## Task Summary
- **What to build**:
  1. Wire `DBLifecycleManager` in `server/cmd/server/main.go`: initialize, call `EnsureDatabaseReady()`, set `cfg.DatabaseURL = dbURL`, handle SIGINT/SIGTERM to call `dbManager.Stop()`.
  2. Implement strict anti-duplication in `server/internal/services/customer_service.go`: strip leading zeros in `CreateCustomer`, `UpdateCustomer`, and `UpdateGridCell` using regex/clean check.
  3. Update `dist_portable/schema/init_schema.sql` and `database/02_tables_and_constraints.sql`:
     - Unique index `uq_customers_subscriber_number_clean` on `REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')`.
     - Remove test customer 495 (`اختبار نظام`) from `customers` table so exactly 494 authentic customers remain.
     - Clean out test invoices for Sept 1, Sept 2, Oct 1 and any test readings/payments/audit logs associated with customer 495, leaving a clean August 2 cycle state.
  4. Verify by running `go test ./...` in `server/` and `go build -o server.exe ./cmd/server`.
- **Success criteria**:
  - `main.go` starts embedded DB and hooks shutdown signals: [VERIFIED]
  - Anti-duplication blocks duplicate subscriber numbers with or without leading zeros: [VERIFIED]
  - `init_schema.sql` has exactly 494 customers, clean August 2 cycle, clean index: [VERIFIED]
  - `02_tables_and_constraints.sql` has clean index: [VERIFIED]
  - `go test ./...` passes in `server/`: [VERIFIED]
  - `go build -o server.exe ./cmd/server` succeeds: [VERIFIED]
- **Interface contracts**: PROJECT.md
- **Code layout**: `server/`, `dist_portable/schema/`, `database/`

## Change Tracker
- **Files modified**:
  - `server/cmd/server/main.go` — Initialized DBLifecycleManager, EnsureDatabaseReady(), overridden cfg.DatabaseURL, hooked SIGINT/SIGTERM with dbManager.Stop().
  - `server/internal/services/customer_service.go` — Added NormalizeSubscriberNumber, updated CreateCustomer, UpdateCustomer, UpdateGridCell, and GetNextSubscriberNumber with REGEXP_REPLACE zero-stripping.
  - `dist_portable/schema/init_schema.sql` — Cleaned to 494 customers, 494 August 2 invoices, 494 readings, removed customer 495 & test logs, updated uq_customers_subscriber_number_clean index, setval to 494.
  - `database/02_tables_and_constraints.sql` — Added uq_customers_subscriber_number_clean unique index with REGEXP_REPLACE zero-stripping.
- **Build status**: PASS
- **Pending issues**: None

## Quality Status
- **Build/test result**: `go test ./...` PASS (0.250s), `go build -o server.exe ./cmd/server` PASS
- **Lint status**: Clean, zero syntax or type errors
- **Tests added/modified**: Executed `verify_all.py` validating all constraints

## Loaded Skills
- None

## Key Decisions Made
- `NormalizeSubscriberNumber` uses `^0+` regex matching PostgreSQL's `REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')`.
- `main.go` shutdown handler triggers `dbManager.Stop()` before `app.Shutdown()`, and defers `dbManager.Stop()` as well.
- Cleaned seed schema retains all 494 authentic customers from the historical August 2 billing cycle without any test remnants.

## Artifact Index
- `d:\elctercity\.agents\worker_m1\DISPATCH.md` — Assignment instructions
- `d:\elctercity\.agents\worker_m1\progress.md` — Liveness and task progress
- `d:\elctercity\.agents\worker_m1\handoff.md` — Final handoff report
- `d:\elctercity\.agents\worker_m1\clean_schema.py` — Schema cleaning script
- `d:\elctercity\.agents\worker_m1\verify_all.py` — Comprehensive verification script
