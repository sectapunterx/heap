# heap. website

The site at <https://sectapunterx.github.io/heap/>: a product site with a browser demo, feature pages,
a comparison, privacy notes, downloads, the docs and the changelog.

> The primary copy of this page lives in Confluence: Software Development → Проекты → «heap. — база знаний» →
> [«Сайт heap.: устройство, разработка, публикация»](https://luxaeterna666.atlassian.net/wiki/spaces/SD/pages/21364739).
> This file mirrors it for convenience; if the two disagree, Confluence wins.

## Stack

- **[Astro](https://astro.build) 7**, static output. Every page is plain HTML; JavaScript loads only where
  something is interactive.
- **React 19 islands** for the interactive parts: the hero board, the `/demo` sandbox, the widgets on the
  feature pages and the site-wide `Ctrl+K` palette. Drag and drop: `@dnd-kit/core`. Note rendering: `marked`.
- **Plain CSS** on the app's own palette (`src/styles/tokens.css` mirrors `qml/Brand.qml` / `qml/Theme.qml`),
  dark and light themes.
- **Fonts are self-hosted** via `@fontsource` (IBM Plex Sans / Serif, JetBrains Mono). The site makes no
  third-party requests, runs no analytics and sets no cookies — an e2e test fails if a page requests another host.

## Where the content comes from

| What | Source |
|---|---|
| Docs pages (`/docs/*`) | the repository's `docs/*.md`, rendered as-is; the list and order live in `src/data/docs.ts` |
| Screenshots | `docs/assets/img/screens/*.png` — the same files the README uses; resized to AVIF/WebP at build |
| Download page, changelog | the GitHub Releases API at build time (`src/lib/github.ts`); falls back to `src/data/releases.fallback.json` if the API is unreachable |
| Release one-liners | `src/data/highlights.ts` — optional, hand-written; without one the changelog counts the notes |
| Feature copy | `src/data/features.ts` — every claim checked against the README and docs |
| Brand book (`/brand/`) | `public/brand/`, a static page with its own CSS and self-hosted fonts |

Links between docs (`HOTKEYS.md#…`) become site links and `../src/…` links point at GitHub
(`src/lib/remark-doc-links.mjs`), so the same Markdown works on GitHub and on the site.

## Develop

```sh
cd site
npm ci
npm run dev          # http://localhost:4321/heap/
npm run check        # astro check (types)
npm test             # unit tests (vitest)
npm run build        # static site in dist/
npx playwright install chromium   # once
npm run test:e2e     # builds must exist; serves dist/ and runs Playwright on desktop + phone
```

Set `ASTRO_TELEMETRY_DISABLED=1` to stop Astro's anonymous CLI telemetry (CI does).

## Layout

```
site/
├─ src/pages/          ← one file per route (index, demo, features/[area], compare, privacy, download, docs/[slug], changelog, 404)
├─ src/layouts/        ← Base (head, nav, footer, palette) and DocLayout
├─ src/components/     ← Astro components (Nav, Footer, OsFiles, DownloadButton, …)
├─ src/islands/        ← React islands used by pages (HeroBoard, FeatureWidget, ConnectWidget, SitePalette)
├─ src/demo/           ← the browser demo: model, reducer, board, week, notes, palette, terminal, quick capture
├─ src/data/           ← site copy and lists (features, docs, highlights, release snapshot)
├─ src/lib/            ← helpers: base-aware URLs, releases, OS detection, search, docs link rewriting
├─ public/             ← favicon, social card, brand book
└─ tests/              ← unit/ (vitest) and e2e/ (Playwright)
```

## The browser demo

`src/demo/` is a small model of heap. — tasks in columns, calendar events, Markdown notes, a focused git branch —
driven by one reducer (`store.ts`). The `/demo` page keeps its state in `localStorage` (`heap-demo-v1`); the
widgets on other pages start fresh on every visit. Pure logic (quick-capture parsing, note rendering, the pretend
shell, calendar layout, the reducer) is unit-tested.

## Deploy

`.github/workflows/pages.yml` builds, type-checks and tests the site on every pull request that touches `site/`,
`docs/` or `design/brand-export/`, and deploys to GitHub Pages on pushes to `master`. It also rebuilds after the
Release workflow finishes, so the download page and changelog follow each release.

## Adding things

- **A doc page** — add the Markdown file to `docs/`, then an entry in `src/data/docs.ts`.
- **A release one-liner** — add the tag to `src/data/highlights.ts`.
- **A feature claim** — edit `src/data/features.ts`; keep it verifiable.

## Known issues

- The app screenshots in `docs/assets/img/screens` show a real profile name (`eNB-core`) in the breadcrumb and
  a "NaNd" deadline bug on the Backlog cards (`board-kanban.png`). Re-shoot them on a neutral profile.
- In `design/brand-export/surfaces/heap-og-card.svg` the wordmark's dot is a separate text element at a fixed
  position, so without IBM Plex Sans installed it renders as "heap .". `public/og.png` is rendered from it.
