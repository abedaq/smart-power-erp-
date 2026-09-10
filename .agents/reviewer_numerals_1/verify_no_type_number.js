import fs from 'fs';
import path from 'path';

function findTypeNumber(dir) {
  const matches = [];
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (!['node_modules', '.git', 'dist'].includes(entry.name)) {
        matches.push(...findTypeNumber(fullPath));
      }
    } else if (/\.(tsx|jsx|html)$/.test(entry.name)) {
      const content = fs.readFileSync(fullPath, 'utf-8');
      const lines = content.split('\n');
      lines.forEach((line, idx) => {
        if (/type=["']number["']/.test(line)) {
          matches.push({ file: fullPath, line: idx + 1, content: line.trim() });
        }
      });
    }
  }
  return matches;
}

const found = findTypeNumber('d:/elctercity/frontend/src');
console.log(`Found type="number" count: ${found.length}`);
if (found.length > 0) {
  console.log(found);
  process.exit(1);
} else {
  console.log('SUCCESS: Exactly zero type="number" found across all frontend/src files.');
}
