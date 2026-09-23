/**
 * Adversarial UI Resilience & Performance Stress Test Suite
 * 
 * Challenger: Frontend UI Resilience Challenger
 * Tests:
 * 1. Scalability benchmarks for computeRowFinancials and computeGridTotals (1,000, 2,500, 5,000 rows)
 * 2. Adversarial edge cases (zeroes, huge numbers, IEEE 754 precision, negative numbers, corrupted inputs)
 * 3. Frame budget verification (< 50ms per tick / 60fps target)
 * 4. UI auto-save on blur and areValuesEqual guard validation
 * 5. Complete mathematical invariant verification across rows and totals
 */

import { performance } from 'perf_hooks';
import {
  computeRowFinancials,
  computeGridTotals,
  formatYemeniPhone,
  buildWhatsAppText,
} from '../types/excelGrid.types.ts';

import {
  toEnglishDigits,
  sanitizeDecimalInput,
  sanitizeIntegerInput,
  formatNumber,
  formatCurrency,
} from '../utils/formatters.ts';

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

// Exact implementation of areValuesEqual from ExcelGrid.tsx (lines 210-216)
const areValuesEqual = (val1, val2) => {
  if (val1 === val2) return true;
  if (typeof val1 === 'number' || typeof val2 === 'number') {
    return Number(val1 || 0) === Number(val2 || 0);
  }
  return String(val1 ?? '').trim() === String(val2 ?? '').trim();
};

console.log('======================================================================');
console.log('FRONTEND UI RESILIENCE & PERFORMANCE ADVERSARIAL STRESS CHALLENGE');
console.log('======================================================================');

// ======================================================================
// SECTION 1: BENCHMARKING COMPUTE ENGINE ON MASSIVE ROWSETS (1K, 2.5K, 5K)
// ======================================================================
console.log('\n[1] Benchmarking computeRowFinancials & computeGridTotals (1,000 / 2,500 / 5,000 rows)...');

function generateBenchmarkDataset(rowCount) {
  const rows = new Array(rowCount);
  for (let i = 0; i < rowCount; i++) {
    const id = i + 1;
    rows[i] = {
      id,
      subNumber: `SUB-${10000 + id}`,
      route: `R-${(id % 20) + 1}`,
      name: `مشترك تجريبي رقم ${id}`,
      address: `صنعاء - الحي ${(id % 15) + 1}`,
      meterNumber: `MTR-${50000 + id}`,
      phone: `77${String(id).padStart(7, '0')}`,
      prevReading: (id * 15) % 100000,
      currReading: ((id * 15) % 100000) + (id % 450) + 10,
      unitPrice: 1400,
      serviceFee: 1000,
      arrears: (id % 10) * 1500,
      paidAmount: (id % 4 === 0) ? 50000 : 0,
      status: (id % 4 === 0) ? 'Paid' : 'Unpaid',
    };
  }
  return rows;
}

function runBenchmark(rowCount, iterations = 10) {
  const dataset = generateBenchmarkDataset(rowCount);
  
  // Warmup V8 JIT
  for (let w = 0; w < 3; w++) {
    const warmupComputed = dataset.map(computeRowFinancials);
    computeGridTotals(warmupComputed);
  }

  // Force garbage collection if exposed, otherwise record memory
  const memBefore = process.memoryUsage();
  const times = [];

  for (let iter = 0; iter < iterations; iter++) {
    const start = performance.now();
    const computedRows = dataset.map(computeRowFinancials);
    const totals = computeGridTotals(computedRows);
    const end = performance.now();
    times.push(end - start);
  }

  const memAfter = process.memoryUsage();
  const minTime = Math.min(...times);
  const maxTime = Math.max(...times);
  const avgTime = times.reduce((a, b) => a + b, 0) / times.length;
  const throughput = Math.round((rowCount / (avgTime / 1000)));
  const heapDeltaMB = ((memAfter.heapUsed - memBefore.heapUsed) / (1024 * 1024)).toFixed(2);

  console.log(`\n  --- Benchmark Scale: ${rowCount.toLocaleString('en-US')} Rows (${iterations} iterations) ---`);
  console.log(`    Avg Time    : ${avgTime.toFixed(2)} ms`);
  console.log(`    Min Time    : ${minTime.toFixed(2)} ms`);
  console.log(`    Max Time    : ${maxTime.toFixed(2)} ms`);
  console.log(`    Throughput  : ${throughput.toLocaleString('en-US')} rows/sec`);
  console.log(`    Heap Delta  : ${heapDeltaMB} MB`);

  return { rowCount, avgTime, minTime, maxTime, throughput, heapDeltaMB };
}

