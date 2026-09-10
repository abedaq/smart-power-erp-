# Project: SmartPower ERP Modernization & Offline-First Standalone Migration

## Architecture
- **Host System**: Windows x64.
- **Backend**: Compiled Go standalone executable (`server.exe`) utilizing Go Fiber v2, PGX v5, pure-Go `whatsmeow` with native PostgreSQL session storage (`CGO_ENABLED=0`), `chromedp` for A5 invoice rendering, and `excelize/v2` for streaming Excel import/export.
- **Frontend**: React Desktop Single-Page Application (React 19, Vite, Tailwind CSS, TanStack Query), built to `frontend/dist` with `base: './'` and embedded directly into `server.exe` via `//go:embed`.
- **Database**: Local PostgreSQL 18.6 instance (`smartpower_db`), accessed with dedicated credentials (`postgres:postgres@localhost:5432/smartpower_db`), strictly enforcing pessimistic row-level locking (`FOR UPDATE`), non-monotonic reading constraints, and deterministic composite invoice numbers (`INV-[Cycle]-[SubscriberNumber]`).
- **Storage & Backup**: Local daily automated `pg_dump -Fc` with auto-detected USB drive mirroring (Win32 API `DRIVE_REMOVABLE`), SHA-256 integrity verification, and graceful fallback.
- **Protocol Governance**: Strictly maintained 3-file migration protocol in `MIGRATION/`:
  1. `MIGRATION/MASTER_PLAN.md`
  2. `MIGRATION/EXECUTION_LOG.md`
  3. `MIGRATION/FINAL_AUDIT.md`

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | 3-File Migration Protocol | Create and govern `MIGRATION/MASTER_PLAN.md`, `MIGRATION/EXECUTION_LOG.md`, and `MIGRATION/FINAL_AUDIT.md` | M1 | ORIGINAL_REQUEST §R1 |
| 2 | Mobile App Deprecation Confirmation | Confirm 100% physical removal of `mobile_app/` and APKs, and update documentation | M1 | ORIGINAL_REQUEST §R4 |
| 3 | Local Database Setup (`smartpower_db`) | Initialize dedicated local PostgreSQL database `smartpower_db` on port 5432 | M2 | ORIGINAL_REQUEST §R2 |
| 4 | Schema Migration & Monotonic Reading Guard | Deploy schema with strict constraints: non-monotonic reading guard, non-negative amounts, UUID idempotency | M2 | ORIGINAL_REQUEST §R2 |
| 5 | Financial Engine & FIFO Waterfall | Implement atomic FIFO waterfall payment allocation with pessimistic locking `FOR UPDATE` | M2 | ORIGINAL_REQUEST §R2 |
| 6 | Deterministic Invoice Numbering | Enforce composite invoice ID format: `INV-[Cycle]-[SubscriberNumber]` across DB and calculations | M2 | ORIGINAL_REQUEST §R2 |
| 7 | Go Fiber REST API Server | Implement standalone Go HTTP server serving exact 14 route groups and 54 endpoints at `/api/...` | M3 | ORIGINAL_REQUEST §R3 |
| 8 | Pure-PG whatsmeow WhatsApp Engine | Implement `whatsmeow` with native PostgreSQL session storage (`CGO_ENABLED=0` binary) and 8-15s rate limiter | M3 | ORIGINAL_REQUEST §R3 |
| 9 | Headless Chromedp A5 Invoicing | Implement server-side A5 dual-stub PDF & image rendering via `chromedp` preserving Arabic ligatures | M3 | ORIGINAL_REQUEST §R3 |
| 10 | Streaming Excel Engine (`excelize/v2`) | Implement high-speed streaming Excel import/export (< 20MB RAM, RTL layout, smart column mapping) | M3 | ORIGINAL_REQUEST §R3 |
| 11 | Embedded React Frontend (`//go:embed`) | Embed `frontend/dist` directly into `server.exe` serving static files at root `http://localhost:3000` | M3 | ORIGINAL_REQUEST §R3 |
| 12 | React Desktop Decoupling & Go API Binding | Remove legacy Supabase fallbacks from frontend services; bind 100% to local Go REST endpoints | M4 | ORIGINAL_REQUEST §R4 |
| 13 | 100% English Numerals Verification | Enforce Western digits (0-9) system-wide, verify CSS resets, and confirm zero Eastern Arabic numerals | M4 | ORIGINAL_REQUEST §R4 |
| 14 | Official A5 Dual-Stub Layout Verification | Validate `InvoiceModal.tsx`, `InvoicePreviewModal.tsx`, and print templates against `photo_5769554780358381104_y.jpg` | M4 | ORIGINAL_REQUEST §R4 |
| 15 | Disaster Recovery & USB Mirroring | Implement automated daily `pg_dump -Fc` backups, Win32 USB mirror detection, and SHA-256 verification | M5 | ORIGINAL_REQUEST §R5 |
| 16 | Financial & Concurrency Stress Testing | Execute automated stress tests: concurrent payments, cascade recalculations, and zero-rounding checks | M5 | ORIGINAL_REQUEST §R5 |
| 17 | Final Protocol Audit Signoff | Complete `MIGRATION/EXECUTION_LOG.md` phase gates and formulate explicit `READY` verdict in `MIGRATION/FINAL_AUDIT.md` | M5 | ORIGINAL_REQUEST §R5 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Protocol Setup & Mobile Deprecation | Initialize `MIGRATION/` (MASTER_PLAN, EXECUTION_LOG, FINAL_AUDIT), formalize baseline, confirm mobile app deprecation | none | IN_PROGRESS |
| M2 | Local PostgreSQL & Financial Integrity | Setup `smartpower_db`, deploy schema, monotonic reading constraints, FIFO waterfall with `FOR UPDATE`, and `INV-[Cycle]-[SubscriberNumber]` | M1 | PLANNED |
| M3 | Standalone Go Backend (`server.exe`) | Build Go Fiber backend: REST API, whatsmeow (pure PG), chromedp A5 rendering, excelize, and embed `frontend/dist` | M2 | PLANNED |
| M4 | React Desktop UI Polish & Decoupling | Decouple frontend from Supabase, bind to local Go API, verify A5 dual-stub invoice and 100% English digits | M3 | PLANNED |
| M5 | Disaster Recovery, Hardening & Audit | Daily automated backups + USB mirror, concurrency stress tests, phase gate verification, and FINAL_AUDIT.md | M4 | PLANNED |

