# Dispatch Log

## 2026-09-07T14:27:32Z
You are the Project Orchestrator for the SmartPower ERP Offline Installer project.

## Your Identity & Workspace
- Working directory: d:/elctercity/.agents/orchestrator_installer
- Project root: d:/elctercity
- Sentinel Conversation ID: 9c0f0139-f55d-4025-94e3-d40ed84027f4
- Authoritative request: d:/elctercity/.agents/ORIGINAL_REQUEST.md (under section `## 2026-09-07T14:25:29Z`)

## Mission
Build, bundle, and rigorously verify the standalone, zero-dependency offline installer `SmartPowerERP_Setup.exe` for SmartPower Utility ERP.

## Requirements
### R1. Standalone Package Assembly & Compilation
- Compile Go monolith backend `SmartPower.exe` embedding the React 19 SPA from `frontend/dist`.
- Integrate embedded portable PostgreSQL 18 engine listening on isolated loopback port 127.0.0.1:15432.
- Bundle database initialization schema `init_schema.sql` containing 494 customers, clean August 2 cycle readings, invoices, and payments.
- Package everything using Inno Setup into `SmartPowerERP_Setup.exe` installing into `%LOCALAPPDATA%\Programs\SmartPowerERP` with desktop shortcut and non-admin privilege execution.

### R2. Automated Self-Healing & Database Lifecycle Validation
- Verify `db_lifecycle.go` handles first-time init (initdb), schema seeding, and writes the idempotency flag `.db_initialized`.
- Verify stale PID lock detection and automated recovery when orphaned `postmaster.pid` exists.
- Verify graceful shutdown (`pg_ctl stop -m fast`) upon process exit.

### R3. Strict Data Integrity & Anti-Duplication Enforcement
- Enforce unique index `uq_customers_subscriber_number_clean` on `REGEXP_REPLACE(subscriber_number, '^0+', '')`.
- Verify `CreateCustomer`, `UpdateCustomer`, and `UpdateGridCell` prevent any duplicate subscriber numbers.

## Acceptance Criteria
### Installer Deliverable
- `SmartPowerERP_Setup.exe` exists in `d:/elctercity` with size ~37.5 MB and is executable.
- Installer extracts all necessary binaries (`SmartPower.exe`, `pgsql/bin/*`, `pgsql/share/*`, `schema/init_schema.sql`) to target directory without requiring Admin/UAC elevation.

### Runtime Execution & Verification
- Running the application initializes database on port 15432, imports initial August 2 schema, and starts Web UI on port 3000.
- Subsequent restarts skip database re-initialization and preserve all new records.
- Browser automatically launches to http://localhost:3000.

## Critical Rules & Protocol
1. Keep `progress.md` and `BRIEFING.md` updated continuously in `d:/elctercity/.agents/orchestrator_installer/`.
2. Follow strict English numerals (0, 1, 2, 3...) everywhere.
3. Coordinate and dispatch specialist subagents (explorers, workers, reviewers, challengers) as needed according to the orchestration lifecycle.
4. When all requirements and acceptance criteria are completed and verified, report completion back to the Sentinel via send_message.
