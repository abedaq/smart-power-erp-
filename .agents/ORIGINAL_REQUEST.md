# Original User Request

## Initial Request — 2026-09-02T17:07:57Z

# Teamwork Project Prompt — Interactive Excel Grid View & WhatsApp Auto-Approval Engine

تحديث وتظوير "سجل العمليات المباشرة ومراجعة القراءات" بالكامل ليصبح كشف تفاعلي بنمط Excel مطابق لتصميم الصورة المرفقة، مع التعديل المباشر داخل الخلايا، واحتساب الوحدات المفقودة، والاعتماد التلقائي مع الواتساب.

Working directory: d:/elctercity
Integrity mode: development

## Requirements

### R1. Backend Lost Units & Comprehensive In-Grid Update APIs
- Update `backend/src/controllers/todayReadings.controller.ts` and API routes to support `lost_units`, `service_fee`, `current_reading`, `previous_reading`, `arrears`, and `paid_amount` inline updates.
- Auto-calculate: `Consumption = Current - Previous`, `Lost Units Cost = Lost Units * Unit Price`, `Total Due = Consumption Cost + Fixed Fee + Lost Units Cost + Arrears`, `Remaining = Total Due - Paid`.
- Update approval RPC/controller to mark reading & invoice `APPROVED`, update customer total due balance, and automatically render & queue WhatsApp invoice image upon clicking approval.

### R2. Frontend Excel-Style Interactive Operations Grid UI
- Transform `frontend/src/pages/TodayReadingsReview.tsx` and `AuditLogs.tsx` into a high-performance, RTL Excel-style data grid matching the 18 columns in the uploaded reference image.
- Enable direct in-cell editing for Current Reading, Previous Reading, Lost Units, Arrears, Monthly Fixed Fee, and Paid Amount with real-time recalculation of totals.
- Add per-row "اعتماد وإرسال واتساب" (Approve & Send WhatsApp) button that executes row approval and triggers instant WhatsApp bill delivery with clean status badges.

### R3. Mobile Flutter App Sync Compatibility
- Update Flutter mobile app models (`MeterReadingModel`, `PaymentModel`) and local Hive DB schemas to store and synchronize `lost_units` and recalculated bill totals without data loss.

## Acceptance Criteria

### Interactive Excel Grid Verification
- [ ] Excel-style grid renders all 18 columns in RTL order matching the reference image layout.
- [ ] Editing any cell (Current Reading, Lost Units, Arrears, Paid Amount) instantly auto-calculates Consumption, Total Due, and Remaining Balance.
- [ ] Clicking "اعتماد" (Approve) successfully updates database, sets status to `APPROVED`, updates customer balance, and queues WhatsApp bill dispatch with image.
- [ ] Full build and test suite verification across React Frontend, Node.js Backend, and Flutter Mobile App.

## 2026-09-02T18:43:23Z

# Teamwork Project Prompt — Frontend UI Redesign & Financial Engine Unification

إعادة هيكلة وتوحيد تصميم وشاشات نظام Smart Power ERP على React Web UI واحتكاماً للنموذج المعتمد code_artifact (8).html مع تفعيل التعديل التفاعلي المباشر للخلايا (Auto-Save on Blur)، والتنقل بين الدورات، والحساب المالي الرجعي التلقائي، وتوفير تبويب تقارير شامل وحذف التبويبات الملغاة.

Working directory: d:/elctercity
Integrity mode: development

## Requirements

### R1. UI Unification to `code_artifact (8).html` Design Across All Main Pages
- Redesign `Customers.tsx`, `Invoices.tsx`, `ArrearsReport.tsx`, and all core tables to strictly match the visual style, Tailwind CSS palette, sticky headers, inline cell editing, badges, KPI cards, and CSV export from `code_artifact (8).html`.
- Implement live inline cell editing for Readings, Payments, Arrears, Rates, and Fees with auto-save on blur (`Auto-Save on Blur`), real-time row recalculation (`units`, `consumptionCost`, `totalDue`, `remaining`), and instant footer summation.
- Integrate the official WhatsApp invoice template (`buildWhatsAppText`) and modal preview across all customer and invoice tables with one-click direct sending (`wa.me`).

