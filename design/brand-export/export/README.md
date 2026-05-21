# heap. — rebrand export

15 ready-to-ship asset files + 1 navigator. Drop the SVGs straight into
`design/brand-export/` to replace the old `heap.` brand.

Open `index.html` for the visual browser with previews and one-click downloads, or use the path map below to bulk-copy.

## Repo path map

| Export file                              | Target path in `sectapunterx/heap`                     |
|------------------------------------------|--------------------------------------------------------|
| `files/icon/heap-icon.svg`               | `design/brand-export/icon/heap-icon.svg`               |
| `files/icon/favicon.svg`                 | `design/brand-export/icon/favicon.svg`                 |
| `files/logo/heap-mark.svg`               | `design/brand-export/logo/heap-mark.svg`               |
| `files/logo/heap-mark-light.svg`         | `design/brand-export/logo/heap-mark-light.svg`         |
| `files/logo/heap-mark-mono.svg`          | `design/brand-export/logo/heap-mark-mono.svg`          |
| `files/logo/heap-wordmark.svg`           | `design/brand-export/logo/heap-wordmark.svg`           |
| `files/logo/heap-wordmark-light.svg`     | `design/brand-export/logo/heap-wordmark-light.svg`     |
| `files/logo/heap-lockup.svg`             | `design/brand-export/logo/heap-lockup.svg`             |
| `files/logo/heap-lockup-light.svg`       | `design/brand-export/logo/heap-lockup-light.svg`       |
| `files/surfaces/heap-splash.svg`         | `design/brand-export/surfaces/heap-splash.svg`         |
| `files/surfaces/heap-readme-banner.svg`  | `design/brand-export/surfaces/heap-readme-banner.svg`  |
| `files/surfaces/heap-marketing-hero.svg` | `design/brand-export/surfaces/heap-marketing-hero.svg` |
| `files/surfaces/heap-og-card.svg`        | `design/brand-export/surfaces/heap-og-card.svg`        |

Filenames match the originals — `git mv` is not required; the files overwrite cleanly.

## Tokens — `qml/Brand.qml` patch

Add these two properties next to the existing `accent` and `text`:

```qml
// Brand singleton — used by the wordmark, the mark, and the lockup.
// Quieter than `accent` / `text` on purpose so the identity sits behind
// the product instead of in front of it.
property color brandInk:    "#8a94a3"
property color brandAccent: "#2f5560"
```

Then in `BrandLogo.qml` swap the two references that previously read
`Brand.text` / `Brand.accent` for `Brand.brandInk` / `Brand.brandAccent`.

Inside the app-icon squircle (the bundled `.icns` / `.ico` exports), the mark is pushed one stop further so the icon
settles into a dark dock:

```qml
property color iconInk:    "#5f6878"
property color iconAccent: "#1f3d45"
```

No other QML or C++ changes are required — `Theme.qml` (and therefore the rest of the app UI) is untouched. App palette
stays exactly as it was.

## Platform icon generation

The exported `heap-icon.svg` is a 1024 master squircle. Per-platform rasters are built from it the same way the original
repo described:

```bash
# Windows .ico (needs ImageMagick)
magick design/brand-export/icon/heap-icon.svg \
       -define icon:auto-resize=256,128,64,48,32,16 heap.ico

# macOS .icns (needs librsvg + sips + iconutil)
rsvg-convert -w 1024 -h 1024 design/brand-export/icon/heap-icon.svg \
             -o heap-1024.png
# ...then the standard iconset → iconutil dance.
```

## Surface SVGs and fonts

The surface SVGs (`heap-splash`, `heap-readme-banner`, `heap-og-card`,
`heap-marketing-hero`) reference IBM Plex Sans / Serif / JetBrains Mono by name only — no `<link>` to a font CDN, same
convention as the original exports. If the host system has those fonts installed (or GitHub's CDN has them cached for
the markdown renderer), the text renders pixel-perfect; otherwise the geometry is unchanged and text falls back to the
system sans / serif / mono.

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
  `brandAccent #2f5560`) used only by the identity. The product palette (cyan `#3bccdd` accent, status hues, surfaces)
  is untouched.
- **Icon** — squircle with the muted mark inside; an extra stop darker so the dock / taskbar version doesn't punch out.

The full brandbook lives in `heap brand.html` one folder up.
