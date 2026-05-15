# todo·cpp

Kanban + calendar desktop app for C++ engineers. The UI lives in `design/` as
React + JSX rendered by `@babel/standalone`; this repo wraps it in Electron
so it ships as a native desktop binary.

## Develop

```sh
npm install
npm start
```

## Build a desktop binary

```sh
npm run build           # current platform
npm run build:linux     # AppImage + .deb
npm run build:mac       # .dmg + .zip
npm run build:win       # NSIS installer + portable
```

Output goes to `dist/`.

## Layout

- `main.js` — Electron main process. Creates the window and loads `design/index.html`.
- `preload.js` — preload (no Node bridge — the UI is pure React).
- `design/` — the UI:
  - `index.html` — entry point, pulls React + Babel from `node_modules`.
  - `styles.css` — design tokens (dark/light + compact/comfy density) and component CSS.
  - `app.jsx` — top-level `App`, modal editors, toast, top bar, side rail.
  - `kanban.jsx` — board with priority/search filters, drag-to-move between columns.
  - `calendar.jsx` — mini-week navigator and day grid with drag-to-create, drag-to-resize, drop-task-to-schedule.
  - `people.jsx` — "Кому написать" list with `todo → pinged → replied` state cycle.
  - `tweaks-panel.jsx` — floating tweaks panel (theme + density).
  - `data.jsx` — sample tasks, events, people.
