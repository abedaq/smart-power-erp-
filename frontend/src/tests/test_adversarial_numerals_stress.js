/**
 * Adversarial Input & Numeral Stress Test Harness
 * 
 * Challenger 1: Input & Numeral Stress Challenger
 * Tests extreme input strings, keystroke sequences across onChange/onBlur,
 * and financial calculation engines in ExcelGrid and TodayReadingsReview.
 */

import {
  toEnglishDigits,
  normalizeNumerals,
  sanitizeDecimalInput,
  sanitizeIntegerInput,
  formatDate,
  formatDateOnly,
  formatMonth,
  formatNumber,
  formatCurrency,
} from '../utils/formatters.ts';

import {
  computeRowFinancials,
  computeGridTotals,
  formatYemeniPhone,
  buildWhatsAppText,
} from '../types/excelGrid.types.ts';

let totalTests = 0;
let passedTests = 0;
let failedTests = 0;
const findings = [];

function assert(condition, testName, details = '') {
  totalTests++;
  if (condition) {
    passedTests++;
    console.log(`  ✓ PASS: ${testName}`);
  } else {
    failedTests++;
    console.error(`  ✗ FAIL: ${testName}`);
    if (details) console.error(`    Details: ${details}`);
    findings.push({ testName, details });
  }
}

console.log('======================================================================');
console.log('CHALLENGER 1: ADVERSARIAL INPUT, NUMERAL & FINANCIAL STRESS HARNESS');
console.log('======================================================================');

// ======================================================================
// SECTION 1: Extreme Input Strings to Sanitizers & Formatters
// ======================================================================
console.log('\n[1] Stress Testing Extreme Input Strings & Encodings...');

// 1.1 Arabic-Indic Numerals (٠-٩)
assert(toEnglishDigits('٠١٢٣٤٥٦٧٨٩') === '0123456789', 'Converts all 10 Eastern Arabic digits (٠-٩)');
assert(sanitizeDecimalInput('١٢٣٤.٥٦') === '1234.56', 'sanitizeDecimalInput: Arabic digits with ASCII dot');
assert(sanitizeIntegerInput('٠١٢٣٤٥٦٧٨٩') === '0123456789', 'sanitizeIntegerInput: Arabic digits integer');

// 1.2 Persian / Eastern Arabic Extended Numerals (۰-۹)
assert(toEnglishDigits('۰۱۲۳۴۵۶۷۸۹') === '0123456789', 'Converts all 10 Persian digits (۰-۹)');
assert(toEnglishDigits('۴۵۶') === '456', 'Persian 4, 5, 6 conversion');
assert(toEnglishDigits('1٠2۳4') === '10234', 'Mixed Western, Eastern Arabic, and Persian digits');

// 1.3 Arabic Decimal Point (٫ / \u066B)
assert(sanitizeDecimalInput('١٢٫٣٤') === '12.34', 'Converts Arabic decimal separator ٫ (\\u066B) to ASCII dot');
assert(sanitizeDecimalInput('٫٥') === '.5', 'Converts leading Arabic decimal separator ٫٥ to .5');
assert(sanitizeDecimalInput('٩٩٫') === '99.', 'Converts trailing Arabic decimal separator ٩٩٫ to 99.');

// 1.4 Arabic Comma (، / \u060C)
assert(sanitizeDecimalInput('١٢،٣٤') === '12.34', 'Converts Arabic comma ، (\\u060C) to ASCII dot');
assert(sanitizeDecimalInput('،٥') === '.5', 'Converts leading Arabic comma ،٥ to .5');

// 1.5 Arabic Thousand Separator (٬ / \u066C)
assert(sanitizeDecimalInput('١٬٠٠٠') === '1.000', 'Converts Arabic thousands separator ٬ (\\u066C) to dot in decimal sanitizer');

// 1.6 Standard ASCII Comma (,)
assert(sanitizeDecimalInput('12,34') === '12.34', 'Converts European/Arabic comma 12,34 to 12.34');
assert(sanitizeDecimalInput(',5') === '.5', 'Converts leading comma ,5 to .5');

// 1.7 Letters & Alphabetic Characters
assert(sanitizeDecimalInput('abc123xyz') === '123', 'Strips Latin alphabetic characters');
assert(sanitizeDecimalInput('قراءة١٢٥٠واط') === '1250', 'Strips Arabic alphabetic characters');
assert(sanitizeDecimalInput('abcdef') === '', 'Pure alphabetic string returns empty');
assert(sanitizeIntegerInput('sub-12345-A') === '12345', 'sanitizeIntegerInput strips letters and dashes');

