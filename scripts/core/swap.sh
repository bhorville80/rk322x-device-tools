#!/system/bin/sh
# core/swap.sh - librairie swap durcie : detection des executeurs swapon,
# fabrication EN DIRECT d'un mini-binaire syscall (ELF ARM32 emis par
# octets printf) si aucun executeur n'existe, mkswap de secours en pur dd,
# et sonde de capacite reelle du kernel.
#
# Source : mem_tune.sh (et tout outil needing swap). Aucune execution au
# chargement. Root requis pour les actions ; les fonctions sont pures sinon.
#
# Chaine de decision de swap_file_on :
#   [1] executeur existant (busybox applet / binaire systeme)
#   [2] sinon : ELF swapctl genere a la volee dans le repertoire cible
#       (__NR_swapon=167 / __NR_swapoff=168, armv7 LE, statique, ~120 octets)
#   [3] signature swap : busybox mkswap -> sinon mkswap_lite (dd+SWAPSPACE2)
#   [4] probe : fichier test 1 Mo sur LE MEME filesystem que la cible ->
#       verdict KERNEL_OK / KERNEL_REFUSE / EXEC_FABRIQUE

# ---------------------------------------------------------------- detecteurs

swap_have_pair()
{
    # un couple swapon+swapoff utilisable existe-t-il ?
    if command -v busybox > /dev/null 2>&1 \
       && busybox swapon --help 2>&1 | grep -q 'Usage' \
       && busybox swapoff --help 2>&1 | grep -q 'Usage'; then
        echo "busybox" ; return 0
    fi
    if command -v swapon > /dev/null 2>&1 && command -v swapoff > /dev/null 2>&1; then
        echo "system" ; return 0
    fi
    return 1
}

swap_on_cmd()   # $1 = chemin ; execute l'activation avec le meilleur agent
{
    P_="$1"
    if command -v busybox > /dev/null 2>&1 \
       && busybox swapon --help 2>&1 | grep -q 'Usage'; then
        busybox swapon -p "$SPRIO_" "$P_" ; return $?
    fi
    if command -v swapon > /dev/null 2>&1; then
        swapon "$P_" ; return $?
    fi
    # build en direct : ELF syscall embarquant le chemin reel, depose dans
    # /data/local/tmp (ext4 executable garanti, jamais sur la cle vfat)
    F_="/data/local/tmp/.swapctl-on"
    swap_elf_emit on "$P_" "$F_" || return 127
    "$F_"
}

swap_off_cmd()  # $1 = chemin
{
    P_="$1"
    if command -v busybox > /dev/null 2>&1 \
       && busybox swapoff --help 2>&1 | grep -q 'Usage'; then
        busybox swapoff "$P_" ; return $?
    fi
    if command -v swapoff > /dev/null 2>&1; then
        swapoff "$P_" ; return $?
    fi
    F_="/data/local/tmp/.swapctl-off"
    swap_elf_emit off "$P_" "$F_" || return 127
    "$F_"
}

# ------------------------------------------------------- emission ELF directe

