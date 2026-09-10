## 2026-09-03T00:54:40Z
<USER_REQUEST>
You are the Worker responsible for Milestone 1: Full Numerals & UI Overhaul.
Your working directory is: d:/elctercity/.agents/worker_implementation/
Authoritative user request: d:/elctercity/.agents/ORIGINAL_REQUEST.md
Project plan: d:/elctercity/.agents/orchestrator_fix_numerals/PROJECT.md

Explorer Reports:
- Explorer 1 (Inputs & Numerals): d:/elctercity/.agents/explorer_survey_inputs/analysis.md
- Explorer 2 (CSS & Sidebar): d:/elctercity/.agents/explorer_survey_css_sidebar/analysis.md
- Explorer 3 (Invoices & Build): d:/elctercity/.agents/explorer_survey_invoices_build/analysis.md

Tasks to implement:
1. `frontend/src/utils/formatters.ts`:
   - Implement and export `toEnglishDigits(val: string | number | null | undefined): string` converting all Arabic-Indic (`٠-٩`) and Persian (`۰-۹`) numerals to ASCII (`0-9`).
   - Implement and export `sanitizeDecimalInput(val: string | number | null | undefined): string`: converts to English digits, removes any characters that are not `0-9` or `.`, and ensures at most one decimal dot exists.
   - Implement and export `sanitizeIntegerInput(val: string | number | null | undefined): string`: converts to English digits, removes any non-digit characters (`0-9` only).

2. `frontend/src/utils/phoneValidation.ts`:
   - Enforce `toEnglishDigits` in phone validation and cleaning functions.

3. Numeric input fields overhaul across all screens and components:
   - Convert all `<input type="number"` to `<input type="text" inputMode="decimal"` (or `inputMode="numeric"` for integer-only fields) and integrate `sanitizeDecimalInput` / `toEnglishDigits` on `onChange` and `onBlur`.
   - Files to update:
     - `frontend/src/components/common/ExcelGrid.tsx` (all grid input cells + batch header inputs)
     - `frontend/src/pages/TodayReadingsReview.tsx` (all review grid input cells)
     - `frontend/src/components/ReadingModal.tsx`
     - `frontend/src/components/PaymentModal.tsx`
     - `frontend/src/components/ArrearsThresholdModal.tsx`
     - `frontend/src/pages/Customers.tsx` (initial reading fields + phone/meter numbers)
     - `frontend/src/pages/Dashboard.tsx`
     - `frontend/src/pages/UnreadMeters.tsx`
     - `frontend/src/pages/WhatsApp.tsx` (phone numbers)
     - Any other relevant screens.

4. `frontend/src/index.css`:
   - Enhance the number spinner suppression CSS rules for WebKit, Gecko, and MS with `display: none !important; opacity: 0 !important; pointer-events: none !important; -webkit-appearance: none !important; -moz-appearance: textfield !important; appearance: textfield !important;` and utility class `.no-spinners`.

5. `frontend/src/components/Sidebar.tsx` & `frontend/src/App.tsx`:
   - Ensure the Arrears tab (`/arrears`) is accessible for `ADMIN`, `ACCOUNTANT`, and `CASHIER` so it is visibly and stably available to all cashiers/accountants.
   - Verify that "General Tariff & Fees" (التعرفة والرسوم العامة) remains completely removed.

6. Invoice layout verification:
   - Confirm official invoice components (`InvoiceModal.tsx`, `CyclePrintView.tsx`, etc.) and backend templates (`invoice.ejs`) maintain dual-stub layout and `en-US` English numerals.

7. Build & Test Verification:
   - Run `npm run build` in `frontend` (`cd frontend && npm run build`).
   - Run `npm run build` in `backend` (`cd backend && npm run build`).
   - Create and run an automated test script (e.g. `node frontend/src/tests/test_numerals_scan.js` or unit test) verifying `toEnglishDigits`, `sanitizeDecimalInput`, and scanning for any leftover uncontrolled `type="number"`.
   - Ensure 100% build pass with exit code 0 and 0 errors.
