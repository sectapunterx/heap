#!/usr/bin/env bash
#
# Copy the MSYS2/ucrt64 DLLs that windeployqt does NOT bundle: qtkeychain
# (a non-Qt module, so windeployqt ignores it even though heap.exe imports it)
# and the transitive compression deps pulled in by Qt6Gui/Qt6Core
# (brotli, zstd, zlib, ...). windeployqt on MSYS2 does not recurse into these
# non-Qt dependencies, which is why a portable zip built with it alone crashes
# on launch with "libqt6keychain / libbrotlidec / zlib1 / libzstd not found".
#
# Rather than hand-list every DLL (fragile — brotlidec silently needs
# brotlicommon, and more can appear on a Qt bump), we let ldd resolve the full
# transitive closure. This script runs AFTER windeployqt has populated the
# bundle, so DLLs already copied resolve from the bundle dir; only the ones
# still missing resolve to the ucrt64 bin dir — those are exactly the gap.
#
# Usage: copy-deps.sh <path-to-bundled-heap.exe> <bundle-dir>
set -euo pipefail

exe="$1"
dest="$2"

# ldd prints "name.dll => /c/msys64/ucrt64/bin/name.dll (0xADDR)" for resolved
# deps. Match the ucrt64 bin dir (works for any MSYS_ROOT — CI's runner path or
# a local C:/msys64) and copy each one that is not already in the bundle.
ldd "$exe" | awk '/ucrt64\/bin/ { print $3 }' | while IFS= read -r dll; do
  [ -f "$dll" ] && cp -u "$dll" "$dest/"
done
