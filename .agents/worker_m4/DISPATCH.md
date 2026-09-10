## 2026-09-02T20:17:34Z

You are Worker M4 (Backend RPC & Arabic Errors Implementation).
Your working directory is: d:/elctercity/.agents/worker_m4
Project root: d:/elctercity
Original Request: Read d:/elctercity/.agents/ORIGINAL_REQUEST.md (specifically the latest section timestamped 2026-09-02T20:04:46Z).
Project Specification: Read d:/elctercity/PROJECT.md and d:/elctercity/.agents/explorer_survey_backend/analysis.md.

Your assigned scope (Milestone M4):
1. Fix the PL/pgSQL function `rpc_submit_meter_reading` and `rpc_approve_meter_reading` to eliminate the `column "r" does not exist` error:
   - In SQL files / scripts (`backend/src/scripts/clean_and_unify_rpc.ts`, `backend/src/scripts/apply_bimonthly_cycle_rpc.ts`, etc.) fix `SELECT row_to_json(m) INTO v_existing_json FROM public.meter_readings m WHERE m.client_mutation_id = p_idempotency_key;`.
   - Apply the updated SQL directly to the PostgreSQL database so the live database function is fixed.
2. Ensure clean Arabic error messages in `backend/src/services/financial-rpc.service.ts` and Express central error handler in `backend/src/index.ts` so raw database internal errors are formatted into clean Arabic user messages.
3. Sync and ensure all reading routes from `backend/src/routes/todayReadings.routes.ts` are active and accessible via `/api/readings` in `backend/src/routes/reading.routes.ts` and `backend/src/index.ts`.
4. Run `npm run build` in `d:/elctercity/backend` and execute test/verification to confirm 0 compilation errors and successful RPC execution without "column r does not exist" error.