### R2. Historical Cycle Navigation & Retroactive Financial Recalculation Engine
- Implement a global/page Cycle Selector (`اغسطس - 2026`, `سبتمبر - 2026`, etc.) allowing seamless navigation and full editability of readings and payments in any past cycle.
- Build retroactive financial recalculation logic so that when a past cycle reading or payment is modified, all downstream balances, arrears, and subsequent cycle totals update automatically across the backend and frontend.

### R3. Live Operations Log & Arrears Management Enhancements
- Build the **Live Operations Log (سجل العمليات المباشرة)** page matching `code_artifact (8).html` style, streaming real-time collector inputs with full inline cell editing and live financial recalculation.
- Enhance the **Arrears / Debts (المديونيات)** page with an "Overdue Days" column (`أيام التأخير`) calculated from the last approved reading date, a "Send Warning Notice" button (`زر الإنذار`), and direct inline payment entry.

### R4. Tab Restructuring, Removals, and Comprehensive Reports Hub
- Completely delete and remove the **Approved Edits (التعديلات المعتمدة)** page and **Plans Management / Tariffs (باقات الاشتراك والتعرفة)** components from navigation and routes.
- Create a unified, comprehensive **Reports Hub (تبويب التقارير الشامل)** containing financial summaries, energy consumption analysis, arrears reports, cycle comparisons, collector performance, and audit logs.

## Acceptance Criteria

### UI & Engine Verification
- [ ] All table pages (`Customers`, `Invoices`, `Arrears`, `Live Operations`) strictly adopt `code_artifact (8).html` layout, inline cell editing with auto-save on blur, and KPI cards.
- [ ] Editing any reading or payment in any cycle automatically recalculates system-wide financial balances across subsequent cycles.
- [ ] Obsolete tabs (`ApprovedEdits`, `PlansManagement`) are completely removed from navigation and routes.
- [ ] Comprehensive Reports Hub renders all financial and operational reports cleanly.

## 2026-09-02T20:04:46Z

# Teamwork Project Prompt — Full ERP Refinement & Database/UI Bug Fixes

تطوير وتحديث نظام Smart Power ERP ليشمل توحيد الإدخالات باللغة الإنجليزية بدون أسهم، إنشاء تبويب مديونيات مستقل بنمط code_artifact (8).html، حذف تبويب التعرفة والرسوم، اعتماد نموذج الفاتورة المعتمد من الصورة photo_5769554780358381104_y.jpg، إصلاح خطأ الدالة المالية column "r" does not exist في السيرفر، وتفعيل الاعتماد التلقائي المباشر لمدير النظام.

Working directory: d:/elctercity
Integrity mode: development

## Requirements

### R1. Number Inputs Unification & Browser Spinner Removal
- Enforce standard English numbers (0, 1, 2, 3...) across all input fields, tables, modals, and PDF/WhatsApp outputs.
- Remove browser up/down spinner arrows from all numeric inputs using CSS resets (`-webkit-appearance: none`, `-moz-appearance: textfield`) and numeric input modes.

### R2. Independent Arrears Tab & General Tariff Tab Deletion
- Build an explicit, independent **Arrears / Debts (المديونيات)** page in the main sidebar matching the new `code_artifact (8).html` design, featuring an "Overdue Days" column, "Send Warning Notice" button (`زر الإنذار`), and direct inline payment entry.
- Completely remove and delete the **General Tariff & Fees (التعرفة والرسوم العامة)** tab from the main sidebar, routes, and navigation.

### R3. Adoption of Official Invoice Template (`photo_5769554780358381104_y.jpg`)
- Update `InvoiceModal.tsx`, `InvoicePreviewModal.tsx`, and PDF/print renders to strictly match the official dual-stub invoice layout from `photo_5769554780358381104_y.jpg` (Header logo & station info, customer details grid, red cycle title, Prev/Curr/Diff/Fee/Value/Arrears/Total table, official rules box, and signature lines).

