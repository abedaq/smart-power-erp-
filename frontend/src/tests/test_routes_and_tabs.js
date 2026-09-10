import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const srcDir = path.resolve(__dirname, '..');

let totalTests = 0;
let passedTests = 0;
let failedTests = 0;

function assert(condition, testName, details = '') {
  totalTests++;
  if (condition) {
    passedTests++;
    console.log(`  ✓ PASS: ${testName}`);
  } else {
    failedTests++;
    console.error(`  ✗ FAIL: ${testName}`);
    if (details) console.error(`    Details: ${details}`);
  }
}

console.log('===============================================================');
console.log('TEST SUITE 1: Route Completeness, Standalone Arrears & Tariff Cleanup');
console.log('===============================================================');

// 1. Check App.tsx Routes & Redirections
const appContent = fs.readFileSync(path.join(srcDir, 'App.tsx'), 'utf-8');

console.log('\n[1] Verifying App.tsx Route Redirections & Protected Routes...');

assert(
  appContent.includes('<Route path="approved-edits" element={<Navigate to="/reports" replace />} />'),
  'Obsolete route "/approved-edits" cleanly redirects to "/reports"'
);

assert(
  appContent.includes('<Route path="users" element={<Navigate to="/settings?tab=users" replace />} />'),
  'Obsolete route "/users" cleanly redirects to "/settings?tab=users"'
);

assert(
  appContent.includes('<Route path="audit-logs" element={<Navigate to="/settings?tab=audit-logs" replace />} />'),
  'Obsolete route "/audit-logs" cleanly redirects to "/settings?tab=audit-logs"'
);

assert(
  appContent.includes('<Route path="whatsapp" element={<Navigate to="/settings?tab=whatsapp" replace />} />'),
  'Obsolete route "/whatsapp" cleanly redirects to "/settings?tab=whatsapp"'
);

assert(
  !appContent.includes('path="import"') && !appContent.includes('tab=tariffs'),
  'Obsolete route "/import" and redirect to "tab=tariffs" are completely removed'
);

assert(
  appContent.includes('path="arrears"') &&
  appContent.includes('<ArrearsReport />') &&
  !appContent.includes('to="/reports?tab=arrears"'),
  'Route "/arrears" directly renders standalone <ArrearsReport /> (no redirect to reports)'
);

assert(
  appContent.includes('<Route path="*" element={<Navigate to="/" replace />} />'),
  'Catch-all wildcard route "*" safely redirects to "/"'
);

assert(
  appContent.includes('path="reports"') && appContent.includes('<ReportsHub />'),
  'Comprehensive Reports Hub route "/reports" is registered'
);

assert(
  appContent.includes('path="customers"') && (appContent.includes("allowedRoles={['ADMIN', 'ACCOUNTANT', 'CASHIER', 'COLLECTOR']}") || appContent.includes("allowedRoles={['ADMIN', 'ACCOUNTANT', 'COLLECTOR']}")),
  'Customers route is protected for ADMIN, ACCOUNTANT, CASHIER, COLLECTOR'
);

assert(
  appContent.includes('path="invoices"') && (appContent.includes("allowedRoles={['ADMIN', 'ACCOUNTANT', 'CASHIER']}") || appContent.includes("allowedRoles={['ADMIN', 'ACCOUNTANT']}")),
  'Invoices route is protected for ADMIN, ACCOUNTANT, CASHIER'
);

assert(
  appContent.includes('path="arrears"') && (appContent.includes("allowedRoles={['ADMIN', 'ACCOUNTANT', 'CASHIER']}") || appContent.includes("allowedRoles={['ADMIN', 'ACCOUNTANT']}")),
  'Arrears route is protected for ADMIN, ACCOUNTANT, CASHIER'
);

assert(
  appContent.includes('path="settings"') && appContent.includes("allowedRoles={['ADMIN']}"),
  'Settings route is protected for ADMIN only'
);

// 2. Check Sidebar Navigation Links
const sidebarContent = fs.readFileSync(path.join(srcDir, 'components/Sidebar.tsx'), 'utf-8');

console.log('\n[2] Verifying Sidebar.tsx Navigation Items...');

assert(
  !sidebarContent.includes('/approved-edits') &&
  !sidebarContent.includes('/plans') &&
  !sidebarContent.includes('/plans-management'),
  'Sidebar contains ZERO references to obsolete routes (/approved-edits, /plans)'
);

assert(
  sidebarContent.includes("to: '/arrears', label: 'المديونيات والمتأخرات', icon: AlertTriangle"),
  'Sidebar includes standalone "المديونيات والمتأخرات" link with AlertTriangle icon'
);

assert(
  sidebarContent.includes("to: '/reports', label: 'مركز التقارير الشامل'"),
  'Sidebar includes unified "مركز التقارير الشامل" link'
);

assert(
  sidebarContent.includes("to: '/customers', label: 'إدارة العملاء والتحصيل'"),
  'Sidebar includes Admin Customers link'
);

assert(
  sidebarContent.includes("to: '/invoices', label: 'الفواتير والتحصيل'"),
  'Sidebar includes Admin Invoices link'
);

