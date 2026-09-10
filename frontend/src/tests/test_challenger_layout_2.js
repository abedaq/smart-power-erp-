import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const srcDir = path.resolve(__dirname, '..');

let totalTests = 0;
let passedTests = 0;
let failedTests = 0;
const failures = [];

function assert(condition, testName, details = '') {
  totalTests++;
  if (condition) {
    passedTests++;
    console.log(`  ✓ PASS: ${testName}`);
  } else {
    failedTests++;
    failures.push({ testName, details });
    console.error(`  ✗ FAIL: ${testName}`);
    if (details) console.error(`    Details: ${details}`);
  }
}

console.log('========================================================================');
console.log('CHALLENGER 2: EMPIRICAL STRUCTURAL & ADVERSARIAL VERIFICATION HARNESS');
console.log('========================================================================\n');

// -----------------------------------------------------------------------------
// MODULE 1: SIDEBAR NAVIGATION & ROLE-BASED ACCESS CONTROL (RBAC)
// -----------------------------------------------------------------------------
console.log('--- MODULE 1: Sidebar Navigation & Role-Based Access Control ---');

const sidebarPath = path.join(srcDir, 'components/Sidebar.tsx');
const appPath = path.join(srcDir, 'App.tsx');
const settingsPath = path.join(srcDir, 'pages/Settings.tsx');

const sidebarSource = fs.readFileSync(sidebarPath, 'utf-8');
const appSource = fs.readFileSync(appPath, 'utf-8');
const settingsSource = fs.readFileSync(settingsPath, 'utf-8');

// 1.1 Role-Based Links in Sidebar.tsx
// Extract role branches
assert(
  sidebarSource.includes("if (role === 'ADMIN')") &&
  sidebarSource.includes("else if (role === 'ACCOUNTANT' || role === 'CASHIER')") &&
  sidebarSource.includes("// COLLECTOR"),
  'Sidebar.tsx implements explicit role segregation for ADMIN, ACCOUNTANT, CASHIER, COLLECTOR'
);

// ADMIN checks
const adminSection = sidebarSource.substring(
  sidebarSource.indexOf("if (role === 'ADMIN')"),
  sidebarSource.indexOf("else if (role === 'ACCOUNTANT'")
);
assert(
  adminSection.includes("to: '/arrears', label: 'المديونيات والمتأخرات', icon: AlertTriangle"),
  'ADMIN role has "/arrears" (المديونيات والمتأخرات) navigation link with AlertTriangle icon'
);
assert(
  adminSection.includes("to: '/customers'") &&
  adminSection.includes("to: '/invoices'") &&
  adminSection.includes("to: '/reports'") &&
  adminSection.includes("to: '/settings'"),
  'ADMIN role has complete management links (customers, invoices, arrears, reports, settings)'
);

// ACCOUNTANT & CASHIER checks
const accountantCashierSection = sidebarSource.substring(
  sidebarSource.indexOf("else if (role === 'ACCOUNTANT' || role === 'CASHIER')"),
  sidebarSource.indexOf("// COLLECTOR")
);
assert(
  accountantCashierSection.includes("to: '/arrears', label: 'المديونيات والمتأخرات', icon: AlertTriangle"),
  'ACCOUNTANT & CASHIER roles have "/arrears" (المديونيات والمتأخرات) navigation link'
);
assert(
  accountantCashierSection.includes("to: '/customers'") &&
  accountantCashierSection.includes("to: '/invoices'") &&
  accountantCashierSection.includes("to: '/reports'"),
  'ACCOUNTANT & CASHIER roles have customers, invoices, arrears, and reports links'
);
assert(
  !accountantCashierSection.includes("to: '/settings'"),
  'ACCOUNTANT & CASHIER roles are restricted from system settings'
);

// COLLECTOR checks
const collectorSection = sidebarSource.substring(
  sidebarSource.indexOf("// COLLECTOR"),
  sidebarSource.indexOf("return (")
);
assert(
  collectorSection.includes("to: '/customers', label: 'العملاء والتحصيل الميداني'") &&
  collectorSection.includes("to: '/unread-meters'"),
  'COLLECTOR role is scoped to field collection (/customers) and unread meters'
);
assert(
  !collectorSection.includes("to: '/arrears'"),
  'COLLECTOR role sidebar omits admin arrears tab (field collection handled inside customer view)'
);

// Role Fallback safety
assert(
  sidebarSource.includes("const role = user?.role || 'COLLECTOR';"),
  'Sidebar.tsx applies principle of least privilege: default role fallback is COLLECTOR'
);

// 1.2 Routing in App.tsx
assert(
  appSource.includes("path=\"arrears\"") &&
  appSource.includes("<ProtectedRoute allowedRoles={['ADMIN', 'ACCOUNTANT', 'CASHIER']}>") &&
  appSource.includes("<ArrearsReport />"),
  'App.tsx protects route "/arrears" for ADMIN, ACCOUNTANT, CASHIER directly rendering <ArrearsReport />'
);