### R4. Fix Backend & PostgreSQL RPC Errors (`column "r" does not exist`)
- Diagnose and fix the PL/pgSQL RPC query bug `column "r" does not exist` in `rpc_submit_meter_reading` and `rpc_approve_meter_reading` in PostgreSQL.
- Ensure all backend error tracebacks are caught and returned to the user in clean, friendly Arabic messages.

### R5. Live Operations Log & Admin Auto-Approval Flow
- Ensure the **Live Operations Log (سجل العمليات المباشرة)** displays collector mobile inputs in real time using the new Excel grid layout.
- Implement immediate **Auto-Approval (`auto_approve: true` / status = `APPROVED`)** for any readings or payments created by an Admin/Manager from the Web ERP without holding them in pending status.

## Acceptance Criteria

### Verification Checklist
- [ ] All number input fields render English numbers cleanly without spinner arrows.
- [ ] Independent "المديونيات" tab is accessible from sidebar with full `code_artifact (8).html` layout.
- [ ] "التعرفة والرسوم العامة" tab is deleted from navigation.
- [ ] Invoice modals and print views strictly match `photo_5769554780358381104_y.jpg`.
- [ ] Submitting readings/payments executes without `column "r" does not exist` errors.
- [ ] Admin reading/payment entries are automatically approved instantly.
- [ ] `npm run build` in `frontend` and `backend` passes with zero errors.

## 2026-09-02T21:46:25Z

# Teamwork Project Prompt — System-Wide English Numerals Conversion & UI Refinements

تطوير وتحديث نظام Smart Power ERP ليشمل تحويل كافة حقول الأرقام إلى حقول نصية نعدام لأسهم رفع وخفض المتصفح، مع المحول التلقائي للأرقام العربية المشرقية إلى الأرقام الإنجليزية (0-9) فورياً، وإبراز تبويب المديونيات المستقل في الشفيرة والقائمة، وحذف تبويب التعرفة العامة، واعتماد نموذج الفاتورة المزدوجة photo_5769554780358381104_y.jpg، وتأكيد اعتماد مدير النظام المباشر.

Working directory: d:/elctercity
Integrity mode: development

## Requirements

### R1. System-Wide English Numerals Conversion & Spinner Removal
- Replace all number spinners (`input[type=number]`) across `ExcelGrid.tsx`, `ReadingModal.tsx`, `PaymentModal.tsx`, `Customers.tsx`, `Invoices.tsx`, `ArrearsReport.tsx`, and `TodayReadingsReview.tsx` with clean input fields (`inputMode="decimal"`) without browser up/down arrow buttons.
- Implement a global sanitizer `toEnglishDigits(val)` on all inputs (`onChange` & `onBlur`) to automatically convert any typed Eastern Arabic numerals (٠, ١, ٢, ٣...) into Western English numerals (0, 1, 2, 3...) across the entire system.

### R2. Explicit Independent Arrears Tab in Main Sidebar
- Expose the independent **المديونيات** (Arrears & Debts) tab directly in `Sidebar.tsx` and `App.tsx` routes with full `code_artifact (8).html` layout, featuring Overdue Days column, Warning Notice button (`زر الإنذار`), and direct inline payments.
- Delete the "التعرفة والرسوم العامة" (General Tariff & Fees) tab completely from `Sidebar.tsx` and system routes.

### R3. Dual-Stub Official Invoice Template (`photo_5769554780358381104_y.jpg`)
- Update `InvoiceModal.tsx`, `InvoicePreviewModal.tsx`, and `CyclePrintView.tsx` to strictly render the official dual-stub invoice format matching `photo_5769554780358381104_y.jpg` (Header logo & station info "محطة الضياء لتوليد الطاقة الكهربائية", phone numbers, account deposit info, customer grid, red cycle header, Prev/Curr/Diff/Fee/Value/Arrears/Total table, official rules box, and signatures).

### R4. Clarify Cell vs Modal Entry & Admin Auto-Approval Flow
- Maintain direct inline cell editing (`Auto-Save on Blur`) for fast data entry alongside icon modal dialogs for full metadata entry.
- Enforce immediate **Auto-Approval (`auto_approve: true` / status = `APPROVED`)** for any readings or payments entered by Manager/Admin from the Web ERP without holding them in pending status.

