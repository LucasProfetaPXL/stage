#!/bin/bash
set -e

echo "──────────────────────────────────────"
echo " Xylos Migration Engine — VM Setup"
echo "──────────────────────────────────────"

# ─── Node.js 18 ───────────────────────────────────────────
echo "[1/7] Node.js installeren..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# ─── Nginx + Certbot ──────────────────────────────────────
echo "[2/7] Nginx en Certbot installeren..."
sudo apt-get install -y nginx certbot python3-certbot-nginx

# ─── PM2 ──────────────────────────────────────────────────
echo "[3/7] PM2 installeren..."
sudo npm install -g pm2

# ─── App bestanden klaarzetten ────────────────────────────
echo "[4/7] App map aanmaken en dependencies installeren..."
sudo mkdir -p /home/debian/app
sudo chown -R debian:debian /home/debian/app
cd /home/debian/app
npm install

# ─── Session secret genereren ─────────────────────────────
echo "[5/7] Session secret instellen..."
if ! grep -q "SESSION_SECRET" /etc/environment; then
    echo "SESSION_SECRET=$(openssl rand -hex 32)" | sudo tee -a /etc/environment
fi
source /etc/environment

# ─── App starten via PM2 ──────────────────────────────────
echo "[6/7] App starten via PM2..."
cd /home/debian/app
pm2 start server.js --name "migration_engine"
pm2 startup systemd -u debian --hp /home/debian
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

# Standaard Nginx site uitzetten en onze site aanzetten
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

# Certbot auto-renewal controleren
sudo systemctl enable certbot.timer

echo ""
echo "✅ Setup voltooid!"
echo "   App bereikbaar op: https://${domain_name}"
echo "   Standaard login:   admin / Admin@Xylos123!"
echo "   ⚠️  Verander het wachtwoord meteen na de eerste login!"