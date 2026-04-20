#!/bin/bash
exec > >(tee /var/log/startup.log) 2>&1
echo "Setup gestart: $(date)"

# Voorkom dat script twee keer uitgevoerd wordt
if [ -f /var/log/startup_done ]; then
    echo "Setup al uitgevoerd, script wordt overgeslagen."
    exit 0
fi

# Node.js 18
echo "[1/8] Node.js installeren..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Build tools
echo "[2/8] Build tools installeren..."
sudo apt-get install -y build-essential python3

# PowerShell
echo "[3/8] PowerShell installeren..."
wget -q https://packages.microsoft.com/config/debian/11/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y powershell

# PowerShell Graph modules installeren
echo "[3b/8] PowerShell Graph modules installeren..."
pwsh -NonInteractive -Command "
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module -Name Microsoft.Graph.Authentication -Force -Scope AllUsers
    Install-Module -Name Microsoft.Graph.Beta.Identity.SignIns -Force -Scope AllUsers
    Install-Module -Name Microsoft.Graph.Beta.DeviceManagement -Force -Scope AllUsers
    Install-Module -Name Microsoft.Graph.Beta.DeviceManagement.Actions -Force -Scope AllUsers
    Install-Module -Name Microsoft.Graph.Applications -Force -Scope AllUsers
    Install-Module -Name Microsoft.Graph.Identity.SignIns -Force -Scope AllUsers
    Write-Host 'PS modules geinstalleerd'
"

# Nginx + Certbot
echo "[4/8] Nginx en Certbot installeren..."
sudo apt-get install -y nginx certbot python3-certbot-nginx

# PM2
echo "[5/8] PM2 installeren..."
sudo npm install -g pm2

# App bestanden van GitHub halen
echo "[6/8] App klonen van GitHub..."
sudo apt-get install -y git
sudo mkdir -p /opt/app
GIT_TERMINAL_PROMPT=0 git clone https://github.com/LucasProfetaPXL/stage.git /opt/app

if [ ! -f /opt/app/server.js ]; then
    echo "FOUT: Git clone mislukt - server.js niet gevonden!"
    exit 1
fi

cd /opt/app
npm install
npm install better-sqlite3 --build-from-source

# Fixes toepassen op code
echo "[6b] Code fixes toepassen..."

# Fix 1: powershell.exe naar pwsh in server.js
sed -i "s/spawn('powershell.exe'/spawn('pwsh'/g" /opt/app/server.js
echo "server.js: powershell.exe vervangen door pwsh"

# Fix 2: -File naar -Command met 6>&1 zodat device code zichtbaar is in browser
# Vervangt de spawn aanroep om PowerShell stream 6 (Write-Host) door te sturen naar stdout
python3 - <<'PYEOF'
import re

with open('/opt/app/server.js', 'r') as f:
    content = f.read()

old = """    const ps = spawn('pwsh', [
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...psArgs
    ], { env: process.env });"""

new = """    const escapedPath = scriptPath.replace(/'/g, "''");
    const argsStr = psArgs.map(a => {
        if (a.startsWith('-')) return a;
        return `'${a.replace(/'/g, "''")}'`;
    }).join(' ');

    const ps = spawn('pwsh', [
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-Command', `& '${escapedPath}' ${argsStr} 6>&1`
    ], { env: process.env });"""

if old in content:
    content = content.replace(old, new)
    with open('/opt/app/server.js', 'w') as f:
        f.write(content)
    print("server.js: 6>&1 fix toegepast")
else:
    print("server.js: spawn patroon niet gevonden - fix overgeslagen")
PYEOF

# Fix 3: isUtils check toevoegen als die nog niet bestaat
python3 - <<'PYEOF'
with open('/opt/app/server.js', 'r') as f:
    content = f.read()

