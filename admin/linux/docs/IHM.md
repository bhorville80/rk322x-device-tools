# IHM - Web panel user guide

> Everything is driven from a browser: `http://<ip-box>:8000/`
> 6 pages, a common navigation bar, and port status badges on top
> of every page.

## Port badges (all pages)

| Badge | Meaning |
|---|---|
| green `OK` | port answers |
| orange `UP - token required` | server active, protected by token |
| red `UNREACHABLE` | service stopped or network blocked |

---

## ACCUEIL (Home)

- **Version summary**: installed (/data/scripts) vs key; verdict "up to date"
  or "divergent -> deploy INSTALL".
- **conf_check verdict**: last 3 lines of the configuration validation.
- **Latest CHECK STATE**: header of the last box/network state.
- **Box clock**: box time compared with PC - red = 1970 (CLOCK BROKEN),
  orange = drift > 180 s (run SYNC HORLOGE).

## CLE (USB key)

- **First boot**: reminder of the initial install command.
- **Tool catalogue** grouped by function.
- **Upload to the key**: pick a file (.dpk/.sha256/.txt/.log, max 20 MB)
  -> TELEVERSER. sha256 is computed by the browser then verified by the
  box. A .dpk automatically offers APPLY.
- **Apply a deposited dpk**: extracts the tar.gz ONTO THE KEY (update
  without unplugging). Then: Commandes page > REBOX, or `deploy INSTALL`.
- **Direct downloads**: hardware report, recette/state/vitals summaries,
  certified manifest, config, log/ directory browsing.

## COMMANDES (actions)

| Section | Buttons | Effect |
|---|---|---|
| Base | SYNC HORLOGE | sets the box clock to PC UTC |
| | CHECK STATE | full state; result in log/state_last.txt |
| | SYNC CLE | syncs /data/scripts back to the key |
| Logs | SEND LOGS / ROTATE / PURGE | collect, rotate, purge traces |
| TV display | PANEL | opens the web panel ON THE TV |
| | HDMI OFF/ON, FIELD OFF/ON | cut/restore display output & services |
| System | MODE ECO / MODE PERF | CPU thermal profile (24/7: ECO) |
| | REBOOT | restart (confirmation dialog) |
| Material | HARDWARE REPORT | generates full hw_report + download link |
| Recette | P1..P7, RETOUR | single phases; COMPLETE = P1->RETOUR |
| | GENERATE MANIFEST | certification after 7/7 OK |

Results are displayed in the black output block under the buttons.

## METRIQUES

- **VITALS**: instant memory/CPU/load reading (+ WATCH for tracking).
- **CHECK STATE**, **CONF CHECK**: manual reruns with raw output.

## TELECOMMANDE

- **TV screen (mirror)**: screenshot refreshed on an interval
  (pause / 2 s / 4 s / **8 s by default**). The reload only happens once
  the SHOT request has completed (a fixed delay could miss a slow
  screencap); failures are shown inline ("8081 unreachable", "capture
  unavailable") next to the port badges. **Clicking the image = TAP at
  the same coordinates on the TV.**
- **Keys**: dpad + OK, BACK/HOME/MENU, VOL +/- , POWER.
- **Send**: TEXT = full-screen message on the TV;
  OPEN URL = page in the TV browser.
- **Front display (blink points)**: direct test of the IHM -> API ->
  FD655 chain. Quick SHOW buttons (8888 / 12.34 / HELP / STOP) and
  named blink presets (`front_digit BLINK`): p1..p4 = decimal point
  per digit, chase, all - built-in defaults. "Definir" creates a new
  preset: name + digit points checkboxes + optional extra 7-seg frames
  + period; sequence always ends off. Endpoints: FD_SHOW, FD_BLINKS,
  FD_BLINK, FD_BLINK_NEW, FD_BLINK_DEL, FD_STOP.
- **Remote console** (adb-shell equivalent): one line -> raw output.
  Requirements: `WEB_RUN=1` in device.conf AND active token
  (`deploy TOKEN ON`) - refused otherwise by design. Bounded to
  15 s / 8 KB, every line is logged.

## INFOS (static data)

- **Identity & versions**: Android, build, kernel, uptime, RAM, CPU, /data.
- **Material**: latest chip report viewable + regeneration button.
- **Active configuration**: device.conf served read-only.
- **Certified recette manifest**: OK phases + sha256 fingerprints.

---

## Security

- Without token: API 8080 and GUI 8081 are open to the LAN
  (panel :8000 is static content).
- `deploy TOKEN ON` protects API/GUI; the panel asks for the value once
  per browser (localStorage).
- The remote console additionally requires `WEB_RUN=1`.

## Troubleshooting

- Badge 8080 red -> run `deploy EXPOSE` on the box (or adb).
- Persistent "Failed to fetch" -> see TROUBLESHOOTING, WEB PANEL section.
- After any script update: `deploy STOP && deploy EXPOSE`.

## Metriques - onglets, un bouton = un rapport (V17)

La page est organisee en **onglets thematiques** :

| Onglet | Actions |
|---|---|
| DIAGNOSTIC | [N5] VITALS, [N6] CHECK STATE, [C1] CONF CHECK, [N8] SYS DIAG |
| PROCESSUS / RAM | [N10] PROCESSUS PSS, [N11] CAPACITES DEV (AUDIT) |
| SWAP | [O9] PROBE SWAPON, [O11] ETAT MEMOIRE, [O12] GARDIEN SWAP |
| LAUNCHER TV | [C4] LAUNCHER ETAT |

Regle d'or : **un bouton = sa zone noire de rapport dediee** (sortie
horodatee dans la carte du bouton, jamais melangee avec les autres).
Chaque carte porte sa case a cocher et sa puce d'etat : ⏳ EN COURS
(clignotante), ✓ OK, ✗ ECHEC. **LANCER LA SELECTION** execute toutes les
cases cochees (tous onglets confondus) via un pool borne par le selecteur
**max parallele** (1-4), departs decalés 300 ms.

Endpoints API 8080 ajoutes pour ces actions : PROC / DEV / PROBE /
LAUNCHER / SWAP (mem_tune STATUS) / SWWATCH (swap_watch STATUS)
(reponse synchrone text/plain, meme pattern que CONF_CHECK).

Selecteur **listeners box** (1-7, defaut 3) : nombre de connexions
simultanees acceptees par l'API 8080 quand le firmware busybox fournit
tcpsvd ; sans tcpsvd, la box reste en mode mono-slot et la valeur sera
appliquee des qu'un busybox complet est disponible. Effectif apres
`deploy STOP ; deploy EXPOSE`.
