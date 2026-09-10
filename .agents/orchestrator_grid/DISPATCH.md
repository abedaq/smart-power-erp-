## 2026-09-02T16:37:33Z
You are the Project Orchestrator for the Smart Power ERP Interactive Excel Grid View & WhatsApp Auto-Approval Engine project.

Your working directory is: `d:/elctercity/.agents/orchestrator_grid`

Read the authoritative user request in `d:/elctercity/.agents/ORIGINAL_REQUEST.md` (specifically the latest section timestamped `2026-09-02T16:31:02Z`).

Key Requirements to orchestrate:
1. Backend Lost Units & Comprehensive In-Grid Update APIs:
   - Update `backend/src/controllers/todayReadings.controller.ts` and API routes to support `lost_units`, `service_fee`, `current_reading`, `previous_reading`, `arrears`, and `paid_amount` inline updates.
   - Auto-calculate: `Consumption = Current - Previous`, `Lost Units Cost = Lost Units * Unit Price`, `Total Due = Consumption Cost + Fixed Fee + Lost Units Cost + Arrears`, `Remaining = Total Due - Paid`.
   - Update approval RPC/controller to mark reading & invoice `APPROVED`, update customer total due balance, and automatically render & queue WhatsApp invoice image upon clicking approval.
2. Frontend Excel-Style Interactive Operations Grid UI:
   - Transform `frontend/src/pages/TodayReadingsReview.tsx` and `AuditLogs.tsx` into a high-performance, RTL Excel-style data grid matching the 18 columns in the reference image `d:/elctercity/photo_5769554780358381104_y.jpg` and table requirements.
   - Enable direct in-cell editing for Current Reading, Previous Reading, Lost Units, Arrears, Monthly Fixed Fee, and Paid Amount with real-time recalculation of totals.
   - Add per-row "اعتماد وإرسال واتساب" (Approve & Send WhatsApp) button that executes row approval and triggers instant WhatsApp bill delivery with clean status badges.
3. Mobile Flutter App Sync Compatibility:
   - Update Flutter mobile app models (`MeterReadingModel`, `PaymentModel`) and local Hive DB schemas to store and synchronize `lost_units` and recalculated bill totals without data loss.

Rules and Constraints:
- Database name: `u721293045_office_service`.
- All numbers displayed in UI must use English numerals (0, 1, 2, 3...) strictly.
- Interface is Arabic RTL.
- Maintain `progress.md` and `BRIEFING.md` in your working directory.
- Dispatch specialists (explorers, workers, reviewers, testers) under `.agents/` subdirectories.
- When all criteria are met and tested, write `handoff.md` and send your completion report to parent.
