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
console.log('TEST SUITE 3: Strict English Numerals Global Scanner & Sanitizers');
console.log('===============================================================');

function getAllFiles(dir, fileList = []) {
  const files = fs.readdirSync(dir);
  files.forEach((file) => {
    const fullPath = path.join(dir, file);
    if (fs.statSync(fullPath).isDirectory()) {
      if (!file.includes('node_modules') && !file.includes('.git') && !file.includes('dist')) {
        getAllFiles(fullPath, fileList);
      }
    } else {
      if (/\.(tsx?|jsx?|html|json|css)$/i.test(file)) {
        fileList.push(fullPath);
      }
    }
  });
  return fileList;
}

const sourceFiles = getAllFiles(srcDir);
console.log(`\n[1] Scanning ${sourceFiles.length} source files in frontend/src for Eastern Arabic digits (٠-٩) in code and UI strings...`);

const arabicIndicRegex = /[\u0660-\u0669\u06F0-\u06F9]/g;

let uiArabicDigitViolations = [];
let commentArabicDigitMentions = [];

sourceFiles.forEach((filePath) => {
  if (filePath.includes('tests\\') || filePath.includes('tests/')) return;

  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split('\n');

  lines.forEach((line, idx) => {
    const trimmed = line.trim();
    const match = trimmed.match(arabicIndicRegex);
    if (match) {
      if (trimmed.startsWith('*') || trimmed.startsWith('//') || trimmed.startsWith('/*')) {
        commentArabicDigitMentions.push({
          file: path.relative(srcDir, filePath),
          line: idx + 1,
          content: trimmed,
        });
      } else {
        uiArabicDigitViolations.push({
          file: path.relative(srcDir, filePath),
          line: idx + 1,
          content: trimmed,
          matchedDigits: match.join(', '),
        });
      }
    }
  });
});

assert(
  uiArabicDigitViolations.length === 0,
  `Zero Arabic-Indic digits (٠-٩) in UI code & templates (Found ${uiArabicDigitViolations.length})`,
  uiArabicDigitViolations.length > 0 ? JSON.stringify(uiArabicDigitViolations) : ''
);

console.log(`  (Informational: Found ${commentArabicDigitMentions.length} explanatory mentions of ٠-٩ in comment documentation in formatters.ts)`);

// [2] Scan for any leftover type="number" inputs
console.log('\n[2] Scanning for any leftover uncontrolled type="number" in frontend/src...');

