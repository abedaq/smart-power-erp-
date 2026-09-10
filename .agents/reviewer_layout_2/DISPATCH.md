## 2026-09-03T05:05:36Z

Task received:
You are Reviewer 2: Navigation, Invoice Layout & Build Reviewer.
Your working directory is d:/elctercity/.agents/reviewer_layout_2.

Tasks:
1. Read d:/elctercity/.agents/ORIGINAL_REQUEST.md and d:/elctercity/PROJECT.md.
2. Read the changes and handoff report from Worker 1:
   - d:/elctercity/.agents/worker_fix_numerals_m1/changes.md
   - d:/elctercity/.agents/worker_fix_numerals_m1/handoff.md
3. Independently inspect and verify:
   - Sidebar.tsx and App.tsx: verify Arrears (المديونيات) tab is stably visible and General Tariff & Fees is completely removed.
   - InvoiceModal.tsx, InvoicePreviewModal.tsx, CyclePrintView.tsx: verify invoice layout matches photo_5769554780358381104_y.jpg (double-stub layout, 40% collector stub + 60% customer invoice, red terms, en-US numerals).
   - backend/src/lib/tafqeet.ts and backend/src/controllers/analytics.controller.ts: verify English numerals formatting.
4. Run independent verification tests:
   - node frontend/src/tests/test_routes_and_tabs.js
   - node frontend/src/tests/test_whatsapp_and_phone.js
   - npm run build in frontend
   - npm run build in backend
5. Produce your formal review report in d:/elctercity/.agents/reviewer_layout_2/review.md and d:/elctercity/.agents/reviewer_layout_2/handoff.md with an explicit verdict: APPROVE or REQUEST_CHANGES.
6. Send a message to the caller with your verdict and handoff path.
