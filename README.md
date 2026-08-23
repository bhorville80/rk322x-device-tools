# rk322x-device-tools

Complete administration toolkit for RK322X TV boxes (Leelboox MXQ,
Android 7.1.2) - deployment, autonomous startup, web panel, diagnostics
and non-regression, all driven from a single USB key.

**This README is only an index.** Each topic lives in its own document:

> **Viewing the .md files**: any Markdown viewer works. Free/portable
> picks: [MarkText](https://github.com/marktext/marktext/releases)
> (portable, Win/Linux/Mac), VS Code (portable zip), or `glow` (CLI).
> GitHub also renders them automatically. Copies ship in `admin/linux/docs`
> and `admin/windows/docs` so the PC admin kit carries its own docs.

| Want to... | Read |
|---|---|
| Prepare the PC + key and install from a factory reset | [docs/SETUP.md](docs/SETUP.md) |
| Install from scratch on a virgin box | [docs/STARTUP.md](docs/STARTUP.md) |
| Use the web panel (pages, buttons, console) | [docs/IHM.md](docs/IHM.md) |
| Find a tool / the full catalogue by theme | [docs/TOOLS.md](docs/TOOLS.md) |
| Write/maintain code (rules & patterns) | [docs/CODING.md](docs/CODING.md) |
| Run the functional/energy acceptance sheet | [docs/RECETTE.md](docs/RECETTE.md) |
| Understand what V1 ships / what is next | [ROADMAP.md](ROADMAP.md) |
| Diagnose a known failure | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| Track non-regression baseline & open points | [docs/NON-REG.md](docs/NON-REG.md) |
| Run the V1-beta checkpoint plan | [docs/RUN-BETA.md](docs/RUN-BETA.md) |

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
