#!/usr/bin/env bash
# Installs a heap .deb into the clean Ubuntu this runs in (release.yml starts it
# in ubuntu:24.04) and checks that the app starts: heap --smoke under a virtual
# X server and a session bus, the two things every desktop session has.
#
#   smoke-deb.sh <package.deb>
#
# On failure it runs heap again under gdb and prints every thread's stack, so a
# hang says where it hangs instead of just timing out.
set -euo pipefail

deb=$1
export DEBIAN_FRONTEND=noninteractive

echo "::group::apt install ./$deb (+ Xvfb, D-Bus)"
apt-get update -q
apt-get install -y "./$deb" xvfb dbus
echo "::endgroup::"

# A library the Depends line forgot shows up here by name, rather than as a
# loader error or a hang further down.
if ldd /usr/bin/heap | grep "not found"; then
  echo "::error::the .deb does not pull in every library heap links"
  exit 1
fi

# Without a session bus Qt blocks at startup on D-Bus (accessibility, the GTK
# platform theme). Both are started directly so heap, or gdb below, is the
# child that the timeout signals.
Xvfb :99 -screen 0 1280x800x24 -nolisten tcp 2>/dev/null &
export DISPLAY=:99
DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address)
export DBUS_SESSION_BUS_ADDRESS
sleep 2

if timeout 120 heap --smoke --data-dir /tmp/heap-smoke; then
  exit 0
fi

echo "::group::where it stops (gdb)"
apt-get install -y -q gdb >/dev/null
timeout -s INT 90 gdb -q -batch -ex run -ex "thread apply all bt 25" \
  --args heap --smoke --data-dir /tmp/heap-smoke-gdb || true
echo "::endgroup::"
exit 1
