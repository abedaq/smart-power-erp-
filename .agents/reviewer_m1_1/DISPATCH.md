# Dispatch for reviewer_m1_1

## 2026-09-07T15:04:00Z
You are reviewer_m1_1.
Your working directory is d:/elctercity/.agents/reviewer_m1_1.
Read your task assignment in d:/elctercity/.agents/reviewer_m1_1/DISPATCH.md.
MANDATORY: Read d:/elctercity/.agents/ORIGINAL_REQUEST.md before starting work.
Objectively and adversarially review backend code changes made by worker_m1 in `server/cmd/server/main.go` and `server/internal/services/customer_service.go`.
Run `go test ./...` in `server/` to verify tests pass.
Write your review report and verdict (APPROVE or REQUEST_CHANGES) in `d:/elctercity/.agents/reviewer_m1_1/handoff.md` and send a completion message.

## Milestone M1 Review: Backend Code Review
Read:
- `d:/elctercity/.agents/ORIGINAL_REQUEST.md` (section `## 2026-09-07T14:25:29Z`)
- `d:/elctercity/PROJECT.md`
- `d:/elctercity/.agents/worker_m1/handoff.md`
- Code files: `server/cmd/server/main.go`, `server/internal/services/customer_service.go`

Review tasks:
1. Verify `DBLifecycleManager` integration in `server/cmd/server/main.go`:
   - Is `EnsureDatabaseReady()` called before `database.InitDB`?
   - Is `cfg.DatabaseURL` properly overridden with the returned local port 15432 URL?
   - Are `os.Interrupt` and `syscall.SIGTERM` captured to gracefully call `dbManager.Stop()`?
2. Verify `customer_service.go`:
   - Does `NormalizeSubscriberNumber` correctly strip leading zeros (`^0+`)?
   - Are `CreateCustomer`, `UpdateCustomer`, `UpdateGridCell`, and `GetNextSubscriberNumber` properly guarded?
3. Run `go test ./...` in `server/` and verify unit tests pass.

Provide verdict (`APPROVE` or `REQUEST_CHANGES`) in `d:/elctercity/.agents/reviewer_m1_1/handoff.md`.
