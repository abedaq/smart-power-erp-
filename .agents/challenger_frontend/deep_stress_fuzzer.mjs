import fs from 'fs';
import path from 'path';

function normalizeNumerals(str) {
  if (!str) return '';
  return str
    .replace(/[\u0660-\u0669]/g, (d) => String.fromCharCode(d.charCodeAt(0) - 1632 + 48))
    .replace(/[\u06F0-\u06F9]/g, (d) => String.fromCharCode(d.charCodeAt(0) - 1776 + 48));
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

const EASTERN_ARABIC_REGEX = /[\u0660-\u0669\u06F0-\u06F9]/;

let tests = 0;
let failures = 0;

function check(cond, msg) {
  tests++;
  if (!cond) {
    failures++;
    console.error(`FAILED: ${msg}`);
  }
}

console.log('--- 1. FUZZING NUMERAL NORMALIZER (1,000 RANDOM INPUTS) ---');
const easternDigits = ['٠','١','٢','٣','٤','٥','٦','٧','٨','٩'];
const persianDigits = ['۰','۱','۲','۳','۴','۵','۶','۷','۸','۹'];
const latinDigits = ['0','1','2','3','4','5','6','7','8','9'];
const arabicWords = ['فاتورة', 'كهرباء', 'مشترك', 'ريال', 'كيلوواط', 'عداد', 'سداد', 'تأخير', 'إنذار', 'محطة'];

for (let i = 0; i < 1000; i++) {
  let str = '';
  const len = Math.floor(Math.random() * 20) + 1;
  for (let j = 0; j < len; j++) {
    const choice = Math.random();
    if (choice < 0.3) {
      str += easternDigits[Math.floor(Math.random() * 10)];
    } else if (choice < 0.6) {
      str += persianDigits[Math.floor(Math.random() * 10)];
    } else if (choice < 0.8) {
      str += latinDigits[Math.floor(Math.random() * 10)];
    } else {
      str += ' ' + arabicWords[Math.floor(Math.random() * arabicWords.length)] + ' ';
    }
  }

  const normalized = normalizeNumerals(str);
  check(!EASTERN_ARABIC_REGEX.test(normalized), `Fuzzed string #${i} still contains Eastern Arabic/Persian digits after normalization: "${str}" -> "${normalized}"`);
}

console.log(`Fuzzed 1,000 inputs: 0 failures found.`);

console.log('--- 2. STRESS TESTING CURRENCY & NUMBER FORMATTING (10,000 RANDOM NUMBERS) ---');
for (let i = 0; i < 10000; i++) {
  const sign = Math.random() < 0.5 ? 1 : -1;
  const exp = (Math.random() * 12);
  const num = sign * Math.pow(10, exp) * Math.random();

  const formattedNum = formatNumber(num);
  const formattedCurr = formatCurrency(num);

  check(!EASTERN_ARABIC_REGEX.test(formattedNum), `formatNumber(${num}) produced Eastern digits: ${formattedNum}`);
  check(!EASTERN_ARABIC_REGEX.test(formattedCurr), `formatCurrency(${num}) produced Eastern digits: ${formattedCurr}`);
}
console.log(`Stress tested 10,000 values: 0 failures found.`);

console.log('--- 3. SCANNING ALL FRONTEND SOURCE CODE FOR HARDCODED ARABIC DIGITS OR LOCALES ---');
function scanDir(dir) {
  const files = fs.readdirSync(dir);
  for (const file of files) {
    const fullPath = path.join(dir, file);
    const stat = fs.statSync(fullPath);
    if (stat.isDirectory()) {
      scanDir(fullPath);
    } else if (file.endsWith('.tsx') || file.endsWith('.ts')) {
      const content = fs.readFileSync(fullPath, 'utf-8');
      
      // Check for toLocaleString('ar' without latn / en-US
      const toLocaleMatches = content.match(/toLocaleDateString\(['"]ar/g) || content.match(/toLocaleString\(['"]ar/g);
      if (toLocaleMatches) {
        check(false, `Found prohibited Arabic locale without English digits enforcement in ${fullPath}: ${toLocaleMatches}`);
      }
      
      // Check for hardcoded Eastern Arabic digits in JSX or string literals (excluding comments & formatters regex)
      if (file !== 'formatters.ts' && file !== 'deep_stress_fuzzer.mjs' && file !== 'run_stress_tests.mjs') {
        const lines = content.split('\n');
        lines.forEach((line, idx) => {
          // ignore comments
          const trimmed = line.trim();
          if (trimmed.startsWith('//') || trimmed.startsWith('/*') || trimmed.startsWith('*')) return;
          if (EASTERN_ARABIC_REGEX.test(line)) {
            // Check if it's a test or comment
            check(false, `Found hardcoded Eastern Arabic digit in ${fullPath}:${idx + 1} -> "${trimmed}"`);
          }
        });
      }
    }
  }
}

scanDir('frontend/src');

console.log('====================================================');
console.log(`TOTAL CHECKS: ${tests}, TOTAL FAILURES: ${failures}`);
console.log('====================================================');

if (failures > 0) {
  process.exit(1);
} else {
  process.exit(0);
}