## Interface Contracts

### 1. Database ↔ Go Backend (M2 ↔ M3)
- Connection: `postgres://postgres:postgres@localhost:5432/smartpower_db?sslmode=disable`
- Pool: PGX v5 connection pool (max 25 open, 5 idle).
- Transactions: Isolation level `ReadCommitted` with explicit `SELECT ... FOR UPDATE` for customer balance and invoice allocations.
- Invoice ID constraint: Pattern `^INV-[A-Za-z0-9_\u0600-\u06FF\-]+-[A-Za-z0-9_\-]+$` deterministic composite format.

### 2. Go Backend ↔ React Desktop Frontend (M3 ↔ M4)
- Port: `http://localhost:3000`
- API Base: `/api`
- Endpoints: JSON REST API matching the 14 Express route groups (auth, customers, readings, invoices, payments, settings, whatsapp, export, import, analytics, audit-logs).
- Static Assets: Handled by Fiber `filesystem` middleware embedding `frontend/dist` via `//go:embed dist/*`.
- SPA Routing Fallback: Any non-API route returns `dist/index.html` (HTTP 200).

### 3. Invoicing & Export Engine ↔ Storage (M3 ↔ M5)
- Invoices: Headless Chromedp navigates to `http://localhost:3000/#/print/invoice/:id` or renders standalone HTML template with Edge/Chrome headless, producing A5 PDF / PNG.
- Backups: Stored locally in `d:\elctercity\backups\` and mirrored to detected USB drive `[USB_DRIVE]:\SmartPower_Backups\`.

## Code Layout
- `go_backend/`: Standalone Go source code (`main.go`, `config/`, `handlers/`, `models/`, `services/`, `whatsapp/`, `chromedp/`, `excel/`, `backup/`).
- `frontend/`: React Desktop source code (`src/`, `public/`, `dist/`).
- `MIGRATION/`: Strictly 3 files: `MASTER_PLAN.md`, `EXECUTION_LOG.md`, `FINAL_AUDIT.md`.
- `backups/`: Local database dump directory (`smartpower_backup_YYYYMMDD_HHMMSS.dump`).
