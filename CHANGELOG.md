# Changelog

All notable changes to the scripts in this repository are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and each script follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) independently. The version of a script is in its
header comment, its `SCRIPT_VERSION` variable, and its banner line, and is printed by `-V`.

| Script                              | Current version                                             |
| ----------------------------------- | ----------------------------------------------------------- |
| `install-freecad-smart-launcher.sh` | [1.1.0](#install-freecad-smart-launchersh-110---2026-11-05) |
| `migrate-freecad-flatpak-config.sh` | [1.0.2](#migrate-freecad-flatpak-configsh-102---2026-11-06) |

---

## install-freecad-smart-launcher.sh 1.1.0 - 2026-11-05

### Added

- Launcher data folder step on install and update. It explains what the folder holds (FreeCAD versions,
  `launcher_config.json`, `time_tracker.json`), shows the current folder with its version count and size, and
  asks whether to keep it.
- New folder input with Tab completion, `~` expansion and validation. Rejected: `/`, the home folder, the
  launcher's own install folder, and folders inside or above the current data folder. Invalid answers are
  explained and asked again; an empty answer cancels.
- Optional move of existing content to the new folder. Settings and statistics always move; FreeCAD versions
  move only when confirmed.
- Menu entries the launcher created for FreeCAD versions are updated to the new paths when those versions move,
  including paths with spaces.
- `--default-data-dir` to skip the question and keep the current folder.
- `--data-dir <dir>` to set the folder without asking, moving existing content.
- Check that the launcher is closed before changing the data folder.

### Changed

- A custom data folder is stored in the new folder's `launcher_config.json`, with a pointer in
  `~/.freecad_launcher_config.json`. The launcher keeps this setting across restarts, unlike a folder changed
  inside the launcher (0.0.4 code), which is forgotten on restart.
- `--uninstall` reports the actual data folder it left in place instead of assuming `~/Applications/FreeCAD`.
- Arguments can be given in any order.

### Fixed

- `--help` printed one line of code after the usage text.

### Safety

- Existing files in the new folder are never overwritten; they are listed as not moved.
- Only empty folders are removed after a move, and the parent only when it is the default `~/Applications`.
- Without a terminal, nothing is asked and the current folder is kept.

## install-freecad-smart-launcher.sh 1.0.0 - 2026-11-05

### Added

- Per-user install, update and uninstall of the FreeCAD Smart Launcher AppImage, without root.
- Fixed, version-less install path `~/.local/opt/freecad-smart-launcher/freecad-smart-launcher.AppImage`, so the
  launcher's built-in self-updater keeps the menu entry valid.
- Menu entry `freecad-smart-launcher.desktop`, named after the AppImage's binary so the Wayland taskbar icon and
  window grouping are correct.
- 256 px icon extracted from the AppImage without FUSE.
- Terminal command `~/.local/bin/freecad-smart-launcher`, with a warning when `~/.local/bin` is not on `PATH`.
- AppImage validation before anything is written.
- Menu refresh through `update-desktop-database` and `kbuildsycoca6` when available.
- Colored, one-line-per-step output that switches off when piped, with `NO_COLOR`, or with `TERM=dumb`.
- `-V` / `--version` and `-h` / `--help`.

## migrate-freecad-flatpak-config.sh 1.0.2 - 2026-11-06

### Fixed

- A `user.cfg` that cannot be read (truncated, empty or hand-edited) is now reported and the comparison is
  skipped, instead of ending in a Python traceback after the profile was replaced. The Flatpak settings are used
  and the unreadable file stays in the backup.

## migrate-freecad-flatpak-config.sh 1.0.1 - 2026-11-06

### Fixed

- A Flatpak profile without a `user.cfg` no longer crashes the settings step (`failed at line 319` in a dry run,
  an error in the merge in a real run). The existing native settings are kept as they are and the run says so.

## migrate-freecad-flatpak-config.sh 1.0.0 - 2026-11-05

### Added

- Copy of FreeCAD settings (`user.cfg`, `system.cfg`) and user data (addons, macros) from the
  `org.freecad.FreeCAD` Flatpak to the native locations used by AppImage builds. The cache is not copied.
- Version selection with `-v` / `--version`, accepting `1.1`, `26.3`, `v1-1`, `1.1.4` and similar. Defaults to
  the newest version in the Flatpak profile.
- `--list-versions` showing the versions found in the Flatpak and native profiles.
- Support for unversioned FreeCAD 1.0-and-older profiles, replacing only the unversioned files and leaving newer
  version folders untouched.
- Interactive merge when a native profile already exists: one question for the toolbar and window layout, one
  for the Start page setting, and the remaining differences grouped by preference section and selected by
  number or range (`1 3 5-7`, `all`, Enter for none).
- `--keep-from <dir>` to compare against another profile, for example a backup.
- `--dry-run` printing every command and the settings comparison without changing anything.
- Rewriting of sandbox paths (`~/.var/app/org.freecad.FreeCAD/{data,config,cache}`) to their native
  equivalents.
- Report of paths that need manual attention: `/app/...`, `/run/user/<uid>/doc/...`, and addon Python packages
  installed for the Flatpak's Python.
- Refusal to run while FreeCAD is open.
- `-V` / `--script-version` and `-h` / `--help`, plus `FC_VER` as an alternative to `-v`.

### Safety

- The Flatpak profile is only read, never modified.
- Everything replaced on the native side is moved to a `.bak-<timestamp>` (or `.legacy.bak-<timestamp>`) folder.
- `Ctrl-D` at a question counts as "no", `Ctrl-C` stops the questions and keeps the Flatpak settings, and
  without a terminal the Flatpak settings are used without asking.
