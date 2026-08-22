<#
admin/windows/provision.ps1 - provisionnement de la MXQ depuis un PC Windows

Miroir de admin/linux/provision.sh. Chaque etape est verifiee puis validee
(avec -Fix : corrige puis re-verifie) :

  [0] reseau   : sous-reseau de la box joignable (-Net pour l'ajouter au PC), ping
  [1] adb      : adb connect <ip>:5555 si necessaire
  [2] root     : su -c id -u == 0 sur la box
  [3] version  : /data/scripts/VERSION vs DEPLOY_VERSION (config/device.conf)
  [4] config   : interface UP, IP statique, passerelle, DNS
  [5] wireless : Wi-Fi et Bluetooth coupes
  [6] horloge  : derive < 5 min (sinon remise a l'heure UTC du PC)
  [7] hdmi     : etat framebuffer (informatif)
  [8] outils v3: cut_services/system_rw/front_led/inspect_all/amorce

Usage:
  powershell -ExecutionPolicy Bypass -File admin\windows\provision.ps1 [-Target cible]
             [-Fix] [-Net] [-SkipDate] [check|fix]

Options:
  -Target cible   cible adb (defaut : <IP>:5555 du profil device.conf)
  -Net            ajoute <sous-reseau>.1/24 au PC si absent (admin requis)
  -Fix            applique les corrections possibles puis re-valide
  -SkipDate       ne touche pas a l'horloge de la box
#>

param(
    [string]$Target = "",
    [ValidateSet("check", "fix")]
    [string]$Action = "check",
    [switch]$Fix,
    [switch]$Net,
    [switch]$SkipDate
)

$ErrorActionPreference = "Continue"

if ($Action -eq "fix") { $Fix = $true }

$Repo = Split-Path -Parent $PSScriptRoot          # admin/
$Repo = Split-Path -Parent $Repo                  # depot
$Conf = Join-Path (Join-Path $Repo "config") "device.conf"

if (-not (Test-Path $Conf)) {
    Write-Host "[ERREUR prov] config introuvable : $Conf"
    exit 1
}

function Cfg([string]$Key, [string]$Default) {
    $line = Select-String -LiteralPath $Conf -Pattern ("^" + $Key + "=(.*)$") |
        Select-Object -First 1
    if ($null -eq $line) { return $Default }
    return $line.Matches[0].Groups[1].Value.Trim()
}

$DeviceName = Cfg "DEVICE_NAME" "boitier"
$Iface      = Cfg "INTERFACE"   "eth0"
$BoxIp      = Cfg "IP"          "192.168.50.20"
$Gw         = Cfg "GATEWAY"     ""
if (-not $Gw) { $Gw = "192.168.50.1" }
$Dns        = Cfg "DNS"         ""
if (-not $Dns) { $Dns = $Gw }
$VerCfg     = Cfg "DEPLOY_VERSION" "?"
$Parts      = $BoxIp.Split(".")
$Subnet     = "$($Parts[0]).$($Parts[1]).$($Parts[2])"
$Prefix     = "24"
$AdbPort    = "5555"

$script:Pass   = 0
$script:KoN    = 0
$script:FixedN = 0

function Ok([string]$msg) { Write-Host ("  [ OK ] " + $msg); $script:Pass++ }
function Ko([string]$label, [string]$detail) {
    Write-Host ("  [ KO ] " + $label.PadRight(28) + " " + $detail); $script:KoN++
}
function Fixed([string]$label, [string]$detail) {
    Write-Host ("  [FIX ] " + $label.PadRight(28) + " " + $detail)
    $script:FixedN++; $script:Pass++
}
function WarnMsg([string]$label, [string]$detail) {
    Write-Host ("  [WARN] " + $label.PadRight(28) + " " + $detail)
}
function InfoMsg([string]$msg) { Write-Host ("  [ -- ] " + $msg) }

function Die([string]$msg) {
    Write-Host "[ERREUR prov] $msg"
    exit 1
}

# --- helpers distants --------------------------------------------------------
function AdbRun {
    if ($Target) { & adb -s $Target @args } else { & adb @args }
}

function Rget([string]$Cmd) {
    $out = AdbRun shell $Cmd 2>$null
    if ($null -eq $out) { return "" }
    return (($out | Out-String) -replace "`r", "").Trim()
}

function Rrun([string]$Cmd) {
    AdbRun shell ("su -c '" + $Cmd + "'") *> $null
}

# === [0] RESEAU ==============================================================
Write-Host ""
Write-Host "--- [0] Reseau PC -> box ---"

$hasSubnet = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -like "$Subnet.*" }).Count -gt 0

