## 2026-09-02T22:23:46Z
You are Worker 1 (Replacement): Core Implementation & Refactoring Worker.
Your working directory is d:/elctercity/.agents/worker_fix_numerals_m1.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. An auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Context and Inputs:
1. Read d:/elctercity/.agents/ORIGINAL_REQUEST.md and d:/elctercity/PROJECT.md.
2. Read Explorer findings from:
   - d:/elctercity/.agents/explorer_inputs_survey/handoff.md
   - d:/elctercity/.agents/explorer_layout_survey/handoff.md
   - d:/elctercity/.agents/explorer_utils_survey/handoff.md

Tasks to execute:
1. In frontend/src/utils/formatters.ts:
   - Ensure sanitizeDecimalInput handles Arabic decimal separators (٫ \u066B and standard commas ,) by converting them to dot (.) before cleaning, and strictly ensures a single decimal point without breaking intermediate typing.
2. In frontend/src/components/common/ExcelGrid.tsx and frontend/src/pages/TodayReadingsReview.tsx:
   - Verify that typing intermediate decimal values (e.g. "12." or "0.") in grid inputs does not get swallowed prematurely during onChange.
3. In backend/src/lib/tafqeet.ts and backend/src/controllers/analytics.controller.ts:
   - Ensure all numeric formats use 'en-US' or English digits.
4. Verify all screens and components (ReadingModal.tsx, PaymentModal.tsx, Customers.tsx, Invoices.tsx, ArrearsReport.tsx, TodayReadingsReview.tsx, ExcelGrid.tsx, etc.) use text inputs with inputMode="decimal" or "numeric" and apply toEnglishDigits sanitization.
5. Verify CSS rules in index.css hide number spinners across webkit and firefox.
6. Verify Arrears tab in Sidebar.tsx and ensure General Tariff is absent.
7. Run the verification test scripts:
   - node frontend/src/tests/test_numerals_scan.js
   - node frontend/src/tests/test_routes_and_tabs.js
   - node frontend/src/tests/test_whatsapp_and_phone.js
8. Run full builds:
   - npm run build in frontend
   - npm run build in backend
   Verify both exit with code 0 and 0 errors.
9. Write your changes and handoff report to d:/elctercity/.agents/worker_fix_numerals_m1/changes.md and d:/elctercity/.agents/worker_fix_numerals_m1/handoff.md.
10. Send a message to the caller with your summary and handoff path.
