import { validateYemeniPhone } from '../utils/phoneValidation.ts';
import { formatYemeniPhone, buildWhatsAppText, computeRowFinancials, buildWarningNoticeText } from '../types/excelGrid.types.ts';

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
console.log('TEST SUITE 2: WhatsApp URL Construction & Yemeni Phone Sanitization');
console.log('===============================================================');

// 1. Phone Number Sanitization Tests (`formatYemeniPhone`)
console.log('\n[1] Testing formatYemeniPhone across standard & edge-case formats...');

const phoneTestCases = [
  { input: '771234567', expected: '967771234567', desc: 'Standard 9-digit mobile (77)' },
  { input: '0771234567', expected: '967771234567', desc: 'Mobile with leading 0 (077)' },
  { input: '967771234567', expected: '967771234567', desc: 'Already prefixed with 967' },
  { input: '00967771234567', expected: '967771234567', desc: 'Prefixed with 00967' },
  { input: '+967 771 234 567', expected: '967771234567', desc: 'Prefixed with +967 and spaces' },
  { input: '+967-771-234-567', expected: '967771234567', desc: 'Prefixed with +967 and hyphens' },
  { input: '(077) 123-4567', expected: '967771234567', desc: 'Formatted with parentheses and hyphens' },
  { input: '781234567', expected: '967781234567', desc: 'Yemen Mobile 4G prefix (78)' },
  { input: '731234567', expected: '967731234567', desc: 'You/MTN prefix (73)' },
  { input: '711234567', expected: '967711234567', desc: 'Sabafon prefix (71)' },
  { input: '701234567', expected: '967701234567', desc: 'Y Telecom prefix (70)' },
  { input: '', expected: '', desc: 'Empty string returns empty' },
  { input: null, expected: '', desc: 'Null returns empty' },
  { input: undefined, expected: '', desc: 'Undefined returns empty' },
  { input: '   ', expected: '', desc: 'Whitespace string returns empty' },
  { input: 'abc-xyz', expected: '', desc: 'Alphabetic string returns empty' },
];

phoneTestCases.forEach((tc) => {
  const result = formatYemeniPhone(tc.input);
  assert(result === tc.expected, `formatYemeniPhone: ${tc.desc}`, `Got: "${result}", Expected: "${tc.expected}"`);
});

// 2. Phone Validation Tests (`validateYemeniPhone`)
console.log('\n[2] Testing validateYemeniPhone operator prefix enforcement...');

const validationCases = [
  { input: '771234567', valid: true, formatted: '771234567', desc: 'Valid 77 number' },
  { input: '0781234567', valid: true, formatted: '781234567', desc: 'Valid 78 number with leading 0' },
  { input: '967731234567', valid: true, formatted: '731234567', desc: 'Valid 73 number with 967' },
  { input: '+967 711 234 567', valid: true, formatted: '711234567', desc: 'Valid 71 number with formatting' },
  { input: '0701234567', valid: true, formatted: '701234567', desc: 'Valid 70 number with leading 0' },
  { input: '721234567', valid: false, desc: 'Invalid prefix 72' },
  { input: '751234567', valid: false, desc: 'Invalid prefix 75' },
  { input: '791234567', valid: false, desc: 'Invalid prefix 79' },
  { input: '7712345', valid: false, desc: 'Short number (7 digits)' },
  { input: '771234567890', valid: false, desc: 'Long number (>9 digits)' },
  { input: '', valid: false, desc: 'Empty number' },
];

validationCases.forEach((tc) => {
  const res = validateYemeniPhone(tc.input);
  if (tc.valid) {
    assert(res.isValid && res.formatted === tc.formatted, `validateYemeniPhone: ${tc.desc}`, `Got: ${JSON.stringify(res)}`);
  } else {
    assert(!res.isValid && !!res.error, `validateYemeniPhone: ${tc.desc} fails cleanly with error message`);
  }
});

// 3. Invoice WhatsApp Text & URL Construction (`buildWhatsAppText` & `wa.me`)
console.log('\n[3] Testing buildWhatsAppText invoice template & wa.me URL builder...');

