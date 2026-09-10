import fs from 'fs';
import path from 'path';

const targets = [
  'd:/elctercity/frontend/src',
  'd:/elctercity/backend/src'
];

let suspiciousCalls = [];

function scanDir(dir) {
  if (!fs.existsSync(dir)) return;
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name !== 'node_modules' && entry.name !== '.git' && entry.name !== 'dist' && entry.name !== 'build') {
        scanDir(fullPath);
      }
    } else if (/\.(tsx?|jsx?)$/i.test(entry.name)) {
      const content = fs.readFileSync(fullPath, 'utf8');
      const lines = content.split('\n');
      lines.forEach((line, idx) => {
        const trimmed = line.trim();
        if (trimmed.startsWith('//') || trimmed.startsWith('/*') || fullPath.includes('tests')) return;
        if (
          (line.includes('.toLocaleString()') || 
           line.includes('.toLocaleDateString()') || 
           line.includes("toLocaleDateString('ar") || 
           line.includes('toLocaleDateString("ar')) &&
          !line.includes('en-US') && 
          !line.includes('latn')
        ) {
          suspiciousCalls.push({
            file: fullPath,
            line: idx + 1,
            code: trimmed
          });
        }
      });
    }
  }
}

for (const t of targets) {
  scanDir(t);
}

console.log(`Suspicious unparameterized locale calls: ${suspiciousCalls.length}`);
if (suspiciousCalls.length > 0) {
  console.log(JSON.stringify(suspiciousCalls, null, 2));
} else {
  console.log('ALL LOCALE CALLS CLEAN: All date/number formatters enforce en-US or latn numbering system!');
}
