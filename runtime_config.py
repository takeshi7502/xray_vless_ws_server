"""Shared, side-effect-free configuration and subscription helpers."""

import base64
import copy
import ipaddress
import socket
from pathlib import Path
from urllib.parse import quote, urlencode, urlparse


LEGACY_ADDRESSES = "api24-normal-alisg.tiktokv.com#FreeTiktok,172.67.168.158#FreeVina Ko Nen"
UPSTREAM_ADDRESSES = (
    "bright-sirius-star.huskydg.dpdns.org#Tiktok,"
    "alpha-rigel-core.huskydg.dpdns.org#Free VNPT,"
    "vega-prime.huskydg.dpdns.org#Free Mobifone"
)
DEFAULT_ADDRESSES = LEGACY_ADDRESSES + "," + UPSTREAM_ADDRESSES


def parse_listeners(value):
    listeners = []
    for item in value.split(","):
        item = item.strip()
        if not item:
            raise ValueError("Empty listener; use IP:port or [IPv6]:port")
        if item.startswith("["):
            host, separator, port = item[1:].partition("]:")
            if not separator:
                raise ValueError("IPv6 listeners must use [IPv6]:port")
        elif ":" in item:
            host, port = item.rsplit(":", 1)
        else:
            host, port = "0.0.0.0", item
        host = str(ipaddress.ip_address(host))
        port = int(port)
        if not 1 <= port <= 65535:
            raise ValueError("Listener port must be between 1 and 65535")
        if (host, port) in listeners:
            raise ValueError(f"Duplicate listener: {host}:{port}")
        listeners.append((host, port))
    return listeners


def url_host(host):
    return f"[{host}]" if ":" in host and not host.startswith("[") else host


def validate_bindings(bindings):
    for index, (host, port) in enumerate(bindings):
        for other_host, other_port in bindings[:index]:
            same_family = (":" in host) == (":" in other_host)
            wildcard = host in ("0.0.0.0", "::") or other_host in ("0.0.0.0", "::")
            if port == other_port and same_family and (host == other_host or wildcard):
                raise ValueError(f"Overlapping listener: {host}:{port}")


def loopback_target(host):
    return {"0.0.0.0": "127.0.0.1", "::": "::1"}.get(host, host)


def local_public_ips():
    """Best-effort diagnostic only; hostname lookups may omit NICs or NAT IPs."""
    try:
        addresses = socket.getaddrinfo(socket.gethostname(), None)
    except OSError:
        return []
    return sorted({info[4][0] for info in addresses if ipaddress.ip_address(info[4][0]).is_global})


def validate_ech(value):
    if value and (urlparse(value).scheme != "https" or not urlparse(value).hostname):
        raise ValueError("DNSECH must be empty or an HTTPS DNS-over-HTTPS URL")
    return value


def configure_routing(config, warp_mode, warp_outbound=None, resolver=socket.getaddrinfo):
    if warp_mode not in ("false", "true", "ip6only"):
        raise ValueError("ENABLE_WARP must be false, true, or ip6only")
    config["dns"] = {"servers": ["https+local://1.1.1.1/dns-query"], "queryStrategy": "UseIP"}
    config["outbounds"] = [{"tag": "direct", "protocol": "freedom", "settings": {"domainStrategy": "UseIPv4"}}]
    if warp_mode == "false":
        return config
    if not warp_outbound:
        raise ValueError("WARP requires a generated wgcf.xray.json outbound")
    warp = copy.deepcopy(warp_outbound)
    warp["tag"] = "wireguard"
    if warp_mode == "true":
        config["outbounds"].insert(0, warp)
        return config

    # Bootstrap the WireGuard tunnel over IPv4 before routing IPv6 through it.
    warp["settings"]["domainStrategy"] = "ForceIPv6"
    for peer in warp["settings"].get("peers", []):
        endpoint = peer.get("endpoint", "")
        host, separator, port = endpoint.rpartition(":")
        if not separator or not port.isdigit():
            raise ValueError("Invalid WireGuard peer endpoint")
        host = host.strip("[]")
        try:
            ip = ipaddress.ip_address(host)
        except ValueError:
            try:
                host = resolver(host, int(port), socket.AF_INET, socket.SOCK_DGRAM)[0][4][0]
            except socket.gaierror:
                host = "162.159.192.1"
        else:
            if ip.version != 4:
                host = "162.159.192.1"
        peer["endpoint"] = f"{host}:{port}"
    config["outbounds"].append(warp)
    config["routing"] = {
        "domainStrategy": "IPIfNonMatch",
        "rules": [{"type": "field", "ip": ["::/0"], "outboundTag": "wireguard"}],
    }
    return config


