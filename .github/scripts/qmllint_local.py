#!/usr/bin/env python3
"""Run CI's qmllint check locally, with the qmllint of the Qt that CI uses.

The ratchet's baseline and its verdict come from Qt 6.9.1's qmllint (see
qmllint_ratchet.py). A local build on another Qt reports different findings,
so a change could pass here and fail in CI. This runs the same lint CI runs:
it takes the argument file CMake writes for `all_qmllint_json`, points its Qt
import path at a Qt 6.9 install instead of the build's Qt, runs that Qt's
qmllint, and judges the result against the baseline on the lines changed since
<base>.

Only qmllint and the Qt 6.9 QML modules are needed, not a build with that Qt:
  pip install aqtinstall
  python -m aqt install-qt windows desktop 6.9.1 win64_msvc2022_64 -O C:/Qt --archives qtbase qtdeclarative qtsvg
  (linux: `linux desktop 6.9.1 linux_gcc_64`, macos: `mac desktop 6.9.1 clang_64`)

Usage:
  qmllint_local.py [--build build] [--qt <Qt 6.9 dir, or $HEAP_QMLLINT_QT>] [--base origin/master]
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
# .qmltypes keys a newer Qt writes and 6.9's qmllint does not know, on a line
# of their own or inside a one-line object ("Signal { name: "x"; lineNumber: 3 }").
NEWER_QMLTYPES_KEYS = re.compile(r"(;\s*|^\s*)lineNumber:\s*\d+\s*$|;\s*lineNumber:\s*\d+(?=\s*})", re.M)


def qmltypes_from_qt69(build: Path, qt: Path):
    """heap_core.qmltypes as Qt 6.9's qmltyperegistrar writes it, or None."""
    registrar = qt / "bin" / ("qmltyperegistrar.exe" if os.name == "nt" else "qmltyperegistrar")
    if not registrar.exists():
        registrar = qt / "libexec" / "qmltyperegistrar"
    foreign = build / "qmltypes" / "heap_core_foreign_types.txt"
    metatypes = build / "meta_types" / "qt6heap_core_metatypes.json"
    if not (registrar.exists() and foreign.exists() and metatypes.exists()):
        return None
    # Qt's own metatypes from the Qt 6.9 install; the project's from the build.
    paths = []
    for p in foreign.read_text(encoding="utf-8").strip().removeprefix("--foreign-types=").split(","):
        p = Path(p)
        if p.parent.name == "metatypes" and not str(p).startswith(str(build)):
            p = qt / "metatypes" / p.name
        paths.append(str(p))
    missing = [p for p in paths if not Path(p).exists()]
    if missing:
        print("qmllint_local: Qt 6.9 lacks " + ", ".join(Path(p).name for p in missing)
              + " (install the module with aqt -m)")
        return None
    out_dir = build / ".qmllint69"
    out_dir.mkdir(exist_ok=True)
    out = out_dir / "heap_core.qmltypes"
    r = subprocess.run([str(registrar), f"--generate-qmltypes={out}", "--import-name=TodoCpp", "--major-version=1",
                        "--minor-version=0", "--foreign-types=" + ",".join(paths),
                        "-o", str(out_dir / "heap_core_qmltyperegistrations.cpp"), str(metatypes)],
                       capture_output=True, text=True)
    if r.returncode != 0 or not out.exists():
        print("qmllint_local: qmltyperegistrar failed: " + (r.stderr or r.stdout).strip()[:300])
        return None
    return out.read_text(encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--build", default="build", help="the CMake build dir (configured with any Qt 6)")
    ap.add_argument("--qt", default=os.environ.get("HEAP_QMLLINT_QT", ""),
                    help="Qt 6.9 install dir, e.g. C:/Qt/6.9.1/msvc2022_64 (or set HEAP_QMLLINT_QT)")
    ap.add_argument("--base", default="origin/master", help="judge findings on lines changed since this ref")
    args = ap.parse_args()

    if not args.qt:
        print("qmllint_local: give the Qt 6.9 dir with --qt or HEAP_QMLLINT_QT (install: see --help)")
        return 2
    qt = Path(args.qt)
    exe = qt / "bin" / ("qmllint.exe" if os.name == "nt" else "qmllint")
    if not exe.exists():
        print(f"qmllint_local: no qmllint at {exe}")
        return 2
    build = (REPO / args.build).resolve() if not Path(args.build).is_absolute() else Path(args.build)
    rsp = build / ".rcc" / "qmllint" / "heap_core_json.rsp"

    # The .qmltypes the lint reads come from the C++ build; make sure they
    # (and the argument file) are current.
    subprocess.run(["cmake", "--build", str(build), "--target", "all_qmltyperegistrations"], check=True)
    if not rsp.exists():
        print(f"qmllint_local: {rsp} is missing - configure {build} with qmllint support first")
        return 2

    build_s = str(build).replace("\\", "/").rstrip("/")
    lines = rsp.read_text(encoding="utf-8").splitlines()
    report = build / "heap_core_qmllint_qt69.json"
    out = []
    i = 0
    while i < len(lines):
        arg = lines[i]
        if arg == "-I" and i + 1 < len(lines):
            path = lines[i + 1].replace("\\", "/").rstrip("/")
            if path.endswith("/qml") and not path.startswith(build_s):
                # The build's own Qt QML dir becomes Qt 6.9's.
                path = str(qt / "qml")
            out += ["-I", path]
            i += 2
            continue
        if arg == "--json" and i + 1 < len(lines):
            out += ["--json", str(report)]
            i += 2
            continue
        out.append(arg)
        i += 1
    rsp69 = rsp.with_name("heap_core_json_qt69.rsp")
    rsp69.write_text("\n".join(out) + "\n", encoding="utf-8")

    # The module's description. The build's Qt wrote it, and what qmllint
    # concludes about the C++ types depends on it: regenerate it with Qt 6.9's
    # qmltyperegistrar from the same moc output, as CI's build would, and put
    # the build's own file back afterwards.
    qmltypes = build / "TodoCpp" / "heap_core.qmltypes"
    saved = qmltypes.read_bytes()
    fresh = qmltypes_from_qt69(build, qt)
    if fresh is None:
        # No usable registrar: at least drop the keys an older qmllint rejects
        # ("lineNumber" since 6.10) - a rejected file leaves every type unknown.
        print("qmllint_local: could not run Qt 6.9's qmltyperegistrar; linting the build's qmltypes")
        fresh = NEWER_QMLTYPES_KEYS.sub("", saved.decode("utf-8"))
    qmltypes.write_text(fresh, encoding="utf-8")
    try:
        if report.exists():
            report.unlink()
        # qmllint exits non-zero whenever it has findings; the ratchet decides.
        subprocess.run([str(exe), f"@{rsp69}"], cwd=str(build), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    finally:
        qmltypes.write_bytes(saved)
    if not report.exists():
        print("qmllint_local: qmllint wrote no report")
        return 2

    return subprocess.run([sys.executable, str(HERE / "qmllint_ratchet.py"), str(report),
                           str(REPO / ".github" / "qmllint-baseline.json"), "--diff", args.base],
                          cwd=str(REPO)).returncode


if __name__ == "__main__":
    sys.exit(main())
