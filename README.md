# FreeCAD Linux Helper Scripts

Two small, dependency-light Bash scripts for running FreeCAD on Linux through
[FreeCAD Smart Launcher](https://github.com/deltahedra3d/freecad-launcher) instead of the Flathub Flatpak.

| Script                              | Version | Purpose                                                                                      |
| ----------------------------------- | ------- | -------------------------------------------------------------------------------------------- |
| `install-freecad-smart-launcher.sh` | 1.1.0   | Install, update or uninstall the launcher AppImage as a desktop app; choose its data folder  |
| `migrate-freecad-flatpak-config.sh` | 1.0.0   | Move FreeCAD settings and user data from the Flatpak to the native profile used by AppImages |

Both run as your normal user and never need `sudo`. They only write inside your home directory, except for a
launcher data folder you choose elsewhere with `--data-dir`.

Contents:

- [Requirements](#requirements)
- [Quick start](#quick-start)
- [install-freecad-smart-launcher.sh](#install-freecad-smart-launchersh)
- [migrate-freecad-flatpak-config.sh](#migrate-freecad-flatpak-configsh)
- [Exit codes](#exit-codes)
- [Output](#output)
- [Changelog](#changelog)
- [References](#references)

---

## Requirements

| Requirement                                | Needed by | Notes                                                                                                                        |
| ------------------------------------------ | --------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Bash 4+, coreutils, `sed`, `grep`          | both      | Present on every mainstream distro                                                                                           |
| `fusermount3` (package `fuse3`)            | installer | Installed by default on Fedora. The launcher uses the static AppImage runtime, so `fuse-libs` / `libfuse2` is **not** needed |
| `python3`                                  | both      | Standard library only. Migrate: compare and merge `user.cfg`. Installer: read and update the launcher's data folder settings; without it the data folder step is skipped |
| `update-desktop-database`, `kbuildsycoca6` | installer | Optional. Used to refresh menus immediately when available                                                                   |

Developed and tested on **Fedora 44, KDE Plasma (Wayland)**. Nothing is Fedora- or KDE-specific; other desktops
simply skip the KDE cache refresh.

---

## Quick start

```bash
chmod +x install-freecad-smart-launcher.sh migrate-freecad-flatpak-config.sh

# 1. Install the launcher (any downloaded release AppImage)
./install-freecad-smart-launcher.sh ~/Downloads/FreeCAD_Smart_Launcher-0.0.4-linux-x86_64.AppImage

# 2. Close FreeCAD everywhere, then bring your Flatpak settings over
./migrate-freecad-flatpak-config.sh --list-versions
./migrate-freecad-flatpak-config.sh --dry-run
./migrate-freecad-flatpak-config.sh
```

---

## install-freecad-smart-launcher.sh

Turns the launcher AppImage into an app that behaves like an RPM or Flatpak install: menu entry, themed icon,
terminal command and a correct taskbar icon on Wayland.

### Usage

```bash
./install-freecad-smart-launcher.sh <FreeCAD_Smart_Launcher-*.AppImage>   # install or update, asks about the data folder
./install-freecad-smart-launcher.sh <file.AppImage> --default-data-dir     # don't ask, keep the current folder
./install-freecad-smart-launcher.sh <file.AppImage> --data-dir /mnt/big/FreeCAD
./install-freecad-smart-launcher.sh --uninstall
./install-freecad-smart-launcher.sh --version
./install-freecad-smart-launcher.sh --help
```

| Option            | Description                                                                                   |
| ----------------- | --------------------------------------------------------------------------------------------- |
| `<file.AppImage>` | Install it, or update an existing install. The header shows `install` or `update` accordingly |
| `--default-data-dir` | Don't ask about the data folder; keep the current one                                      |
| `--data-dir DIR`  | Set the launcher data folder without asking and move existing content there. `DIR` may be outside your home |
| `--uninstall`     | Remove everything the installer created. The data folder is left untouched                    |
| `-V`, `--version` | Print the script version                                                                      |
| `-h`, `--help`    | Print usage                                                                                   |

### What gets installed

| Item                                   | Location                                                               |
| -------------------------------------- | ---------------------------------------------------------------------- |
| AppImage (fixed, version-less name)    | `~/.local/opt/freecad-smart-launcher/freecad-smart-launcher.AppImage`  |
| Menu entry                             | `~/.local/share/applications/freecad-smart-launcher.desktop`           |
| Icon (256 px, taken from the AppImage) | `~/.local/share/icons/hicolor/256x256/apps/freecad-smart-launcher.png` |
| Terminal command (symlink)             | `~/.local/bin/freecad-smart-launcher`                                  |

Each step prints one line with what it touched. The input file is checked to be a real AppImage before anything is written.

### Launcher data folder

The launcher keeps everything it downloads and tracks in one folder, `~/Applications/FreeCAD` by default:
every FreeCAD version installed through it (one AppImage each), its settings (`launcher_config.json`) and
usage statistics (`time_tracker.json`). On install and update the installer shows the current folder with its
version count and size, then asks whether to keep it. Pick a roomy disk if you keep many versions.

- **New folder.** Type a path (`~` and relative paths work, Tab completes). An empty answer cancels. Rejected,
  with the reason shown: `/`, your home folder, the current folder, the launcher's own install folder, anything
  inside or above the current folder, an existing file, or a place you can't write to.
- **Existing content.** Settings and statistics always follow the move. FreeCAD versions move only when you
  confirm. Files that already exist in the new folder are never overwritten; they are listed as not moved.
- **Menu entries.** When versions move, the `FreeCAD x.y` menu entries the launcher created are updated to the
  new paths, including paths with spaces.
- **Persistence.** A custom folder is stored in `<folder>/launcher_config.json` plus a pointer in
  `~/.freecad_launcher_config.json`, which the launcher keeps across restarts. A folder changed inside the
  launcher is forgotten on restart in the 0.0.4 code, so change it with `--data-dir DIR` instead.
- **Launcher must be closed.** The installer refuses to change the folder while the launcher is running.
- **No terminal.** Nothing is asked and the current folder is kept. Use `--data-dir DIR` for unattended runs.
- **Cleanup.** After a move only empty folders are removed, and the parent only when it is the default
  `~/Applications`.

### Design notes

- **Fixed file name.** The launcher's own "Update launcher" button downloads the new release and swaps it in
  at the same path it runs from. A version-less name means the menu entry keeps working after every update.
- **Not in the launcher's data folder** (default `~/Applications/FreeCAD`). The launcher lists every
  `*.AppImage` in that folder as a FreeCAD version. Installing there would make the launcher show up in its own list.
- **Desktop file named after the binary.** The AppImage's executable is `freecad-smart-launcher`, which Qt
  reports as the Wayland app ID. Matching the `.desktop` name (plus `StartupWMClass`) gives the correct taskbar
  icon and window grouping.
- **Icon extraction needs no FUSE.** It uses `--appimage-extract <name>` to pull out just the icon file.

### Updating

Either use the launcher's built-in **Update launcher** button, or re-run the installer with a newer AppImage.
Both keep the same path, so nothing else changes.

### Uninstalling

`--uninstall` removes the AppImage, menu entry, icon and command link, then refreshes menus.
It deliberately keeps the launcher data folder (default `~/Applications/FreeCAD`), which holds your downloaded
FreeCAD builds and the launcher's config and statistics. The installer prints the folder it left in place.

### Troubleshooting

| Symptom                                     | Fix                                                                                                            |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Menu entry not visible yet                  | Log out and back in, or run `kbuildsycoca6`                                                                    |
| `freecad-smart-launcher: command not found` | `~/.local/bin` is not on your `PATH`; the installer prints a warning for this. The menu entry still works      |
| Generic icon in the taskbar                 | Make sure no older, differently named `.desktop` file for the launcher exists in `~/.local/share/applications` |
| `FreeCAD Smart Launcher is running`         | Close the launcher, then run the installer again. A stale `~/.freecad_launcher.lock` from a crash is ignored   |
| FreeCAD versions missing after a move       | You declined moving the existing content. Move the `*.AppImage` files into the new folder yourself          |
| Data folder reset after restarting the launcher | It was changed inside the launcher (0.0.4). Set it with `--data-dir DIR` instead                           |

---

## migrate-freecad-flatpak-config.sh

Copies FreeCAD settings and user data (addons, macros) from the Flathub Flatpak `org.freecad.FreeCAD` to the
native locations that AppImage builds use. If a native profile already exists, it lets you choose which of its
settings to keep.

### Where FreeCAD stores its data

Since 1.1, FreeCAD keeps one folder per `major.minor` version, named `v{major}-{minor}`
(`v1-1`, `v26-3`, ...). The Flatpak uses the same layout inside its sandbox folder.

| Kind                                         | Flatpak                                                   | Native (AppImage)               |
| -------------------------------------------- | --------------------------------------------------------- | ------------------------------- |
| Settings (`user.cfg`, `system.cfg`)          | `~/.var/app/org.freecad.FreeCAD/config/FreeCAD/v1-1/`     | `~/.config/FreeCAD/v1-1/`       |
| Data (`Mod`, `Macro`, addon Python packages) | `~/.var/app/org.freecad.FreeCAD/data/FreeCAD/v1-1/`       | `~/.local/share/FreeCAD/v1-1/`  |
| Cache                                        | `~/.var/app/org.freecad.FreeCAD/cache/FreeCAD/v1-1/Cache` | not copied, FreeCAD rebuilds it |

FreeCAD 1.0 and older store everything directly in `~/.config/FreeCAD` and `~/.local/share/FreeCAD`,
without a version folder.

### Usage

```bash
./migrate-freecad-flatpak-config.sh                    # newest version found in the Flatpak
./migrate-freecad-flatpak-config.sh -v 1.1             # a specific FreeCAD version
./migrate-freecad-flatpak-config.sh --list-versions    # show what exists on both sides
./migrate-freecad-flatpak-config.sh --dry-run          # show what would happen, change nothing
./migrate-freecad-flatpak-config.sh --keep-from ~/.config/FreeCAD/v1-1.bak-20261105-124525
```

| Option                   | Description                                                                              |
| ------------------------ | ---------------------------------------------------------------------------------------- |
| `-v`, `--version <ver>`  | FreeCAD version to migrate. Default: newest version in the Flatpak profile               |
| `--list-versions`        | List the versions found in the Flatpak and native profiles, then exit                    |
| `--dry-run`              | Print every command and the settings comparison without changing anything                |
| `--keep-from <dir>`      | Compare against this folder instead of the current native profile (for example a backup) |
| `-V`, `--script-version` | Print the script version                                                                 |
| `-h`, `--help`           | Print usage                                                                              |
| `FC_VER=<ver>`           | Environment variable alternative to `-v`                                                 |

### Version selection

| Input                                   | Resolves to                                                          |
| --------------------------------------- | -------------------------------------------------------------------- |
| `1.1`, `v1-1`, `1.1.4`, `--version=1.1` | `v1-1` (the patch number is ignored; settings are per `major.minor`) |
| `26.3`, `26.3.0`, `v26-3`               | `v26-3`                                                              |
| `1.0`, `0.21`                           | Unversioned 1.0-and-older profile                                    |
| a version that is not in the Flatpak    | Refused, with the list of available versions                         |
| anything else (`banana`)                | Refused with an error                                                |

Each version is copied into the **same** version on the native side. Upgrading settings between versions
(for example 1.1 to 26.3) is left to FreeCAD, which offers its own migration the first time a new version starts.

When migrating a 1.0-or-older profile, only the unversioned files are replaced. Any existing `v*-*` folders
next to them are left exactly where they are.

### Keeping existing settings

If the native side already has a `user.cfg` (for example because the AppImage was started once before
migrating), the script compares it with the Flatpak settings and asks what to keep. The Flatpak value
is used wherever you answer no.

```text
 ◆ Existing settings

   Existing profile differs from the Flatpak in 8 setting(s).
   Flatpak values win unless you choose to keep the existing ones.

    A  Toolbar & window layout (4: toolbar rows/positions, docks, icon size)
    S  Start page on startup   ShowOnStartup 0 → 1
    1  Prefs/RecentFiles  MRU0: /home/dani/new.FCStd → /home/dani/old.FCStd
    2  Prefs/View  2: BackgroundColor, UseAntialiasing

   Keep existing toolbar & window layout? [y/N]
   Keep existing Start page setting? [y/N]
   Keep existing for which others? e.g. 1 3 5-7 · all · Enter = none
```

| Entry  | Contents                                                                                                                                      | Question                                                     |
| ------ | --------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `A`    | Toolbar and window layout: `MainWindowState`, `Geometry`, toolbar visibility, status/menu bar widgets, docks, toolbar icon size, toolbar lock | One yes/no. These settings only make sense together          |
| `S`    | `Mod/Start/ShowOnStartup`                                                                                                                     | One yes/no                                                   |
| `1..n` | Every other differing setting, grouped by preference section, with the old and new value for single settings                                  | Type numbers and ranges: `1 3 5-7`, `all`, or Enter for none |

Behaviour details:

- Invalid input is rejected and the question is asked again.
- `Ctrl-D` counts as "no" / "none". `Ctrl-C` stops the questions and keeps the Flatpak settings.
- Without a terminal (piped or scripted), nothing is asked and the Flatpak settings are used.
- `--dry-run` shows the same comparison without asking.
- The layout settings come from FreeCAD's own source (`MainWindow.cpp`, `ToolBarManager.cpp`,
  `DockWindowManager.cpp`). FreeCAD Smart Launcher itself does not change toolbar settings.

### Paths and warnings

Settings that point into the Flatpak sandbox folder (`~/.var/app/org.freecad.FreeCAD/{data,config,cache}`)
are rewritten to the native equivalents, for example the macro folder.

Values that cannot be fixed safely by text replacement are listed after the run instead of guessed:

| Pattern                          | Typical cause                                                                             | What to do                                                         |
| -------------------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| `/app/...`                       | Tools or examples inside the Flatpak, such as `/app/bin/ccx` or `/app/share/examples/...` | Recent Files entries: ignore. Tool paths: set them in Preferences  |
| `/run/user/<uid>/doc/...`        | Files opened through the Flatpak file picker                                              | Reopen those files once                                            |
| `AdditionalPythonPackages/py3XX` | Addon dependencies installed for the Flatpak's Python version                             | If an addon fails, reinstall its dependencies in the Addon Manager |

### Safety and rollback

- The Flatpak profile is only read, never modified. It stays usable until you remove the Flatpak.
- The script refuses to run while any FreeCAD process is open.
- Anything it replaces is moved, not deleted:

| Replaced                        | Backup                                                                                      |
| ------------------------------- | ------------------------------------------------------------------------------------------- |
| `~/.config/FreeCAD/v1-1`        | `~/.config/FreeCAD/v1-1.bak-<timestamp>`                                                    |
| `~/.local/share/FreeCAD/v1-1`   | `~/.local/share/FreeCAD/v1-1.bak-<timestamp>`                                               |
| Unversioned 1.0-and-older files | `~/.config/FreeCAD.legacy.bak-<timestamp>`, `~/.local/share/FreeCAD.legacy.bak-<timestamp>` |

To roll back a 1.1 migration:

```bash
rm -rf ~/.config/FreeCAD/v1-1 ~/.local/share/FreeCAD/v1-1
mv ~/.config/FreeCAD/v1-1.bak-<timestamp>       ~/.config/FreeCAD/v1-1
mv ~/.local/share/FreeCAD/v1-1.bak-<timestamp>  ~/.local/share/FreeCAD/v1-1   # if it exists
```

### Common workflows

**First migration.** Close FreeCAD, preview, then run:

```bash
./migrate-freecad-flatpak-config.sh --dry-run
./migrate-freecad-flatpak-config.sh
```

**Get back the toolbar layout from before a migration.** Point `--keep-from` at the backup and answer `y` to `A`:

```bash
./migrate-freecad-flatpak-config.sh -v 1.1 --keep-from ~/.config/FreeCAD/v1-1.bak-<timestamp>
```

**Migrate a different FreeCAD version.**

```bash
./migrate-freecad-flatpak-config.sh --list-versions
./migrate-freecad-flatpak-config.sh -v 26.3
```

After migrating, start FreeCAD from the launcher with **Vanilla launch** turned off. That option starts FreeCAD
with an empty temporary profile and would ignore the migrated settings.

---

## Exit codes

| Code  | `install-freecad-smart-launcher.sh`                                               | `migrate-freecad-flatpak-config.sh`                     |
| ----- | --------------------------------------------------------------------------------- | ------------------------------------------------------- |
| `0`   | Success, or `--help` / `--version`                                                | Success, or `--help` / `--list-versions` / `-V`         |
| `1`   | File missing or not an AppImage, rejected data folder, or launcher running        | No Flatpak profile, unknown version, or FreeCAD running |
| `2`   | Wrong arguments                                                                   | Unknown option                                          |
| other | A step failed: the failing command's exit code, plus `failed at line N` on stderr | Same                                                    |

## Output

Both scripts print one line per step with the path it touched. Colors switch off automatically when output
is piped or redirected, when `NO_COLOR` is set, or when `TERM=dumb`, so logs stay clean.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## References

- [FreeCAD Smart Launcher](https://github.com/deltahedra3d/freecad-launcher)
- [FreeCAD: `src/App/ApplicationDirectories.cpp`](https://github.com/FreeCAD/FreeCAD/blob/main/src/App/ApplicationDirectories.cpp) (versioned folders)
- [FreeCAD: `src/Gui/MainWindow.cpp`](https://github.com/FreeCAD/FreeCAD/blob/main/src/Gui/MainWindow.cpp) and
  [`src/Gui/ToolBarManager.cpp`](https://github.com/FreeCAD/FreeCAD/blob/main/src/Gui/ToolBarManager.cpp) (window and toolbar layout)
- [FreeCAD wiki: Version Migration](https://wiki.freecad.org/Version_Migration)
