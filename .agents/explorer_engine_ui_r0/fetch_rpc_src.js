const { prisma } = require('d:/elctercity/backend/dist/lib/prisma.js');

async function main() {
  const procs = await prisma.$queryRawUnsafe(`
    SELECT proname, pg_get_functiondef(oid) as def 
    FROM pg_proc 
    WHERE proname LIKE 'rpc_%' 
    ORDER BY proname;
  `);
  console.log(JSON.stringify(procs, null, 2));
}

main().catch(console.error).finally(() => prisma.$disconnect());