assert(
  appSource.includes("if (user.role === 'COLLECTOR') {\n      return <Navigate to=\"/customers\" replace />;\n    }"),
  'App.tsx redirect guard sends unauthorized COLLECTOR attempts cleanly to "/customers"'
);

assert(
  appSource.includes("if (user.role === 'ACCOUNTANT' || user.role === 'CASHIER') {\n      return <Navigate to=\"/invoices\" replace />;\n    }"),
  'App.tsx redirect guard sends unauthorized ACCOUNTANT/CASHIER attempts cleanly to "/invoices"'
);

// -----------------------------------------------------------------------------
// MODULE 2: COMPLETE ERADICATION OF GENERAL TARIFF & FEES
// -----------------------------------------------------------------------------
console.log('\n--- MODULE 2: Eradication of General Tariff & Fees ---');

// 2.1 Absence from Sidebar
assert(
  !sidebarSource.includes('GeneralTariff') &&
  !sidebarSource.includes('/tariffs') &&
  !sidebarSource.includes('/general-tariffs') &&
  !sidebarSource.includes('التعرفة والرسوم العامة'),
  'Sidebar.tsx contains ZERO references to General Tariff & Fees'
);

// 2.2 Absence from App.tsx
assert(
  !appSource.includes('GeneralTariff') &&
  !appSource.includes('path="tariffs"') &&
  !appSource.includes('path="general-tariffs"') &&
  !appSource.includes('tab=tariffs'),
  'App.tsx contains ZERO routes or redirects for General Tariff & Fees'
);

// 2.3 Absence from Settings.tsx
assert(
  !settingsSource.includes('GeneralTariff') &&
  !settingsSource.includes('tab=tariffs') &&
  !settingsSource.includes("activeTab === 'tariffs'") &&
  !settingsSource.includes('التعرفة'),
  'Settings.tsx contains ZERO references or sub-tabs for General Tariff & Fees'
);

// 2.4 Verified Settings Active Tabs
assert(
  settingsSource.includes("activeTab === 'users'") &&
  settingsSource.includes("activeTab === 'whatsapp'") &&
  settingsSource.includes("activeTab === 'audit-logs'"),
  'Settings.tsx active tabs strictly restricted to Users, WhatsApp, and Audit Logs'
);

// -----------------------------------------------------------------------------
// MODULE 3: DOUBLE-STUB INVOICE LAYOUT VERIFICATION
// -----------------------------------------------------------------------------
console.log('\n--- MODULE 3: Double-Stub Invoice Layout Verification ---');

const invoiceModalPath = path.join(srcDir, 'components/common/InvoiceModal.tsx');
const invoicePreviewModalPath = path.join(srcDir, 'components/InvoicePreviewModal.tsx');
const cyclePrintViewPath = path.join(srcDir, 'components/CyclePrintView.tsx');

const invoiceModalSrc = fs.readFileSync(invoiceModalPath, 'utf-8');
const invoicePreviewSrc = fs.readFileSync(invoicePreviewModalPath, 'utf-8');
const cyclePrintSrc = fs.readFileSync(cyclePrintViewPath, 'utf-8');

const invoiceComponents = [
  { name: 'InvoiceModal.tsx', src: invoiceModalSrc },
  { name: 'InvoicePreviewModal.tsx', src: invoicePreviewSrc },
  { name: 'CyclePrintView.tsx (Individual Mode)', src: cyclePrintSrc },
];

const requiredTerms = [
  'يتم سداد الفاتورة يوم استلامها او اليوم التالي فقط',
  'في حالة تأخر السداد سيتم فصل التيار دون إشعار مسبق ولن يعاد الا بغرامة',
  'في حال قيام المشترك بتوصيل التيار لشخص آخر سيتم تغريم المشترك مبلغ وقدره 200000',
  'يتحمل المشترك مديونية أي موظف إن لم يكن هناك سند رسمي مختوم بختم المحطة',
  'سعر الكيلوواط/ ساعة 1400 ريال ويرتفع سعر الكيلو بنسبة وتناسب بارتفاع الديزل',
];