const bench1000 = runBenchmark(1000, 15);
assert(bench1000.avgTime < 50, `1,000 Rows: Avg time (${bench1000.avgTime.toFixed(2)}ms) strictly within 50ms frame budget`);
assert(bench1000.avgTime < 16.67, `1,000 Rows: Avg time (${bench1000.avgTime.toFixed(2)}ms) fits 60fps single-frame render budget (<16.67ms)`);

const bench2500 = runBenchmark(2500, 10);
assert(bench2500.avgTime < 50, `2,500 Rows: Avg time (${bench2500.avgTime.toFixed(2)}ms) strictly within 50ms frame budget`);

const bench5000 = runBenchmark(5000, 10);
assert(bench5000.avgTime < 50, `5,000 Rows: Avg time (${bench5000.avgTime.toFixed(2)}ms) strictly within 50ms frame budget`);

// ======================================================================
// SECTION 2: ADVERSARIAL EDGE CASES (FINANCIAL ENGINE MATH & STABILITY)
// ======================================================================
console.log('\n[2] Adversarial Edge-Case Stress Testing (Math, Types, Overflow, IEEE 754)...');

// 2.1 Zero Readings
const zeroRow = computeRowFinancials({
  id: 1,
  prevReading: 0,
  currReading: 0,
  unitPrice: 0,
  serviceFee: 0,
  arrears: 0,
  paidAmount: 0,
});
assert(zeroRow.units === 0, 'Zero reading: units === 0');
assert(zeroRow.consumptionCost === 0, 'Zero reading: consumptionCost === 0');
assert(zeroRow.totalDue === 0, 'Zero reading: totalDue === 0');
assert(zeroRow.remaining === 0, 'Zero reading: remaining === 0');
assert(!Number.isNaN(zeroRow.totalDue), 'Zero reading: zero NaN generated');

// 2.2 Non-monotonic reading: currReading < prevReading (protection against negative consumption)
const nonMonotonicRow = computeRowFinancials({
  id: 2,
  prevReading: 5000,
  currReading: 3000, // Reversed!
  unitPrice: 1400,
  serviceFee: 1000,
  arrears: 500,
  paidAmount: 2000,
});
assert(nonMonotonicRow.units === 0, 'Non-monotonic: units clamped to 0 via Math.max(0, curr - prev)');
assert(nonMonotonicRow.consumptionCost === 0, 'Non-monotonic: consumption cost is 0');
assert(nonMonotonicRow.totalDue === 1500, 'Non-monotonic: totalDue = 0 + 1000 + 500 = 1,500');
assert(nonMonotonicRow.remaining === -500, 'Non-monotonic: remaining = 1500 - 2000 = -500');

// 2.3 Astronomical / Huge Numbers (Stress overflow & precision)
const hugeRow = computeRowFinancials({
  id: 3,
  prevReading: '100000000',
  currReading: '100050000', // 50,000 units
  unitPrice: '1400',
  serviceFee: '100000',
  arrears: '5000000000', // 5 Billion YER arrears
  paidAmount: '2000000000', // 2 Billion YER paid
});
assert(hugeRow.units === 50000, 'Huge numbers: 50,000 units parsed');
assert(hugeRow.consumptionCost === 70000000, 'Huge numbers: consumption cost 70,000,000 YER');
assert(hugeRow.totalDue === 70000000 + 100000 + 5000000000, 'Huge numbers: total due matches 5,070,100,000');
assert(hugeRow.remaining === (5070100000 - 2000000000), 'Huge numbers: remaining matches 3,070,100,000');
assert(!Number.isNaN(hugeRow.totalDue), 'Huge numbers: no NaN generated');
assert(Number.isFinite(hugeRow.totalDue), 'Huge numbers: result is finite');

// 2.4 Fractional / IEEE 754 Floating Point Quirks
const floatRow = computeRowFinancials({
  id: 4,
  prevReading: '1000.1',
  currReading: '1000.3', // 0.2 units
  unitPrice: '1400.5',
  serviceFee: '100.25',
  arrears: '50.75',
  paidAmount: '300.50',
});
assert(Math.abs(floatRow.units - 0.2) < 1e-9, `Float precision: units is ~0.2 (actual: ${floatRow.units})`);
assert(!Number.isNaN(floatRow.totalDue), 'Float precision: totalDue is not NaN');
assert(!Number.isNaN(floatRow.remaining), 'Float precision: remaining is not NaN');

