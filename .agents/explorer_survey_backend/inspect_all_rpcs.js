require('d:/elctercity/backend/node_modules/dotenv').config({ path: 'd:/elctercity/backend/.env' });
const { prisma } = require('d:/elctercity/backend/dist/lib/prisma');

(async () => {
  try {
    const procs = await prisma.$queryRawUnsafe(`
      SELECT p.proname, pg_get_function_arguments(p.oid) as args, p.prosrc
      FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname = 'public' AND (p.proname LIKE 'rpc_%' OR p.proname LIKE 'fn_%')
      ORDER BY p.proname, args;
    `);
    
    console.log(`Found ${procs.length} RPC/Functions:`);
    procs.forEach(p => {
      console.log(`\n======================================================`);
      console.log(`FUNCTION: ${p.proname}(${p.args})`);
      console.log(`======================================================`);
      console.log(p.prosrc);
    });
  } catch (err) {
    console.error('Error fetching procs:', err);
  } finally {
    await prisma.$disconnect();
  }
})();
