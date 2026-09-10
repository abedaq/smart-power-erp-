const { prisma } = require('d:/elctercity/backend/dist/lib/prisma.js');

async function main() {
  const views = await prisma.$queryRawUnsafe(`
    SELECT table_name, pg_get_viewdef(table_name::regclass, true) as def
    FROM information_schema.views
    WHERE table_schema = 'public'
    ORDER BY table_name;
  `);
  console.log(JSON.stringify(views, null, 2));
}

main().catch(console.error).finally(() => prisma.$disconnect());
