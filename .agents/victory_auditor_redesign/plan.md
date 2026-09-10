# Victory Audit Plan — Frontend UI Redesign & Financial Engine Unification

## Phase A: Timeline & Provenance Audit
1. Inspect git log / file timestamps across `frontend/src` and `backend/src`.
2. Check for anomalous pre-populated artifacts or unnatural commits/files.
3. Validate progression through M1 -> M2 -> M3 -> M4 -> M5.

## Phase B: Forensic Integrity & Deep Code Inspection
1. **Mock / Dummy / Facade check**:
   - Grep for `mock`, `dummy`, `TODO`, `fake`, hardcoded returns, empty handlers across `frontend/src` and `backend/src`.
2. **R1 Verification (UI Unification to `code_artifact (8).html`)**:
   - Inspect `code_artifact (8).html` layout and components.
   - Inspect `Customers.tsx`, `Invoices.tsx`, `ArrearsReport.tsx`, `ExcelGrid.tsx`.
   - Verify sticky headers, sticky footer totals, inline cell editing with Auto-Save on Blur, KPI cards, UTF-8 CSV export, WhatsApp invoice modal preview & direct sending (`wa.me` / `buildWhatsAppText`).
3. **R2 Verification (Historical Cycle Navigation & Retroactive Recalculation)**:
   - Inspect `PeriodSelector.tsx` or cycle selection mechanism.
   - Inspect `backend/src/services/recalculation.service.ts` and `backend/src/controllers/todayReadings.controller.ts` or routes.
   - Verify downstream cascade: updating past cycle reading/payment re-evaluates all subsequent cycles $T+1 \dots N$, updates invoice balances, arrears, customer balance, with database transactions and locking.
4. **R3 Verification (Live Operations Log & Arrears Enhancements)**:
   - Inspect `TodayReadingsReview.tsx`: check 18 columns matching `code_artifact (8).html`, real-time inline editing, auto-calculations, approval & WhatsApp queuing.
   - Inspect `ArrearsReport.tsx`: Overdue days calculation, warning notice generator / button, inline payment entry / modal.
5. **R4 Verification (Obsolete Tab Removal & Comprehensive Reports Hub)**:
   - Check `App.tsx` and `Sidebar.tsx` to verify `ApprovedEdits` and `PlansManagement` are completely removed from routes and navigation.
   - Inspect `ReportsHub.tsx`: verify 6 analytical tabs (Financial summary, Energy/Losses, Arrears aging, Cycle comparison, Collector performance, Audit logs) with real data feeds.
6. **English Numerals Verification**:
   - Check for any Arabic-Indic numerals (`[\u0660-\u0669]`) in source code and formatters.

## Phase C: Independent Test & Build Execution
1. Execute `npm run build` in `frontend`.
2. Execute `npm run build` in `backend`.
3. Execute backend tests / validation scripts (e.g. `test_recalculation_engine.js`, `test_rbac_routes.js`, etc.).
4. Verify execution results directly and confirm zero compilation/runtime errors.

## Phase D: Final Synthesis & Verdict
- Compile complete evidence and deliver structured VICTORY AUDIT REPORT with final verdict: VICTORY CONFIRMED or VICTORY REJECTED.
