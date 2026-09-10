## 2026-09-02T20:29:40Z
<USER_REQUEST>
You are Worker M3 (Official Invoice Template Adoption Implementation).
Your working directory is: d:/elctercity/.agents/worker_m3
Project root: d:/elctercity
Original Request: Read d:/elctercity/.agents/ORIGINAL_REQUEST.md (specifically the latest section timestamped 2026-09-02T20:04:46Z).
Project Specification: Read d:/elctercity/PROJECT.md and d:/elctercity/.agents/explorer_survey_invoice/analysis.md.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Your assigned scope (Milestone M3):
1. Strict alignment with official invoice template in `photo_5769554780358381104_y.jpg`:
   - Visual Layout: Left side = Main Customer Bill (~60% width / 7 columns + 5 policy points + signatures + bottom-left date), Right side = Collector Stub (~40% width / 5 columns + signatures).
   - In `d:/elctercity/backend/src/templates/invoice.ejs`: Ensure the HTML/CSS places the Main Bill on the Left and Collector Stub on the Right, with all numbers and dates formatted with English numerals 0-9.
   - In `d:/elctercity/frontend/src/components/InvoicePreviewModal.tsx` & `d:/elctercity/frontend/src/components/CyclePrintView.tsx`: Ensure the dual-stub layout visually displays Main Bill on the Left and Stub on the Right matching the official photo.
   - In `d:/elctercity/frontend/src/components/common/InvoiceModal.tsx`: Unify to use the official dual-stub presentation matching `InvoicePreviewModal`.
2. WhatsApp Template:
   - Ensure `buildWhatsAppText` in `d:/elctercity/frontend/src/types/excelGrid.types.ts` formats the WhatsApp text cleanly with English digits (0-9) and clear itemization.
3. Run `npm run build` in both `d:/elctercity/frontend` and `d:/elctercity/backend` to verify 0 errors.
4. Run template rendering test / screenshot generation test to verify the rendered invoice matches `photo_5769554780358381104_y.jpg`.

Write a complete report of all changes and verification outputs to `d:/elctercity/.agents/worker_m3/handoff.md`.
Send a message back to parent when done.
</USER_REQUEST>