## Acceptance Criteria

### Verification Checklist
- [ ] Typing Eastern Arabic numerals (٠-٩) in any input field immediately converts to English digits (0-9).
- [ ] No browser spinner arrows appear on any number input fields across the system.
- [ ] Independent "المديونيات" tab is present in the main sidebar and fully accessible.
- [ ] "التعرفة والرسوم العامة" tab is deleted from navigation.
- [ ] Invoice preview modal and print view strictly match `photo_5769554780358381104_y.jpg`.
- [ ] Admin reading and payment entries auto-approve immediately.
- [ ] `npm run build` in `frontend` passes with zero errors.

## 2026-09-02T21:48:34Z

# Teamwork Project Prompt — Fix Numeric Input Fields & System-Wide English Numerals

المهمة: إصلاح مشكلة الإدخال في جميع حقول الأرقام بالنظام كاملاً.

المشكلة: حقول الإدخال تستخدم `type="number"` مما يجعل المتصفح يمنع الكتابة بلكيبورد أو الأرقام العربية المشرقية (٠-٩) ويُجبر المستخدم على استخدام الأسهم فقط.

الحل المطلوب وتطبيقه في كافة الشاشات والمكونات (`ExcelGrid.tsx`, `ReadingModal.tsx`, `PaymentModal.tsx`, `Customers.tsx`, `Invoices.tsx`, `ArrearsReport.tsx`, `TodayReadingsReview.tsx`):
1. تحويل جميع حقول الإدخال الرقمية من `type="number"` إلى `type="text"` مع تحديد `inputMode="decimal"` أو `inputMode="numeric"`.
2. إضافة وتطبيق دالة التحويل الفوري للأرقام العربية إلى إنجليزية `toEnglishDigits(val)` على جميع الإدخالات (`onChange` و `onBlur`):
```typescript
export function toEnglishDigits(str: string | number | null | undefined): string {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/[٠-٩]/g, (d) => (d.charCodeAt(0) - 1632).toString())
    .replace(/[۰-۹]/g, (d) => (d.charCodeAt(0) - 1776).toString());
}
```
مع تنظيف القيمة بتعبير نمطي `.replace(/[^0-9.]/g, '')` لحظر أي أحرف غير رقمية وإتاحة الكتابة المباشرة السلسة من لوحة المفاتيح بلغة إنجليزية 100%.
3. تصفية CSS في `index.css` لإخفاء أسهم رفع وخفض الأرقام كلياً.
4. التأكد الفعلي من ظهور تبويب **المديونيات** في القائمة الجانبية بشكل مستقر وحذف تبويب التعرفة والرسوم العامة.
5. تأكيد مطابقة الفاتورة لصورة `photo_5769554780358381104_y.jpg`.
6. إجراء اختبار التجميع `npm run build` للتأكد من نجاح العملية بنسبة 100%.

Working directory: d:/elctercity
Integrity mode: development

## 2026-09-06T07:57:38Z

Complete end-to-end migration, modernization, and hardening of the SmartPower Electricity Utility ERP system into a 100% offline-first standalone system powered by a compiled Go backend (`server.exe`), local PostgreSQL, embedded React Desktop (with verified A5 double-stub invoicing), `whatsmeow` WhatsApp integration, and complete deprecation of the mobile app, strictly governed by the 3-file migration protocol (`MIGRATION/MASTER_PLAN.md`, `MIGRATION/EXECUTION_LOG.md`, `MIGRATION/FINAL_AUDIT.md`).

Working directory: d:\elctercity
Integrity mode: development

## Requirements

### R1. System Discovery & 3-File Migration Protocol Setup
Inspect the repository comprehensively (business logic, calculations, database schema, and integrations). Create and continuously maintain exactly three files in `MIGRATION/`:
1. `MIGRATION/MASTER_PLAN.md` (System understanding, business logic inventory, target architecture, and phased migration strategy).
2. `MIGRATION/EXECUTION_LOG.md` (Live phase-by-phase working journal with evidence-based phase gates).
3. `MIGRATION/FINAL_AUDIT.md` (Independent post-migration verification with a strict `READY` or `NOT_READY` verdict).

