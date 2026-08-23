# identify_box.ps1 - identifie la box MXQ/RK322X depuis le PC (Windows, via adb)
#
# Etats geres (le script dit toujours OU en est la box) :
#   [0] adb absent              -> chemin teste + consigne d'installation
#   [1] box absente du bus USB  -> scan PnP des VID candidats + procedure [P2..P5]
#   [2] box USB visible mais    -> peripherique trouve : pilote / debogage USB
#       hors adb                   a verifier
#   [3] box joignable (USB ou   -> carte d'identite complete + option
#       TCP via -Target)           inventaire materiel [N3] si toolkit installe
#
# VID/PID attendus sur RK322X :
#   18D1:xxxx  Google ADB composite (PID 4EE7 courant, D002 bootloader)
#   2207:0006  Rockchip adb seul ; 2207:0011 MTP+adb
#   1F3A:xxxx  mode loader/maskrom (ne pas confondre avec adb)
#
# Usage:
#   powershell -File admin\windows\identify_box.ps1
#   powershell -File admin\windows\identify_box.ps1 -Target 192.168.50.20:5555
#   powershell -File admin\windows\identify_box.ps1 -Serial <serial adb>
#   powershell -File admin\windows\identify_box.ps1 -Full   (+ device_info [N3])
#
# Prerequis : adb (PATH ou %LOCALAPPDATA%\Android\Sdk\platform-tools).
# Root (su) utile seulement pour l'option -Full.

param(
    [string]$Target = "",
    [string]$Serial = "",
    [switch]$Full
)

$ErrorActionPreference = "Stop"

function Die([string]$Msg) {
    Write-Host "[ERREUR ident] $Msg" -ForegroundColor Red
    exit 1
}

