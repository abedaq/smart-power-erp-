# Project: System-Wide English Numerals & UI Overhaul

## Architecture
- **Frontend**: React + TypeScript + Vite + Tailwind CSS (`frontend/`)
- **Backend**: Node.js + Express + TypeScript (`backend/`)
- **Formatters & Utilities**: `frontend/src/utils/formatters.ts`, `frontend/src/utils/phoneValidation.ts`
- **Shared Components & Grids**: `frontend/src/components/common/ExcelGrid.tsx`, `ReadingModal.tsx`, `PaymentModal.tsx`, `ArrearsThresholdModal.tsx`
- **Pages**: `Customers.tsx`, `TodayReadingsReview.tsx`, `Dashboard.tsx`, `UnreadMeters.tsx`, `Invoices.tsx`, `ArrearsReport.tsx`, `WhatsApp.tsx`
- **Styling**: `frontend/src/index.css`
- **Navigation**: `frontend/src/components/Sidebar.tsx`, `frontend/src/App.tsx`
- **Invoice Templates**: `frontend/src/components/common/InvoiceModal.tsx`, `backend/src/templates/invoice.ejs`

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | English Digits Utilities | Add `toEnglishDigits`, `sanitizeDecimalInput`, `sanitizeIntegerInput` in `formatters.ts` | M1 | Survey (Explorer 1) |
| 2 | Phone Validation Sanitation | Enforce `toEnglishDigits` in `phoneValidation.ts` and WhatsApp inputs | M1 | Survey (Explorer 1) |
| 3 | ExcelGrid Numeric Conversion | Convert all grid cells and batch inputs from `type="number"` to `type="text" inputMode="decimal"` with `sanitizeDecimalInput` | M1 | Survey (Explorer 1) |
| 4 | Modals & Pages Numeric Conversion | Convert `ReadingModal`, `PaymentModal`, `Customers`, `TodayReadingsReview`, `Dashboard`, `UnreadMeters`, `ArrearsThresholdModal` to `type="text" inputMode="decimal"` | M1 | Survey (Explorer 1) |
| 5 | Cross-Browser CSS Spinner Suppression | Add comprehensive WebKit/Gecko/MS rules in `index.css` to hide number spinners | M1 | Survey (Explorer 2) |
| 6 | Sidebar & Navigation Polish | Stabilize `/arrears` visibility for ADMIN/ACCOUNTANT/CASHIER and ensure General Tariff is purged | M1 | Survey (Explorer 2) |
| 7 | Invoice Layout & Numerals Verification | Validate official invoice dual-stub layout and `en-US` numerals vs reference photo | M1 | Survey (Explorer 3) |
| 8 | Frontend & Backend Build Check | Run `npm run build` in `frontend` and `backend` with 0 errors | M1 | Survey (Explorer 3) |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Full Numerals & UI Overhaul | Implement utilities, convert all numeric inputs, update CSS spinner rules, polish sidebar roles, verify invoice formatting, and execute builds | none | IN_PROGRESS |

## Code Layout
- `frontend/src/utils/formatters.ts` — Number converters & regex sanitizers
- `frontend/src/utils/phoneValidation.ts` — Phone validator using English numerals
- `frontend/src/components/common/ExcelGrid.tsx` — Excel grid cells & batch header inputs
- `frontend/src/components/ReadingModal.tsx` — Meter reading modal input
- `frontend/src/components/PaymentModal.tsx` — Payment collection modal input
- `frontend/src/components/ArrearsThresholdModal.tsx` — Arrears threshold input
- `frontend/src/pages/Customers.tsx` — Customer creation & edit forms
- `frontend/src/pages/TodayReadingsReview.tsx` — Today readings review table inputs
- `frontend/src/pages/Dashboard.tsx` — Quick edit input
- `frontend/src/pages/UnreadMeters.tsx` — Unread meters reading input
- `frontend/src/pages/WhatsApp.tsx` — WhatsApp phone inputs
- `frontend/src/index.css` — Global CSS spinner suppressors & typography rules
- `frontend/src/components/Sidebar.tsx` — Sidebar navigation role matching
- `frontend/src/App.tsx` — Protected routes role permissions

## Interface Contracts
### `formatters.ts` ↔ Components
- `toEnglishDigits(val: string | number | null | undefined): string`: Converts any Arabic-Indic / Persian digits (`٠-٩`, `۰-۹`) to ASCII English digits (`0-9`).
- `sanitizeDecimalInput(val: string | number | null | undefined): string`: Converts to English digits, strips non-numeric characters except one dot (`.`), prevents multiple dots.
- `sanitizeIntegerInput(val: string | number | null | undefined): string`: Converts to English digits and strips non-numeric characters (`0-9` only).
