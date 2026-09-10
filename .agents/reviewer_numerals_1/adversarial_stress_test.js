import {
  toEnglishDigits,
  sanitizeDecimalInput,
  sanitizeIntegerInput,
  formatCurrency,
  formatDate,
  formatDateOnly,
  formatMonth,
  formatNumber,
} from '../../frontend/src/utils/formatters.ts';

let passed = 0;
let failed = 0;

function test(name, actual, expected) {
  if (actual === expected) {
    passed++;
    console.log(`[PASS] ${name}: ${JSON.stringify(actual)} === ${JSON.stringify(expected)}`);
  } else {
    failed++;
    console.error(`[FAIL] ${name}: Got ${JSON.stringify(actual)}, Expected ${JSON.stringify(expected)}`);
  }
}

console.log('--- 1. Intermediate Typing & Dot Preservation ---');
test('Intermediate typing "12."', sanitizeDecimalInput('12.'), '12.');
test('Intermediate typing "0."', sanitizeDecimalInput('0.'), '0.');
test('Intermediate typing single dot "."', sanitizeDecimalInput('.'), '.');
test('Intermediate typing zero with decimals "0.0"', sanitizeDecimalInput('0.0'), '0.0');
test('Intermediate typing "0.00"', sanitizeDecimalInput('0.00'), '0.00');
test('Intermediate typing "12.05"', sanitizeDecimalInput('12.05'), '12.05');

console.log('\n--- 2. Arabic Numerals & Separators Conversion ---');
test('Eastern Arabic digits "١٢٣٤٥"', toEnglishDigits('١٢٣٤٥'), '12345');
test('Persian digits "۱۲۳۴۵"', toEnglishDigits('۱۲۳۴۵'), '12345');
test('Eastern Arabic decimal "١٢.٥"', sanitizeDecimalInput('١٢.٥'), '12.5');
test('Arabic decimal separator "١٢٫٥" (\\u066B)', sanitizeDecimalInput('١٢٫٥'), '12.5');
test('Arabic thousands separator "١٢٬٥" (\\u066C)', sanitizeDecimalInput('١٢٬٥'), '12.5');
test('Arabic comma "١٢،٥" (\\u060C)', sanitizeDecimalInput('١٢،٥'), '12.5');
test('ASCII comma "12,5"', sanitizeDecimalInput('12,5'), '12.5');
test('Trailing Arabic comma "١٢٫"', sanitizeDecimalInput('١٢٫'), '12.');
test('Trailing Arabic comma "١٢،"', sanitizeDecimalInput('١٢،'), '12.');

console.log('\n--- 3. Multiple Separators & Adversarial Edge Cases ---');
test('Double dots "12..5"', sanitizeDecimalInput('12..5'), '12.5');
test('Triple dots "12...5"', sanitizeDecimalInput('12...5'), '12.5');
test('Multiple decimal points "12.34.56"', sanitizeDecimalInput('12.34.56'), '12.3456');
test('Multiple Arabic commas "١٢٫٣٤٫٥٦"', sanitizeDecimalInput('١٢٫٣٤٫٥٦'), '12.3456');
test('Mixed dots and commas "١٢.٣٤٫٥٦,٧٨"', sanitizeDecimalInput('١٢.٣٤٫٥٦,٧٨'), '12.345678');
test('Leading dots "..5"', sanitizeDecimalInput('..5'), '.5');
test('Surrounding garbage " ر.ي 1,250.75 YER "', sanitizeDecimalInput(' ر.ي 1,250.75 YER '), '1.25075');
test('Empty string ""', sanitizeDecimalInput(''), '');
test('null', sanitizeDecimalInput(null), '');
test('undefined', sanitizeDecimalInput(undefined), '');
test('number 42', sanitizeDecimalInput(42), '42');
test('number 42.5', sanitizeDecimalInput(42.5), '42.5');

console.log('\n--- 4. Integer Sanitizer ---');
test('Integer Eastern digits "٠٧٧١٢٣٤٥٦٧"', sanitizeIntegerInput('٠٧٧١٢٣٤٥٦٧'), '0771234567');
test('Integer with dashes "77-123-4567"', sanitizeIntegerInput('77-123-4567'), '771234567');
test('Integer with letters "MTR-998811"', sanitizeIntegerInput('MTR-998811'), '998811');
test('Integer null', sanitizeIntegerInput(null), '');
test('Integer empty', sanitizeIntegerInput(''), '');

console.log('\n--- 5. Currency & Date Formatters ---');
test('formatCurrency 0', formatCurrency(0), '0');
test('formatCurrency 28500', formatCurrency(28500), '28,500');
test('formatCurrency 28500.5', formatCurrency(28500.5), '28,500.5');
test('formatCurrency 28500.75', formatCurrency(28500.75), '28,500.75');

const d = new Date('2026-09-02T15:30:00Z');
const fDate = formatDate(d);
test('formatDate contains no Eastern Arabic digits', /[\u0660-\u0669\u06F0-\u06F9]/.test(fDate), false);
test('formatDate uses en-US slash format', /\d{2}\/\d{2}\/\d{4}/.test(fDate), true);

const fMonth = formatMonth(d);
test('formatMonth contains Arabic month name "سبتمبر"', fMonth.includes('سبتمبر'), true);
test('formatMonth contains English year "2026"', fMonth.includes('2026'), true);
test('formatMonth contains no Eastern Arabic digits', /[\u0660-\u0669\u06F0-\u06F9]/.test(fMonth), false);

console.log(`\n================================`);
console.log(`Total Passed: ${passed}, Total Failed: ${failed}`);
if (failed > 0) process.exit(1);
