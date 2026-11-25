#!/bin/bash

# ============================================
# KONFIGURASI
# ============================================
PANEL_URL="https://vvipbokep.naaofficial.me"
API_KEY="ptla_qvu094TMhapXMajTiLE4FxZPo3ZqwghhAPxkb1VXQxh"

CONFIG=$(cat <<'EOF'
{
  loc: '1',
  nest: '5',
  egg: '15',
  datacenter: ''
}
EOF
)

LOCATION_ID="1"
NEST_ID="5"
EGG_ID="15"
DATACENTER=""

MEMORY="1024"
DISK="2048"
CPU="100"
JUMLAH_USER=10
EMAIL_DOMAIN="ren.clods"
PASSWORD="12345678"

DOCKER_IMAGE="ghcr.io/parkervcp/yolks:nodejs_18"
STARTUP_CMD="node index.js"

# ============================================
# WARNA
# ============================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

log_info(){ echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok(){ echo -e "${GREEN}[✔ OK]${NC} $1"; }
log_err(){ echo -e "${RED}[✘ ERR]${NC} $1"; }
log_warn(){ echo -e "${YELLOW}[⚠ WARN]${NC} $1"; }

# ============================================
# SPINNER ANIMASI
# ============================================
SPIN_CHARS=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
SPIN_IDX=0

spin_start() {
    local msg=$1
    SPIN_MSG="$msg"
    SPIN_ACTIVE=1
    (
        while [ "$SPIN_ACTIVE" = "1" ]; do
            local c=${SPIN_CHARS[$SPIN_IDX]}
            printf "\r${CYAN}%s${NC} %s..." "$c" "$SPIN_MSG"
            SPIN_IDX=$(( (SPIN_IDX + 1) % ${#SPIN_CHARS[@]} ))
            sleep 0.08
        done
    ) &
    SPIN_PID=$!
}

spin_stop() {
    SPIN_ACTIVE=0
    wait "$SPIN_PID" 2>/dev/null
    printf "\r\033[K"
}

# ============================================
# PROGRESS BAR
# ============================================
progress_bar() {
    local current=$1 total=$2 width=30
    local pct=$(( current * 100 / total ))
    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))
    local bar=""
    for ((i=0;i<filled;i++)); do bar+="█"; done
    for ((i=0;i<empty;i++)); do bar+="░"; done
    printf "\r${MAGENTA}[%s]${NC} ${BOLD}%3d%%${NC} (%d/%d)" "$bar" "$pct" "$current" "$total"
}

# ============================================
# ANIMASI LOG FLOW
# ============================================
animate_line() {
    local text=$1 color=${2:-$GREEN} delay=${3:-0.01}
    for ((i=0;i<${#text};i++)); do
        printf "%b%s${NC}" "$color" "${text:$i:1}"
        sleep "$delay"
    done
    echo
}

animate_marquee() {
    local text=$1 color=${2:-$CYAN} width=${3:-50}
    local padded="   ${text}   "
    local len=${#padded}
    for ((i=0;i<len+width;i++)); do
        local out=""
        for ((j=0;j<width;j++)); do
            local idx=$(( (i + j) % len ))
            out+="${padded:$idx:1}"
        done
        printf "\r%b%s${NC}" "$color" "$out"
        sleep 0.02
    done
    printf "\r\033[K"
}

# ============================================
# BANNER
# ============================================
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
   ___         __        ___      __   ____                __  __
  / _ | __ __ / /_ ___  / _ \___ / /  / __/__ _____  ___  / /_/ /
 / __ |/ // // __/ _ \/ // / -_) _ \/ _// _ `/ __/ _ \/ _ \/ __/ _ \
/_/ |_/\_,_/ \__/\___/____/\__/_.__/___/\_,_/_/  \___/\___/\__/_//_/
EOF
    echo -e "${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────${NC}"
    echo -e " ${BOLD}Panel  :${NC} ${PANEL_URL}"
    echo -e " ${BOLD}Egg    :${NC} ${EGG_ID}  ${BOLD}Nest :${NC} ${NEST_ID}  ${BOLD}Loc :${NC} ${LOCATION_ID}"
    echo -e " ${BOLD}Target :${NC} ${JUMLAH_USER} user/server"
    echo -e "${DIM}─────────────────────────────────────────────────────${NC}"
    echo
}

# ============================================
# API WRAPPER
# ============================================
api() {
    local method=$1 endpoint=$2 data=$3
    if [ -z "$data" ]; then
        curl -s -X "$method" "${PANEL_URL}/api/application${endpoint}" \
            -H "Authorization: Bearer ${API_KEY}" \
            -H "Content-Type: application/json" \
            -H "Accept: Application/vnd.pterodactyl.v1+json"
    else
        curl -s -X "$method" "${PANEL_URL}/api/application${endpoint}" \
            -H "Authorization: Bearer ${API_KEY}" \
            -H "Content-Type: application/json" \
            -H "Accept: Application/vnd.pterodactyl.v1+json" \
            -d "$data"
    fi
}

# ============================================
# AMBIL ALLOCATION FREE
# ============================================
get_free_allocs() {
    local result="" page=1
    while :; do
        local resp=$(api "GET" "/nodes?page=${page}&per_page=100")
        local nodes=$(echo "$resp" | jq -r --arg loc "$LOCATION_ID" \
            '.data[] | select(.attributes.location_id == ($loc|tonumber)) | .attributes.id')
        for nid in $nodes; do
            local p=1
            while :; do
                local aresp=$(api "GET" "/nodes/${nid}/allocations?page=${p}&per_page=100")
                local free=$(echo "$aresp" | jq -r '.data[] | select(.attributes.assigned == false) | "\(.attributes.id)|\(.attributes.ip)|\(.attributes.port)"')
                [ -n "$free" ] && result="${result}${free}"$'\n'
                local cp=$(echo "$aresp" | jq -r '.meta.pagination.current_page // 1')
                local tp=$(echo "$aresp" | jq -r '.meta.pagination.total_pages // 1')
                [ "$cp" -ge "$tp" ] && break
                p=$((p+1))
            done
        done
        local cp=$(echo "$resp" | jq -r '.meta.pagination.current_page // 1')
        local tp=$(echo "$resp" | jq -r '.meta.pagination.total_pages // 1')
        [ "$cp" -ge "$tp" ] && break
        page=$((page+1))
    done
    echo "$result" | grep -v '^$' | sort -u
}

# ============================================
# MAIN
# ============================================
show_banner

spin_start "Mengambil allocation free di location ${LOCATION_ID}"
ALLOCS=$(get_free_allocs)
spin_stop

TOTAL_ALLOC=$(echo "$ALLOCS" | grep -c . )
if [ "$TOTAL_ALLOC" -eq 0 ]; then
    log_err "Tidak ada allocation free di location ${LOCATION_ID}!"
    exit 1
fi
log_ok "Total allocation free: ${BOLD}${TOTAL_ALLOC}${NC}"
echo

# Info auto detect nest jika perlu
if [ -z "$NEST_ID" ]; then
    spin_start "Auto-detect nest dari egg ${EGG_ID}"
    NEST_ID=$(api "GET" "/nests?per_page=100" | jq -r --arg egg "$EGG_ID" '
        .data[] | .attributes.id as $nid |
        (.attributes.relationships.eggs.data[]? | select(.attributes.id == ($egg|tonumber)) | $nid)
    ' | head -n1)
    spin_stop
fi

if [ "$JUMLAH_USER" -gt "$TOTAL_ALLOC" ]; then
    log_warn "JUMLAH_USER ($JUMLAH_USER) > allocation ($TOTAL_ALLOC). Disesuaikan ke ${TOTAL_ALLOC}"
    JUMLAH_USER=$TOTAL_ALLOC
fi

echo -e "${DIM}─────────────────────────────────────────────────────${NC}"
animate_line "  Memulai flood create ${JUMLAH_USER} server..." "$CYAN" 0.008
echo -e "${DIM}─────────────────────────────────────────────────────${NC}"
echo

: > result_users.txt
counter=0
success=0
failed=0

echo "$ALLOCS" | while IFS='|' read -r ALLOC_ID ALLOC_IP ALLOC_PORT; do
    [ -z "$ALLOC_ID" ] && continue
    counter=$((counter+1))
    [ "$counter" -gt "$JUMLAH_USER" ] && break

    # --- header per user ---
    progress_bar "$counter" "$JUMLAH_USER"
    echo
    echo -e "${BOLD}${MAGENTA}┌─ [${counter}/${JUMLAH_USER}] Create User + Server${NC}"

    # --- random nama angka ---
    RAND_NUM=$(shuf -i 1000000-9999999999 -n1)
    USERNAME="user${RAND_NUM}"
    EMAIL="${USERNAME}@${EMAIL_DOMAIN}"

    echo -e "${MAGENTA}│${NC}  ${DIM}username:${NC} ${BOLD}${USERNAME}${NC}"
    echo -e "${MAGENTA}│${NC}  ${DIM}email   :${NC} ${BOLD}${EMAIL}${NC}"
    echo -e "${MAGENTA}│${NC}  ${DIM}alloc   :${NC} ${ALLOC_IP}:${ALLOC_PORT}"

    # --- CREATE USER (spinner) ---
    USER_PAYLOAD=$(jq -n \
        --arg u "$USERNAME" --arg e "$EMAIL" \
        --arg f "$USERNAME" --arg l "$USERNAME" \
        --arg p "$PASSWORD" \
        '{username:$u,email:$e,first_name:$f,last_name:$l,password:$p,root_admin:false,language:"en"}')

    spin_start "POST /users"
    USER_RESP=$(api "POST" "/users" "$USER_PAYLOAD")
    spin_stop
    USER_ID=$(echo "$USER_RESP" | jq -r '.attributes.id // empty')

    if [ -z "$USER_ID" ]; then
        MSG=$(echo "$USER_RESP" | jq -r '.errors[0].detail // "unknown error"' 2>/dev/null)
        echo -e "${MAGENTA}│${NC}  ${RED}✘ User gagal: ${MSG}${NC}"
        echo -e "${BOLD}${MAGENTA}└─${NC} ${RED}FAILED${NC}"
        failed=$((failed+1))
        continue
    fi
    echo -e "${MAGENTA}│${NC}  ${GREEN}✔ User created${NC} ${DIM}(ID=$USER_ID)${NC}"

    # --- CREATE SERVER (spinner) ---
    SRV_PAYLOAD=$(jq -n \
        --arg name "$USERNAME" --arg uid "$USER_ID" \
        --argjson egg "$EGG_ID" --argjson nest "$NEST_ID" \
        --argjson alloc "$ALLOC_ID" \
        --argjson mem "$MEMORY" --argjson disk "$DISK" --argjson cpu "$CPU" \
        --arg img "$DOCKER_IMAGE" --arg startup "$STARTUP_CMD" \
        '{
            name:$name, user:$uid, egg:$egg,
            docker_image:$img, startup:$startup,
            environment:{}, limits:{memory:$mem,swap:0,disk:$disk,io:500,cpu:$cpu},
            feature_limits:{databases:0,backups:0,allocations:1},
            allocation:{default:$alloc}, start_on_completion:false
        }')

    spin_start "POST /servers (egg=${EGG_ID}, nest=${NEST_ID})"
    SRV_RESP=$(api "POST" "/servers" "$SRV_PAYLOAD")
    spin_stop
    SRV_ID=$(echo "$SRV_RESP" | jq -r '.attributes.id // empty')

    if [ -z "$SRV_ID" ]; then
        MSG=$(echo "$SRV_RESP" | jq -r '.errors[0].detail // "unknown error"' 2>/dev/null | head -c 160)
        echo -e "${MAGENTA}│${NC}  ${RED}✘ Server gagal: ${MSG}${NC}"
        echo -e "${MAGENTA}│${NC}  ${YELLOW}↺ rollback delete user${NC}"
        spin_start "DELETE /users/${USER_ID}"
        api "DELETE" "/users/${USER_ID}" > /dev/null
        spin_stop
        echo -e "${BOLD}${MAGENTA}└─${NC} ${RED}FAILED${NC}"
        failed=$((failed+1))
        continue
    fi
    echo -e "${MAGENTA}│${NC}  ${GREEN}✔ Server created${NC} ${DIM}(ID=$SRV_ID)${NC}"
    echo -e "${BOLD}${MAGENTA}└─${NC} ${GREEN}${BOLD}SUCCESS${NC}"
    success=$((success+1))

    echo "${USERNAME}|${EMAIL}|${PASSWORD}|${SRV_ID}|${ALLOC_IP}:${ALLOC_PORT}" >> result_users.txt
done

# ============================================
# RINGKASAN
# ============================================
echo
echo -e "${DIM}─────────────────────────────────────────────────────${NC}"
animate_line "  ✔ SELESAI" "$GREEN" 0.02
echo -e "${DIM}─────────────────────────────────────────────────────${NC}"
echo -e "  ${BOLD}Total dicoba :${NC} $JUMLAH_USER"
echo -e "  ${BOLD}Berhasil     :${NC} ${GREEN}$success${NC}"
echo -e "  ${BOLD}Gagal        :${NC} ${RED}$failed${NC}"
echo -e "  ${BOLD}Hasil        :${NC} result_users.txt"
echo -e "${DIM}─────────────────────────────────────────────────────${NC}"
echo
animate_marquee "★ FLOOD COMPLETE ★ CEK result_users.txt ★ THANKS ★ " "$CYAN" 55
echo
log_info "Format: USERNAME|EMAIL|PASSWORD|SERVER_ID|IP:PORT"
cat result_users.txt 2>/dev/null
