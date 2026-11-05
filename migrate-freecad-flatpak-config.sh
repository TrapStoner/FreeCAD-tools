#!/usr/bin/env bash
# migrate-freecad-flatpak-config.sh  v1.0.0
#
# Copy FreeCAD settings + user data from the Flathub Flatpak (org.freecad.FreeCAD)
# to the native locations used by AppImage builds (e.g. ones run by FreeCAD Smart Launcher).
# If a native profile already exists, you choose which of its settings to keep
# (toolbar/window layout, Start page, then any other differing settings by number).
# The Flatpak copy is never modified; the replaced native profile is kept as .bak-<stamp>.
#
#   ./migrate-freecad-flatpak-config.sh                  # newest version found in the Flatpak profile
#   ./migrate-freecad-flatpak-config.sh -v 1.1           # pick a version: 1.0, 1.1, 26.3, 27.2, v1-1, 1.1.4 …
#   ./migrate-freecad-flatpak-config.sh --list-versions  # what the Flatpak and native profiles contain
#   ./migrate-freecad-flatpak-config.sh --dry-run        # show what would happen
#   ./migrate-freecad-flatpak-config.sh --keep-from ~/.config/FreeCAD/v1-1.bak-20261105-124525
#   ./migrate-freecad-flatpak-config.sh -V | --help      # script version / this help
#
# Versions 1.1+ use per-version folders (v1-1, v26-3…). 1.0 and older share one
# unversioned folder; those are migrated as-is and newer FreeCAD offers its own upgrade on start.
set -euo pipefail

SCRIPT_VERSION="1.0.0"
VER_ARG="${FC_VER:-}"; DRY=0; KEEP_FROM=""; LIST=0
while (( $# )); do
  case "$1" in
    -v|--version)   VER_ARG="${2:?--version needs a value, e.g. 1.1 or 26.3}"; shift ;;
    --version=*)    VER_ARG="${1#*=}" ;;
    --list-versions) LIST=1 ;;
    --dry-run)      DRY=1 ;;
    --keep-from)    KEEP_FROM="${2:?--keep-from needs a directory}"; shift ;;
    -V|--script-version) printf '%s %s\n' "${0##*/}" "$SCRIPT_VERSION"; exit 0 ;;
    -h|--help)      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'unknown option: %s (see --help)\n' "$1" >&2; exit 2 ;;
  esac; shift
done
FP="$HOME/.var/app/org.freecad.FreeCAD"
NATIVE_CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
NATIVE_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
NATIVE_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
STAMP="$(date +%Y%m%d-%H%M%S)"
trap 'printf "\n ✖ failed at line %s\n" "$LINENO" >&2' ERR

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
  B=$'\e[1m' D=$'\e[2m' R=$'\e[0m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' MAG=$'\e[35m' CYN=$'\e[36m'
  export FCM_COLOR=1
else B='' D='' R='' RED='' GRN='' YLW='' BLU='' MAG='' CYN=''; export FCM_COLOR=0; fi
t()    { printf '%s' "${1/#$HOME/\~}"; }
step() { printf ' %s▸%s %-26s' "$BLU" "$R" "$1"; (( DRY )) && echo || true; }
ok()   { printf '%s✔%s %s%s%s\n' "$GRN" "$R" "$D" "${1:-}" "$R"; }
warn() { printf '%s⚠%s %s\n' "$YLW" "$R" "$1"; }
die()  { printf '\n %s%s✖ %s%s\n\n' "$B" "$RED" "$1" "$R" >&2; exit 1; }
run()  { if (( DRY )); then printf '   %s$ %s%s\n' "$D" "$*" "$R"; else "$@"; fi; }

# ---------------------------------------------------------------------------
# Settings merge helper (FreeCAD user.cfg is XML: nested FCParamGroup + typed leaves).
# argv: <keep.cfg> <target.cfg> <interactive|list>
# Target starts as the Flatpak settings; chosen settings from keep.cfg are written over it.
# ---------------------------------------------------------------------------
read -r -d '' MERGE_PY <<'PY' || true
import copy, os, re, sys
import xml.etree.ElementTree as ET

