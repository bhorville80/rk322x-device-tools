# ROADMAP - rk322x-device-tools

## V1 - RELEASED (all features shipped)

One-page summary of what V1 delivers on a stock RK322X TV box
(Leelbox MXQ, Android 7.1.2, 2 GB RAM, headless 24/7):

- [x] **Deployment** - USB key is the source of truth; dpk packages with
      sha256; `INSTALLER.sh` interactive one-command install with validation
      gates; post-install auto boot-hook setup (init rc / init.d /
      install-recovery fallbacks); `/data/bin` links with stale-link purge.
- [x] **Autonomous startup** - boot hook survives reboots; waits for key
      enumeration (`BOOT_WAIT_KEY`); applies mem_tune, cut_services,
      network (no-cut IP switch), clock (key mtime / dpk filename / RTC
      sources), web stack EXPOSE with port verification, front-panel clock,
      SD-card last, log rotation/purge.
- [x] **Web panel (IHM)** - 6 pages on :8000: Accueil (versions, verdicts,
      box clock), Cle (upload with browser sha256 + APPLY_DPK key update +
      direct downloads), Commandes (clock sync, state, logs, HDMI, ECO/PERF,
      reboot, hardware report, recette phases P1..P7 + manifest),
      Metriques en onglets (DIAGNOSTIC / PROCESSUS-RAM / SWAP / LAUNCHER TV,
      un bouton = un rapport dedie), Telecommande (TV screen mirror,
      click-to-TAP, keys, TEXT/URL, remote console RUN), Infos (static data).
- [x] **Servers** - busybox httpd :8000 (static key), control API :8180
      (FIFO detached handlers, POST upload, APPLY_DPK, RUN console gated by
      WEB_RUN+token, diagnostics PROC/DEV/PROBE/LAUNCHER), GUI TV :8081
      (KEY/TAP/TEXT/URL/SHOT), optional dropbear.
- [x] **Tooling** - 50+ tools: nreg (10-theme non-regression runner),
      config (interactive editor with type validation), profile manager,
      manage dispatcher, inspect_all heart/exploration classes, hw_report
      hardware research report, rampre pre-install RAM baseline,
      ramstep instrumented deployment (per-step RAM deltas), selftest,
      aliases for uid-2000 shortcuts.
- [x] **Ops hygiene** - standardized traces (runlog), log rotation with
      age-based purge at boot, dist/ rotation, manifests with sha256.

## NEXT - V1-beta roadmap

### Phase 1 - Integration from scratch

> Plan d'execution par checkpoints : **docs/RUN-BETA.md**
> (sequence 9 -> 5 -> 2 -> 4 -> 6/7/8 ; preuves attendues par checkpoint).

> Etat au 2026-08-23 : code pret, MXQ reset usine en attente de run.
> Les IDs [Xnn] referencent docs/STARTUP.md. Rien n'est coche tant que
> la preuve (log/trace/sortie) n'est pas archivée.

#### Pre-requis
- [ ] Cle FAT32 preparee avec dernier dpk + sha256 + deploy.sh ([P1])
- [ ] TV : options developpeur + debogage USB actives ([P2][P3])
- [ ] IP statique configuree via TV ([P4])
- [ ] adb root operationnel en USB ([P5][P6])

#### Baseline
- [ ] [A2] rampre 120 s archive sur la cle (rapport renomme baseline)

#### Installation
- [ ] [I1] INSTALLER interactif : 0 ERREUR, hook confirme par boot STATUS

#### Configuration & optimisations
- [ ] [C1] conforme / [C3] ping OK
- [ ] [O1] ECO actif ; [O2] mem_tune applique ; chaine swap cle -> repli
      /data active (JAMAIS sans swap) ; [O9] PROBE verdict KERNEL_OK archive
- [ ] [O5] cut_services CUT : gains PSS chiffres vs baseline
- [ ] [O8] ramstep 30 s : chronologie ram_steps archivee

#### Verification & inspection
- [ ] [R1] nreg 10/10 themes PASS
- [ ] [R2] selftest 0 FAIL
- [ ] [N10] inspect_proc : candidats RAM identifies (baseline detournement)
- [ ] [N11] inspect_dev : KSM/scheduler verifies avant tout daemon maison
- [ ] [C4] launcher_toggle STATUS vert (voie A/B prete si besoin UI TV)
- [ ] [N4] hw_report SAVE genere (analyse puces a fournir)

#### Serveur & IHM
- [ ] [S2] manage web : tcpsvd actif ? listeners = API_MAX_CONN ?
- [ ] [W0..W7] matrice IHM complete (dont auth user/user, upload+APPLY dpk reel)

#### Gate beta
- [ ] [B1..B4] reboot autonome x2 CONSECUTIFS sans intervention
- [ ] docs/NON-REG.md mis a jour (points O1-O5 fermes)
- [ ] tag v1.0-beta

### Hors phase 1 (backlog, non planifie)
- [ ] GUI 8081 multi-listeners (tcpsvd) comme l'API 8180
- [ ] OTA delta via UPLOAD/APPLY_DPK programme
- [ ] provisioning multi-box depuis admin/
- [ ] page IHM viewer de logs
