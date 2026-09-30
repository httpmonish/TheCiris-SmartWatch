const { runMigrations, getAll, getOne } = require('../database/db');

async function testDatabase() {
  console.log('Testing database connection and migrations...');
  await runMigrations();

  const tables = await getAll("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
  console.log('Registered Tables in SQLite:', tables.map(t => t.name));

  const datasetCount = await getOne('SELECT COUNT(*) as count FROM datasets');
  console.log('Datasets count:', datasetCount.count);

  const modelCount = await getOne('SELECT COUNT(*) as count FROM models');
  console.log('Models count:', modelCount.count);

  console.log('All database checks PASSED!');
}

testDatabase().catch(err => {
  console.error('Database test failed:', err);
  process.exit(1);
});
