# Dispatch: Explorer M1 Master Plan

**Target**: `d:\elctercity\.agents\explorer_m1_masterplan`
**Milestone**: M1 - Protocol Setup & Mobile Deprecation
**Task**: Formulate exact specifications and draft content for `MIGRATION/MASTER_PLAN.md` based on ORIGINAL_REQUEST.md (§ 2026-09-06T07:57:38Z) and Phase 0 survey findings.

## 2026-09-06T08:29:46Z
Your identity: explorer_m1_masterplan (Role: Master Plan Designer)
Your working directory: d:\elctercity\.agents\explorer_m1_masterplan
Your parent: orchestrator_migration (Conversation ID: 8662d701-dced-4ddd-b545-e2b64c0e3fc2)

MANDATORY FIRST STEP:
Read the authoritative user request at:
d:\elctercity\.agents\ORIGINAL_REQUEST.md
Pay special attention to section `## 2026-09-06T07:57:38Z`.

ALSO READ INPUT CONTEXT:
- `d:\elctercity\.agents\orchestrator_migration\PROJECT.md`
- `d:\elctercity\.agents\explorer_migration_backend\analysis.md`
- `d:\elctercity\.agents\explorer_migration_frontend\analysis.md`
- `d:\elctercity\.agents\explorer_migration_ops\analysis.md`

YOUR SCOPE & MISSION:
Formulate the exact, comprehensive content and structure for `MIGRATION/MASTER_PLAN.md` governing the entire migration:
1. Executive Summary & Core Mission (Offline-first, standalone Go binary server.exe, local PostgreSQL smartpower_db, embedded React Desktop, pure PG whatsmeow, mobile app deprecation).
2. Comprehensive Business Logic & Calculation Inventory:
   - Consumption = Current - Previous reading (monotonic reading guard, reject current < previous).
   - Lost Units Cost = Lost Units * Unit Price.
   - Total Due = Consumption Cost + Fixed Service Fee + Arrears.
   - Remaining = Total Due - Paid Amount.
   - FIFO Waterfall payment allocation with pessimistic row-level locking (`FOR UPDATE`).
   - Cascade billing cycle recalculation (retroactive adjustment propagation).
   - Deterministic composite invoice numbering format: `INV-[Cycle]-[SubscriberNumber]`.
3. Complete REST API Contract Mapping (the 14 route groups and 54 endpoints mapped in backend analysis).
4. Target Architecture & Technology Stack:
   - Standalone Go Fiber backend (< 25MB binary, < 35MB RAM, `CGO_ENABLED=0`).
   - Native PostgreSQL session storage for whatsmeow (pure Go, 8-15s rate limiter).
   - Chromedp headless A5 invoice PDF/image rendering.
   - Excelize streaming import/export (< 20MB RAM, RTL layout).
   - React Desktop embedded via `//go:embed` with 100% English digits.
   - Local daily automated `pg_dump -Fc` with Win32 USB mirror and SHA-256 validation.
5. Phased Migration Roadmap with concrete phase deliverables.

OUTPUT REQUIREMENTS:
Write your complete technical proposal and draft to:
`d:\elctercity\.agents\explorer_m1_masterplan\analysis.md`
and write your self-contained handoff report to:
`d:\elctercity\.agents\explorer_m1_masterplan\handoff.md`
Once written, use `send_message` to notify orchestrator_migration that your report is ready.