### R2. Local PostgreSQL Database & Financial Integrity Core
Establish and migrate all database entities to local PostgreSQL (`smartpower_db`). Ensure:
- Strict schema constraints (non-monotonic reading guards, non-negative amounts, UUID idempotency).
- Atomic financial logic with pessimistic row-level locking (`FOR UPDATE`) for FIFO waterfall payment allocations and cascade billing cycle recalculations.
- Deterministic composite invoice numbering: `INV-[Cycle]-[SubscriberNumber]`.

### R3. High-Performance Standalone Go Backend (`server.exe`)
Build a modular Go backend replacing the monolithic Node.js backend:
- Web layer using Go Fiber serving the exact JSON REST API contracts at `http://localhost:3000/api`.
- Native PostgreSQL session storage for `whatsmeow` WhatsApp engine (`CGO_ENABLED=0` pure binary).
- Rate-limited WhatsApp background queue worker.
- Headless A5 invoice rendering using `chromedp` (leveraging system Edge/Chrome) preserving 100% Arabic text shaping and English numerals.
- High-speed Excel import/export using `excelize`.
- Embedding React frontend distribution (`frontend/dist`) directly into `server.exe` using `//go:embed`.

### R4. React Desktop UI Polish & Mobile Deprecation
- Bind React Desktop frontend seamlessly to the local Go API.
- Preserve the official A5 double-stub invoice layout (`photo_5769554780358381104_y.jpg`) in `InvoiceModal.tsx`.
- Enforce 100% English numerals (0, 1, 2, 3...) across all screens and inputs.
- Safely delete the obsolete `mobile_app/` directory and standalone APK artifacts based on reference tracing.

### R5. Disaster Recovery, Hardening & Independent Audit
- Implement automated local daily database dumps and external USB backup mirroring.
- Run complete regression, concurrency, and financial reconciliation tests.
- Complete the independent final audit in `MIGRATION/FINAL_AUDIT.md`.

## Acceptance Criteria

### Protocol & Documentation
- [ ] Exactly three files exist in `MIGRATION/`: `MASTER_PLAN.md`, `EXECUTION_LOG.md`, `FINAL_AUDIT.md`.
- [ ] Every migration phase in `EXECUTION_LOG.md` has concrete command outputs, logs, and a verified `PASS` gate before proceeding.
- [ ] `FINAL_AUDIT.md` concludes with an explicit decision of `READY` or `NOT_READY`.

### Compilation & Packaging
- [ ] Go backend compiles cleanly with `CGO_ENABLED=0` into a single standalone `server.exe` (< 25MB).
- [ ] Frontend builds cleanly (`npm run build`) and is embedded directly inside `server.exe`.
- [ ] Double-clicking `server.exe` boots the system in < 0.1s and opens `http://localhost:3000` with 0 external server dependencies.

### Financial Logic & Invoicing
- [ ] Reading submissions, payments, and recalculations match historical database records with 0 rounding errors.
- [ ] Negative or non-monotonic meter readings are strictly rejected by database constraints.
- [ ] Printed A5 invoices render perfectly with Arabic ligatures, double-stub layout, and 100% English digits.

### WhatsApp & Background Services
- [ ] `whatsmeow` operates natively with PostgreSQL session storage without Cgo.
- [ ] WhatsApp messages are queued locally and dispatched with a safe rate-limiter (8-15s delay) when internet is active.
- [ ] Automated backup creates verified daily database dumps to local and USB paths.

### Cleanup & Performance
- [ ] `mobile_app/` and obsolete files are completely removed.
- [ ] System RAM consumption remains under 35MB for the backend during normal operation.

## 2026-09-07T14:25:29Z

Build, bundle, and rigorously verify the standalone, zero-dependency offline installer SmartPowerERP_Setup.exe for SmartPower Utility ERP.

Working directory: d:/elctercity
Integrity mode: development

## Requirements

