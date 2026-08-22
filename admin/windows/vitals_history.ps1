# vitals_history.ps1 - un passage de collecte des signes vitaux, toutes les boxes
#
# Pour chaque box joignable : `vitals CSV` via adb -> append dans
# history/vitals/<ip>.csv (en-tete ecrit a la creation du fichier).
# A planifier avec le Planificateur de taches Windows (une execution = 1 ligne/box).
#
# Usage:
#   powershell -File admin\windows\vitals_history.ps1
#   powershell -File admin\windows\vitals_history.ps1 -Targets 192.168.50.20,192.168.50.21

param(
    [string]$Targets = ""
)

$ErrorActionPreference = "Continue"

function Die([string]$Msg) {
    Write-Host "[ERREUR vitals-h] $Msg" -ForegroundColor Red
    exit 1
}

$Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$OutDir = Join-Path (Join-Path $Repo "history") "vitals"

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) { Die "adb introuvable dans le PATH" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$List = @()
if ($Targets) {
    $List = $Targets -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ }
} else {
    $Fleet = Join-Path (Join-Path $Repo "config") "fleet.txt"
    if (Test-Path $Fleet) {
        $List = Get-Content $Fleet |
            Where-Object { $_ -and ($_ -notmatch "^\s*#") } |
            ForEach-Object { $_.Trim() }
    }
    if ($List.Count -eq 0) {
        $Conf = Join-Path (Join-Path $Repo "config") "device.conf"
        if (-not (Test-Path $Conf)) { Die "ni config/fleet.txt ni config/device.conf" }
        $Ip = (Select-String -LiteralPath $Conf -Pattern "^IP=(.*)$" |
            Select-Object -First 1).Matches[0].Groups[1].Value.Trim()
        if (-not $Ip) { Die "IP illisible" }
        $List = @($Ip)
    }
}

$Header = "epoch,tmax_c,tmax_zone,cpu_mhz,governor,load1,ram_pct,uptime_min"

foreach ($T in $List) {
    $Tgt = if ($T -match ":") { $T } else { "$T`:5555" }
    $Ip = ($Tgt -split ":")[0]

    & adb connect $Tgt *> $null
    $Raw = & adb -s $Tgt shell 'su -c "sh /data/scripts/vitals.sh CSV"' 2>$null
    $V = (($Raw -join "") -replace "`r", "").Trim()

    if ($V -match "^[0-9]+,") {
        $Csv = Join-Path $OutDir "$Ip.csv"
        if (-not (Test-Path $Csv) -or ((Get-Item $Csv).Length -eq 0)) {
            Set-Content -LiteralPath $Csv -Value $Header -Encoding Ascii
        }
        Add-Content -LiteralPath $Csv -Value $V -Encoding Ascii
        Write-Host "[ OK ] $Ip -> $(Split-Path -Leaf $Csv) : $V"
    } elseif (-not $V) {
        Write-Host "[ KO ] $Ip injoignable ou toolkit absent"
    } else {
        Write-Host "[ ?? ] $Ip reponse inattendue : $V"
    }
}
exit 0
