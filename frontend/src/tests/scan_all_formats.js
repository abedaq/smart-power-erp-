import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const srcDir = path.resolve(__dirname, '..');

function getAllFiles(dir, fileList = []) {
  const files = fs.readdirSync(dir);
  files.forEach((file) => {
    const fullPath = path.join(dir, file);
    if (fs.statSync(fullPath).isDirectory()) {
      if (!file.includes('node_modules') && !file.includes('.git')) {
        getAllFiles(fullPath, fileList);
      }
    } else {
      if (/\.(tsx?|jsx?)$/i.test(file)) {
        fileList.push(fullPath);
      }
    }
  });
  return fileList;
}

const sourceFiles = getAllFiles(srcDir);
console.log(`Scanning ${sourceFiles.length} files for all date and number locale calls...\n`);

sourceFiles.forEach((filePath) => {
  if (filePath.includes('tests\\') || filePath.includes('tests/')) return;
  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split('\n');

  lines.forEach((line, idx) => {
    if (
      line.includes('toLocaleString') ||
      line.includes('toLocaleDateString') ||
      line.includes('toLocaleTimeString') ||
      line.includes('Intl.DateTimeFormat') ||
      line.includes('Intl.NumberFormat')
    ) {
      console.log(`${path.relative(srcDir, filePath)}:${idx + 1} -> ${line.trim()}`);
    }
  });
});
