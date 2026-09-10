# Dispatch: Explorer Migration Backend

## 2026-09-06T08:02:10Z

**Sender**: orchestrator_migration (8662d701-dced-4ddd-b545-e2b64c0e3fc2)
**Identity**: explorer_migration_backend (Role: Backend and Database Surveyor)
**Working directory**: d:\elctercity\.agents\explorer_migration_backend

**Target Request**:
Authoritative request in `d:\elctercity\.agents\ORIGINAL_REQUEST.md` (section `## 2026-09-06T07:57:38Z`).

**Scope & Mission**:
Conduct a comprehensive, read-only technical investigation into the existing backend and database systems to map requirements for migration to a 100% offline-first standalone Go backend (`server.exe`) and local PostgreSQL (`smartpower_db`).

**Specific Investigation Targets**:
1. Examine `backend/` codebase: Express app, routes, controllers, services, middleware, dependencies (`package.json`). Map all JSON REST API endpoints currently served at `/api/...` (e.g. readings, customers, invoices, arrears, auth, settings, collectors, WhatsApp).
2. Examine database architecture: Supabase migrations (`supabase/migrations/` or similar), SQL schema files, table structures, RPC functions (`rpc_submit_meter_reading`, `rpc_submit_payment`, etc.), triggers, views.
3. Investigate financial calculations:
   - Consumption = Current - Previous.
   - Lost units calculation.
   - Tariff / pricing rules.
   - Strict monotonic reading enforcement (guard against negative or lower readings).
   - Pessimistic locking (`FOR UPDATE`) for FIFO waterfall payment allocation.
   - Deterministic composite invoice numbering format: `INV-[Cycle]-[SubscriberNumber]`.
4. Investigate WhatsApp integration:
   - Current implementation (Baileys/Node or mock).
   - Target Go engine: `whatsmeow` with pure PostgreSQL session storage (CGO_ENABLED=0 pure binary).
   - Background message queue and rate limiting (8-15s delay).
5. Investigate Go tooling & environment in the system:
   - Check if `go` is installed, version, module setup, dependencies needed (Go Fiber, pgx, excelize, chromedp, whatsmeow).
6. Assess performance & standalone compilation criteria:
   - Standalone binary `< 25MB`, RAM usage `< 35MB`.

**Deliverables**:
- `d:\elctercity\.agents\explorer_migration_backend\analysis.md`
- `d:\elctercity\.agents\explorer_migration_backend\handoff.md`
- Send completion message to parent.
