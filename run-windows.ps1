param(
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectRoot

$Defaults = [ordered]@{
    RUN_MODE = "quick_tunnel"
    PORT = "127.0.0.1:8888"
    XRAY_UUID = ""
    FAKE_SNI = "api24-normal-alisg.tiktokv.com#FreeTiktok,172.67.168.158#FreeVNPT,vega-prime.huskydg.dpdns.org#FreeMobiFone"
    WS_PATH = "/vless"
    WS_HOST = "trycloudflare.com"
    TRANSPORT = "websocket,xhttp"
    XHTTP_MODE = "auto"
    ENABLE_WARP = "false"
    WEBHOOK_URL = ""
    TUNNEL_TOKEN = ""
    COUNTRY_CODE = ""
    CUSTOM_DOMAIN = ""
    PORT_MODE = "443"
    DNSECH = ""
    TLS_PORT = ""
    TLS_PEM = ""
    TLS_KEY = ""
    LOGGER_HOST = "127.0.0.1"
    PASSWORD = ""
    DEBUG_MODE = "false"
    FRP_INFO_FORMAT = "plain"
}
$LegacyAddresses = "api24-normal-alisg.tiktokv.com#FreeTiktok,172.67.168.158#FreeVNPT"
$NewAddresses = "vega-prime.huskydg.dpdns.org#FreeMobiFone"
$EnvKeys = @($Defaults.Keys)
$EnvPath = Join-Path $ProjectRoot ".env"
$script:Python = $null

function Write-Header([string]$Title) {
    Write-Host ""
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Green
    Write-Host "===================================================" -ForegroundColor Cyan
}

function Write-Info([string]$Message) { Write-Host " [i] $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host " [OK] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host " [!] $Message" -ForegroundColor Yellow }
function Write-Err([string]$Message) { Write-Host " [ERR] $Message" -ForegroundColor Red }

function Write-Step([string]$Number, [string]$Title) {
    Write-Host ""
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host " BUOC $Number  $Title" -ForegroundColor Green
    Write-Host "===================================================" -ForegroundColor Cyan
}

function Read-Value([string]$Prompt, [string]$Default) {
    $suffix = if ([string]::IsNullOrWhiteSpace($Default)) { "" } else { " [$Default]" }
    $answer = Read-Host "$Prompt$suffix"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim()
}

function Read-EnvFile {
    $settings = [ordered]@{}
    foreach ($key in $EnvKeys) {
        $settings[$key] = $Defaults[$key]
    }

    if (Test-Path $EnvPath) {
        foreach ($line in Get-Content -LiteralPath $EnvPath) {
            $trimmed = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) { continue }
            $separator = $trimmed.IndexOf("=")
            if ($separator -lt 1) { continue }
            $key = $trimmed.Substring(0, $separator).Trim()
            if ($settings.Contains($key)) {
                $settings[$key] = $trimmed.Substring($separator + 1)
            }
        }
    }
    return $settings
}

function Write-EnvFile($Settings) {
    if ([string]::IsNullOrWhiteSpace($Settings["WS_PATH"])) { $Settings["WS_PATH"] = "/vless" }
    if ([string]::IsNullOrWhiteSpace($Settings["XRAY_UUID"])) {
        $Settings["XRAY_UUID"] = [guid]::NewGuid().ToString()
    }
    $lines = foreach ($key in $EnvKeys) {
        "$key=$($Settings[$key])"
    }
    $content = ($lines -join [Environment]::NewLine) + [Environment]::NewLine
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($EnvPath, $content, $utf8NoBom)
    Write-Ok "Da ghi .env (RUN_MODE=$($Settings['RUN_MODE']))"
}