// 1.8 Symbols, Punctuation & Unicode Controls
assert(sanitizeDecimalInput('@#$%^&*()_+={}[]|\\:;"\'<>?/~') === '', 'Strips all special ASCII symbols');
assert(sanitizeDecimalInput('⚡1250.50💡') === '1250.50', 'Strips Emoji and retains decimal digits');
assert(sanitizeDecimalInput('\u200F1250\u200E') === '1250', 'Strips Right-to-Left / Left-to-Right marks (\\u200F, \\u200E)');
assert(sanitizeDecimalInput('\u200B1250\u200C') === '1250', 'Strips Zero-Width Space & Zero-Width Non-Joiner');
assert(sanitizeDecimalInput('\t 1250.25 \n') === '1250.25', 'Strips tabs, spaces, and newlines');

// 1.9 Negative Signs
assert(sanitizeDecimalInput('-100') === '100', 'Strips leading negative sign (enforces unsigned magnitude in decimal inputs)');
assert(sanitizeDecimalInput('-0.5') === '0.5', 'Strips negative sign on fractional input');
assert(sanitizeDecimalInput('--100--') === '100', 'Strips multiple negative signs');

// 1.10 Multiple Dots & Redundant Decimal Separators
assert(sanitizeDecimalInput('12.3.4.5') === '12.345', 'Collapses multiple dots into single decimal point (12.3.4.5 -> 12.345)');
assert(sanitizeDecimalInput('12..34') === '12.34', 'Handles double dots without creating extra decimals');
assert(sanitizeDecimalInput('..........') === '.', 'Multiple bare dots collapse into single dot');
assert(sanitizeDecimalInput('.1.2.3.') === '.123', 'Leading, interior, and trailing dots collapsed safely');

// 1.11 Leading Dots
assert(sanitizeDecimalInput('.5') === '.5', 'Preserves leading dot for typing .5');
assert(sanitizeDecimalInput('.00') === '.00', 'Preserves leading dot for typing .00');
assert(sanitizeDecimalInput('.٠٥') === '.05', 'Leading dot with Eastern Arabic digits');
assert(sanitizeDecimalInput('.') === '.', 'Preserves bare single dot');

// 1.12 Trailing Dots
assert(sanitizeDecimalInput('12.') === '12.', 'Preserves trailing dot for in-flight typing ("12.")');
assert(sanitizeDecimalInput('0.') === '0.', 'Preserves zero with trailing dot ("0.")');
assert(sanitizeDecimalInput('٩٩.') === '99.', 'Preserves converted digits with trailing dot');

// 1.13 Zero Values & Edge Case Representables
assert(sanitizeDecimalInput('0') === '0', 'Sanitizes single zero');
assert(sanitizeDecimalInput('0.00') === '0.00', 'Sanitizes 0.00');
assert(sanitizeDecimalInput('٠') === '0', 'Sanitizes Eastern zero ٠');
assert(sanitizeDecimalInput('٠.٠٠') === '0.00', 'Sanitizes Eastern ٠.٠٠');
assert(sanitizeDecimalInput('000123') === '000123', 'Preserves raw digits string for user typing');

// 1.14 Null, Undefined, Empty, Whitespace
assert(sanitizeDecimalInput(null) === '', 'sanitizeDecimalInput handles null gracefully');
assert(sanitizeDecimalInput(undefined) === '', 'sanitizeDecimalInput handles undefined gracefully');
assert(sanitizeDecimalInput('') === '', 'sanitizeDecimalInput handles empty string');
assert(sanitizeDecimalInput('   ') === '', 'sanitizeDecimalInput handles whitespace string');
assert(sanitizeIntegerInput(null) === '', 'sanitizeIntegerInput handles null');
assert(sanitizeIntegerInput(undefined) === '', 'sanitizeIntegerInput handles undefined');
assert(sanitizeIntegerInput('') === '', 'sanitizeIntegerInput handles empty string');

// ======================================================================
// SECTION 2: Simulating Keystroke Sequences Across onChange and onBlur
// ======================================================================
console.log('\n[2] Simulating Keystroke Sequences (onChange -> intermediate states -> onBlur)...');