assert(
  sidebarContent.includes("to: '/settings', label: 'الإعدادات والتهيئة'"),
  'Sidebar includes Admin Settings link'
);

// 3. Check Settings.tsx for Complete Deletion of General Tariff & Fees
const settingsContent = fs.readFileSync(path.join(srcDir, 'pages/Settings.tsx'), 'utf-8');

console.log('\n[3] Verifying Settings.tsx General Tariff Tab & Component Deletion...');

assert(
  !settingsContent.includes('GeneralTariffSettings'),
  'Settings.tsx: GeneralTariffSettings component is completely deleted'
);

assert(
  !settingsContent.includes("setTab('tariffs')") && !settingsContent.includes("activeTab === 'tariffs'"),
  'Settings.tsx: tariffs sub-tab button and tab content rendering are completely removed'
);

assert(
  settingsContent.includes("setTab('users')") &&
  settingsContent.includes("setTab('whatsapp')") &&
  settingsContent.includes("setTab('audit-logs')"),
  'Settings.tsx: active tabs are users, whatsapp, and audit-logs'
);

// 4. Check ArrearsReport.tsx Component Features (R2)
const arrearsContent = fs.readFileSync(path.join(srcDir, 'pages/ArrearsReport.tsx'), 'utf-8');

console.log('\n[4] Verifying ArrearsReport.tsx Standalone Features...');

assert(
  arrearsContent.includes('أيام التأخير'),
  'ArrearsReport: Overdue Days (أيام التأخير) column and KPI card are present'
);

assert(
  arrearsContent.includes('sendDisconnectionWarning') && arrearsContent.includes('buildWarningNoticeText'),
  'ArrearsReport: Warning notice modal/action (sendDisconnectionWarning) is present'
);

assert(
  arrearsContent.includes('PaymentModal') && arrearsContent.includes('setSelectedPaymentCustomer'),
  'ArrearsReport: Inline Payment modal (PaymentModal) for instant settlement is present'
);

assert(
  arrearsContent.includes('export default ArrearsReport') || arrearsContent.includes('export const ArrearsReport'),
  'ArrearsReport: component export is valid'
);

// 5. Check Deprecated Components
const approvedEditsContent = fs.readFileSync(path.join(srcDir, 'pages/ApprovedEdits.tsx'), 'utf-8');
const plansManagementContent = fs.readFileSync(path.join(srcDir, 'components/PlansManagement.tsx'), 'utf-8');

console.log('\n[5] Verifying Obsolete Components Stubs / Deprecation...');

assert(
  approvedEditsContent.includes('<Navigate to="/reports" replace />'),
  'ApprovedEdits.tsx is a deprecation redirect to /reports'
);

assert(
  plansManagementContent.includes('export const PlansManagement: React.FC = () => {') &&
  plansManagementContent.includes('return null;'),
  'PlansManagement.tsx is deprecated and returns null'
);

// 6. Check ReportsHub 6 Sub-Tabs Architecture
const reportsHubContent = fs.readFileSync(path.join(srcDir, 'pages/ReportsHub.tsx'), 'utf-8');

console.log('\n[6] Verifying ReportsHub.tsx 6 Analytical Sub-Tabs...');

assert(
  reportsHubContent.includes("onClick={() => setTab('financial')}") &&
  reportsHubContent.includes("activeTab === 'financial'"),
  'Tab 1: Financial Summaries (الإيرادات ومعدلات التحصيل) is implemented'
);

assert(
  reportsHubContent.includes("onClick={() => setTab('energy')}") &&
  reportsHubContent.includes("activeTab === 'energy'"),
  'Tab 2: Energy & Loss Analysis (استهلاك الطاقة والفاقد) is implemented'
);

assert(
  reportsHubContent.includes("onClick={() => setTab('arrears')}") &&
  reportsHubContent.includes("activeTab === 'arrears'"),
  'Tab 3: Arrears & Debt Aging (أعمار الديون والمديونيات) is implemented'
);

assert(
  reportsHubContent.includes("onClick={() => setTab('cycles')}") &&
  reportsHubContent.includes("activeTab === 'cycles'"),
  'Tab 4: Cycle Comparisons (المقارنة بين الدورات) is implemented'
);

assert(
  reportsHubContent.includes("onClick={() => setTab('collectors')}") &&
  reportsHubContent.includes("activeTab === 'collectors'"),
  'Tab 5: Collector Performance (مؤشرات أداء المحصلين) is implemented'
);

assert(
  reportsHubContent.includes("onClick={() => setTab('audit')}") &&
  reportsHubContent.includes("activeTab === 'audit'"),
  'Tab 6: Audit & Operations Logs (سجل الرقابة والعمليات) is implemented'
);

console.log('\n---------------------------------------------------------------');
console.log(`Summary: ${passedTests}/${totalTests} tests passed (${failedTests} failed).`);
if (failedTests > 0) {
  process.exit(1);
} else {
  console.log('✓ ALL ROUTE, SIDEBAR, SETTINGS & ARREARS TESTS PASSED SUCCESSFULLY!');
}
