#!/system/bin/sh
# capture - captures reseau (pcap) via tcpdump, sans installation.
#
# Le binaire tcpdump n'est PAS fourni (meme principe que ssh_server) :
# deposer un tcpdump statique arm32 sur la cle (server/tcpdump) ou la box
# (/data/local/tmp/tcpdump). Le script le copie hors de la cle (montee
# noexec) avant execution.
#
#   capture STATUS            binaire trouve ? captures existantes
#   capture START [s] [filt]  enregistre s secondes (defaut 60, filtre bpf)
#   capture LIST              liste des .pcap sur la cle
#   capture CLEAN             supprime les captures
#
# Analyse : ouvrir les .pcap dans Wireshark cote PC.

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

command -v is_root >/dev/null 2>&1 || is_root() { case "$(id -u 2>/dev/null)" in 0) return 0 ;; esac; case "$(id 2>/dev/null)" in "uid=0("*) return 0 ;; esac; return 1; }

TOOL_DIR="/data/local/tmp/.nettools"

key_dir()
{
    for d in /mnt/media_rw/*; do
        [ -f "$d/deploy.sh" ] && { printf '%s' "$d"; return 0; }
    done
    return 1
}

cap_dir()
{
    KEY_="$(key_dir)"
    if [ -n "$KEY_" ]; then
        mkdir -p "$KEY_/log/captures" 2>/dev/null
        printf '%s/log/captures' "$KEY_"
    else
        mkdir -p /data/local/tmp/captures 2>/dev/null
        printf '%s' "/data/local/tmp/captures"
    fi
}

find_bin()
{
    NAME="$1"
    for C in \
        "$(key_dir)/server/$NAME" \
        "/data/local/tmp/$NAME" \
        "$TOOL_DIR/$NAME" \
        "/system/xbin/$NAME" "/system/bin/$NAME" ; do
        [ -x "$C" ] && { printf '%s' "$C"; return 0; }
        # sur cle vfat : present mais non executable (noexec)
        if [ -f "$C" ]; then
            printf 'NEEDEXEC %s' "$C"
            return 0
        fi
    done
    return 1
}

ensure_exec()
{
    SRC="$1"
    case "$SRC" in
        $TOOL_DIR/*|/system/*) printf '%s' "$SRC"; return 0 ;;
    esac
    mkdir -p "$TOOL_DIR" 2>/dev/null || return 1
    cp -f "$SRC" "$TOOL_DIR/$(basename "$SRC")" 2>/dev/null || return 1
    chmod 755 "$TOOL_DIR/$(basename "$SRC")" 2>/dev/null
    printf '%s' "$TOOL_DIR/$(basename "$SRC")"
}

do_status()
{
    echo ""
    echo "=== CAPTURE STATUS ==="
    for N in tcpdump ngrep; do
        F="$(find_bin "$N")"
        case "$F" in
            "")         printf '  %-8s : absent (deposer sur server/%s de la cle)\n' "$N" "$N" ;;
            NEEDEXEC*)  printf '  %-8s : present sur la cle (%s)\n' "$N" "${F#NEEDEXEC }" ;;
            *)          printf '  %-8s : %s\n' "$N" "$F" ;;
        esac
    done
    NB="$(ls -1 "$(cap_dir)"/*.pcap 2>/dev/null | grep -c .)"
    echo "  captures  : $NB fichier(s) dans $(cap_dir)"
    echo ""
    return 0
}

do_start()
{
    SECS="${1:-60}"
    FILTER="$2"
    case "$SECS" in ''|*[!0-9]*) SECS=60 ;; esac

    F="$(find_bin tcpdump)"
    case "$F" in
        "") echo "[ERREUR] tcpdump introuvable."
            echo "         obtenir un tcpdump statique arm32 et le poser ici :"
            echo "           <cle>/server/tcpdump   ou   /data/local/tmp/tcpdump"
            echo "         puis relancer : capture START"
            return 1 ;;
        NEEDEXEC*) F="$(ensure_exec "${F#NEEDEXEC }")" || { echo "[ERREUR] copie impossible vers $TOOL_DIR"; return 1; } ;;
    esac

    is_root || { echo "[ERREUR] privileges root requis : su -c \"sh $0 START\""; return 1; }

    OUT="$(cap_dir)/cap_$(date '+%Y%m%d-%H%M%S').pcap"
    IFACE="eth0"
    ip link show eth0 > /dev/null 2>&1 || IFACE="any"

    echo "[*] capture ${SECS}s sur $IFACE${FILTER:+ (filtre: $FILTER)}..."
    if [ -n "$FILTER" ]; then
        timeout "$SECS" "$F" -i "$IFACE" -s 96 -C 20 -W 4 -w "$OUT" "$FILTER" > /dev/null 2>&1
    else
        timeout "$SECS" "$F" -i "$IFACE" -s 96 -C 20 -W 4 -w "$OUT" > /dev/null 2>&1
    fi

    SZ="$(du -h "$OUT" 2>/dev/null | cut -f1)"
    if [ -s "$OUT" ]; then
        echo "[ OK ] capture -> $(basename "$OUT") ($SZ)"
        echo "       analyse cote PC : Wireshark"
    else
        rm -f "$OUT"
        echo "[ ERREUR ] capture vide (binaire incompatible ? essayer iface 'any')"
        return 1
    fi
    return 0
}

do_list()
{
    D="$(cap_dir)"
    echo ""
    echo "=== CAPTURES ($D) ==="
    if [ "$(ls -1 "$D"/*.pcap* 2>/dev/null | grep -c .)" = "0" ]; then
        echo "  (aucune)"
    else
        ls -l "$D"/*.pcap* 2>/dev/null | tail -n +2 | while read -r P L O G SZ M D2 T F; do
            [ -n "${F:-}" ] && printf '  %-22s %6s\n' "$F" "$SZ"
        done
    fi
    echo ""
    return 0
}

do_clean()
{
    D="$(cap_dir)"
    N=0
    for F in "$D"/*.pcap*; do
        [ -f "$F" ] || continue
        rm -f "$F" && N=$((N+1))
    done
    echo "[ OK ] $N capture(s) supprimee(s)"
    return 0
}

case "$1" in
    ""|STATUS|status) do_status ;;
    START|start)      shift; do_start "$@" ;;
    LIST|list)        shift; do_list "$@" ;;
    CLEAN|clean)      do_clean ;;
    HELP|help|-h|--help)
        echo ""
        echo "Usage: capture <STATUS|START [s] [filtre_bpf]|LIST|CLEAN>"
        echo ""
        echo "  START 60                capture 60 s tout le trafic"
        echo "  START 120 \"port 8080\"   avec filtre bpf"
        echo "  Binaire tcpdump statique arm32 a deposer (pas fourni), cf. STATUS"
        echo ""
        ;;
    *) echo "Usage: capture <STATUS|START [s] [filtre]|LIST|CLEAN>" ;;
esac
