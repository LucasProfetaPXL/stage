const express     = require('express');
const cors        = require('cors');
const { spawn }   = require('child_process');
const path        = require('path');
const fs          = require('fs');
const session     = require('express-session');
const SQLiteStore = require('connect-sqlite3')(session);

const db = require('./db');
const { requireAuth, handleLogin, handleLogout, loginLimiter } = require('./auth');

const app  = express();
const port = 3000;

app.use(cors());
app.use(express.json());

// SESSIE
app.use(session({
    store: new SQLiteStore({ db: 'sessions.db', dir: './' }),
    secret: process.env.SESSION_SECRET || 'verander-dit-naar-een-lang-random-geheim',
    resave: false,
    saveUninitialized: false,
    cookie: {
        secure: false,
        httpOnly: true,
        maxAge: 8 * 60 * 60 * 1000
    }
}));

// AUTH ROUTES
app.post('/api/auth/login',  loginLimiter, handleLogin);
app.post('/api/auth/logout', handleLogout);

// BEVEILIG ALLES BEHALVE LOGIN
app.use((req, res, next) => {
    const openPaths = ['/login.html', '/style.css'];
    if (req.path.startsWith('/api/auth/') || openPaths.includes(req.path)) {
        return next();
    }
    requireAuth(req, res, next);
});

// STATIC FILES
app.use(express.static(path.join(__dirname, 'public')));

// HUIDIGE USER OPHALEN
app.get('/api/auth/me', requireAuth, (req, res) => {
    res.json({ username: req.session.username, userId: req.session.userId });
});

// ═══════════════════════════════════════════════════════════
//  CREDENTIALS API (per user)
// ═══════════════════════════════════════════════════════════

app.get('/api/credentials', requireAuth, (req, res) => {
    const rows = db.prepare(
        'SELECT id, label, tenant_id, app_id, created_at FROM credentials WHERE user_id = ?'
    ).all(req.session.userId);
    res.json(rows);
});

app.post('/api/credentials', requireAuth, (req, res) => {
    const { label, tenant_id, app_id, app_secret } = req.body;

    if (!label || !tenant_id || !app_id || !app_secret) {
        return res.status(400).json({ error: 'Alle velden zijn verplicht.' });
    }

    try {
        db.prepare(`
            INSERT INTO credentials (user_id, label, tenant_id, app_id, app_secret)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(user_id, label) DO UPDATE SET
                tenant_id  = excluded.tenant_id,
                app_id     = excluded.app_id,
                app_secret = excluded.app_secret
        `).run(req.session.userId, label, tenant_id, app_id, app_secret);

        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: 'Kon credential niet opslaan.' });
    }
});

app.delete('/api/credentials/:id', requireAuth, (req, res) => {
    db.prepare(
        'DELETE FROM credentials WHERE id = ? AND user_id = ?'
    ).run(req.params.id, req.session.userId);
    res.json({ success: true });
});

// ═══════════════════════════════════════════════════════════
//  JSON FILES API (per user map)
// ═══════════════════════════════════════════════════════════
const CATEGORY_FOLDERS = {
    ca:   'ConditionalAccess',
    av:   'Antivirus',
    epm:  'EndpointPrivilegeManagement',
    comp: 'CompliancePolicies',
    ap:   'AppProtection',
    sb:   'SecurityBaselines',
    sc:   'SettingsCatalog',
    dc:   'DeviceConfigurations',
    ps:   'PowerShellScripts',
    grp:  'Groups',
    asg:  'Assignments'
};

app.get('/api/json-files/:category', requireAuth, (req, res) => {
    const folder = CATEGORY_FOLDERS[req.params.category];
    if (!folder) return res.status(400).json({ error: 'Onbekende categorie.' });

    const dir = path.join(
        __dirname, 'public', 'scripts', 'export',
        req.session.username, 'GoldenTenant_Backup', folder
    );

    if (!fs.existsSync(dir)) return res.json({ files: [], exists: false });

    const files = fs.readdirSync(dir)
        .filter(f => f.endsWith('.json'))
        .map(f => {
            try {
                const raw   = fs.readFileSync(path.join(dir, f), 'utf8');
                const clean = raw.charCodeAt(0) === 0xFEFF ? raw.slice(1) : raw;
                return { fileName: f, valid: true, parsed: JSON.parse(clean) };
            } catch {
                return { fileName: f, valid: false };
            }
        });

    res.json({ files, exists: true });
});

