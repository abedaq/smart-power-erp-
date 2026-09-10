# DISPATCH

## 2026-09-02T21:47:12Z
You are the Project Orchestrator for the Smart Power ERP system update.
Your working directory is: d:/elctercity/.agents/orchestrator_numerals_ui
The authoritative user request is recorded in: d:/elctercity/.agents/ORIGINAL_REQUEST.md (see the latest entry from 2026-09-02T21:46:25Z).

## Objective & Requirements
Execute the full cycle of requirements:
1. R1: System-Wide English Numerals Conversion & Spinner Removal:
   - Replace all number spinners (input[type=number]) across ExcelGrid.tsx, ReadingModal.tsx, PaymentModal.tsx, Customers.tsx, Invoices.tsx, ArrearsReport.tsx, and TodayReadingsReview.tsx with clean input fields (inputMode="decimal") without browser up/down arrow buttons.
   - Implement a global sanitizer toEnglishDigits(val) on all inputs (onChange & onBlur) to automatically convert any typed Eastern Arabic numerals (٠, ١, ٢, ٣...) into Western English numerals (0, 1, 2, 3...) across the entire system.
2. R2: Explicit Independent Arrears Tab in Main Sidebar:
   - Expose the independent المديونيات (Arrears & Debts) tab directly in Sidebar.tsx and App.tsx routes with full code_artifact (8).html layout, featuring Overdue Days column, Warning Notice button (زر الإنذار), and direct inline payments.
   - Delete the "التعرفة والرسوم العامة" (General Tariff & Fees) tab completely from Sidebar.tsx and system routes.
3. R3: Dual-Stub Official Invoice Template (photo_5769554780358381104_y.jpg):
   - Update InvoiceModal.tsx, InvoicePreviewModal.tsx, and CyclePrintView.tsx to strictly render the official dual-stub invoice format matching photo_5769554780358381104_y.jpg (Header logo & station info "محطة الضياء لتوليد الطاقة الكهربائية", phone numbers, account deposit info, customer grid, red cycle header, Prev/Curr/Diff/Fee/Value/Arrears/Total table, official rules box, and signatures).
4. R4: Clarify Cell vs Modal Entry & Admin Auto-Approval Flow:
   - Maintain direct inline cell editing (Auto-Save on Blur) for fast data entry alongside icon modal dialogs for full metadata entry.
   - Enforce immediate Auto-Approval (auto_approve: true / status = APPROVED) for any readings or payments entered by Manager/Admin from the Web ERP without holding them in pending status.