// 2.5 Negative Arrears (Subscriber Credit Balance)
const creditRow = computeRowFinancials({
  id: 5,
  prevReading: 1000,
  currReading: 1100, // 100 units
  unitPrice: 1400,
  serviceFee: 1000,
  arrears: -25000, // Negative arrears = 25,000 credit
  paidAmount: 50000,
});
assert(creditRow.totalDue === (140000 + 1000 - 25000), 'Negative arrears: total due reflects credit deduction (116,000)');
assert(creditRow.remaining === (116000 - 50000), 'Negative arrears: remaining is 66,000');

// 2.6 Massive Overpayment (Resulting in negative remaining balance / credit)
const overpaidRow = computeRowFinancials({
  id: 6,
  prevReading: 1000,
  currReading: 1050, // 50 units * 1400 = 70,000
  unitPrice: 1400,
  serviceFee: 1000,
  arrears: 0,
  paidAmount: 100000, // Paid 100k for 71k total
});
assert(overpaidRow.totalDue === 71000, 'Overpayment: total due is 71,000');
assert(overpaidRow.remaining === -29000, 'Overpayment: remaining balance is -29,000 (credit)');

// 2.7 Malformed & Corrupted Types Resilience
const corruptedRow = computeRowFinancials({
  id: 7,
  prevReading: null,
  currReading: undefined,
  unitPrice: '',
  serviceFee: '   ',
  arrears: NaN,
  paidAmount: {},
});
assert(corruptedRow.units === 0, 'Corrupted row: units safely evaluates to 0');
assert(corruptedRow.consumptionCost === 0, 'Corrupted row: consumptionCost is 0');
assert(corruptedRow.totalDue === 0, 'Corrupted row: totalDue is 0 (zero crash/NaN)');
assert(corruptedRow.remaining === 0, 'Corrupted row: remaining is 0');

// 2.8 Inputs with Unicode, RTL Marks, and Commas
const unicodeRow = computeRowFinancials({
  id: 8,
  prevReading: '\u200F1,200\u200E',
  currReading: '\u200B1,450.50\u200C',
  unitPrice: '١,٤٠٠', // Eastern Arabic 1,400 with comma
  serviceFee: '1,000',
  arrears: '12,500',
  paidAmount: '200,000',
});
assert(unicodeRow.units === 250.5, `Unicode & Commas: units parsed as 250.5 (actual: ${unicodeRow.units})`);
assert(unicodeRow.consumptionCost === (250.5 * 1400), `Unicode & Commas: consumption cost is 350,700 (actual: ${unicodeRow.consumptionCost})`);
assert(!Number.isNaN(unicodeRow.totalDue), 'Unicode & Commas: total due is free of NaN');
assert(!Number.isNaN(unicodeRow.remaining), 'Unicode & Commas: remaining is free of NaN');

// ======================================================================
// SECTION 3: UI AUTO-SAVE ON BLUR & areValuesEqual GUARD VERIFICATION
// ======================================================================
console.log('\n[3] Validating areValuesEqual Guard (False-Positive & False-Negative Prevention)...');

// 3.1 Identical Values (Must return TRUE -> No Save)
assert(areValuesEqual(100, 100) === true, 'areValuesEqual: 100 === 100');
assert(areValuesEqual(0, 0) === true, 'areValuesEqual: 0 === 0');
assert(areValuesEqual('Sanaa', 'Sanaa') === true, 'areValuesEqual: "Sanaa" === "Sanaa"');
assert(areValuesEqual('', '') === true, 'areValuesEqual: "" === ""');
assert(areValuesEqual(null, null) === true, 'areValuesEqual: null === null');
assert(areValuesEqual(undefined, undefined) === true, 'areValuesEqual: undefined === undefined');

