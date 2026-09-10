# Dispatch: Explorer M2 Cascade Recalc

**Target**: `d:\elctercity\.agents\explorer_m2_cascade_recalc`
**Milestone**: M2 - Local PostgreSQL Database & Financial Integrity Core
**Task**: Design retroactive cascade billing cycle recalculation engine across cycles (T -> N), customer balance locking (`ORDER BY customer_id ASC FOR UPDATE`), and transactional safety.

## 2026-09-06T09:20:36Z
Your identity: explorer_m2_cascade_recalc (Role: Cascade Recalculation Engine Architect)
Your working directory: d:\elctercity\.agents\explorer_m2_cascade_recalc
Your parent: orchestrator_migration (Conversation ID: 8662d701-dced-4ddd-b545-e2b64c0e3fc2)

MANDATORY FIRST STEP:
Read the authoritative user request at:
d:\elctercity\.agents\ORIGINAL_REQUEST.md (§ 2026-09-06T07:57:38Z)

INPUTS TO READ:
- `d:\elctercity\.agents\orchestrator_migration\PROJECT.md`
- `d:\elctercity\MIGRATION\MASTER_PLAN.md` (§ 2.3 and § 2.4)
- `d:\elctercity\MIGRATION\EXECUTION_LOG.md` (check Gate 2.6 specification)
- `backend/src/services/recalculation.service.ts`

YOUR TASK:
Design the retroactive cascade billing cycle recalculation engine:
1. When a past cycle reading or payment is modified at cycle $T$:
   - Propagate recalculated consumption, totals, and arrears forward from $T$ to subsequent cycles $T+1, T+2, \dots, N$.
2. Locking & Concurrency strategy:
   - Lock customer records in strict ascending order (`ORDER BY customer_id ASC FOR UPDATE`) to eliminate deadlock risks.
3. Mathematical precision:
   - 0 rounding errors: all financial amounts rounded strictly to 2 decimal places (`ROUND(x, 2)` or `NUMERIC(12,2)`).
   - Verified formula:
     `Consumption = Current - Previous`
     `ConsumptionCost = Consumption * UnitPrice`
     `LostUnitsCost = LostUnits * UnitPrice`
     `TotalDue = ConsumptionCost + LostUnitsCost + FixedServiceFee + Arrears`
     `RemainingAmount = TotalDue - PaidAmount`

OUTPUT REQUIREMENTS:
Write your complete technical proposal and implementation design to:
`d:\elctercity\.agents\explorer_m2_cascade_recalc\analysis.md`
Write your self-contained handoff report to:
`d:\elctercity\.agents\explorer_m2_cascade_recalc\handoff.md`
Notify parent via send_message.
