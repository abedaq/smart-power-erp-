## 2026-09-03T05:18:59Z
You are Worker 2: Refactoring & Challenger Fix Worker.
Your working directory is d:/elctercity/.agents/worker_fix_numerals_m2.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. An auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Context and Failure Analysis:
Challenger 1 identified 3 edge-case failures in d:/elctercity/frontend/src/types/excelGrid.types.ts:
1. computeRowFinancials evaluates Eastern Arabic digits as NaN, resulting in 0 units and 0 consumptionCost because toEnglishDigits is not called before Number()/parseFloat().
2. formatYemeniPhone strips Eastern Arabic phone digits to empty string "" because .replace(/[^0-9]/g, '') is called before toEnglishDigits.
3. buildWhatsAppText injects "NaN" when interpolating readings formatted with Eastern Arabic digits.

Tasks to execute:
1. In frontend/src/types/excelGrid.types.ts:
   - Import toEnglishDigits from ../utils/formatters (or ensure toEnglishDigits is available).
   - Update computeRowFinancials: Wrap all inputs (prevReading, currReading, lostUnits, unitPrice, serviceFee, arrears, paidAmount) through toEnglishDigits(String(val || '0')) before parsing to float/number.
   - Update formatYemeniPhone: Apply toEnglishDigits(String(phone || '')) BEFORE doing .replace(/[^0-9]/g, '').
   - Update buildWhatsAppText: Ensure all numeric values (prevReading, currReading, units, consumptionCost, serviceFee, arrears, totalDue, paidAmount, remaining) safely use toEnglishDigits / parsed numbers with toLocaleString('en-US').
2. Run the full suite of automated tests:
   - node frontend/src/tests/test_adversarial_numerals_stress.js
   - node frontend/src/tests/test_numerals_scan.js
   - node frontend/src/tests/test_routes_and_tabs.js
   - node frontend/src/tests/test_whatsapp_and_phone.js
   - node frontend/src/tests/test_challenger_layout_2.js
   Ensure 100% of all tests pass with 0 failures.
3. Run full production builds:
   - npm run build in frontend
   - npm run build in backend
   Verify both exit with code 0 and 0 errors.
4. Record your changes in d:/elctercity/.agents/worker_fix_numerals_m2/changes.md and d:/elctercity/.agents/worker_fix_numerals_m2/handoff.md.
5. Send a message to the caller with your summary and handoff path.
