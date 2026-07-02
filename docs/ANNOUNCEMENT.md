# heap. — public release announcement

Reusable copy for the GitHub Release body, Show HN, Reddit, and social. Trim to
fit each channel. Replace `<REPO_URL>` and `<RELEASE_URL>` before posting.

---

## Long form (GitHub Release / blog / Show HN body)

**heap. — Work, in one place.**
*A native, local-first desktop planner for engineers: kanban board, calendar,
notes and docs in one keyboard-driven window.*

I got tired of keeping tasks in a browser tab, the calendar in another, notes in
a third, and paying latency (and my attention) for the privilege. heap. puts all
of it in **one native binary** — no Electron, no browser, no account, no server.
Your data is a plain JSON file on your disk.

### What it is

- **Kanban board** — drag-and-drop columns, priority chips (P0–P3), branch tags,
  scheduled-time pills.
- **Three time views** — a deadline-bucketed Timeline, a 7-day Week grid, and a
  drag-to-create Day calendar where overlapping events sit side-by-side and you
  can drop a task to book a focus block.
- **Docs & Notes** — sections, syntax-highlighted snippets, contact cards, and a
  per-profile markdown canvas with `@people` / `#ticket` autocomplete.
- **Quick-capture** — one hotkey opens a single field; type
  `ship v1 tomorrow 14:00 @lena // needs review` and it parses the deadline,
  the mention and the description (English **and** Russian dates) and files the
  task in under two seconds.
- **Profiles** — feature-scoped workspaces, each with its own tasks/people/docs,
  exportable as JSON.
- **Command palette** (`Ctrl+K`), a fully **rebindable** hotkey catalog, quiet-
  hours-aware deadline/standup reminders, light/dark + high-contrast + reduced-
  motion.

### Why it might be for you

It's **local-first and boring on purpose**: one file you can read, back up, and
diff. It's **keyboard-first**: most days you never touch the mouse. And it's a
**single ~native app** that starts instantly and stays out of the way.

### Get it

Downloads for **Windows** (installer + portable), **Linux** (`.deb` + AppImage)
and **macOS** (`.dmg`) are on the releases page: `<RELEASE_URL>`.
Build from source (Qt 6.4+, C++20) per the README.

### Under the hood

Qt 6 / QML + C++20, one `qt_add_executable` target. Unit-tested (chrono parser,
text/quick-capture parsing, models, controller logic) with CI across Linux and
Windows plus an ASan/UBSan run. MIT licensed.

### What's next

Continuous multi-device sync via your **own private git remote** (the diff-
friendly serializer already lives in the tree), and two-way sync with
Jira/GitHub/GitLab. Feedback and issues welcome: `<REPO_URL>`.

---

## Short forms

**Show HN / HN title**
> Show HN: heap. – a local-first native task board, calendar and notes for engineers

**Reddit (r/QtFramework, r/opensource, r/productivity) title**
> heap. — a single-binary, local-first planner (board + calendar + notes) built in Qt 6 / C++20 [MIT]

**Tweet / Mastodon (≤280)**
> heap. is out — a native, local-first desktop planner for engineers: kanban board, calendar, notes & docs in one keyboard-driven window. No Electron, no account, your data is one JSON file. Win/macOS/Linux, MIT. <RELEASE_URL>

**One-liner**
> heap. — Work, in one place. A native, local-first board + calendar + notes app for engineers.

---

## Posting checklist

- [ ] Tag the release (`git tag vX.Y.Z && git push --tags`) — the Release
      workflow builds and attaches all platform artifacts (see
      [PACKAGING.md](PACKAGING.md)).
- [ ] Paste the long form into the GitHub Release body (or let the workflow's
      auto-notes handle the changelog and prepend the intro).
- [ ] Replace `<REPO_URL>` / `<RELEASE_URL>` placeholders.
- [ ] Attach a screenshot or short screen capture (see
      `docs/assets/img/screens/`).
- [ ] Post Show HN in the morning (US), cross-post to Reddit, then social.
