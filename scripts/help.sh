#!/system/bin/sh

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

main()
{
cat << 'EOF'

==========================================================
              RK322X DEVICE TOOLS - AIDE
==========================================================

DEPLOIEMENT   (depuis la cle : sh /mnt/media_rw/<ID>/deploy.sh <cmd>)
  INSTALL      Installe les scripts de la cle sur la box
               (/data/scripts + liens /data/bin)
               avec sauvegarde auto de l'existant
  PKG [f]      Installe depuis un paquet .dpk (tar.gz)
               a la racine de la cle, ou chemin fourni
  RESTORE      Restaure la derniere installation sauvegardee
  EXPOSE       Expose le contenu de la cle en HTTP port 8000
  STOP         Arrete les serveurs HTTP actifs
  SEND_LOGS    Collecte logcat/dmesg/getprop/ip/mount/ps
               dans log/log_<TS>/ sur la cle
  HELP         Aide rapide deploy

VERIFICATION
  check_state        Etat IP / wireless / bluetooth / HDMI
                     compare a la config cible
                     exit 1 si au moins un KO
  selftest           Verifie que tous les outils repondent

INSPECTION
  inspect_user       Methodes de creation utilisateur dispo
                     (pm create-user, cmd user, busybox...)
                     option : nom d'utilisateur exemple
  inspect_system     Rapport materiel : RAM, CPU freq/governor,
                     GPU Mali, temperatures, stockage,
                     affichage/HDMI, charge, top RAM
  inspect_services   Services init (running/stopped), packages
                     systeme/tiers/desactives, top RAM,
                     cout SurfaceFlinger
  inspect_display    Afficheur digital frontal : leds sysfs,
                     noeuds /dev, drivers fd65x/tm16x, daemons,
                     moyens de modification
  inspect_remote     Telecommande IR : recepteur input, layouts
                     .kl (scancode->keycode), droits /system,
                     procedure de remap

ACTIONS
  hdmi OFF           Coupe sortie HDMI + blank framebuffer
  hdmi ON            Reactive la sortie HDMI
  hdmi STATUS        Etat noeuds sysfs display
  disable_wireless   Coupe Wi-Fi, Bluetooth, wlan0/p2p0/hci0
  media              Liste medias montes (USB/SD) et types
  field_mode OFF     Mode exploitation sans ecran : wireless + HDMI
                     + serveurs + services de SERVICES_STOP
                     (config/device.conf)
  field_mode ON      Retour ecran + redemarre les services surveilles
  field_mode STATUS  Etat HDMI / wireless / services

MAINTENANCE
  sync_usb           Synchronise /data/scripts -> cle USB
  add_to_bin <s>     Ajoute un script dans /data/bin
  add_script_to_usb  Copie un fichier vers la racine cle

RESEAU / HEURE   (racine de la cle)
  set_network.sh     Config statique eth0 (IP/route/DNS)
  setHEURE_FILE.sh   Heure depuis fichier SET_HEURE sur la cle
  setHEURE_INIT.sh   Heure fixe codee dans le script

SERVEURS   (dossier server/ de la cle)
  start_server.sh    HTTP port 8000 servant la cle
  control_server.sh  API port 8080 (HELP/SEND_LOGS/PURGE_LOG/SYNC)
                     + watch_usb.sh execute les fichiers temoins
                     poses dans incoming/
  Securite : si server/token existe, l'API exige ?token=<valeur>

LOGS
  Chaque outil ecrit : log/exec/<script>_<YYYYmmdd-HHMMSS>.log
  Collecte globale   : deploy SEND_LOGS -> log/log_<TS>/
  Serveurs           : log/control_server.log, http_server.log

PACKAGING
  Cote PC    : tools/pack.sh construit dist/rk322x-tools_v<ver>_<TS>.dpk
                (+ .sha256), archive tar.gz du toolkit complet
  Cote PC    : tools/dpk.sh build|list|latest|verify|push|install
                push/install = adb vers la box (-t ip:5555 ou DPK_TARGET)
  Cote box   : deploy PKG [fichier.dpk]
                extraction + installation traquee comme INSTALL
  show_key     Liste les paquets .dpk de la cle, marque celui
                que deploy PKG prendra, compare a la version
                installee, etat incoming/logs/manifests
  Le .dpk se pose simplement a la racine de la cle
  Doc complete : PACKAGING.md a la racine du depot

EXEMPLES D'USAGE SUR SITE
  adb shell                 puis su
  deploy INSTALL            installe les outils
  check_state               verifie l'etat cible
  inspect_services          inventaire avant tri
  hdmi OFF                  libere l'affichage
  disable_wireless          coupe radio
  deploy EXPOSE             sert la cle sur reseau

==========================================================

EOF
    return 0
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main >> "$RUNLOG_FILE" 2>&1
    RC=$?
    runlog_end "$RC"
    cat "$RUNLOG_FILE"
else
    main
    RC=$?
fi

exit "$RC"