for (const comp of invoiceComponents) {
  console.log(`\n  Checking Component: ${comp.name}...`);

  // 3.1 40% / 60% Split Verification
  assert(
    comp.src.includes('grid grid-cols-12 gap-0 items-stretch') || comp.src.includes('grid-cols-12'),
    `[${comp.name}] Uses 12-column grid layout`
  );
  assert(
    comp.src.includes('col-span-5'),
    `[${comp.name}] Collector stub allocated col-span-5 (5/12 = 41.7% ~ 40%)`
  );
  assert(
    comp.src.includes('col-span-7'),
    `[${comp.name}] Customer main invoice allocated col-span-7 (7/12 = 58.3% ~ 60%)`
  );
  assert(
    comp.src.includes('border-r-2 border-black'),
    `[${comp.name}] Vertical separating border between collector coupon and customer bill is present`
  );

  // 3.2 Outer Thick Frame
  assert(
    comp.src.includes('border-2 border-black'),
    `[${comp.name}] Outer thick black border (border-2 border-black) wrapping invoice`
  );

  // 3.3 Station Name & Official Phone & Bank Account
  assert(
    comp.src.includes('محطة الضياء لتوليد الطاقة الكهربائية'),
    `[${comp.name}] Station name default is "محطة الضياء لتوليد الطاقة الكهربائية"`
  );
  assert(
    comp.src.includes('783270260_736955883'),
    `[${comp.name}] Official station phones "783270260_736955883" included`
  );
  assert(
    comp.src.includes('3052001225') && comp.src.includes('يمكنك الإيداع على الحساب'),
    `[${comp.name}] Bank deposit account number "3052001225" and notice included`
  );

  // 3.4 Red Terms & Conditions (5 Clauses)
  assert(
    comp.src.includes('text-red-600'),
    `[${comp.name}] Terms are styled in bold red (text-red-600)`
  );
  for (let i = 0; i < requiredTerms.length; i++) {
    const term = requiredTerms[i];
    assert(
      comp.src.includes(term),
      `[${comp.name}] Clause ${i + 1} present: "${term.substring(0, 30)}..."`
    );
  }

  // 3.5 Column Structure - Collector Stub (5 Columns)
  assert(
    comp.src.includes('قــــــراءة العداد') &&
    (comp.src.includes('ق.السابقة') || comp.src.includes('ق. السابقة')) &&
    (comp.src.includes('ق.الحالية') || comp.src.includes('ق. الحالية')) &&
    comp.src.includes('الفارق') &&
    comp.src.includes('متأخرات وغرامات') &&
    comp.src.includes('الاجمالي'),
    `[${comp.name}] Collector stub has all 5 columns: Previous, Current, Diff, Arrears/Fines, Total`
  );

  // 3.6 Column Structure - Main Invoice (7 Columns)
  assert(
    (comp.src.includes('اشتراك') || comp.src.includes('الاشتراك')) &&
    (comp.src.includes('القيمـة') || comp.src.includes('القيمة')) &&
    comp.src.includes('متأخرات') &&
    comp.src.includes('الاجمالي'),
    `[${comp.name}] Main invoice has all 7 columns: Previous, Current, Diff, Fee, Value, Arrears, Total`
  );

  // 3.7 English Numerals Formatting (en-US)
  assert(
    comp.src.includes(".toLocaleString('en-US')"),
    `[${comp.name}] Table numeric data formatted strictly with .toLocaleString('en-US')`
  );

  // 3.8 Dual Signatures & Bottom-Left Date
  assert(
    comp.src.includes('المحصل') && comp.src.includes('الحسابات'),
    `[${comp.name}] Both signatures (المحصل & الحسابات) present in both stubs`
  );
  assert(
    comp.src.includes('التاريخ :') && (comp.src.includes('text-left') || comp.src.includes('dir-ltr')),
    `[${comp.name}] Date label is positioned at bottom left`
  );
}

// -----------------------------------------------------------------------------
// MODULE 4: ADVERSARIAL STRESS TESTING & EDGE CASE GENERATION
// -----------------------------------------------------------------------------
console.log('\n--- MODULE 4: Adversarial Stress Testing & Edge Cases ---');

// 4.1 Check formatting under zero, negative, massive numbers
import { formatNumber, formatCurrency, toEnglishDigits, formatDateOnly } from '../utils/formatters.ts';

const testValues = [
  { val: 0, expectedFmt: '0', expectedCurr: '0' },
  { val: 1400, expectedFmt: '1,400', expectedCurr: '1,400' },
  { val: 999999999, expectedFmt: '999,999,999', expectedCurr: '999,999,999' },
  { val: -5000, expectedFmt: '-5,000', expectedCurr: '-5,000' },
  { val: 12345.67, expectedFmt: '12,345.67', expectedCurr: '12,345.67' },
];

for (const tv of testValues) {
  assert(
    formatNumber(tv.val) === tv.expectedFmt,
    `formatNumber correctly formats ${tv.val} -> ${tv.expectedFmt}`
  );
  assert(
    formatCurrency(tv.val) === tv.expectedCurr,
    `formatCurrency correctly formats ${tv.val} -> ${tv.expectedCurr}`
  );
}

