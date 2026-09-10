## 2026-09-02T08:34:55Z
You are Worker M5 Repair (ESM Runtime & Puppeteer Hardening Specialist).
Your working directory is `d:/elctercity/.agents/worker_repair`.
Read `d:/elctercity/.agents/ORIGINAL_REQUEST.md` under section `## 2026-09-02T08:09:15Z`.
Read `d:/elctercity/.agents/challenger_1/handoff.md` and `d:/elctercity/PROJECT.md`.

You exclusively own these files:
- `backend/src/services/invoice-renderer.service.ts`
- `backend/src/services/receipt-renderer.service.ts`

Tasks:
1. In `backend/src/services/invoice-renderer.service.ts`:
   - Replace top-level static `import puppeteer from 'puppeteer';` with type-only `import type { Browser } from 'puppeteer';`.
   - In `generateInvoiceImage`: load puppeteer dynamically via `const puppeteer = (await import('puppeteer')).default;`.
2. In `backend/src/services/receipt-renderer.service.ts`:
   - Replace top-level static `import puppeteer, { Browser } from 'puppeteer';` with type-only `import type { Browser } from 'puppeteer';`.
   - In `getBrowser`: load puppeteer dynamically via `const puppeteer = (await import('puppeteer')).default;`.
3. Compile backend with `npm run build` in `d:/elctercity/backend` (verify exit code 0).
4. Verify with Electron standalone runtime:
   `[System.Environment]::SetEnvironmentVariable('ELECTRON_RUN_AS_NODE', '1'); & 'd:\elctercity\desktop\electron-bin\electron.exe' -e 'require("./backend/dist/services/invoice-renderer.service.js"); require("./backend/dist/services/receipt-renderer.service.js"); require("./backend/dist/controllers/reading.controller.js"); console.log("ELECTRON_NODE_PUPPETEER_SURVIVED_CLEAN_BOOT");'`
5. Recompile Inno Setup installer:
   `& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" "d:\elctercity\SmartPower_Installer.iss"`
6. Sync output to `dist_output/` and update checksums.
7. Strictly use English numerals (0, 1, 2, 3...).
8. Write your handoff report to `d:/elctercity/.agents/worker_repair/handoff.md` and send completion message back.
