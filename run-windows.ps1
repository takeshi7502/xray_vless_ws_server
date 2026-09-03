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
    FAKE_SNI = "api24-normal-alisg.tiktokv.com#Free Tiktok,vnpt.theworkpc.com#Free Vina Ko Nen"
    WS_PATH = "/tiktok4g"
    WS_HOST = "trycloudflare.com"
    TRANSPORT = "websocket"
    XHTTP_MODE = "packet-up"
    ENABLE_WARP = "false"
    WEBHOOK_URL = ""
    TUNNEL_TOKEN = ""
    COUNTRY_CODE = ""
    CUSTOM_DOMAIN = ""
    PORT_MODE = "both"
    SUBSCRIPTION_SYNC_URL = ""
    SUBSCRIPTION_SYNC_TOKEN = ""
    SUBSCRIPTION_NODE_ID = ""
}
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
    Write-Host " [$Number] " -NoNewline -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Green
    Write-Host " -------------------------------------------------" -ForegroundColor DarkGray
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
    $lines = foreach ($key in $EnvKeys) {
        "$key=$($Settings[$key])"
    }
    $content = ($lines -join [Environment]::NewLine) + [Environment]::NewLine
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($EnvPath, $content, $utf8NoBom)
    Write-Ok "Da ghi .env (RUN_MODE=$($Settings['RUN_MODE']))"
}

# Retained for optional Subscription Hub support. Setup modes do not call it.
function Get-BaseHubUrl([string]$Url) {
    return $Url -replace "/sync$", ""
}

function Normalize-HubUrl([string]$Url) {
    $value = $Url.Trim().TrimEnd("/")
    $value = $value -replace "/frp_info\.config$", ""
    $value = $value -replace "/sync$", ""
    if ($value -notmatch "^https?://") { $value = "https://$value" }
    return "$value/sync"
}

function Select-FakeSni($Settings) {
    Write-Info "Chon domain hien trong ten link."
    Write-Host "   1) Free Tiktok  (api24-normal-alisg.tiktokv.com)"
    Write-Host "   2) Free Vina Ko Nen  (vnpt.theworkpc.com)"
    Write-Host "   3) Ca hai (mac dinh)"
    Write-Host "   Hoac nhap gia tri tuy chinh. Enter = giu gia tri hien tai."
    $choice = Read-Host " Chon [1/2/3/tuy chinh]"
    switch ($choice) {
        "1" { $Settings["FAKE_SNI"] = "api24-normal-alisg.tiktokv.com#Free Tiktok" }
        "2" { $Settings["FAKE_SNI"] = "vnpt.theworkpc.com#Free Vina Ko Nen" }
        "3" { $Settings["FAKE_SNI"] = $Defaults["FAKE_SNI"] }
        "" { if ([string]::IsNullOrWhiteSpace($Settings["FAKE_SNI"])) { $Settings["FAKE_SNI"] = $Defaults["FAKE_SNI"] } }
        default { $Settings["FAKE_SNI"] = $choice.Trim() }
    }
    Write-Ok "FAKE_SNI: $($Settings['FAKE_SNI'])"
}

function Select-Transport($Settings) {
    $default = switch ($Settings["TRANSPORT"]) {
        "xhttp" { "2" }
        "websocket,xhttp" { "3" }
        "xhttp,websocket" { "3" }
        default { "1" }
    }
    Write-Info "Chon transport cho link VLESS."
    Write-Host "   1) WebSocket"
    Write-Host "   2) xHTTP"
    Write-Host "   3) Ca WebSocket + xHTTP"
    $choice = Read-Value " Chon [1/2/3]" $default
    switch ($choice) {
        "1" { $Settings["TRANSPORT"] = "websocket" }
        "2" { $Settings["TRANSPORT"] = "xhttp" }
        "3" { $Settings["TRANSPORT"] = "websocket,xhttp" }
        default { Write-Warn "Lua chon khong hop le, giu lai $($Settings['TRANSPORT'])." }
    }

    if ($Settings["TRANSPORT"] -like "*xhttp*") {
        $modeDefault = switch ($Settings["XHTTP_MODE"]) {
            "stream-up" { "2" }
            "stream-one" { "3" }
            default { "1" }
        }
        Write-Host "   xHTTP mode: 1) packet-up  2) stream-up  3) stream-one"
        $mode = Read-Value " Chon xHTTP mode [1/2/3]" $modeDefault
        switch ($mode) {
            "1" { $Settings["XHTTP_MODE"] = "packet-up" }
            "2" { $Settings["XHTTP_MODE"] = "stream-up" }
            "3" { $Settings["XHTTP_MODE"] = "stream-one" }
            default { Write-Warn "Mode khong hop le, giu lai $($Settings['XHTTP_MODE'])." }
        }
    }
    Write-Ok "Transport: $($Settings['TRANSPORT'])"
}

