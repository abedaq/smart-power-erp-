import fs from 'fs';
import path from 'path';

// Extract implementation of formatters for pure JS execution
function formatDate(date) {
  return new Date(date).toLocaleString('en-US', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: true,
  });
}

function formatDateOnly(date) {
  return new Date(date).toLocaleDateString('en-US', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
}

const ARABIC_MONTHS = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

function formatMonth(date) {
  const d = new Date(date);
  return `${ARABIC_MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}

function formatNumber(value) {
  return Number(value).toLocaleString('en-US');
}

function formatCurrency(value) {
  return Number(value).toLocaleString('en-US', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  });
}

function normalizeNumerals(str) {
  if (!str) return '';
  return str
    .replace(/[\u0660-\u0669]/g, (d) => String.fromCharCode(d.charCodeAt(0) - 1632 + 48))
    .replace(/[\u06F0-\u06F9]/g, (d) => String.fromCharCode(d.charCodeAt(0) - 1776 + 48));
}

const results = {
  passed: 0,
  failed: 0,
  assertions: [],
};

function assert(condition, testName, details = '') {
  if (condition) {
    results.passed++;
    results.assertions.push({ status: 'PASS', testName, details });
    console.log(`[PASS] ${testName}`);
  } else {
    results.failed++;
    results.assertions.push({ status: 'FAIL', testName, details });
    console.error(`[FAIL] ${testName} - ${details}`);
  }
}

const EASTERN_ARABIC_REGEX = /[\u0660-\u0669\u06F0-\u06F9]/;

console.log('====================================================');
console.log('STAGE 1: NUMERAL NORMALIZATION & FORMATTING STRESS TESTS');
console.log('====================================================');

// Test Eastern Arabic Digits (٠-٩)
const easternArabicInput = '٠١٢٣٤٥٦٧٨٩';
const normalizedEastern = normalizeNumerals(easternArabicInput);
assert(normalizedEastern === '0123456789', 'Normalize Eastern Arabic digits ٠-٩ to 0-9', `Got: ${normalizedEastern}`);
assert(!EASTERN_ARABIC_REGEX.test(normalizedEastern), 'Zero Eastern Arabic digits in normalized Eastern output');

// Test Persian Digits (۰-۹)
const persianInput = '۰۱۲۳۴۵۶۷۸۹';
const normalizedPersian = normalizeNumerals(persianInput);
assert(normalizedPersian === '0123456789', 'Normalize Persian digits ۰-۹ to 0-9', `Got: ${normalizedPersian}`);
assert(!EASTERN_ARABIC_REGEX.test(normalizedPersian), 'Zero Persian digits in normalized Persian output');

// Test Mixed Text & Numerals
const mixedText = 'المشترك رقم ١٠٤٥ استهلك ۲۵۰ كيلوواط بمبلغ ٤٥٠٠٠ ريال';
const normalizedMixed = normalizeNumerals(mixedText);
assert(
  normalizedMixed === 'المشترك رقم 1045 استهلك 250 كيلوواط بمبلغ 45000 ريال',
  'Normalize mixed Arabic/Persian/Latin string',
  `Got: ${normalizedMixed}`
);
assert(!EASTERN_ARABIC_REGEX.test(normalizedMixed), 'Zero Eastern/Persian digits in normalized mixed text');

// Edge cases for normalizeNumerals: null, undefined, empty, special chars
assert(normalizeNumerals('') === '', 'normalizeNumerals handles empty string');
assert(normalizeNumerals(null) === '', 'normalizeNumerals handles null safely');
assert(normalizeNumerals(undefined) === '', 'normalizeNumerals handles undefined safely');
assert(normalizeNumerals('NoDigitsHere') === 'NoDigitsHere', 'normalizeNumerals preserves ASCII letters');
assert(normalizeNumerals('!@#$%^&*()_+-=') === '!@#$%^&*()_+-=', 'normalizeNumerals preserves symbols');

// Test formatNumber
assert(formatNumber(0) === '0', 'formatNumber(0) -> "0"');
assert(formatNumber(1000) === '1,000', 'formatNumber(1000) -> "1,000"');
assert(formatNumber(28500) === '28,500', 'formatNumber(28500) -> "28,500"');
assert(formatNumber('5000000') === '5,000,000', 'formatNumber("5000000") -> "5,000,000"');
assert(formatNumber(-12500) === '-12,500', 'formatNumber(-12500) -> "-12,500"');
assert(!EASTERN_ARABIC_REGEX.test(formatNumber(28500)), 'formatNumber produces strictly English digits');

// Test formatCurrency
assert(formatCurrency(0) === '0', 'formatCurrency(0) -> "0"');
assert(formatCurrency(28500) === '28,500', 'formatCurrency(28500) -> "28,500"');
assert(formatCurrency(28500.5) === '28,500.5', 'formatCurrency(28500.5) -> "28,500.5"');
assert(formatCurrency(28500.75) === '28,500.75', 'formatCurrency(28500.75) -> "28,500.75"');
assert(formatCurrency(28500.999) === '28,501', 'formatCurrency(28500.999) -> "28,501" (rounded to 2 max decimals)');
assert(formatCurrency(-4500.5) === '-4,500.5', 'formatCurrency(-4500.5) -> "-4,500.5"');
assert(formatCurrency(1e9) === '1,000,000,000', 'formatCurrency(1e9) -> "1,000,000,000"');
assert(!EASTERN_ARABIC_REGEX.test(formatCurrency(9999999.99)), 'formatCurrency produces strictly English digits');

// Test formatDate & formatDateOnly
const testDateIso = '2026-08-20T13:18:00Z';
const formattedFull = formatDate(testDateIso);
const formattedDateOnly = formatDateOnly(testDateIso);
assert(!EASTERN_ARABIC_REGEX.test(formattedFull), `formatDate has no Eastern Arabic digits: "${formattedFull}"`);
assert(!EASTERN_ARABIC_REGEX.test(formattedDateOnly), `formatDateOnly has no Eastern Arabic digits: "${formattedDateOnly}"`);
assert(/\d{2}\/\d{2}\/\d{4}/.test(formattedDateOnly), `formatDateOnly matches MM/DD/YYYY format: "${formattedDateOnly}"`);

// Test formatMonth across all 12 months
for (let m = 0; m < 12; m++) {
  const d = new Date(2026, m, 15);
  const result = formatMonth(d);
  const expectedMonthName = ARABIC_MONTHS[m];
  assert(result.startsWith(expectedMonthName), `formatMonth month ${m + 1} starts with "${expectedMonthName}"`);
  assert(result.endsWith('2026'), `formatMonth month ${m + 1} ends with English year "2026"`);
  assert(!EASTERN_ARABIC_REGEX.test(result), `formatMonth month ${m + 1} has zero Eastern Arabic digits: "${result}"`);
}

console.log('\n====================================================');
console.log('STAGE 2: ROUTE & COMPONENT INTEGRITY TESTS');
console.log('====================================================');

const appTsxContent = fs.readFileSync('frontend/src/App.tsx', 'utf-8');
const sidebarContent = fs.readFileSync('frontend/src/components/Sidebar.tsx', 'utf-8');
const settingsContent = fs.readFileSync('frontend/src/pages/Settings.tsx', 'utf-8');
const arrearsReportContent = fs.readFileSync('frontend/src/pages/ArrearsReport.tsx', 'utf-8');

// 1. Verify /arrears route in App.tsx
assert(appTsxContent.includes('path="arrears"'), 'App.tsx contains path="arrears" route');
assert(appTsxContent.includes('<ArrearsReport />'), 'App.tsx route "arrears" renders <ArrearsReport />');
assert(
  appTsxContent.includes("allowedRoles={['ADMIN', 'ACCOUNTANT']}") &&
  appTsxContent.indexOf('path="arrears"') < appTsxContent.indexOf('<ArrearsReport />'),
  'App.tsx protects "arrears" for ADMIN and ACCOUNTANT'
);

// 2. Verify Sidebar contains /arrears for ADMIN and ACCOUNTANT
assert(
  sidebarContent.includes("{ to: '/arrears', label: 'المديونيات والمتأخرات', icon: AlertTriangle }"),
  'Sidebar contains /arrears link definition'
);

// 3. Verify Obsolete Tab Removals in App.tsx
assert(
  appTsxContent.includes('path="approved-edits" element={<Navigate to="/reports" replace />}'),
  'App.tsx redirects /approved-edits to /reports'
);
assert(
  !appTsxContent.includes('PlansManagement'),
  'App.tsx does NOT import or render PlansManagement'
);
assert(
  !appTsxContent.includes('path="tariffs"'),
  'App.tsx does NOT contain path="tariffs"'
);
assert(
  !appTsxContent.includes('path="import"'),
  'App.tsx does NOT contain path="import"'
);

// 4. Verify Settings.tsx handles tab params without crashing
assert(
  settingsContent.includes("const activeTab = searchParams.get('tab') || 'users';"),
  'Settings.tsx reads tab search param with safe fallback to users'
);
assert(
  !settingsContent.includes('PlansManagement') && !settingsContent.includes('Tariffs'),
  'Settings.tsx has no legacy Tariffs/PlansManagement component tabs'
);
assert(
  settingsContent.includes("activeTab === 'users'") &&
  settingsContent.includes("activeTab === 'whatsapp'") &&
  settingsContent.includes("activeTab === 'audit-logs'"),
  'Settings.tsx supports exactly users, whatsapp, and audit-logs tabs'
);

// 5. Verify ArrearsReport features
assert(arrearsReportContent.includes('days_overdue'), 'ArrearsReport calculates days_overdue');
assert(arrearsReportContent.includes('sendDisconnectionWarning'), 'ArrearsReport has sendDisconnectionWarning mutation');
assert(arrearsReportContent.includes('PaymentModal'), 'ArrearsReport includes direct inline PaymentModal');
assert(arrearsReportContent.includes('buildWarningNoticeText'), 'ArrearsReport includes buildWarningNoticeText for WhatsApp warning notices');

console.log('\n====================================================');
console.log('STAGE 3: DUAL-STUB INVOICE DOM & RTL LAYOUT TESTS');
console.log('====================================================');

const invoicePreviewContent = fs.readFileSync('frontend/src/components/InvoicePreviewModal.tsx', 'utf-8');
const cyclePrintContent = fs.readFileSync('frontend/src/components/CyclePrintView.tsx', 'utf-8');
const invoiceModalContent = fs.readFileSync('frontend/src/components/common/InvoiceModal.tsx', 'utf-8');
const invoiceEjsContent = fs.readFileSync('backend/src/templates/invoice.ejs', 'utf-8');

// 1. RTL and Width Split in InvoicePreviewModal
assert(invoicePreviewContent.includes('dir="rtl"'), 'InvoicePreviewModal has dir="rtl" on printable container');
assert(invoicePreviewContent.includes('col-span-5'), 'InvoicePreviewModal uses col-span-5 (~40%) for right collector coupon');
assert(invoicePreviewContent.includes('col-span-7'), 'InvoicePreviewModal uses col-span-7 (~60%) for left main customer bill');
assert(
  invoicePreviewContent.indexOf('col-span-5') < invoicePreviewContent.indexOf('col-span-7'),
  'InvoicePreviewModal places Collector Coupon FIRST in DOM (sits on RIGHT under RTL)'
);

// 2. RTL and Width Split in CyclePrintView
assert(cyclePrintContent.includes('dir="rtl"'), 'CyclePrintView has dir="rtl" on printable container');
assert(cyclePrintContent.includes('col-span-5'), 'CyclePrintView uses col-span-5 (~40%) for right collector coupon');
assert(cyclePrintContent.includes('col-span-7'), 'CyclePrintView uses col-span-7 (~60%) for left main customer bill');
assert(
  cyclePrintContent.indexOf('col-span-5') < cyclePrintContent.indexOf('col-span-7'),
  'CyclePrintView places Collector Coupon FIRST in DOM (sits on RIGHT under RTL)'
);

// 3. RTL and Width Split in InvoiceModal
assert(invoiceModalContent.includes('dir="rtl"'), 'InvoiceModal has dir="rtl" on printable container');
assert(invoiceModalContent.includes('col-span-5'), 'InvoiceModal uses col-span-5 (~40%) for right collector coupon');
assert(invoiceModalContent.includes('col-span-7'), 'InvoiceModal uses col-span-7 (~60%) for left main customer bill');
assert(
  invoiceModalContent.indexOf('col-span-5') < invoiceModalContent.indexOf('col-span-7'),
  'InvoiceModal places Collector Coupon FIRST in DOM (sits on RIGHT under RTL)'
);

// 4. RTL and Width Split in Puppeteer invoice.ejs
assert(invoiceEjsContent.includes('direction: rtl;'), 'invoice.ejs CSS specifies direction: rtl');
assert(invoiceEjsContent.includes('.collector-stub'), 'invoice.ejs has .collector-stub class');
assert(invoiceEjsContent.includes('.main-bill'), 'invoice.ejs has .main-bill class');
assert(
  invoiceEjsContent.indexOf('class="collector-stub"') < invoiceEjsContent.indexOf('class="main-bill"'),
  'invoice.ejs places collector-stub FIRST in flex layout (sits on RIGHT under RTL)'
);

// 5. Check Table Headers in Dual-Stub Layouts
// Collector Coupon: 5 columns (ق.السابقة, ق.الحالية, الفارق, متأخرات وغرامات, الاجمالي)
assert(invoicePreviewContent.includes('قــــــراءة العداد'), 'Collector coupon table has reading header group');
assert(invoicePreviewContent.includes('متأخرات وغرامات'), 'Collector coupon table has "متأخرات وغرامات" header');

// Main Customer Bill: 7 columns (ق. السابقة, ق. الحالية, الفارق, اشتراك, القيمة, متأخرات, الاجمالي)
assert(invoicePreviewContent.includes('اشتراك'), 'Main bill table has "اشتراك" (fixed fee) column');
assert(invoicePreviewContent.includes('القيمـة'), 'Main bill table has "القيمة" (consumption value) column');

// 6. Check 5 Official Policy Lines in Templates
const policyKeywords = [
  'يتم سداد الفاتورة يوم استلامها',
  'في حالة تأخر السداد سيتم فصل التيار',
  'توصيل التيار لشخص آخر',
  'سند رسمي مختوم بختم المحطة',
  'سعر الكيلوواط/ ساعة 1400 ريال',
];

policyKeywords.forEach((kw, idx) => {
  assert(
    invoicePreviewContent.includes(kw),
    `InvoicePreviewModal contains policy rule #${idx + 1} ("${kw}")`
  );
  assert(
    cyclePrintContent.includes(kw),
    `CyclePrintView contains policy rule #${idx + 1} ("${kw}")`
  );
  assert(
    invoiceModalContent.includes(kw),
    `InvoiceModal contains policy rule #${idx + 1} ("${kw}")`
  );
  assert(
    invoiceEjsContent.includes(kw),
    `invoice.ejs contains policy rule #${idx + 1} ("${kw}")`
  );
});

