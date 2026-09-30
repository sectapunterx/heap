#!/usr/bin/env bash
#
# Drop what windeployqt and the QtQuick copy ship but heap never loads, before
# copy-deps.sh walks the DLL closure (audit REL-3: ~21 MB of 185 MB unpacked).
#
#  - Every Qt Quick Controls style but Basic. main.cpp forces
#    QQuickStyle::setStyle("Basic") before the engine starts, and qml/ imports
#    only QtQuick.Controls, .Basic and .impl — so Material, Imagine, Universal,
#    Fusion, Windows and FluentWinUI3 (plus NativeStyle, which only Fusion and
#    Windows use, and the Designer helpers) are dead weight, with their
#    Qt6QuickControls2<Style>*.dll behind them.
#  - QtQuick.Particles and QtQuick.LocalStorage: nothing imports them;
#    LocalStorage is what drags Qt6Sql and the sqldrivers plugins in.
#
# Pruning first and walking the closure after is what keeps this safe: if
# anything still bundled imports a DLL removed here, copy-deps.sh copies it
# back in, and its final re-scan fails the build if it cannot. The smoke test
# in CI/release then starts the bundle with only System32 on PATH.
#
# Usage: prune-bundle.sh <bundle-dir>
set -euo pipefail

bundle="$1"
[ -d "$bundle" ] || { echo "prune-bundle: no bundle at $bundle" >&2; exit 1; }

# The app's own QML must not have started using something pruned here.
src_qml="$(cd "$(dirname "$0")/../.." && pwd)/qml"
if [ -d "$src_qml" ] && grep -rEq '^\s*import\s+QtQuick\.(Particles|LocalStorage|Controls\.(Material|Imagine|Universal|Fusion|Windows|FluentWinUI3))\b' "$src_qml"; then
  echo "prune-bundle: qml/ imports a module this script removes — update packaging/windows/prune-bundle.sh" >&2
  exit 1
fi

styles=(Material Imagine Universal Fusion Windows FluentWinUI3 macOS iOS designer)
removed=0
# windeployqt deploys QML modules under qml/, the CMake target copies QtQuick
# beside the exe as well; prune both trees.
for root in "$bundle" "$bundle/qml"; do
  [ -d "$root/QtQuick" ] || continue
  for s in "${styles[@]}"; do
    if [ -d "$root/QtQuick/Controls/$s" ]; then rm -rf "$root/QtQuick/Controls/$s"; removed=$((removed + 1)); fi
  done
  for m in NativeStyle Particles LocalStorage; do
    if [ -d "$root/QtQuick/$m" ]; then rm -rf "$root/QtQuick/$m"; removed=$((removed + 1)); fi
  done
done

shopt -s nullglob nocaseglob
dlls=()
for s in Material Imagine Universal Fusion Windows FluentWinUI3; do
  dlls+=("$bundle"/Qt6QuickControls2"$s"*.dll)
done
dlls+=("$bundle"/Qt6QuickParticles.dll "$bundle"/Qt6QmlLocalStorage.dll "$bundle"/Qt6Sql.dll)
for f in "${dlls[@]}"; do
  rm -f "$f"
  removed=$((removed + 1))
done
if [ -d "$bundle/sqldrivers" ]; then rm -rf "$bundle/sqldrivers"; removed=$((removed + 1)); fi

echo "prune-bundle: removed $removed unused style/module entries from $bundle"
