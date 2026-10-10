# lowkey website

The site at <https://sectapunterx.github.io/lowkey/>: one page in two languages — `/` English, `/ru/` Russian —
plus a download page for each (`/download/`, `/ru/download/`) and a 404. Pages of the 0.7 site
(`/demo/`, `/docs/…`, `/features/…`, `/compare/`, `/privacy/`, `/changelog/`, `/brand/`) redirect to the
closest place (`astro.config.mjs`).

Every claim on it is listed in [PROMISES.md](PROMISES.md) with the app feature behind it. Change a claim →
change its row.

## Stack

- **Astro 7**, static output. **GSAP** (ScrollTrigger) and **Lenis** for the scroll scenes; both respect
  `prefers-reduced-motion`.
- Fonts are self-hosted via `@fontsource` (Golos Text, JetBrains Mono). The site makes no third-party
  requests, runs no analytics and sets no cookies — an e2e test fails if a page requests another host.
- The app's screens are not pictures: they are live HTML from the 0.8.0 redesign mockups, put on the page by
  `src/components/Screen.astro` inside a declarative shadow root (so the site's styles cannot leak in) and
  scaled from a 1440×900 canvas by `src/scripts/landing.ts`.

## Where things are

| What | Where |
|---|---|
| All copy, ru + en | `src/data/i18n.ts` (runtime strings of the capture demo: `src/scripts/landing.ts`) |
| The repository name (download links, releases API, source links) | `REPO` in `src/lib/site.ts`; the Pages path is `base` in `astro.config.mjs` |
| Download files and sizes | GitHub Releases API at build time (`src/lib/github.ts`), else `src/data/releases.fallback.json` |
| Scoop on the download page | shown only while `../bucket/heap.json` installs the latest release (`src/lib/scoop.ts`) |
| state.json example | `src/data/state-example.json`, generated — see below |
| Screens | `src/screens/<name>.html` (ru) and `<name>.en.html` (generated) |
| Page frame, search, nav | `src/layouts/Page.astro`, `src/scripts/site.ts` |
| Home page | `src/components/Landing.astro`, `src/scripts/landing.ts` |
| Download page | `src/components/Download.astro` |

## Develop

```sh
cd site
npm ci
npm run dev          # http://localhost:4321/heap/
npm run check        # astro check (types)
npm test             # unit tests (vitest)
npm run build        # static site in dist/
npx playwright install chromium   # once
npm run test:e2e     # serves dist/ and runs Playwright on desktop + phone
```

Set `ASTRO_TELEMETRY_DISABLED=1` to stop Astro's anonymous CLI telemetry (CI does).

## Screens

After the mockups change, re-extract the fragments (Playwright's Chromium renders the `.dc.html` sheets):

```sh
MOCKUPS="C:/Users/Fin/Desktop/Code/New heap design/screens" node tools/extract-screens.mjs H2-Board H2-Today H2-Calendar H2-Task H2-Knowledge Q-Board
```

`X-Capture.html` was made from `X-Oth-Capture` by hand (sheet title and frame removed, windows moved into
the frame) — repeat that when re-extracting it.

English screens are generated from the Russian ones with the dictionary `tools/screens.en.json`:

```sh
node tools/screen-strings.mjs strings.json   # every Russian string, with the translations known so far
npm run screens:en                           # fails on any string without a translation
```

`tests/unit/screens.test.ts` fails when a screen has a string without a translation, or when the committed
`.en.html` files are not what the translator makes now.

## The state.json example

Not typed by hand: `npm run state-example` cuts it from the newest release fixture in
`../tests/fixtures/state/` and brings it up to the schema the app writes (`kSchemaVersion` in
`../src/StateSerializer.h`). `tests/unit/state-example.test.ts` fails when the example lags the schema;
when the schema moves, port the new rung into `tools/state-example.mjs` and rerun it.

## Deploy

`.github/workflows/pages.yml` builds, type-checks and tests the site on every pull request that touches
`site/`, the state fixtures, `src/StateSerializer.h` or `bucket/`, and deploys to GitHub Pages on pushes to
`master`. It also rebuilds after the Release workflow, so the download sizes follow each release.
