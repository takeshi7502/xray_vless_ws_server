import os
import platform
import requests

WGCF_VERSION = "v0.3.6"
BASE_URL = f"https://github.com/vincentng295/wgcf-cli/releases/download/{WGCF_VERSION}"


def get_os_name():
    system = platform.system().lower()
    arch = platform.machine().lower()
    if os.getenv("TERMUX_VERSION") or "com.termux" in os.getenv("PREFIX", ""):
        system = "android"
    suffixes = {
        "windows": {"amd64": "windows-64.exe", "x86_64": "windows-64.exe", "arm64": "windows-arm64-v8a.exe", "aarch64": "windows-arm64-v8a.exe", "x86": "windows-32.exe", "i686": "windows-32.exe"},
        "linux": {"amd64": "linux-64", "x86_64": "linux-64", "arm64": "linux-arm64-v8a", "aarch64": "linux-arm64-v8a", "armv7l": "linux-arm32-v7a", "arm": "linux-arm32-v7a"},
        "darwin": {"arm64": "macos-arm64-v8a", "aarch64": "macos-arm64-v8a", "x86_64": "macos-64"},
        "android": {"arm64": "android-arm64-v8a", "aarch64": "android-arm64-v8a", "amd64": "android-amd64", "x86_64": "android-amd64"},
    }
    suffix = suffixes.get(system, {}).get(arch)
    if not suffix:
        raise RuntimeError(f"Unsupported wgcf platform: {system} {arch}")
    return "wgcf-cli-" + suffix, "wgcf-cli.exe" if system == "windows" else "wgcf-cli"


def install_wgcf():
    asset, destination = get_os_name()
    temporary = destination + ".download"
    try:
        with requests.get(f"{BASE_URL}/{asset}", stream=True, timeout=(15, 120)) as response:
            response.raise_for_status()
            with open(temporary, "wb") as output:
                for chunk in response.iter_content(chunk_size=65536):
                    output.write(chunk)
        if not os.path.getsize(temporary):
            raise RuntimeError("Downloaded wgcf binary is empty")
        if os.name != "nt":
            os.chmod(temporary, 0o755)
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.remove(temporary)
    print(f"[OK] Installed wgcf: {os.path.abspath(destination)}")


if __name__ == "__main__":
    install_wgcf()
