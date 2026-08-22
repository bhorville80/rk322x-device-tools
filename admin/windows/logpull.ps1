# logpull.ps1 - recupere les collections SEND_LOGS de la cle vers le PC (via adb)
#
# La cle reste branchee sur la box : archive sur la box (root), tiree en
# /data/local/tmp puis extraite vers history/logs/.
#
# Usage:
#   powershell -File admin\windows\logpull.ps1
#   powershell -File admin\windows\logpull.ps1 -All
#   powershell -File admin\windows\logpull.ps1 -Target 192.168.50.20:5555 -Out D:\logs

param(
    [switch]$All,
    [string]$Target = "",
    [string]$Out = ""
)

$ErrorActionPreference = "Stop"

function Die([string]$Msg) {
    Write-Host "[ERREUR logpull] $Msg" -ForegroundColor Red
    exit 1
}

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) { Die "adb introuvable dans le PATH" }

$Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $Target) {
    $Conf = Join-Path (Join-Path $Repo "config") "device.conf"
    if (-not (Test-Path $Conf)) { Die "config/device.conf introuvable (et pas de -Target)" }
    $Ip = (Select-String -LiteralPath $Conf -Pattern "^IP=(.*)$" |
        Select-Object -First 1).Matches[0].Groups[1].Value.Trim()
    if (-not $Ip) { Die "IP illisible dans config/device.conf" }
    $Target = "$Ip`:5555"
}

if ($Target -match ":") { & adb connect $Target | Out-Null }
$AdbArgs = @("-s", $Target)
function Rget([string]$Cmd) { (& adb @AdbArgs shell $Cmd 2>$null) -replace "`r", "" }
function Rrun([string]$Cmd) { & adb @AdbArgs shell ("su -c '" + $Cmd + "'") *> $null }

& adb @AdbArgs shell echo ok *> $null
if ($LASTEXITCODE -ne 0) { Die "box injoignable : $Target" }

$KeyLine = Rget "ls -1d /mnt/media_rw/*/deploy.sh 2>/dev/null" | Select-Object -First 1
if (-not $KeyLine) { Die "aucune cle detectee sur la box ($Target)" }
$KeyDir = $KeyLine.Trim().TrimEnd("/deploy.sh")

$Cols = @(Rget "ls -1d $KeyDir/log/log_* 2>/dev/null | sort" | Where-Object { $_ })
if ($Cols.Count -eq 0) { Die "aucune collection SEND_LOGS sur la cle (deploy SEND_LOGS d'abord ?)" }

if ($All) {
    $Bases = ($Cols | ForEach-Object { Split-Path -Leaf $_ }) -join " "
    $Label = "tout"
} else {
    $Last = $Cols[-1]
    $Bases = Split-Path -Leaf $Last
    $Label = $Bases
}
if ($Bases -match "[^a-zA-Z0-9_.\- ]") { Die "nom de collection inattendu : $Bases" }

$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$RemoteTgz = "/data/local/tmp/rk322x_pull_$Stamp.tgz"

Write-Host "[..] tirage de : $Label <- $KeyDir/log"
Rrun "tar -czf $RemoteTgz -C $KeyDir/log $Bases || busybox tar -czf $RemoteTgz -C $KeyDir/log $Bases"

if (-not $Out) { $Out = Join-Path (Join-Path $Repo "history") "logs" }
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$LocalTgz = Join-Path $Out "rk322x_pull_$Stamp.tgz"
& adb @AdbArgs pull $RemoteTgz $LocalTgz *> $null
if (-not (Test-Path $LocalTgz)) {
    Rrun "rm -f $RemoteTgz"
    Die "echec adb pull"
}
Rrun "rm -f $RemoteTgz"

$First = ($Bases -split " ")[0]
$Extract = Join-Path $Out "${First}_$Stamp"
New-Item -ItemType Directory -Force -Path $Extract | Out-Null
tar -xzf $LocalTgz -C $Extract
Remove-Item $LocalTgz -ErrorAction SilentlyContinue

Write-Host "[ OK ] extrait dans : $Extract"
Get-ChildItem -Recurse -File $Extract | ForEach-Object { Write-Host ("       " + $_.FullName) }
exit 0
