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
  VERSION      Version installee vs cle (diagnostic mise a jour)
  STATUS       Etat du deploiement : outils presents, liens bin,
               backups, manifest, version vs cle, serveurs actifs
               (validation automatique a la fin de chaque INSTALL :
               sh -n sur chaque script + liens, tracee dans VERSION)
  CLEAN [DRY]  Assainissement : garde 3 backups + 10 manifests,
               purge staging dpk/tmp residuels et tombstones,
               rotation logs exec ; DRY = simulation seule
  HELP         Aide rapide deploy

AMORCE (demarrage rapide, apres le premier INSTALL)
  amorce             Etat cle/versions + rappel des commandes
  amorce INSTALL     Met a jour depuis la cle
  amorce EXPOSE      Serveurs HTTP/GUI sur la cle
  amorce SELFTEST    Verifie tous les outils
  1ere fois          voir le fichier AMORCE a la racine de la cle
                     (su -c 'sh /mnt/media_rw/*/deploy.sh INSTALL')

VERIFICATION
  check_state        Etat IP / wireless / bluetooth / HDMI
                      compare a la config cible
                      exit 1 si au moins un KO
  conf_check         Validation config/device.conf (+ overlay
                      profiles/<PROFILE>.conf, secrets.conf) :
                      cles requises, formats IP/prefix/ports,
                      valeurs autorisees ; etat d'application
                      des optimisations memoire (lance/pas lance)
                      ; exit 1 si invalide
  run_state          Etat de lancement des outils via log/exec :
                      lances (nb, dernier, rc), installes jamais
                      lances, executions en echec
  selftest           Verifie que tous les outils repondent

INSPECTION
  inspect_all        Rapport global : lance TOUS les inspect_* +
                     check_state + thermal + cut_services/front_led
                     STATUS, synthese rc par outil en fin de rapport
  inspect_user       Methodes de creation utilisateur dispo
                      (pm create-user, cmd user, busybox...)
                      option : nom d'utilisateur exemple
  device_info        Inventaire puces / materiel trie par fonctionnalite
                      (SOC/CPU, RAM, GPU, stockage, reseau, wireless,
                      USB, audio, HDMI, entrees/IR, alim/RTC, thermique)
                      + services init rattaches a chaque fonction
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
  disable_wireless   Coupe Wi-Fi/BT (persistant au reboot) + verifie
                     STATUS : etat des radios ; ON : restauration
                     option WIRELESS_AIRPLANE=1 (device.conf)
  media              Liste medias montes (USB/SD) et types
   field_mode OFF     Mode exploitation sans ecran : wireless + HDMI
                      + serveurs + services de SERVICES_STOP
                      (config/device.conf)
   field_mode ON      Retour ecran + redemarre les services surveilles
   field_mode STATUS  Etat HDMI / wireless / services

