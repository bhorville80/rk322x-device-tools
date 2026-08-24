# BEST COMMANDES - ce qui debloque quoi, et les meilleures commandes internes

> Reference : quels binaires/offrent quelle puissance sur la box RK322X
> (Leelbox MXQ, Android 7.1.2, 2 Go RAM, ARMv7 32 bits), et un aide-
> memoire des meilleures commandes internes. Complements directs de :
> `busi` [N12-N14] (inventaire busybox vivant), `inspect_dev` [N11]
> (capacites execution), `preflight` (verdicts features).

## 0. La regle d'or

Un binaire statique ARM pose sur la cle = un DOMAINE ENTIER debloque,
sans installation ni dependance (le firmware reste intact). Trois
familles :

1. deja presents dans le firmware : busybox, toybox, mksh
2. a deposer sur la cle : tcpdump, dropbear, socat, strace...
3. un rootfs Linux complet en chroot (`chroot_env`) = l'ultimate

Notation : `$BB` = chemin du busybox detecte (voir `busi INFO`,
surcharge possible par `BUSYBOX_BIN` dans device.conf).

## 1. Deja dans la box

| Binaire | Puissance | Exploite par |
|---|---|---|
| busybox | des centaines d'applets : web (httpd), reseau (nc/wget/telnetd/tftp), disques (dd/tar/gzip), process (watch/top), planification (crond), isolation (chroot) | panneau :8000, paquets .dpk, swap.bin, vitals, nreg |
| toybox | applets Android modernes, dont `chroot` sur 7.1 | chroot_env, inspect_dev |
| mksh | shell POSIX complet : le moteur de TOUT le toolkit | tous les scripts |
| toolbox | applets historiques encore servis au boot (getprop/start/stop...) : CONSERVE, decision actee | init Android |

## 2. A deposer sur la cle (binaires statiques ARM armhf)

| Binaire | Debloque | Consomme par le kit |
|---|---|---|
| dropbear + dbclient/scp | SSH+SFTP port 2222, shell distant chiffre | ssh_server (START/STATUS) |
| tcpdump | captures pcap temps reel -> Wireshark cote PC | capture START (deja integre) |
| socat | relais TCP/UDP/UNIX, tunnels, redirections | tests API, ponts ad-hoc |
| strace | tracage syscalls d'un processus vivant | investigate DISPLAY (daemon FD655) |
| openssl | tests TLS/certificats (s_client), chiffrement | audits reseau manuels |
| nmap | inventaire/scan de ports du LAN | audit reseau manuel |
| iperf | mesure de bande passante propre | alternative a net_diag THROUGHPUT |
| gdbserver | debug pas-a-pas d'un binaire C | developpement uniquement |

Ou les poser : racine de la cle USB (pattern dpk/UPLOAD du panneau) ou
`/data/local/tmp`. Executables admis si `/data` est monte exec (verdict :
`inspect_dev` [N11], cf aussi `busi CHECK`). ABI obligatoire : armeabi-v7a.

## 3. Les BEST internes busybox (aide-memoire)

| Commande | Effet immediat |
|---|---|
| `$BB httpd -f -p 8181 -h .` | serveur web instantane (mecanisme du panneau) |
| `$BB wget -q -O - URL` | telechargement HTTP (absent d'Android stock) |
| `$BB nc -z IP PORT && echo ouvert` | test de port sans nmap |
| `$BB nc -l -p 9000` | recepteur TCP brut (debug API/daemon) |
| `$BB tar -czf out.tgz DIR` | sauvegarde compressee (mecanisme .dpk) |
| `dd if=/dev/zero of=swap.bin bs=1M count=512` | fabrication swap sur cle (mem_tune) |
| `$BB awk '/MemAvail/{a=$2}/MemTotal/{t=$2}END{print a*100/t"%"}' /proc/meminfo` | % RAM libre (moteur vitals) |
| `$BB find DIR -type f \| xargs du -k \| sort -nr \| head` | top gros fichiers (audit eMMC) |
| `$BB watch -n 5 'date; cat /proc/loadavg'` | monitoring continu (vitals WATCH) |
| `$BB sed -n 's/^IP=//p' device.conf` | extraction d'une cle de config |
| `$BB crond -b -c DIR` | planification cron (repli du hook BOOT_*) |
| `$BB telnetd -p 2323 -l /system/bin/sh` | repli shell distant sans SSH |
| `$BB tftp -g -r fic IP` | transfert rapide LAN sans HTTP |
| `$BB chroot ROOTFS /bin/sh` | mini-conteneur (cf chroot_env ENTER) |
| `$BB sha256sum fichier` | integrite (pattern .dpk.sha256) |
| `$BB hexdump -C fic \| head` / `strings fic` | analyse binaire/log binaire |
| `$BB base64 fic > fic.b64` | transport texte d'un binaire (coller via adb) |
| `$BB vi /data/scripts/config/device.conf` | edition directe sur la box |

## 4. Combos gagnants (one-liners)

```sh
# partager un repertoire entier sur le LAN en une ligne (PC: http://IP:8181)
cd /data/local/tmp && $BB httpd -f -p 8181 -h .

# copier un rapport vers le PC SADB pull : servir puis recuperer au navigateur
$BB httpd -f -p 8181 -h /tmp/rk322x_logs &

# surveiller qui parle sur le reseau (top connexions, 1 ligne)
$BB watch -n 5 "awk 'NR>2{print \$3}' /proc/net/tcp | sort | uniq -c | sort -nr | head"

# extraire la temperature SOC et alerter si > 70C (boucle BOOT_* compatible)
while :; do T=$(cat /sys/class/thermal/thermal_zone0/temp); [ "$T" -gt 70000 ] && echo HOT; sleep 30; done
```

## 5. Ce qu'AUCUN binaire ne debloque sur ce firmware

| Besoin | Verdict | Contournement du kit |
|---|---|---|
| Docker reel | kernel Android 4.4 incomplet (cgroups/overlayfs) | chroot_env (rootfs Debian armhf) |
| systemd / cgroups v2 | absents du kernel | boucles sleep + hook BOOT_* |
| binaires 64 bits | Cortex-A7 = 32 bits only | compiler/target armeabi-v7a |
| zram compression | backend lz4 casse (cf TROUBLESHOOTING) | swap sur cle (mem_tune) |

## 6. Voir aussi

- `busi POWERS` [N14] : ces puissances EN ACTION sur la box
- `busi CHECK` [N13] : ce qui manque aux besoins reels du kit
- `busi WHO` [N15] : quel binaire fournit chaque commande de /system/bin
- `docs/TOOLS.md` : catalogue complet des outils exploitant tout ceci
