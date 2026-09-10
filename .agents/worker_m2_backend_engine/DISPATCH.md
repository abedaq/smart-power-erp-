## 2026-09-02T18:54:00Z
You are Worker 2 for Milestone 2 (M2): Cycle Navigation & Retroactive Financial Engine.
Your working directory is: d:/elctercity/.agents/worker_m2_backend_engine (create this directory if needed, write progress.md and handoff.md inside it).
Read ORIGINAL_REQUEST.md at: d:/elctercity/.agents/ORIGINAL_REQUEST.md
Read PROJECT.md at: d:/elctercity/PROJECT.md
Read Survey findings at: d:/elctercity/.agents/explorer_survey_backend/handoff.md

Your exclusive write ownership:
- `backend/prisma/schema.prisma`
- `backend/src/services/recalculation.service.ts`
- `backend/src/controllers/todayReadings.controller.ts`
- `backend/src/routes/todayReadings.routes.ts`
- `frontend/src/components/common/PeriodSelector.tsx`

Scope & Requirements:
1. Schema & Models: Ensure `lost_units` is properly supported in backend invoice/reading handling (default 0).
2. Implement Retroactive Cascade Recalculation Engine in `backend/src/services/recalculation.service.ts`:
   - When a reading, lost units, fee, arrears, or payment is edited in cycle $T$ for customer $C$:
     - Recalculate cycle $T$: consumption = max(0, curr - prev), consumptionCost = (units + lost_units)*unitPrice, totalDue = consumptionCost + fee + arrears, remaining = totalDue - paid.
     - Cascade downstream across cycles $T+1, T+2, \dots, N$:
       - Update $R_{prev}^{(k)} = R_{curr}^{(k-1)}$.
       - Update consumption and consumption value for cycle $k$.
       - Update arrears $A_{arrears}^{(k)} = R_{remaining}^{(k-1)}$.
       - Recalculate totalDue and remaining for cycle $k$.
       - Update customer's cumulative total balance to match the final cycle remaining amount.
     - Execute inside an atomic transaction with row locking.
3. Update `backend/src/controllers/todayReadings.controller.ts` and `routes`:
   - Support `PUT /api/readings/:id/cell-update` for inline cell updates triggering the recalculation engine.
   - Support `GET /api/readings/cycles` to list available cycles with aggregated financial stats.
   - Support `GET /api/readings/cycle-data` to return 18-column grid rows for selected cycle.
   - Support `POST /api/readings/:id/approve-and-whatsapp` to approve and queue WhatsApp message.
4. Implement `frontend/src/components/common/PeriodSelector.tsx` for easy, stylish cycle switching across all pages.
5. Verify backend build (`npm run build` in `backend` if applicable) and test the endpoints.

Key Constraint:
English numerals ONLY (0, 1, 2, 3...) across all API responses, numbers, and dates.
