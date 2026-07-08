#!/usr/bin/env bash
#
# heap — installer for the distro-agnostic Linux tarball.
#
# This tarball ships the dynamically-linked `heap` binary and expects Qt 6 (>= 6.4)
# to be provided by your distribution — the Arch/source-install convention. It does
# NOT bundle Qt; if you want a self-contained binary use the AppImage instead.
#
# Usage:
#   ./install.sh                 install (system-wide as root, else into ~/.local)
#   ./install.sh --prefix=DIR    install under DIR (DIR/bin, DIR/share/...)
#   ./install.sh --uninstall     remove a previous install (respects --prefix)
#   ./install.sh --help
#
# Env: PREFIX=DIR is honoured as a fallback if --prefix is not given.
set -euo pipefail

app=heap
here="$(cd "$(dirname "$0")" && pwd)"

# ── Resolve prefix ───────────────────────────────────────────────────────────
# Root installs system-wide to /usr/local; a normal user installs into ~/.local
# (no sudo needed). --prefix / $PREFIX override either default.
prefix="${PREFIX:-}"
action=install
for arg in "$@"; do
  case "$arg" in
    --prefix=*) prefix="${arg#*=}" ;;
    --uninstall|--remove) action=uninstall ;;
    -h|--help)
      sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "install.sh: unknown argument: $arg" >&2; exit 2 ;;
  esac
done
if [ -z "$prefix" ]; then
  if [ "$(id -u)" -eq 0 ]; then prefix=/usr/local; else prefix="$HOME/.local"; fi
fi

bindir="$prefix/bin"
appdir="$prefix/share/applications"
icondir="$prefix/share/icons/hicolor/scalable/apps"

bin_target="$bindir/$app"
desktop_target="$appdir/$app.desktop"
icon_target="$icondir/$app.svg"

refresh_caches() {
  # Best-effort: keep the desktop/icon databases in sync so the launcher and
  # icon show up immediately. Missing tools are fine.
  command -v update-desktop-database >/dev/null 2>&1 && \
    update-desktop-database "$appdir" >/dev/null 2>&1 || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 && \
    gtk-update-icon-cache -qtf "$prefix/share/icons/hicolor" >/dev/null 2>&1 || true
}

# ── Uninstall ────────────────────────────────────────────────────────────────
if [ "$action" = uninstall ]; then
  echo "Removing heap from $prefix ..."
  rm -f "$bin_target" "$desktop_target" "$icon_target"
  refresh_caches
  echo "Done."
  exit 0
fi

# ── Install ──────────────────────────────────────────────────────────────────
[ -f "$here/$app" ] || { echo "install.sh: '$app' binary not found next to this script" >&2; exit 1; }

echo "Installing heap into $prefix ..."
install -Dm755 "$here/$app"           "$bin_target"
install -Dm644 "$here/$app.svg"       "$icon_target"
# Install the .desktop with an absolute Exec so the launcher works even when
# $bindir is not on PATH (e.g. a ~/.local install on a minimal desktop).
install -dm755 "$appdir"
sed "s|^Exec=heap$|Exec=$bin_target|" "$here/$app.desktop" > "$desktop_target"
chmod 644 "$desktop_target"
refresh_caches

# ── Post-install checks ──────────────────────────────────────────────────────
# Warn (don't fail) if Qt/other shared libs are missing — this tarball relies on
# system Qt 6. Point the user at their distro's Qt 6 packages.
if command -v ldd >/dev/null 2>&1; then
  missing="$(ldd "$bin_target" 2>/dev/null | awk '/not found/{print "  " $1}' || true)"
  if [ -n "$missing" ]; then
    echo
    echo "WARNING: some shared libraries are missing:" >&2
    echo "$missing" >&2
    echo "Install Qt 6 (>= 6.4) from your distribution, e.g.:" >&2
    echo "  Arch:          sudo pacman -S qt6-base qt6-declarative qt6-svg qt6-wayland" >&2
    echo "  Debian/Ubuntu: sudo apt install libqt6core6 libqt6quick6 libqt6svg6 qml6-module-qtquick" >&2
    echo "  Fedora:        sudo dnf install qt6-qtbase qt6-qtdeclarative qt6-qtsvg" >&2
  fi
fi

case ":$PATH:" in
  *":$bindir:"*) : ;;
  *) echo; echo "Note: $bindir is not on your PATH — add it or run heap by full path: $bin_target" ;;
esac

echo
echo "Installed. Launch with 'heap' or from your application menu."