function Select-PortMode($Settings) {
    Write-Info "Chon cac link se duoc xuat ra."
    Write-Host "   1) Chi port 80 (KHONG TLS)"
    Write-Host "   2) Chi port 443 (TLS)"
    Write-Host "   3) Ca 80 + 443 (mac dinh)"
    $choice = Read-Host " Chon [1/2/3]"
    switch ($choice) {
        "1" { $Settings["PORT_MODE"] = "80" }
        "2" { $Settings["PORT_MODE"] = "443" }
        default { $Settings["PORT_MODE"] = "both" }
    }
    Write-Ok "Che do port: $($Settings['PORT_MODE'])"
}

function Configure-Subscription($Settings) {
    Write-Info "Dong bo subscription nhieu may (tuy chon)."
    Write-Host "      Enter de giu gia tri hien tai; nhap - de tat dong bo."
    $current = Get-BaseHubUrl $Settings["SUBSCRIPTION_SYNC_URL"]
    $answer = Read-Host " URL subscription [$current]"
    if ($answer -eq "-") {
        $Settings["SUBSCRIPTION_SYNC_URL"] = ""
        $Settings["SUBSCRIPTION_SYNC_TOKEN"] = ""
        $Settings["SUBSCRIPTION_NODE_ID"] = ""
        Write-Info "Da tat dong bo subscription."
        return
    }
    if (-not [string]::IsNullOrWhiteSpace($answer)) {
        $Settings["SUBSCRIPTION_SYNC_URL"] = Normalize-HubUrl $answer
    }
    if (-not [string]::IsNullOrWhiteSpace($Settings["SUBSCRIPTION_SYNC_URL"])) {
        $Settings["SUBSCRIPTION_NODE_ID"] = Read-Value " Node ID (duy nhat, vd vps-jp-1)" $Settings["SUBSCRIPTION_NODE_ID"]
        $Settings["SUBSCRIPTION_SYNC_TOKEN"] = Read-Value " Hub sync token" $Settings["SUBSCRIPTION_SYNC_TOKEN"]
        if ([string]::IsNullOrWhiteSpace($Settings["SUBSCRIPTION_NODE_ID"]) -or [string]::IsNullOrWhiteSpace($Settings["SUBSCRIPTION_SYNC_TOKEN"])) {
            throw "Can Node ID va Hub sync token khi bat dong bo subscription."
        }
        Write-Ok "Subscription: $(Get-BaseHubUrl $Settings['SUBSCRIPTION_SYNC_URL'])"
    }
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
    Write-Header "1. Quick Tunnel (trycloudflare.com)"
    Write-Info "Khong can domain. Hostname thay doi moi lan khoi dong."
    $settings = Read-EnvFile
    $settings["RUN_MODE"] = "quick_tunnel"
    $settings["PORT"] = "127.0.0.1:8888"
    $settings["WS_HOST"] = "trycloudflare.com"
    $settings["TUNNEL_TOKEN"] = ""
    $settings["TRANSPORT"] = "websocket"

    Write-Step "1/6" "Thong tin server"
    $settings["XRAY_UUID"] = Read-Value " VLESS UUID" $(if ($settings["XRAY_UUID"]) { $settings["XRAY_UUID"] } else { [guid]::NewGuid().ToString() })

    Write-Step "2/6" "Fake SNI"
    Select-FakeSni $settings

    Write-Step "3/6" "Duong dan WebSocket"
    $settings["WS_PATH"] = Read-Value " Duong dan WebSocket" $settings["WS_PATH"]
    if (-not $settings["WS_PATH"].StartsWith("/")) { $settings["WS_PATH"] = "/$($settings['WS_PATH'])" }
    Write-Ok "Transport: WebSocket"

    Write-Step "4/6" "Port link VLESS"
    Select-PortMode $settings

    Write-Step "5/6" "Vi tri node"
    Configure-Country $settings

    Write-Step "6/6" "Luu va khoi dong"
    Start-Server $settings
}

