# Execution Plan: System-wide English Numerals & Input Fields Refactoring

## Objectives
1. Survey all numeric input fields, digit utility functions, CSS styles, navigation components, and invoice print/preview layouts.
2. Ensure unified `toEnglishDigits` utility and helper functions for sanitizing numeric inputs (allowing digits and at most one decimal point).
3. Convert all `type="number"` inputs to `type="text"` with `inputMode="decimal"` / `inputMode="numeric"`, binding `onChange` and `onBlur` cleanly without breaking typing flow.
4. Hide browser number spinners/arrows completely in `index.css`.
5. Ensure Arrears (المديونيات) tab is stably visible in sidebar, and General Tariff & Fees (التعرفة والرسوم العامة) is removed.
6. Verify invoice layout adherence to `photo_5769554780358381104_y.jpg`.
7. Full build verification for frontend and backend (`npm run build`).
8. Adversarial validation and forensic audit.

## Phases
- **Phase 0: Survey & Codebase Mapping (3 Explorers)**
  - Explorer 1: Frontend inputs inventory (`ExcelGrid.tsx`, `ReadingModal.tsx`, `PaymentModal.tsx`, `Customers.tsx`, `Invoices.tsx`, `ArrearsReport.tsx`, `TodayReadingsReview.tsx`, etc.) and CSS.
  - Explorer 2: Navigation sidebar, Arrears tab visibility, General Tariff removal, and invoice layout analysis.
  - Explorer 3: Utility functions (`toEnglishDigits`, formatters), backend interactions, and build config.
- **Phase 1: Implementation (Worker)**
  - Implement changes across core utilities, CSS, components, navigation, and invoice layouts.
- **Phase 2: Review (2 Reviewers in parallel)**
  - Reviewer 1: Input handling, numeric conversions, CSS spinners, and type safety.
  - Reviewer 2: Navigation items, invoice layout match, and UI/UX responsiveness.
- **Phase 3: Adversarial Challenge (2 Challengers in parallel)**
  - Challenger 1: Edge-case stress testing on inputs (Arabic numerals, multiple dots, negative values, copy-paste, rapid typing).
  - Challenger 2: Navigation state & Invoice layout visual and structural verification.
- **Phase 4: Forensic Audit (Auditor)**
  - Teamwork Forensic Auditor for genuine implementation and integrity checks.
- **Phase 5: Gate & Final Verification**
