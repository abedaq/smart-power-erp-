import fs from 'fs';
import path from 'path';

function findEasternDigits(dir) {
  const matches = [];
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (!['node_modules', '.git', 'dist', 'tests'].includes(entry.name)) {
        matches.push(...findEasternDigits(fullPath));
      }
    } else if (/\.(tsx?|jsx?)$/.test(entry.name)) {
      const content = fs.readFileSync(fullPath, 'utf-8');
      const lines = content.split('\n');
      lines.forEach((line, idx) => {
        const trimmed = line.trim();
        // Ignore comments
        if (trimmed.startsWith('//') || trimmed.startsWith('*') || trimmed.startsWith('/*')) return;
        if (/[\u0660-\u0669\u06F0-\u06F9]/.test(line)) {
          // Check if regex character class in formatters.ts
          if (line.includes('[\\u0660-\\u0669]') || line.includes('[٠-٩]')) return;
          matches.push({ file: fullPath, line: idx + 1, content: trimmed });
        }
      });
    }
  }
  return matches;
}

const found = findEasternDigits('d:/elctercity/frontend/src');
console.log(`Found unexempt Eastern digits in code count: ${found.length}`);
if (found.length > 0) {
  console.log(found);
  process.exit(1);
} else {
  console.log('SUCCESS: Exactly zero Eastern Arabic digits found in UI code.');
}
