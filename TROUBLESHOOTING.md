# Troubleshooting

> Known issues, diagnostics and solutions for `rk322x-device-tools`.

This document contains problems encountered during development, deployment and administration of RK322x-based Android devices.

When a new issue is identified, document it here together with the observed behavior, diagnosis and solution.

---

## ADB

### ADB device not detected

Check whether the device is visible:

```bash
adb devices
```

If the device does not appear:

1. Check the USB connection.
2. Check that Android debugging is enabled.
3. Restart the ADB server:

```bash
adb kill-server
adb start-server
```

Then check again:

```bash
adb devices
```

---

## ROOT

### `su` does not provide root access

Check:

```bash
adb shell
```

Then:

```bash
su
```

Verify the current user:

```bash
id
```

A successful root shell should report:

```text
uid=0(root)
```

Under `su`, both **uid and gid are 0**: `uid=0(root) gid=0(root) groups=...`.

### Root detected as missing even under `su` (`privileges root requis`)

**Observed:** after `su -c "sh deploy.sh INSTALL"`, the script still reports
`[ERREUR] privileges root requis`, although plain `id` shows `uid=0(root) gid=0(root)`.

**Diagnosis:** old Android toolbox builds (common on RK322x boxes, Android 4.4/5.1)
do not support the `-u` option: `id -u` fails and outputs nothing, so any
`[ "$(id -u)" != "0" ]` test evaluates as "not root".

**Solution (applied in the codebase):** every root check now uses a robust
`is_root()` helper that first tries `id -u`, then falls back to parsing the
raw `id` output:

```sh
is_root()
{
    case "$(id -u 2>/dev/null)" in
        0) return 0 ;;
    esac
    case "$(id 2>/dev/null)" in
        "uid=0("*) return 0 ;;
    esac
    return 1
}
```

If a very old copy of the scripts is still installed on the box
(`/data/scripts/core/config.sh` without `is_root`), re-run INSTALL from an
up-to-date key/package.

If root access is unavailable, check the device image and root configuration.

---

## DATE / TIME

### `date` returns a permission error

The system date requires root privileges.

Use:

```bash
su
```

Then:

```bash
date
```

Or execute the command directly as root:

```bash
su -c 'date 080820262026.00'
```

---

## NETWORK

### Ethernet interface has no expected IP

Check the interface:

```bash
ip addr show eth0
```

Also check all interfaces:

```bash
ip addr
```

Expected configuration:

```text
192.168.50.20
```

Check the interface state:

```bash
ip link show eth0
```

---

### Cannot access the HTTP server

First verify that the server is running:

```bash
ps | grep httpd
```

Start it manually:

```bash
busybox httpd -f -p 0.0.0.0:8000 \
    -h /mnt/media_rw/4E28-7C59
```

If root privileges are required:

```bash
su -c 'busybox httpd -f -p 0.0.0.0:8000 -h /mnt/media_rw/4E28-7C59'
```

From another machine, test:

```text
http://192.168.50.20:8000/
```

---

## USB

### USB storage is not available

Check mounted filesystems:

```bash
mount
```

Check the media directory:

```bash
ls -la /mnt/media_rw/
```

Expected USB path:

```text
/mnt/media_rw/4E28-7C59
```

Verify that the directory exists:

```bash
ls -la /mnt/media_rw/4E28-7C59
```

---

### USB synchronization fails

Run the synchronization script manually:

```bash
/data/bin/sync_usb
```

Check the generated logs:

```text
/mnt/media_rw/4E28-7C59/log/
```

Also verify that the USB drive has sufficient free space.

---

## WIFI / BLUETOOTH

### Wi-Fi or Bluetooth is still active

Run:

```bash
/data/bin/disable_wireless
```

Then check interfaces:

```bash
ip link
```

Look for:

```text
wlan0
p2p0
hci0
```

Check related processes:

```bash
ps | grep -iE 'bluetooth|wpa|wifi'
```

---

## DEPLOYMENT

### `deploy.sh` does not execute

Check that the file exists:

```bash
ls -la /mnt/media_rw/4E28-7C59/deploy.sh
```

Run the help command:

```bash
sh /mnt/media_rw/4E28-7C59/deploy.sh HELP
```

If the script depends on other files, verify that the complete USB directory structure is present.

---

### `tmp-mksh: ... No such file or directory` / `syntax error: 'do' unexpected`

