const fs = require('fs');
const path = require('path');

const inputsData = JSON.parse(fs.readFileSync('d:/elctercity/.agents/explorer_inputs_survey/inputs_dump.json', 'utf8'));

console.log(`Analyzing ${inputsData.length} inputs across ${new Set(inputsData.map(d => d.file)).size} files...\n`);

const resultsByFile = {};

inputsData.forEach(item => {
  if (!resultsByFile[item.file]) resultsByFile[item.file] = [];
  
  // Read full context around line
  const fileLines = fs.readFileSync(path.join('d:/elctercity/frontend/src', item.file), 'utf8').split('\n');
  const startLine = Math.max(0, item.lineNum - 5);
  const endLine = Math.min(fileLines.length, item.lineNum + 15);
  const contextSnippet = fileLines.slice(startLine, endLine).join('\n');
  
  resultsByFile[item.file].push({
    lineNum: item.lineNum,
    type: item.type,
    inputMode: item.inputMode,
    fullTag: item.fullTag,
    contextSnippet
  });
});

fs.writeFileSync('d:/elctercity/.agents/explorer_inputs_survey/detailed_inputs.json', JSON.stringify(resultsByFile, null, 2));

console.log('Detailed context extracted. Generating summary breakdown...\n');

Object.keys(resultsByFile).sort().forEach(file => {
  console.log(`=== ${file} (${resultsByFile[file].length} inputs) ===`);
  resultsByFile[file].forEach(inp => {
    console.log(`  Line ${inp.lineNum}: type="${inp.type}" inputMode="${inp.inputMode || 'none'}"`);
    console.log(`    Tag: ${inp.fullTag.slice(0, 100)}...`);
  });
  console.log('');
});