// Helper to simulate a user typing a sequence of characters into an ExcelGrid / TodayReadingsReview cell
function simulateTypingSession(initialValue, keystrokes, simulateBlur = true) {
  let currentValue = initialValue;
  const intermediateValues = [];
  const intermediateFinancials = [];

  const baseRow = {
    id: 1,
    subNumber: '1001',
    route: 'R-01',
    name: 'مشترك تجريبي',
    address: 'صنعاء',
    meterNumber: 'M-555',
    phone: '771234567',
    prevReading: 1000,
    currReading: 1000,
    lostUnits: 0,
    unitPrice: 1400,
    serviceFee: 1000,
    arrears: 0,
    paidAmount: 0,
  };

  // 1. Keystroke by keystroke onChange
  for (const char of keystrokes) {
    if (char === '<BACKSPACE>') {
      currentValue = currentValue.slice(0, -1);
    } else {
      currentValue = currentValue + char;
    }

    // Mirror onChange:
    const clean = sanitizeDecimalInput(currentValue);
    currentValue = clean;
    intermediateValues.push(clean);

    // Compute live financials during typing
    const liveRow = computeRowFinancials({
      ...baseRow,
      currReading: clean,
    });
    intermediateFinancials.push(liveRow);
  }

  // 2. onBlur:
  let finalSavedValue = currentValue;
  if (simulateBlur) {
    const clean = sanitizeDecimalInput(currentValue);
    finalSavedValue = clean === '' || isNaN(Number(clean)) ? 0 : Number(clean);
  }

  const finalComputedRow = computeRowFinancials({
    ...baseRow,
    currReading: finalSavedValue,
  });

  return {
    intermediateValues,
    intermediateFinancials,
    finalSavedValue,
    finalComputedRow,
  };
}

// 2.1 Typing "1250.75" character by character
const session1 = simulateTypingSession('', ['1', '2', '5', '0', '.', '7', '5']);
assert(session1.intermediateValues.includes('1250.'), 'Session 1: Trailing dot "1250." preserved during typing without swallowing');
assert(session1.finalSavedValue === 1250.75, 'Session 1: onBlur saved 1250.75 as valid numeric float');
assert(session1.finalComputedRow.units === 250.75, 'Session 1: Final units computed as 250.75 (1250.75 - 1000)');
assert(!session1.intermediateFinancials.some(f => isNaN(f.totalDue)), 'Session 1: Zero NaN throughout intermediate typing states');

// 2.2 Typing Eastern Arabic digits "١٢٥٠٫٥"
const session2 = simulateTypingSession('', ['١', '٢', '٥', '٠', '٫', '٥']);
assert(session2.intermediateValues[0] === '1', 'Session 2: First Eastern digit ١ converts to 1 immediately on onChange');
assert(session2.intermediateValues[4] === '1250.', 'Session 2: Arabic decimal ٫ converts to ASCII dot "." immediately');
assert(session2.finalSavedValue === 1250.5, 'Session 2: onBlur saves 1250.5 cleanly');
assert(session2.finalComputedRow.units === 250.5, 'Session 2: Units computed as 250.5');

// 2.3 User typing bare dot "." and blurring without numbers
const session3 = simulateTypingSession('', ['.']);
assert(session3.intermediateValues[0] === '.', 'Session 3: Bare dot "." allowed during intermediate typing');
assert(session3.finalSavedValue === 0, 'Session 3: onBlur converts bare dot to 0 safely (preventing NaN in DB)');
assert(session3.finalComputedRow.units === 0, 'Session 3: Final units safely computed as 0');

// 2.4 User clearing cell completely and blurring
const session4 = simulateTypingSession('1500', ['<BACKSPACE>', '<BACKSPACE>', '<BACKSPACE>', '<BACKSPACE>']);
assert(session4.intermediateValues[3] === '', 'Session 4: Backspace clears input to empty string');
assert(session4.finalSavedValue === 0, 'Session 4: onBlur converts empty string to 0 safely');
assert(session4.finalComputedRow.units === 0, 'Session 4: Units computed as 0 without crash');

// 2.5 User typing multiple dots e.g. "12.3.4"
const session5 = simulateTypingSession('', ['1', '2', '.', '3', '.', '4']);
assert(session5.finalSavedValue === 12.34, 'Session 5: Multiple dots handled cleanly, saving 12.34');

// 2.6 User entering leading dot ".5"
const session6 = simulateTypingSession('', ['.', '5']);
assert(session6.intermediateValues[0] === '.', 'Session 6: Intermediate dot preserved');
assert(session6.intermediateValues[1] === '.5', 'Session 6: Intermediate .5 preserved');
assert(session6.finalSavedValue === 0.5, 'Session 6: onBlur converts .5 to 0.5');

