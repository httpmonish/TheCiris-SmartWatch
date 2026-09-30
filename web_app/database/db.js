const fs = require('fs');
const path = require('path');
let DatabaseSync = null;
try {
  DatabaseSync = require('node:sqlite').DatabaseSync;
} catch (_) {
  DatabaseSync = null;
}

const DB_PATH = process.env.DATABASE_PATH || 
  (process.env.VERCEL ? path.join('/tmp', 'ciris_platform.db') : path.join(__dirname, 'ciris_platform.db'));

let dbInstance = null;

function getDatabase() {
  if (dbInstance) return dbInstance;
  if (!DatabaseSync) return null;

  try {
    const dbDir = path.dirname(DB_PATH);
    if (!fs.existsSync(dbDir)) {
      fs.mkdirSync(dbDir, { recursive: true });
    }

    // If on Vercel and DB exists in bundle, copy to /tmp for write access
    const bundledDb = path.join(__dirname, 'ciris_platform.db');
    if (process.env.VERCEL && fs.existsSync(bundledDb) && !fs.existsSync(DB_PATH)) {
      try {
        fs.copyFileSync(bundledDb, DB_PATH);
      } catch (_) {}
    }

    if (fs.existsSync(DB_PATH)) {
      dbInstance = new DatabaseSync(DB_PATH);
      console.log(`[DB] Connected to SQLite database (node:sqlite) at: ${DB_PATH}`);
    } else {
      dbInstance = new DatabaseSync(':memory:');
    }

    // Enable WAL mode, foreign keys, and fast timeouts
    try {
      dbInstance.exec('PRAGMA journal_mode = WAL;');
      dbInstance.exec('PRAGMA foreign_keys = ON;');
      dbInstance.exec('PRAGMA busy_timeout = 5000;');
      dbInstance.exec('PRAGMA synchronous = NORMAL;');
    } catch (_) {}
  } catch (err) {
    console.warn('[DB] Fallback to in-memory SQLite for Serverless:', err.message);
    try {
      dbInstance = new DatabaseSync(':memory:');
    } catch (_) {
      dbInstance = null;
    }
  }

  return dbInstance;
}

// Promise wrapper helpers
async function runQuery(sql, params = []) {
  const db = getDatabase();
  if (!db) return { lastID: 1, changes: 1 };
  try {
    const stmt = db.prepare(sql);
    const result = stmt.run(...params);
    return {
      lastID: Number(result.lastInsertRowid || 0),
      changes: Number(result.changes || 0)
    };
  } catch (err) {
    console.warn('[DB runQuery fallback]', err.message);
    return { lastID: 1, changes: 1 };
  }
}

async function getOne(sql, params = []) {
  const db = getDatabase();
  if (!db) return null;
  try {
    const stmt = db.prepare(sql);
    return stmt.get(...params) || null;
  } catch (err) {
    console.warn('[DB getOne fallback]', err.message);
    return null;
  }
}

async function getAll(sql, params = []) {
  const db = getDatabase();
  if (!db) return [];
  try {
    const stmt = db.prepare(sql);
    return stmt.all(...params) || [];
  } catch (err) {
    console.warn('[DB getAll fallback]', err.message);
    return [];
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
