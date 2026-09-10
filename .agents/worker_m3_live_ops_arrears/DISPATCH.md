## 2026-09-02T19:07:54Z
<USER_REQUEST>
You are Worker 4 for Milestone 3 (M3): Live Operations Log & Arrears Enhancements.
Your working directory is: d:/elctercity/.agents/worker_m3_live_ops_arrears (create this directory if needed, write progress.md and handoff.md inside it).
Read ORIGINAL_REQUEST.md at: d:/elctercity/.agents/ORIGINAL_REQUEST.md
Read PROJECT.md at: d:/elctercity/PROJECT.md
Read Survey handoffs and previous milestone handoffs (`worker_m1_ui_grid/handoff.md` and `worker_m2_backend_engine/handoff.md`).

Your exclusive write ownership:
- `frontend/src/pages/TodayReadingsReview.tsx`
- `frontend/src/pages/ArrearsReport.tsx`

Scope & Requirements:
1. Live Operations Log (`frontend/src/pages/TodayReadingsReview.tsx`):
   - Refactor completely to be the central **Live Operations Log (سجل العمليات المباشرة ومراجعة القراءات)** matching `code_artifact (8).html` design.
   - Integrate `PeriodSelector.tsx` for seamless historical cycle switching.
   - Render the 18-column RTL Excel Grid with sticky headers and footers.
   - Support inline cell editing (current reading, previous reading, lost units, rate, service fee, arrears, paid amount) with Auto-Save on Blur (`PUT /api/readings/:id/cell-update`) and instant client recalculation.
   - Add row action "اعتماد وإرسال واتساب" (`POST /api/readings/:id/approve-and-whatsapp`) and preview modal via `InvoiceModal.tsx`.
   - Top 5 KPI cards + UTF-8 BOM CSV export (`exportGridToCSV`).
2. Enhanced Arrears & Debts Management (`frontend/src/pages/ArrearsReport.tsx`):
   - Redesign matching `code_artifact (8).html` Tailwind palette and KPI cards.
   - Include **Overdue Days column (`أيام التأخير`)** calculated from the last approved reading date.
   - Include **"Send Warning Notice" action button (`زر الإنذار`)** that formats an official debt reminder and opens WhatsApp / modal.
   - Include **Direct inline payment entry** for instant debt collection and settlement.
   - Top KPI cards (Total Debtors, Total Arrears, Critical >60 Days Debt, Settled Today, Total Due) and CSV export.
3. Verification:
   - Run `npm run build` in `frontend` and ensure zero TypeScript errors.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Key Constraint:
English numerals ONLY (0, 1, 2, 3...) across all UI labels, inputs, outputs, and formatters.

When finished, write handoff.md with verification details, and send a message to parent.
</USER_REQUEST>
