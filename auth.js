const bcrypt    = require('bcrypt');
const rateLimit = require('express-rate-limit');
const db        = require('./db');

// Max 10 loginpogingen per 15 minuten per IP
const loginLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 10,
    message: 'Te veel loginpogingen. Probeer opnieuw na 15 minuten.',
    standardHeaders: true,
    legacyHeaders: false
});

// Middleware: controleer of gebruiker ingelogd is
function requireAuth(req, res, next) {
    if (req.session && req.session.userId) {
        return next();
    }
    res.redirect('/login.html');
}

// POST /api/auth/login
async function handleLogin(req, res) {
    const { username, password } = req.body;

    // Validatie — voorkomt lege inputs
    if (!username || !password) {
        return res.status(400).json({ error: 'Gebruikersnaam en wachtwoord zijn verplicht.' });
    }

    // Geparametriseerde query — voorkomt SQL injectie
    const user = db.prepare('SELECT * FROM users WHERE username = ?').get(username);

    if (!user) {
        // Zelfde foutmelding zodat je geen info lekt over bestaande gebruikers
        return res.status(401).json({ error: 'Ongeldige gebruikersnaam of wachtwoord.' });
    }

    const match = await bcrypt.compare(password, user.password);
    if (!match) {
        return res.status(401).json({ error: 'Ongeldige gebruikersnaam of wachtwoord.' });
    }

    req.session.userId   = user.id;
    req.session.username = user.username;
    res.json({ success: true });
}

// POST /api/auth/logout
function handleLogout(req, res) {
    req.session.destroy(() => {
        res.clearCookie('connect.sid');
        res.json({ success: true });
    });
}

// POST /api/auth/register — alleen voor admins
async function handleRegister(req, res) {
    const { username, password } = req.body;

    if (!username || !password) {
        return res.status(400).json({ error: 'Alle velden zijn verplicht.' });
    }

    // Wachtwoord validatie
    const passwordRegex = /^(?=.*[A-Z])(?=.*[0-9])(?=.*[!@#$%^&*]).{10,}$/;
    if (!passwordRegex.test(password)) {
        return res.status(400).json({
            error: 'Wachtwoord moet minimaal 10 tekens, 1 hoofdletter, 1 cijfer en 1 speciaal teken bevatten.'
        });
    }

    const hash = await bcrypt.hash(password, 12);

    try {
        // Geparametriseerde query — voorkomt SQL injectie
        db.prepare('INSERT INTO users (username, password) VALUES (?, ?)').run(username, hash);
        res.json({ success: true });
    } catch (err) {
        if (err.message.includes('UNIQUE')) {
            return res.status(409).json({ error: 'Gebruikersnaam bestaat al.' });
        }
        res.status(500).json({ error: 'Interne fout.' });
    }
}

module.exports = { requireAuth, handleLogin, handleLogout, handleRegister, loginLimiter };