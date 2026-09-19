# md4c, vendored

[md4c](https://github.com/mity/md4c) is the CommonMark parser heap builds its
notes editor on. `md4c.c`, `md4c.h` and `LICENSE.md` are copied here verbatim —
do not edit them. Local changes belong in a patch file next to this README so an
upgrade stays a straight re-copy.

## Provenance

| | |
|---|---|
| Upstream | https://github.com/mity/md4c |
| Version | 0.5.3 |
| Tag | `release-0.5.3` (annotated tag object `093c3f45ce44bd6661849982b1dd7f0e7f385621`) |
| Commit | `472c417005c2c71b8617de4f7b8d6b30411d78f4` |
| Source archive | `https://api.github.com/repos/mity/md4c/tarball/release-0.5.3`, sha256 `bc2e3bf85e5e6235ee5246778d608048e0a572d9d84538e5ef9e7d4b59a28ad6` |
| License | MIT (`LICENSE.md`) |

File checksums, so a re-copy can be verified without re-downloading:

```
f12907817a17ae7d0f6c8d18770df839f187cad5649dd36a475dba0675c5c1f8  md4c.c
4efd19bf7ec270691d5b4189f496886e421768a814b5e817eb945aa85e859f18  md4c.h
d30937367d5413e7eaa218b1640b8946ff76fd34d97152f6979fd96169d5d0fc  LICENSE.md
```

`md4c.h` as shipped here is byte-identical (ignoring line endings) to the header
MSYS2 installs from its own independently built `mingw-w64-ucrt-x86_64-md4c`
0.5.3 package, which is how this copy was corroborated against a second source.

## Why vendored rather than linked

heap depends on Qt and QtKeychain and nothing else: no FetchContent, no vcpkg,
no Conan. The Windows portable bundle is assembled by walking the DLL closure of
the executable, and a dependency that is present on the build machine but absent
from a clean target has shipped a broken release before. Two C files compiled
into a static library add no DLL and no discovery step on any platform.

Qt itself uses md4c for `QTextDocument::setMarkdown`, and on some platforms it
links a shared `libmd4c`. To keep the two copies from being confused for one
another, this build compiles with hidden visibility and renames the entry point
to `heap_md_parse` (see `CMakeLists.txt`); call it through `md4c.h` as
`md_parse` and the macro takes care of the rest.

## Updating

1. Download the tarball for the new tag and record its sha256 above.
2. Copy `src/md4c.c`, `src/md4c.h` and `LICENSE.md` over the files here; copy
   nothing else — the upstream test suite, `md4c-html` and the CLI are not used.
3. Re-run the checksums, update the table, and run `ctest -R heap_md4c`.
