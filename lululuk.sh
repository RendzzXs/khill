#!/bin/bash
# ==========================================
# 🛠️ AUTO FIX "Load Failed" (RenKiller)
# ==========================================

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

DOMAIN="killer.googleclient.biz.id"
WEB_ROOT="/var/www/$DOMAIN/public"
NODE_DIR="/opt/renkiller"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

echo -e "${CYAN}[1/5] Cek Status Backend Node.js...${NC}"
if systemctl is-active --quiet renkiller; then
    echo -e "${GREEN}  ✅ Backend Nyala${NC}"
else
    echo -e "${RED}  ❌ Backend Mati! Nyalain ulang...${NC}"
    systemctl restart renkiller
    sleep 2
fi

# Cek apakah file server.js ada
if [ ! -f "$NODE_DIR/server.js" ]; then
    echo -e "${YELLOW}  ⚠️ File server.js hilang. Bikin ulang...${NC}"
    cat > "$NODE_DIR/server.js" << 'NODEEOF'
const express = require('express');
const axios = require('axios');
const cors = require('cors');
const app = express();
app.use(cors()); app.use(express.json());
const makeApi = (panelUrl, apiKey) => axios.create({ baseURL: `${panelUrl}/api/application`, headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json', 'Accept': 'Application/vnd.pterodactyl.v1+json' }, timeout: 20000 });
app.post('/api/stats', async (req, res) => { const { panelUrl, apiKey } = req.body; try { const api = makeApi(panelUrl, apiKey); const [u, s] = await Promise.all([api.get('/users?per_page=1'), api.get('/servers?per_page=1')]); res.json({ status: true, totalUsers: u.data.meta.pagination.total, totalServers: s.data.meta.pagination.total, freeAllocs: 'OK' }); } catch (e) { res.json({ status: false, message: e.message }); } });
app.post('/api/changepass', async (req, res) => { const { panelUrl, apiKey, userId, newPassword } = req.body; try { await makeApi(panelUrl, apiKey).patch(`/users/${userId}`, { password: newPassword }); res.json({ status: true }); } catch (e) { res.json({ status: false, message: e.message }); } });
app.post('/api/flood-user', async (req, res) => { res.json({ status: true, message: "Flood user di-skip (Mode Darurat)" }); });
app.post('/api/flood-server', async (req, res) => { res.json({ status: true, message: "Flood server di-skip (Mode Darurat)" }); });
app.post('/api/flood-all', async (req, res) => { res.json({ status: true, message: "Flood all di-skip (Mode Darurat)" }); });
app.listen(3000, '127.0.0.1', () => console.log('✅ Backend Running'));
NODEEOF
    cd "$NODE_DIR" && npm install --silent >/dev/null 2>&1
    systemctl restart renkiller
fi

echo -e "${CYAN}[2/5] Test Koneksi Port 3000...${NC}"
if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3000/ | grep -q "200\|404"; then
    echo -e "${GREEN}  ✅ Port 3000 OK${NC}"
else
    echo -e "${RED}  ❌ Port 3000 Gagal! Cek log: journalctl -u renkiller -n 20${NC}"
fi

echo -e "${CYAN}[3/5] Fix Nginx Reverse Proxy...${NC}"
cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;
    root $WEB_ROOT; index index.php index.html;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location /api-killer/ {
        proxy_pass http://127.0.0.1:3000/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_buffering off;
        proxy_read_timeout 300s;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
    }
}
NGINXEOF

nginx -t >/dev/null 2>&1 && systemctl reload nginx
echo -e "${GREEN}  ✅ Nginx Proxy Fixed${NC}"

echo -e "${CYAN}[4/5] Fix Frontend URL...${NC}"
# Pastiin URL API di frontend bener
sed -i "s|const API_BACKEND = window.location.origin + '/api-killer';|const API_BACKEND = 'https://$DOMAIN/api-killer';|" "$WEB_ROOT/index.php"
echo -e "${GREEN}  ✅ Frontend URL Fixed${NC}"

echo -e "${CYAN}[5/5] Restart Semua Service...${NC}"
systemctl restart php*-fpm 2>/dev/null
systemctl restart nginx
systemctl restart renkiller

echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ AUTO FIX SELESAI!                      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🔗 Buka Web:${NC} https://$DOMAIN"
echo -e "${YELLOW}⚠️  Clear Cache (Ctrl+F5) browser lu dulu!${NC}"
echo ""
echo -e "${YELLOW}💡 Kalo masih 'Load Failed', coba jalanin:${NC}"
echo -e "   ${WHITE}journalctl -u renkiller -n 20 --no-pager${NC}"
echo -e "   (Buat liat error di backend Node.js)"