keep_path, target_path, mode = sys.argv[1:4]
C = os.environ.get("FCM_COLOR") == "1"
def c(code, s): return f"\033[{code}m{s}\033[0m" if C else s
B, D, CY, YL, GR = (lambda s: c(1, s)), (lambda s: c(2, s)), (lambda s: c(36, s)), (lambda s: c(33, s)), (lambda s: c(32, s))

LEAF = {"FCBool", "FCInt", "FCUInt", "FCFloat", "FCText"}
def flat(root):
    out = {}
    def walk(g, path):
        for ch in g:
            if ch.tag == "FCParamGroup":
                walk(ch, path + (ch.get("Name"),))
            elif ch.tag in LEAF:
                out[(path, ch.get("Name"))] = ch
    walk(root, ())
    return out
def val(e): return (e.text or "") if e.tag == "FCText" else e.get("Value", "")
def gpath(path): return "/".join(p for p in path if p != "Root")
def short(p):
    for a, b in (("BaseApp/Preferences/Mod/", "Mod/"), ("BaseApp/Preferences/", "Prefs/"), ("BaseApp/", "")):
        if p.startswith(a): return b + p[len(a):]
    return p
def clip(s, n=28):
    s = s.replace("\n", " ")
    return s if len(s) <= n else s[: n - 1] + "…"

# Where FreeCAD 1.1 stores toolbar/window layout (src/Gui/MainWindow.cpp, ToolBarManager.cpp, DockWindowManager.cpp)
LAYOUT_GENERAL = {"ToolbarIconSize", "LockToolBars", "StatusBarIconSize", "MenuBarIconSize"}
def is_layout(p, n):
    return (p.startswith("BaseApp/MainWindow") or p == "BaseApp/Preferences/MainWindow"
            or p.startswith("BaseApp/Preferences/DockWindows")
            or (p == "BaseApp/Preferences/General" and n in LAYOUT_GENERAL))
def is_start(p, n): return p == "BaseApp/Preferences/Mod/Start" and n == "ShowOnStartup"

keep_tree, target_tree = ET.parse(keep_path), ET.parse(target_path)
old, new = flat(keep_tree.getroot()), flat(target_tree.getroot())
diffs = [k for k, e in old.items() if k not in new or new[k].tag != e.tag or val(new[k]) != val(e)]
if not diffs:
    print(f"   {D('No differences: existing settings already match the Flatpak.')}")
    sys.exit(0)

layout = [k for k in diffs if is_layout(gpath(k[0]), k[1])]
start = [k for k in diffs if is_start(gpath(k[0]), k[1])]
groups = {}
for k in diffs:
    if k in layout or k in start: continue
    groups.setdefault(gpath(k[0]), []).append(k)
others = sorted(groups.items())

def change(k):
    o = val(old[k]); n = val(new[k]) if k in new else None
    return f"{clip(o)} {D('→')} {clip(n) if n is not None else D('(not set)')}"

print(f"   Existing profile differs from the Flatpak in {B(str(len(diffs)))} setting(s).")
print(f"   {D('Flatpak values win unless you choose to keep the existing ones.')}\n")

numbered = []
if layout:
    print(f"   {B(' A')}  {CY('Toolbar & window layout')} {D(f'({len(layout)}: toolbar rows/positions, docks, icon size)')}")
if start:
    print(f"   {B(' S')}  {CY('Start page on startup')}   {D('ShowOnStartup')} {change(start[0])}")
for i, (p, ks) in enumerate(others, 1):
    numbered.append(ks)
    names = ", ".join(k[1] for k in ks)
    detail = f"{ks[0][1]}: {change(ks[0])}" if len(ks) == 1 else f"{len(ks)}: {clip(names, 52)}"
    print(f"   {B(str(i).rjust(2))}  {short(p)}  {D(detail)}")
print()

if mode == "list" or not sys.stdin.isatty():
    if mode != "list":
        print(f"   {YL('⚠')} No terminal to ask: keeping Flatpak values for everything.")
    sys.exit(0)

def ask(q):
    try:
        return input(q)
    except EOFError:            # Ctrl-D: treat as "no / none"
        print(); return ""
    except KeyboardInterrupt:   # Ctrl-C: stop, Flatpak settings stay as copied
        print(f"\n   {YL('⚠')} Interrupted: Flatpak settings used; existing profile is in the .bak folder.")
        sys.exit(0)

def ask_yn(q):
    while True:
        a = ask(f"   {q} {D('[y/N]')} ").strip().lower()
        if a in ("", "n", "no"): return False
        if a in ("y", "yes"): return True