function Select-FakeSni($Settings) {
    $default = switch ($Settings["FAKE_SNI"]) {
        "api24-normal-alisg.tiktokv.com#FreeTiktok" { "1" }
        "api24-normal-alisg.tiktokv.com#Free Tiktok" { "1" }
        "172.67.168.158#FreeVina Ko Nen" { "2" }
        "172.67.168.158#Free Vina Ko Nen" { "2" }
        "172.67.168.158#FreeVNPT" { "2" }
        $NewAddresses { "3" }
        "vega-prime.huskydg.dpdns.org#Free Mobifone" { "3" }
        $Defaults["FAKE_SNI"] { "4" }
        "" { "4" }
        default { "tuy chinh" }
    }
    Write-Info "Chon domain hien trong ten link."
    Write-Host "   1. FreeTiktok  (api24-normal-alisg.tiktokv.com)"
    Write-Host "   2. FreeVNPT  (172.67.168.158)"
    Write-Host "   3. FreeMobiFone (vega-prime.huskydg.dpdns.org)"
    Write-Host "   4. Ca ba (mac dinh cho cai moi)"
    Write-Host "   Hoac nhap gia tri tuy chinh."
    $choice = Read-Value " Chon [1-4/tuy chinh]" $default
    switch ($choice) {
        "1" { $Settings["FAKE_SNI"] = "api24-normal-alisg.tiktokv.com#FreeTiktok" }
        "2" { $Settings["FAKE_SNI"] = "172.67.168.158#FreeVNPT" }
        "3" { $Settings["FAKE_SNI"] = $NewAddresses }
        "4" { $Settings["FAKE_SNI"] = $Defaults["FAKE_SNI"] }
        "tuy chinh" { }
        default { $Settings["FAKE_SNI"] = $choice.Trim() }
    }
    Write-Ok "FAKE_SNI: $($Settings['FAKE_SNI'])"
}

function Select-Transport($Settings) {
    $default = switch ($Settings["TRANSPORT"]) {
        "websocket" { "1" }
        "xhttp" { "2" }
        "websocket,xhttp" { "3" }
        "xhttp,websocket" { "3" }
        default { "3" }
    }
    Write-Info "Chon transport cho link VLESS."
    Write-Host "   1. WebSocket"
    Write-Host "   2. xHTTP"
    Write-Host "   3. Ca WebSocket + xHTTP"
    $choice = Read-Value " Chon [1/2/3]" $default
    switch ($choice) {
        "1" { $Settings["TRANSPORT"] = "websocket" }
        "2" { $Settings["TRANSPORT"] = "xhttp" }
        "3" { $Settings["TRANSPORT"] = "websocket,xhttp" }
        default { Write-Warn "Lua chon khong hop le, giu lai $($Settings['TRANSPORT'])." }
    }

    if ($Settings["TRANSPORT"] -like "*xhttp*") {
        $modeDefault = switch ($Settings["XHTTP_MODE"]) {
            "packet-up" { "1" }
            "stream-up" { "2" }
            "stream-one" { "3" }
            default { "4" }
        }
        Write-Host "   xHTTP mode:"
        Write-Host "   1. packet-up"
        Write-Host "   2. stream-up"
        Write-Host "   3. stream-one"
        Write-Host "   4. auto (mac dinh moi)"
        $mode = Read-Value " Chon xHTTP mode [1/2/3/4]" $modeDefault
        switch ($mode) {
            "1" { $Settings["XHTTP_MODE"] = "packet-up" }
            "2" { $Settings["XHTTP_MODE"] = "stream-up" }
            "3" { $Settings["XHTTP_MODE"] = "stream-one" }
            "4" { $Settings["XHTTP_MODE"] = "auto" }
            default { Write-Warn "Mode khong hop le, giu lai $($Settings['XHTTP_MODE'])." }
        }
    }
    Write-Ok "Transport: $($Settings['TRANSPORT'])"
}

function Select-PortMode($Settings) {
    Write-Info "Chon cac link se duoc xuat ra."
    Write-Host "   1. Chi port 80 (KHONG TLS)"
    Write-Host "   2. Chi port 443 (TLS, mac dinh)"
    Write-Host "   3. Ca 80 + 443"
    $choice = Read-Value " Chon [1/2/3]" "2"
    switch ($choice) {
        "1" { $Settings["PORT_MODE"] = "80" }
        "2" { $Settings["PORT_MODE"] = "443" }
        "3" { $Settings["PORT_MODE"] = "both" }
        default { Write-Warn "Lua chon khong hop le, giu lai $($Settings['PORT_MODE'])." }
    }
    Write-Ok "Che do port: $($Settings['PORT_MODE'])"
}