# --- adb : PATH puis repli platform-tools SDK (pattern set_box_time.bat) ---
$AdbExe = $null
foreach ($Cand in @(
    (Get-Command adb -ErrorAction SilentlyContinue).Source,
    (Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"))) {
    if ($Cand -and (Test-Path $Cand)) { $AdbExe = $Cand ; break }
}
if (-not $AdbExe) {
    Die "adb introuvable (ni PATH ni $env:LOCALAPPDATA\Android\Sdk\platform-tools)"
}
$AdbInfo = & $AdbExe version | Select-Object -First 1
Write-Host "[ OK ] adb : $AdbInfo"
Write-Host "       ($AdbExe)"

# --- selection de la cible ---
if ($Target) {
    & $AdbExe connect $Target *> $null
    $Sel = @("-s", $Target)
} elseif ($Serial) {
    $Sel = @("-s", $Serial)
} else {
    $Null0 = & $AdbExe start-server 2>$null
    $Lines = (& $AdbExe devices -l) | Select-Object -Skip 1 |
        Where-Object { $_.Trim() -ne "" }
    if (-not $Lines) {
        Write-Host ""
        Write-Host "[ -- ] aucune box dans 'adb devices'"
        & $AdbExe kill-server *> $null

        # scan PnP Windows : la box est-elle enumerable quelque part ?
        $Cands = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -match 'VID_(18D1|2207|1F3A)' }
        if ($Cands) {
            Write-Host "[ !! ] peripherique(s) Android/Rockchip sur le bus USB mais HORS adb :" -ForegroundColor Yellow
            foreach ($D in $Cands) {
                Write-Host ("       {0}  {1}" -f $D.Status, $D.InstanceId)
                if ($D.Status -ne "OK") {
                    Write-Host "       -> pilote a installer (Google USB Driver) ou peripherique en erreur"
                } else {
                    Write-Host "       -> debogage USB desactive sur la TV ? refaire [P2][P3]"
                }
            }
        } else {
            Write-Host "[ -- ] aucun peripherique Android/Rockchip sur le bus USB"
            Write-Host "       VID attendus quand elle sera branchee :"
            Write-Host "         18D1:4EE7  ADB composite (courant)"
            Write-Host "         2207:0006  Rockchip adb seul"
            Write-Host "         2207:0011  Rockchip MTP+adb"
            Write-Host "         1F3A:....  loader/maskrom (pas adb)"
        }
        Write-Host ""
        Write-Host "       procedure : [P2] options developpeur (7x build),"
        Write-Host "                   [P3] debogage USB ON, cable DONNEES,"
        Write-Host "                   puis relancer ce script"
        exit 1
    }
    if (@($Lines).Count -gt 1) {
        Write-Host "[ !! ] plusieurs peripheriques adb, preciser lequel :" -ForegroundColor Yellow
        $Lines | ForEach-Object { Write-Host "       $_" }
        Write-Host "       relancer avec -Serial <serial> ou -Target ip:port"
        exit 1
    }
    # serial = 1er champ de la ligne "SERIAL device product:..."
    $Serial = ($Lines[0] -split "\s+")[0]
    $Sel = @("-s", $Serial)
}

& $AdbExe @Sel shell echo ok *> $null
if ($LASTEXITCODE -ne 0) { Die "box injoignable : $($Sel[1])" }

function Rget([string]$Cmd) {
    (& $AdbExe @Sel shell $Cmd 2>$null) -replace "`r", ""
}

# --- carte d'identite ---
$Transport = if ($Target) { "TCP $Target" } else { "USB $($Sel[1])" }
Write-Host ""
Write-Host "=== IDENTITE BOX ($Transport) ==="

$Model   = Rget "getprop ro.product.model"
$Device  = Rget "getprop ro.product.device"
$Brand   = Rget "getprop ro.product.brand"
$Board   = Rget "getprop ro.product.board"
$Hw      = Rget "getprop ro.hardware"
$Platf   = Rget "getprop ro.board.platform"
$Rel     = Rget "getprop ro.build.version.release"
$Sdk     = Rget "getprop ro.build.version.sdk"
$Patch   = Rget "getprop ro.build.version.security_patch"
$BuildId = Rget "getprop ro.build.display.id"
$Fp      = Rget "getprop ro.build.fingerprint"
$SerialB = Rget "getprop ro.serialno"
$UpTime  = Rget "uptime"

$row = { param($K, $V) Write-Host ("  {0,-14} {1}" -f "$K :", $(if ($V) { $V } else { "[ -- ]" })) }
& $row "modele"     "$Brand $Model ($Device)"
& $row "board/soc"  "$Board / $Platf ($Hw)"
& $row "android"    "$Rel (SDK $Sdk), patch $Patch"
& $row "build"      $BuildId
& $row "fingerprint" $Fp
& $row "serialno"   $SerialB

# reseau : IP effective + MAC eth0 (root non requis pour lecture)
$IpEth = Rget "ip -4 addr show eth0 2>/dev/null | grep inet"
$Mac   = Rget "cat /sys/class/net/eth0/address 2>/dev/null"
$Route = Rget "ip route 2>/dev/null | grep default"
& $row "eth0"       "$(if ($IpEth) { $IpEth.Trim() } else { '[ -- ] pas d adresse' })"
& $row "mac eth0"   $Mac
& $row "passerelle" "$(if ($Route) { $Route.Trim() } else { '[ -- ]' })"

$Root = Rget "su -c id 2>/dev/null"
& $row "root (su)"  "$(if ($Root -match "uid=0") { "OUI" } else { "NON (limite aux lectures shell)" })"
& $row "uptime"     "$(if ($UpTime) { $UpTime.Trim() } else { '' })"

# coherence avec config/device.conf du depot
$Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Conf = Join-Path (Join-Path $Repo "config") "device.conf"
if (Test-Path $Conf) {
    $ConfIp = (Select-String -LiteralPath $Conf -Pattern "^IP=(.*)$" |
        Select-Object -First 1).Matches[0].Groups[1].Value.Trim()
    $ConfName = (Select-String -LiteralPath $Conf -Pattern "^DEVICE_NAME=(.*)$" |
        Select-Object -First 1).Matches[0].Groups[1].Value.Trim()
    $BoxIp = if ($IpEth -match "inet (\d+\.\d+\.\d+\.\d+)") { $Matches[1] } else { "" }
    Write-Host ""
    Write-Host ("  attendu (device.conf) : {0} @ {1}" -f $ConfName, $ConfIp)
    if ($BoxIp -eq $ConfIp) {
        Write-Host "  [ OK ] IP conforme a la configuration du depot"
    } elseif ($BoxIp) {
        Write-Host "  [ !! ] IP differente de device.conf (reseau statique non applique ?)" -ForegroundColor Yellow
        Write-Host "         remediation : set_network sur la box ([C3] ping ensuite)"
    }
}

# --- option -Full : inventaire materiel complet [N3] ---
if ($Full) {
    Write-Host ""
    Write-Host "--- inventaire materiel [N3] ---"
    if ((Rget "test -f /data/scripts/device_info.sh && echo ok") -eq "ok") {
        Write-Host (Rget "su -c 'sh /data/scripts/device_info.sh'")
    } else {
        $Src = Join-Path (Join-Path $Repo "scripts") "device_info.sh"
        if (Test-Path $Src) {
            & $AdbExe @Sel push $Src /data/local/tmp/device_info.sh *> $null
            Write-Host (Rget "sh /data/local/tmp/device_info.sh")
        } else {
            Write-Host "[ -- ] scripts/device_info.sh absent du depot : inventaire indisponible"
        }
    }
}

exit 0