// 2.7 User pasting string with Arabic thousands separator "١٬٥٠٠"
const pasteArabicSep = sanitizeDecimalInput('١٬٥٠٠');
const blurArabicSep = pasteArabicSep === '' || isNaN(Number(pasteArabicSep)) ? 0 : Number(pasteArabicSep);
assert(blurArabicSep === 1.5, 'Session 7: Arabic thousands separator converts to decimal point (1.5)');

// ======================================================================
// SECTION 3: Financial Engine Calculations (ExcelGrid & TodayReadingsReview)
// ======================================================================
console.log('\n[3] Testing Financial Engine Calculations & Row Computations...');

// 3.1 Standard Complete Row Calculation
const testRow1 = {
  id: 1,
  subNumber: '1001',
  route: 'R-01',
  name: 'صالح محمد',
  address: 'صنعاء - التحرير',
  meterNumber: 'M-101',
  phone: '771234567',
  prevReading: 1200,
  currReading: 1350,
  lostUnits: 10,
  unitPrice: 1400,
  serviceFee: 1000,
  arrears: 12000,
  paidAmount: 200000,
};

const comp1 = computeRowFinancials(testRow1);
assert(comp1.units === 150, 'Row 1 Units: 1350 - 1200 = 150');
assert(comp1.consumptionCost === 210000, 'Row 1 Consumption Cost: 150 * 1400 = 210,000');
assert(comp1.lostUnitsCost === 14000, 'Row 1 Lost Units Cost: 10 * 1400 = 14,000');
assert(comp1.totalDue === 237000, 'Row 1 Total Due: 210000 + 14000 + 1000 + 12000 = 237,000');
assert(comp1.remaining === 37000, 'Row 1 Remaining: 237000 - 200000 = 37,000');

// 3.2 Negative Consumption Protection (curr < prev)
const testRow2 = {
  ...testRow1,
  prevReading: 1500,
  currReading: 1200, // lower than previous
};
const comp2 = computeRowFinancials(testRow2);
assert(comp2.units === 0, 'Row 2: Negative consumption prevented: Math.max(0, 1200 - 1500) = 0');
assert(comp2.consumptionCost === 0, 'Row 2: Consumption cost is 0');
assert(comp2.totalDue === comp2.lostUnitsCost + Number(testRow2.serviceFee) + Number(testRow2.arrears), 'Row 2: Total due does not subtract consumption');

// 3.3 Overpayment Scenario (Paid > Total Due) -> Negative Remaining (Customer Credit)
const testRow3 = {
  ...testRow1,
  paidAmount: 250000, // Total due is 237,000
};
const comp3 = computeRowFinancials(testRow3);
assert(comp3.remaining === -13000, 'Row 3: Overpayment yields negative remaining (credit balance of -13,000)');

// 3.4 Missing / Undefined / String Fields Resilience
const testRow4 = {
  id: 4,
  subNumber: '1004',
  route: '',
  name: 'مشترك بدون بيانات',
  address: '',
  meterNumber: '',
  phone: '',
  prevReading: '',
  currReading: '100',
  lostUnits: undefined,
  unitPrice: '1400',
  serviceFee: null,
  arrears: '',
  paidAmount: undefined,
};
const comp4 = computeRowFinancials(testRow4);
assert(comp4.units === 100, 'Row 4: Empty prevReading treated as 0 (units = 100)');
assert(comp4.lostUnitsCost === 0, 'Row 4: Undefined lostUnits treated as 0');
assert(comp4.serviceFee === null, 'Row 4: Service fee null retained on row');
assert(comp4.consumptionCost === 140000, 'Row 4: String unitPrice parsed correctly');
assert(comp4.totalDue === 140000, 'Row 4: Total due computed cleanly without NaN');
assert(comp4.remaining === 140000, 'Row 4: Remaining computed cleanly without NaN');

// 3.5 Grid Totals Aggregation (computeGridTotals)
const rows = [comp1, comp2, comp3, comp4];
const totals = computeGridTotals(rows);

assert(totals.visibleCount === 4, 'Totals: visibleCount is 4');
assert(totals.totalUnitsSum === 150 + 0 + 150 + 100, `Totals: totalUnitsSum matches (${totals.totalUnitsSum} === 400)`);
assert(totals.totalArrearsSum === 12000 + 12000 + 12000 + 0, `Totals: totalArrearsSum matches (${totals.totalArrearsSum} === 36,000)`);
assert(totals.totalPaidSum === 200000 + 200000 + 250000 + 0, `Totals: totalPaidSum matches (${totals.totalPaidSum} === 650,000)`);

