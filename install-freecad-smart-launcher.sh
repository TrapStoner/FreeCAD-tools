#!/usr/bin/env bash
# install-freecad-smart-launcher.sh  v1.1.0
#
# Install / update / uninstall FreeCAD Smart Launcher (AppImage) as a proper
# per-user desktop app: stable path, menu entry, themed icon, PATH command,
# correct Wayland taskbar icon, and a choice of where the launcher keeps its data. No root needed.
#
#   ./install-freecad-smart-launcher.sh <FreeCAD_Smart_Launcher-*.AppImage>   # asks about the data folder
#   ./install-freecad-smart-launcher.sh <AppImage> --default-data-dir         # don't ask, keep current/default
#   ./install-freecad-smart-launcher.sh <AppImage> --data-dir /mnt/big/FreeCAD
#   ./install-freecad-smart-launcher.sh --uninstall
#   ./install-freecad-smart-launcher.sh --version | --help
set -euo pipefail

SCRIPT_VERSION="1.1.0"
APP_ID="freecad-smart-launcher"      # == AppImage's internal binary name == Wayland app_id
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
OPT_DIR="$HOME/.local/opt/$APP_ID"   # NOT inside the launcher data folder: it lists every *.AppImage there
APPIMAGE="$OPT_DIR/$APP_ID.AppImage" # stable, version-less name: in-app self-update replaces this file in place
DESKTOP="$DATA/applications/$APP_ID.desktop"
ICON="$DATA/icons/hicolor/256x256/apps/$APP_ID.png"
BIN_LINK="$HOME/.local/bin/$APP_ID"

# Launcher internals (freecad_smart_launcher_linux.py): default data folder, the config it probes
# first inside it, the home-level config it probes second, and its single-instance lock.
DEFAULT_DATA_DIR="$HOME/Applications/FreeCAD"
HOME_CFG="$HOME/.freecad_launcher_config.json"
LOCK_FILE="$HOME/.freecad_launcher.lock"

# ---------- output styling (auto-off when piped or NO_COLOR is set) ----------
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
  B=$'\e[1m' D=$'\e[2m' R=$'\e[0m'
  RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' MAG=$'\e[35m' CYN=$'\e[36m'
else
  B='' D='' R='' RED='' GRN='' YLW='' BLU='' MAG='' CYN=''
fi
tilde() { printf '%s' "${1/#$HOME/\~}"; }
banner() { printf '\n %s%s◆ FreeCAD Smart Launcher%s %s· %s · installer v%s%s\n\n' "$B" "$MAG" "$R" "$D" "$1" "$SCRIPT_VERSION" "$R"; }
step()   { printf ' %s▸%s %-22s' "$BLU" "$R" "$1"; }
ok()     { printf '%s✔%s %s%s%s\n' "$GRN" "$R" "$D" "${1:-}" "$R"; }
skip()   { printf '%s–%s %s%s%s\n' "$YLW" "$R" "$D" "${1:-}" "$R"; }
note()   { printf '   %s%s%s\n' "$D" "$1" "$R"; }
warn()   { printf '   %s⚠ %s%s\n' "$YLW" "$1" "$R"; }
die()    { printf '\n %s%s✖ %s%s\n\n' "$B" "$RED" "$1" "$R" >&2; exit 1; }
done_()  { printf '\n %s%s✔ %s%s\n' "$B" "$GRN" "$1" "$R"; }
trap 'printf "\n %s%s✖ failed at line %s%s\n" "$B" "$RED" "$LINENO" "$R" >&2' ERR

usage() {
  printf 'usage: %s <FreeCAD_Smart_Launcher-*.AppImage> [--default-data-dir | --data-dir DIR]\n' "${0##*/}" >&2
  printf '       %s --uninstall | --version | --help\n' "${0##*/}" >&2
  exit 2
}

# ---------- arguments ----------
SRC=""; MODE="install"; DATA_CHOICE="ask"; DATA_ARG=""
while (( $# )); do
  case "$1" in
    -V|--version)       printf '%s %s\n' "${0##*/}" "$SCRIPT_VERSION"; exit 0 ;;
    -h|--help)          sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --uninstall)        MODE="uninstall" ;;
    --default-data-dir) DATA_CHOICE="keep" ;;
    --data-dir)         DATA_CHOICE="set"; DATA_ARG="${2:?--data-dir needs a directory}"; shift ;;
    --data-dir=*)       DATA_CHOICE="set"; DATA_ARG="${1#*=}" ;;
    -*)                 usage ;;
    *)                  [[ -z "$SRC" ]] || usage; SRC="$1" ;;
  esac; shift
done