Signature of **CRLF line endings** (Windows) corrupting the shebang:
the kernel tries to execute `/system/bin/sh\r`, which does not exist.

* Fixed permanently: `.gitattributes` forces LF (`eol=lf`) for everything
  deployed to the box; `tools/pack.sh` refuses a build containing `\r`;
  the pre-commit hook converts CRLF->LF automatically.
* If an old copy still shows the symptom: rebuild the key/package from
  a clean checkout and re-run INSTALL.

Reminder: `/mnt/media_rw/*` is mounted **noexec** - always run scripts
via `sh <path>`, never `./script` (Permission denied is expected there).

---

### Deployment logs are missing

Check:

```bash
ls -la /mnt/media_rw/4E28-7C59/log/
```

Then collect logs:

```bash
sh /mnt/media_rw/4E28-7C59/deploy.sh SEND_LOGS
```

Verify that the USB storage is writable.

---

## SCRIPT EXECUTION

### Script returns `Permission denied`

Check permissions:

```bash
ls -la /data/bin/
```

Try executing the script through the shell:

```bash
sh /data/bin/<script>
```

If the script is stored on the USB drive:

```bash
sh /mnt/media_rw/4E28-7C59/<script>
```

---

## DIAGNOSTIC COMMANDS

### Device information

```bash
getprop
```

### Current user

```bash
id
```

### Network

```bash
ip addr
```

```bash
ip link
```

### Processes

```bash
ps
```

### Mounted filesystems

```bash
mount
```

### Storage

```bash
df -h
```

### Current date

```bash
date
```

---

## SD CARD / BOOT BLOCKED

### Box does not boot when the SD card is inserted at power-on

**Symptômes observés :**

```text
LED rouge figée, logo bloqué, ou boot très long avec carte SD insérée.
Sans la carte : la box démarre normalement sur l'eMMC (Android).
```

**Causes connues sur RK322x :**

1. Le BootROM/loader essaie de démarrer sur la SD avant l'eMMC
   (carte avec signature de boot, MBR exotique, ou ordre de boot du loader).
2. Le driver mmc des noyaux 3.10/4.4 se bloque sur certaines cartes
   (SDXC / UHS-I rapides) pendant l'énumération.
3. Android (vold) voit la carte mais ne la monte jamais
   (stockage adopté résiduel, format non supporté).

**Procédure d'investigation :**

```bash
# 0) après un boot bloqué puis redémarré SANS la carte :
deploy SEND_LOGS          # capture pstore/last_kmsg + logs sur la clé
admin/*/logpull           # récupération vers le PC sans débrancher la clé

# 1) état actuel (avec carte insérée à chaud si possible) :
sd_inspect                # enumeration mmc, montage/vold, traces pstore
sd_inspect DMESG          # messages noyau live mmc/sdhci
```

Interprétation :

```text
Carte absente de l'énumération + blocage au logo  -> stade loader (cause 1)
Erreurs timeout/crc dans le pstore                -> driver/carte (cause 2)
Carte vue par le noyau mais rien de monté         -> vold/format (cause 3)
```

**Contournements / solutions :**

| Cause | Solution |
|---|---|
| Loader | Formater la carte en **FAT32, MBR, une seule partition primaire, sans flag boot** ; sinon reflasher le loader via RKDevTool (PC, câble OTG, point reset) |
| Driver/carte | Essayer une autre carte : SDHC plutôt que SDXC, classe 10 sans UHS, marque connue |
| vold/format | Format portable FAT32 (pas de "stockage interne") ; vérifier `sd_inspect` section adoption |

**Objectif :** pouvoir laisser la carte insérée au démarrage et l'utiliser comme stockage. La voie logicielle dépend de la cause identifiée par `sd_inspect` ; documenter ici le résultat obtenu.

### Examen de la carte EN DERNIER au boot (v17+)

