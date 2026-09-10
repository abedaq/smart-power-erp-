# Explorer Engine & UI R0 Dispatch
Assigned to survey Rejection/Void engine, financial billing, PDF/WhatsApp, and React UI for R4 & R5.

## 2026-09-02T05:30:00Z
Survey and analyze the Rejection/Void Engine, Financial Billing Engine, PDF/WhatsApp notifications, and React UI state management in d:/elctercity regarding Requirements R4 and R5:
1. Reading rejection workflow: Locate Reject Reading logic, transition to REJECTED, automatic voiding of associated invoice (VOID), and reading rollback mechanism (meter calculations reverting to previous approved reading).
2. React Query cache invalidation: Locate React Query mutations/hooks on the web frontend for reading approval and rejection, and check cache invalidation keys (invalidateQueries).
3. Consumption calculation equation: Verify Consumption = Current Reading - Last Approved Reading across backend/RPC and UI.
4. Invoice total calculation equation: Verify Total = Consumption Amount + Fixed Fees + Previous Outstanding Arrears.
5. PDF invoice generation and automated WhatsApp billing notifications dispatch: Locate PDF template/generation service and WhatsApp messaging service / webhook dispatch logic.
