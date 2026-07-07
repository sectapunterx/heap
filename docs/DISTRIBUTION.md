# Distribution channels

`heap.` ships from [GitHub Releases](https://github.com/sectapunterx/heap/releases).
Package-manager manifests reuse those same release assets. This doc tracks each
free channel, the manifest that feeds it, and the exact steps to submit/update.

| Channel | Manifest | Status | Submission |
|---------|----------|--------|------------|
| **Scoop** (Windows) | [`bucket/heap.json`](../bucket/heap.json) | ✅ live in this repo | none — this repo *is* the bucket |
| **winget** (Windows) | [`packaging/winget/`](../packaging/winget/) | 📝 ready to PR | PR to `microsoft/winget-pkgs` |
| **Flathub** (Linux) | [`packaging/flatpak/`](../packaging/flatpak/) | 📝 draft, test then PR | PR to `flathub/flathub` |

Other channels (AUR, Snap, Chocolatey, Homebrew) are not set up yet — they need
external accounts. See "Not yet done" below.

---

## Scoop — works now

This repository is a Scoop bucket (`bucket/heap.json`). Users install with:

```powershell
scoop bucket add heap https://github.com/sectapunterx/heap
scoop install heap
```

`checkver: github` + `autoupdate` mean the manifest tracks the latest GitHub
release automatically; on a new release update `version`/`url`/`hash` (or run
`scoop update`/`checkver -u` from a Scoop clone).

To also get into the shared **Extras** bucket (more discoverable), open a PR to
[`ScoopInstaller/Extras`](https://github.com/ScoopInstaller/Extras) with a copy
of `bucket/heap.json`.

## winget — ready to PR

Manifests live in `packaging/winget/` (schema 1.6.0):
`sectapunterx.heap.yaml`, `.installer.yaml`, `.locale.en-US.yaml`.

1. Validate + test locally (Windows):
   ```powershell
   winget validate --manifest packaging\winget
   winget install --manifest packaging\winget   # optional smoke install
   ```
2. Submit — easiest with wingetcreate:
   ```powershell
   winget install Microsoft.WingetCreate
   wingetcreate submit --token <gh-token> packaging\winget
   ```
   or manually fork [`microsoft/winget-pkgs`](https://github.com/microsoft/winget-pkgs),
   copy the three files to
   `manifests/s/sectapunterx/heap/0.4.2/`, and open a PR.
3. On each release, bump `PackageVersion` + `InstallerUrl` + `InstallerSha256`
   (`sha256sum heap-<ver>-windows-setup.exe`) and repeat. `wingetcreate update`
   automates this.

> The installer is currently **unsigned**; winget's automated validation still
> accepts it, but signing (see [PACKAGING.md](PACKAGING.md)) is recommended.

## Flathub — draft, test before PR

Files in `packaging/flatpak/`: manifest `io.github.sectapunterx.heap.yaml`,
`io.github.sectapunterx.heap.metainfo.xml`, `io.github.sectapunterx.heap.desktop`.
The manifest builds from the `v0.4.2` git tag against the KDE 6 runtime.

1. Build + run locally:
   ```bash
   flatpak install flathub org.kde.Platform//6.8 org.kde.Sdk//6.8
   flatpak-builder --user --install --force-clean build-dir \
     packaging/flatpak/io.github.sectapunterx.heap.yaml
   flatpak run io.github.sectapunterx.heap
   ```
2. Validate metadata:
   ```bash
   flatpak run org.freedesktop.appstream.cli validate \
     packaging/flatpak/io.github.sectapunterx.heap.metainfo.xml
   ```
   (If `post-install` install paths fail, adjust them relative to the build cwd.)
3. Submit: fork [`flathub/flathub`](https://github.com/flathub/flathub), create a
   branch off `new-pr`, add the manifest, open a PR. A reviewer runs the build and
   may request tweaks. On approval you get a dedicated `flathub/io.github.sectapunterx.heap`
   repo; bump the `tag`/`commit` there for each release.

---

## Not yet done (need external accounts)

| Channel | What's needed |
|---------|---------------|
| **Homebrew Cask** (macOS) | own tap repo `homebrew-heap` with a cask pointing at the `.dmg`, or PR to `homebrew/homebrew-cask` (has a notability bar) |
| **AUR** (Arch) | AUR account + SSH key; push a `PKGBUILD` |
| **Snap Store** | Snapcraft account; `snapcraft.yaml` + `snapcraft upload` |
| **Chocolatey** | community account + API key; `.nuspec` + `choco push` |
| **Microsoft Store** | $19 one-time dev account + MSIX packaging (removes SmartScreen entirely) |
