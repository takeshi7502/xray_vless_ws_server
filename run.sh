#!/usr/bin/env bash
set -o pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BLUE='\033[0;34m'; NC='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd "$SCRIPT_DIR" || exit 1

# Detect Termux
IS_TERMUX=false
if [ -n "${TERMUX_VERSION:-}" ] || [[ "${PREFIX:-}" == *"com.termux"* ]]; then
    IS_TERMUX=true
fi

SERVICE_NAME="xray-vless"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

DEF_PORT_QUICK="127.0.0.1:8888"
DEF_PORT_NAMED="127.0.0.1:8888"
DEF_PORT_DIRECT="0.0.0.0:80"
LEGACY_FAKE_SNI="api24-normal-alisg.tiktokv.com#FreeTiktok,172.67.168.158#FreeVNPT"
NEW_FAKE_SNI="vega-prime.huskydg.dpdns.org#FreeMobiFone"
DEF_FAKE_SNI="$LEGACY_FAKE_SNI,$NEW_FAKE_SNI"
DEF_WS_PATH="/vless"
DEF_WS_HOST="trycloudflare.com"
DEF_TRANSPORT="websocket,xhttp"
DEF_XHTTP_MODE="auto"

RUN_MODE=""; PORT=""; UUID=""; FAKE_SNI=""; WS_PATH=""; WS_HOST=""; TUNNEL_TOKEN=""; ENABLE_WARP="false"; WEBHOOK_URL=""; TRANSPORT="websocket,xhttp"; XHTTP_MODE="auto"; COUNTRY_CODE=""; CUSTOM_DOMAIN=""; PORT_MODE="443"
DNSECH=""; TLS_PORT=""; TLS_KEY=""; TLS_PEM=""; PASSWORD=""; LOGGER_HOST="127.0.0.1"; DEBUG_MODE="false"; FRP_INFO_FORMAT="plain"

