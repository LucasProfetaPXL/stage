#!/bin/bash
set -e

echo "──────────────────────────────────────"
echo " Xylos Migration Engine — VM Setup"
echo "──────────────────────────────────────"

# ─── Node.js 18 ───────────────────────────────────────────
echo "[1/7] Node.js installeren..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# ─── Build tools ──────────────────────────────────────────
echo "[1b] Build tools installeren..."
sudo apt-get install -y build-essential python3

# ─── Nginx + Certbot ──────────────────────────────────────
echo "[2/7] Nginx en Certbot installeren..."
sudo apt-get install -y nginx certbot python3-certbot-nginx

# ─── PM2 ──────────────────────────────────────────────────
echo "[3/7] PM2 installeren..."
sudo npm install -g pm2

# ─── App bestanden van GitHub halen ───────────────────────
echo "[4/7] App klonen van GitHub..."
sudo apt-get install -y git
sudo mkdir -p /opt/app
export GIT_TERMINAL_PROMPT=0
git clone https://github.com/LucasProfetaP/stage.git /opt/app
cd /opt/app
npm install

# ─── Session secret genereren ─────────────────────────────
echo "[5/7] Session secret instellen..."
if ! grep -q "SESSION_SECRET" /etc/environment; then
    echo "SESSION_SECRET=$(openssl rand -hex 32)" | sudo tee -a /etc/environment
fi
source /etc/environment

# ─── App starten via PM2 ──────────────────────────────────
echo "[6/7] App starten via PM2..."
cd /opt/app
pm2 start server.js --name "migration_engine"
pm2 startup systemd -u root --hp /root
pm2 save

# ─── Nginx configureren ───────────────────────────────────
echo "[7/7] Nginx en SSL configureren..."
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

sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/migration_engine /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# ─── Let's Encrypt certificaat ────────────────────────────
echo "[SSL] Certbot certificaat aanvragen voor ${domain_name}..."
sudo certbot --nginx \
  -d ${domain_name} \
  --non-interactive \
  --agree-tos \
  -m ${email}

sudo systemctl enable certbot.timer

echo ""
echo "✅ Setup voltooid!"
echo "   App bereikbaar op: https://${domain_name}"
echo "   Standaard login:   admin / Admin@Xylos123!"
echo "   ⚠️  Verander het wachtwoord meteen na de eerste login!"