// ═══════════════════════════════════════════════════════════
//  SCRIPT RUNNER (per user map + streaming)
// ═══════════════════════════════════════════════════════════
function runScriptHandler(req, res) {
    const rawPath    = req.params.folder
        ? `${req.params.folder}/${req.params.scriptName}`
        : req.params.scriptName;
    const scriptPath = path.resolve(__dirname, 'public', 'scripts', `${rawPath}.ps1`);

    if (!fs.existsSync(scriptPath)) {
        return res.status(404).send(`[FOUT] Script niet gevonden op: ${scriptPath}`);
    }

    // Per-user backup map
    const userBackupDir = path.join(
        __dirname, 'public', 'scripts', 'export',
        req.session.username, 'GoldenTenant_Backup'
    );
    fs.mkdirSync(userBackupDir, { recursive: true });

    const psArgs   = [];
    const usedKeys = new Set();
    const isExport  = rawPath.toLowerCase().includes('export');
    const isImport  = rawPath.toLowerCase().includes('import');
    const isFixJson = rawPath.toLowerCase().includes('fix_json');
    const isUtils   = rawPath.toLowerCase().includes('utils');

    // BackupDir of BackupBase meesturen afhankelijk van scripttype
    // Utils-scripts (zoals Create_SourceTenant_App) verwachten geen BackupDir
    if (isFixJson) {
        psArgs.push('-BackupBase', userBackupDir);
        usedKeys.add('backupbase');
    } else if (!isUtils) {
        psArgs.push('-BackupDir', userBackupDir);
        usedKeys.add('backupdir');
    }

    Object.entries(req.body).forEach(([key, val]) => {
        if (!val || val === '') return;

        let cleanKey = null;

        if (isExport && (key.startsWith('src-') || key.startsWith('exp-'))) {
            cleanKey = key.replace(/^(src-|exp-)/, '');
        } else if (isImport && (key.startsWith('dst-') || key.startsWith('imp-'))) {
            cleanKey = key.replace(/^(dst-|imp-)/, '');
        } else if (!key.includes('-')) {
            cleanKey = key;
        }

        if (cleanKey && !usedKeys.has(cleanKey.toLowerCase())) {
            psArgs.push(`-${cleanKey}`, String(val));
            usedKeys.add(cleanKey.toLowerCase());
        }
    });

    console.log(`[EXEC] ${rawPath}.ps1 — user: ${req.session.username}`);
    console.log(`[ARGS] ${JSON.stringify(psArgs)}`);

    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.setHeader('Transfer-Encoding', 'chunked');

    // Bouw het PowerShell commando met 6>&1 om Write-Host/Information stream
    // door te sturen naar stdout zodat de browser de device code ziet
    const escapedPath = scriptPath.replace(/'/g, "''");
    const argsStr = psArgs.map(a => {
        if (a.startsWith('-')) return a;
        return `'${a.replace(/'/g, "''")}'`;
    }).join(' ');

    const ps = spawn('pwsh', [
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-Command', `& '${escapedPath}' ${argsStr} 6>&1`
    ], { env: process.env });

    ps.stdout.on('data', d => res.write(d.toString()));
    ps.stderr.on('data', d => res.write(`\n[PS-FOUT] ${d.toString()}`));
    ps.on('close', () => res.end());
}

app.post('/api/run/:folder/:scriptName', requireAuth, runScriptHandler);
app.post('/api/run/:scriptName',         requireAuth, runScriptHandler);

// START
app.listen(port, () => {
    console.log(`Migration Engine actief op http://localhost:${port}`);
});