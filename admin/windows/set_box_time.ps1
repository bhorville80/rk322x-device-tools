# set_box_time.ps1 - force la mise a l'heure de la box depuis le PC (Windows, via adb)
#
# Pousse l'heure UTC du PC vers la box :
#   - chemin privilegie : set_time SET (toolkit installe sur /data/scripts)
#   - fallback          : date -u -s directe (toolkit absent)
#
# Usage:
#   powershell -File admin\windows\set_box_time.ps1
#   powershell -File admin\windows\set_box_time.ps1 -Target 192.168.50.20:5555
#
# Prerequis : adb dans le PATH + acces root sur la box (su).

param(
    [string]$Target = ""
)

$ErrorActionPreference = "Stop"

function Die([string]$Msg) {
    Write-Host "[ERREUR heure] $Msg" -ForegroundColor Red
    exit 1
}

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    Die "adb introuvable dans le PATH"
}

# cible par defaut depuis config/device.conf
if (-not $Target) {
    $Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # depot
    $Conf = Join-Path (Join-Path $Repo "config") "device.conf"
    if (-not (Test-Path $Conf)) { Die "config/device.conf introuvable (et pas de -Target)" }
    $Ip = (Select-String -LiteralPath $Conf -Pattern "^IP=(.*)$" |
        Select-Object -First 1).Matches[0].Groups[1].Value.Trim()
    if (-not $Ip) { Die "IP illisible dans config/device.conf" }
    $PortLine = Select-String -LiteralPath $Conf -Pattern "^ADB_PORT=(.*)$" |
        Select-Object -First 1
    $Port = if ($null -ne $PortLine) { $PortLine.Matches[0].Groups[1].Value.Trim() } else { "" }
    if (-not $Port) { $Port = "5555" }
    $Target = "$Ip`:$Port"
}

if ($Target -match ":") {
    & adb connect $Target | Out-Null
}

$AdbArgs = @("-s", $Target)
& adb @AdbArgs shell echo ok *> $null
if ($LASTEXITCODE -ne 0) { Die "box injoignable : $Target" }

function Rget([string]$Cmd) {
    (& adb @AdbArgs shell $Cmd 2>$null) -replace "`r", ""
}
function Rrun([string]$Cmd) {
    & adb @AdbArgs shell ("su -c '" + $Cmd + "'") *> $null
}

$Now = (Get-Date).ToUniversalTime().ToString("yyyyMMdd.HHmmss")
Write-Host "[..] heure PC (UTC) : $Now -> $Target"

if ((Rget "test -f /data/scripts/set_time.sh && echo ok") -eq "ok") {
    $Mode = "set_time SET"
    Rrun "sh /data/scripts/set_time.sh SET $Now"
} else {
    $Mode = "date -u -s (toolkit absent)"
    Rrun "date -u -s $Now"
}

Start-Sleep -Seconds 1
$BoxDate = Rget "date '+%Y-%m-%d %H:%M:%S'"
Write-Host "[ OK ] regle via : $Mode"
Write-Host ("       box       : " + $(if ($BoxDate) { $BoxDate } else { "illisible" }))
Write-Host ("       PC (UTC)  : " + (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss"))

if (-not $BoxDate) { exit 1 }
exit 0