def make_inbound(listen, port, transport, client_id, path, xhttp_mode="auto", certificate=None):
    stream = {"network": "xhttp" if transport == "xhttp" else "ws", "security": "none"}
    if transport == "xhttp":
        stream["xhttpSettings"] = {"path": path, "mode": xhttp_mode}
    else:
        stream["wsSettings"] = {"path": path, "headers": {}}
    if certificate:
        cert_file, key_file = certificate
        stream.update(security="tls", tlsSettings={"certificates": [{"certificateFile": cert_file, "keyFile": key_file}]})
    return {
        "port": port, "listen": listen, "protocol": "vless",
        "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"], "routeOnly": True},
        "settings": {"clients": [{"id": client_id, "level": 0}], "decryption": "none"},
        "streamSettings": stream,
    }


def build_links(client_id, addresses, transports, host, path, port_mode="443", xhttp_mode="auto", ech="", country="", run_mode="quick_tunnel"):
    validate_ech(ech)
    flag = "".join(chr(0x1F1E6 + ord(c) - ord("A")) for c in country) if len(country) == 2 and country.isascii() and country.isalpha() and country.isupper() else ""
    prefix = f"[{flag}] {country} | " if flag else ""
    links = []
    for entry in addresses.split(","):
        address, _, remark = entry.strip().partition("#")
        address = address.strip()
        if not address:
            continue
        friendly = {"api24-normal-alisg.tiktokv.com": "FreeTiktok", "172.67.168.158": "FreeVina Ko Nen"}
        label = {"Free Tiktok": "FreeTiktok", "Free Vina Ko Nen": "FreeVina Ko Nen"}.get(remark.strip(), remark.strip()) or friendly.get(address, address)
        for transport in transports:
            params = {"type": "xhttp" if transport == "xhttp" else "ws", "encryption": "none"}
            name = quote(f"{prefix}{label} {'XHTTP' if transport == 'xhttp' else 'WS'}", safe="")
            for port in ((443, 80) if port_mode == "both" else (int(port_mode),)):
                if port == 80 and run_mode == "direct":
                    continue
                query = dict(params, security="tls" if port == 443 else "none", path=path, host=host)
                if transport == "xhttp":
                    query["mode"] = xhttp_mode
                if port == 443:
                    query["sni"] = host
                    if transport == "xhttp":
                        query["alpn"] = "h3,h2"
                    if ech:
                        query["ech"] = host + "+" + ech
                links.append(f"vless://{client_id}@{url_host(address)}:{port}?{urlencode(query, quote_via=quote)}#{name}")
    return links


def write_subscription(links, output_format="plain", directory="."):
    if output_format not in ("plain", "base64"):
        raise ValueError("FRP_INFO_FORMAT must be plain or base64")
    plain = "\n".join(links) + ("\n" if links else "")
    encoded = base64.b64encode(plain.encode("utf-8")).decode("ascii")
    directory = Path(directory)
    for name, content in (("frp_info.config", plain if output_format == "plain" else encoded), ("frp_info.base64", encoded)):
        target = directory / name
        temporary = target.with_suffix(target.suffix + ".tmp")
        temporary.write_text(content, encoding="utf-8")
        temporary.replace(target)


def read_subscription(filename):
    content = Path(filename).read_text(encoding="utf-8").strip()
    if not content or content.startswith("vless://"):
        return content
    return base64.b64decode(content, validate=True).decode("utf-8").strip()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--show-links", required=True)
    args = parser.parse_args()
    print(read_subscription(args.show_links))
