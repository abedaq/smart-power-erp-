# Dispatch: Explorer M2 Financial Core

## 2026-09-06T09:20:36Z
Your identity: explorer_m2_financial_core (Role: Financial Integrity Core Architect)
Your working directory: d:\elctercity\.agents\explorer_m2_financial_core
Your parent: orchestrator_migration (Conversation ID: 8662d701-dced-4ddd-b545-e2b64c0e3fc2)

MANDATORY FIRST STEP:
Read the authoritative user request at:
d:\elctercity\.agents\ORIGINAL_REQUEST.md (§ 2026-09-06T07:57:38Z)

INPUTS TO READ:
- `d:\elctercity\.agents\orchestrator_migration\PROJECT.md`
- `d:\elctercity\MIGRATION\MASTER_PLAN.md` (§ 2.1 and § 2.2)
- `d:\elctercity\MIGRATION\EXECUTION_LOG.md` (check Gate 2.3, 2.4, 2.5 specifications)
- `backend/scripts/deploy_complete_database_procedures.sql`
- `backend/src/scripts/unify_payment_rpc.ts`

YOUR TASK:
Design the complete financial integrity core procedures and logic:
1. Strict monotonic reading constraint trigger/procedure:
   - Guard against negative or lower readings (`current_reading >= previous_reading`).
   - Allow legitimate meter replacement/rollover via explicit flag (`is_meter_reset = true`).
2. Atomic FIFO waterfall payment allocation procedure:
   - Pessimistic row-level locking: `SELECT ... FROM invoices WHERE customer_id = ... AND status IN ('Unpaid', 'Partially_Paid') ORDER BY due_date ASC, id ASC FOR UPDATE`.
   - Lock customer record first: `SELECT ... FROM customers WHERE id = ... FOR UPDATE`.
   - Waterfall payment allocation settling oldest pending invoices first.
   - Any excess payment stored as customer credit balance (`balance`).
3. Deterministic composite invoice numbering:
   - Format: `INV-[Cycle]-[SubscriberNumber]` (e.g. `INV-2026-08-C101`).
   - Enforce uniqueness and pattern constraints (`CHECK (invoice_number ~ '^INV-[A-Za-z0-9_\u0600-\u06FF\-]+-[A-Za-z0-9_\-]+$')`).

OUTPUT REQUIREMENTS:
Write your complete technical proposal and PL/pgSQL scripts to:
`d:\elctercity\.agents\explorer_m2_financial_core\analysis.md`
Write your self-contained handoff report to:
`d:\elctercity\.agents\explorer_m2_financial_core\handoff.md`
Notify parent via send_message.

## 2026-09-06T09:36:03Z
From: orchestrator_migration (8662d701-dced-4ddd-b545-e2b64c0e3fc2)
**Context**: Status check on Financial Integrity Core design report.
**Content**: Please report your current progress, completed items, and estimated time to deliver analysis.md and handoff.md.
**Action**: Reply with brief status update.