chosen = []
if layout and ask_yn(f"Keep existing {CY('toolbar & window layout')}?"): chosen += layout
if start and ask_yn(f"Keep existing {CY('Start page')} setting?"): chosen += start
if numbered:
    hint = D("e.g. 1 3 5-7 · all · Enter = none")
    while True:
        raw = ask(f"   Keep existing for which others? {hint} ").strip().lower()
        if raw in ("", "none"): sel = set(); break
        if raw == "all": sel = set(range(1, len(numbered) + 1)); break
        sel, bad = set(), False
        for tok in re.split(r"[,\s]+", raw):
            m = re.fullmatch(r"(\d+)(?:-(\d+))?", tok)
            if not m: bad = True; break
            a, b = int(m[1]), int(m[2] or m[1])
            if not (1 <= a <= b <= len(numbered)): bad = True; break
            sel.update(range(a, b + 1))
        if not bad: break
        print(f"   {YL('⚠')} Use numbers 1-{len(numbered)}, ranges like 2-4, 'all' or Enter.")
    for i in sorted(sel): chosen += numbered[i - 1]

if not chosen:
    print(f"\n   {D('Kept nothing from the existing profile: Flatpak settings used as-is.')}")
    sys.exit(0)

root = target_tree.getroot()
for k in chosen:
    # walk/create the group path below <FCParameters>
    g = root
    for name in k[0]:
        nxt = next((ch for ch in g if ch.tag == "FCParamGroup" and ch.get("Name") == name), None)
        if nxt is None:
            nxt = ET.SubElement(g, "FCParamGroup", {"Name": name})
        g = nxt
    for ch in [ch for ch in g if ch.tag in LEAF and ch.get("Name") == k[1]]:
        g.remove(ch)
    g.append(copy.deepcopy(old[k]))
target_tree.write(target_path, encoding="utf-8", xml_declaration=True)
print(f"\n   {GR('✔')} Kept {B(str(len(chosen)))} existing setting(s) on top of the Flatpak settings.")
PY

merge_settings() {  # merge_settings <keep.cfg> <target.cfg> <interactive|list>
  python3 -I -c "$MERGE_PY" "$@"
}

# ---------- version handling (FreeCAD: ApplicationDirectories::versionStringForPath → "v{major}-{minor}") ----------
is_verdir() { [[ -d "$1" && "$(basename "$1")" =~ ^v[0-9]+-[0-9]+$ ]]; }
norm_ver() {  # 1.1 | v1-1 | 1.1.4 | 26.3 → v1-1 / v26-3 ; empty on garbage
  [[ "$1" =~ ^[vV]?([0-9]+)[.-]([0-9]+)([.-][0-9]+)?$ ]] || return 0
  printf 'v%d-%d' "$((10#${BASH_REMATCH[1]}))" "$((10#${BASH_REMATCH[2]}))"
}
pretty() { local v="${1#v}"; printf '%s' "${v/-/.}"; }
is_versioned() {  # per-version folders exist since 1.1
  local v="${1#v}" maj min; maj="${v%-*}"; min="${v#*-}"
  (( maj > 1 || (maj == 1 && min >= 1) ))
}
has_legacy() { [[ -f "$1/FreeCAD/user.cfg" || -d "$1/FreeCAD/Mod" || -d "$1/FreeCAD/Macro" ]]; }
versions_in() {  # versions_in <base> → versioned dirs present under <base>/FreeCAD, newest last
  local d; for d in "$1"/FreeCAD/v*-*; do if is_verdir "$d"; then basename "$d"; fi; done | sort -t- -k1.2,1n -k2,2n
}