function Configure-NamedTunnel {
    Write-Header "2. Named Cloudflare Tunnel + domain rieng"
    Write-Info "Trong Cloudflare Zero Trust, tao Public Hostname tro toi http://127.0.0.1:8888."
    $settings = Read-EnvFile
    $defaultHost = if ($settings["WS_HOST"] -eq "trycloudflare.com") { $settings["CUSTOM_DOMAIN"] } else { $settings["WS_HOST"] }

    Write-Step "1/6" "Domain va tunnel credentials"
    $settings["WS_HOST"] = Read-Value " Domain (vd vless.example.com)" $defaultHost
    $settings["TUNNEL_TOKEN"] = Read-Value " Tunnel connector token" $settings["TUNNEL_TOKEN"]
    if ([string]::IsNullOrWhiteSpace($settings["WS_HOST"]) -or $settings["WS_HOST"] -eq "trycloudflare.com") { throw "Can domain cho Named Tunnel." }
    if ([string]::IsNullOrWhiteSpace($settings["TUNNEL_TOKEN"])) { throw "Can tunnel connector token." }
    $settings["RUN_MODE"] = "named_tunnel"
    $settings["PORT"] = "127.0.0.1:8888"
    $settings["CUSTOM_DOMAIN"] = $settings["WS_HOST"]
    $settings["XRAY_UUID"] = Read-Value " VLESS UUID" $(if ($settings["XRAY_UUID"]) { $settings["XRAY_UUID"] } else { [guid]::NewGuid().ToString() })

    Write-Step "2/6" "Fake SNI"
    Select-FakeSni $settings

    Write-Step "3/6" "Diem cuoi transport"
    $settings["WS_PATH"] = Read-Value " Duong dan WebSocket" $settings["WS_PATH"]
    Select-Transport $settings

    Write-Step "4/6" "Port link VLESS"
    Select-PortMode $settings

    Write-Step "5/6" "Vi tri node"
    Configure-Country $settings

    Write-Step "6/6" "Luu va khoi dong"
    Start-Server $settings
}

function Configure-Direct {
    Write-Header "3. Direct Cloudflare proxied DNS -> Windows"
    Write-Warn "Mode nay can quyen Administrator de bind port 80 va can mo Windows Firewall."
    $settings = Read-EnvFile
    $defaultHost = if ($settings["WS_HOST"] -eq "trycloudflare.com") { $settings["CUSTOM_DOMAIN"] } else { $settings["WS_HOST"] }

    Write-Step "1/6" "Domain va origin listener"
    $settings["WS_HOST"] = Read-Value " Domain" $defaultHost
    $settings["PORT"] = Read-Value " Origin listen address:port" "0.0.0.0:80"
    if ([string]::IsNullOrWhiteSpace($settings["WS_HOST"]) -or $settings["WS_HOST"] -eq "trycloudflare.com") { throw "Can domain cho Direct mode." }
    $settings["RUN_MODE"] = "direct"
    $settings["TUNNEL_TOKEN"] = ""
    $settings["CUSTOM_DOMAIN"] = $settings["WS_HOST"]
    $settings["XRAY_UUID"] = Read-Value " VLESS UUID" $(if ($settings["XRAY_UUID"]) { $settings["XRAY_UUID"] } else { [guid]::NewGuid().ToString() })

    Write-Step "2/6" "Fake SNI"
    Select-FakeSni $settings

    Write-Step "3/6" "Diem cuoi transport"
    $settings["WS_PATH"] = Read-Value " Duong dan WebSocket" $settings["WS_PATH"]
    Select-Transport $settings

    Write-Step "4/6" "Port link VLESS"
    Select-PortMode $settings

    Write-Step "5/6" "Vi tri node"
    Configure-Country $settings

    Write-Step "6/6" "Luu va khoi dong"
    Start-Server $settings
}

function Remove-RuntimeFiles {
    $files = @("xray.exe", "cloudflared.exe", "wgcf-cli.exe", ".env", "config.json", "frp_info.config", "frp_info.json", "wgcf.json", "wgcf.xray.json")
    foreach ($file in $files) {
        Remove-Item -LiteralPath (Join-Path $ProjectRoot $file) -Force -ErrorAction SilentlyContinue
    }
    foreach ($directory in @("xray_bin", "__pycache__")) {
        Remove-Item -LiteralPath (Join-Path $ProjectRoot $directory) -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Ok "Da xoa cac file runtime. Source code duoc giu nguyen."
}

try {
    :mainMenu while ($true) {
        Write-Header "May chu Xray VLESS-WS (Windows)"
        Write-Host "  [Windows] Che do truc tiep (khong systemd)" -ForegroundColor Green
        if (Test-Path $EnvPath) {
            $activeSettings = Read-EnvFile
            Write-Host "  Config: $($activeSettings['RUN_MODE']) -> $($activeSettings['WS_HOST'])" -ForegroundColor DarkGray
        }
        Write-Host ""
        Write-Host "  SETUP" -ForegroundColor Cyan
        Write-Host " 1. Quick Tunnel (trycloudflare.com) - khong can domain"
        Write-Host " 2. Named Cloudflare Tunnel + domain rieng"
        Write-Host " 3. Direct Cloudflare proxied DNS -> Windows"
        Write-Host ""
        Write-Host "  UTILITIES" -ForegroundColor Cyan
        Write-Host " 4. Go cai dat runtime"
        Write-Host " 0. Thoat"
        $choice = (Read-Host " Chon [0-4]").Trim()
        switch ($choice) {
            "1" { Configure-QuickTunnel }
            "2" { Configure-NamedTunnel }
            "3" { Configure-Direct }
            "4" { Remove-RuntimeFiles }
            "0" { break mainMenu }
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
