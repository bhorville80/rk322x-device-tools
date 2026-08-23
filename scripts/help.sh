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
  boot INSTALL       Persiste optimisations au boot (hook init rc,
                     repli install-recovery) ; boot TEST/STATUS/REMOVE
  boot (sans arg)    Execute les actions BOOT_* du device.conf
  reboot [s]         Redemarre (immediat ou dans N s, CANCEL pour annuler)
  reboot RECOVERY    Recovery / BOOTLOADER : fastboot
  remote_map STATUS  Telecommande IR : device cible + layout + remaps actifs
  remote_map DEVICES Liste devices input -> layout .kl attendu
  remote_map LEARN   Capte les appuis IR et propose les commandes MAP
  remote_map MAP     Remap touches (ex: MAP 102=HOME) ; RESET = origine
                      (effectif au reboot ; backup auto au premier MAP)
  investigate DISPLAY Enquete afficheur : qui ecrit sur /dev/fd655_dev,
                      lecture brute, strace daemon, traces kernel/init
  investigate REMOTE Enquete telecommande : noyau IR, getevent, layouts
  investigate ALL    Rapport complet sauvegarde sur la cle
  stress_ram [mo]    Test de provocation RAM avec surveillance : remplissage
                     tmpfs par paliers, tenue, relachement ; detecte les
                     kills lmkd/oom et la recuperation (rapport sur cle)
  net_watch STATUS   Surveillance reseau zero-dependance : etats de
                     connexions, top IP, alertes scan/bruteforce
  net_watch DAEMON   Echantillonnage continu (csv + evenements sur cle)
  net_watch LOGSCAN  IP agressives dans les logs serveurs -> BAN suggere
  net_watch BAN ip   Blocage iptables (UNBAN / BANS pour la liste)
  capture START      Capture pcap via tcpdump si depose (server/tcpdump),
                      analyse Wireshark cote PC ; cf. capture STATUS
  crowdsec STATUS    IDS comportemental : verdict natif/proot + guide
  front_led DEMO ON  Relance l'horloge frontale (STOP : arret)
  front_digit PROBE  Identifie le format de trame du display FD655 (1 fois)
  front_digit SHOW   Affiche un texte 7-seg (ex: SHOW "12.34")
  front_digit CLOCK  Horloge custom HH.MM (remplace le daemon usine)
  front_digit ROTATE Rotation toutes les N s (TIME IP RAM UP) ; STOP
                     BOOT_FRONT_CLOCK=1 -> horloge auto au boot
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
  recette            Recette complete en une commande : install,
                      selftest, conf_check, mem_tune OPTIMIZE,
                      inspect_all, run_state, expose verifie,
                      SEND_LOGS puis "CLE PRETE POUR ANALYSE
                      RETOUR" ; bilan : log/recette_last.txt
                      Phases separees possibles : recette P1..P7
                      ou RETOUR (etat par phase dans
                      log/recette_phases.txt, boutons IHM)
                      Sections thematiques : recette CONFIG
                      (P3+P4) / recette DIAG (P5+P6)
                      Liste complete : recette HELP
  nreg               Non-regression executable (cf.
                      docs/NON-REG.md) : 10 themes verifies
                      (deploiement, outils, configuration,
                      memoire, boot, reseau, wifi, diagnostic,
                      sd, traces) avec bilan PASS/FAIL
                      Un seul theme : nreg 4 | nreg mem |
                      nreg wifi ; liste : nreg HELP
  config             Configuration interactive : toute la
                      config en une page numerotee puis
                      modification par numero (validation
                      par type) ; scripts : config GET/SET ;
                      validation : config CHECK
  manage             Etat & gestion centralises :
                      manage = apercu services+web+ports,
                      manage service [wifi-off|ssh-...],
                      manage web [expose|stop|restart|
                      token-status], manage ports
  selftest           Verifie que tous les outils repondent
  menu               Dispatcher par sujet : install recette optim
                       inspect diag logs serveur cle
                       menu <sujet> = aide + actions
                       menu <sujet> <action> = lancement
                       ex : menu optim mem / menu recette tout /
                       menu inspect all / menu serveur expose

INSPECTION
  inspect_all        Rapport standard : coeur de verification
                      (check_state, inspect_system, device_info,
                      inspect_services, thermal, net_diag,
                      sys_diag, sd_inspect, cut_services,
                      front_led) + synthese rc par outil
                      Les analyses one-shot (inspect_gui/display/
                      remote/user) sont EXCLUES du standard :
                      inspect_all LIST = classification avec
                      raison/attentes ; inspect_all FORCE =
                      tout apres presentation et confirmation
                      (FORCE YES = sans question, scripts)
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

CARTE SD
  sd_boot STATUS     Carte enumeree ? montee ? config (BOOT_SD_LAST...)
  sd_boot CHECK      Attente enumeration + montage tardif ; lance
                     automatiquement en FIN de boot si BOOT_SD_LAST=1
                     (une carte problematique ne bloque plus le demarrage)
  sd_boot MOUNT [ro|rw]   Montage manuel sur /mnt/media_rw/sdcard1
  sd_boot UNMOUNT    Demontage propre
  sd_inspect         Diagnostic complet : enumeration mmc, montage/vold,
                     pstore du boot precedent (DMESG = noyau live)

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
  motd DEFAULT       Genere la banniere (panneau/ports/ip/ram/boot)
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
              deploy TOKEN ON|OFF|<valeur>|STATUS (ON = aleatoire)

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
