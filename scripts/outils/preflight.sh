#!/system/bin/sh
# preflight - verifie la disponibilite des commandes critiques AVANT le run.
#
# A executer sur la box VIERGE avant le Checkpoint A :
#   adb push scripts\preflight.sh /data/local/tmp/
#   adb shell ; su ; sh /data/local/tmp/preflight.sh
#
# Sortie : tableau OK/ABSENT par capacite + VERDICT par feature
# (multi-listeners tcpsvd, swap cle, panneau, telecommande, logs).
# Rapport sauvegarde : /data/local/tmp/preflight.txt

SCRIPT_ID="preflight"
OUT="/data/local/tmp/preflight.txt"
if ! ( : > "$OUT" ) 2>/dev/null; then
    OUT="./preflight.txt"          # repli PC / environnement sans /data
    ( : > "$OUT" ) 2>/dev/null
fi

has() { command -v "$1" > /dev/null 2>&1 && return 0 ; return 1 ; }

bb_has()
{
    # applet busybox presente ? (test d'invocation reelle)
    [ -n "$(command -v busybox)" ] || return 1
    busybox "$1" --help 2>&1 | head -n 1 | grep -qiE "$1|usage" && return 0
    return 1
}

row()
{
    S_="$1" N_="$2" C_="$3"
    printf '  [%s] %-14s %s\n' "$S_" "$N_" "$C_"
    echo "[$S_] $N_ :: $C_" >> "$OUT"
}

sec() { echo "" >> "$OUT" ; printf '\n--- %s ---\n' "$1" ; }

main()
{
    : > "$OUT" 2>/dev/null
    echo "=== PREFLIGHT - $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$OUT"

    sec "Shell et utilitaires de base"
    for C in cat ls grep sed awk wc head tail sort cut tr sleep date id ps mkdir cp mv rm ln chmod; do
        has "$C" && row OK "$C" "" || row ABSENT "$C" "impact fort - environnement anormal"
    done

    sec "BusyBox et applets critiques"
    has busybox && row OK busybox "$(busybox 2>/dev/null | sed -n 2p)" || row ABSENT busybox "critique : presque tout en depend"
    for A in nc mkfifo dd wget tar gzip sha256sum mkswap swapon swapoff find; do
        bb_has "$A" && row OK "bb:$A" "" || { has "$A" && row OK "$A" "(hors busybox)" || row ABSENT "bb:$A" ""; }
    done

    sec "Multi-listeners API 8180"
    HAS_T=""
    has tcpsvd && { row OK tcpsvd "factory listeners activee" ; HAS_T=tcpsvd ; }
    if [ -z "$HAS_T" ] && busybox tcpsvd 2>&1 | grep -q tcpsvd; then
        row OK "bb:tcpsvd" "factory listeners activee" ; HAS_T="busybox tcpsvd"
    fi
    [ -z "$HAS_T" ] && row ABSENT tcpsvd "repli automatique FIFO mono-slot (fonctionne, 1 connexion a la fois)"

    sec "Timeouts et bornes"
    has timeout && row OK timeout "bornage requetes/transferts" || row ABSENT timeout "degradation : pas de garde-fou temps"

    sec "Swap sur la cle (Checkpoint A)"
    has dd && row OK dd "" || row ABSENT dd "swap impossible"
    bb_has mkswap && row OK "bb:mkswap" "" || { has mkswap && row OK mkswap || row ABSENT mkswap "swap fichier impossible"; }
    bb_has swapon && row OK "bb:swapon" "" || { has swapon && row OK swapon || row ABSENT swapon "swap fichier impossible"; }
    # test reel de swapon fichier sera fait par mem_tune OPTIMIZE (Checkpoint A)
    echo "[INFO] verdict final swap : voir sortie de mem_tune OPTIMIZE (/proc/swaps)" >> "$OUT"

    sec "Panneau web"
    bb_has httpd && row OK "bb:httpd" "" || { has httpd && row OK httpd || row ABSENT httpd "panneau 8000 impossible"; }
    bb_has wget && row OK "bb:wget" "sondes internes recette/P7" || row ABSENT "bb:wget" "sondes degradees (netstat seul)"
    has netstat && row OK netstat "" || row ABSENT netstat "sondes via /proc/net/tcp uniquement"

    sec "Telecommande TV"
    has screencap && row OK screencap "miroir ecran" || row ABSENT screencap "pas de miroir"
    has input && row OK input "touches/TAP" || row ABSENT input "pas de touches"
    has am && row OK am "TEXT/URL plein ecran" || row ABSENT am "TEXT/URL indispo"

    sec "Logs et rapports enrichis"
    has logcat && row OK logcat "pressions lmk detectees (rampre)" || row ABSENT logcat "rampre sans compteur lmk"
    has dumpsys && row OK dumpsys "top PSS (rampre/hw_report)" || row ABSENT dumpsys "rapports moins detailles"
    has dmesg && row OK dmesg "" || row ABSENT dmesg "hw_report tronque"
    has getprop && row OK getprop "" || row ABSENT getprop "identite absente des rapports"
    has setprop && row OK setprop "DNS appliquable" || row ABSENT setprop "DNS non appliquable"

    sec "Reseau"
    has ip && row OK ip "" || row ABSENT ip "set_network degrade (ifconfig seul)"
    has ifconfig && row OK ifconfig "" || row ABSENT ifconfig ""
    has ping && row OK ping "" || row ABSENT ping ""
    has sshd || has dropbear || row "--" dropbear "optionnel (ssh_server)"

    # --- verdict ---
    {
      echo ""
      echo "=== VERDICTS ==="
    } >> "$OUT"
    printf '\n'
    printf '%s\n' "--- VERDICTS ---"
    if [ -n "$HAS_T" ]; then
        echo "  MULTI-LISTENERS : OUI ($HAS_T) - jusqu'a API_MAX_CONN connexions"
        echo "  [VERDICT] tcpsvd=OK" >> "$OUT"
    else
        echo "  MULTI-LISTENERS : NON - repli FIFO mono-slot (fonctionnel)"
        echo "  [VERDICT] tcpsvd=FALLBACK_FIFO" >> "$OUT"
    fi
    if bb_has mkswap && bb_has swapon; then
        echo "  SWAP CLE        : A TESTER au Checkpoint A (applets presents)"
        echo "  [VERDICT] swap=A_TESTER" >> "$OUT"
    else
        echo "  SWAP CLE        : IMPOSSIBLE (applets manquants) -> plan B SD type 82"
        echo "  [VERDICT] swap=IMPOSSIBLE" >> "$OUT"
    fi
    echo "  PANNEAU/TELECOM : voir sections ci-dessus (httpd+screencap+input requis)"
    echo ""
    echo "[ OK ] rapport -> $OUT"
    echo "       renvoyer ce fichier pour analyse avant le Checkpoint A."
}

main
exit 0
