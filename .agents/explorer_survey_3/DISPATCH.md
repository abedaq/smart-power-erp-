# Dispatch for explorer_survey_3

## Objective
Survey data integrity, anti-duplication enforcement, and runtime execution:
1. Locate customer entity, constraints, and migrations:
   - Check unique index `uq_customers_subscriber_number_clean` on `REGEXP_REPLACE(subscriber_number, '^0+', '')`.
   - Check `CreateCustomer`, `UpdateCustomer`, and `UpdateGridCell` handlers/services in the Go backend.
   - Verify how they prevent duplicate subscriber numbers (both exact match and leading-zero normalized matches).
2. Survey runtime behavior:
   - Auto-launching browser to `http://localhost:3000`.
   - Subsequent restarts skipping database re-initialization and preserving all records.
   - Any existing test suites, runners, or verification scripts.

## Inputs
- `d:/elctercity/.agents/ORIGINAL_REQUEST.md` (section `## 2026-09-07T14:25:29Z`)
- Project root: `d:/elctercity`

## Output
Write report to `d:/elctercity/.agents/explorer_survey_3/handoff.md`.

## 2026-09-07T14:28:50Z
You are explorer_survey_3.
Your working directory is d:/elctercity/.agents/explorer_survey_3.
Read your task assignment in d:/elctercity/.agents/explorer_survey_3/DISPATCH.md.
MANDATORY: Read d:/elctercity/.agents/ORIGINAL_REQUEST.md before starting work.
Do NOT write or modify application code or run build commands. You are a read-only explorer.
Investigate:
1. Locate customer entity, constraints, and migrations:
   - Check unique index `uq_customers_subscriber_number_clean` on `REGEXP_REPLACE(subscriber_number, '^0+', '')`.
   - Check `CreateCustomer`, `UpdateCustomer`, and `UpdateGridCell` handlers/services in the Go backend.
   - Verify how they prevent duplicate subscriber numbers (both exact match and leading-zero normalized matches).
2. Survey runtime behavior:
   - Auto-launching browser to `http://localhost:3000`.
   - Subsequent restarts skipping database re-initialization and preserving all records.
   - Any existing test suites, runners, or verification scripts.

Produce a comprehensive, structured report with exact file paths, line numbers, and findings, and save it to d:/elctercity/.agents/explorer_survey_3/handoff.md. Update progress.md in your directory periodically. When done, send a completion message back.

## 2026-09-07T14:41:35Z
From: parent (84698da9-7fdd-447b-9ddf-2971e3ed92b4)
**Context**: Survey Phase - Data Integrity & Runtime Verification
**Content**: Checking in on your survey investigation progress.
**Action**: Please report your current status, findings so far, and ETA for handoff.md.


