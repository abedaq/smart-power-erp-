require('d:/elctercity/backend/node_modules/dotenv').config({ path: 'd:/elctercity/backend/.env' });
const { prisma } = require('d:/elctercity/backend/dist/lib/prisma');

(async () => {
  try {
    const pubTables = await prisma.$queryRawUnsafe(`
      SELECT schemaname, tablename 
      FROM pg_publication_tables 
      WHERE pubname = 'supabase_realtime';
    `);
    console.log('Tables in supabase_realtime publication:');
    console.table(pubTables);
  } catch (err) {
    console.error('Error querying publication tables:', err);
  } finally {
    await prisma.$disconnect();
  }
})();
