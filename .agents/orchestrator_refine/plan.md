# Execution Plan — Smart Power ERP Refinement

## Goal
Implement and verify all 5 core requirements (R1 - R5) plus end-to-end build verification (R6) per ORIGINAL_REQUEST.md.

## Phase 0: Survey & Codebase Exploration
- Explorer 1: Frontend Architecture & UI Analysis (R1 Number inputs/spinners, R2 Arrears tab + General tariff removal, R5 Live operations log UI).
- Explorer 2: Invoice Template & Preview/Print/WhatsApp Analysis (R3 Invoice matching photo_5769554780358381104_y.jpg, components, shared generator).
- Explorer 3: Backend & Database Analysis (R4 PostgreSQL RPC error "column 'r' does not exist" in rpc_submit_meter_reading and rpc_approve_meter_reading, error handling, R5 manager auto-approval).

## Phase 1: Milestone Decomposition & Project Scope Definition
- Synthesize findings into `PROJECT.md`.
- Finalize Feature Inventory, code layout, interface contracts, and milestone breakdown.

## Phase 2: Implementation (Milestones M1 - M5)
- M1: R1 Number Inputs & Spinner Removal.
- M2: R2 Independent Arrears Tab & Delete General Tariff & Fees Tab.
- M3: R3 Official Invoice Template strictly matching photo_5769554780358381104_y.jpg.
- M4: R4 Backend & RPC column "r" error fix with clean Arabic error responses.
- M5: R5 Live Operations Log Excel Grid & Admin Auto-Approval Flow.

## Phase 3: Verification & Quality Gate (M6)
- Reviewer checks, Challenger stress testing, and Forensic Auditor verification.
- Full build check (frontend + backend 0 errors).
- Final report to Parent.