let typeNumberOccurrences = [];
sourceFiles.forEach((filePath) => {
  if (!/\.(tsx|jsx)$/i.test(filePath)) return;
  if (filePath.includes('tests\\') || filePath.includes('tests/')) return;

  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split('\n');

  lines.forEach((line, idx) => {
    if (/type=["']number["']/.test(line)) {
      typeNumberOccurrences.push({
        file: path.relative(srcDir, filePath),
        line: idx + 1,
        content: line.trim(),
      });
    }
  });
});

assert(
  typeNumberOccurrences.length === 0,
  `Zero uncontrolled type="number" inputs found in frontend components (Found ${typeNumberOccurrences.length})`,
  typeNumberOccurrences.length > 0 ? JSON.stringify(typeNumberOccurrences) : ''
);

// [3] Scan for toLocaleString / toLocaleDateString locale parameter
console.log('\n[3] Checking toLocaleString() & toLocaleDateString() locale specification...');

let nonEnUsCalls = [];
sourceFiles.forEach((filePath) => {
  if (filePath.includes('tests\\') || filePath.includes('tests/')) return;

  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split('\n');

  lines.forEach((line, idx) => {
    if (line.includes('toLocaleString()') || line.includes("toLocaleDateString('ar")) {
      nonEnUsCalls.push({
        file: path.relative(srcDir, filePath),
        line: idx + 1,
        content: line.trim(),
      });
    }
  });
});

assert(
  nonEnUsCalls.length === 0,
  `Zero non-en-US locale calls across all frontend source files (Found ${nonEnUsCalls.length})`,
  nonEnUsCalls.length > 0 ? JSON.stringify(nonEnUsCalls) : ''
);

// [4] Unit test centralized formatters.ts
console.log('\n[4] Testing centralized formatters.ts functions...');

import {
  formatDate,
  formatDateOnly,
  formatMonth,
  formatNumber,
  formatCurrency,
  toEnglishDigits,
  normalizeNumerals,
  sanitizeDecimalInput,
  sanitizeIntegerInput,
} from '../utils/formatters.ts';

const testDate = new Date('2026-08-20T13:18:00Z');
const dStr = formatDate(testDate);
const dOnlyStr = formatDateOnly(testDate);
const mStr = formatMonth(testDate);
const numStr = formatNumber(1234567.89);
const currStr = formatCurrency(28500);

assert(!arabicIndicRegex.test(dStr) && /\d{2}\/\d{2}\/\d{4}/.test(dStr), `formatDate("${dStr}") contains English digits only`);
assert(!arabicIndicRegex.test(dOnlyStr) && /\d{2}\/\d{2}\/\d{4}/.test(dOnlyStr), `formatDateOnly("${dOnlyStr}") contains English digits only`);
assert(!arabicIndicRegex.test(mStr) && /2026/.test(mStr) && /أغسطس/.test(mStr), `formatMonth("${mStr}") uses Arabic month name with English year numeral`);
assert(!arabicIndicRegex.test(numStr) && numStr.includes('1,234,567.89'), `formatNumber("${numStr}") formats with English separators`);
assert(!arabicIndicRegex.test(currStr) && currStr === '28,500', `formatCurrency("${currStr}") formats currency with English numerals`);

// Test toEnglishDigits
assert(toEnglishDigits('١٢٣٤٥٦٧٨٩٠') === '1234567890', 'toEnglishDigits converts Arabic-Indic numerals');
assert(toEnglishDigits('۱۲۳۴۵۶۷۸۹۰') === '1234567890', 'toEnglishDigits converts Persian numerals');
assert(toEnglishDigits(12345) === '12345', 'toEnglishDigits handles number inputs');
assert(toEnglishDigits(null) === '', 'toEnglishDigits handles null');
assert(toEnglishDigits(undefined) === '', 'toEnglishDigits handles undefined');
assert(normalizeNumerals('١٢٣') === '123', 'normalizeNumerals backward compatibility works');

// Test sanitizeDecimalInput
assert(sanitizeDecimalInput('١٢.٣٤') === '12.34', 'sanitizeDecimalInput converts Eastern numerals with decimal point');
assert(sanitizeDecimalInput('١٢٫٣٤') === '12.34', 'sanitizeDecimalInput converts Arabic decimal comma (\\u066B)');
assert(sanitizeDecimalInput('١٢٬٣٤') === '12.34', 'sanitizeDecimalInput converts Arabic thousands separator (\\u066C)');
assert(sanitizeDecimalInput('١٢،٣٤') === '12.34', 'sanitizeDecimalInput converts Arabic comma (\\u060C)');
assert(sanitizeDecimalInput('12,34') === '12.34', 'sanitizeDecimalInput converts standard comma (,) to dot');
assert(sanitizeDecimalInput('12.') === '12.', 'sanitizeDecimalInput preserves intermediate typing dot ("12.")');
assert(sanitizeDecimalInput('0.') === '0.', 'sanitizeDecimalInput preserves intermediate typing zero-dot ("0.")');
assert(sanitizeDecimalInput('.') === '.', 'sanitizeDecimalInput preserves single leading dot (".")');
assert(sanitizeDecimalInput('١٢٫') === '12.', 'sanitizeDecimalInput converts trailing Arabic comma to trailing dot ("12.")');
assert(sanitizeDecimalInput('abc١٢.٣٤xyz') === '12.34', 'sanitizeDecimalInput removes invalid characters');
assert(sanitizeDecimalInput('١٢..٣٤') === '12.34', 'sanitizeDecimalInput preserves only single decimal point');
assert(sanitizeDecimalInput('100.50.25') === '100.5025', 'sanitizeDecimalInput strips secondary dots');
assert(sanitizeDecimalInput('') === '', 'sanitizeDecimalInput handles empty string');
assert(sanitizeDecimalInput(null) === '', 'sanitizeDecimalInput handles null');
assert(sanitizeDecimalInput(undefined) === '', 'sanitizeDecimalInput handles undefined');
assert(sanitizeDecimalInput(45.67) === '45.67', 'sanitizeDecimalInput handles numeric input');

// Test sanitizeIntegerInput
assert(sanitizeIntegerInput('٠٧٧١٢٣٤٥٦٧') === '0771234567', 'sanitizeIntegerInput converts Eastern numerals to integer string');
assert(sanitizeIntegerInput('abc-771-234-567') === '771234567', 'sanitizeIntegerInput strips non-digits');
assert(sanitizeIntegerInput(null) === '', 'sanitizeIntegerInput handles null');

// [5] Unit test phoneValidation.ts with Eastern numerals
console.log('\n[5] Testing phoneValidation.ts with Eastern numerals and formatted inputs...');
import { validateYemeniPhone } from '../utils/phoneValidation.ts';

const phoneRes1 = validateYemeniPhone('٠٧٧١٢٣٤٥٦٧');
assert(phoneRes1.isValid && phoneRes1.formatted === '+967771234567', 'validateYemeniPhone validates Eastern numerals (٠٧٧١٢٣٤٥٦٧)');

const phoneRes2 = validateYemeniPhone('٧٣١٢٣٤٥٦٧');
assert(phoneRes2.isValid && phoneRes2.formatted === '+967731234567', 'validateYemeniPhone validates Eastern numerals without leading 0 (٧٣١٢٣٤٥٦٧)');

const phoneRes3 = validateYemeniPhone('+967 78 123 4567');
assert(phoneRes3.isValid && phoneRes3.formatted === '+967781234567', 'validateYemeniPhone validates formatted Yemen Mobile 78');

const phoneRes4 = validateYemeniPhone('٠٧٩١٢٣٤٥٦٧');
assert(!phoneRes4.isValid, 'validateYemeniPhone rejects invalid operator prefix 79');

console.log('\n---------------------------------------------------------------');
console.log(`Summary: ${passedTests}/${totalTests} tests passed (${failedTests} failed).`);
if (failedTests > 0) {
  process.exit(1);
} else {
  console.log('✓ ALL ENGLISH NUMERALS, INPUT SANITIZERS & SCANNER TESTS PASSED SUCCESSFULLY!');
}
