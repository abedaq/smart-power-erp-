# Dispatch for worker_m2

## Milestone: M2 — Standalone Package Assembly & Inno Setup

## Objective
Assemble the complete offline distribution in `dist_portable/`, update Inno Setup script for `%LOCALAPPDATA%` non-admin installation, and compile `SmartPowerERP_Setup.exe` (~37.5 MB).

## Context & Inputs
Read:
- `d:/elctercity/PROJECT.md`
- `d:/elctercity/.agents/ORIGINAL_REQUEST.md` (section `## 2026-09-07T14:25:29Z`)
- `d:/elctercity/.agents/explorer_survey_1/handoff.md` (Packaging analysis)
- `d:/elctercity/.agents/worker_m1/handoff.md` (M1 deliverables & clean schema)

## Mandatory Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Write Ownership & Scope
You exclusively own and may edit/generate:
1. `server/internal/ui/dist/` (syncing latest `frontend/dist/` assets if needed)
2. `dist_portable/SmartPowerERP.exe` & `dist_portable/SmartPower.exe`
3. `SmartPower_Installer.iss`
4. `SmartPowerERP_Setup.exe`

## Concrete Tasks
1. **Frontend Dist Synchronization & Go Monolith Compilation**:
   - Verify `server/internal/ui/dist` contains the complete, up-to-date production build from `frontend/dist`.
   - Compile the Go monolith backend from `server/cmd/server`:
     `go build -ldflags="-s -w" -o d:\elctercity\dist_portable\SmartPowerERP.exe ./cmd/server`
     Also place `SmartPower.exe` as alias or ensure both names are available if needed.
   - Verify the compiled executable runs and contains embedded UI and M1 lifecycle hooks.
2. **Update Inno Setup Script (`SmartPower_Installer.iss`)**:
   - Configure installer metadata:
     - `AppName=SmartPower Utility ERP`
     - `AppVersion=2.0.0`
     - `DefaultDirName={localappdata}\Programs\SmartPowerERP` (or `{autopf}\SmartPowerERP` with `PrivilegesRequired=lowest`)
     - `PrivilegesRequired=lowest` (ensures non-admin execution without UAC elevation prompt)
     - `OutputBaseFilename=SmartPowerERP_Setup`
     - `OutputDir=d:\elctercity`
     - `Compression=lzma2/ultra64`
     - `SolidCompression=yes`
   - Files mapping:
     - Package everything in `d:\elctercity\dist_portable\*` into `{app}` recursively.
   - Icons & Shortcuts:
     - Desktop icon: `{autodesktop}\SmartPower ERP` pointing to `{app}\SmartPowerERP.exe`
     - Start Menu icon: `{autoprograms}\SmartPower ERP`
   - Run section:
     - Launch `{app}\SmartPowerERP.exe` after installation finishes.
3. **Compile Installer**:
   - Compile using Inno Setup compiler:
     `& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" d:\elctercity\SmartPower_Installer.iss`
   - Verify `d:\elctercity\SmartPowerERP_Setup.exe` is created.
   - Check file size: expected size is approximately 37.5 MB (e.g. ~37.5 MB under LZMA2 ultra64).
4. **Verification**:
   - Verify `SmartPowerERP_Setup.exe` exists, length is ~37.5 MB, and executable headers are valid.
   - Document exact sizes, compiler logs, and hashes.

## Output
Write full report with command logs and file metadata to `d:/elctercity/.agents/worker_m2/handoff.md`.