swap_elf_emit()  # $1 = on|off  $2 = chemin cible reel  $3 = fichier sortant
{
    # Fabrique en direct un ELF32 ARMv7 LE statique qui fait l'appel
    # systeme brut swapon(167)/swapoff(168). Le chemin REEL est EMBARQUE :
    # le binaire n'accepte pas d'argument, il agit sur sa cible gravee.
    NUM_="$1" ; TGT_="$2" ; OUT_="$3"
    case "$NUM_" in
        on)  NB_=167 ;;
        off) NB_=168 ;;
        *)   return 1 ;;
    esac
    [ -n "$TGT_" ] || return 1

    LOW_=$((NB_ % 256))
    BYTES="16 0 143 226  0 16 160 227  $LOW_ 112 160 227  0 0 0 239  1 112 160 227  0 0 0 239"
    PB_=""
    I_=0
    while [ "$I_" -lt "${#TGT_}" ]; do
        C_="$(printf '%s' "$TGT_" | cut -c "$((I_ + 1))")"
        D_="$(printf '%d' "'$C_")"
        if [ -z "$PB_" ]; then PB_="$D_" ; else PB_="$PB_ $D_" ; fi
        I_=$((I_ + 1))
    done
    FSZ=$((84 + 24 + ${#TGT_} + 1))
    B0_=$((FSZ % 256)) ; B1_=$((FSZ / 256 % 256))
    B2_=$((FSZ / 65536 % 256)) ; B3_=$((FSZ / 16777216 % 256))

    # NOTE : pas de separateur entre les echappements - chaque sequence fait
    # exactement 3 chiffres octaux, la concatenation reste donc non ambigue.
    OCT="$(printf '\\%03o' \
        127 69 76 70 1 1 1 0 0 0 0 0 0 0 0 0 \
        2 0 40 0 1 0 0 0 \
        84 128 0 0 52 0 0 0 0 0 0 0 0 0 0 5 \
        52 0 32 0 1 0 0 0 0 0 0 0 \
        1 0 0 0 0 0 0 0 0 128 0 0 0 128 0 0 \
        $B0_ $B1_ $B2_ $B3_ $B0_ $B1_ $B2_ $B3_ 5 0 0 0 0 16 0 0 \
        $BYTES $PB_ 0)"

    printf '%b' "$OCT" > "$OUT_" 2>/dev/null || return 1
    chmod 700 "$OUT_" 2>/dev/null
    # garde portable : non-vide et taille exacte (le bit x depend du montage,
    # il sera bon sur ext4 /data cote box ; vfat ne le preserve pas toujours)
    [ -s "$OUT_" ] || return 1
    GOT_F_="$(wc -c < "$OUT_" 2>/dev/null | tr -dc '0-9')"
    [ "$GOT_F_" = "$FSZ" ] || return 1
}


# ------------------------------------------------------------- signature swap

mkswap_lite()   # $1 = fichier deja dimensionne (multiple de 4096)
{
    # repli sans applet mkswap : page zero + magie SWAPSPACE2 en fin de
    # derniere page (attendu par le kernel pour un fichier de swap ext4)
    P_="$1"
    SZ_="$(wc -c < "$P_" 2>/dev/null | tr -dc '0-9')"
    case "$SZ_" in ''|0) return 1 ;; esac
    OFF_=$((SZ_ - 10))
    printf 'SWAPSPACE2' | dd of="$P_" bs=1 seek="$OFF_" conv=notrunc > /dev/null 2>&1 \
        || return 1
    return 0
}

swap_mkswap()   # $1 = fichier ; essai busybox puis lite
{
    P_="$1"
    if command -v busybox > /dev/null 2>&1 \
       && busybox mkswap "$P_" > /dev/null 2>&1; then
        return 0
    fi
    mkswap_lite "$P_"
}

# ------------------------------------------------------- activation durcie

swap_file_on_hardened()  # $1=chemin $2=Mo $3=prio ; SPRIRO non requis ici
{
    P_="$1" ; MB_="$2" ; SPRIO_="$3"
    case "$MB_" in ''|*[!0-9]*) return 1 ;; esac
    [ "$MB_" -gt 0 ] || return 1
    SZ_WANT=$((MB_ * 1024 * 1024))
    mkdir -p "$(dirname "$P_")" 2>/dev/null
    GOT_="$(wc -c < "$P_" 2>/dev/null | tr -dc '0-9')"
    case "${GOT_:-0}" in ''|*[!0-9]*) GOT_=0 ;; esac
    if [ "$GOT_" -ne "$SZ_WANT" ]; then
        rm -f "$P_" 2>/dev/null
        dd if=/dev/zero of="$P_" bs=1048576 count="$MB_" > /dev/null 2>&1 \
            && swap_mkswap "$P_" || return 1
    else
        swap_listed_quiet "$P_" && return 0
        # taille ok mais jamais formate (ou reformat neutre)
        swap_mkswap "$P_"
    fi
    swap_on_cmd "$P_"
}

swap_listed_quiet()
{
    grep -qF "$1" /proc/swaps 2>/dev/null
}

# --------------------------------------------------------------- sonde fiable

swap_probe_capability()  # $1 = repertoire de test (meme fs que la cible)
                         # echo "KERNEL_OK|KERNEL_REFUSE|EXEC_IMPOSSIBLE"
{
    DIR_="${1:-/data/local/tmp}"
    T_="${DIR_}/.swapprobe.bin"
    SPRIO_=1
    rm -f "$T_" 2>/dev/null
    if dd if=/dev/zero of="$T_" bs=1048576 count=1 > /dev/null 2>&1 \
       && swap_mkswap "$T_"; then
        if swap_on_cmd "$T_" > /dev/null 2>&1; then
            swap_off_cmd "$T_" > /dev/null 2>&1
            rm -f "$T_" 2>/dev/null
            echo KERNEL_OK ; return 0
        fi
        rm -f "$T_" 2>/dev/null
        echo KERNEL_REFUSE ; return 0
    fi
    rm -f "$T_" 2>/dev/null
    echo EXEC_IMPOSSIBLE
}