const mockRow = computeRowFinancials({
  id: 101,
  subNumber: 'SUB-4092',
  route: 'R-05',
  name: 'محمد علي الحبيشي',
  address: 'صنعاء - شارع تعز',
  meterNumber: 'MTR-8821',
  phone: '771234567',
  prevReading: 1200,
  currReading: 1350,
  lostUnits: 15,
  unitPrice: 1400,
  serviceFee: 1000,
  arrears: 5000,
  paidAmount: 200000,
  sent: false,
});

const periodName = 'أغسطس - 2026';
const waText = buildWhatsAppText(mockRow, periodName);

assert(waText.includes('*فاتورة استهلاك الطاقة الكهربائية*'), 'Contains official title header');
assert(waText.includes('*المشترك:* محمد علي الحبيشي'), 'Contains customer name');
assert(waText.includes('*رقم الاشتراك:* SUB-4092'), 'Contains subscriber number');
assert(waText.includes('*رقم العداد:* MTR-8821'), 'Contains meter number');
assert(waText.includes('*العنوان:* صنعاء - شارع تعز'), 'Contains address');
assert(waText.includes('*الفترة:* أغسطس - 2026'), 'Contains period');
assert(waText.includes('*القراءة السابقة:* 1,200'), 'Previous reading uses English numerals formatting (1,200)');
assert(waText.includes('*القراءة الحالية:* 1,350'), 'Current reading uses English numerals formatting (1,350)');
assert(waText.includes('*كمية الاستهلاك:* 150 ك.و'), 'Consumption units computed correctly (150)');
assert(waText.includes('*سعر الوحدة:* 1,400 ريال'), 'Unit price formatted correctly');
assert(waText.includes('*قيمة الاستهلاك:* 210,000 ريال'), 'Consumption cost computed correctly (150 * 1400 = 210,000)');
assert(waText.includes('*رسوم الخدمة:* 1,000 ريال'), 'Service fee formatted correctly');
assert(waText.includes('*المتأخرات السابقة:* 5,000 ريال'), 'Arrears formatted correctly');
// Total Due = 210,000 + 1,000 + 5,000 = 216,000
assert(waText.includes('*إجمالي المستحق:* 216,000 ريال'), 'Total due includes consumption + fee + arrears (216,000)');
assert(waText.includes('*المبلغ المدفوع:* 200,000 ريال'), 'Paid amount formatted correctly (200,000)');
assert(waText.includes('*المبلغ المتبقي:* 16,000 ريال'), 'Remaining balance formatted correctly (16,000)');

// Test URL generation
const phoneFormatted = formatYemeniPhone(mockRow.phone);
const generatedUrl = `https://wa.me/${phoneFormatted}?text=${encodeURIComponent(waText)}`;

assert(generatedUrl.startsWith('https://wa.me/967771234567?text='), 'WhatsApp URL starts with https://wa.me/967771234567?text=');
const parsedUrl = new URL(generatedUrl);
const decodedText = parsedUrl.searchParams.get('text');
assert(decodedText === waText, 'URL encoded text round-trips with 100% fidelity');

// 4. Special Characters and Extreme Value Stress Testing
console.log('\n[4] Adversarial Stress Testing: Special characters, zeros, large numbers...');

const stressRow = computeRowFinancials({
  id: 999,
  subNumber: 'SPEC & <SUB> #1',
  route: 'R/01',
  name: 'مؤسسة "النجاح & الأمل" <التجارية>',
  address: 'صنعاء / حدة #2 (عمارة 5)',
  meterNumber: 'M-000000',
  phone: '00967-78-999-8888',
  prevReading: 0,
  currReading: 1000000,
  lostUnits: 50000,
  unitPrice: 2500,
  serviceFee: 10000,
  arrears: 15000000,
  paidAmount: 0,
});

const stressWaText = buildWhatsAppText(stressRow, 'دورة خاصة #2026');
const stressPhone = formatYemeniPhone(stressRow.phone);
const stressUrl = `https://wa.me/${stressPhone}?text=${encodeURIComponent(stressWaText)}`;

assert(stressPhone === '967789998888', 'Stress phone sanitized from 00967-78-999-8888 to 967789998888');
assert(stressWaText.includes('مؤسسة "النجاح & الأمل" <التجارية>'), 'Special characters in name preserved in text');
assert(stressWaText.includes('1,000,000'), 'Large million reading formatted cleanly (1,000,000)');
assert(stressUrl.includes('https://wa.me/967789998888?text='), 'Stress URL successfully generated');