header(){ echo; echo -e "${CYAN}===================================================${NC}"; echo -e "${GREEN} $1${NC}"; echo -e "${CYAN}===================================================${NC}"; }
ok(){ echo -e " ${GREEN}[OK]${NC} $1"; }
warn(){ echo -e " ${YELLOW}[!]${NC}  $1"; }
err(){ echo -e " ${RED}[ERR]${NC} $1"; }
info(){ echo -e " ${BLUE}[i]${NC}  $1"; }
setup_step(){
    echo
    echo -e "${CYAN}===================================================${NC}"
    echo -e " ${GREEN}BUOC $1${NC}  $2"
    echo -e "${CYAN}===================================================${NC}"
}
pause_next(){ echo; read -r -p " Press Enter to continue..." _; }
ask_yes_no(){ local ans hint default="${2:-y}"; [ "$default" = "y" ] && hint="Y/n" || hint="y/N"; read -r -p " $1 [$hint]: " ans; ans="${ans:-$default}"; [[ "$ans" =~ ^[Yy]$ ]]; }
ask_val(){ local prompt="$1" default="$2" ans; read -r -p " $prompt [$default]: " ans; [ -n "$ans" ] && echo "$ans" || echo "$default"; }
ask_country(){
    local ans cc
    echo -e " ${BLUE}[i]${NC}  Server country flag (optional)"
    echo -e "      Hint: VN  JP  US  SG  DE  FR  KR  HK  TW  NL  GB  AU  CA"
    read -r -p " Country code (Enter to skip) [${COUNTRY_CODE:-}]: " ans
    if [ -n "$ans" ]; then
        cc="$(printf '%s' "$ans" | tr 'a-z' 'A-Z' | tr -dc 'A-Z')"
        COUNTRY_CODE="${cc:0:2}"
    fi
    [ -n "$COUNTRY_CODE" ] && ok "Country: $COUNTRY_CODE" || info "No country flag."
}
ask_fake_sni(){
    local choice default_choice="5"
    case "$FAKE_SNI" in
        "api24-normal-alisg.tiktokv.com#FreeTiktok"|"api24-normal-alisg.tiktokv.com#Free Tiktok") default_choice="1" ;;
        "172.67.168.158#FreeVNPT"|"172.67.168.158#FreeVina Ko Nen"|"172.67.168.158#Free Vina Ko Nen") default_choice="2" ;;
        "$LEGACY_FAKE_SNI"|"api24-normal-alisg.tiktokv.com#Free Tiktok,172.67.168.158#Free Vina Ko Nen") default_choice="3" ;;
        "$NEW_FAKE_SNI"|"vega-prime.huskydg.dpdns.org#Free Mobifone") default_choice="4" ;;
        "$DEF_FAKE_SNI"|"") ;;
        *) default_choice="tuy chinh" ;;
    esac
    echo -e " ${BLUE}[i]${NC}  FAKE_SNI selection:"
    echo "   1. FreeTiktok  (api24-normal-alisg.tiktokv.com)"
    echo "   2. FreeVNPT  (172.67.168.158)"
    echo "   3. Hai address cu"
    echo "   4. FreeMobiFone (vega-prime.huskydg.dpdns.org)"
    echo "   5. Ca hai address cu + Mobifone (mac dinh cho cai moi)"
    echo "   Hoac nhap gia tri FAKE_SNI tuy chinh"
    read -r -p " Chon [1-5/tuy chinh] [$default_choice]: " choice
    choice="${choice:-$default_choice}"
    case "$choice" in
        1) FAKE_SNI="api24-normal-alisg.tiktokv.com#FreeTiktok" ;;
        2) FAKE_SNI="172.67.168.158#FreeVNPT" ;;
        3) FAKE_SNI="$LEGACY_FAKE_SNI" ;;
        4) FAKE_SNI="$NEW_FAKE_SNI" ;;
        5) FAKE_SNI="$DEF_FAKE_SNI" ;;
        "tuy chinh") ;;
        *) FAKE_SNI="$choice" ;;
    esac
    ok "FAKE_SNI: $FAKE_SNI"
}
ask_transport(){
    local choice mode_choice default_choice="3"
    case "$TRANSPORT" in
        xhttp) default_choice="2" ;;
        websocket) default_choice="1" ;;
    esac
    echo -e " ${BLUE}[i]${NC}  Chon transport:"
    echo "   1. WebSocket (on dinh / ho tro client rong nhat)"
    echo "   2. xHTTP (transport HTTP hien dai)"
    echo "   3. Ca WebSocket + xHTTP"
    read -r -p " Chon [1/2/3] [$default_choice]: " choice
    choice="${choice:-$default_choice}"
    case "$choice" in
        1) TRANSPORT="websocket" ;;
        2) TRANSPORT="xhttp" ;;
        3) TRANSPORT="websocket,xhttp" ;;
        *) warn "Lua chon khong hop le; giu lai $TRANSPORT." ;;
    esac
    if [[ "$TRANSPORT" == *xhttp* ]]; then
        echo "   xHTTP mode:"
        echo "   1. packet-up"
        echo "   2. stream-up"
        echo "   3. stream-one"
        echo "   4. auto (mac dinh moi)"
        case "$XHTTP_MODE" in packet-up) mode_choice=1 ;; stream-up) mode_choice=2 ;; stream-one) mode_choice=3 ;; *) mode_choice=4 ;; esac
        read -r -p " Chon xHTTP mode [1/2/3/4] [$mode_choice]: " choice
        choice="${choice:-$mode_choice}"
        case "$choice" in 1) XHTTP_MODE="packet-up" ;; 2) XHTTP_MODE="stream-up" ;; 3) XHTTP_MODE="stream-one" ;; 4) XHTTP_MODE="auto" ;; *) warn "Mode khong hop le; giu lai $XHTTP_MODE." ;; esac
    fi
    if [[ "$TRANSPORT" == *xhttp* ]]; then
        ok "Transport: $TRANSPORT (xHTTP mode: $XHTTP_MODE)"
    else
        ok "Transport: $TRANSPORT"
    fi
}
quick_tunnel_transport(){
    TRANSPORT="websocket"
    warn "Luu y: Quick Tunnel (trycloudflare.com) khong ho tro xHTTP."
    ok "Transport: WebSocket"
}

ask_port_mode(){
    local choice default_choice="2"
    echo -e " ${BLUE}[i]${NC}  Chon port cho link VLESS:"
    echo "   1. Chi port 80 (KHONG TLS)"
    echo "   2. Chi port 443 (TLS, mac dinh)"
    echo "   3. Ca 80 + 443"
    read -r -p " Chon [1/2/3] [$default_choice]: " choice
    choice="${choice:-$default_choice}"
    case "$choice" in
        1) PORT_MODE="80" ;;
        2) PORT_MODE="443" ;;
        3) PORT_MODE="both" ;;
        *) warn "Lua chon khong hop le; giu lai ${PORT_MODE:-443}."; PORT_MODE="${PORT_MODE:-443}" ;;
    esac
    ok "Che do port: $PORT_MODE"
}
env_get(){ grep -E "^$1=" .env 2>/dev/null | head -n1 | cut -d= -f2-; }