# ---------- launcher data folder helpers ----------
# Resolve the folder the launcher will actually use, the same way it does on startup.
current_data_dir() {
  python3 -I - "$DEFAULT_DATA_DIR" "$HOME_CFG" <<'PY' 2>/dev/null || printf '%s' "$DEFAULT_DATA_DIR"
import json, os, sys
default, home_cfg = sys.argv[1:3]
install_dir = default
for p in (os.path.join(default, "launcher_config.json"), home_cfg):
    try:
        with open(p, encoding="utf-8") as f:
            d = json.load(f)
        if isinstance(d, dict):
            install_dir = d.get("install_dir") or install_dir
            break
    except Exception:
        pass
print(install_dir, end="")
PY
}

# Point the launcher at NEW: write NEW/launcher_config.json (paths rewritten OLD→NEW), make the
# launcher find it on startup, and fix "FreeCAD x.y" menu entries the launcher created.
apply_data_dir() {  # apply_data_dir <old> <new> <content_moved 0|1>
  python3 -I - "$1" "$2" "$3" "$DEFAULT_DATA_DIR" "$HOME_CFG" "$DATA/applications" "$APP_ID" <<'PY'
import glob, json, os, sys
old, new, moved, default, home_cfg, apps, app_id = sys.argv[1:8]
moved = moved == "1"
CFG = "launcher_config.json"

def load(p):
    try:
        with open(p, encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}

def swap(v):
    if isinstance(v, str) and (v == old or v.startswith(old + os.sep)):
        return new + v[len(old):]
    if isinstance(v, list):
        return [swap(x) for x in v]
    if isinstance(v, dict):
        return {k: swap(x) for k, x in v.items()}
    return v

cfg = load(os.path.join(new, CFG)) or load(os.path.join(old, CFG))
if moved:  # FreeCAD versions now live in NEW, so stored paths to them follow
    cfg = swap(cfg)
cfg["install_dir"] = new
os.makedirs(new, exist_ok=True)
with open(os.path.join(new, CFG), "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)

# The launcher reads <default>/launcher_config.json first, then ~/.freecad_launcher_config.json.
# For a non-default folder: drop the default-folder config (it would win) and leave a pointer in ~.
# The pointer survives because the launcher only deletes it when it was the file it loaded last.
default_cfg = os.path.join(default, CFG)
if os.path.normpath(new) == os.path.normpath(default):
    if os.path.isfile(home_cfg):
        os.remove(home_cfg)
else:
    if os.path.isfile(default_cfg):
        os.remove(default_cfg)
    with open(home_cfg, "w", encoding="utf-8") as f:
        json.dump({"install_dir": new}, f, indent=2)

# Launcher-made menu entries: Exec=<path with spaces escaped as "\ "> %F
if not moved:  # versions stayed in OLD: their menu entries are still correct
    print(0, end=""); sys.exit(0)
esc = lambda p: p.replace("\\", "\\\\").replace(" ", "\\ ")
fixed = 0
for path in glob.glob(os.path.join(apps, "freecad-*.desktop")):
    if os.path.basename(path) == f"{app_id}.desktop":
        continue
    with open(path, encoding="utf-8") as f:
        text = f.read()
    out = []
    for line in text.splitlines(keepends=True):
        if line.startswith(("Exec=", "TryExec=")):
            line = line.replace(esc(old) + "/", esc(new) + "/")
        out.append(line)
    out = "".join(out)
    if out != text:
        with open(path, "w", encoding="utf-8") as f:
            f.write(out)
        fixed += 1
print(fixed, end="")
PY
}

resolve_dir() {  # ~ expansion + absolute + normalized, without requiring existence
  local p="$1"; p="${p/#\~/$HOME}"; [[ "$p" == /* ]] || p="$PWD/$p"
  realpath -m -- "$p"
}
# Echo an error string when NEW isn't usable as the data folder (empty = fine)
check_dir() {  # check_dir <new> <old>
  local new="$1" old="$2"
  [[ "$new" == "/" || "$new" == "$HOME" ]] && { echo "That is too broad, pick a dedicated folder"; return; }
  [[ "$new" == "$old" ]] && { echo "That is already the current folder"; return; }
  [[ "$new" == "$OPT_DIR" || "$new" == "$OPT_DIR"/* ]] && { echo "Can't be inside the launcher's own install folder"; return; }
  [[ "$new" == "$old"/* || "$old" == "$new"/* ]] && { echo "Can't be inside, or a parent of, the current folder"; return; }
  [[ -e "$new" && ! -d "$new" ]] && { echo "Exists and is not a folder"; return; }
  # writable check on the nearest existing parent; the folder itself is created only when the move happens
  local anc="$new"; while [[ ! -e "$anc" ]]; do anc="$(dirname -- "$anc")"; done
  [[ -d "$anc" && -w "$anc" ]] || { echo "Can't create or write to it"; return; }
}
launcher_running() {
  [[ -f "$LOCK_FILE" ]] || return 1
  local pid; pid="$(tr -dc '0-9' <"$LOCK_FILE")"
  [[ -n "$pid" && -d "/proc/$pid" ]]
}
ask_yn() {  # ask_yn <question> <default Y|N>; returns 0 for yes
  local a hint="[Y/n]"; [[ "$2" == N ]] && hint="[y/N]"
  while true; do
    read -r -p "   $1 $D$hint$R " a || a=""
    a="${a,,}"
    [[ -z "$a" ]] && { [[ "$2" == Y ]]; return; }
    [[ "$a" == y || "$a" == yes ]] && return 0
    [[ "$a" == n || "$a" == no ]] && return 1
  done
}

refresh_menus() {
  step "Refreshing menus"
  command -v update-desktop-database >/dev/null && update-desktop-database -q "$DATA/applications" || true
  if command -v kbuildsycoca6 >/dev/null; then kbuildsycoca6 >/dev/null 2>&1 || true; ok "KDE cache rebuilt"
  else ok; fi
}

rm_item() {  # rm_item <label> <path>
  step "$1"
  if [[ -e "$2" || -L "$2" ]]; then rm -rf "$2"; ok "$(tilde "$2")"; else skip "not present"; fi
}

# ---------- uninstall ----------
if [[ "$MODE" == uninstall ]]; then
  [[ -z "$SRC" && "$DATA_CHOICE" == ask ]] || usage
  banner "uninstall"
  rm_item "Menu entry"   "$DESKTOP"
  rm_item "Icon"         "$ICON"
  rm_item "Command link" "$BIN_LINK"
  rm_item "AppImage"     "$OPT_DIR"
  refresh_menus
  done_ "Removed."
  note "Launcher data folder left untouched: $(tilde "$(current_data_dir)")"
  echo
  exit 0
fi

# ---------- install / update ----------
[[ -n "$SRC" ]] || usage
action="install"; [[ -f "$APPIMAGE" ]] && action="update"
banner "$action"

step "Checking AppImage"
[[ -f "$SRC" ]] || die "File not found: $SRC"
# ELF + AppImage type-2 magic ("AI" at offset 8)
[[ "$(head -c 4 "$SRC" | od -An -c | tr -d ' ')" == "177ELF" && "$(dd if="$SRC" bs=1 skip=8 count=2 2>/dev/null)" == "AI" ]] \
  || die "Not an AppImage: $SRC"
ok "$(du -h "$SRC" | cut -f1) · ${SRC##*/}"

# ---------- launcher data folder: decide before changing anything ----------
OLD_DATA="$(current_data_dir)"; NEW_DATA="$OLD_DATA"; MOVE_DATA=0
if [[ "$DATA_CHOICE" != keep ]] && ! command -v python3 >/dev/null; then
  [[ "$DATA_CHOICE" == set ]] && die "python3 is needed to change the data folder"
  DATA_CHOICE="keep"
fi
if [[ "$DATA_CHOICE" == set ]]; then
  NEW_DATA="$(resolve_dir "$DATA_ARG")"
  if [[ "$NEW_DATA" != "$OLD_DATA" ]]; then
    err="$(check_dir "$NEW_DATA" "$OLD_DATA")"; [[ -z "$err" ]] || die "Data folder $(tilde "$NEW_DATA"): $err"
    MOVE_DATA=1
  fi
elif [[ "$DATA_CHOICE" == ask && -t 0 ]]; then
  n_ver=0; size="empty"
  if [[ -d "$OLD_DATA" ]]; then
    n_ver="$(find "$OLD_DATA" -maxdepth 1 -name '*.AppImage' | wc -l)"
    size="$(du -sh "$OLD_DATA" 2>/dev/null | cut -f1)"
  fi
  printf '\n %s%s◆ Launcher data folder%s\n' "$B" "$CYN" "$R"
  note "Where the launcher keeps what it downloads and tracks:"
  note "  · every FreeCAD version installed through it (stable, weekly, RC), one AppImage each"
  note "  · its settings (launcher_config.json) and usage stats (time_tracker.json)"
  note "Pick a roomy disk if you keep many versions; every *.AppImage in it is listed as a FreeCAD version."
  printf '   Current: %s%s%s %s(%s FreeCAD version(s), %s)%s\n\n' "$CYN" "$(tilde "$OLD_DATA")" "$R" "$D" "$n_ver" "$size" "$R"
  if ! ask_yn "Keep this folder?" Y; then
    while true; do
      read -r -e -p "   New folder (Tab completes, Enter cancels): " ans || ans=""
      [[ -z "$ans" ]] && { note "Keeping $(tilde "$OLD_DATA")"; break; }
      cand="$(resolve_dir "$ans")"
      err="$(check_dir "$cand" "$OLD_DATA")"
      if [[ -z "$err" ]]; then NEW_DATA="$cand"; MOVE_DATA=1; break; fi
      warn "$err"
    done
  fi
  echo
elif [[ "$DATA_CHOICE" == ask ]]; then
  note "No terminal to ask: keeping launcher data folder $(tilde "$OLD_DATA")"
fi
MOVE_CONTENT=0
if (( MOVE_DATA )); then
  launcher_running && die "FreeCAD Smart Launcher is running. Close it, then run the installer again."
  movable=0  # the current folder may not exist yet (launcher never ran)
  if [[ -d "$OLD_DATA" ]]; then
    movable="$(find "$OLD_DATA" -mindepth 1 -maxdepth 1 ! -name launcher_config.json ! -name time_tracker.json | wc -l)"
  fi
  if (( movable > 0 )); then
    if [[ "$DATA_CHOICE" == set || ! -t 0 ]]; then MOVE_CONTENT=1
    else
      n_ver="$(find "$OLD_DATA" -maxdepth 1 -name '*.AppImage' | wc -l)"
      ask_yn "Move existing content ($n_ver FreeCAD version(s), $(du -sh "$OLD_DATA" | cut -f1)) to the new folder?" Y && MOVE_CONTENT=1
      (( MOVE_CONTENT )) || note "Left in $(tilde "$OLD_DATA"); those versions won't show in the launcher."
      echo
    fi
  fi
fi

step "Installing AppImage"
install -Dm755 "$SRC" "$APPIMAGE"
ok "$(tilde "$APPIMAGE")"

step "Extracting icon"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
( cd "$tmp" && "$APPIMAGE" --appimage-extract "$APP_ID.png" >/dev/null )
[[ -f "$tmp/squashfs-root/$APP_ID.png" ]] || die "Icon not found inside the AppImage"
install -Dm644 "$tmp/squashfs-root/$APP_ID.png" "$ICON"
ok "$(tilde "$ICON")"

step "Linking command"
mkdir -p "$(dirname "$BIN_LINK")"
ln -sfn "$APPIMAGE" "$BIN_LINK"
ok "$(tilde "$BIN_LINK")"

step "Writing menu entry"
mkdir -p "$(dirname "$DESKTOP")"
cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Version=1.5
Name=FreeCAD Smart Launcher
GenericName=FreeCAD Version Manager
Comment=Manage FreeCAD stable/weekly builds, test pull requests, browse projects
Exec="$APPIMAGE"
TryExec=$APPIMAGE
Icon=$APP_ID
Terminal=false
Categories=Graphics;3DGraphics;Engineering;
Keywords=FreeCAD;CAD;AppImage;weekly;launcher;
StartupNotify=true
StartupWMClass=$APP_ID
EOF
chmod 644 "$DESKTOP"
ok "$(tilde "$DESKTOP")"

step "Data folder"
if (( MOVE_DATA )); then
  mkdir -p "$NEW_DATA"
  skipped=()
  # settings + stats always follow; the rest only if chosen
  while IFS= read -r -d '' e; do
    base="${e##*/}"
    if (( ! MOVE_CONTENT )) && [[ "$base" != launcher_config.json && "$base" != time_tracker.json ]]; then continue; fi
    if [[ -e "$NEW_DATA/$base" && "$base" != launcher_config.json ]]; then skipped+=("$base"); continue; fi
    [[ "$base" == launcher_config.json && -e "$NEW_DATA/$base" ]] && continue
    mv -- "$e" "$NEW_DATA/"
  done < <(find "$OLD_DATA" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
  fixed="$(apply_data_dir "$OLD_DATA" "$NEW_DATA" "$MOVE_CONTENT")"
  # tidy up only what's empty; the parent only when it's the default ~/Applications
  if rmdir "$OLD_DATA" 2>/dev/null && [[ "$OLD_DATA" == "$DEFAULT_DATA_DIR" ]]; then
    rmdir "$(dirname "$OLD_DATA")" 2>/dev/null || true
  fi
  ok "$(tilde "$NEW_DATA")$( (( fixed > 0 )) && printf '  (%s FreeCAD menu entr%s updated)' "$fixed" "$( (( fixed == 1 )) && echo y || echo ies)")"
  for s in "${skipped[@]}"; do warn "Not moved, already exists in the new folder: $s"; done
else
  ok "$(tilde "$OLD_DATA")"
fi

refresh_menus

if [[ "$action" == update ]]; then done_ "Updated."; else done_ "Installed."; fi
printf '   %sStart it from the app menu, or run %s%s%s\n' "$D" "$R$CYN" "$APP_ID" "$R"
(( MOVE_DATA )) && note "Change the data folder later by re-running with --data-dir DIR, not from inside the launcher."
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *)
  printf '   %s⚠ ~/.local/bin is not on your PATH; the menu entry still works.%s\n' "$YLW" "$R" ;;
esac
echo
