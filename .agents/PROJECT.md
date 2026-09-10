# Project: Smart Power ERP Audit & Verification

## Architecture & Scope
Comprehensive End-to-End Audit & Verification of the Smart Power ERP system covering Flutter mobile application, Express/Node.js backend, Supabase PostgreSQL RPCs, and React Web Dashboard.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | R1.1 Hive Local DB & UI | Offline & online meter reading entry with local Hive DB caching and instant UI update | M1 | ORIGINAL_REQUEST §R1 |
| 2 | R1.2 Cycle Sequencing | Automatic billing cycle sequencing (e.g. "أغسطس- 1 - 2026" to "أغسطس- 2 - 2026") | M1 | ORIGINAL_REQUEST §R1 |
| 3 | R1.3 Payment Idempotency | Payment voucher entry with client-side UUID idempotency key generation & duplicate prevention | M1 | ORIGINAL_REQUEST §R1 |
| 4 | R1.4 Lower Reading Validation | Strict validation blocking meter readings lower than last approved reading + alert UI | M1 | ORIGINAL_REQUEST §R1 |
| 5 | R2.1 rpc_submit_meter_reading | Signature verification, parameter mapping (no PGRST203), JSON response {success, error} | M2 | ORIGINAL_REQUEST §R2 |
| 6 | R2.2 rpc_submit_payment FIFO | FIFO invoice allocation (settling oldest pending invoices first) & credit balance calculation | M2 | ORIGINAL_REQUEST §R2 |
| 7 | R2.3 Offline Queue Resilience | Resilient error handling (discard failed queue items without blocking valid items) | M2 | ORIGINAL_REQUEST §R2 |
| 8 | R3.1 JWT Session Precedence | JWT session resolution giving precedence to local backend admin tokens over collector accounts | M3 | ORIGINAL_REQUEST §R3 |
| 9 | R3.2 RBAC 403 Enforcement | RBAC permission boundaries for ADMIN, ACCOUNTANT, COLLECTOR (HTTP 403 for collector on tariff/user mgmt) | M3 | ORIGINAL_REQUEST §R3 |
| 10 | R4.1 Reading Rejection & Invoice VOID | Rejection workflow, state transition to REJECTED, automatic voiding of associated invoice (VOID) | M4 | ORIGINAL_REQUEST §R4 |
| 11 | R4.2 Reading Rollback | Meter query calculation rollback reverting immediately to previous approved reading | M4 | ORIGINAL_REQUEST §R4 |
| 12 | R4.3 Cache Invalidation | React Query cache invalidation upon reading rejection or approval | M4 | ORIGINAL_REQUEST §R4 |
| 13 | R5.1 Consumption Equation | Consumption = Current Reading - Last Approved Reading verification | M5 | ORIGINAL_REQUEST §R5 |
| 14 | R5.2 Invoice Total Calculation | Total = Consumption Amount + Fixed Fees + Previous Outstanding Arrears | M5 | ORIGINAL_REQUEST §R5 |
| 15 | R5.3 PDF & WhatsApp Notification | PDF invoice generation and automated WhatsApp billing notification dispatch | M5 | ORIGINAL_REQUEST §R5 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M0 | Survey & Architecture Mapping | Survey Flutter, Express, Supabase RPCs, React UI | none | DONE |
| M1 | R1: Flutter Mobile App Audit | Field Collector Hive cache, cycle sequencing, UUID idempotency, lower reading validation | M0 | DONE |
| M2 | R2: Sync & Supabase RPC Audit | rpc_submit_meter_reading, rpc_submit_payment FIFO, offline sync error resilience | M0 | DONE |
| M3 | R3: Auth & RBAC Audit | JWT session resolution precedence, RBAC 403 enforcement | M0 | DONE |
| M4 | R4: Rejection & Void Engine Audit | Rejection workflow, VOID invoices, reading rollback, React Query invalidation | M0 | DONE |
| M5 | R5: Financial Billing & Notifications | Billing equations, totals, arrears, PDF generation, WhatsApp notifications | M0 | DONE |
| M6 | Consolidated Comprehensive Audit Report | Final synthesized report with code proofs, query outputs, and test logs | M1, M2, M3, M4, M5 | IN_PROGRESS |

## Code Layout & Audit Targets
- Flutter Mobile App: `lib/`, `android/`, `ios/` or mobile subdirectories
- Express Backend: `server/`, `backend/`, `src/routes/`, `src/controllers/`, `src/services/`
- Supabase RPCs & Migrations: `supabase/`, `migrations/`, SQL files
- React Web UI: `src/`, `web/`, `frontend/`, components and state management
- Test Suites: unit, integration, and E2E verification test scripts
