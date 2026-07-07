#!/usr/bin/env bash
#
# Complete the Windows portable bundle: copy every MSYS2/ucrt64 DLL the app and
# its Qt DLLs/plugins transitively need but windeployqt does NOT ship. On MSYS2
# windeployqt bundles Qt's own DLLs (+ plugins) but not qtkeychain (a non-Qt
# module) nor the transitive non-Qt deps of Qt6Core/Qt6Gui/plugins
# (pcre2, zlib, zstd, double-conversion, freetype, harfbuzz, icu, brotli,
# libjpeg, ...). Without them the portable zip crashes on launch
# ("libqt6keychain / libbrotlidec / zlib1 / libzstd not found").
#
# We resolve dependencies with `objdump -p` (a STATIC read of each PE's import
# table) and recurse ourselves. This is deliberately NOT `ldd`: ldd resolves via
# the loader/PATH and, on the CI runner, lists only an exe's DIRECT imports —
# it never descends into Qt6Core.dll, so the transitive deps were silently
# dropped and the published v0.5.0/v0.5.1 zips shipped broken. objdump reads the
# same bytes on every machine, so a bundle that verifies locally verifies on CI.
#
# Seed = every PE already in the bundle (heap.exe + windeployqt's Qt DLLs AND
# the plugin DLLs in subdirs — plugins have their own deps, e.g. qjpeg → libjpeg).
# Any imported DLL that exists in the ucrt64 bin dir is copied in and recursed
# into; anything not there is a Windows system DLL and is left alone.
#
# Finally we re-scan the finished bundle and FAIL if any ucrt64 dependency is
# still missing — so a broken bundle can never be published silently again.
#
# Perf: Windows process spawns are expensive, so this avoids per-DLL helpers —
# lowercasing and basename use bash builtins (${x,,} / ${x##*/}), directory
# listings are read once into hash maps, and each PE's import table is dumped by
# objdump exactly once (memoized, shared by the copy walk and the integrity gate).
#
# Usage: copy-deps.sh <bundle-dir> <ucrt64-bin-dir>
set -euo pipefail

bundle="$1"
libdir="$2"
objdump="${libdir}/objdump.exe"
[ -x "$objdump" ] || objdump="objdump"   # fall back to PATH if not beside libs

# Memoized objdump: cache each PE's imported DLL names (newline-separated).
declare -A IMPCACHE
imports_of() {
  local f="$1"
  if [ -z "${IMPCACHE[$f]+x}" ]; then
    IMPCACHE[$f]=$("$objdump" -p "$f" 2>/dev/null | awk '/DLL Name:/ { print $3 }')
  fi
  printf '%s\n' "${IMPCACHE[$f]}"
}

# One pass over ucrt64/bin: lowercased DLL name → absolute source path.
declare -A libmap
while IFS= read -r p; do
  b="${p##*/}"; libmap["${b,,}"]="$p"
done < <(find "$libdir" -maxdepth 1 -type f -iname '*.dll' 2>/dev/null)

# One pass over the bundle: set of lowercased basenames already present (any depth),
# and the list of PE files to seed the walk.
declare -A have
queue=()
while IFS= read -r pe; do
  b="${pe##*/}"; have["${b,,}"]=1
  case "${b,,}" in *.exe|*.dll) queue+=("$pe");; esac
done < <(find "$bundle" -type f)

declare -A processed
copied=0
while ((${#queue[@]})); do
  pe="${queue[0]}"; queue=("${queue[@]:1}")
  b="${pe##*/}"; k="${b,,}"
  [ -n "${processed[$k]:-}" ] && continue
  processed[$k]=1

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
    queue+=("$bundle/$sb")                      # recurse into the newly bundled DLL
  done < <(imports_of "$pe")
done
echo "copy-deps: copied $copied DLL(s) from $libdir"

# ── Integrity gate ──────────────────────────────────────────────────────────
# Every ucrt64 dependency of every bundled PE must now be present. A dep that
# ucrt64 provides but the bundle lacks is a packaging bug → fail the build.
missing=0
while IFS= read -r pe; do
  while IFS= read -r dll; do
    [ -n "$dll" ] || continue
    dk="${dll,,}"
    [ -n "${have[$dk]:-}" ] && continue
    if [ -n "${libmap[$dk]:-}" ]; then
      echo "  !! MISSING: $dll (needed by ${pe##*/})" >&2
      missing=$((missing + 1))
    fi
  done < <(imports_of "$pe")
done < <(find "$bundle" -type f \( -iname '*.exe' -o -iname '*.dll' \))

if [ "$missing" -ne 0 ]; then
  echo "copy-deps: $missing dependency(ies) missing from bundle — aborting" >&2
  exit 1
fi
echo "copy-deps: bundle dependency closure verified"
