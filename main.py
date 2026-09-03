import os
import json
import re
import shutil
import socket
from urllib import request
from sys import prefix
from dotenv import load_dotenv
import threading
import subprocess
import platform
import uuid
import time
from logging_site import RealtimeLogger
import requests
import importlib

xray_downloader = importlib.import_module("download-xray")
cloudflared_downloader = importlib.import_module("download-cloudflared")
# WARP downloader is imported lazily only when WARP is enabled.

def main():
    # =========================================
    # CONFIG SERVER (Cloudflare Tunnel)
    # =========================================
    default_configs = {
        "PORT": "127.0.0.1:8888",
        "XRAY_UUID": str(uuid.uuid4()),
        "FAKE_SNI": "api24-normal-alisg.tiktokv.com#Free Tiktok,vnpt.theworkpc.com#Free Vina Ko Nen",
        "WS_PATH": "/tiktok4g",
        "WS_HOST": "trycloudflare.com",
        "TRANSPORT": "websocket",
        "XHTTP_MODE": "packet-up",
        "ENABLE_WARP": "false",
        "WEBHOOK_URL": "",
        "TUNNEL_TOKEN": "",
        "COUNTRY_CODE": "",
        "PORT_MODE": "both",
        "SUBSCRIPTION_SYNC_URL": "",
        "SUBSCRIPTION_SYNC_TOKEN": "",
        "SUBSCRIPTION_NODE_ID": "",
        "RUN_MODE": "quick_tunnel"
    }
    START_TIME = int(time.time())

    def get_os_env(name):
        return os.getenv(name, default_configs.get(name))

    def get_public_url():
        # Get ip via ipify
        try:
            ip = requests.get("https://api.ipify.org").text
            return ip
        except Exception as e:
            print(f"[!] Failed to get public IP: {e}")
            return "0.0.0.0"

    def init_env_file():
        env_path = ".env"
        # Support multiple ports format.
        # Default: localhost:8888

        if not os.path.exists(env_path):
            print("[*] File .env does not exist. Using default configuration...")
            with open(env_path, "w", encoding="utf-8") as f:
                for key, value in default_configs.items():
                    f.write(f"{key}={value}\n")
            print("[+] Generated .env configuration.")
        else:
            print("[*] Found .env configuration.")

    init_env_file()
    load_dotenv()

    # Read raw PORT string from .env
    PORT_ENV = get_os_env("PORT")
    UUID = get_os_env("XRAY_UUID")
    FAKE_SNI = get_os_env("FAKE_SNI")
    WS_PATH = get_os_env("WS_PATH")
    WS_HOST = get_os_env("WS_HOST")
    WEBHOOK_URL = get_os_env("WEBHOOK_URL")
    TUNNEL_TOKEN = get_os_env("TUNNEL_TOKEN").strip()
    ENABLE_WARP = get_os_env("ENABLE_WARP").lower() == "true"
    DEBUG_MODE = os.getenv("DEBUG_MODE", "false").lower() == "true"
    RUN_MODE = get_os_env("RUN_MODE").strip().lower()
    COUNTRY_CODE = get_os_env("COUNTRY_CODE").strip().upper()
    PORT_MODE = get_os_env("PORT_MODE").strip().lower()
    SUBSCRIPTION_SYNC_URL = get_os_env("SUBSCRIPTION_SYNC_URL").strip()
    SUBSCRIPTION_SYNC_TOKEN = get_os_env("SUBSCRIPTION_SYNC_TOKEN").strip()
    SUBSCRIPTION_NODE_ID = get_os_env("SUBSCRIPTION_NODE_ID").strip()
    if SUBSCRIPTION_SYNC_URL:
        SUBSCRIPTION_SYNC_URL = SUBSCRIPTION_SYNC_URL.rstrip("/")
        for suffix in ("/frp_info.config", "/sync"):
            if SUBSCRIPTION_SYNC_URL.endswith(suffix):
                SUBSCRIPTION_SYNC_URL = SUBSCRIPTION_SYNC_URL[:-len(suffix)]
        SUBSCRIPTION_SYNC_URL = f"{SUBSCRIPTION_SYNC_URL}/sync"
    if PORT_MODE not in ("80", "443", "both"):
        PORT_MODE = "both"

    # Normalize RUN_MODE. Old .env files without RUN_MODE default to quick_tunnel.
    ALLOWED_RUN_MODES = ("quick_tunnel", "named_tunnel", "direct")
    if RUN_MODE not in ALLOWED_RUN_MODES:
        print(f"[!] Unknown RUN_MODE '{RUN_MODE}', falling back to 'quick_tunnel'.")
        RUN_MODE = "quick_tunnel"

    # Validate per-mode requirements before downloading/launching anything.
    if RUN_MODE == "named_tunnel":
        if not WS_HOST.strip() or WS_HOST.strip() == "trycloudflare.com":
            print("[ERROR] RUN_MODE=named_tunnel requires WS_HOST to be your custom domain (not trycloudflare.com).")
            return
        if not TUNNEL_TOKEN:
            print("[ERROR] RUN_MODE=named_tunnel requires TUNNEL_TOKEN.")
            return
    elif RUN_MODE == "direct":
        if not WS_HOST.strip() or WS_HOST.strip() == "trycloudflare.com":
            print("[ERROR] RUN_MODE=direct requires WS_HOST to be your Cloudflare-proxied domain.")
            return

    # Transport can be WebSocket, xHTTP, or both (comma-separated).
    requested_transports = [item.strip().lower() for item in get_os_env("TRANSPORT").split(",") if item.strip()]
    allowed_transports = {"websocket", "xhttp"}
    TRANSPORTS = []
    for transport in requested_transports:
        if transport in allowed_transports and transport not in TRANSPORTS:
            TRANSPORTS.append(transport)
        elif transport not in allowed_transports:
            print(f"[!] Unknown transport '{transport}' ignored.")
    if not TRANSPORTS:
        print("[!] No valid transport configured; falling back to 'websocket'.")
        TRANSPORTS = ["websocket"]
    TRANSPORT = ",".join(TRANSPORTS)
    DUAL_TRANSPORT = len(TRANSPORTS) == 2

    XHTTP_MODE = get_os_env("XHTTP_MODE").strip().lower()
    allowed_xhttp_modes = {"packet-up", "stream-up", "stream-one"}
    if XHTTP_MODE not in allowed_xhttp_modes:
        print(f"[!] Unknown XHTTP_MODE '{XHTTP_MODE}', falling back to 'packet-up'.")
        XHTTP_MODE = "packet-up"

    # Parse multi-port configuration
    # Supported formats: "8888" (defaults to 0.0.0.0), "127.0.0.1:8888", "0.0.0.0:443,0.0.0.0:80"
    inbound_ports = []
    for p_item in PORT_ENV.split(","):
        p_item = p_item.strip()
        if ":" in p_item:
            parts = p_item.split(":")
            listen_ip = ":".join(parts[:-1])
            port_num = int(parts[-1])
            inbound_ports.append((listen_ip, port_num))
        else:
            inbound_ports.append(("0.0.0.0", int(p_item)))

    # Cloudflare tunnel will point to the first port in the list
    CLOUDFLARE_TARGET_IP = inbound_ports[0][0]
    CLOUDFLARE_TARGET_PORT = inbound_ports[0][1]
    # If listening on all interfaces, force cloudflared to connect via localhost
    if CLOUDFLARE_TARGET_IP == "0.0.0.0":
        CLOUDFLARE_TARGET_IP = "127.0.0.1"

    if RUN_MODE == "direct":
        direct_ip, direct_port = inbound_ports[0]
        if direct_port != 80:
            print(f"[!] DIRECT MODE: origin is listening on port {direct_port}. Cloudflare Flexible expects an HTTP origin on port 80.")
        print("[!] DIRECT MODE: origin leg is plaintext HTTP transport (WS/xHTTP, no TLS). Set Cloudflare SSL/TLS to 'Flexible'.")

    def send_webhook(data):
        if not WEBHOOK_URL:
            return
        def task():
            try:
                response = requests.post(
                    WEBHOOK_URL,
                    json=data,
                    timeout=10
                )
                if response.status_code == 200:
                    print("[+] Webhook sent successfully!")
                else:
                    print(f"[-] Webhook failed with status: {response.status_code}")
            except Exception as e:
                print(f"[!] Error sending webhook: {e}")
        thread = threading.Thread(target=task)
        thread.daemon = True
        thread.start()

    if not WS_PATH.startswith("/"):
        WS_PATH = "/" + WS_PATH

    XRAY_BIN = "./xray.exe" if platform.system().lower() == "windows" else "./xray"
    CLF_BIN = "./cloudflared.exe" if platform.system().lower() == "windows" else "./cloudflared"
    WGCF_BIN = "./wgcf-cli.exe" if platform.system().lower() == "windows" else "./wgcf-cli"

    # Termux installs cloudflared into PATH instead of this project directory.
    is_termux = bool(os.getenv("TERMUX_VERSION")) or "com.termux" in os.getenv("PREFIX", "")
    if is_termux:
        cloudflared_path = shutil.which("cloudflared")
        if cloudflared_path:
            CLF_BIN = cloudflared_path

    def xray_is_runnable():
        if not os.path.isfile(XRAY_BIN) or not os.access(XRAY_BIN, os.X_OK):
            return False
        try:
            subprocess.run(
                [XRAY_BIN, "version"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=True,
                timeout=15,
            )
            return True
        except (OSError, subprocess.SubprocessError):
            return False

    if is_termux and not xray_is_runnable():
        print("[*] Termux needs a runnable Android Xray binary. Downloading a fresh copy...")
        try:
            xray_downloader.install_xray()
        except Exception as error:
            print(f"[ERROR] Could not install Xray for Termux: {error}")
            return
        if not xray_is_runnable():
            print("[ERROR] Xray is still not executable. Ensure ~/vless is in Termux home, not /sdcard, then run bash run.sh again.")
            return
    elif not os.path.exists(XRAY_BIN):
        print(f"[ERROR] Unable to find xray path: {XRAY_BIN}")
        xray_downloader.install_xray()
    if RUN_MODE != "direct" and not os.path.exists(CLF_BIN):
        print(f"[ERROR] Unable to find Cloudflared path: {CLF_BIN}")
        cloudflared_downloader.install_cloudflared()

    wgcf_outbound = None

    if ENABLE_WARP:
        if not os.path.exists(WGCF_BIN):
            print(f"[ERROR] Unable to find WGCF path: {WGCF_BIN}")
            importlib.import_module("download-wgcf").install_wgcf()

        if not os.path.exists("wgcf.xray.json"):
            print("[*] Generating WARP account...")
            # Dont print output of wgcf-cli to avoid leaking sensitive info, but ensure it runs successfully
            subprocess.run([WGCF_BIN, "register"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([WGCF_BIN, "generate", "--xray"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        """
        this is content of wgcf.xray.json generated by wgcf-cli, which is used to configure WARP as an outbound in Xray.
        {
            "protocol": "wireguard",
            "settings": {
                ...
            },
            "tag": "wireguard"
        }
        """
        with open("wgcf.xray.json", "r") as f:
            wgcf_outbound = json.load(f)

    # =========================================
    # VLESS transport config generator
    # =========================================
    def build_stream_settings(transport):
        if transport == "xhttp":
            return {"network": "xhttp", "security": "none", "xhttpSettings": {"path": WS_PATH, "mode": XHTTP_MODE}}
        return {"network": "ws", "security": "none", "wsSettings": {"path": WS_PATH, "headers": {}}}

    # Dual transport uses separate loopback Xray inbounds and a TCP demux on
    # the public endpoint. WebSocket Upgrade goes to WS; plain HTTP goes xHTTP.
    WS_INTERNAL_OFFSET, XHTTP_INTERNAL_OFFSET = 20000, 30000
    def internal_port_for(base_port, transport):
        candidate = base_port + (WS_INTERNAL_OFFSET if transport == "websocket" else XHTTP_INTERNAL_OFFSET)
        if candidate > 65535: raise ValueError(f"Cannot allocate internal {transport} port for {base_port}")
        return candidate
    def peek_is_websocket(conn, timeout=3.0):
        conn.settimeout(timeout)
        try: data = conn.recv(8192, socket.MSG_PEEK)
        except OSError: data = b""
        finally: conn.settimeout(None)
        return b"upgrade: websocket" in data.lower()
    def pipe_bytes(src, dst):
        try:
            while chunk := src.recv(65536): dst.sendall(chunk)
        except OSError: pass
        finally:
            try: src.shutdown(socket.SHUT_RD)
            except OSError: pass
            try: dst.shutdown(socket.SHUT_WR)
            except OSError: pass
    def handle_demux_connection(client_conn, ws_port, xhttp_port):
        try: backend_conn = socket.create_connection(("127.0.0.1", ws_port if peek_is_websocket(client_conn) else xhttp_port), timeout=5)
        except OSError:
            client_conn.close(); return
        threading.Thread(target=pipe_bytes, args=(client_conn, backend_conn), daemon=True).start()
        threading.Thread(target=pipe_bytes, args=(backend_conn, client_conn), daemon=True).start()
    def start_demux_server(listen_ip, listen_port, ws_port, xhttp_port):
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((listen_ip if listen_ip != "0.0.0.0" else "", listen_port)); server.listen(128)
        def accept_loop():
            while True:
                try: connection, _ = server.accept()
                except OSError: break
                threading.Thread(target=handle_demux_connection, args=(connection, ws_port, xhttp_port), daemon=True).start()
        threading.Thread(target=accept_loop, daemon=True).start()
        print(f"[*] Dual transport demux: {listen_ip}:{listen_port} -> ws:{ws_port}, xhttp:{xhttp_port}")
        return server
    def make_inbound(listen, port, transport):
        return {"port": port, "listen": listen, "protocol": "vless", "sniffing": {"enabled": True, "destOverride": ["http", "tls"]}, "settings": {"clients": [{"id": UUID, "level": 0}], "decryption": "none"}, "streamSettings": build_stream_settings(transport)}
    def write_configs():
        inbounds, demux_servers = [], []
        for ip, port in inbound_ports:
            if DUAL_TRANSPORT:
                ws_port, xhttp_port = internal_port_for(port, "websocket"), internal_port_for(port, "xhttp")
                inbounds.extend([make_inbound("127.0.0.1", ws_port, "websocket"), make_inbound("127.0.0.1", xhttp_port, "xhttp")])
                demux_servers.append((ip, port, ws_port, xhttp_port))
            else: inbounds.append(make_inbound(ip, port, TRANSPORTS[0]))
        xray_config = {"log": {"loglevel": "debug"}, "inbounds": inbounds, "outbounds": [{"protocol": "freedom", "settings": {"domainStrategy": "UseIPv4"}}]}
        if ENABLE_WARP and wgcf_outbound: xray_config["outbounds"].insert(0, wgcf_outbound)
        with open("config.json", "w", encoding="utf-8") as config_file: json.dump(xray_config, config_file, indent=2)
        return demux_servers
    demux_intents = write_configs()
    print("[*] Launching XRAY with configured transport inbounds...")
    xp = subprocess.Popen([XRAY_BIN, "run", "-c", "config.json"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    demux_listeners = []
    if DUAL_TRANSPORT:
        time.sleep(1)
        for ip, port, ws_port, xhttp_port in demux_intents:
            try: demux_listeners.append(start_demux_server(ip, port, ws_port, xhttp_port))
            except OSError as error:
                print(f"[ERROR] Failed to bind dual transport demux on {ip}:{port}: {error}"); xp.terminate(); return

    def wait_for_xray_listener(timeout=10):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            exit_code = xp.poll()
            if exit_code is not None:
                details = xp.stdout.read().strip() if xp.stdout else ""
                print(f"[ERROR] Xray stopped during startup (exit code {exit_code}).")
                if details:
                    print(f"[XRAY ERROR] {details}")
                return False
            try:
                with socket.create_connection((CLOUDFLARE_TARGET_IP, CLOUDFLARE_TARGET_PORT), timeout=0.5):
                    print(f"[OK] Xray is listening at {CLOUDFLARE_TARGET_IP}:{CLOUDFLARE_TARGET_PORT}.")
                    return True
            except OSError:
                time.sleep(0.25)

        print(f"[ERROR] Xray did not open {CLOUDFLARE_TARGET_IP}:{CLOUDFLARE_TARGET_PORT} within {timeout}s.")
        return False

    if not wait_for_xray_listener():
        try: xp.terminate()
        except OSError: pass
        return

    def launch_cloudflared():
        # direct mode does not use cloudflared at all.
        if RUN_MODE == "direct":
            return None

        if RUN_MODE == "named_tunnel":
            print("[*] Launching Cloudflare Named Tunnel (token mode)...")
            return subprocess.Popen(
                [CLF_BIN, "tunnel", "run", "--token", TUNNEL_TOKEN],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding='utf-8',
                errors='replace'
            )

        # Quick Tunnels only need an outbound TCP connection and HTTP/2 avoids
        # waiting for QUIC to fail on hosts or networks that block UDP.
        tunnel_protocol = "http2" if RUN_MODE == "quick_tunnel" else "auto"
        print(f"[*] Launching Cloudflare Tunnel ({tunnel_protocol}) pointing to http://{CLOUDFLARE_TARGET_IP}:{CLOUDFLARE_TARGET_PORT}...")
        return subprocess.Popen(
            [CLF_BIN, "tunnel", "--protocol", tunnel_protocol, "--url", f"http://{CLOUDFLARE_TARGET_IP}:{CLOUDFLARE_TARGET_PORT}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding='utf-8',
            errors='replace'
        )

    clp = launch_cloudflared()

    cloudflare_url = None
    published_link_host = None

    try:
        logger = RealtimeLogger(port=9999, password=None)
        logger_url = logger.start()
        print(f"[*] Logger Web UI is running at: {logger_url}")
    except Exception:
        logger = None

    def logger_push(message, source):
        if logger:
            logger.push_log(f"[{source}] {message}", source)
            print(f"[{source}] {message}") if DEBUG_MODE else None

    def monitor_xray(pipe):
        try:
            with pipe:
                for line in iter(pipe.readline, ''):
                    if logger:
                        logger_push(line.strip(), "XRAY")
                    if re.search(r"permission denied|eacces|address already in use|\berror\b|\bfailed\b", line, re.IGNORECASE):
                        print(f"[XRAY ERROR] {line.strip()}")
        except Exception:
            pass

    def monitor_cloudflare(pipe):
        nonlocal cloudflare_url, published_link_host
        ansi_escape = re.compile(r'\x1b\[[0-9;]*[mK]')
        try:
            with pipe:
                for line in iter(pipe.readline, ''):
                    clean_line = ansi_escape.sub('', line)
                    print(f"[CLOUDFLARE LOG] {clean_line.strip()}")

                    if RUN_MODE == "named_tunnel":
                        # Named tunnel via token: the hostname is whatever was
                        # configured on the Cloudflare Zero Trust dashboard
                        # (WS_HOST), not something printed to stdout. Instead,
                        # watch for a "connection registered" log line to know
                        # the tunnel is actually up, then print links once.
                        if published_link_host != WS_HOST and re.search(r'[Rr]egistered tunnel connection', clean_line):
                            cloudflare_url = WS_HOST
                            print_vless_links(cloudflare_url, UUID, FAKE_SNI, WS_PATH)
                            published_link_host = cloudflare_url
                        continue

                    match = re.search(r'https://[a-zA-Z0-9-]+\.trycloudflare\.com', clean_line)
                    if match:
                        new_url = match.group(0).replace("https://", "")
                        if new_url != cloudflare_url:
                            if cloudflare_url:
                                print(f"[*] Detected new tunnel domain: {new_url} (was: {cloudflare_url})")
                            cloudflare_url = new_url
                    if cloudflare_url and published_link_host != cloudflare_url and re.search(r'[Rr]egistered tunnel connection', clean_line):
                        print_vless_links(cloudflare_url, UUID, FAKE_SNI, WS_PATH)
                        published_link_host = cloudflare_url
        except Exception as e:
            # print(e)
            pass

    # Friendly name map for known FAKE_SNI hostnames
    FRIENDLY_NAME_MAP = {
        "api24-normal-alisg.tiktokv.com": "Free Tiktok",
        "vnpt.theworkpc.com": "Free Vina Ko Nen",
    }

    def flag_emoji(cc):
        """Convert 2-letter ISO country code to flag emoji. Returns None if invalid."""
        cc = (cc or "").strip().upper()
        if len(cc) != 2 or not all("A" <= c <= "Z" for c in cc):
            return None
        return "".join(chr(0x1F1E6 + ord(c) - ord("A")) for c in cc)

    def print_vless_links(tunnel_host, uuid_str, fake_sni, ws_path):
        import urllib.parse
        encoded_path = urllib.parse.quote(ws_path, safe='')
        tunnel_host_info = WS_HOST if WS_HOST and WS_HOST != "trycloudflare.com" else tunnel_host
        payloads = []
        country_flag = flag_emoji(COUNTRY_CODE)
        country_prefix = f"[{country_flag}] {COUNTRY_CODE} | " if country_flag else ""

        def add_link(sni, transport, label):
            params = f"type={'ws' if transport == 'websocket' else 'xhttp'}&encryption=none&security="
            xhttp_params = f"&mode={XHTTP_MODE}" if transport == "xhttp" else ""
            if PORT_MODE in ("443", "both"):
                tls_params = f"tls&path={encoded_path}&host={tunnel_host_info}&sni={tunnel_host_info}{xhttp_params}"
                if transport == "xhttp": tls_params += "&alpn=h3%2Ch2"
                payloads.append(f"vless://{uuid_str}@{sni}:443?{params}{tls_params}#{urllib.parse.quote(label + ' 443', safe='')}")
            if PORT_MODE in ("80", "both") and RUN_MODE != "direct":
                payloads.append(f"vless://{uuid_str}@{sni}:80?{params}&path={encoded_path}&host={tunnel_host_info}{xhttp_params}#{urllib.parse.quote(label + ' 80', safe='')}")

        for sni_entry in fake_sni.split(","):
            sni_entry = sni_entry.strip()
            if not sni_entry: continue
            sni, separator, remark = sni_entry.partition("#")
            sni, remark = sni.strip(), remark.strip()
            base_label = remark or FRIENDLY_NAME_MAP.get(sni) or sni
            label = f"{country_prefix}{base_label}"
            for transport in TRANSPORTS:
                add_link(sni, transport, label)

        print("\n" + "=" * 70)
        print(" DIRECT MODE (Cloudflare proxied DNS -> origin :80)" if RUN_MODE == "direct" else " CONNECTED TO CLOUDFLARE TUNNEL")
        print("=" * 70 + "\n")
        with open("frp_info.config", "w", encoding="utf-8") as links_file:
            links_file.write("\n".join(payloads) + ("\n" if payloads else ""))
        print(" VLESS LINKS (server continues running)")
        print("-" * 70)
        for payload in payloads:
            print(payload)
        print("-" * 70)
        print("[OK] Links were also saved to: frp_info.config")
        print("[i] To view them again from another Termux session: cat ~/vless/frp_info.config")

        if SUBSCRIPTION_SYNC_URL:
            if not SUBSCRIPTION_SYNC_TOKEN or not SUBSCRIPTION_NODE_ID:
                print("[!] Subscription sync skipped: URL requires token and node ID.")
            else:
                try:
                    response = requests.post(SUBSCRIPTION_SYNC_URL, json={"node_id": SUBSCRIPTION_NODE_ID, "payloads": payloads}, headers={"Authorization": f"Bearer {SUBSCRIPTION_SYNC_TOKEN}"}, timeout=15)
                    response.raise_for_status()
                    print(f"[OK] Subscription synced: node {SUBSCRIPTION_NODE_ID}")
                except requests.RequestException as error:
                    print(f"[!] Subscription sync failed (server still running): {error}")

        frp_info = {"payloads": payloads, "ip": get_public_url(), "wshost": tunnel_host, "wspath": ws_path, "transport": TRANSPORT, "xhttp_mode": XHTTP_MODE if "xhttp" in TRANSPORTS else None, "start_time": START_TIME}
        send_webhook(frp_info)
        with open("frp_info.json", "w", encoding="utf-8") as info_file: json.dump(frp_info, info_file, indent=4)
        print("Written to frp_info.json")

    # Start log readers only after print_vless_links exists. A Quick Tunnel can
    # return its hostname immediately on fast connections.
    threading.Thread(target=monitor_xray, args=(xp.stdout,), daemon=True).start()
    if clp is not None:
        threading.Thread(target=monitor_cloudflare, args=(clp.stdout,), daemon=True).start()

    # Direct mode has no cloudflared process to scrape a hostname from,
    # so generate links immediately from the configured WS_HOST.
    if RUN_MODE == "direct":
        cloudflare_url = WS_HOST
        print("[!] Recommended: restrict origin port 80 to Cloudflare IP ranges only.")
        print_vless_links(cloudflare_url, UUID, FAKE_SNI, WS_PATH)

    try:
        while True:
            if RUN_MODE == "direct":
                # Only monitor Xray; there is no cloudflared process.
                if xp.poll() is not None:
                    print("\n[!] WARNING: Xray process has stopped.")
                    break
            else:
                if xp.poll() is not None:
                    print("\n[!] WARNING: Xray process has stopped; stopping Cloudflare Tunnel.")
                    try: clp.terminate()
                    except OSError: pass
                    break

                # If only cloudflared died (e.g. quick tunnel dropped/restarted), relaunch it.
                # This will get a brand new trycloudflare.com domain, which monitor_cloudflare
                # picks up and re-broadcasts via print_vless_links() + webhook automatically.
                if clp.poll() is not None and xp.poll() is None:
                    print("[!] Cloudflare Tunnel process stopped unexpectedly. Restarting...")
                    clp = launch_cloudflared()
                    threading.Thread(target=monitor_cloudflare, args=(clp.stdout,), daemon=True).start()

            time.sleep(1)

    except KeyboardInterrupt:
        print("\n[*] Stopping services...")
    finally:
        try: xp.terminate()
        except: pass
        if clp is not None:
            try: clp.terminate()
            except: pass

if __name__ == "__main__":
    main()
