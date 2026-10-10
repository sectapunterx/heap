#!/usr/bin/env bash
# Builds the drag-to-Applications dmg: <app> plus an /Applications link.
#
#   make-dmg.sh <path/to/lowkey.app> <out.dmg>
#
# hdiutil on hosted macOS runners now and then fails with "Resource busy" when
# something (Spotlight, a previous mount) still holds the volume; that says
# nothing about the build, so it gets three tries.
set -euo pipefail

app=$1
out=$2
stage=$(mktemp -d)
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"

for attempt in 1 2 3; do
  if hdiutil create -volname "lowkey" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$out"; then
    exit 0
  fi
  echo "::warning::hdiutil create failed (attempt $attempt of 3)"
  sleep 15
done
exit 1
