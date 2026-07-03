# Packaging & release

`heap.` ships from a single GitHub Actions workflow,
[`.github/workflows/release.yml`](../.github/workflows/release.yml). It builds
native artifacts for Windows, Linux and macOS and attaches them to a GitHub
Release.

## Triggering a release

- **On a version tag (primary path):**
  ```bash
  git tag v1.2.3
  git push origin v1.2.3
  ```
  The workflow uses the tag name verbatim for the release and artifact names.

- **Manually:** run the *Release* workflow from the Actions tab
  (`workflow_dispatch`). A dated tag `vYYYY.MM.DD-<short-sha>` is minted
  automatically.

## Artifacts

| Platform | Format | How it is built |
|----------|--------|-----------------|
| Windows  | `…-windows-portable.zip` | CMake `portable` target (windeployqt bundle) |
| Windows  | `…-windows-setup.exe`    | Inno Setup ([`installer/heap.iss`](../installer/heap.iss)) wrapping the portable bundle |
| Linux    | `…-linux-amd64.deb`      | `dpkg-deb` over [`packaging/linux/`](../packaging/linux/) staging |
| Linux    | `…-linux-x86_64.AppImage`| `linuxdeploy` + the Qt plugin (best-effort; the `.deb` still ships if it fails) |
| macOS    | `…-macos.dmg`            | `macdeployqt -dmg` (unsigned unless signing secrets are set) |

## macOS signing & notarization

The `.dmg` is **unsigned** by default, so first launch requires a
right-click → *Open*. To codesign + notarize automatically, add these repo
secrets — the workflow's optional step activates when `MACOS_CERT_P12` is
present:

| Secret | Meaning |
|--------|---------|
| `MACOS_CERT_P12` | base64 of a *Developer ID Application* `.p12` certificate |
| `MACOS_CERT_PASSWORD` | password for that `.p12` |
| `MACOS_NOTARY_APPLE_ID` | Apple ID used for notarization |
| `MACOS_NOTARY_PASSWORD` | app-specific password for that Apple ID |
| `MACOS_NOTARY_TEAM_ID` | Apple Developer Team ID |

## Windows signing

Windows binaries and the installer are **unsigned** by default, so SmartScreen
shows an *"Unknown publisher"* warning on first download/run. To Authenticode-sign
`heap.exe`, the bundled Qt DLLs and the setup `.exe` automatically, add these repo
secrets — the workflow's optional signing steps activate when `WINDOWS_CERT_PFX`
is present (mirrors the macOS pattern):

| Secret | Meaning |
|--------|---------|
| `WINDOWS_CERT_PFX` | base64 of an Authenticode code-signing `.pfx`/`.p12` certificate (OV or EV) |
| `WINDOWS_CERT_PASSWORD` | password for that `.pfx` |

Signing uses [`osslsigncode`](https://github.com/mtrojnar/osslsigncode) with an
RFC-3161 SHA-256 timestamp, so signatures stay valid after the certificate
expires. An **EV** certificate earns SmartScreen reputation instantly; an **OV**
certificate builds it up over downloads. The uninstaller (`unins000.exe`, which
Inno generates on the target machine) is not signed — add Inno's
`SignedUninstaller` directive later if that warning needs to go too.

## Follow-ups (not yet automated)

These formats from the original scope are intentionally deferred — each needs
extra tooling/infra that is easiest to add once the core three platforms are
proven:

- **Flatpak** — a `org.heap.heap.yaml` manifest built via `flatpak-builder`
  and pushed to a Flathub repo.
- **`.rpm`** — an `fpm`/`rpmbuild` job mirroring the `.deb` staging.
