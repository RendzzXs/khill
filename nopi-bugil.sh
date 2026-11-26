
#!/bin/bash
set -Eeuo pipefail

# ==========================================
# RENKILLER v6.0 - STABLE EDITION
# Pterodactyl Read-Only Management Dashboard
# ==========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

DOMAIN="killer.googleclient.biz.id"
NODE_DIR="/opt/renkiller"
WEB_ROOT="/var/www/${DOMAIN}/public"
NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}"
ENV_FILE="/etc/renkiller.env"

[[ $EUID -eq 0 ]] || {
  echo "Jalankan sebagai root!"
  exit 1
}

echo -e "${CYAN}"
echo "===================================="
echo "       RENKILLER v6.0 UPDATE"
echo "===================================="
echo -e "${NC}"

# ==========================================
# 1. INPUT CONFIGURATION
# ==========================================

read -rp "Panel URL: " PANEL_URL
PANEL_URL="${PANEL_URL%/}"

read -rsp "New Pterodactyl Application API Key: " API_KEY
echo

read -rp "Node ID (default 1): " NODE_ID
NODE_ID="${NODE_ID:-1}"

read -rp "Dashboard username: " DASH_USER
read -rsp "Dashboard password: " DASH_PASS
echo

[[ "$PANEL_URL" =~ ^https?:// ]] || {
  echo "Panel URL tidak valid"
  exit 1
}

[[ -n "$API_KEY" && -n "$DASH_USER" && -n "$DASH_PASS" ]] || {
  echo "Konfigurasi tidak boleh kosong"
  exit 1
}

# ==========================================
# 2. INSTALL DEPENDENCIES
# ==========================================

echo -e "${YELLOW}[1/6] Installing dependencies...${NC}"

apt-get update -y

apt-get install -y \
  nginx \
  nodejs \
  npm \
  apache2-utils \
  curl \
  ca-certificates

node --version
npm --version

mkdir -p "$NODE_DIR" "$WEB_ROOT"

# ==========================================
# 3. NODE.JS BACKEND
# ==========================================

echo -e "${YELLOW}[2/6] Installing backend...${NC}"

cd "$NODE_DIR"

cat > package.json <<'EOF'
{
  "name": "renkiller",
  "version": "6.0.0",
  "private": true,
  "main": "server.js",
  "dependencies": {
    "express": "^4.21.2",
    "axios": "^1.7.9"
  }
}
EOF

npm install --omit=dev --no-audit --no-fund

cat > server.js <<'EOF'
const express = require('express');
const axios = require('axios');

const app = express();

const PORT = 3000;
const HOST = '127.0.0.1';

app.disable('x-powered-by');
app.use(express.json({ limit: '10kb' }));

const PANEL_URL = (process.env.PANEL_URL || '').replace(/\/+$/, '');
const API_KEY = process.env.PANEL_API_KEY || '';
const NODE_ID = Number(process.env.NODE_ID || 1);

function getApi() {
    if (!PANEL_URL || !API_KEY) {
        throw new Error('Panel configuration belum tersedia');
    }

    return axios.create({
        baseURL: PANEL_URL + '/api/application',
        timeout: 15000,
        headers: {
            Authorization: 'Bearer ' + API_KEY,
            Accept: 'Application/vnd.pterodactyl.v1+json',
            'Content-Type': 'application/json'
        }
    });
}

app.get('/api/health', (req, res) => {
    res.json({
        status: true,
        service: 'RenKiller',
        version: '6.0.0',
        uptime: Math.floor(process.uptime()),
        timestamp: new Date().toISOString()
    });
});

app.get('/api/stats', async (req, res) => {
    try {
        const api = getApi();

        const [users, servers] = await Promise.all([
            api.get('/users?per_page=1'),
            api.get('/servers?per_page=1')
        ]);

        let freeAllocs = 0;
        let totalAllocs = 0;

        try {
            let page = 1;
            let totalPages = 1;

            do {
                const result = await api.get(
                    `/nodes/${NODE_ID}/allocations?per_page=100&page=${page}`
                );

                const rows = result.data.data || [];

                totalAllocs += rows.length;

                freeAllocs += rows.filter(
                    item => !item.attributes.assigned
                ).length;

                totalPages =
                    result.data.meta.pagination.total_pages || 1;

                page++;
            } while (page <= totalPages);

        } catch (error) {
            console.error('Allocation error:', error.message);
            freeAllocs = null;
        }

        res.json({
            status: true,
            panel: PANEL_URL,
            totalUsers:
                users.data.meta.pagination.total,
            totalServers:
                servers.data.meta.pagination.total,
            totalAllocations: totalAllocs,
            freeAllocations: freeAllocs,
            timestamp: new Date().toISOString()
        });

    } catch (error) {
        const status = error.response?.status || 502;

        console.error(
            'Pterodactyl API error:',
            status,
            error.response?.data || error.message
        );

        res.status(502).json({
            status: false,
            httpStatus: status,
            message: error.response?.data?.errors?.[0]?.detail
                || error.message
        });
    }
});

app.listen(PORT, HOST, () => {
    console.log('RenKiller v6.0 running');
    console.log(`Backend: http://${HOST}:${PORT}`);
});
EOF

# ==========================================
# 4. ENVIRONMENT CONFIGURATION
# ==========================================

echo -e "${YELLOW}[3/6] Configuring secure environment...${NC}"

cat > "$ENV_FILE" <<EOF
PANEL_URL=$PANEL_URL
PANEL_API_KEY=$API_KEY
NODE_ID=$NODE_ID
NODE_ENV=production
EOF

chown root:www-data "$ENV_FILE"
chmod 640 "$ENV_FILE"

# ==========================================
# 5. SYSTEMD SERVICE
# ==========================================

echo -e "${YELLOW}[4/6] Creating systemd service...${NC}"

cat > /etc/systemd/system/renkiller.service <<'EOF'
[Unit]
Description=RenKiller v6.0 Backend
After=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/renkiller
EnvironmentFile=/etc/renkiller.env
ExecStart=/usr/bin/node /opt/renkiller/server.js
Restart=always
RestartSec=5

NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

chown -R root:www-data "$NODE_DIR"
chmod -R 750 "$NODE_DIR"

systemctl daemon-reload
systemctl enable renkiller
systemctl restart renkiller

# ==========================================
# 6. FRONTEND
# ==========================================

echo -e "${YELLOW}[5/6] Creating dashboard...${NC}"

cat > "$WEB_ROOT/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>RenKiller v6.0</title>

<style>
*{box-sizing:border-box}
body{
 margin:0;background:#080808;color:white;
 font-family:Arial,sans-serif;padding:20px;
}
.container{max-width:950px;margin:auto}
header{
 border-bottom:1px solid #292929;
 padding-bottom:20px;margin-bottom:25px;
}
h1{color:#ff1744;margin:0}
.sub{color:#888;font-size:12px;letter-spacing:2px}
.status{
 display:inline-block;color:#00ed83;
 background:#062619;padding:9px 14px;
 border-radius:30px;margin-top:15px;
 font-size:12px;
}
.grid{
 display:grid;grid-template-columns:repeat(3,1fr);
 gap:14px;margin-bottom:20px;
}
.card{
 background:#131313;border:1px solid #292929;
 border-radius:12px;padding:20px;
}
.card small{color:#888}
.number{font-size:30px;font-weight:bold;margin-top:12px}
.red{color:#ff1744}
.green{color:#00ed83}
button{
 background:#ff1744;color:white;border:0;
 padding:13px 18px;border-radius:8px;
 font-weight:bold;cursor:pointer;
}
button:disabled{opacity:.5}
.terminal{
 background:#000;border:1px solid #333;
 padding:18px;border-radius:10px;
 margin-top:20px;min-height:120px;
 font-family:monospace;overflow-wrap:anywhere;
}
.line{margin-bottom:10px;color:#aaa}
@media(max-width:600px){
 .grid{grid-template-columns:1fr}
}
</style>
</head>

<body>
<div class="container">

<header>
<h1>☠ RenKiller v6.0</h1>
<p class="sub">PTERODACTYL MANAGEMENT SYSTEM</p>
<div class="status" id="status">● CHECKING BACKEND...</div>
</header>

<div class="grid">

<div class="card">
<small>TOTAL USERS</small>
<div class="number" id="users">-</div>
</div>

<div class="card">
<small>TOTAL SERVERS</small>
<div class="number red" id="servers">-</div>
</div>

<div class="card">
<small>FREE ALLOCATIONS</small>
<div class="number green" id="allocs">-</div>
</div>

<div class="card">
<small>TOTAL ALLOCATIONS</small>
<div class="number" id="totalAlloc">-</div>
</div>

<div class="card">
<small>BACKEND UPTIME</small>
<div class="number" id="uptime">-</div>
</div>

<div class="card">
<small>VERSION</small>
<div class="number red">6.0.0</div>
</div>

</div>

<div class="card">
<h3>⚙ Panel Connection</h3>
<p id="panel">Memeriksa koneksi...</p>
<button onclick="refresh()">↻ REFRESH DATA</button>
</div>

<div class="terminal" id="terminal">
<div class="line">[SYSTEM] RenKiller initialized...</div>
</div>

</div>

<script>
const $ = id => document.getElementById(id);

function log(message){
 const line=document.createElement('div');
 line.className='line';
 line.textContent='['+new Date().toLocaleTimeString()+'] '+message;
 $('terminal').prepend(line);
}

async function refresh(){
 const button=document.querySelector('button');
 button.disabled=true;

 try{
  const health=await fetch('/api/health',{cache:'no-store'});
  if(!health.ok) throw new Error('Backend offline');

  const h=await health.json();

  $('status').textContent='● BACKEND ONLINE';
  $('status').style.color='#00ed83';
  $('uptime').textContent=Math.floor(h.uptime/60)+' min';

  const response=await fetch('/api/stats',{cache:'no-store'});
  const data=await response.json();

  if(!data.status) throw new Error(data.message);

  $('users').textContent=data.totalUsers;
  $('servers').textContent=data.totalServers;
  $('allocs').textContent=data.freeAllocations ?? 'N/A';
  $('totalAlloc').textContent=data.totalAllocations;
  $('panel').textContent='Connected: '+data.panel;

  log('Pterodactyl synchronization successful');

 }catch(error){
  $('status').textContent='● CONNECTION ERROR';
  $('status').style.color='#ff1744';
  $('panel').textContent=error.message;
  log('ERROR: '+error.message);
 }finally{
  button.disabled=false;
 }
}

refresh();
setInterval(refresh,30000);
</script>

</body>
</html>
EOF

chown -R www-data:www-data "/var/www/$DOMAIN"

# ==========================================
# NGINX
# ==========================================

echo -e "${YELLOW}[6/6] Configuring Nginx...${NC}"

if [ -f "$NGINX_CONF" ]; then
  cp "$NGINX_CONF" "${NGINX_CONF}.backup.$(date +%s)"
fi

htpasswd -bc /etc/nginx/.renkiller_htpasswd \
  "$DASH_USER" "$DASH_PASS"

chown root:www-data /etc/nginx/.renkiller_htpasswd
chmod 640 /etc/nginx/.renkiller_htpasswd

cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name $DOMAIN;

    root $WEB_ROOT;
    index index.html;

    auth_basic "RenKiller Private Dashboard";
    auth_basic_user_file /etc/nginx/.renkiller_htpasswd;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:3000/api/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_connect_timeout 10s;
        proxy_read_timeout 30s;
        proxy_buffering off;
    }

    location ~ /\. {
        deny all;
    }
}
EOF

ln -sfn "$NGINX_CONF" "/etc/nginx/sites-enabled/$DOMAIN"

nginx -t

systemctl reload nginx
systemctl restart renkiller

# ==========================================
# FINAL CHECK
# ==========================================

echo ""
echo "======================================"
echo "       RENKILLER v6.0 STATUS"
echo "======================================"

systemctl is-active --quiet renkiller \
  && echo "Backend: ONLINE" \
  || echo "Backend: ERROR"

systemctl is-active --quiet nginx \
  && echo "Nginx: ONLINE" \
  || echo "Nginx: ERROR"

echo ""
echo "Backend test:"

curl -sS http://127.0.0.1:3000/api/health || true

echo ""
echo "======================================"
echo "RenKiller v6.0 UPDATE SELESAI"
echo "======================================"

echo "URL: http://$DOMAIN"
echo "Dashboard User: $DASH_USER"
echo "Dashboard Password: [yang kamu masukkan]"
echo ""
echo "API Key tersimpan aman di $ENV_FILE"
echo "======================================"
