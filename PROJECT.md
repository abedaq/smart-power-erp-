# Project: SmartPower ERP Offline Standalone Installer

## Architecture
- **Architecture Type**: Standalone, Zero-Dependency Offline Utility ERP Desktop Package.
- **Backend Monolith**: Go 1.27.0 binary (`SmartPower.exe` / `SmartPowerERP.exe`) embedding React 19 SPA from `frontend/dist` via Fiber v2 `filesystem` middleware.
- **Embedded Database**: Portable PostgreSQL 18.6 (x64) located in `pgsql/bin/*`, `pgsql/lib/*`, `pgsql/share/*`, bound to loopback `127.0.0.1:15432`.
  > [!WARNING]
  > The database cluster data format is PostgreSQL 18.6. Downgrading the binaries to PostgreSQL 16 will break cluster startup due to binary catalog version incompatibility. All packaging scripts (Inno Setup / portable packages) must bundle PostgreSQL 18.6.
- **Database Lifecycle Engine**: `server/internal/database/db_lifecycle.go` managing first-time `initdb`, schema execution, `.db_initialized` idempotency lock, stale PID cleanup, and `pg_ctl stop -m fast` shutdown.
- **Database Schema**: `schema/init_schema.sql` seeded with 494 authentic customers, August 2 cycle readings, invoices, and payments.
- **Installer & Packaging**: Inno Setup 6 script (`SmartPower_Installer.iss`) producing `SmartPowerERP_Setup.exe` (~37.5 MB LZMA2-compressed) targeting `%LOCALAPPDATA%\Programs\SmartPowerERP` with non-admin privileges (`PrivilegesRequired=lowest`).

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Go Monolith Compilation | Compile Go backend embedding React 19 SPA from `frontend/dist` into `SmartPower.exe` | M2 | Survey / ORIGINAL_REQUEST R1 |
| 2 | Embedded PostgreSQL 18 Integration | Integrate portable PostgreSQL 18 engine listening on `127.0.0.1:15432` | M1 | Survey / ORIGINAL_REQUEST R1 |
| 3 | Schema Seeding & August 2 Data | Bundle clean `init_schema.sql` with 494 customers, August 2 readings, invoices, and payments | M1 | Survey / ORIGINAL_REQUEST R1 |
| 4 | Inno Setup Packaging | Package into `SmartPowerERP_Setup.exe` (~37.5 MB) targeting `%LOCALAPPDATA%\Programs\SmartPowerERP` without UAC elevation | M2 | Survey / ORIGINAL_REQUEST R1 |
| 5 | Database Lifecycle Wiring | Wire `db_lifecycle.go` into `main.go` for automated `initdb`, seeding, and `.db_initialized` flag | M1 | Survey / ORIGINAL_REQUEST R2 |
| 6 | Stale PID Detection & Recovery | Automated detection and removal of orphaned `postmaster.pid` on crash/reboot | M3 | Survey / ORIGINAL_REQUEST R2 |
| 7 | Graceful Shutdown | Intercept `os.Interrupt`/`SIGTERM` to issue `pg_ctl stop -m fast` on exit | M1 | Survey / ORIGINAL_REQUEST R2 |
| 8 | Clean Unique Subscriber Index | Enforce `uq_customers_subscriber_number_clean` on `REGEXP_REPLACE(subscriber_number, '^0+', '')` | M1 | Survey / ORIGINAL_REQUEST R3 |
| 9 | Application Anti-Duplication Enforcement | Enforce duplicate subscriber prevention in `CreateCustomer`, `UpdateCustomer`, and `UpdateGridCell` | M1 | Survey / ORIGINAL_REQUEST R3 |
| 10 | Browser Auto-Launch | Auto-launch default browser to `http://localhost:3000` on startup | M3 | Survey / ORIGINAL_REQUEST Acceptance |
| 11 | Restart Idempotency & Data Preservation | Skip re-initialization on subsequent restarts and preserve newly created records | M3 | Survey / ORIGINAL_REQUEST Acceptance |
| 12 | End-to-End Test Suite & Installer Validation | Verify standalone installer extraction, execution, and financial suite validation | M4 | Survey / ORIGINAL_REQUEST Acceptance |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Backend Lifecycle Wiring & Anti-Duplication Core | Wire `db_lifecycle.go` into `main.go`, add graceful shutdown, update `customer_service.go` anti-duplication with leading-zero normalization, clean `init_schema.sql` (494 customers) and update `uq_customers_subscriber_number_clean` index | none | DONE (Gate PASS: main.go wired, customer_service.go normalized, init_schema.sql cleaned to 494 customers, unit tests pass) |
| M2 | Standalone Package Assembly & Inno Setup | Compile Go monolith `SmartPower.exe` embedding React 19 SPA, update Inno Setup script for `%LOCALAPPDATA%`, compile `SmartPowerERP_Setup.exe` (~37.5 MB) | M1 | PLANNED |
| M3 | Self-Healing & Database Lifecycle Validation | Empirically verify first-time init, `.db_initialized` flag, stale PID cleanup, graceful shutdown, restart preservation, and auto-launch | M2 | PLANNED |
| M4 | Final E2E Test Suite & Adversarial Integrity Gate | Run `test_financial_suite.py`, anti-duplication challenge harness, non-admin extraction test, and forensic integrity audit | M3 | PLANNED |

## Interface Contracts
### `server/cmd/server/main.go` ↔ `server/internal/database/db_lifecycle.go`
- `dbManager := database.NewDBLifecycleManager()`
- `dbURL, err := dbManager.EnsureDatabaseReady()`
- Signal hook: `signal.Notify(quit, os.Interrupt, syscall.SIGTERM)` -> `dbManager.Stop()`

### `server/internal/services/customer_service.go` ↔ PostgreSQL Customers Table
- Function: `normalizeSubscriberNumber(s string) string` stripping leading zeros: `regexp.MustCompile("^0+").ReplaceAllString(strings.TrimSpace(s), "")`
- Constraint: `CREATE UNIQUE INDEX uq_customers_subscriber_number_clean ON public.customers USING btree (REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', '')) WHERE (is_deleted = false);`

### Inno Setup (`SmartPower_Installer.iss`) ↔ Portable Distribution (`dist_portable/`)
- Source: `d:\elctercity\dist_portable\*`
- Target: `{localappdata}\Programs\SmartPowerERP`
- Binary: `{app}\SmartPowerERP.exe`
- Compiler: `C:\Program Files (x86)\Inno Setup 6\ISCC.exe`
- Output: `d:\elctercity\SmartPowerERP_Setup.exe`

## Code Layout
- `server/cmd/server/main.go`: Application entrypoint, server startup, DB lifecycle hook, browser auto-launch.
- `server/internal/database/db_lifecycle.go`: Portable PostgreSQL cluster manager (initdb, start, stop, recovery).
- `server/internal/services/customer_service.go`: Customer service, subscriber validation & normalization.
- `dist_portable/schema/init_schema.sql`: Clean database initialization schema (494 customers, August 2).
- `dist_portable/pgsql/`: Embedded PostgreSQL 18.6 binaries and libraries.
- `SmartPower_Installer.iss`: Inno Setup compiler configuration.
- `SmartPowerERP_Setup.exe`: Final distributable installer.