run_as_root(){
    if [ "$(id -u)" = "0" ]; then "$@"; else sudo "$@"; fi
}

uuid_gen(){
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import uuid; print(uuid.uuid4())'
    elif command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    else
        cat /proc/sys/kernel/random/uuid 2>/dev/null
    fi
}

# ==================== Termux ====================
termux_bootstrap(){
    $IS_TERMUX || return 0
    echo
    echo -e " ${GREEN}========================================${NC}"
    echo -e " ${GREEN}  Ban dang chay server tren Termux!${NC}"
    echo -e " ${GREEN}========================================${NC}"
    echo
    if ! command -v python3 >/dev/null 2>&1; then
        info "Dang cai Python..."
        if ! pkg install -y python; then
            err "Cai Python that bai. Hay chay 'termux-change-repo', chon mirror hoat dong, sau do thu lai."
            return 1
        fi
    fi
    if ! python3 -m pip --version >/dev/null 2>&1; then
        err "Python pip chua san sang. Hay chay: pkg install python"
        return 1
    fi
    ok "Python Termux san sang."
}
# ==================== Python bootstrap ====================
detect_python(){
    if $IS_TERMUX; then
        if command -v python3 >/dev/null 2>&1; then echo python3; return; fi
        err "Khong tim thay Python 3. Hay chay: pkg install python"
        return
    fi
    if [ -x "$SCRIPT_DIR/.venv/bin/python" ]; then
        if "$SCRIPT_DIR/.venv/bin/python" -m pip --version >/dev/null 2>&1; then
            echo "$SCRIPT_DIR/.venv/bin/python"; return
        fi
        warn ".venv bi loi (khong co pip). Dang xoa..."
        rm -rf "$SCRIPT_DIR/.venv"
    fi
    if command -v python3 >/dev/null 2>&1; then echo python3; return; fi
    if command -v python >/dev/null 2>&1; then
        if python -c 'import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)' 2>/dev/null; then
            echo python; return
        fi
    fi
    err "Khong tim thay Python 3. Hay cai: sudo apt install python3 python3-venv python3-pip"
}

install_venv_package(){
    local py="$1"
    command -v apt-get >/dev/null 2>&1 || return 1
    local pyver
    pyver="$("$py" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "3")"
    info "Dang tu cai python${pyver}-venv python3-pip qua apt..."
    run_as_root apt-get update -qq 2>/dev/null
    run_as_root apt-get install -y -qq "python${pyver}-venv" python3-pip 2>&1 | tail -3
}

ensure_python_deps(){
    local py="$1"
    if "$py" -c "import dotenv, requests" 2>/dev/null; then return 0; fi
    warn "Thieu Python dependencies. Dang cai..."

    # Termux chay bang Python he thong, khong dung .venv, apt hay sudo.
    if $IS_TERMUX; then
        if "$py" -m pip install --user -q python-dotenv requests; then
            "$py" -c "import dotenv, requests" 2>/dev/null && { ok "Da cai dependencies can thiet."; return 0; }
        fi
        err "Cai dependencies can thiet that bai. Kiem tra ket noi mang roi thu lai."
        return 1
    fi
    # Neu dang o trong venv
    if "$py" -c 'import sys; sys.exit(0 if hasattr(sys, "real_prefix") or (hasattr(sys, "base_prefix") and sys.base_prefix != sys.prefix) else 1)' 2>/dev/null; then
        if "$py" -m pip install -q python-dotenv requests 2>&1 | tail -3; then
            "$py" -c "import dotenv, requests" 2>/dev/null && { ok "Deps installed."; return 0; }
        fi
        if [[ "$py" = "$SCRIPT_DIR/.venv/"* ]]; then
            warn ".venv bi loi. Dang tao lai..."
            rm -rf "$SCRIPT_DIR/.venv"
            py="$(command -v python3 2>/dev/null || command -v python 2>/dev/null)"
            [ -z "$py" ] && { err "Khong co Python3 he thong."; return 1; }
        else
            err "pip that bai trong venv ben ngoai."; return 1
        fi
    fi

    # pip --user
    if "$py" -m pip install --user -q python-dotenv requests 2>/dev/null; then
        "$py" -c "import dotenv, requests" 2>/dev/null && { ok "Da cai dependencies (--user)."; return 0; }
    fi
    # --break-system-packages
    if "$py" -m pip install --break-system-packages -q python-dotenv requests 2>/dev/null; then
        "$py" -c "import dotenv, requests" 2>/dev/null && { ok "Deps installed."; return 0; }
    fi

    # Tao .venv
    info "Dang tao .venv..."
    rm -rf "$SCRIPT_DIR/.venv"
    if ! "$py" -m venv "$SCRIPT_DIR/.venv" 2>/dev/null || [ ! -x "$SCRIPT_DIR/.venv/bin/python" ]; then
        install_venv_package "$py"
        rm -rf "$SCRIPT_DIR/.venv"
        "$py" -m venv "$SCRIPT_DIR/.venv" 2>/dev/null
    fi
    [ -x "$SCRIPT_DIR/.venv/bin/python" ] || { err "Tao .venv that bai."; return 1; }
    local venv_py="$SCRIPT_DIR/.venv/bin/python"
    "$venv_py" -m pip install -q python-dotenv requests 2>&1 | tail -3
    if "$venv_py" -c "import dotenv, requests" 2>/dev/null; then
        ok "Da cai dependencies vao .venv/."
        PYBIN="$venv_py"; return 0
    fi
    err "Cai dependencies that bai."; return 1
}