// 3.2 Equivalent Numbers across Types (Must return TRUE -> Prevent redundant API call)
assert(areValuesEqual(1250, '1250') === true, 'areValuesEqual: 1250 (number) === "1250" (string)');
assert(areValuesEqual('1250', 1250) === true, 'areValuesEqual: "1250" (string) === 1250 (number)');
assert(areValuesEqual(1250.5, '1250.50') === true, 'areValuesEqual: 1250.5 === "1250.50" (floating format difference)');
assert(areValuesEqual(0, '0') === true, 'areValuesEqual: 0 === "0"');
assert(areValuesEqual(0, '') === true, 'areValuesEqual: 0 === "" (blank treated as 0 for numeric field)');
assert(areValuesEqual('', 0) === true, 'areValuesEqual: "" === 0');
assert(areValuesEqual(0, null) === true, 'areValuesEqual: 0 === null');
assert(areValuesEqual(0, undefined) === true, 'areValuesEqual: 0 === undefined');
assert(areValuesEqual(null, 0) === true, 'areValuesEqual: null === 0');

// 3.3 Trimmed Strings (Must return TRUE -> Prevent redundant save on trailing space)
assert(areValuesEqual('صنعاء ', 'صنعاء') === true, 'areValuesEqual: "صنعاء " === "صنعاء" (whitespace trimmed)');
assert(areValuesEqual('  R-01  ', 'R-01') === true, 'areValuesEqual: "  R-01  " === "R-01"');
assert(areValuesEqual(null, undefined) === true, 'areValuesEqual: null === undefined (both blank strings)');
assert(areValuesEqual(null, '') === true, 'areValuesEqual: null === ""');

// 3.4 Genuinely Different Values (Must return FALSE -> Guarantee auto-save triggers)
assert(areValuesEqual(1250, 1350) === false, 'areValuesEqual: 1250 !== 1350 (triggers save)');
assert(areValuesEqual(1250, '1251') === false, 'areValuesEqual: 1250 !== "1251" (triggers save)');
assert(areValuesEqual(0, 50) === false, 'areValuesEqual: 0 !== 50 (triggers save)');
assert(areValuesEqual('صنعاء', 'عدن') === false, 'areValuesEqual: "صنعاء" !== "عدن" (triggers save)');
assert(areValuesEqual('SUB-001', 'SUB-002') === false, 'areValuesEqual: "SUB-001" !== "SUB-002" (triggers save)');

// 3.5 String Identifier Leading Zero Retention
// subNumber "00123" vs "123": Both are strings, so String.trim() is compared!
assert(areValuesEqual('00123', '123') === false, 'areValuesEqual: "00123" !== "123" (preserves subscriber number leading zero change)');
assert(areValuesEqual('01', '1') === false, 'areValuesEqual: "01" !== "1" for string route identifier');

// 3.6 Rapid Repeated Blurs Simulation (Idempotency Guard)
let networkCallCount = 0;
const mockInitialRow = { id: 1, currReading: 1250, subNumber: '1001' };
const initialMap = new Map([[1, { ...mockInitialRow }]]);

function simulateBlurEvent(id, field, newValue) {
  const orig = initialMap.get(id);
  const origVal = orig ? orig[field] : undefined;
  if (areValuesEqual(origVal, newValue)) {
    // Guard prevented save!
    return false;
  }
  // Trigger save:
  networkCallCount++;
  // Update snapshot map to prevent revert:
  initialMap.set(id, { ...orig, [field]: newValue });
  return true;
}

// User enters 1250 (same as initial) -> Blur
const saved1 = simulateBlurEvent(1, 'currReading', 1250);
assert(saved1 === false && networkCallCount === 0, 'Simulation 1: Blurring unchanged value triggers 0 API calls');

// User enters "1250" (string identical) -> Blur
const saved2 = simulateBlurEvent(1, 'currReading', '1250');
assert(saved2 === false && networkCallCount === 0, 'Simulation 2: Blurring string representation of same number triggers 0 API calls');

// User modifies to 1350 -> Blur
const saved3 = simulateBlurEvent(1, 'currReading', 1350);
assert(saved3 === true && networkCallCount === 1, 'Simulation 3: Legitimate change triggers exactly 1 API call');

// User clicks cell again, modifies nothing, blurs
const saved4 = simulateBlurEvent(1, 'currReading', 1350);
assert(saved4 === false && networkCallCount === 1, 'Simulation 4: Subsequent blur on updated value triggers 0 additional API calls');

// User enters "1350.00" -> Blur
const saved5 = simulateBlurEvent(1, 'currReading', '1350.00');
assert(saved5 === false && networkCallCount === 1, 'Simulation 5: Formatted blur of updated value triggers 0 additional API calls');

