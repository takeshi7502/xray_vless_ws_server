import os
import platform
import shutil
import tarfile
import requests

CLOUDFLARED_VERSION = "2026.8.2"
BASE_URL = f"https://github.com/cloudflare/cloudflared/releases/download/{CLOUDFLARED_VERSION}"


def is_termux():
    return platform.system().lower() == "android" or bool(os.getenv("TERMUX_VERSION")) or "com.termux" in os.getenv("PREFIX", "")


def get_download_info():
    system, arch = platform.system().lower(), platform.machine().lower()
    suffixes = {
        "windows": {"amd64": "amd64.exe", "x86_64": "amd64.exe", "x86": "386.exe", "i686": "386.exe"},
        "linux": {"amd64": "amd64", "x86_64": "amd64", "arm64": "arm64", "aarch64": "arm64", "armv7l": "arm", "arm": "arm", "i686": "386", "i386": "386"},
        "darwin": {"amd64": "amd64.tgz", "x86_64": "amd64.tgz", "arm64": "arm64.tgz", "aarch64": "arm64.tgz"},
    }
    suffix = suffixes.get(system, {}).get(arch)
    if not suffix:
        raise RuntimeError(f"Unsupported cloudflared platform: {system} {arch}")
    return f"cloudflared-{system}-{suffix}", "cloudflared.exe" if system == "windows" else "cloudflared"


def download_file(url, filename):
    print(f"[*] Downloading: {url}")
    with requests.get(url, stream=True, timeout=(15, 120)) as response:
        response.raise_for_status()
        with open(filename, "wb") as output:
            for chunk in response.iter_content(chunk_size=65536):
                output.write(chunk)


def install_cloudflared():
    if is_termux():
        existing = shutil.which("cloudflared")
        if not existing:
            raise RuntimeError("Termux: run pkg install cloudflared -y, then restart")
        destination = os.path.abspath("cloudflared")
        if os.path.realpath(existing) != os.path.realpath(destination):
            if os.path.lexists(destination):
                os.remove(destination)
            os.symlink(existing, destination)
        return
    asset, destination = get_download_info()
    temporary, archive = destination + ".download", "cloudflared_temp.archive"
    try:
        if asset.endswith(".tgz"):
            download_file(f"{BASE_URL}/{asset}", archive)
            with tarfile.open(archive, "r:gz") as package:
                member = next((m for m in package.getmembers() if m.isfile() and os.path.basename(m.name) == "cloudflared"), None)
                if member is None:
                    raise RuntimeError("cloudflared binary missing from archive")
                with package.extractfile(member) as source, open(temporary, "wb") as output:
                    shutil.copyfileobj(source, output)
        else:
            download_file(f"{BASE_URL}/{asset}", temporary)
        if not os.path.getsize(temporary):
            raise RuntimeError("Downloaded cloudflared binary is empty")
        if os.name != "nt":
            os.chmod(temporary, 0o755)
        os.replace(temporary, destination)
    finally:
        for filename in (temporary, archive):
            if os.path.exists(filename):
                os.remove(filename)
    print(f"[OK] Installed cloudflared: {os.path.abspath(destination)}")


if __name__ == "__main__":
    install_cloudflared()
