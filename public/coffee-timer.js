/* ============================================================
 * Xylos Migration Engine — Coffee Timer
 * Toont een koffie-timer naast de navigatie en een eenmalige
 * "Tijd voor koffie!" popup wanneer de gebruiker 30 minuten
 * actief op de site is geweest (cumulatief over pagina's heen).
 * ============================================================ */
(function () {
    'use strict';

    // ─── Config ────────────────────────────────────────────────
    var COFFEE_BREAK_MS  = 30 * 60 * 1000;   // 30 min
    var TICK_MS          = 1000;             // update iedere seconde
    var SAVE_EVERY_MS    = 5000;             // localStorage elke 5s wegschrijven
    var KEY_ACTIVE_MS    = 'xylos_activeTimeMs';
    var KEY_POPUP_SHOWN  = 'xylos_coffeePopupShown';

    // ─── State ─────────────────────────────────────────────────
    var totalMs     = parseInt(localStorage.getItem(KEY_ACTIVE_MS) || '0', 10) || 0;
    var popupShown  = localStorage.getItem(KEY_POPUP_SHOWN) === 'true';
    var lastTick    = Date.now();
    var lastSave    = Date.now();
    var timerEl, timerText, timerIcon;

    // ─── Styles ────────────────────────────────────────────────
    var css = ''
      + '.coffee-timer{'
      +   'display:inline-flex;align-items:center;gap:6px;'
      +   'font-family:inherit;font-variant-numeric:tabular-nums;'
      +   'font-size:10.5px;font-weight:700;letter-spacing:0.8px;'
      +   'color:rgba(255,255,255,0.7);text-transform:uppercase;'
      +   'padding:5px 11px;border-radius:99px;margin-left:14px;'
      +   'background:rgba(255,255,255,0.06);'
      +   'border:1px solid rgba(255,255,255,0.12);'
      +   'transition:all .3s ease;'
      + '}'
      + '.coffee-timer.warn{'
      +   'color:#ffdca8;background:rgba(217,119,6,0.18);'
      +   'border-color:rgba(217,119,6,0.5);'
      + '}'
      + '.coffee-timer.done{'
      +   'color:var(--lime,#6dd400);background:rgba(109,212,0,0.12);'
      +   'border-color:rgba(109,212,0,0.4);'
      + '}'
      + '.coffee-timer-icon{display:inline-block;animation:ct-steam 2.6s ease-in-out infinite;}'
      + '@keyframes ct-steam{0%,100%{transform:translateY(0)}50%{transform:translateY(-2px)}}'

      /* Popup */
      + '.ct-overlay{'
      +   'position:fixed;inset:0;background:rgba(20,30,62,0.55);'
      +   'backdrop-filter:blur(5px);-webkit-backdrop-filter:blur(5px);'
      +   'display:flex;align-items:center;justify-content:center;'
      +   'z-index:10000;padding:20px;'
      +   'animation:ct-fade .25s ease-out;'
      + '}'
      + '.ct-popup{'
      +   'background:var(--white,#fff);border-radius:12px;'
      +   'padding:44px 44px 32px;max-width:440px;width:100%;'
      +   'text-align:center;box-shadow:0 24px 60px rgba(0,0,0,0.35);'
      +   'animation:ct-pop .4s cubic-bezier(.2,1.4,.5,1);'
      +   'position:relative;'
      + '}'
      + '.ct-popup-emoji{'
      +   'font-size:72px;line-height:1;margin-bottom:18px;'
      +   'display:inline-block;animation:ct-bounce 1.6s ease-in-out infinite;'
      + '}'
      + '.ct-popup h2{'
      +   'font-family:inherit;font-size:24px;font-weight:800;'
      +   'color:var(--navy,#1e2d5a);margin:0 0 10px;letter-spacing:-0.3px;'
      + '}'
      + '.ct-popup p{'
      +   'font-family:inherit;font-size:13.5px;line-height:1.65;'
      +   'color:var(--gray-text,#6b7280);margin:0 0 28px;'
      + '}'
      + '.ct-popup .btn{min-width:200px;}'
      + '.ct-popup-hint{'
      +   'font-size:10.5px;color:var(--gray-text,#6b7280);margin-top:14px;'
      +   'text-transform:uppercase;letter-spacing:1px;font-weight:600;opacity:.7;'
      + '}'
      + '@keyframes ct-fade{from{opacity:0}to{opacity:1}}'
      + '@keyframes ct-pop{from{opacity:0;transform:scale(.88) translateY(12px)}to{opacity:1;transform:scale(1) translateY(0)}}'
      + '@keyframes ct-bounce{0%,100%{transform:translateY(0) rotate(-4deg)}50%{transform:translateY(-8px) rotate(4deg)}}';

    var styleEl = document.createElement('style');
    styleEl.textContent = css;
    document.head.appendChild(styleEl);

    // ─── Helpers ───────────────────────────────────────────────
    function formatTime(ms) {
        var total = Math.max(0, Math.ceil(ms / 1000));
        var m = Math.floor(total / 60);
        var s = total % 60;
        return (m < 10 ? '0' : '') + m + ':' + (s < 10 ? '0' : '') + s;
    }

    function buildTimer() {
        var el = document.createElement('div');
        el.className = 'coffee-timer';
        el.id = 'coffee-timer';
        el.title = 'Tijd tot je koffiepauze';
        el.innerHTML =
            '<span class="coffee-timer-icon" id="coffee-timer-icon">☕</span>' +
            '<span id="coffee-timer-text">30:00</span>';
        return el;
    }

    function placeTimer() {
        // Probeer in .nav-links (meeste pagina's) — anders in .status-bar — anders fixed rechtsboven
        var navLinks = document.querySelector('.nav-links');
        if (navLinks) {
            timerEl = buildTimer();
            navLinks.appendChild(timerEl);
            return true;
        }
        var statusBar = document.querySelector('.status-bar');
        if (statusBar) {
            timerEl = buildTimer();
            statusBar.appendChild(timerEl);
            return true;
        }
        return false;
    }

    function waitForNav(attempts) {
        attempts = attempts || 0;
        if (placeTimer()) {
            timerText = document.getElementById('coffee-timer-text');
            timerIcon = document.getElementById('coffee-timer-icon');
            render();
            return;
        }
        if (attempts > 60) return; // ~6s — nav komt blijkbaar niet, geef op zonder crash
        setTimeout(function () { waitForNav(attempts + 1); }, 100);
    }

    function render() {
        if (!timerText || !timerEl) return;
        if (popupShown || totalMs >= COFFEE_BREAK_MS) {
            timerEl.classList.remove('warn');
            timerEl.classList.add('done');
            if (timerIcon) timerIcon.textContent = '✓';
            timerText.textContent = 'Pauze gehad';
            timerEl.title = 'Je koffiepauze is geweest vandaag';
        } else {
            var remaining = COFFEE_BREAK_MS - totalMs;
            timerText.textContent = formatTime(remaining);
            // Laatste 5 minuten → oranje accent
            if (remaining <= 5 * 60 * 1000) {
                timerEl.classList.add('warn');
            }
        }
    }

    function showPopup() {
        if (popupShown) return;
        popupShown = true;
        localStorage.setItem(KEY_POPUP_SHOWN, 'true');

        var overlay = document.createElement('div');
        overlay.className = 'ct-overlay';
        overlay.innerHTML =
            '<div class="ct-popup" role="dialog" aria-labelledby="ct-title">' +
              '<div class="ct-popup-emoji">☕</div>' +
              '<h2 id="ct-title">Tijd voor koffie!</h2>' +
              '<p>Je bent al 30 minuten onafgebroken bezig met de Migration Engine. ' +
                 'Strek even je benen, haal een verse koffie en kom er straks weer fris bij.</p>' +
              '<button class="btn btn-primary" id="ct-close-btn">' +
                '<span class="btn-text">Lekker, pauze!</span>' +
              '</button>' +
              '<div class="ct-popup-hint">Deze melding verschijnt maar één keer</div>' +
            '</div>';

        document.body.appendChild(overlay);

        function close() {
            overlay.style.animation = 'ct-fade .2s ease-out reverse';
            setTimeout(function () { if (overlay.parentNode) overlay.parentNode.removeChild(overlay); }, 180);
        }
        overlay.querySelector('#ct-close-btn').addEventListener('click', close);
        overlay.addEventListener('click', function (e) { if (e.target === overlay) close(); });
        document.addEventListener('keydown', function esc(e) {
            if (e.key === 'Escape') { close(); document.removeEventListener('keydown', esc); }
        });

        render();
    }

    // ─── Tick loop ─────────────────────────────────────────────
    function tick() {
        var now = Date.now();
        var elapsed = now - lastTick;
        lastTick = now;

        // Alleen tijd tellen als de tab zichtbaar is en elapsed redelijk is
        // (bv. als laptop in slaap ging: elapsed = uren → niet meetellen)
        if (document.visibilityState === 'visible' && elapsed > 0 && elapsed < 5000) {
            totalMs += elapsed;
        }

        if (now - lastSave >= SAVE_EVERY_MS) {
            try { localStorage.setItem(KEY_ACTIVE_MS, String(totalMs)); } catch (e) {}
            lastSave = now;
        }

        render();

        if (!popupShown && totalMs >= COFFEE_BREAK_MS) {
            showPopup();
        }
    }

    // Bij tab wissel: reset lastTick zodat verborgen tijd niet geteld wordt
    document.addEventListener('visibilitychange', function () {
        lastTick = Date.now();
    });

    // Laatste stand wegschrijven vóór navigatie/sluiten
    window.addEventListener('beforeunload', function () {
        try { localStorage.setItem(KEY_ACTIVE_MS, String(totalMs)); } catch (e) {}
    });

    // ─── Init ──────────────────────────────────────────────────
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function () { waitForNav(0); });
    } else {
        waitForNav(0);
    }
    setInterval(tick, TICK_MS);

    // ─── Debug helper (optioneel) ──────────────────────────────
    // Typ in console:  coffeeTimerReset()   om alles te resetten
    window.coffeeTimerReset = function () {
        localStorage.removeItem(KEY_ACTIVE_MS);
        localStorage.removeItem(KEY_POPUP_SHOWN);
        totalMs = 0;
        popupShown = false;
        if (timerEl) {
            timerEl.classList.remove('done', 'warn');
            if (timerIcon) timerIcon.textContent = '☕';
        }
        render();
        console.log('[coffee-timer] reset — de popup zal opnieuw verschijnen na 30 min');
    };
})();