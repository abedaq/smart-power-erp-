## 2026-09-02T18:54:00Z

# Assignment: Worker 1 - Milestone 1 (M1) UI Unification & In-Grid Live Editing

## Exclusive Write Ownership
- `frontend/src/types/excelGrid.types.ts`
- `frontend/src/components/common/ExcelGrid.tsx`
- `frontend/src/components/common/InvoiceModal.tsx`
- `frontend/src/pages/Customers.tsx`
- `frontend/src/pages/Invoices.tsx`

## Scope & Requirements
1. Implement `frontend/src/types/excelGrid.types.ts` with `GridRowData`, `ComputedGridRow`, `GridFooterTotals`, and pure functions `computeRowFinancials`, `computeGridTotals`.
2. Implement reusable `frontend/src/components/common/ExcelGrid.tsx` and `frontend/src/components/common/InvoiceModal.tsx` matching `code_artifact (8).html` design:
   - Sticky header (`sticky top-0 bg-slate-100 font-bold border-b-2`) and sticky footer (`sticky bottom-0 bg-slate-200 font-bold border-t-2`).
   - Tailwind color palette: Emerald for approved/totals, Rose for Arrears (`bg-rose-50/70 border-x-2 border-rose-300 text-rose-700`), Amber for consumption, Blue for current reading & payments, Slate for background.
   - Inline editable cells with Auto-Save on Blur / Enter (`onBlur`, `onChange` optimistic updates).
   - Real-time row recalculation (units = max(0, curr - prev), consumptionCost = (units + lostUnits)*unitPrice, totalDue = consumptionCost + serviceFee + arrears, remaining = totalDue - paid).
   - Real-time footer & 5 KPI cards aggregation (Subscribers, Energy Units, Arrears, Total Due, Remaining Balance).
   - UTF-8 BOM CSV export (`exportToCSV`).
   - Official WhatsApp message generator (`buildWhatsAppText`) and modal preview with Clipboard Copy and direct `wa.me/967...` URL.
3. Refactor `frontend/src/pages/Customers.tsx` and `frontend/src/pages/Invoices.tsx` to utilize the unified Excel grid, KPI cards, and WhatsApp modal.
4. Verify TypeScript compilation by running `npm run build` in `frontend` and ensuring zero errors.

## Key Constraint
English numerals ONLY (0, 1, 2, 3...) across all UI labels, inputs, outputs, and formatters.