if ($hasSubnet) {
    Ok "PC present sur $Subnet.0/$Prefix"
} else {
    WarnMsg "PC hors sous-reseau" "$Subnet.0/$Prefix absent des interfaces"
    if ($Net) {
        $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric | Select-Object -First 1
        if ($null -eq $route) { Die "interface reseau du PC introuvable" }
        try {
            New-NetIpAddress -IPAddress "$Subnet.1" -PrefixLength 24 `
                -InterfaceAlias $route.InterfaceAlias -ErrorAction Stop | Out-Null
            Fixed "adresse PC" "$($Subnet).1/24 sur $($route.InterfaceAlias)"
        } catch {
            Ko "adresse PC" "echec ajout $($Subnet).1/24 (console admin requise ?)"
        }
    } else {
        InfoMsg "relancer avec -Net pour poser $Subnet.1/24 sur le PC"
    }
}

$pingOk = $false
for ($i = 1; $i -le 4; $i++) {
    if (Test-Connection -ComputerName $BoxIp -Count 1 -Quiet) { $pingOk = $true; break }
    Start-Sleep -Seconds 1
}
if (-not $pingOk) {
    Die "$DeviceName injoignable (ping $BoxIp) : verifier cable/switch/adresse"
}
Ok "ping $BoxIp"

# === [1] ADB =================================================================
Write-Host ""
Write-Host "--- [1] ADB ---"

$state = $null
try { $state = AdbRun get-state 2>$null } catch { $state = $null }

if (-not ($state -and "$state".Trim() -eq "device")) {
    Write-Host "[prov] connexion adb $BoxIp`:$AdbPort..."
    & adb connect "${BoxIp}:${AdbPort}" *> $null
    Start-Sleep -Seconds 1
    for ($i = 1; $i -le 3; $i++) {
        try { $state = AdbRun get-state 2>$null } catch { $state = $null }
        if ($state -and "$state".Trim() -eq "device") { break }
        & adb connect "${BoxIp}:${AdbPort}" *> $null
        Start-Sleep -Seconds 2
    }
}
if ($state -and "$state".Trim() -eq "device") {
    Ok "adb connecte (${Target})"
} else {
    Die "adb injoignable sur ${BoxIp}:$AdbPort (debug USB / adb tcpip sur la box)"
}

# === [2] ROOT ================================================================
Write-Host ""
Write-Host "--- [2] Root ---"

$RootOk = ((Rget "su -c id -u") -eq "0")
if ($RootOk) {
    Ok "acces root (su)"
} else {
    WarnMsg "acces root" ($(if ($Fix) { "requis pour -Fix" } else { "indisponible (lecture seule)" }))
    if ($Fix) { Die "-Fix exige un acces root sur la box" }
}

# === [3] VERSION INSTALLEE ===================================================
Write-Host ""
Write-Host "--- [3] Toolkit installe ---"

$vInst = (Rget "cat /data/scripts/VERSION" -split "`n" |
    Select-String -Pattern "^version\s*:\s*(.*)$" |
    Select-Object -First 1)
$vStr = ""
if ($vInst) { $vStr = $vInst.Matches[0].Groups[1].Value.Trim() }

if (-not $vStr) {
    Ko "version installee" "absente (installer : tools/dpk.sh install)"
} elseif ($vStr -eq $VerCfg) {
    Ok "version installee = $vStr"
} else {
    Ko "version installee" "$vStr (profil v$VerCfg, MAJ : tools/dpk.sh install)"
}

# === [4] CONFIG RESEAU BOX ===================================================
Write-Host ""
Write-Host "--- [4] Config reseau box ($Iface) ---"

$linkOut = Rget "ip link show $Iface"
if (-not $linkOut) {
    Ko "interface $Iface" "absente"
} elseif ($linkOut -match "state UP|state UNKNOWN") {
    Ok "$Iface UP"
} else {
    Ko "$Iface DOWN" "correction possible avec -Fix"
    if ($Fix) {
        Rrun "ip link set $Iface up"
        if ((Rget "ip link show $Iface") -match "state UP|state UNKNOWN") {
            Fixed "$Iface UP" "applied"
        } else {
            Ko "$Iface apres fix" "toujours DOWN"
        }
    }
}

$ipOut = Rget "ip addr show $Iface"
$m = [regex]::Match($ipOut, "inet (\d+\.\d+\.\d+\.\d+)")
$curIp = ""
if ($m.Success) { $curIp = $m.Groups[1].Value }

if ($curIp -eq $BoxIp) {
    Ok "IP $Iface = $BoxIp"
} else {
    Ko "IP $Iface" "$(if ($curIp) { $curIp } else { 'aucune' }) (attendu $BoxIp)"
    if ($Fix) {
        Rrun "ip addr flush dev $Iface; ip addr add $BoxIp/$Prefix dev $Iface"
        $m = [regex]::Match((Rget "ip addr show $Iface"), "inet (\d+\.\d+\.\d+\.\d+)")
        if ($m.Success -and $m.Groups[1].Value -eq $BoxIp) { Fixed "IP $Iface" "= $BoxIp" }
        else { Ko "IP apres fix" $(if ($m.Success) { $m.Groups[1].Value } else { "aucune" }) }
    }
}

$gwOut = Rget "ip route"
$m = [regex]::Match(($gwOut -join "`n"), "(?m)^default via (\d+\.\d+\.\d+\.\d+)")
$curGw = ""
if ($m.Success) { $curGw = $m.Groups[1].Value }

if ($curGw -eq $Gw) {
    Ok "passerelle = $Gw"
} else {
    Ko "passerelle" "$(if ($curGw) { $curGw } else { 'absente' }) (attendu $Gw)"
    if ($Fix) {
        Rrun "ip route del default; ip route add default via $Gw dev $Iface"
        $m = [regex]::Match((Rget "ip route" -join "`n"), "(?m)^default via (\d+\.\d+\.\d+\.\d+)")
        if ($m.Success -and $m.Groups[1].Value -eq $Gw) { Fixed "passerelle" "= $Gw" }
        else { Ko "passerelle apres fix" $(if ($m.Success) { $m.Groups[1].Value } else { "absente" }) }
    }
}

$curDns = (Rget "getprop net.dns1")
if ($curDns -eq $Dns) {
    Ok "DNS = $Dns"
} else {
    Ko "DNS" "$(if ($curDns) { $curDns } else { 'non defini' }) (attendu $Dns)"
    if ($Fix) {
        Rrun "setprop net.dns1 $Dns; setprop net.dns2 8.8.8.8"
        if ((Rget "getprop net.dns1") -eq $Dns) { Fixed "DNS" "= $Dns" }
        else { Ko "DNS apres fix" "non confirme" }
    }
}

# === [5] WIRELESS ============================================================
Write-Host ""
Write-Host "--- [5] Wireless ---"

$wifi = Rget "settings get global wifi_on"
switch ($wifi) {
    "0" { Ok "Wi-Fi coupe" }
    "1" {
        Ko "Wi-Fi" "ACTIF"
        if ($Fix) {
            Rrun "svc wifi disable; settings put global wifi_on 0"
            if ((Rget "settings get global wifi_on") -eq "0") { Fixed "Wi-Fi coupe" "applied" }
            else { Ko "Wi-Fi apres fix" "toujours actif" }
        }
    }
    default { InfoMsg "Wi-Fi : etat inconnu ($wifi)" }
}

$bt = Rget "settings get global bluetooth_on"
switch ($bt) {
    "0" { Ok "Bluetooth coupe" }
    "1" {
        Ko "Bluetooth" "ACTIF"
        if ($Fix) {
            Rrun "svc bluetooth disable; settings put global bluetooth_on 0"
            if ((Rget "settings get global bluetooth_on") -eq "0") { Fixed "Bluetooth coupe" "applied" }
            else { Ko "Bluetooth apres fix" "toujours actif" }
        }
    }
    default { InfoMsg "Bluetooth : etat inconnu ($bt)" }
}

# === [6] HORLOGE =============================================================
Write-Host ""
Write-Host "--- [6] Horloge ---"

if ($SkipDate) {
    InfoMsg "horloge : passee (-SkipDate)"
} else {
    $boxS = Rget "date +%s"
    if ($boxS -match "^\d+$") {
        $pcS   = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $drift = [Math]::Abs(([long]$boxS) - $pcS)
        if ($drift -le 300) {
            Ok "horloge (derive ${drift}s)"
        } else {
            Ko "horloge" "derive ${drift}s"
            if ($Fix) {
                $val = (Get-Date).ToUniversalTime().ToString("yyyyMMdd.HHmmss")
                Rrun "date -u -s $val"
                $boxS = Rget "date +%s"
                if ($boxS -match "^\d+$") {
                    $drift = [Math]::Abs(([long]$boxS) - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
                    if ($drift -le 300) { Fixed "horloge" "remise a l'heure UTC" }
                    else { Ko "horloge apres fix" "derive ${drift}s" }
                } else {
                    Ko "horloge apres fix" "lecture impossible"
                }
            }
        }
    } else {
        Ko "horloge" "lecture impossible"
    }
}

# === [7] HDMI (informatif) ===================================================
Write-Host ""
Write-Host "--- [7] HDMI (informatif) ---"

$blank = (Rget "cat /sys/class/graphics/fb0/blank")
switch ($blank) {
    "1"  { InfoMsg "framebuffer blank (ecran coupe, field mode)" }
    "0"  { InfoMsg "framebuffer actif" }
    ""   { InfoMsg "fb0/blank illisible" }
    default { InfoMsg "framebuffer : $blank" }
}

# === [8] OUTILS V3 ===========================================================
Write-Host ""
Write-Host "--- [8] Outils V3 ---"

$V3Tools = @("amorce", "cut_services", "system_rw", "front_led", "inspect_all")
$missing = @()
foreach ($t in $V3Tools) {
    if ((Rget "test -f /data/scripts/$t.sh && echo ok") -eq "ok") {
        Ok $t
    } else {
        $missing += $t
    }
}
if ($missing.Count -gt 0) {
    Ko "absents sur la box" (($missing -join " ") + " (maj : tools/dpk.sh install)")
}

if ((Rget "test -f /data/bin/amorce && echo ok") -eq "ok") {
    Ok "commande amorce (/data/bin)"
} else {
    InfoMsg "pas de lien /data/bin/amorce (deploy INSTALL le creera)"
}

# === RESUME ==================================================================
Write-Host ""
Write-Host "=== RESUME PROVISIONNEMENT ($DeviceName) ==="
Write-Host ("  OK/FIX : " + $script:Pass + "   KO : " + $script:KoN)
Write-Host ""

if ($script:KoN -eq 0) {
    Write-Host "OK : configuration conforme au profil"
    exit 0
}
Write-Host "KO restants : relancer avec -Fix (et -Net au besoin)"
exit 1