`BOOT_SD_LAST=1` (défaut) fait traiter la carte **après la fin complète du
boot** : le hook lance `sd_boot CHECK` en toute dernière étape (après réseau,
serveurs, mem_tune). Une carte lente ou capricieuse ne retarde plus le
démarrage, et une carte vue par le noyau mais non montée est montée
tardivement sur `/mnt/media_rw/sdcard1` (lecture seule si `SD_MOUNT_RO=1`,
attente d'énumération `SD_WAIT_SEC`, défaut 15 s).

```bash
sd_boot STATUS        # carte vue ? montée ? config active
sd_boot MOUNT rw      # montage manuel si besoin
```

Limite : cela n'agit qu'**après init**. Un blocage au stade loader/driver
(logo figé) reste du ressource matériel : format FAT32/MBR sans flag boot,
ou carte SDHC sans UHS.

---

## WEB PANEL

### Every button shows `Erreur : TypeError: Failed to fetch`

Two independent causes, both fixed in v17+:

1. **Response never sent back** (root cause): the API servers used
   `nc -l > request_file` then printed the reply AFTER `nc` had already
   exited - the response went to the log, the browser got an empty
   connection after ~30 s and every click failed. Fixed by piping the
   handler INTO `nc` (`{ wait for request ; handle } | nc -l ...`), so the
   reply really travels on the socket while the connection is open.
2. **CORS**: panel is served on :8000 while the API listens on 8080/8081 -
   different origins. Without `Access-Control-Allow-Origin: *` the browser
   blocks the response and `fetch()` rejects.

After updating, restart the servers:

```bash
deploy STOP && deploy EXPOSE
```

Panel side hardening (same version): 20 s timeout per call, one automatic
retry (the single-slot servers can refuse a connection while busy), and an
explicit error message pointing at the port badges.

### Buttons answer `{"status":"error","message":"forbidden"}` (403)

A `server/token` file exists on the key: every API call requires
`?token=<value>`. The panel prompts for it once on the first 403 and keeps
it in localStorage. To remove the protection, delete `server/token`.

To create the protection (it does not exist by default):

```bash
deploy TOKEN ON              # random value, printed once
# or: deploy TOKEN MonSecret123
deploy STOP && deploy EXPOSE
```

`deploy TOKEN STATUS` shows the current state, `deploy TOKEN OFF`
removes it. The value is read from the key by `control_server.sh`
(8080) and `gui_server.sh` (8081) at each request; alphanumerics only.

### Port badges under the page title

Every panel page shows three badges (`8000 HTTP / 8080 API / 8081 GUI`):

- green `OK`: port answers;
- orange `UP - token requis`: server reachable, 403 answered (token
  missing or wrong in this browser);
- red `INJOIGNABLE (arrete ou bloque)`: TCP connection failed.

### Panel loads but every fetch fails / nothing loads at all

The Android box installs no firewall rules itself. If a port is closed
from your PC, the block is on the path between the two:

1. `http://IP:8000` does not even load -> Wi-Fi AP isolation or router
   firewall; connect the PC to the same network segment.
2. Panel loads but badges show `8080 INJOIGNABLE` while `net_diag PORTS`
   on the box lists `:8080` -> inbound filter on 8080/8081 (PC firewall,
   corporate LAN). Test from the PC:
   `curl http://IP:8080/api/HELP` (or `Test-NetConnection IP -Port 8080`).
3. Badges flip OK/INJOIGNABLE intermittently -> single-slot `nc` servers
   busy (a synchronous CONF_CHECK blocks 8080 for a few seconds); retry.
4. Requests never appear in `log/control_server.log` (not even as
   `REQUEST REJECTED`) -> they are dropped before reaching the box:
   confirmed network/firewall issue, not a tools problem.

### Command accepted but nothing happens

The watcher runs the action with the uid of whoever launched `EXPOSE`.
Launched from `adb shell` (uid 2000), root-only actions fail silently in
`log/watch.log`. Launch with root:

```bash
su -c 'sh /data/scripts/deploy.sh EXPOSE'
```

### Ports 8080/8081 unreachable while 8000 answers

The control (8080) and gui (8081) servers are single-connection `nc`
loops: a silent connection (browser preconnect, port scan) used to
monopolize the only slot, and a server started from an adb session died
with it (SIGHUP). Fixed in v17+: idle connections expire after 30 s
(`timeout`), loops ignore SIGHUP, `deploy STOP` also sweeps orphaned
instances through `/proc/*/cmdline`. v18: at startup each server
also kills its own leftover port holder (orphan `nc` keeps the bind while
serving nothing - seen in the v18 field logs: 8081 "up" to TCP probes but
every SHOT silent, TV mirror never displayed), and fails loudly if a
foreign process still holds the port. v19: `net_diag PORTS` merges netstat
and `/proc/net/tcp` readings and drops entries outside 1-65535 (a bogus
toolbox value used to mask the /proc fallback).

v20 fixes the two blind spots the field logs exposed:

- **Key-first root resolution** (`gui_server.sh`, `control_server.sh`,
  `watch_usb.sh`): launched from `/data/scripts/server`, `dirname($0)/..`
  used to win and logs/pidfiles/incoming landed in `/data/scripts/...`,
  invisible to `SEND_LOGS` (srv_logs reads `<key>/log`) and to
  `deploy STOP`. Field witness: http_server.log said `CONTROL SERVER
  STARTED (PORT 8080)` while no control/gui log existed on the key.
- **"ALREADY RUNNING" no longer exits blindly**: a live pidfile whose nc
  listener died answered ALREADY RUNNING without opening the port, BEFORE
  the orphan-recovery block was ever reached - 8081 stayed dead with no
  trace anywhere. The pid is now verified against the port: listening ->
  normal exit (traced); silent -> killed and startup falls through to
  orphan recovery.
- **Every outcome traced**: start_server writes deja actif / ECHEC (with
  server output) / script absent / WARN port-not-open into
  `log/http_server.log` for both GUI and CONTROL.
- **SEND_LOGS sees both layouts**: srv_logs picks the newest copy of each
  server log from `<key>/log` OR `/data/scripts/log`; a raw
  `ports_raw.txt` (netstat + `/proc/net/tcp{,6}`) is collected too, so a
  silent net_diag can never blind a session again.

v21 closes the hole those fixes exposed (field logs session C): after a
STOP, a surviving `tcpsvd` supervisor from the previous session kept the
8080 bind - it matches neither the script name nor `nc`, so every rebind
of the new control failed (`tcpsvd en echec -> REPLI FIFO`, port NON
ouvert) while the startup verdict reported "en ecoute" by probing the
FOREIGN holder. `deploy STOP`/`services STOP` sweeps and the control
orphan-recovery now target `tcpsvd ... 8080` holders too; gui requests
without action are logged with their raw request line.

Diagnosis on the box:

```bash
net_diag PORTS
ps | grep busybox        # nc processes stuck = old behavior
```

Recovery:

```bash
su -c 'sh /data/scripts/deploy.sh STOP'
su -c 'sh /data/scripts/deploy.sh EXPOSE'
net_diag PORTS           # 8000/8080/8081 expected
```

---

## Logging Issues

When reporting a problem, collect the following information whenever possible:

```text
Device model:
RK322x variant:
Android version:
Date/time:
IP address:
ADB status:
Root status:
USB status:
Deployment command:
Error message:
Relevant logs:
```

Logs should preferably be collected using:

```bash
sh /mnt/media_rw/4E28-7C59/deploy.sh SEND_LOGS
```

---

## Issue History

Document confirmed issues below.

### 2026-08-23 - Recette NO-GO (P2/P4/P7) sur Leelbox rk322x

```text
Date:      2026-08-23
Device:    Leelbox rk322x_box, Android 7.1.2 (SDK 25)
Version:   v4
Problem:   recette -> verdict NO-GO (phases P2 P4 P7)
Symptoms:  P2 selftest KO (ssh_server STATUS rc=127) ;
           P4 mem_tune OPTIMIZE rc=1 sans trace exec ;
           P7 ports 0/3, panneau ko, aucun log http/gui/control sur la cle.
Diagnosis: P2 : selftest pointait $BASE/../server/ -> /data/server inexistant
              (server/ jamais installe cote box, manifest le confirme).
           P4 : kernel expose zram0 mais backend lz4 casse
              (dmesg : "Cannot initialise lz4 compressing backend",
              fs_mgr: swapon failed au boot) -> mkswap/swapon en erreur.
              mem_tune ne tracait rien (runlog non branche).
           P7 : deploy EXPOSE dependait de server/ SUR LA CLE uniquement ;
              absent -> echec silencieux. Le label "api CONFIG repond"
              etait affiche avant le test (trompeur).
Solution:  v5 : server/*.sh installes dans /data/scripts/server a l'INSTALL,
              EXPOSE et selftest utilisent l'installation d'abord ;
              mem_tune : relecture disksize + tentative comp_algorithm=lzo,
              backend casse -> WARN + marqueur /data/etc/mem_tune.zram_unavailable
              (conf_check affiche INDISPON., plus de faux "PAS LANCE") ;
              runlog branche sur mem_tune ; recette P7 affiche la sortie EXPOSE
              en cas d'echec et sonde les ports via /proc/net/tcp si netstat absent.
Status:    Corrige en v5. zram reste impossible sur ce firmware (limite kernel).
```

### 2026-08-23 - Recette toujours NO-GO (P1/P2/P4/P7) apres retour de logs

```text
Date:      2026-08-23
Device:    Leelbox rk322x_box, Android 7.1.2 (SDK 25)
Version:   v13 cote PC ; box re-installee depuis une cle perimee/incomplete
Problem:   recette -> verdict NO-GO (P1 P2 P4 P7)
Symptoms:  manifest d'install : 9 outils manquants + /data/scripts/server VIDE ;
           P2 ssh_server rc=127 ; P4 mem_tune rc=1 (mkswap/swapon) ;
           P7 ports 0/3 alors que l'api CONFIG repond au wget.
Diagnosis: - Cle au layout zip officiel (deploy.sh + .dpk a la racine, sans
             scripts/) : deploy INSTALL ne copie presque rien -> boite
             demi-installee, server/ vide -> selftest et EXPOSE en echec.
           - "Dernier .dpk" choisi par tri lexical du nom : v9 > v13
             (find_pkg cote box, show_key, tools/dpk.sh latest).
           - mem_tune : le kernel ACCEPTE disksize mais backend lz4 mort
             (dmesg : "Cannot initialise lz4 compressing backend") ->
             mkswap/swapon echouent -> RC=1 ; chemin non couvert par le
             correctif v5 (qui ne declenchait que si disksize etait refuse).
           - recette P7 : netstat absent/muet et parsing /proc incertain sur
             ce firmware -> 0/3 meme quand les services repondent.
Solution:  v13 : INSTALL bascule automatiquement sur le .dpk quand la cle n'a
              pas scripts/ ; "dernier paquet" trie sur le BUILD_ID (3e champ,
              largeur fixe) cote PC et box ; mem_tune : comp_algorithm AVANT
              disksize, echec mkswap/swapon -> WARN + marqueur zram_unavailable
              + reset propre (rc neutre, limite firmware) ; recette port_up :
              netstat -> /proc/net/tcp -> sonde wget fonctionnelle par endpoint.
Status:    Corrige en v13. Re-deployer : dezipper rk322x-cle_v13_*.zip a la
           racine de la cle puis su -c 'sh /mnt/media_rw/*/deploy.sh INSTALL'
           et relancer la recette. zram reste impossible sur ce firmware.
           v18 : net_diag PORTS applique le meme repli (netstat ->
           /proc/net/tcp hexa, etat 0A) ; sur firmware muet il listait
           "rien" et le pied de page "Arret global" induisait en erreur
           alors que les serveurs repondaient.
```

### 2026-08-23 - Recette bloquee en P7 + boot bloque sur front_digit

```text
Date:      2026-08-23
Device:    Leelbox rk322x_box, Android 7.1.2 (SDK 25)
Version:   v17
Problem:   recette -> log tronque juste apres "--- [P7] EXPOSE ---"
           (deux runs identiques) : pas de bilan, pas de RETOUR,
           P7 absente de recette_phases.txt.
           boot -> log tronque apres "[boot] front_digit CLOCK..." :
           sd_boot CHECK et motd jamais executes au demarrage.
Symptoms:  box vivante pendant le blocage (autres outils lancables) ;
           run_state annonce des "echecs" RC ? pour selftest/recette/
           run_state eux-memes, simplement parce que leur trace est
           encore en cours d'ecriture au moment du scan.
Diagnosis: sous-shell de service lance en arriere-plan SANS redirection :
           il herite du tube d'une capture $( ) et la ferme jamais ->
           le $( ) n'en finit jamais.
           - gui_server/control_server : ( boucle nc ) & capture par
             start_server (GUI_OUT=/CTRL_OUT=$( ... )) puis recette P7
             (EXPOSE_OUT="$( deploy EXPOSE )") -> fige exactement apres
             l'entete [P7].
           - front_digit daemon_loop : ( while true ) & capture par
             PID="$( daemon_loop ... )" -> do_clock ne rend jamais la
             main -> boot.sh bloque avant la fin de sequence.
           - le boot passe quand il redirige vers /dev/null (run_tool),
             d'ou l'impression que seul P7 est touche.
Solution:  redirection systematique des sous-shells detaches
           ( ) >/dev/null ou >> "$LOG" ; captures par fichier temporaire
           au lieu d'un $( ) nu (recette P7, start_server) ; sondes wget
           bornees timeout dans P7 ; boot : front_digit CLOCK sous
           timeout 90 pour garantir la suite du boot ; run_state : seuls
           les rc numeriques non nuls comptent en echec, trace en cours
           ignoree (comparaison -nt marqueur), verdict "trace incomplete"
           sinon.
Status:    Corrige. Regle generale : ne JAMAIS capturer dans $( ) un
           script qui detache une boucle infinie - rediriger le
           sous-shell OU passer par un fichier temporaire.
```

---

## Notes

This document should evolve with the project.

Every recurring issue should eventually have:

1. A clear description.
2. The symptoms observed.
3. The diagnostic commands used.
4. The identified cause.
5. The solution or workaround.
6. The affected version, when known.

---

## TOOLS

### crowdsec tool removed (v17+)

The `crowdsec` helper has been withdrawn from the toolkit. Verdict after
evaluation: CrowdSec ships glibc-linked binaries that cannot run on this
firmware's bionic kernel userspace, and proot-based alternatives exceed the
realistic RAM budget of a 2 GB headless box.

Behavioural IDS needs are covered natively by `net_watch`
(BAN/UNBAN iptables, event log). If CrowdSec is ever required, run it on
the gateway/PC side instead - not on the box.

---

## SWAP

### Swap chain: key file with /data fallback (v17+)

Context: zram is impossible on this firmware (broken lz4 backend, see
entry above), so disk swap is the only swap available. The original V1
design used a single 512 MB `swap.bin` on the USB key
(`MEM_SWAP_FILE=auto`, priority 1, re-armed each boot by
`BOOT_MEM_TUNE=1`). Failure mode: unplug/lose/rekey the USB stick and
the box runs with NO swap at all until someone notices.

Solution (v17): explicit two-link chain in `mem_tune`:

| Link | Path | Priority | When |
|---|---|---|---|
| Key file | `/mnt/media_rw/*/swap.bin` | 1 | normal operation |
| Data fallback | `/data/local/swap.bin` | 2 | only when the key link fails |

Rules:
- OPTIMIZE activates the key first; only on failure it creates/enables
  the data fallback (`MEM_SWAP_DATA_MB=512`, 0 = disabled).
- When the key comes back, the next OPTIMIZE swaps off the fallback and
  rests the eMMC ("retour de la cle" log line).
- STATUS shows every link state plus a one-line chain verdict
  ("JAMAIS sans swap" / "cle ACTIF seule" / "repli /data ACTIF").
- The boot path needs no change: BOOT_MEM_TUNE runs the same OPTIMIZE.

Kernel capability gate is unchanged: if `swapon` refuses a file on the
key it will refuse `/data` too (same filesystem mechanics) - check
`preflight` (swap section) and `dmesg` first.

### swapon acceptance assurance + live-built syscall binary (v17+)

The swap chain assumed a working `swapon` executor. Two failure modes
remained: busybox without the swapon/swapoff applets, and a kernel that
refuses file swap. `mem_tune PROBE` (action [O9]) closes both:

- Detects available agents in order: busybox applet, system binary.
- If NONE: builds one LIVE - `core/swap.sh` emits a minimal static
  ELF32 ARMv7 (129 bytes) byte-by-byte via printf, embedding the real
  target path, calling raw syscall __NR_swapon=167 / __NR_swapoff=168.
  Dropped in /data/local/tmp (ext4, exec-safe; never on vfat key).
- mkswap fallback: if the applet is missing too, a pure-dd formatter
  writes the SWAPSPACE2 magic at end of last page (sufficient for ext4
  file swap on 4k kernels).
- Real capability test: 1 MB probe file on the SAME filesystem as the
  target -> KERNEL_OK / KERNEL_REFUSE / EXEC_IMPOSSIBLE, verdict kept in
  /data/etc/mem_tune.swap_capability and surfaced by mem_tune STATUS.

Emitter validated offline: magic/entry/phdr/code words checked byte per
byte for both variants. KERNEL_REFUSE (CONFIG_SWAP off or fstype reject)
is a firmware limit no userspace build can bypass - PROBE makes that
explicit instead of failing silently at OPTIMIZE time.