function Configure-Country($Settings) {
    Write-Info "Ma quoc gia chi dung de gan co va ten node."
    Write-Host "      Hint: VN  JP  US  SG  DE  FR  KR  HK  TW  NL  GB  AU  CA" -ForegroundColor DarkGray
    Write-Host "      Vi du: VN = Vietnam, SG = Singapore, JP = Japan, US = United States" -ForegroundColor DarkGray
    $country = Read-Value " Country code (Enter to skip)" $Settings["COUNTRY_CODE"]
    $country = ([regex]::Replace($country.ToUpperInvariant(), "[^A-Z]", ""))
    $Settings["COUNTRY_CODE"] = if ($country.Length -ge 2) { $country.Substring(0, 2) } else { $country }
    if ($Settings["COUNTRY_CODE"]) { Write-Ok "Country: $($Settings['COUNTRY_CODE'])" }
}

function Configure-Advanced {
    if (-not (Test-Path $EnvPath)) { throw "Hay setup mot che do truoc." }
    $settings = Read-EnvFile
    Write-Header "Cau hinh nang cao"
    Write-Info "Enter giu gia tri; nhap - de xoa gia tri tuy chon. Khoi dong lai sau khi luu."
    $warp = Read-Value " WARP: false / true / ip6only" $settings["ENABLE_WARP"]
    if ($warp -notin @("false", "true", "ip6only")) { throw "WARP khong hop le." }
    $settings["ENABLE_WARP"] = $warp
    foreach ($key in @("DNSECH", "TLS_PORT", "TLS_PEM", "TLS_KEY", "LOGGER_HOST")) {
        $value = Read-Value " $key" $settings[$key]
        $settings[$key] = if ($value -eq "-") { "" } else { $value }
    }
    Write-Warn "TLS_PORT can cert/key PEM co san; TLS chi phuc vu transport dau tien."
    $secret = Read-Host " Logger password (Enter giu cu, - de xoa)" -AsSecureString
    $credential = New-Object System.Management.Automation.PSCredential("logger", $secret)
    $value = $credential.GetNetworkCredential().Password
    if ($value -eq "-") { $settings["PASSWORD"] = "" }
    elseif ($value) { $settings["PASSWORD"] = $value }
    $debugValue = Read-Value " DEBUG_MODE: false / true" $settings["DEBUG_MODE"]
    if ($debugValue -notin @("false", "true")) { throw "DEBUG_MODE khong hop le." }
    $settings["DEBUG_MODE"] = $debugValue
    $format = Read-Value " FRP_INFO_FORMAT: plain / base64" $settings["FRP_INFO_FORMAT"]
    if ($format -notin @("plain", "base64")) { throw "Format khong hop le." }
    $settings["FRP_INFO_FORMAT"] = $format
    Write-EnvFile $settings
}

function Ensure-Python {
    if ($script:Python) { return }
    $launcher = Get-Command py -ErrorAction SilentlyContinue
    if ($launcher) {
        & $launcher.Source -3 -c "import sys; assert sys.version_info >= (3, 9)"
        if ($LASTEXITCODE -eq 0) {
            $script:Python = [pscustomobject]@{ Path = $launcher.Source; Arguments = @("-3") }
            return
        }
    }
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        & $python.Source -c "import sys; assert sys.version_info >= (3, 9)"
        if ($LASTEXITCODE -eq 0) {
            $script:Python = [pscustomobject]@{ Path = $python.Source; Arguments = @() }
            return
        }
    }
    throw "Khong tim thay Python 3.9+. Cai Python tu https://www.python.org/downloads/ va chon Add Python to PATH."
}

function Invoke-Python([string[]]$Arguments) {
    & $script:Python.Path @($script:Python.Arguments) @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Python command failed (exit code $LASTEXITCODE)." }
}

