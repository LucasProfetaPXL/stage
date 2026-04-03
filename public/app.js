// ─── NAV LOADER ───────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
    const ph = document.getElementById('nav-placeholder');
    if (ph) {
        fetch('nav.html')
            .then(r => r.text())
            .then(html => {
                ph.innerHTML = html;
                const path = window.location.pathname;
                const page = path.split('/').pop().replace('.html','') || 'index';
                document.querySelectorAll('[data-page]').forEach(el => {
                    if (el.dataset.page === page) el.classList.add('active');
                    const migrationPages = ['full-migration', 'app-migration', 'policy-migration'];
                    if (el.dataset.page === 'migratie' && migrationPages.includes(page)) {
                        el.classList.add('active');
                    }
                });
            })
            .catch(err => console.error('Fout bij laden navigatie:', err));
    }
});

// ─── CONSOLE BEHEER ───────────────────────────────────────
function getConsole() {
    return document.getElementById('output');
}

function consoleClear() {
    const c = getConsole();
    if (c) c.innerHTML = '<div class="line-info">> Console gereed...</div>';
}

function consolePrint(text, type = '') {
    const c = getConsole();
    if (!c) return;

    const trimmed = text.trim();
    if (!trimmed) return;

    // Sla alleen pure JSON structuurregels over — NIET foutmeldingen
    const isPureJson = (
        trimmed === '{' || trimmed === '}' ||
        trimmed === '[' || trimmed === ']' ||
        trimmed === '},' || trimmed === '],' ||
        (trimmed.startsWith('"') && (trimmed.endsWith('",') || trimmed.endsWith('":')))
    );
    if (isPureJson) return;

    const line = document.createElement('div');
    if (type) {
        line.className = `line-${type}`;
    } else {
        const raw = trimmed.toLowerCase();
        if (raw.includes('error') || raw.includes('fout') || raw.includes('failed') || raw.includes('[ps-fout]')) {
            line.className = 'line-err';
        } else if (raw.includes('success') || raw.includes('voltooid') || raw.includes('[ok]')) {
            line.className = 'line-ok';
        } else if (raw.includes('warning') || raw.includes('waarschuwing')) {
            line.className = 'line-warn';
        } else {
            line.className = 'line-default';
        }
    }
    line.textContent = trimmed;
    c.appendChild(line);

    // Max 300 regels — verwijder oudste
    while (c.children.length > 300) c.removeChild(c.firstChild);

    c.scrollTop = c.scrollHeight;
}

function consoleWriteLines(text) {
    if (!text) return;
    text.split('\n').forEach(line => { if (line.trim()) consolePrint(line); });
}

// ─── SCRIPT RUNNER (streaming) ────────────────────────────
async function runScript(scriptName, extraPayload = {}) {
    if (window.event) window.event.preventDefault();

    const btn = document.querySelector(`[data-script="${scriptName}"]`);
    if (btn) { btn.classList.add('running'); btn.disabled = true; }

    consoleClear();
    consolePrint(`> Initialiseren: ${scriptName}.ps1`, 'info');
    consolePrint(`> Verbinding maken met API...`, 'info');

    const payload = { ...extraPayload };
    document.querySelectorAll('input[id]').forEach(input => {
        const val = input.value.trim();
        if (val && input.type !== 'button') payload[input.id] = val;
    });

    try {
        const response = await fetch(`http://localhost:3000/api/run/${scriptName}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });

        if (!response.ok) {
            const result = await response.text();
            consolePrint(`\n[FOUT] Server antwoordde met status ${response.status}`, 'err');
            consoleWriteLines(result);
            return;
        }

        // ── Streaming: toon output terwijl script nog loopt ──
        const reader  = response.body.getReader();
        const decoder = new TextDecoder();
        let   buffer  = '';

        while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            buffer += decoder.decode(value, { stream: true });
            const lines = buffer.split('\n');
            buffer = lines.pop(); // Bewaar onvolledige laatste regel

            lines.forEach(line => { if (line.trim()) consolePrint(line); });
        }

        if (buffer.trim()) consolePrint(buffer);
        consolePrint(`> Script succesvol uitgevoerd.`, 'ok');

    } catch (err) {
        consolePrint(`[NETWERK FOUT] Kan de Migration Engine niet bereiken.`, 'err');
        consolePrint(`Controleer of 'node server.js' draait op poort 3000.`, 'warn');
        consolePrint(`Details: ${err.message}`, 'err');
    } finally {
        if (btn) { btn.classList.remove('running'); btn.disabled = false; }
    }
}