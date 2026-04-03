#!/bin/bash
set -e

# ── Node.js ──────────────────────────────────────────────
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# ── Nginx + Certbot ──────────────────────────────────────
sudo apt-get install -y nginx certbot python3-certbot-nginx

# ── PM2 ──────────────────────────────────────────────────
sudo npm install -g pm2

# ── App starten ──────────────────────────────────────────
cd /home/debian/app
npm install
pm2 start server.js --name "migration_tool"
pm2 startup systemd -u debian --hp /home/debian
pm2 save

# ── Nginx config ─────────────────────────────────────────
sudo tee /etc/nginx/sites-available/migration_tool > /dev/null <<EOF
server {
    listen 80;
    server_name ${domain_name};

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/migration_tool /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# ── Let's Encrypt certificaat ────────────────────────────
sudo certbot --nginx \
  -d ${domain_name} \
  --non-interactive \
  --agree-tos \
  -m ${email}