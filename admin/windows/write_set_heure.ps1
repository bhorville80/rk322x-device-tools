# write_set_heure.ps1 - depose SET_HEURE (heure UTC du PC) a la racine de la cle USB
#
# La box lira ce fichier au prochain set_time AUTO / set_time FILE.
# Format : une ligne YYYYMMDD.HHMMSS (UTC).
#
# Usage:
#   powershell -File admin\windows\write_set_heure.ps1
#   powershell -File admin\windows\write_set_heure.ps1 -Path E:\
#
# Sans argument : premiere cle USB amovible detectee.

param(
    [string]$Path = ""
)

$ErrorActionPreference = "Stop"

function Die([string]$Msg) {
    Write-Host "[ERREUR SET_HEURE] $Msg" -ForegroundColor Red
    exit 1
}

if (-not $Path) {
    $Vol = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" |
        Select-Object -First 1
    if ($null -eq $Vol) { Die "aucune cle USB amovible detectee (ou passer -Path E:\)" }
    $Path = "$($Vol.DeviceID)\"
}

if (-not (Test-Path $Path)) { Die "chemin introuvable : $Path" }
$Key = Join-Path $Path "SET_HEURE"
$Now = (Get-Date).ToUniversalTime().ToString("yyyyMMdd.HHmmss")

try {
    Set-Content -LiteralPath $Key -Value $Now -NoNewline -Encoding Ascii
} catch {
    Die "ecriture impossible sur $Key"
}

Write-Host "[ OK ] $Key <- $Now (UTC)"
exit 0
