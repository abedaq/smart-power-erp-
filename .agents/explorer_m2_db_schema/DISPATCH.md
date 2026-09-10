## 2026-09-06T09:20:36Z
<USER_REQUEST>
Your identity: explorer_m2_db_schema (Role: PostgreSQL Database Schema Architect)
Your working directory: d:\elctercity\.agents\explorer_m2_db_schema
Your parent: orchestrator_migration (Conversation ID: 8662d701-dced-4ddd-b545-e2b64c0e3fc2)

MANDATORY FIRST STEP:
Read the authoritative user request at:
d:\elctercity\.agents\ORIGINAL_REQUEST.md (§ 2026-09-06T07:57:38Z)

INPUTS TO READ:
- `d:\elctercity\.agents\orchestrator_migration\PROJECT.md`
- `d:\elctercity\MIGRATION\MASTER_PLAN.md`
- `d:\elctercity\MIGRATION\EXECUTION_LOG.md` (check Gate 2.1 and Gate 2.2 specifications)
- Existing schemas: `backend/prisma/schema.prisma` and `backend/scripts/*.sql`

YOUR TASK:
Design the complete local database setup for `smartpower_db`:
1. Database initialization script (`CREATE DATABASE smartpower_db;`).
2. Complete DDL schema script creating all 11 tables with proper PostgreSQL data types (UUID, NUMERIC(12,2), TIMESTAMPTZ, TEXT, BOOLEAN):
   - `users`, `customers`, `meter_readings`, `invoices`, `payments`, `billing_cycles`, `plans`, `settings`, `audit_logs`, `whatsapp_queue_messages`, `whatsapp_sessions`.
3. Table constraints:
   - Primary keys (UUID or BIGSERIAL).
   - Foreign keys with `ON DELETE RESTRICT` or `CASCADE`.
   - `CHECK (amount >= 0)`, `CHECK (paid_amount >= 0)`, `CHECK (consumption >= 0)`.
   - UUID idempotency keys on payments and reading submissions.
   - Indices on `(customer_id, status)`, `(cycle_id)`, `(due_date)`, and composite invoice numbers.

OUTPUT REQUIREMENTS:
Write your complete technical proposal and SQL DDL script to:
`d:\elctercity\.agents\explorer_m2_db_schema\analysis.md`
Write your self-contained handoff report to:
`d:\elctercity\.agents\explorer_m2_db_schema\handoff.md`
Notify parent via send_message.
</USER_REQUEST>