ALLEGEMENT (24/7)
  cut_services STATUS Inventaire services init + paquets usine,
                      candidats [CUT]/[safe]/[opt], RAM dispo
  cut_services CUT    Coupe la liste SAFE : services (perfprofd,
                      bootanim, cameraserver, debuggerd, console)
                      + paquets usine (stresstest, devicetest, OTA,
                      katniss), mesure le gain RAM
  cut_services CUT FULL   Phase 2 : ajoute les services media/audio
                      (serveur de fichiers pur, aucune lecture locale)
  cut_services APPS   Preset finalite serveur : GMS/Play/katniss/
                      DLNA/mediacenter/changeled/tests/OTA desactives
                      (launcher/UI/clavier/apps perso conserves)
  cut_services APPS MAX   Phase 2 extreme : coupe aussi l'interface TV
                      (headless total jusqu'a RESTORE/reboot)
   cut_services RESTORE  Remet l'etat d'origine
                       Personnalisation : SERVICES_CUT / PACKAGES_DISABLE
                       dans config/device.conf
   mem_tune STATUS    Memoire : zram/swap, swappiness, lmk minfree,
                       buffers logd, profil cible
   mem_tune OPTIMIZE  Profil optimise : zram (si kernel expose),
                       swappiness adapte, kills plus tot (option),
                       buffers logd reduits ; ORIGINE sauvegardee
   mem_tune RESTORE   Remet les valeurs d'origine
                       Pilotage : MEM_ZRAM_MB / MEM_SWAPPINESS /
                       MEM_LMK_EARLY / LOGD_SIZE_KB (device.conf)

SYSTEME
  system_rw STATUS   Etat du montage /system (device/type/options)
  system_rw RW       Passe /system en lecture-ecriture (probe incluse)
                     requis avant : edition .kl (inspect_remote),
                     bootanimation, fichiers systeme
  system_rw RO       Retour lecture-seule (defaut au reboot)

AFFICHEUR FRONTAL
  front_led STATUS   Leds sysfs + noeud fd655 + daemon FD655_Demo
  front_led LED <n> <v>     luminosite (ex : front_led LED green 255)
  front_led TRIGGER <n> <t> heartbeat / timer / none...
  front_led BLINK <n> <on> <off>  clignotement ms (trigger timer)
  front_led ON|OFF   toutes les leds au max / a zero
  front_led DEMO STOP  arrete l'horloge FD655_Demo (reboot la relance)

ACCES / ACCUEIL
  motd STATUS        Message affiche a l'ouverture d'un adb shell
                     (equivalent MOTD ssh)
  motd DEFAULT       Genere la banniere (device/ip/outils)
  motd SET <texte>   Definit le message (ou : motd FILE <fichier>)
  motd ON|OFF        Pose/retire le crochet dans /system/etc/mkshrc
                     (remount rw/ro automatique via system_rw)

RESEAU / DIAGNOSTIC
  net_diag           Diagnostic complet : lien (vitesse/duplex),
                     adresses auto-detectees, routes, DNS,
                     ping passerelle + internet, resume ok/ko/warn
  net_diag PORTS     Services en ecoute (8000 cle, 8080 API,
                     8081 GUI, 5555 adb, 2222 ssh...)
  net_diag PING <h>  Latence detaillee vers un hote
  net_diag THROUGHPUT <ip>   Debit sortant dd->nc (receveur requis)
  sys_diag           Sante systeme : horloge (retour 1970),
                     memoire/lmkd, entropie, ecriture eMMC,
                     securite (adb/token/ssh/wireless)
  vitals             Signes vitaux : temperatures, CPU/governor/
                     charge, RAM, usure eMMC + remplissage /data,
                     lien reseau, alimentation
  vitals WATCH [N] [S]   N releves toutes les S s (defaut 10x5)
                     -> suivre une montee en temperature
  vitals CSV         ligne machine pour collecte PC
                     (admin/*/vitals_history)
  set_network.sh     Config statique eth0 (IP/route/DNS) depuis
                     config/device.conf

MAINTENANCE
  sync_usb           Synchronise /data/scripts -> cle USB
                     + validation post-copie (cmp octet a octet)
  sync_usb STATUS    Compare sans copier : identiques/divergents
  add_to_bin <s>     Ajoute un script dans /data/bin
  add_script_to_usb  Copie un fichier vers la racine cle

RESEAU / HEURE   (commande apres INSTALL)
  set_time STATUS    Heure actuelle + sources disponibles (verdict)
  set_time AUTO      Defaut, ordre : INIT (valeur codee) -> FILE
                     (SET_HEURE sur la cle) -> adb (poussee PC)
  set_time FILE      Force la lecture de SET_HEURE sur la cle
  set_time RTC       Force l'heure depuis l'horloge materielle
  set_time INIT      Valeur codee de secours
  set_time SET <v>   Applique une valeur passee par le PC
                     (adb / provision --fix / panneau web)
                     formats : YYYYMMDD.HHMMSS ou MMDDhhmmCCYY.ss

SERVEURS   (dossier server/ de la cle)
  start_server.sh    HTTP port 8000 servant la cle
  control_server.sh  API port 8080 (HELP/SEND_LOGS/PURGE_LOG/SYNC)
                      + watch_usb.sh execute les fichiers temoins
                      poses dans incoming/
  ssh_server.sh      SSH via dropbear port 2222 (binaire a deposer,
                      cf. ssh_server STATUS) ; OPTIONNEL, jamais lance
                      automatiquement : l'acces de reference reste adb
                      arret inclus dans deploy STOP (server/ssh.pid)
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