if (( LIST )); then
  printf '\n %s%s◆ FreeCAD profiles%s %s· migrate v%s%s\n\n' "$B" "$MAG" "$R" "$D" "$SCRIPT_VERSION" "$R"
  for side in "Flatpak:$FP/config:$FP/data" "Native:$NATIVE_CFG:$NATIVE_DATA"; do
    IFS=: read -r name cbase dbase <<<"$side"
    printf '   %s%s%s\n' "$B" "$name" "$R"
    found=0
    while read -r v; do [[ -n "$v" ]] || continue; found=1
      printf '     %s%-6s%s %s%s%s\n' "$CYN" "$(pretty "$v")" "$R" "$D" "$(t "$cbase/FreeCAD/$v")" "$R"
    done < <({ versions_in "$cbase"; versions_in "$dbase"; } | sort -u -t- -k1.2,1n -k2,2n)
    if has_legacy "$cbase" || has_legacy "$dbase"; then found=1
      printf '     %s≤1.0  %s %s%s  (1.0 and older, unversioned)%s\n' "$CYN" "$R" "$D" "$(t "$cbase/FreeCAD")" "$R"; fi
    (( found )) || printf '     %snothing found%s\n' "$D" "$R"
  done
  printf '\n   %sUse: %s -v <version>%s\n\n' "$D" "${0##*/}" "$R"
  exit 0
fi

# Resolve which version to migrate
if [[ -n "$VER_ARG" ]]; then
  VER="$(norm_ver "$VER_ARG")"
  [[ -n "$VER" ]] || die "Not a version: '$VER_ARG' (use e.g. 1.0, 1.1, 26.3)"
else
  VER="$(versions_in "$FP/config" | tail -n1)"
  [[ -z "$VER" ]] && has_legacy "$FP/config" && VER="v1-0"
  [[ -n "$VER" ]] || die "No Flatpak FreeCAD profile found under $(t "$FP/config/FreeCAD")"
fi

if is_versioned "$VER"; then
  LEGACY=0; LABEL="$(pretty "$VER")"
  SRC_CFG="$FP/config/FreeCAD/$VER";  SRC_DATA="$FP/data/FreeCAD/$VER"
  DST_CFG="$NATIVE_CFG/FreeCAD/$VER"; DST_DATA="$NATIVE_DATA/FreeCAD/$VER"
  CFG_BAK="$DST_CFG.bak-$STAMP";      DATA_BAK="$DST_DATA.bak-$STAMP"
  [[ -d "$SRC_CFG" ]] || {
    avail="$(versions_in "$FP/config" | while read -r v; do printf '%s ' "$(pretty "$v")"; done)"
    has_legacy "$FP/config" && avail+="≤1.0"
    die "Flatpak has no FreeCAD $LABEL profile. Available: ${avail:-none}"; }
else
  LEGACY=1; LABEL="$(pretty "$VER") (unversioned, ≤1.0)"
  SRC_CFG="$FP/config/FreeCAD";      SRC_DATA="$FP/data/FreeCAD"
  DST_CFG="$NATIVE_CFG/FreeCAD";     DST_DATA="$NATIVE_DATA/FreeCAD"
  # only the unversioned files are replaced; newer v*-* folders next to them stay in place
  CFG_BAK="$NATIVE_CFG/FreeCAD.legacy.bak-$STAMP"; DATA_BAK="$NATIVE_DATA/FreeCAD.legacy.bak-$STAMP"
  has_legacy "$FP/config" || die "Flatpak has no unversioned (≤1.0) FreeCAD profile."
fi
[[ -d "$SRC_DATA" ]] || SRC_DATA=""

printf '\n %s%s◆ FreeCAD Flatpak → native%s %s· %s%s · migrate v%s%s\n\n' "$B" "$MAG" "$R" "$D" "$LABEL" "$( ((DRY)) && echo ' · dry run')" "$SCRIPT_VERSION" "$R"

step "Locating Flatpak profile"
ok "$(t "$SRC_CFG")"

step "Checking FreeCAD closed"
# exact process name match: won't hit this script or freecad-smart-launcher
pgrep -xi 'freecad|freecadcmd' >/dev/null && die "FreeCAD is running. Close it (Flatpak and AppImage) first."
ok

# Existing native settings to offer keeping: explicit --keep-from, else the profile we're about to replace
step "Existing native profile"
if [[ -n "$KEEP_FROM" ]]; then
  KEEP_FROM="${KEEP_FROM%/}"
  [[ -f "$KEEP_FROM/user.cfg" ]] || die "No user.cfg in $KEEP_FROM"
  KEEP_CFG="$KEEP_FROM/user.cfg"; ok "$(t "$KEEP_FROM") (--keep-from)"
elif [[ -f "$DST_CFG/user.cfg" ]]; then
  EXISTING_CFG="$DST_CFG/user.cfg"; KEEP_CFG="$CFG_BAK/user.cfg"; ok "found, will be compared"
