const fs = require('fs');
const results = JSON.parse(fs.readFileSync('d:/elctercity/.agents/explorer_inputs_survey/detailed_inputs.json', 'utf8'));

const targetFiles = [
  'components/ArrearsThresholdModal.tsx',
  'components/PaymentModal.tsx',
  'components/ReadingModal.tsx',
  'components/common/ExcelGrid.tsx',
  'components/common/InvoiceModal.tsx',
  'components/InvoicePreviewModal.tsx',
  'components/CyclePrintView.tsx',
  'components/PlansManagement.tsx',
  'pages/Customers.tsx',
  'pages/Invoices.tsx',
  'pages/ArrearsReport.tsx',
  'pages/TodayReadingsReview.tsx',
  'pages/Settings.tsx',
  'pages/Dashboard.tsx'
];

targetFiles.forEach(file => {
  console.log(`\n=================== ${file} ===================`);
  const list = results[file] || [];
  if (list.length === 0) {
    console.log('No inputs found in this file.');
  } else {
    list.forEach(inp => {
      console.log(`\n>>> Line ${inp.lineNum}: type="${inp.type}" inputMode="${inp.inputMode}"`);
      console.log(inp.contextSnippet);
    });
  }
});
