#!/usr/bin/env bash
# Starts a heap AppImage in the clean Ubuntu this runs in (release.yml starts it
# in ubuntu:24.04) and checks it with heap --smoke.
#
#   smoke-appimage.sh <heap.AppImage>
#
# The AppImage carries Qt and everything linuxdeploy bundles; what it expects
# from the system is what every desktop has — GL, fontconfig, the X client
# libraries, a session bus. Only those are installed here, so a library the
# AppImage should have bundled shows up as missing instead of being supplied
# by the host. On failure it runs heap again under gdb and prints every
# thread's stack.
set -euo pipefail

image=$(realpath "$1")
export DEBIAN_FRONTEND=noninteractive

echo "::group::desktop base (X server, GL, fonts, session bus)"
apt-get update -q
apt-get install -y --no-install-recommends \
  xvfb dbus libgl1 libegl1 libfontconfig1 libfreetype6 libglib2.0-0t64 \
  libx11-6 libx11-xcb1 libxkbcommon0 libxkbcommon-x11-0 \
  libxcb1 libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 \
  libxcb-render-util0 libxcb-shape0 libxcb-shm0 libxcb-sync1 libxcb-xfixes0 libxcb-xinerama0 libxcb-xkb1
echo "::endgroup::"

# Extract rather than mount: no FUSE in a container. AppRun is what a user's
# double-click runs.
work=$(mktemp -d)
cd "$work"
"$image" --appimage-extract >/dev/null

# Anything linuxdeploy left out and this desktop base does not provide.
missing=$(find squashfs-root -type f \( -name '*.so*' -o -path '*/usr/bin/heap' \) -exec ldd {} + 2>/dev/null \
  | grep "not found" | sort -u || true)
if [[ -n "$missing" ]]; then
  echo "$missing"
  echo "::error::the AppImage does not bundle every library it needs"
  exit 1
fi

# Without a session bus Qt blocks at startup on D-Bus. Both are started directly
# so heap, or gdb below, is the child that the timeout signals; -k because heap
# turns SIGTERM into a quit request a blocked main thread never reads.
Xvfb :99 -screen 0 1280x800x24 -nolisten tcp 2>/dev/null &
export DISPLAY=:99
DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address)
export DBUS_SESSION_BUS_ADDRESS
sleep 2

if timeout -k 10 120 squashfs-root/AppRun --smoke --data-dir /tmp/heap-smoke; then
  exit 0
fi

echo "::group::where it stops (gdb)"
apt-get install -y -q gdb >/dev/null
# The binary itself, not AppRun (a shell script with linuxdeploy's hooks): it
# finds its Qt through its rpath and the qt.conf beside it.
timeout -s INT -k 20 90 gdb -q -batch -ex run -ex "thread apply all bt 25" \
  --args squashfs-root/usr/bin/heap --smoke --data-dir /tmp/heap-smoke-gdb || true
echo "::endgroup::"
exit 1