prepare_python(){
    PYBIN="$(detect_python)"
    [ -z "$PYBIN" ] && return 1
    ensure_python_deps "$PYBIN" || return 1
    # Keep a virtualenv interpreter path intact. Resolving its symlink points
    # systemd at the base Python and drops packages installed in .venv.
    if [[ "$PYBIN" = /* ]]; then PYBIN_ABS="$PYBIN"
    else PYBIN_ABS="$(command -v "$PYBIN" 2>/dev/null)"; fi
    ok "Python san sang: $PYBIN_ABS"
}

# ==================== .env ====================
write_env(){
    UUID="${UUID:-$(uuid_gen)}"
    [ -n "$UUID" ] || { err "Khong tao duoc VLESS UUID."; return 1; }
    {
        echo "RUN_MODE=$RUN_MODE"; echo "PORT=$PORT"; echo "XRAY_UUID=$UUID"
        echo "FAKE_SNI=$FAKE_SNI"; echo "WS_PATH=$WS_PATH"; echo "WS_HOST=$WS_HOST"
        echo "TRANSPORT=$TRANSPORT"; echo "XHTTP_MODE=$XHTTP_MODE"; echo "ENABLE_WARP=$ENABLE_WARP"
        echo "WEBHOOK_URL=$WEBHOOK_URL"; echo "TUNNEL_TOKEN=$TUNNEL_TOKEN"
        echo "COUNTRY_CODE=$COUNTRY_CODE"
        echo "CUSTOM_DOMAIN=$CUSTOM_DOMAIN"
        echo "PORT_MODE=$PORT_MODE"
        echo "DNSECH=$DNSECH"; echo "TLS_PORT=$TLS_PORT"; echo "TLS_KEY=$TLS_KEY"; echo "TLS_PEM=$TLS_PEM"
        echo "PASSWORD=$PASSWORD"; echo "LOGGER_HOST=$LOGGER_HOST"; echo "DEBUG_MODE=$DEBUG_MODE"; echo "FRP_INFO_FORMAT=$FRP_INFO_FORMAT"
    } > .env
    ok "Da ghi .env (RUN_MODE=$RUN_MODE)"
}

load_existing(){
    [ -f .env ] || return 0
    UUID="$(env_get XRAY_UUID)"; FAKE_SNI="$(env_get FAKE_SNI)"
    WS_PATH="$(env_get WS_PATH)"; WS_PATH="${WS_PATH:-$DEF_WS_PATH}"; WS_HOST="$(env_get WS_HOST)"
    TUNNEL_TOKEN="$(env_get TUNNEL_TOKEN)"; ENABLE_WARP="$(env_get ENABLE_WARP)"
    WEBHOOK_URL="$(env_get WEBHOOK_URL)"; TRANSPORT="$(env_get TRANSPORT)"; XHTTP_MODE="$(env_get XHTTP_MODE)"
    XHTTP_MODE="${XHTTP_MODE:-$DEF_XHTTP_MODE}"
    COUNTRY_CODE="$(env_get COUNTRY_CODE)"
    CUSTOM_DOMAIN="$(env_get CUSTOM_DOMAIN)"
    PORT_MODE="$(env_get PORT_MODE)"
    PORT_MODE="${PORT_MODE:-443}"
    ENABLE_WARP="${ENABLE_WARP:-false}"
    DNSECH="$(env_get DNSECH)"; TLS_PORT="$(env_get TLS_PORT)"; TLS_KEY="$(env_get TLS_KEY)"; TLS_PEM="$(env_get TLS_PEM)"
    PASSWORD="$(env_get PASSWORD)"; LOGGER_HOST="$(env_get LOGGER_HOST)"; LOGGER_HOST="${LOGGER_HOST:-127.0.0.1}"
    DEBUG_MODE="$(env_get DEBUG_MODE)"; DEBUG_MODE="${DEBUG_MODE:-false}"
    FRP_INFO_FORMAT="$(env_get FRP_INFO_FORMAT)"; FRP_INFO_FORMAT="${FRP_INFO_FORMAT:-plain}"
}

advanced_settings(){
    [ -f .env ] || { err "Hay setup mot che do truoc."; return 1; }
    load_existing
    RUN_MODE="$(env_get RUN_MODE)"; PORT="$(env_get PORT)"
    header "Cau hinh nang cao"
    info "Enter de giu gia tri; nhap - de xoa mot gia tri tuy chon."
    local value
    value="$(ask_val 'WARP: false / true / ip6only' "$ENABLE_WARP")"
    case "$value" in false|true|ip6only) ENABLE_WARP="$value" ;; *) err "WARP khong hop le"; return 1 ;; esac
    DNSECH="$(ask_val 'ECH DoH URL (vd https://1.1.1.1/dns-query)' "$DNSECH")"; [ "$DNSECH" = "-" ] && DNSECH=""
    TLS_PORT="$(ask_val 'TLS listener (vd 0.0.0.0:443 hoac [::]:443)' "$TLS_PORT")"; [ "$TLS_PORT" = "-" ] && TLS_PORT=""
    if [ -n "$TLS_PORT" ]; then
        TLS_PEM="$(ask_val 'TLS certificate PEM path' "$TLS_PEM")"
        TLS_KEY="$(ask_val 'TLS private key path' "$TLS_KEY")"
        warn "TLS listener chi phuc vu transport dau tien. Can cert/key co san; khong tu tao cert."
    fi
    LOGGER_HOST="$(ask_val 'Logger listen IP (nen giu localhost)' "$LOGGER_HOST")"
    read -r -s -p " Logger password (Enter giu cu, - de xoa): " value; echo
    if [ "$value" = "-" ]; then PASSWORD=""; elif [ -n "$value" ]; then PASSWORD="$value"; fi
    value="$(ask_val 'Debug logs: false / true' "$DEBUG_MODE")"
    case "$value" in false|true) DEBUG_MODE="$value" ;; *) err "Debug khong hop le"; return 1 ;; esac
    value="$(ask_val 'frp_info.config format: plain / base64' "$FRP_INFO_FORMAT")"
    case "$value" in plain|base64) FRP_INFO_FORMAT="$value" ;; *) err "Format khong hop le"; return 1 ;; esac
    write_env || return 1
    info "Da luu. Khoi dong lai server de ap dung."
}

show_links(){
    local py
    py="$(detect_python)" || return 1
    "$py" "$SCRIPT_DIR/runtime_config.py" --show-links "$SCRIPT_DIR/frp_info.config"
}

# ==================== Systemd ====================
install_service(){
    if ! command -v systemctl >/dev/null 2>&1; then
        err "Khong co systemd."; return 1
    fi
    if [ "$(id -u)" != "0" ] && ! command -v sudo >/dev/null 2>&1; then
        err "Can quyen root hoac sudo."; return 1
    fi
    [ -f .env ] || { err "Khong tim thay .env."; return 1; }
    prepare_python || return 1

    # Dung service cu neu dang chay
    systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null && run_as_root systemctl stop "$SERVICE_NAME"

    info "Dang cai systemd service: $SERVICE_NAME"
    run_as_root tee "$SERVICE_FILE" >/dev/null <<UNIT
[Unit]
Description=May chu Xray VLESS-WS
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStart=$PYBIN_ABS $SCRIPT_DIR/main.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

[Install]
WantedBy=multi-user.target
UNIT

    run_as_root systemctl daemon-reload
    run_as_root systemctl enable "$SERVICE_NAME" 2>/dev/null
    run_as_root systemctl start "$SERVICE_NAME"
    ok "Service da chay. Dang doi link VLESS..."
}

wait_and_show_links(){
    # Doi main.py ghi frp_info.config
    local tries=0
    while [ $tries -lt 90 ]; do
        if [ -f "$SCRIPT_DIR/frp_info.config" ] && [ -s "$SCRIPT_DIR/frp_info.config" ]; then
            sleep 2  # cho main.py ghi xong
            echo
            header "Link VLESS"
            echo
            show_links
            echo
            ok "Sao chep mot link ben tren vao v2rayNG / Shadowrocket."
            if [ "$RUN_MODE" = "quick_tunnel" ]; then
                warn "Hostname Quick Tunnel thay doi sau moi lan khoi dong lai."
                info "Xem link moi sau khi khoi dong lai: cat $SCRIPT_DIR/frp_info.config"
            fi
            return 0
        fi
        sleep 1
        tries=$((tries + 1))
    done
    err "Het thoi gian doi link VLESS sau 90 giay."
    info "Kiem tra service: journalctl -u $SERVICE_NAME -e --no-pager -n 30"
    return 1
}

# ==================== Khoi dong server ====================
start_server(){
    rm -f "$SCRIPT_DIR/frp_info.config"
    if $IS_TERMUX; then
        prepare_python || return 1
        if [ "$RUN_MODE" != "direct" ] && ! command -v cloudflared >/dev/null 2>&1; then
            info "Quick/Named Tunnel can cloudflared. Dang cai package can thiet..."
            if ! pkg install -y cloudflared; then
                err "Cai cloudflared that bai. Hay kiem tra mirror/mang roi thu lai."
                return 1
            fi
        fi
        echo
        info "Dang chay server truc tiep (che do Termux)..."
        info "Nhan Ctrl+C de dung server."
        echo
        "$PYBIN_ABS" "$SCRIPT_DIR/main.py"
    else
        install_service || return 1
        wait_and_show_links
    fi
}

# ==================== Cac che do cai dat ====================
quick_mode(){
    header "Quick Tunnel"
    info "Khong can domain. Cloudflare cap hostname ngau nhien sau moi lan chay."
    load_existing

    setup_step "1/4" "Fake SNI"
    ask_fake_sni

    setup_step "2/4" "Port link VLESS"
    WS_PATH="${WS_PATH:-$DEF_WS_PATH}"
    quick_tunnel_transport
    RUN_MODE="quick_tunnel"; PORT="$DEF_PORT_QUICK"
    [ -n "$WS_HOST" ] && [ "$WS_HOST" != "$DEF_WS_HOST" ] && CUSTOM_DOMAIN="$WS_HOST"
    WS_HOST="$DEF_WS_HOST"
    ask_port_mode

    setup_step "3/4" "Vi tri node"
    ask_country

    setup_step "4/4" "Luu va khoi dong"
    write_env || return 1
    start_server
}

named_mode(){
    header "Named Cloudflare Tunnel"
    info "Can Cloudflare Zero Trust."
    echo -e " ${CYAN}Truoc khi tiep tuc trong Zero Trust:${NC}"
    echo "   - Networks -> Tunnels -> Create -> Cloudflared -> sao chep token."
    echo -e "   - Public Hostname -> Service = ${GREEN}http://127.0.0.1:8888${NC}"
    echo
    read -r -p " Nhan Enter khi san sang..." _
    load_existing
    [ "$(env_get RUN_MODE)" = "quick_tunnel" ] && TRANSPORT="$DEF_TRANSPORT"

    setup_step "1/6" "Domain va tunnel credentials"
    local def_host="${WS_HOST:-}"
    [ "$def_host" = "trycloudflare.com" ] || [ -z "$def_host" ] && def_host="${CUSTOM_DOMAIN:-}"
    WS_HOST="$(ask_val "Domain (vi du: vless.example.com)" "$def_host")"
    TUNNEL_TOKEN="$(ask_val "Tunnel connector token" "${TUNNEL_TOKEN:-}")"
    [ -z "$WS_HOST" ] || [ "$WS_HOST" = "trycloudflare.com" ] && { err "Can domain."; return 1; }
    [ -z "$TUNNEL_TOKEN" ] && { err "Can token."; return 1; }
    RUN_MODE="named_tunnel"; PORT="$DEF_PORT_NAMED"

    setup_step "2/6" "Fake SNI"
    ask_fake_sni

    setup_step "3/6" "Diem cuoi transport"
    WS_PATH="${WS_PATH:-$DEF_WS_PATH}"; TRANSPORT="${TRANSPORT:-$DEF_TRANSPORT}"
    ask_transport

    setup_step "4/6" "Port link VLESS"
    ask_port_mode

    setup_step "5/6" "Vi tri node"
    ask_country

    setup_step "6/6" "Luu va khoi dong"
    CUSTOM_DOMAIN="$WS_HOST"
    write_env || return 1
    start_server
}

direct_mode(){
    header "Direct Cloudflare"
    info "Khong dung cloudflared. Cloudflare chuyen tiep vao port 80."
    echo -e " ${CYAN}Truoc khi tiep tuc trong Cloudflare:${NC}"
    echo -e "   - ${GREEN}vless.example.com -> A -> <VPS IP>${NC}, proxy ${GREEN}ON${NC} (orange cloud)"
    echo -e "   - SSL/TLS -> ${GREEN}Flexible${NC}"
    echo -e "   - Cho phep TCP inbound ${GREEN}80${NC} tu IP Cloudflare"
    echo
    read -r -p " Nhan Enter khi san sang..." _
    load_existing
    [ "$(env_get RUN_MODE)" = "quick_tunnel" ] && TRANSPORT="$DEF_TRANSPORT"

    setup_step "1/6" "Domain va origin listener"
    local def_host="${WS_HOST:-}"
    [ "$def_host" = "trycloudflare.com" ] || [ -z "$def_host" ] && def_host="${CUSTOM_DOMAIN:-}"
    WS_HOST="$(ask_val "Domain" "$def_host")"
    PORT="$(ask_val "Origin listen address:port" "$DEF_PORT_DIRECT")"
    [ -z "$WS_HOST" ] || [ "$WS_HOST" = "trycloudflare.com" ] && { err "Can domain."; return 1; }
    RUN_MODE="direct"

    setup_step "2/6" "Fake SNI"
    ask_fake_sni

    setup_step "3/6" "Diem cuoi transport"
    WS_PATH="${WS_PATH:-$DEF_WS_PATH}"; TRANSPORT="${TRANSPORT:-$DEF_TRANSPORT}"
    ask_transport

    setup_step "4/6" "Port link VLESS"
    ask_port_mode

    setup_step "5/6" "Vi tri node"
    ask_country

    setup_step "6/6" "Luu va khoi dong"
    CUSTOM_DOMAIN="$WS_HOST"
    write_env || return 1
    start_server
}
# ==================== Quan ly Service ====================
service_manager(){
    if $IS_TERMUX; then
        warn "Quan ly Service khong ho tro tren Termux."
        info "Tren Termux, chay mot setup mode (1/2/3) de khoi dong server truc tiep."
        return 1
    fi
    if ! command -v systemctl >/dev/null 2>&1; then
        err "Khong co systemd."; return 1
    fi
    while true; do
        header "Quan ly Service"
        local st
        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            st="${GREEN}● Dang chay${NC}"
        elif [ -f "$SERVICE_FILE" ]; then
            st="${YELLOW}● Da dung${NC}"
        else
            st="${RED}● Chua cai${NC}"
        fi
        echo -e "  Service : ${CYAN}${SERVICE_NAME}${NC}    $st"
        [ -f .env ] && echo -e "  Mode    : ${CYAN}$(env_get RUN_MODE)${NC}  →  $(env_get WS_HOST)"
        echo
        echo " 1. Khoi dong"
        echo " 2. Dung"
        echo " 3. Khoi dong lai"
        echo " 4. Xem log (truc tiep)"
        echo " 5. Trang thai"
        echo " 6. Xem link VLESS"
        echo " 7. Cai lai service"
        echo " 8. Xoa service"
        echo " 0. Quay lai"
        read -r -p " Chon [0-8]: " c
        case "$c" in
            1) run_as_root systemctl start "$SERVICE_NAME" 2>/dev/null && ok "Da khoi dong." || err "That bai." ;;
            2) run_as_root systemctl stop "$SERVICE_NAME" 2>/dev/null && ok "Da dung." || err "Khong dang chay." ;;
            3) run_as_root systemctl restart "$SERVICE_NAME" 2>/dev/null; sleep 2
               systemctl is-active --quiet "$SERVICE_NAME" && ok "Da khoi dong lai." || err "That bai." ;;
            4) info "Nhan Ctrl+C de dung xem log."; echo; journalctl -u "$SERVICE_NAME" -f --no-pager -n 50 ;;
            5) systemctl status "$SERVICE_NAME" --no-pager -l 2>/dev/null || info "Chua cai." ;;
            6) if [ -f "$SCRIPT_DIR/frp_info.config" ] && [ -s "$SCRIPT_DIR/frp_info.config" ]; then
                   header "Link VLESS"; echo; show_links; echo
               else info "Chua co link. Hay khoi dong service truoc."; fi ;;
            7) install_service ;;
            8) if [ -f "$SERVICE_FILE" ]; then
                   systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null && run_as_root systemctl stop "$SERVICE_NAME"
                   run_as_root systemctl disable "$SERVICE_NAME" 2>/dev/null
                   run_as_root rm -f "$SERVICE_FILE"
                   run_as_root systemctl daemon-reload
                   ok "Da xoa service."
               else info "Chua cai."; fi ;;
            0) return ;;
            *) err "Lua chon khong hop le" ;;
        esac
        pause_next
    done
}

# ==================== Go cai dat ====================
uninstall_all(){
    header "Go cai dat"
    info "CHI xoa file do project nay tai ve/tao ra."
    echo -e " ${YELLOW}Se xoa:${NC}"
    echo "   Binaries: xray, cloudflared, wgcf-cli"
    echo "   Tao ra: .env, config.json, wgcf.json, frp_info.*, config.yml"
    echo "   Thu muc: xray_bin, wgcf_bin, __pycache__, .venv"
    [ -f "$SERVICE_FILE" ] && echo -e "   Service: ${CYAN}$SERVICE_NAME${NC}"
    echo
    info "KHONG BAO GIO xoa file source."
    echo
    ask_yes_no "Tiep tuc?" "n" || { info "Da huy."; return; }
    # Service (bo qua tren Termux)
    if ! $IS_TERMUX && [ -f "$SERVICE_FILE" ]; then
        systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null && run_as_root systemctl stop "$SERVICE_NAME"
        run_as_root systemctl disable "$SERVICE_NAME" 2>/dev/null
        run_as_root rm -f "$SERVICE_FILE"
        run_as_root systemctl daemon-reload
        ok "Da xoa service."
    fi
    # File
    local removed=0
    for f in xray xray.exe cloudflared cloudflared.exe wgcf-cli wgcf-cli.exe \
             .env config.json wgcf.json wgcf.xray.json frp_info.json frp_info.config frp_info.base64 \
             frpc.toml config.yml xray.zip cloudflared_temp.archive wgcf-cli.tar.zstd; do
        [ -e "$f" ] && rm -rf -- "$f" && { ok "Removed $f"; removed=1; }
    done
    for d in xray_bin wgcf_bin __pycache__ .venv; do
        [ -d "$d" ] && rm -rf -- "$d" && { ok "Removed $d/"; removed=1; }
    done
    [ "$removed" = "0" ] && info "Da sach." || ok "Hoan tat."
}

# ==================== Menu chinh ====================
termux_bootstrap || { err "Khong the chuan bi Termux. Hay sua package/mirror roi chay lai."; exit 1; }
while true; do
    header "May chu Xray VLESS-WS"
    $IS_TERMUX && echo -e "  ${GREEN}[Termux]${NC} Che do truc tiep (khong systemd)"
    # Hien trang thai hien tai
    if ! $IS_TERMUX && command -v systemctl >/dev/null 2>&1 && [ -f "$SERVICE_FILE" ]; then
        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            echo -e "  ${GREEN}● Service dang chay${NC}  $(env_get RUN_MODE) → $(env_get WS_HOST)"
        else
            echo -e "  ${YELLOW}● Service da dung${NC}"
        fi
        echo
    fi
    echo " 1. [1] Quick Tunnel - [tao ngay khong can domain]"
    echo " 2. [2] Named Cloudflare Tunnel - [can domain]"
    echo " 3. [3] Direct Cloudflare - [can domain + public port]"
    echo " 4. Quan ly Service"
    echo " 5. Go cai dat"
    echo " 6. Thoat"
    echo " 7. Cau hinh nang cao (WARP / ECH / TLS / logger / Base64)"
    read -r -p " Chon [1-7]: " MENU_CHOICE
    case "$MENU_CHOICE" in
        1) quick_mode ;;
        2) named_mode ;;
        3) direct_mode ;;
        4) service_manager ;;
        5) uninstall_all ;;
        6) exit 0 ;;
        7) advanced_settings ;;
        *) err "Lua chon khong hop le" ;;
    esac
    pause_next
done
