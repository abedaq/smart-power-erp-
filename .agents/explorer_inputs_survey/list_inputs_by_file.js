const fs = require('fs');
const results = JSON.parse(fs.readFileSync('d:/elctercity/.agents/explorer_inputs_survey/detailed_inputs.json', 'utf8'));

Object.keys(results).sort().forEach(file => {
  console.log(`\n=================== FILE: ${file} (Count: ${results[file].length}) ===================`);
  results[file].forEach((inp, idx) => {
    console.log(`[${idx + 1}] Line ${inp.lineNum} | type="${inp.type}" | inputMode="${inp.inputMode || 'none'}"`);
    console.log(`    Tag: ${inp.fullTag}`);
  });
});