if 'isUtils' not in content:
    old = "    const isFixJson = rawPath.toLowerCase().includes('fix_json');"
    new = """    const isFixJson = rawPath.toLowerCase().includes('fix_json');
    const isUtils   = rawPath.toLowerCase().includes('utils');"""
    content = content.replace(old, new)

    old = "    } else {\n        psArgs.push('-BackupDir', userBackupDir);"
    new = "    } else if (!isUtils) {\n        psArgs.push('-BackupDir', userBackupDir);"
    content = content.replace(old, new)

    with open('/opt/app/server.js', 'w') as f:
        f.write(content)
    print("server.js: isUtils fix toegepast")
else:
    print("server.js: isUtils fix al aanwezig")
PYEOF

# Fix 4: localhost URLs verwijderen in HTML bestanden
sed -i 's|http://localhost:3000/api/run/|/api/run/|g' /opt/app/public/policy-migration.html
sed -i 's|http://localhost:3000/api/json-files/|/api/json-files/|g' /opt/app/public/policy-migration.html
sed -i 's|http://localhost:3000/api/run/|/api/run/|g' /opt/app/public/full-migration.html
sed -i 's|http://localhost:3000/api/run/|/api/run/|g' /opt/app/public/group-migration.html
sed -i 's|http://localhost:3000/api/run/|/api/run/|g' /opt/app/public/prepare.html
echo "HTML: localhost URLs vervangen"

# Fix 5: Alias CustomerTenantId toevoegen aan utils PS1 scripts
for ps1file in /opt/app/public/scripts/utils/Create_SourceTenant_App.ps1 /opt/app/public/scripts/utils/Create_DestTenant_App.ps1; do
    if [ -f "$ps1file" ]; then
        if ! grep -q "Alias('CustomerTenantId')" "$ps1file"; then
            sed -i "s/\[Parameter(Mandatory=\$true)\] \[string\]\$TenantId,/[Parameter(Mandatory=\$true)]\n    [Alias('CustomerTenantId')]\n    [string]\$TenantId,/" "$ps1file"
            echo "PS1 alias fix toegepast op $ps1file"
        else
            echo "PS1 alias fix al aanwezig in $ps1file"
        fi
    fi
done

# Fix 6: git safe directory instellen
git config --global --add safe.directory /opt/app
echo "Git: safe directory ingesteld"

# Session secret genereren
echo "[7/8] Session secret instellen..."
if ! grep -q "SESSION_SECRET" /etc/environment; then
    echo "SESSION_SECRET=$(openssl rand -hex 32)" | sudo tee -a /etc/environment
fi
source /etc/environment

# PM2 startup configureren voor app start
export HOME=/root
pm2 startup systemd -u root --hp /root
systemctl enable pm2-root

# App starten via PM2
cd /opt/app
HOME=/root pm2 start server.js --name "migration_engine"
HOME=/root pm2 save --force

# Nginx configureren
echo "[8/8] Nginx configureren..."
sudo rm -f /etc/nginx/sites-enabled/default
sudo rm -f /etc/nginx/sites-available/default

sudo tee /etc/nginx/sites-available/migration_engine > /dev/null <<EOF
server {
    listen 80;
    server_name ${domain_name};

    location / {
        proxy_pass         http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout    300;
        proxy_connect_timeout 300;
        proxy_send_timeout    300;
        proxy_buffering       off;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/migration_engine /etc/nginx/sites-enabled/migration_engine
sudo nginx -t
sudo systemctl start nginx
sudo systemctl enable nginx
sleep 5

# SSL certificaat bewaren/herstellen
echo "[SSL] Certificaat controleren..."

if gsutil -q stat gs://xylos-terraform-state/ssl-backup/fullchain.pem 2>/dev/null; then
    echo "Bestaand certificaat gevonden in GCS - herstellen..."
    mkdir -p /tmp/ssl-backup
    gsutil cp gs://xylos-terraform-state/ssl-backup/* /tmp/ssl-backup/

    sudo mkdir -p /etc/letsencrypt/live/${domain_name}
    sudo mkdir -p /etc/letsencrypt/archive/${domain_name}

    sudo cp /tmp/ssl-backup/fullchain.pem /etc/letsencrypt/live/${domain_name}/fullchain.pem
    sudo cp /tmp/ssl-backup/privkey.pem   /etc/letsencrypt/live/${domain_name}/privkey.pem
    sudo cp /tmp/ssl-backup/chain.pem     /etc/letsencrypt/live/${domain_name}/chain.pem
    sudo cp /tmp/ssl-backup/cert.pem      /etc/letsencrypt/live/${domain_name}/cert.pem

    sudo certbot --nginx -d ${domain_name} --non-interactive --agree-tos -m ${email} --reinstall 2>/dev/null || \
    sudo certbot install --nginx -d ${domain_name} --cert-name ${domain_name} --non-interactive 2>/dev/null || \
    echo "WAARSCHUWING: Certbot reinstall mislukt - Nginx handmatig configureren voor SSL..."

    sudo tee /etc/nginx/sites-available/migration_engine > /dev/null <<EOF2
server {
    listen 80;
    server_name ${domain_name};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name ${domain_name};
    ssl_certificate     /etc/letsencrypt/live/${domain_name}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain_name}/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        proxy_pass         http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout    300;
        proxy_connect_timeout 300;
        proxy_send_timeout    300;
        proxy_buffering       off;
    }
}
EOF2
    sudo nginx -t && sudo systemctl reload nginx
    echo "SSL hersteld van GCS backup!"

