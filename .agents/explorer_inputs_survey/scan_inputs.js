const fs = require('fs');
const path = require('path');

function walk(dir) {
  let results = [];
  const list = fs.readdirSync(dir);
  list.forEach(file => {
    const fullPath = path.join(dir, file);
    const stat = fs.statSync(fullPath);
    if (stat && stat.isDirectory()) {
      results = results.concat(walk(fullPath));
    } else if (file.endsWith('.tsx') || file.endsWith('.ts')) {
      results.push(fullPath);
    }
  });
  return results;
}

const files = walk('d:/elctercity/frontend/src');

const analysis = [];

files.forEach(filePath => {
  const relPath = path.relative('d:/elctercity/frontend/src', filePath).replace(/\\/g, '/');
  const content = fs.readFileSync(filePath, 'utf8');
  
  // Regex to find JSX input elements
  const inputRegex = /<input\b([^>]*?)(\/?>)/gs;
  let match;
  while ((match = inputRegex.exec(content)) !== null) {
    const fullTag = match[0];
    const attrs = match[1];
    
    // Find line number
    const upToMatch = content.substring(0, match.index);
    const lineNum = upToMatch.split('\n').length;
    
    // Extract attributes
    const typeMatch = attrs.match(/type=["']([^"']+)["']/);
    const inputModeMatch = attrs.match(/inputMode=["']([^"']+)["']/);
    const valueMatch = attrs.match(/value=\{?([^}"'\s>]+)\}?/);
    const onChangeMatch = attrs.match(/onChange=\{([^}]+)\}/s);
    const onBlurMatch = attrs.match(/onBlur=\{([^}]+)\}/s);
    const placeholderMatch = attrs.match(/placeholder=["']([^"']+)["']/);
    const nameMatch = attrs.match(/name=["']([^"']+)["']/);
    const idMatch = attrs.match(/id=["']([^"']+)["']/);
    const classNameMatch = attrs.match(/className=["']([^"']+)["']/);

    analysis.push({
      file: relPath,
      lineNum,
      type: typeMatch ? typeMatch[1] : 'text(default)',
      inputMode: inputModeMatch ? inputModeMatch[1] : null,
      name: nameMatch ? nameMatch[1] : null,
      id: idMatch ? idMatch[1] : null,
      placeholder: placeholderMatch ? placeholderMatch[1] : null,
      hasOnChange: !!onChangeMatch,
      hasOnBlur: !!onBlurMatch,
      fullTag: fullTag.replace(/\s+/g, ' ').trim()
    });
  }
});

console.log('Total input tags found:', analysis.length);
fs.writeFileSync('d:/elctercity/.agents/explorer_inputs_survey/inputs_dump.json', JSON.stringify(analysis, null, 2));

// Summary statistics
const typeCounts = {};
analysis.forEach(item => {
  typeCounts[item.type] = (typeCounts[item.type] || 0) + 1;
});
console.log('Input type breakdown:', typeCounts);

// Breakdown by file
const fileMap = {};
analysis.forEach(item => {
  if (!fileMap[item.file]) fileMap[item.file] = [];
  fileMap[item.file].push(item);
});

console.log('\nInputs per file:');
Object.keys(fileMap).sort().forEach(file => {
  console.log(`- ${file}: ${fileMap[file].length} inputs`);
});
