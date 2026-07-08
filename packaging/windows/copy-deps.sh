#!/usr/bin/env bash
#
# Complete the Windows portable bundle: copy every MSYS2/ucrt64 DLL the app and
# its Qt DLLs/plugins transitively need but windeployqt does NOT ship. On MSYS2
# windeployqt bundles Qt's own DLLs (+ plugins) but not qtkeychain (a non-Qt
# module) nor the transitive non-Qt deps of Qt6Core/Qt6Gui/plugins
# (pcre2, zlib, zstd, double-conversion, freetype, harfbuzz, icu, brotli,
# libjpeg, the glib stack) nor the Qt6 module DLLs behind some QML plugins
# (Qt6QmlLocalStorage, Qt6QuickParticles, Qt6Sql, Qt6QuickVectorImage*). Without
# them the portable zip crashes on launch ("libqt6keychain / zlib1 / ... not found").
#
# We resolve dependencies with `objdump -p` (a STATIC read of each PE's import
# table) and recurse ourselves. This is deliberately NOT `ldd`: ldd resolves via
# the loader/PATH and, on the CI runner, lists only an exe's DIRECT imports —
# it never descends into Qt6Core.dll, so the transitive deps were silently
# dropped and the published v0.5.0/v0.5.1 zips shipped broken. objdump reads the
# same bytes on every machine, so a bundle that verifies locally verifies on CI.
#
# Seed = every PE already in the bundle (heap.exe + windeployqt's Qt DLLs AND
# every plugin DLL in the subdirs, including the large qml/ tree). Any imported
# DLL that exists in the ucrt64 bin dir is copied in and recursed into; anything
# not there is a Windows system DLL and is left alone.
#
# Finally we re-scan the finished bundle and FAIL if any ucrt64 dependency is
# still missing — so a broken bundle can never be published silently again.
#
# Perf: the bundle's qml/ tree holds hundreds of plugin DLLs, and a process
# spawn on the Windows CI runner is expensive, so objdump is NOT run per file.
# The walk is breadth-first and each level's files are dumped in one batched
# objdump invocation (via xargs, which also keeps the command line under the
# Windows length limit). That makes the whole closure a handful of spawns, not
# hundreds. Lowercasing/basename use bash builtins (${x,,} / ${x##*/}).
#
# Usage: copy-deps.sh <bundle-dir> <ucrt64-bin-dir>
set -euo pipefail

bundle="$1"
libdir="$2"
objdump="${libdir}/objdump.exe"
[ -x "$objdump" ] || objdump="objdump"   # fall back to PATH if not beside libs

# Print the unique DLL names imported by a set of PE files, batching the objdump
# calls with xargs so hundreds of files cost only a few spawns.
imports_of() { printf '%s\0' "$@" | xargs -0 "$objdump" -p 2>/dev/null \
                 | awk '/DLL Name:/ { print $3 }' | sort -u; }

# One pass over ucrt64/bin: lowercased DLL name → absolute source path.
declare -A libmap
while IFS= read -r p; do
  b="${p##*/}"; libmap["${b,,}"]="$p"
done < <(find "$libdir" -maxdepth 1 -type f -iname '*.dll' 2>/dev/null)

# One pass over the bundle: set of lowercased basenames already present (any
# depth), and the first BFS level = every PE currently in the bundle.
declare -A have
level=()
while IFS= read -r pe; do
  b="${pe##*/}"; have["${b,,}"]=1
  case "${b,,}" in *.exe|*.dll) level+=("$pe");; esac
done < <(find "$bundle" -type f)

copied=0
while ((${#level[@]})); do
  next=()
  while IFS= read -r dll; do
    [ -n "$dll" ] || continue
    dk="${dll,,}"
    [ -n "${have[$dk]:-}" ] && continue        # already in the bundle
    src="${libmap[$dk]:-}"
    [ -n "$src" ] || continue                  # system DLL — leave to Windows
    sb="${src##*/}"
    cp "$src" "$bundle/$sb"
    have[$dk]=1
    copied=$((copied + 1))
    echo "  + $sb"
    next+=("$bundle/$sb")                        # recurse into it next level
  done < <(imports_of "${level[@]}")
  level=("${next[@]}")
done
echo "copy-deps: copied $copied DLL(s) from $libdir"

# ── Integrity gate ──────────────────────────────────────────────────────────
# Every ucrt64 dependency of every bundled PE must now be present. A dep that
# ucrt64 provides but the bundle lacks is a packaging bug → fail the build.
mapfile -t allpe < <(find "$bundle" -type f \( -iname '*.exe' -o -iname '*.dll' \))
missing=0
while IFS= read -r dll; do
  [ -n "$dll" ] || continue
  dk="${dll,,}"
  [ -n "${have[$dk]:-}" ] && continue
  if [ -n "${libmap[$dk]:-}" ]; then
    echo "  !! MISSING: $dll" >&2
    missing=$((missing + 1))
  elif [[ "$dk" == qt6*.dll || "$dk" == libqt6keychain*.dll ]]; then
    # A Qt module / qtkeychain we MUST ship, imported by a bundled PE but present
    # in neither the bundle nor ucrt64/bin. The plain "not in ucrt64 ⇒ system DLL"
    # rule above would silently ignore it — that is exactly how a build missing
    # its qt6-svg package shipped a bundle without Qt6Svg.dll. Treat it as a hard
    # error: the module's package is almost certainly not installed in the build
    # environment.
    echo "  !! MISSING (required Qt module — is its MSYS2 package installed?): $dll" >&2
    missing=$((missing + 1))
  fi
done < <(imports_of "${allpe[@]}")

if [ "$missing" -ne 0 ]; then
  echo "copy-deps: $missing dependency(ies) missing from bundle — aborting" >&2
  exit 1
fi
echo "copy-deps: bundle dependency closure verified"