// 5. Warning Notice Text Verification (`buildWarningNoticeText`)
console.log('\n[5] Testing buildWarningNoticeText for disconnection notices...');

const warningItem = {
  customer: {
    id: 42,
    subscriber_number: 'SUB-7701',
    full_name: 'صالح أحمد مقبل',
    meter_number: 'MTR-3399',
    phone_number: '733112233',
    address: 'إب - الدائري الغربي',
  },
  total_arrears: 85000,
  days_overdue: 45,
};

const warningText = buildWarningNoticeText(warningItem);

assert(warningText.includes('*إشعار إنذار رسمي بالسداد وفصل الخدمة*'), 'Contains warning notice header');
assert(warningText.includes('*المشترك:* صالح أحمد مقبل'), 'Contains defaulter customer name');
assert(warningText.includes('*مدة التأخير:* 45 يوماً'), 'Contains overdue days in English numerals (45)');
assert(warningText.includes('*إجمالي المديونية المتأخرة:* 85,000 ريال يمني'), 'Contains total arrears in English numerals (85,000)');
assert(warningText.includes('خلال 48 ساعة لتجنب فصل التيار الكهربائي'), 'Contains 48-hour cutoff warning');

// 6. Challenger 1 Edge Case Validations: Eastern Arabic Numeral Computations
console.log('\n[6] Testing Eastern Arabic Digits across computeRowFinancials & buildWhatsAppText...');

const easternRow = computeRowFinancials({
  id: 202,
  subNumber: 'SUB-202',
  route: 'R-02',
  name: 'عبدالله الأهدل',
  address: 'الحديدة',
  meterNumber: 'MTR-9900',
  phone: '\u0660\u0667\u0667\u0661\u0662\u0663\u0664\u0665\u0666\u0667', // ٠٧٧١٢٣٤٥٦٧
  prevReading: '\u0661\u0660\u0660\u0660', // ١٠٠٠ -> 1000
  currReading: '\u0661\u0662\u0665\u0660', // ١٢٥٠ -> 1250
  lostUnits: '\u0661\u0660', // ١٠ -> 10
  unitPrice: '\u0661\u0664\u0660\u0660', // ١٤٠٠ -> 1400
  serviceFee: '\u0661\u0660\u0660\u0660', // ١٠٠٠ -> 1000
  arrears: '\u0665\u0660\u0660\u0660', // ٥٠٠٠ -> 5000
  paidAmount: '\u0662\u0660\u0660\u0660\u0660\u0660', // ٢٠٠٠٠٠ -> 200000
});

assert(easternRow.units === 250, 'Eastern digits parsed in computeRowFinancials: units = 250 (1250 - 1000)');
assert(easternRow.consumptionCost === 350000, 'Eastern digits consumptionCost = 350,000 (250 * 1400)');
assert(easternRow.lostUnitsCost === 14000, 'Eastern digits lostUnitsCost = 14,000 (10 * 1400)');
assert(easternRow.totalDue === 356000, 'Eastern digits totalDue = 356,000 (350k + 1k + 5k)');
assert(easternRow.remaining === 156000, 'Eastern digits remaining = 156,000 (356k - 200k)');

const easternWaText = buildWhatsAppText(easternRow, 'سبتمبر 2026');
assert(!easternWaText.includes('NaN'), 'buildWhatsAppText with Eastern inputs produces ZERO NaN');
assert(easternWaText.includes('1,250'), 'buildWhatsAppText current reading formatted with English comma (1,250)');
assert(easternWaText.includes('356,000'), 'buildWhatsAppText total due formatted with English comma (356,000)');
assert(easternWaText.includes('156,000'), 'buildWhatsAppText remaining formatted with English comma (156,000)');
assert(!/[\u0660-\u0669\u06F0-\u06F9]/.test(easternWaText), 'buildWhatsAppText outputs 100% English numerals');

const easternPhone = formatYemeniPhone(easternRow.phone);
assert(easternPhone === '967771234567', 'formatYemeniPhone handles Eastern Arabic phone: 967771234567');

console.log('\n---------------------------------------------------------------');
console.log(`Summary: ${passedTests}/${totalTests} tests passed (${failedTests} failed).`);
if (failedTests > 0) {
  process.exit(1);
} else {
  console.log('✓ ALL WHATSAPP & PHONE SANITIZATION TESTS PASSED SUCCESSFULLY!');
}