// ======================================================================
// SECTION 4: MATHEMATICAL INVARIANT CONSISTENCY ACROSS 5,000 ROWS
// ======================================================================
console.log('\n[4] Verifying 10 Mathematical Invariants Across 5,000 Mixed Rows...');

const stressRows = generateBenchmarkDataset(5000);
// Inject adversarial mutations into subset of rows
stressRows[10].currReading = stressRows[10].prevReading - 500; // Negative consumption
stressRows[20].arrears = -35000; // Negative arrears
stressRows[30].paidAmount = 1000000; // Large overpayment
stressRows[50].serviceFee = '2500'; // String service fee
stressRows[60].currReading = ''; // Empty reading
stressRows[70].paidAmount = undefined; // Undefined paid

const computedStress = stressRows.map(computeRowFinancials);
const totalsStress = computeGridTotals(computedStress);

let invariantsPassed = true;
let nanCount = 0;

let manualUnitsSum = 0;
let manualArrearsSum = 0;
let manualConsumptionCostSum = 0;
let manualTotalDueSum = 0;
let manualPaidSum = 0;
let manualRemainingSum = 0;

for (let i = 0; i < computedStress.length; i++) {
  const r = computedStress[i];
  
  // Check for NaN
  if (Number.isNaN(r.units) || Number.isNaN(r.consumptionCost) || Number.isNaN(r.totalDue) || Number.isNaN(r.remaining)) {
    nanCount++;
  }

  // Row invariant check
  if (r.units < 0) invariantsPassed = false;
  if (r.consumptionCost !== (r.units * Number(r.unitPrice || 0))) invariantsPassed = false;
  
  const expectedTotalDue = r.consumptionCost + Number(r.serviceFee || 0) + Number(r.arrears || 0);
  if (Math.abs(r.totalDue - expectedTotalDue) > 1e-6) invariantsPassed = false;

  const expectedRemaining = r.totalDue - Number(r.paidAmount || 0);
  if (Math.abs(r.remaining - expectedRemaining) > 1e-6) invariantsPassed = false;

  manualUnitsSum += r.units;
  manualArrearsSum += Number(r.arrears || 0);
  manualConsumptionCostSum += r.consumptionCost;
  manualTotalDueSum += r.totalDue;
  manualPaidSum += Number(r.paidAmount || 0);
  manualRemainingSum += r.remaining;
}

assert(nanCount === 0, `Mathematical Invariants: Exactly 0 NaN values across 5,000 rows (found: ${nanCount})`);
assert(invariantsPassed === true, 'Mathematical Invariants: 100% of row-level formulas strictly satisfied');
assert(totalsStress.visibleCount === 5000, 'Totals Invariant: visibleCount matches 5,000');
assert(Math.abs(totalsStress.totalUnitsSum - manualUnitsSum) < 1e-4, 'Totals Invariant: totalUnitsSum matches manual sum');
assert(Math.abs(totalsStress.totalArrearsSum - manualArrearsSum) < 1e-4, 'Totals Invariant: totalArrearsSum matches manual sum');
assert(Math.abs(totalsStress.totalConsumptionCostSum - manualConsumptionCostSum) < 1e-4, 'Totals Invariant: totalConsumptionCostSum matches manual sum');
assert(Math.abs(totalsStress.totalDueSum - manualTotalDueSum) < 1e-4, 'Totals Invariant: totalDueSum matches manual sum');
assert(Math.abs(totalsStress.totalPaidSum - manualPaidSum) < 1e-4, 'Totals Invariant: totalPaidSum matches manual sum');
assert(Math.abs(totalsStress.totalRemainingSum - manualRemainingSum) < 1e-4, 'Totals Invariant: totalRemainingSum matches manual sum');

// ======================================================================
// SUMMARY & VERDICT
// ======================================================================
console.log('\n======================================================================');
console.log(`STRESS TEST SUMMARY: ${passedTests}/${totalTests} tests passed (${failedTests} failed).`);
if (failedTests > 0) {
  console.error(`✗ ADVERSARIAL CHALLENGE COMPLETED WITH ${failedTests} FAILURE(S)!`);
  process.exit(1);
} else {
  console.log('✓ ALL ADVERSARIAL STRESS CHALLENGES PASSED EMPIRICALLY!');
  console.log('======================================================================');
}
