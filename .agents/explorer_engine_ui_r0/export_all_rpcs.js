const fs = require('fs');
const { prisma } = require('d:/elctercity/backend/dist/lib/prisma.js');

async function main() {
  const procs = await prisma.$queryRawUnsafe(`
    SELECT proname, pg_get_functiondef(oid) as def 
    FROM pg_proc 
    WHERE proname LIKE 'rpc_%' 
    ORDER BY proname;
  `);

  let md = '# PostgreSQL RPC Function Definitions\n\n';
  for (const proc of procs) {
    md += `## ${proc.proname}\n\`\`\`sql\n${proc.def}\n\`\`\`\n\n`;
  }

  fs.writeFileSync('d:/elctercity/.agents/explorer_engine_ui_r0/all_rpc_definitions.md', md);
  console.log(`Successfully saved ${procs.length} RPC definitions.`);
}

main().catch(console.error).finally(() => prisma.$disconnect());