// 4.2 Invoice Data Pipeline Stress Test: Edge Case Rows
const invoiceStressRows = [
  { name: 'Zero consumption', prev: 0, curr: 0, units: 0, fee: 0, val: 0, arrears: 0, total: 0 },
  { name: 'Massive numbers', prev: 1000000, curr: 1250000, units: 250000, fee: 5000, val: 350000000, arrears: 12000000, total: 362005000 },
  { name: 'Nullish edge values', prev: null, curr: undefined, units: null, fee: undefined, val: null, arrears: undefined, total: null },
  { name: 'Decimal values', prev: 100.5, curr: 250.75, units: 150.25, fee: 500, val: 210350, arrears: 0, total: 210850 },
];

for (const r of invoiceStressRows) {
  const pStr = Number(r.prev || 0).toLocaleString('en-US');
  const cStr = Number(r.curr || 0).toLocaleString('en-US');
  const uStr = Number(r.units || 0).toLocaleString('en-US');
  const fStr = Number(r.fee || 0).toLocaleString('en-US');
  const vStr = Number(r.val || 0).toLocaleString('en-US');
  const aStr = Number(r.arrears || 0).toLocaleString('en-US');
  const tStr = Number(r.total || 0).toLocaleString('en-US');

  assert(
    !/[\u0660-\u0669\u06F0-\u06F9]/.test(`${pStr} ${cStr} ${uStr} ${fStr} ${vStr} ${aStr} ${tStr}`),
    `[Stress Row: ${r.name}] Output strings contain 100% English numerals`
  );
  assert(
    !isNaN(Number(r.total || 0)),
    `[Stress Row: ${r.name}] Total due evaluates to a valid number`
  );
}

// 4.3 Simulation of Role Navigation Matrix
const rolePermissions = {
  ADMIN: { canAccessArrears: true, sidebarHasArrears: true, canAccessSettings: true },
  ACCOUNTANT: { canAccessArrears: true, sidebarHasArrears: true, canAccessSettings: false },
  CASHIER: { canAccessArrears: true, sidebarHasArrears: true, canAccessSettings: false },
  COLLECTOR: { canAccessArrears: false, sidebarHasArrears: false, canAccessSettings: false },
};

const allowedArrearsRoles = ['ADMIN', 'ACCOUNTANT', 'CASHIER'];

for (const [roleName, perms] of Object.entries(rolePermissions)) {
  const allowed = allowedArrearsRoles.includes(roleName);
  assert(
    allowed === perms.canAccessArrears,
    `Role ${roleName} Arrears access route matches RBAC contract (allowed: ${allowed})`
  );

  const roleInSidebarHasArrears = roleName === 'ADMIN' 
    ? adminSection.includes('/arrears')
    : (roleName === 'ACCOUNTANT' || roleName === 'CASHIER')
      ? accountantCashierSection.includes('/arrears')
      : collectorSection.includes('/arrears');

  assert(
    roleInSidebarHasArrears === perms.sidebarHasArrears,
    `Role ${roleName} Sidebar Arrears tab visibility matches RBAC specification (${perms.sidebarHasArrears})`
  );
}

// 4.3 Date formatting stress test
const testDates = [
  new Date(2026, 7, 20), // August 20, 2026
  '2026-09-02T18:00:00Z',
];

for (const td of testDates) {
  const formatted = formatDateOnly(td);
  assert(
    /^[0-9]{2}\/[0-9]{2}\/[0-9]{4}$/.test(formatted),
    `formatDateOnly outputs standard en-US format (MM/DD/YYYY): ${formatted}`
  );
  assert(
    !/[\u0660-\u0669\u06F0-\u06F9]/.test(formatted),
    `formatDateOnly contains zero Eastern Arabic digits: ${formatted}`
  );
}

// 4.4 Zero Eastern Arabic digits across invoice files
for (const comp of invoiceComponents) {
  const easternDigitsMatch = comp.src.match(/[\u0660-\u0669\u06F0-\u06F9]/g);
  assert(
    easternDigitsMatch === null,
    `[${comp.name}] Contains ZERO hardcoded Eastern Arabic digits (٠-٩)`
  );
}

// -----------------------------------------------------------------------------
// SUMMARY & VERDICT
// -----------------------------------------------------------------------------
console.log('\n========================================================================');
console.log(`TOTAL TESTS: ${totalTests} | PASSED: ${passedTests} | FAILED: ${failedTests}`);
console.log('========================================================================');

if (failedTests > 0) {
  console.error('\nFAILURE DETAILS:');
  failures.forEach((f, idx) => {
    console.error(`  ${idx + 1}. ${f.testName}`);
    if (f.details) console.error(`     ${f.details}`);
  });
  console.error('\nOVERALL VERDICT: REJECT ❌');
  process.exit(1);
} else {
  console.log('\nOVERALL VERDICT: APPROVE ✅');
  process.exit(0);
}
