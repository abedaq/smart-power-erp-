const fs = require('fs');
const path = require('path');

let found = [];
function walk(dir) {
  for (const item of fs.readdirSync(dir)) {
    const full = path.join(dir, item);
    if (fs.statSync(full).isDirectory()) {
      if (!['node_modules', '.git', 'dist', 'build'].includes(item)) walk(full);
    } else if (/\.(tsx|jsx|ts|js|html)$/i.test(item)) {
      if (full.includes('tests')) continue;
      const content = fs.readFileSync(full, 'utf8');
      const lines = content.split('\n');
      lines.forEach((line, idx) => {
        if (/type\s*=\s*[']number[']/.test(line)) {
          found.push({ file: full, line: idx + 1, text: line.trim() });
        }
      });
    }
  }
}

walk('d:/elctercity/frontend/src');
console.log('TOTAL_TYPE_NUMBER_FOUND:', found.length);
if (found.length > 0) {
  console.log(JSON.stringify(found, null, 2));
  process.exit(1);
} else {
  console.log('SUCCESS: Zero type=number found across all frontend source files!');
}
