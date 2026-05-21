# heap. — brand export for Qt 6 / QML

Brand bundle for `sectapunterx/heap` (Qt 6 + QML + CMake). The 2026 rebrand introduces a new mark (three-node binary
heap), a new tagline (`Work, in one place.`), and two identity-only color tokens (`brandInk` / `brandAccent`) that sit
beside the existing product palette (cyan `accent` etc., untouched).

## Layout

```
brand-export/
├─ logo/
│  ├─ heap-mark.svg           ← mark, dark surface
│  ├─ heap-mark-light.svg     ← mark, light surface
│  ├─ heap-mark-mono.svg      ← single-color (currentColor)
│  ├─ heap-lockup.svg         ← horizontal lockup: mark + "heap."
│  ├─ heap-lockup-light.svg
│  ├─ heap-wordmark.svg       ← wordmark only
│  └─ heap-wordmark-light.svg
├─ icon/
│  ├─ heap-icon.svg           ← 1024 master squircle, app icon source
│  ├─ heap-icon.ico           ← Windows multi-resolution icon
│  ├─ heap-icon.rc            ← Windows resource (compiled into heap.exe)
│  └─ favicon.svg             ← 32×32 favicon
├─ surfaces/
│  ├─ heap-splash.svg
│  ├─ heap-readme-banner.svg
│  ├─ heap-marketing-hero.svg
│  └─ heap-og-card.svg        ← 1200×630 social card
├─ export/                    ← navigator + raw export bundle (`index.html`)
├─ brand.css                  ← brandbook tokens as CSS variables
└─ heap brand.html            ← full brandbook
```

`BrandLogo.qml` paints the lockup with native QML primitives, so the brand renders even without the `qsvg` plugin. The
SVGs above are bundled into
`qrc:/brand/...` by `qt_add_resources` in the root `CMakeLists.txt` for the app icon and any consumer that prefers
vector assets.

## Tokens

Two new identity-only colors live next to `accent` / `text` in
`qml/Brand.qml`:

```qml
// Brand singleton — used by the wordmark, the mark, and the lockup.
// Quieter than `accent` / `text` on purpose so the identity sits behind
// the product instead of in front of it.
property color brandInk:    "#8a94a3"
property color brandAccent: "#2f5560"
```

Inside the app-icon squircle (the bundled `.icns` / `.ico` exports), the mark is pushed one stop further so the icon
settles into a dark dock:

```qml
property color iconInk:    "#5f6878"
property color iconAccent: "#1f3d45"
```

The product palette (cyan `#3bccdd` accent, status hues, surfaces) is untouched — `Theme.qml` and the rest of the app UI
continue to use
`Brand.accent` / `Brand.text` directly.

## Platform icon generation

`heap-icon.svg` is a 1024 master squircle. Per-platform rasters:

```bash
# Windows .ico (needs ImageMagick)
magick design/brand-export/icon/heap-icon.svg \
       -define icon:auto-resize=256,128,64,48,32,16 \
       design/brand-export/icon/heap-icon.ico

# macOS .icns (needs librsvg + sips + iconutil)
rsvg-convert -w 1024 -h 1024 design/brand-export/icon/heap-icon.svg \
             -o heap-1024.png
# ...then the standard iconset → iconutil dance.
```

## Surface SVGs and fonts

The surface SVGs (`heap-splash`, `heap-readme-banner`, `heap-og-card`,
`heap-marketing-hero`) reference IBM Plex Sans / Serif / JetBrains Mono by name only — no `<link>` to a font CDN. If the
host system has those fonts installed the text renders pixel-perfect; otherwise geometry is unchanged and text falls
back to the system sans / serif / mono.

For a guaranteed-identical render on social cards (`og:image`) and the README banner, pre-rasterise to PNG:

```bash
rsvg-convert -w 1280 -h 640 design/brand-export/surfaces/heap-readme-banner.svg \
             -o design/brand-export/surfaces/heap-readme-banner.png
```

## What changed vs the old `heap.`

- **Name** — unchanged, still `heap.`.
- **Mark** — new geometry. Three-node binary heap (root + two leaves + two edges) instead of the old heap-tree
  silhouette.
- **Wordmark** — IBM Plex Sans 500, slate ink, dark-teal terminal stop.
- **Lockup** — mark + wordmark on a shared baseline, 12 px gap.
- **Slogan** — `Work, in one place.` (was `heap.push(task)`). Long-form alt: `A quiet place for the work you owe.`
- **Brand palette** — two new tokens (`brandInk #8a94a3`,
  `brandAccent #2f5560`) used only by the identity.
- **Icon** — squircle with the muted mark inside; an extra stop darker so the dock / taskbar version doesn't punch out.

The full brandbook lives in [`heap brand.html`](heap%20brand.html); the exporter view with previews and one-click
downloads is in
[`export/index.html`](export/index.html).
