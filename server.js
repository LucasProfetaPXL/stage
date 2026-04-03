const express  = require('express');
const cors     = require('cors');
const { spawn } = require('child_process');
const path     = require('path');
const fs       = require('fs');

const app  = express();
const port = 3000;

app.use(cors());
app.use(express.json());
app.use(express.static('public'));

/* ─────────────────────────────────────────────────────────────
   Categorie -> Backup submap mapping
───────────────────────────────────────────────────────────── */
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

/* ─────────────────────────────────────────────────────────────
   GET /api/json-files/:category
───────────────────────────────────────────────────────────── */
app.get('/api/json-files/:category', (req, res) => {
    const folder = CATEGORY_FOLDERS[req.params.category];
    if (!folder) return res.status(400).json({ error: 'Onbekende categorie.' });

    const dir = path.join(__dirname, 'public', 'scripts', 'export', 'GoldenTenant_Backup', folder);
    if (!fs.existsSync(dir)) return res.json({ files: [], exists: false });

    const files = fs.readdirSync(dir).filter(f => f.endsWith('.json')).map(f => {
        try {
            const raw = fs.readFileSync(path.join(dir, f), 'utf8');
            const clean = raw.charCodeAt(0) === 0xFEFF ? raw.slice(1) : raw;
            return { fileName: f, valid: true, parsed: JSON.parse(clean) };
        } catch { return { fileName: f, valid: false }; }
    });
    res.json({ files, exists: true });
});

/* ─────────────────────────────────────────────────────────────
   POST /api/run/:folder/:scriptName
   Met automatische filtering van Bron vs Doel credentials
───────────────────────────────────────────────────────────── */
function runScriptHandler(req, res) {
    const rawPath = req.params.folder ? `${req.params.folder}/${req.params.scriptName}` : req.params.scriptName;
    const scriptPath = path.resolve(__dirname, 'public', 'scripts', `${rawPath}.ps1`);

    if (!fs.existsSync(scriptPath)) {
        return res.status(404).send(`[FOUT] Script niet gevonden op: ${scriptPath}`);
    }

    const psArgs = [];
    const usedKeys = new Set();
    const isExport = rawPath.toLowerCase().includes('export');
    const isImport = rawPath.toLowerCase().includes('import');

    // Filter logica: stuur alleen relevante velden door
    Object.entries(req.body).forEach(([key, val]) => {
        if (!val || val === "") return;

        let cleanKey = null;

        if (isExport && (key.startsWith('src-') || key.startsWith('exp-'))) {
            cleanKey = key.replace(/^(src-|exp-)/, '');
        }
        else if (isImport && (key.startsWith('dst-') || key.startsWith('imp-'))) {
            cleanKey = key.replace(/^(dst-|imp-)/, '');
        }
        else if (!key.includes('-')) {
            cleanKey = key;
        }

        if (cleanKey && !usedKeys.has(cleanKey.toLowerCase())) {
            psArgs.push(`-${cleanKey}`, String(val));
            usedKeys.add(cleanKey.toLowerCase());
        }
    });

    console.log(`[EXEC] ${rawPath}.ps1`);
    console.log(`[ARGS] ${JSON.stringify(psArgs)}`);

    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.setHeader('Transfer-Encoding', 'chunked');

    const ps = spawn('powershell.exe', [
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...psArgs
    ], { env: process.env });

    ps.stdout.on('data', d => res.write(d.toString()));
    ps.stderr.on('data', d => res.write(`\n[PS-FOUT] ${d.toString()}`));
    ps.on('close', code => res.end());
}

app.post('/api/run/:folder/:scriptName', runScriptHandler);
app.post('/api/run/:scriptName', runScriptHandler);

app.listen(port, () => {
    console.log(`🚀 MIGRATION ENGINE actief op http://localhost:${port}`);
});