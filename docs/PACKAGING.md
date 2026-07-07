# Packaging & release

`heap.` ships from a single GitHub Actions workflow,
[`.github/workflows/release.yml`](../.github/workflows/release.yml). It builds
native artifacts for Windows, Linux and macOS and attaches them to a GitHub
Release.

## Triggering a release

The version lives in **one** place — `project(heap VERSION X.Y.Z …)` in
[`CMakeLists.txt`](../CMakeLists.txt). The release tag mirrors it, and the
workflow refuses to publish if the two disagree.

- **Cut a release (primary path):** bump `CMakeLists.txt` to the new version,
  land it on `master`, then push the matching semver tag:
  ```bash
  git tag v1.2.3
  git push origin v1.2.3
  ```
  The tag name is used verbatim for the release and artifact names. A guard in
  the `meta` job fails the run if the tag's numeric core (`1.2.3`) does not
  equal the CMake version. The release is marked **latest**, so the in-app
  updater picks it up.

- **Pre-release:** push a hyphenated tag such as `v1.2.3-rc.1` (its core must
  still match CMake). It is published but flagged **pre-release** and kept off
  `/releases/latest`, so the auto-updater never offers it.

- **Manual test build:** run the *Release* workflow from the Actions tab
  (`workflow_dispatch`). It builds a `vX.Y.Z-dev.<short-sha>` bundle and
  attaches the artifacts to the workflow run — **nothing is tagged or
  published**. Use it to smoke-test packaging without cutting a release.

## Artifacts

| Platform | Format | How it is built |
|----------|--------|-----------------|
| Windows  | `…-windows-portable.zip` | CMake `portable` target (windeployqt bundle) |
| Windows  | `…-windows-setup.exe`    | Inno Setup ([`installer/heap.iss`](../installer/heap.iss)) wrapping the portable bundle |
| Linux    | `…-linux-amd64.deb`      | `dpkg-deb` over [`packaging/linux/`](../packaging/linux/) staging |
| Linux    | `…-linux-x86_64.AppImage`| `linuxdeploy` + the Qt plugin (best-effort; the `.deb` still ships if it fails) |
| macOS    | `…-macos.dmg`            | `macdeployqt` → `hdiutil` drag-to-Applications dmg, **ad-hoc codesigned** (Developer ID + notarized when signing secrets are set) |

## macOS signing & notarization

By default the `.app` inside the `.dmg` is **ad-hoc codesigned** (no paid Apple
Developer ID required). This gives it a *valid* signature — without it, the
`install_name_tool` rpath rewrites `macdeployqt` performs on the arm64 binary
and Qt frameworks leave broken signatures, and a downloaded (quarantined) copy
fails to launch with the fatal *"heap is damaged and can't be opened"*.

Because the ad-hoc build is not notarized, first launch still shows the
bypassable *"unidentified developer"* prompt. Open it either way:

- **Right-click → *Open*** (then *Open* again in the dialog), or
- strip the download quarantine flag:
  ```bash
  xattr -dr com.apple.quarantine /Applications/heap.app
  ```

To codesign with a *Developer ID Application* certificate, notarize and staple
the ticket automatically — which removes the prompt entirely — add these repo
secrets. The workflow's optional step activates when `MACOS_CERT_P12` is
present (it also signs with a hardened runtime + the `allow-jit` entitlement in
[`packaging/macos/heap.entitlements`](../packaging/macos/heap.entitlements) that
Qt's JS engine needs):

| Secret | Meaning |
|--------|---------|
| `MACOS_CERT_P12` | base64 of a *Developer ID Application* `.p12` certificate |
| `MACOS_CERT_PASSWORD` | password for that `.p12` |
| `MACOS_NOTARY_APPLE_ID` | Apple ID used for notarization |
| `MACOS_NOTARY_PASSWORD` | app-specific password for that Apple ID |
| `MACOS_NOTARY_TEAM_ID` | Apple Developer Team ID |

## Windows signing

Windows binaries and the installer are **unsigned** by default, so SmartScreen
shows an *"Unknown publisher"* warning on first download/run. Signing is wired to
[**SignPath Foundation**](https://signpath.org) — free Authenticode code signing
for qualifying open-source projects — and activates when `SIGNPATH_API_TOKEN` is
present (mirrors the macOS optional-signing pattern). Unsigned builds still ship
when it is absent.

**What signing does — and does not — do.** As of 2024 **no certificate removes
the SmartScreen warning instantly** ([Microsoft
Learn](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation);
EV lost its instant bypass). Signing (1) replaces *"Unknown publisher"* with the
verified publisher **"SignPath Foundation"** (the certificate is issued to the
Foundation, not to heap), and (2) lets SmartScreen reputation accumulate on that
certificate so the warning fades over downloads. The Foundation cert is shared by
many OSS projects, so it already carries some reputation — a head start over a
fresh cert. The only way to a zero-warning first launch is Microsoft Store (MSIX)
distribution, which is not used here.

Post-2023 CA rules forbid downloadable `.pfx` keys for publicly-trusted
certificates (keys must live on an HSM/token or a managed service), which is why
signing goes through SignPath's cloud service rather than a `.pfx` secret. The
flow: CI uploads the unsigned artifact as a GitHub workflow artifact,
[`signpath/github-action-submit-signing-request`](https://docs.signpath.io/trusted-build-systems/github)
submits a signing request, SignPath verifies the build origin, signs the
configured PE files (with an RFC-3161 timestamp, so signatures outlive the cert),
and returns the signed files. `heap.exe` + the bundled Qt DLLs are signed before
packaging, then the setup `.exe` is signed after Inno builds it.

Configure it after the SignPath Foundation application is approved:

| Repo setting | Kind | Meaning |
|--------------|------|---------|
| `SIGNPATH_API_TOKEN` | secret | SignPath API token with submitter permission |
| `SIGNPATH_ORG_ID` | variable | SignPath organization ID |
| `SIGNPATH_PROJECT_SLUG` | variable | SignPath project slug (e.g. `heap`) |
| `SIGNPATH_POLICY_SLUG` | variable | signing policy slug (e.g. `release-signing`) |

In the SignPath console the project needs the **GitHub.com** trusted build system
(with the SignPath GitHub App installed on the repo) and two **artifact
configurations**: `portable` (recursively signs `*.exe`/`*.dll` in the bundle) and
`installer` (signs the setup `.exe`). SignPath's OSS program requires every job up
to the signing request to run on GitHub-hosted runners — `package-windows` already
does. The uninstaller (`unins000.exe`, which Inno generates on the target machine)
is not signed.

## Follow-ups (not yet automated)

These formats from the original scope are intentionally deferred — each needs
extra tooling/infra that is easiest to add once the core three platforms are
proven:

- **Flatpak** — a `org.heap.heap.yaml` manifest built via `flatpak-builder`
  and pushed to a Flathub repo.
- **`.rpm`** — an `fpm`/`rpmbuild` job mirroring the `.deb` staging.