// 3.6 Empty Grid Totals Protection
const emptyTotals = computeGridTotals([]);
assert(emptyTotals.visibleCount === 0, 'Empty Totals: visibleCount is 0');
assert(emptyTotals.totalUnitsSum === 0, 'Empty Totals: totalUnitsSum is 0');
assert(emptyTotals.totalDueSum === 0, 'Empty Totals: totalDueSum is 0');
assert(emptyTotals.totalRemainingSum === 0, 'Empty Totals: totalRemainingSum is 0');

// 3.7 Scale & Stress: 1,000 Simulated Rows Performance
const thousandRows = [];
for (let i = 1; i <= 1000; i++) {
  thousandRows.push({
    id: i,
    subNumber: `SUB-${i}`,
    route: `R-${i % 10}`,
    name: `مشترك رقم ${i}`,
    address: 'صنعاء',
    meterNumber: `M-${i}`,
    phone: `77${String(i).padStart(7, '0')}`,
    prevReading: i * 10,
    currReading: i * 10 + 50,
    lostUnits: 2,
    unitPrice: 1400,
    serviceFee: 1000,
    arrears: 500,
    paidAmount: 10000,
  });
}

const startTime = performance.now();
const computed1000 = thousandRows.map(computeRowFinancials);
const totals1000 = computeGridTotals(computed1000);
const durationMs = performance.now() - startTime;

assert(computed1000.length === 1000, 'Scale Test: 1000 rows computed');
assert(totals1000.visibleCount === 1000, 'Scale Test: totals1000 visibleCount is 1000');
assert(totals1000.totalUnitsSum === 50000, 'Scale Test: total units is 50,000 (50 * 1000)');
assert(durationMs < 50, `Scale Test: Execution took ${durationMs.toFixed(2)}ms (well within 50ms budget)`);

// ======================================================================
// SECTION 4: WhatsApp Message & Phone Internationalization
// ======================================================================
console.log('\n[4] Testing WhatsApp Output English Digits & Yemeni Phone Formatting...');

const waText = buildWhatsAppText(comp1, 'أغسطس - 2026');
const arabicDigitRegex = /[\u0660-\u0669\u06F0-\u06F9]/;
assert(!arabicDigitRegex.test(waText), 'WhatsApp message contains zero Eastern Arabic digits');
assert(waText.includes('1,350'), 'WhatsApp message formats current reading with English comma');
assert(waText.includes('237,000'), 'WhatsApp message formats total due with English comma');
assert(waText.includes('37,000'), 'WhatsApp message formats remaining balance with English comma');
assert(!waText.includes('NaN'), 'WhatsApp message contains zero NaN instances');

// Phone tests
assert(formatYemeniPhone('٠٧٧١٢٣٤٥٦٧') === '967771234567', 'formatYemeniPhone converts Eastern digits to 967 standard');
assert(formatYemeniPhone('+967 (78) 123-4567') === '967781234567', 'formatYemeniPhone strips symbols from phone');
assert(formatYemeniPhone('00967-73-1234567') === '967731234567', 'formatYemeniPhone standardizes international prefix');

// ======================================================================
// SECTION 5: Formatters Locale & Display Verification
// ======================================================================
console.log('\n[5] Verifying Formatters en-US Locale & Numeral Formatting...');

assert(formatNumber(1000000) === '1,000,000', 'formatNumber formats with English commas');
assert(formatCurrency(28500.5) === '28,500.5', 'formatCurrency formats currency with English numerals');
assert(formatMonth(new Date('2026-08-15')) === 'أغسطس 2026', 'formatMonth uses Arabic name and English year');
assert(!arabicDigitRegex.test(formatDate(new Date())), 'formatDate produces English numerals only');
assert(!arabicDigitRegex.test(formatDateOnly(new Date())), 'formatDateOnly produces English numerals only');

// ======================================================================
// SUMMARY & VERDICT
// ======================================================================
console.log('\n======================================================================');
console.log(`STRESS TEST SUMMARY: ${passedTests}/${totalTests} tests passed (${failedTests} failed).`);
if (failedTests > 0) {
  console.error(`✗ ADVERSARIAL STRESS TEST FAILED with ${failedTests} finding(s)!`);
  process.exit(1);
} else {
  console.log('✓ ALL ADVERSARIAL STRESS TESTS PASSED WITH ZERO REGRESSIONS!');
  console.log('======================================================================');
}
