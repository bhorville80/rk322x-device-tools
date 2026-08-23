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
      Metriques (vitals/state/conf), Telecommande (TV screen mirror,
      click-to-TAP, keys, TEXT/URL, remote console RUN), Infos (static data).
- [x] **Servers** - busybox httpd :8000 (static key), control API :8080
      (FIFO detached handlers, POST upload, APPLY_DPK, RUN console gated by
      WEB_RUN+token), GUI TV :8081 (KEY/TAP/TEXT/URL/SHOT), optional dropbear.
- [x] **Tooling** - 50+ tools: nreg (10-theme non-regression runner),
      config (interactive editor with type validation), profile manager,
      manage dispatcher, inspect_all heart/exploration classes, hw_report
      hardware research report, rampre pre-install RAM baseline,
      ramstep instrumented deployment (per-step RAM deltas), selftest,
      aliases for uid-2000 shortcuts.
- [x] **Ops hygiene** - standardized traces (runlog), log rotation with
      age-based purge at boot, dist/ rotation, manifests with sha256.

## NEXT - V1-beta roadmap

**Phase 1 (next) - From-scratch integration of a rich version**
Rebuild the distribution as a single rich V-beta image: full STARTUP
procedure executed end-to-end on a factory-reset box (baseline rampre ->
INSTALLER -> ramstep instrumented -> nreg -> IHM matrix -> autonomous
reboot), with every gap found during the run fixed before beta tagging.

Later candidates (unordered): multi-box fleet provisioning from the PC
admin kit, panel-side log viewer page, optional SSH hardening wizard,
OTA delta updates via UPLOAD/APPLY_DPK scheduling.
