import fs from 'fs';
import path from 'path';

const arabicIndicRegex = /[\u0660-\u0669\u06F0-\u06F9]/g;
const targets = [
  'd:/elctercity/frontend/src',
  'd:/elctercity/backend/src',
  'd:/elctercity/backend/templates'
];

let scannedFiles = 0;
let violations = [];

function scanDir(dir) {
  if (!fs.existsSync(dir)) return;
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name !== 'node_modules' && entry.name !== '.git' && entry.name !== 'dist' && entry.name !== 'build') {
        scanDir(fullPath);
      }
    } else if (/\.(tsx?|jsx?|html|ejs|json|css)$/i.test(entry.name)) {
      scannedFiles++;
      const content = fs.readFileSync(fullPath, 'utf8');
      const lines = content.split('\n');
      lines.forEach((line, idx) => {
        const trimmed = line.trim();
        // Ignore comments that explicitly document or test normalization
        if (trimmed.startsWith('//') || trimmed.startsWith('/*') || trimmed.startsWith('*') || fullPath.includes('tests')) {
          return;
        }
        const match = trimmed.match(arabicIndicRegex);
        if (match) {
          violations.push({
            file: fullPath,
            line: idx + 1,
            matched: match.join(','),
            snippet: trimmed
          });
        }
      });
    }
  }
}

for (const t of targets) {
  scanDir(t);
}

console.log(`Scanned ${scannedFiles} files across frontend and backend.`);
console.log(`Violations found: ${violations.length}`);
if (violations.length > 0) {
  console.log('VIOLATIONS:');
  console.log(JSON.stringify(violations, null, 2));
  process.exit(1);
} else {
  console.log('ALL FILES CLEAN: Zero Eastern Arabic numerals found in production code & templates!');
  process.exit(0);
}