function Start-Server($Settings) {
    Write-EnvFile $Settings
    Ensure-Python
    Write-Info "Dang cai/kiem tra Python dependencies..."
    Invoke-Python @("-m", "pip", "install", "-q", "-r", "requirements.txt")
    Remove-Item -LiteralPath (Join-Path $ProjectRoot "frp_info.config") -Force -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Info "Dang chay server truc tiep tren Windows. Nhan Ctrl+C de dung."
    Write-Host ""
    Invoke-Python @("main.py")
}

function Configure-QuickTunnel {
    Write-Header "Quick Tunnel"
    Write-Info "Khong can domain. Hostname thay doi moi lan khoi dong."
    $settings = Read-EnvFile
    $settings["RUN_MODE"] = "quick_tunnel"
    $settings["PORT"] = "127.0.0.1:8888"
    $settings["WS_HOST"] = "trycloudflare.com"
    $settings["TUNNEL_TOKEN"] = ""
    $settings["TRANSPORT"] = "websocket"

    Write-Step "1/4" "Fake SNI"
    Select-FakeSni $settings

    Write-Step "2/4" "Port link VLESS"
    if (-not $settings["WS_PATH"]) { $settings["WS_PATH"] = "/vless" }
    Write-Ok "Transport: WebSocket"
    Select-PortMode $settings

    Write-Step "3/4" "Vi tri node"
    Configure-Country $settings

    Write-Step "4/4" "Luu va khoi dong"
    Start-Server $settings
}

function Configure-NamedTunnel {
    Write-Header "Named Cloudflare Tunnel"
    Write-Info "Trong Cloudflare Zero Trust, tao Public Hostname tro toi http://127.0.0.1:8888."
    $settings = Read-EnvFile
    if ($settings["RUN_MODE"] -eq "quick_tunnel") { $settings["TRANSPORT"] = "websocket,xhttp" }
    $defaultHost = if ($settings["WS_HOST"] -eq "trycloudflare.com") { $settings["CUSTOM_DOMAIN"] } else { $settings["WS_HOST"] }

    Write-Step "1/6" "Domain va tunnel credentials"
    $settings["WS_HOST"] = Read-Value " Domain (vd vless.example.com)" $defaultHost
    $settings["TUNNEL_TOKEN"] = Read-Value " Tunnel connector token" $settings["TUNNEL_TOKEN"]
    if ([string]::IsNullOrWhiteSpace($settings["WS_HOST"]) -or $settings["WS_HOST"] -eq "trycloudflare.com") { throw "Can domain cho Named Tunnel." }
    if ([string]::IsNullOrWhiteSpace($settings["TUNNEL_TOKEN"])) { throw "Can tunnel connector token." }
    $settings["RUN_MODE"] = "named_tunnel"
    $settings["PORT"] = "127.0.0.1:8888"
    $settings["CUSTOM_DOMAIN"] = $settings["WS_HOST"]

    Write-Step "2/6" "Fake SNI"
    Select-FakeSni $settings

    Write-Step "3/6" "Diem cuoi transport"
    if (-not $settings["WS_PATH"]) { $settings["WS_PATH"] = "/vless" }
    Select-Transport $settings

    Write-Step "4/6" "Port link VLESS"
    Select-PortMode $settings

    Write-Step "5/6" "Vi tri node"
    Configure-Country $settings

    Write-Step "6/6" "Luu va khoi dong"
    Start-Server $settings
}

function Configure-Direct {
    Write-Header "Direct Cloudflare"
    Write-Warn "Mode nay can quyen Administrator de bind port 80 va can mo Windows Firewall."
    $settings = Read-EnvFile
    if ($settings["RUN_MODE"] -eq "quick_tunnel") { $settings["TRANSPORT"] = "websocket,xhttp" }
    $defaultHost = if ($settings["WS_HOST"] -eq "trycloudflare.com") { $settings["CUSTOM_DOMAIN"] } else { $settings["WS_HOST"] }

    Write-Step "1/6" "Domain va origin listener"
    $settings["WS_HOST"] = Read-Value " Domain" $defaultHost
    $settings["PORT"] = Read-Value " Origin listen address:port" "0.0.0.0:80"
    if ([string]::IsNullOrWhiteSpace($settings["WS_HOST"]) -or $settings["WS_HOST"] -eq "trycloudflare.com") { throw "Can domain cho Direct mode." }
    $settings["RUN_MODE"] = "direct"
    $settings["TUNNEL_TOKEN"] = ""
    $settings["CUSTOM_DOMAIN"] = $settings["WS_HOST"]

    Write-Step "2/6" "Fake SNI"
    Select-FakeSni $settings

    Write-Step "3/6" "Diem cuoi transport"
    if (-not $settings["WS_PATH"]) { $settings["WS_PATH"] = "/vless" }
    Select-Transport $settings

    Write-Step "4/6" "Port link VLESS"
    Select-PortMode $settings

    Write-Step "5/6" "Vi tri node"
    Configure-Country $settings

    Write-Step "6/6" "Luu va khoi dong"
    Start-Server $settings
}

