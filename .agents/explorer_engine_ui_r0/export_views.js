const fs = require('fs');
const { prisma } = require('d:/elctercity/backend/dist/lib/prisma.js');

async function main() {
  const views = await prisma.$queryRawUnsafe(`
    SELECT table_name, pg_get_viewdef(table_name::regclass, true) as def
    FROM information_schema.views
    WHERE table_schema = 'public'
    ORDER BY table_name;
  `);

  let md = '# PostgreSQL View Definitions\n\n';
  for (const v of views) {
    md += `## ${v.table_name}\n\`\`\`sql\n${v.def}\n\`\`\`\n\n`;
  }

  fs.writeFileSync('d:/elctercity/.agents/explorer_engine_ui_r0/all_view_definitions.md', md);
  console.log(`Saved ${views.length} views.`);
}

main().catch(console.error).finally(() => prisma.$disconnect());
