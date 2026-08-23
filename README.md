# rk322x-device-tools

Complete administration toolkit for RK322X TV boxes (Leelboox MXQ,
Android 7.1.2) - deployment, autonomous startup, web panel, diagnostics
and non-regression, all driven from a single USB key.

**This README is only an index.** Each topic lives in its own document:

| Want to... | Read |
|---|---|
| Install from scratch on a virgin box | [docs/STARTUP.md](docs/STARTUP.md) |
| Use the web panel (pages, buttons, console) | [docs/IHM.md](docs/IHM.md) |
| Run the functional/energy acceptance sheet | [docs/RECETTE.md](docs/RECETTE.md) |
| Understand what V1 ships / what is next | [ROADMAP.md](ROADMAP.md) |
| Diagnose a known failure | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| Track non-regression baseline & open points | [docs/NON-REG.md](docs/NON-REG.md) |

## 60-second overview

```bash
# PC: copy to USB key root: <latest>.dpk (+.sha256), deploy.sh, INSTALLER.sh comes inside the dpk
adb shell ; su
sh /mnt/media_rw/*/INSTALLER.sh     # interactive install + boot hook + apply now
```

Then everything runs by itself at every boot, and the panel is on
`http://<ip-box>:8000/` (see docs/IHM.md).

Packaging details: [PACKAGING.md](PACKAGING.md).
PC-side admin kit (provision/logpull/set_box_time): `admin/linux`, `admin/windows`.
