# Handoff Report — Explorer 2 (Invoice Template Survey)

## 1. Observation
- **Reference Image**: `photo_5769554780358381104_y.jpg` exists in the project root. Inspection confirmed it is a dual-stub electricity consumption invoice with:
  - Left Section (Main Customer Bill, ~60% width): Logo on top-left, station header (`محطة الضياء لتوليد الطاقة الكهربائية`, phones `783270260_736955883`, bank deposit text), customer info grid, red cycle title, 7-column table (`ق. السابقة`, `ق. الحالية`, `الفارق`, `اشتراك`, `القيمة`, `متأخرات`, `الاجمالي`), 5 red policy bullet points, `المحصل` and `الحسابات` signatures, and print date at bottom-left (`التاريخ: 2026/07/17`).
  - Right Section (Collector Counterfoil / Stub, ~40% width): Logo on top-left, station header, customer info, red cycle title, 5-column table (`ق. السابقة`, `ق. الحالية`, `الفارق`, `متأخرات وغرامات`, `الاجمالي`), `المحصل` and `الحسابات` signatures.
- **Frontend Components Examined**:
  - `frontend/src/components/InvoicePreviewModal.tsx` (lines 101–315): Implements the dual-stub layout, but in RTL grid `col-span-7` placed on the right side instead of left.
  - `frontend/src/components/CyclePrintView.tsx` (lines 178–395): Implements dual-stub for individual cycle print mode with same stub placement.
  - `frontend/src/components/common/InvoiceModal.tsx` (lines 56–233): Renders a single-card key-value modal, creating an inconsistency with the official dual-stub format.
  - `frontend/src/types/excelGrid.types.ts` (lines 117–152): Contains `buildWhatsAppText()` helper for official text template with English digits.
  - `frontend/src/utils/printUtils.ts`: Provides `printElementViaIframe()` using A4 landscape CSS.
- **Backend Components Examined**:
  - `backend/src/templates/invoice.ejs` (lines 38–414): Generates HTML for Puppeteer screenshot. In RTL flexbox, the main bill was positioned right and stub left. Date at bottom line 412 produced Arabic Eastern digits in rendered image `live_db_invoice_rendered.png`.
  - `backend/src/services/invoice-renderer.service.ts`: Puppeteer screenshot capture of `#receipt-container`.
  - `backend/src/services/whatsapp-notifier.service.ts`: Automatic queueing of approved invoices & receipts for WhatsApp delivery.
  - `backend/src/controllers/whatsapp.controller.ts`: API handler for `/whatsapp/send-invoice`.

## 2. Logic Chain
1. Requirement R3 in `ORIGINAL_REQUEST.md` demands strict adoption of the official invoice template from `photo_5769554780358381104_y.jpg` across `InvoiceModal.tsx`, `InvoicePreviewModal.tsx`, PDF/print renders, and WhatsApp outputs.
2. In `photo_5769554780358381104_y.jpg`, the sheet layout is visually: Left = Main Invoice (7 columns + 5 policy bullet points + date), Right = Collector Stub (5 columns).
3. In RTL flex/grid implementations, the first child naturally floats to the right. Therefore, having `main-bill` as the first child in RTL flipped the visual layout relative to the reference image. Reversing child order or using explicit flex/grid column ordering (`order-2` / `order-1`) resolves this.
4. The project rules strictly enforce English numerals (0-9). `backend/src/templates/invoice.ejs` must format all dates and amounts using explicit Latin numeral locales (`en-US` / `en-GB`).
5. To eliminate UI inconsistencies, `InvoiceModal.tsx` and `InvoicePreviewModal.tsx` in the frontend should share a unified dual-stub presentation.

## 3. Caveats
- No source code modifications were executed during this investigation phase (read-only compliance).
- The exact logo SVG/PNG in `frontend/public/station_logo.png` is used as the station emblem; dynamic logo replacement via settings is supported.
- Printer paper size assumed to be standard A4 Landscape for dual-stub layout, or thermal 80mm for single-receipt vouchers.

## 4. Conclusion
The codebase is fully equipped with the necessary Puppeteer and React infrastructure, but requires 4 targeted alignment fixes:
1. Re-ordering left and right stubs in `invoice.ejs`, `InvoicePreviewModal.tsx`, and `CyclePrintView.tsx` so the main bill is on the Left and the collector stub on the Right matching `photo_5769554780358381104_y.jpg`.
2. Fixing numeral formatting in `invoice.ejs` to enforce English numbers.
3. Unifying `InvoiceModal.tsx` in `ExcelGrid.tsx` with the official dual-stub layout.
4. Preserving the WhatsApp text builder (`buildWhatsAppText`) in `excelGrid.types.ts` with English digits and formatted summary.

## 5. Verification Method
- **Visual Inspection**: Compare screenshots of `live_db_invoice_rendered.png` and web preview modals against `photo_5769554780358381104_y.jpg`.
- **Build Verification**: Run `npm run build` in `d:/elctercity/frontend` and `d:/elctercity/backend`.
- **Print Inspection**: Trigger `printElementViaIframe` from `Invoices.tsx` to verify A4 landscape dual-stub pagination.
- **WhatsApp Output**: Run test send or inspect message queue payload for base64 PNG attachment and formatted text caption.