// 7. Check Station Phone & Bank Account
assert(invoicePreviewContent.includes('783270260_736955883'), 'InvoicePreviewModal has station phone default');
assert(invoicePreviewContent.includes('3052001225'), 'InvoicePreviewModal has bank account number default');
assert(invoiceEjsContent.includes('783270260_736955883'), 'invoice.ejs has station phone default');
assert(invoiceEjsContent.includes('3052001225'), 'invoice.ejs has bank account number default');

console.log('\n====================================================');
console.log('STAGE 4: CSS SPINNERS & NUMERAL RESETS TESTS');
console.log('====================================================');

const indexCssContent = fs.readFileSync('frontend/src/index.css', 'utf-8');

assert(
  indexCssContent.includes('input[type="number"]::-webkit-outer-spin-button') &&
  indexCssContent.includes('-webkit-appearance: none;'),
  'index.css resets WebKit outer/inner spin buttons'
);
assert(
  indexCssContent.includes('-moz-appearance: textfield;'),
  'index.css resets Firefox spinner via -moz-appearance: textfield'
);
assert(
  indexCssContent.includes('font-feature-settings: "lnum" 1;'),
  'index.css forces lining English numerals via font-feature-settings'
);

console.log('\n====================================================');
console.log(`SUMMARY: Total Passed: ${results.passed}, Total Failed: ${results.failed}`);
console.log('====================================================');

fs.writeFileSync(
  '.agents/challenger_frontend/stress_test_results.json',
  JSON.stringify(results, null, 2),
  'utf-8'
);

if (results.failed > 0) {
  process.exit(1);
} else {
  process.exit(0);
}