else
    echo "Geen backup gevonden - nieuw certificaat aanvragen..."

    # Probeer eerst Let's Encrypt
    SSL_OK=false
    if sudo certbot --nginx -d ${domain_name} --non-interactive --agree-tos -m ${email}; then
        SSL_OK=true
        echo "SSL certificaat succesvol aangemaakt via Let's Encrypt!"
    fi

    # Fallback: ZeroSSL als Let's Encrypt rate limit bereikt
    if [ "$SSL_OK" = false ]; then
        echo "Let's Encrypt mislukt - ZeroSSL proberen..."
        if [ -n "${zerossl_kid}" ] && [ -n "${zerossl_hmac}" ]; then
            if sudo certbot --nginx \
              -d ${domain_name} \
              --non-interactive \
              --agree-tos \
              -m ${email} \
              --server https://acme.zerossl.com/v2/DV90 \
              --eab-kid "${zerossl_kid}" \
              --eab-hmac-key "${zerossl_hmac}"; then
                SSL_OK=true
                echo "SSL certificaat succesvol aangemaakt via ZeroSSL!"
            fi
        fi
    fi

    if [ "$SSL_OK" = true ]; then
        sudo tee /etc/systemd/system/certbot-renew.service > /dev/null <<'CERTBOT_SERVICE'
[Unit]
Description=Certbot Renewal

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --quiet --deploy-hook "systemctl reload nginx"
CERTBOT_SERVICE

        sudo tee /etc/systemd/system/certbot-renew.timer > /dev/null <<'CERTBOT_TIMER'
[Unit]
Description=Run certbot renewal twice daily

[Timer]
OnCalendar=*-*-* 00,12:00:00
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
CERTBOT_TIMER

        sudo systemctl daemon-reload
        sudo systemctl enable certbot-renew.timer
        sudo systemctl start certbot-renew.timer
        sudo systemctl reload nginx
        echo "Auto-renewal geconfigureerd!"
    else
        echo ""
        echo "WAARSCHUWING: SSL MISLUKT - app draait op HTTP only."
        echo "VM IP: $(curl -s ifconfig.me)"
        echo ""
        echo "Fix nadien handmatig met:"
        echo "  sudo certbot --nginx -d ${domain_name} --email ${email}"
    fi
fi

# Certificaat opslaan in GCS
if [ -f /etc/letsencrypt/live/${domain_name}/fullchain.pem ]; then
    gsutil cp /etc/letsencrypt/live/${domain_name}/*.pem gs://xylos-terraform-state/ssl-backup/
    echo "Certificaat opgeslagen in GCS voor hergebruik"
fi

# Markeer setup als klaar
touch /var/log/startup_done

echo ""
echo "Setup voltooid: $(date)"
echo "Standaard login: admin / Admin@Xylos123!"
echo "Verander het wachtwoord meteen na de eerste login!"