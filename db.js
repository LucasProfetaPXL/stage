const Database = require('better-sqlite3');
const bcrypt   = require('bcrypt');
const path     = require('path');

const db = new Database(path.join(__dirname, 'users.db'));

// Tabel aanmaken
db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    username  TEXT UNIQUE NOT NULL,
    password  TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  )
`);

// Standaard admin aanmaken als er nog geen gebruikers zijn
const count = db.prepare('SELECT COUNT(*) as count FROM users').get();
if (count.count === 0) {
    const hash = bcrypt.hashSync('Admin@Xylos123!', 12);
    const hash1 = bcrypt.hashSync('XylosMigration123!', 12);
    const hash2 = bcrypt.hashSync('giulia_quadrifoglio@', 12);
    db.prepare('INSERT INTO users (username, password) VALUES (?, ?)').run('admin', hash);
    db.prepare('INSERT INTO users (username, password) VALUES (?, ?)').run('abdelmalek', hash1);
    db.prepare('INSERT INTO users (username, password) VALUES (?, ?)').run('Gauthier', hash2);
    console.log('✅ Standaard admin aangemaakt — verander het wachtwoord meteen!');
}

module.exports = db;