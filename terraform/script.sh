#!/bin/bash
exec > >(tee /var/log/startup.log) 2>&1
echo "Setup gestart: $(date)"

# ─── Voorkom dat script twee keer uitgevoerd wordt ───────
if [ -f /var/log/startup_done ]; then
    echo "Setup al uitgevoerd, script wordt overgeslagen."
    exit 0
fi

# ─── Node.js 18 ───────────────────────────────────────────
echo "[1/8] Node.js installeren..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# ─── Build tools ──────────────────────────────────────────
echo "[2/8] Build tools installeren..."
sudo apt-get install -y build-essential python3

# ─── PowerShell ───────────────────────────────────────────
echo "[3/8] PowerShell installeren..."
wget -q https://packages.microsoft.com/config/debian/11/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y powershell

# ─── Nginx + Certbot ──────────────────────────────────────
echo "[4/8] Nginx en Certbot installeren..."
sudo apt-get install -y nginx certbot python3-certbot-nginx

# ─── PM2 ──────────────────────────────────────────────────
echo "[5/8] PM2 installeren..."
sudo npm install -g pm2

# ─── App bestanden van GitHub halen ───────────────────────
echo "[6/8] App klonen van GitHub..."
sudo apt-get install -y git
sudo mkdir -p /opt/app
GIT_TERMINAL_PROMPT=0 git clone https://github.com/LucasProfetaPXL/stage.git /opt/app
cd /opt/app
npm install

# ─── Session secret genereren ─────────────────────────────
echo "[7/8] Session secret instellen..."
if ! grep -q "SESSION_SECRET" /etc/environment; then
    echo "SESSION_SECRET=$(openssl rand -hex 32)" | sudo tee -a /etc/environment
fi
source /etc/environment

# ─── PM2 startup configureren VOOR app start ─────────────
export HOME=/root
pm2 startup systemd -u root --hp /root
systemctl enable pm2-root

# ─── App starten via PM2 ──────────────────────────────────
cd /opt/app
HOME=/root pm2 start server.js --name "migration_engine"
HOME=/root pm2 save --force

# ─── Nginx configureren (HTTP eerst) ─────────────────────
echo "[8/8] Nginx configureren..."
sudo rm -f /etc/nginx/sites-enabled/default

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
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/migration_engine /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl start nginx
sudo systemctl enable nginx
sleep 5

# ─── Let's Encrypt certificaat ────────────────────────────
echo "[SSL] Certbot certificaat aanvragen voor ${domain_name}..."
if sudo certbot --nginx \
  -d ${domain_name} \
  --non-interactive \
  --agree-tos \
  -m ${email}; then

    echo "✅ SSL certificaat succesvol aangemaakt!"

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

    echo "✅ Auto-renewal geconfigureerd!"
    echo "   App bereikbaar op: https://${domain_name}"

else
    echo ""
    echo "⚠️  SSL MISLUKT - app draait op HTTP only."
    echo "   VM IP: $(curl -s ifconfig.me)"
    echo ""
    echo "Fix nadien handmatig met:"
    echo "  sudo certbot --nginx -d ${domain_name} --email ${email}"
fi

# ─── Markeer setup als klaar ─────────────────────────────
touch /var/log/startup_done

echo ""
echo "✅ Setup voltooid: $(date)"
echo "   Standaard login: admin / Admin@Xylos123!"
echo "   ⚠️  Verander het wachtwoord meteen na de eerste login!"