### R1. Standalone Package Assembly & Compilation
- Compile Go monolith backend SmartPower.exe embedding the React 19 SPA from frontend/dist.
- Integrate embedded portable PostgreSQL 18 engine listening on isolated loopback port 127.0.0.1:15432.
- Bundle database initialization schema init_schema.sql containing 494 customers, clean August 2 cycle readings, invoices, and payments.
- Package everything using Inno Setup into SmartPowerERP_Setup.exe installing into %LOCALAPPDATA%\Programs\SmartPowerERP with desktop shortcut and non-admin privilege execution.

### R2. Automated Self-Healing & Database Lifecycle Validation
- Verify db_lifecycle.go handles first-time init (initdb), schema seeding, and writes the idempotency flag .db_initialized.
- Verify stale PID lock detection and automated recovery when orphaned postmaster.pid exists.
- Verify graceful shutdown (pg_ctl stop -m fast) upon process exit.

### R3. Strict Data Integrity & Anti-Duplication Enforcement
- Enforce unique index uq_customers_subscriber_number_clean on REGEXP_REPLACE(subscriber_number, '^0+', '').
- Verify CreateCustomer, UpdateCustomer, and UpdateGridCell prevent any duplicate subscriber numbers.

## Acceptance Criteria

### Installer Deliverable
- [ ] SmartPowerERP_Setup.exe exists in d:/elctercity with size ~37.5 MB and is executable.
- [ ] Installer extracts all necessary binaries (SmartPower.exe, pgsql/bin/*, pgsql/share/*, schema/init_schema.sql) to target directory without requiring Admin/UAC elevation.

### Runtime Execution & Verification
- [ ] Running the application initializes database on port 15432, imports initial August 2 schema, and starts Web UI on port 3000.
- [ ] Subsequent restarts skip database re-initialization and preserve all new records.
- [ ] Browser automatically launches to http://localhost:3000.

## 2026-09-09T11:01:16Z

مراقبة شاملة واختبار صمود الواجهات وسجلات التدقيق وقواعد البيانات لنظام SmartPower Utility ERP تحت ضغط العمليات المتزامنة والمكثفة.

Working directory: d:/elctercity
Integrity mode: development

## Requirements

### R1. مراقبة صمود واستجابة الواجهات الأمامية (Frontend UI Resilience & Live Interaction)
مراقبة وفحص أداء واجهات المستخدم (لوحة التحكم، شبكة المشتركين Grid، نماذج الفوترة والتحصيل) أثناء تدفق العمليات المتزامنة، والتأكد من خلو واجهات المتصفح من أي تجميد (UI Freezing) أو أخطاء مع الحفاظ على التحديث اللحظي للبيانات.

### R2. مراقبة ومطابقة سلامة قواعد البيانات (Database & Transaction Integrity)
التحقق من سلامة القيود البرمجية في PostgreSQL، انعدام تكرار أرقام المشتركين والسندات، وصحة حركة الفواتير والتحصيلات والأرصدة الدائنة (Customer Credits) والمتأخرات في جدول المعاملات.

### R3. تدقيق وتوثيق سجلات الرقابة (Audit Logs & Operation Forensics)
مراقبة تسجيل الحركات في جدول `audit_logs` والتحقق من توثيق كل عملية إنشاء، تعديل، قراءة، وسداد دون أي تسريب أو فقدان للبيانات.

## Acceptance Criteria

### استقرار الواجهات الأمامية (UI Stability)
- [ ] استجابة فورية لكافة شاشات النظام دون أخطاء في الـ Console أو انهيار في طبقة العرض.
- [ ] تحديث حي لشبكة المشتركين (Grid) بعد أي تعديل فوري في الخلايا.

### اتساق وتكامل قاعدة البيانات (Database Consistency)
- [ ] مطابقة تامة 100% بين إجمالي المبالغ المفوترة، المحصلة، والأرصدة الدائنة مع مؤشرات لوحة التحكم.
- [ ] توثيق جميع العمليات في جدول `audit_logs` مع تحديد هوية المستخدم ونوع الإجراء والتوقيت.