function Remove-RuntimeFiles {
    $files = @("xray.exe", "cloudflared.exe", "wgcf-cli.exe", ".env", "config.json", "frp_info.config", "frp_info.base64", "frp_info.json", "wgcf.json", "wgcf.xray.json")
    foreach ($file in $files) {
        Remove-Item -LiteralPath (Join-Path $ProjectRoot $file) -Force -ErrorAction SilentlyContinue
    }
    foreach ($directory in @("xray_bin", "__pycache__")) {
        Remove-Item -LiteralPath (Join-Path $ProjectRoot $directory) -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Ok "Da xoa cac file runtime. Source code duoc giu nguyen."
}

function Manage-Server {
    if (-not (Test-Path $EnvPath)) {
        Write-Warn "Chua co cau hinh. Hay chay mot mode setup truoc."
        return
    }
    while ($true) {
        Write-Header "Quan ly Service"
        Write-Info "Windows chay server truc tiep; nhan Ctrl+C de dung."
        Write-Host " 1. Chay lai cau hinh da luu"
        Write-Host " 2. Xem link VLESS"
        Write-Host " 0. Quay lai"
        switch ((Read-Host " Chon [0-2]").Trim()) {
            "1" { Start-Server (Read-EnvFile) }
            "2" {
                $linksPath = Join-Path $ProjectRoot "frp_info.config"
                if (Test-Path $linksPath) { Ensure-Python; Invoke-Python @("runtime_config.py", "--show-links", $linksPath) }
                else { Write-Info "Chua co link. Hay khoi dong server truoc." }
            }
            "0" { return }
            default { Write-Err "Lua chon khong hop le." }
        }
    }
}

try {
    :mainMenu while ($true) {
        Write-Header "May chu Xray VLESS-WS (Windows)"
        Write-Host "  [Windows] Che do truc tiep (khong systemd)" -ForegroundColor Green
        if (Test-Path $EnvPath) {
            $activeSettings = Read-EnvFile
            Write-Host "  Config: $($activeSettings['RUN_MODE']) -> $($activeSettings['WS_HOST'])" -ForegroundColor DarkGray
        }
        Write-Host " 1. [1] Quick Tunnel - [tao ngay khong can domain]"
        Write-Host " 2. [2] Named Cloudflare Tunnel - [can domain]"
        Write-Host " 3. [3] Direct Cloudflare - [can domain + public port]"
        Write-Host " 4. Quan ly Service"
        Write-Host " 5. Go cai dat"
        Write-Host " 6. Thoat"
        Write-Host " 7. Cau hinh nang cao (WARP / ECH / TLS / logger / Base64)"
        $choice = (Read-Host " Chon [1-7]").Trim()
        switch ($choice) {
            "1" { Configure-QuickTunnel }
            "2" { Configure-NamedTunnel }
            "3" { Configure-Direct }
            "4" { Manage-Server }
            "5" { Remove-RuntimeFiles }
            "6" { break mainMenu }
            "7" { Configure-Advanced }
            default { Write-Err "Lua chon khong hop le." }
        }
        if (-not $NoPause) { [void](Read-Host " Press Enter de tiep tuc") }
    }
}
catch {
    Write-Host "" 
    Write-Err $_.Exception.Message
    if (-not $NoPause) { [void](Read-Host " Press Enter de dong") }
    exit 1
}
