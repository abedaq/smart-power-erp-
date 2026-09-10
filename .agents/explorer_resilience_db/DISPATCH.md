# DISPATCH: Database & Transaction Integrity Survey

## 2026-09-09T11:03:38Z
- **Working Directory**: `d:/elctercity/.agents/explorer_resilience_db/`
- **Project Root**: `d:/elctercity`
- **Original Request**: `d:/elctercity/.agents/ORIGINAL_REQUEST.md`
- **Mission**:
  Investigate the Database and Transaction Integrity architecture:
  1. PostgreSQL schema definition (`schema/init_schema.sql`, `database/`, etc.).
  2. Constraints in PostgreSQL: unique indexes (e.g. `uq_customers_subscriber_number_clean`), check constraints, non-monotonic reading guards, non-negative amounts, foreign keys.
  3. Anti-duplication logic in Go backend (`server/internal/services/customer_service.go`, payment vouchers, etc.).
  4. Transaction handling and concurrency control: pessimism vs optimism (`FOR UPDATE`), isolation levels, atomic financial recalculations.
  5. Financial balance reconciliation: Invoices total, collections, customer credits (`customer_credits`), arrears, and how they match the Dashboard KPI counters.
  6. Existing database test scripts (`test_financial_suite.py`, `test_subscriber_anti_duplication.py`).
  7. Output your findings into `report.md` and `handoff.md` in your working directory.

