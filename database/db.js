const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

const DB_PATH = process.env.DATABASE_PATH || path.join(__dirname, 'ciris_platform.db');

let dbInstance = null;

function getDatabase() {
  if (dbInstance) return dbInstance;

  const dbDir = path.dirname(DB_PATH);
  if (!fs.existsSync(dbDir)) {
    fs.mkdirSync(dbDir, { recursive: true });
  }

  try {
    dbInstance = new DatabaseSync(DB_PATH);
    console.log(`[DB] Connected to SQLite database (node:sqlite) at: ${DB_PATH}`);

    // Enable WAL mode, foreign keys, and fast timeouts
    dbInstance.exec('PRAGMA journal_mode = WAL;');
    dbInstance.exec('PRAGMA foreign_keys = ON;');
    dbInstance.exec('PRAGMA busy_timeout = 5000;');
    dbInstance.exec('PRAGMA synchronous = NORMAL;');
  } catch (err) {
    console.error('[DB] Failed to connect to SQLite database:', err.message);
    throw err;
  }

  return dbInstance;
}

// Promise wrapper helpers
async function runQuery(sql, params = []) {
  const db = getDatabase();
  try {
    const stmt = db.prepare(sql);
    const result = stmt.run(...params);
    return {
      lastID: Number(result.lastInsertRowid || 0),
      changes: Number(result.changes || 0)
    };
  } catch (err) {
    throw err;
  }
}

async function getOne(sql, params = []) {
  const db = getDatabase();
  try {
    const stmt = db.prepare(sql);
    return stmt.get(...params) || null;
  } catch (err) {
    throw err;
  }
}

async function getAll(sql, params = []) {
  const db = getDatabase();
  try {
    const stmt = db.prepare(sql);
    return stmt.all(...params) || [];
  } catch (err) {
    throw err;
  }
}

// Run schema migrations
async function runMigrations() {
  const db = getDatabase();
  const schemaPath = path.join(__dirname, 'schema.sql');
  if (!fs.existsSync(schemaPath)) {
    throw new Error(`Schema file not found at ${schemaPath}`);
  }

  const schemaSql = fs.readFileSync(schemaPath, 'utf8');

  try {
    db.exec(schemaSql);

    // Record migration in schema_migrations table
    const existing = await getOne('SELECT version FROM schema_migrations WHERE version = ?', [1]);
    if (!existing) {
      await runQuery(
        'INSERT INTO schema_migrations (version, description) VALUES (?, ?)',
        [1, 'Initial CIRIS platform relational schema']
      );
    }
    console.log('[DB] Database schema migrations successfully applied.');
  } catch (err) {
    console.error('[DB] Migration error:', err);
    throw err;
  }
}

module.exports = {
  getDatabase,
  runQuery,
  getOne,
  getAll,
  runMigrations,
  DB_PATH
};
