const fs = require('fs');
const results = JSON.parse(fs.readFileSync('d:/elctercity/.agents/explorer_inputs_survey/detailed_inputs.json', 'utf8'));

let md = '# Full Survey of All Input Fields in Frontend Codebase\n\n';
md += '| # | File | Line | Current Type | InputMode | Field Purpose | Current Sanitizer/Handler | Evaluation / Action Required |\n';
md += '|---|------|------|--------------|-----------|---------------|----------------------------|-------------------------------|\n';

let counter = 1;

Object.keys(results).sort().forEach(file => {
  results[file].forEach(inp => {
    // Determine purpose
    let purpose = 'Text / Search';
    let sanitizer = 'Direct string';
    let evaluation = 'OK (Search/Filter text)';

    if (inp.type === 'password') {
      purpose = 'Password input';
      sanitizer = 'Password handler';
      evaluation = 'OK (Password field)';
    } else if (inp.type === 'checkbox') {
      purpose = 'Checkbox (Remember me)';
      sanitizer = 'Boolean state';
      evaluation = 'OK (Checkbox)';
    } else if (inp.contextSnippet.includes('sanitizeDecimalInput')) {
      purpose = 'Decimal numeric field';
      sanitizer = 'sanitizeDecimalInput';
      evaluation = 'Protected with toEnglishDigits + decimal sanitize';
    } else if (inp.contextSnippet.includes('toEnglishDigits')) {
      purpose = 'Integer / Phone / Route / Meter';
      sanitizer = 'toEnglishDigits';
      evaluation = 'Protected with toEnglishDigits';
    } else if (inp.fullTag.includes('search') || inp.fullTag.includes('Search') || inp.fullTag.includes('بحث')) {
      purpose = 'Search query box';
      sanitizer = 'Direct string onChange';
      evaluation = 'OK (Search text field)';
    } else if (inp.fullTag.includes('name') || inp.fullTag.includes('Name') || inp.fullTag.includes('username') || inp.fullTag.includes('address')) {
      purpose = 'Name / Address / Username';
      sanitizer = 'Direct string onChange';
      evaluation = 'OK (Text field)';
    } else if (inp.type === 'number') {
      purpose = 'Unconverted number input';
      sanitizer = 'None';
      evaluation = 'CRITICAL: Must convert to type="text" inputMode="decimal"';
    }

    md += `| ${counter++} | \`${file}\` | ${inp.lineNum} | \`${inp.type}\` | \`${inp.inputMode || 'none'}\` | ${purpose} | \`${sanitizer}\` | ${evaluation} |\n`;
  });
});

fs.writeFileSync('d:/elctercity/.agents/explorer_inputs_survey/inputs_table.md', md);
console.log('inputs_table.md written successfully. Total items:', counter - 1);