else
  KEEP_CFG=""; ok "none"
fi
command -v python3 >/dev/null || { [[ -z "$KEEP_CFG" ]] || die "python3 is needed to compare settings"; }

entries() { local e; for e in "$1"/* "$1"/.[!.]*; do [[ -e "$e" ]] || continue; (( LEGACY )) && is_verdir "$e" && continue; printf '%s\0' "$e"; done; }
copy_tree() {  # copy_tree <label> <src> <dst> <bak>
  step "$1"
  [[ -n "$2" && -d "$2" ]] || { printf '%s–%s %snot in Flatpak profile%s\n' "$YLW" "$R" "$D" "$R"; return; }
  local note="" e moved=0
  # back up what's there (legacy: only unversioned entries, never sibling v*-* folders)
  if [[ -d "$3" ]]; then
    while IFS= read -r -d '' e; do
      (( moved )) || run mkdir -p "$4"; moved=1
      run mv "$e" "$4/"
    done < <(entries "$3")
    (( moved )) && note="  (existing → $(basename "$4"))"
  fi
  run mkdir -p "$3"
  while IFS= read -r -d '' e; do run cp -a "$e" "$3/"; done < <(entries "$2")
  ok "$(t "$3")$note"
}
copy_tree "Copying settings"  "$SRC_CFG"  "$DST_CFG"  "$CFG_BAK"
copy_tree "Copying user data" "$SRC_DATA" "$DST_DATA" "$DATA_BAK"

step "Rewriting sandbox paths"
n=0
for f in "$DST_CFG"/*.cfg; do
  [[ -f "$f" ]] || continue
  run sed -i \
    -e "s#$FP/data#$NATIVE_DATA#g" \
    -e "s#$FP/config#$NATIVE_CFG#g" \
    -e "s#$FP/cache#$NATIVE_CACHE#g" "$f"
  n=$((n+1))
done
(( DRY )) && n="$(find "$SRC_CFG" -maxdepth 1 -name '*.cfg' 2>/dev/null | wc -l)"
ok "$n cfg file(s)"

step "Skipping cache"
ok "regenerated on first start"

if [[ -n "$KEEP_CFG" ]]; then
  printf '\n %s%s◆ Existing settings%s\n\n' "$B" "$CYN" "$R"
  if (( DRY )); then
    # nothing copied yet: compare against the Flatpak original (read-only)
    cmp_target="$(mktemp)"; cp "$SRC_CFG/user.cfg" "$cmp_target"
    merge_settings "${EXISTING_CFG:-$KEEP_CFG}" "$cmp_target" list; rm -f "$cmp_target"
  else
    merge_settings "$KEEP_CFG" "$DST_CFG/user.cfg" interactive
  fi
fi

echo
# Things a text rewrite can't fix safely: report, don't guess
if ((! DRY)); then
  hits="$(grep -nE '>/app/|/run/user/[0-9]+/doc/|\.var/app/' "$DST_CFG"/*.cfg 2>/dev/null || true)"
  if [[ -n "$hits" ]]; then
    warn "Settings still pointing inside the Flatpak sandbox (harmless for Recent Files; fix tool paths in Preferences):"
    printf '%s\n' "$hits" | sed -E 's/^([^:]+):([0-9]+):.*(Name="[^"]*").*>([^<]*)<.*/   \2: \3 = \4/' | sed "s#$HOME#~#g" | head -20
  fi
  for d in "$DST_DATA"/AdditionalPythonPackages/py*; do
    [[ -d "$d" ]] && warn "Addon Python deps in $(t "$d") were built for the Flatpak's Python; if an addon fails, reinstall its deps via Addon Manager."
  done
fi

printf '\n %s%s✔ Done.%s %sStart FreeCAD from the launcher (keep “Vanilla launch” off).%s\n' "$B" "$GRN" "$R" "$D" "$R"
(( LEGACY )) && printf '   %sFreeCAD 1.1+ will offer to migrate this ≤1.0 profile into its own version folder on first start.%s\n' "$D" "$R"
printf '   %sRollback: restore %s and %s from the *bak-%s copies. Flatpak profile untouched.%s\n\n' \
  "$D" "$(t "$DST_CFG")" "$(t "$DST_DATA")" "$STAMP" "$R"
