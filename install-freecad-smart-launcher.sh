#!/usr/bin/env bash
# install-freecad-smart-launcher.sh  v1.0.0
#
# Install / update / uninstall FreeCAD Smart Launcher (AppImage) as a proper
# per-user desktop app: stable path, menu entry, themed icon, PATH command,
# correct Wayland taskbar icon. No root needed.
#
#   ./install-freecad-smart-launcher.sh ~/Downloads/FreeCAD_Smart_Launcher-*-linux-x86_64.AppImage
#   ./install-freecad-smart-launcher.sh --uninstall
#   ./install-freecad-smart-launcher.sh --version | --help
set -euo pipefail

SCRIPT_VERSION="1.0.0"
APP_ID="freecad-smart-launcher"      # == AppImage's internal binary name == Wayland app_id
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
OPT_DIR="$HOME/.local/opt/$APP_ID"   # NOT ~/Applications/FreeCAD: the launcher lists every *.AppImage there
APPIMAGE="$OPT_DIR/$APP_ID.AppImage" # stable, version-less name: in-app self-update replaces this file in place
DESKTOP="$DATA/applications/$APP_ID.desktop"
ICON="$DATA/icons/hicolor/256x256/apps/$APP_ID.png"
BIN_LINK="$HOME/.local/bin/$APP_ID"

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
die()    { printf '\n %s%s✖ %s%s\n\n' "$B" "$RED" "$1" "$R" >&2; exit 1; }
done_()  { printf '\n %s%s✔ %s%s\n' "$B" "$GRN" "$1" "$R"; }
trap 'printf "\n %s%s✖ failed at line %s%s\n" "$B" "$RED" "$LINENO" "$R" >&2' ERR

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

usage() { printf 'usage: %s <FreeCAD_Smart_Launcher-*.AppImage> | --uninstall | --version | --help\n' "${0##*/}" >&2; exit 2; }

case "${1:-}" in
  -V|--version) printf '%s %s\n' "${0##*/}" "$SCRIPT_VERSION"; exit 0 ;;
  -h|--help)    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  -*)           [[ "$1" == --uninstall ]] || usage ;;
esac

# ---------- uninstall ----------
if [[ "${1:-}" == "--uninstall" ]]; then
  banner "uninstall"
  rm_item "Menu entry"   "$DESKTOP"
  rm_item "Icon"         "$ICON"
  rm_item "Command link" "$BIN_LINK"
  rm_item "AppImage"     "$OPT_DIR"
  refresh_menus
  done_ "Removed."
  printf '   %sFreeCAD builds & config in ~/Applications/FreeCAD were left untouched.%s\n\n' "$D" "$R"
  exit 0
fi

# ---------- install / update ----------
[[ $# -eq 1 ]] || usage
SRC="$1"
action="install"; [[ -f "$APPIMAGE" ]] && action="update"
banner "$action"

step "Checking AppImage"
[[ -f "$SRC" ]] || die "File not found: $SRC"
# ELF + AppImage type-2 magic ("AI" at offset 8)
[[ "$(head -c 4 "$SRC" | od -An -c | tr -d ' ')" == "177ELF" && "$(dd if="$SRC" bs=1 skip=8 count=2 2>/dev/null)" == "AI" ]] \
  || die "Not an AppImage: $SRC"
ok "$(du -h "$SRC" | cut -f1) · ${SRC##*/}"

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

refresh_menus

if [[ "$action" == update ]]; then done_ "Updated."; else done_ "Installed."; fi
printf '   %sStart it from the app menu, or run %s%s%s\n' "$D" "$R$CYN" "$APP_ID" "$R"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *)
  printf '   %s⚠ ~/.local/bin is not on your PATH; the menu entry still works.%s\n' "$YLW" "$R" ;;
esac
echo
