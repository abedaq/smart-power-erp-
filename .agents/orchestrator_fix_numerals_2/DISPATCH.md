## 2026-09-03T01:08:26+03:00

You are the Project Orchestrator.
Your working directory is d:/elctercity/.agents/orchestrator_fix_numerals_2.
The authoritative user request is recorded in d:/elctercity/.agents/ORIGINAL_REQUEST.md.

Mission:
Fix numeric input fields & enforce system-wide English numerals across all ERP components:
1. Convert all numeric input fields from `type="number"` to `type="text"` with `inputMode="decimal"` or `inputMode="numeric"` across all screens and components (`ExcelGrid.tsx`, `ReadingModal.tsx`, `PaymentModal.tsx`, `Customers.tsx`, `Invoices.tsx`, `ArrearsReport.tsx`, `TodayReadingsReview.tsx`, etc.).
2. Implement and apply `toEnglishDigits(val)` with regex cleanup `.replace(/[^0-9.]/g, '')` on all inputs (`onChange` and `onBlur`) to allow smooth keyboard typing and 100% English digits.
3. Filter CSS in `index.css` to completely hide browser number spinners/arrows.
4. Ensure stable visibility of the Arrears (المديونيات) tab in the sidebar and ensure General Tariff & Fees (التعرفة والرسوم العامة) is completely removed.
5. Verify invoice layout matches `photo_5769554780358381104_y.jpg`.
6. Run `npm run build` in frontend and backend to verify 100% build success.

Maintain your plan.md, progress.md, and BRIEFING.md in your working directory. Dispatch specialists (workers, reviewers, challengers) to carry out implementation and adversarial verification. Report back when finished.
