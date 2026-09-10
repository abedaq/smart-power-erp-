# Plan: Resilience & Integrity Verification of SmartPower ERP

## Architecture & Scope
- **Target System**: SmartPower Utility ERP (Go backend monolith, embedded PostgreSQL on 127.0.0.1:15432, React 19 SPA on http://localhost:3000).
- **Mission**: Comprehensive monitoring, stress testing, and forensic audit of Frontend UI, Database Transactions, and Audit Logs under heavy concurrent load.

## Feature & Verification Inventory
| # | Area | Scope / Requirement | Method | Milestone |
|---|------|---------------------|--------|-----------|
| 1 | R1: Frontend UI Resilience | Dashboard, Grid, Billing & Collection modals under concurrent ops. Check for UI freezing, console errors, live cell updates. | Headless / Playwright / HTTP / UI state inspection | M1 |
| 2 | R2: Database Integrity | PostgreSQL constraints, zero duplicate subscriber/voucher numbers, FIFO payments, customer credits, 100% KPI match. | SQL assertions & concurrent load scripts | M2 |
| 3 | R3: Audit Logs Forensics | All CRUD & payment actions logged in `audit_logs` without leakage, verifying user_id, action, timestamp, metadata. | SQL audit queries & forensic inspection | M3 |
| 4 | Verification & Hardening | Independent review, adversarial challenge, and forensic integrity audit. | Reviewers, Challenger, Forensic Auditor | M4 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M0 | Survey & Architecture Mapping | Survey frontend, backend, DB, and existing test scripts | none | IN_PROGRESS |
| M1 | R1: Frontend UI Stress & Interaction | Verify UI resilience, no freezing, zero console errors, instant cell updates | M0 | PLANNED |
| M2 | R2: Database Integrity & Reconciliation | Verify constraints, zero duplicate subscribers/vouchers, 100% KPI match | M0 | PLANNED |
| M3 | R3: Audit Logs & Forensic Verification | Verify 100% audit logging coverage for all operations | M0 | PLANNED |
| M4 | Independent Review & Forensic Audit | Challengers, Reviewers, and Forensic Auditor verification | M1, M2, M3 | PLANNED |
| M5 | Consolidated Reporting & Handoff | Arabic RTL report with English numbers & complete evidence | M4 | PLANNED |

## Code & Script Layout
- `server/`: Go backend source code.
- `frontend/`: React 19 source code.
- `schema/` & `database/`: Database migration & seed schemas.
- `test_financial_suite.py`: Financial integrity test script.
- `test_subscriber_anti_duplication.py`: Anti-duplication test script.
- `.agents/`: Agent workspaces and state metadata.
