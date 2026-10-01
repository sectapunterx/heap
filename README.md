<p align="center">
  <img src="design/brand-export/surfaces/heap-og-card-outlined.svg?v=0.5.5" width="100%" alt="heap. — Work, in one place.">
</p>

<h3 align="center">Tickets, calendar and notes for engineers — one native, keyboard-first window.</h3>

<p align="center">
  <a href="https://sectapunterx.github.io/heap/"><b>Website</b></a> ·
  <a href="https://sectapunterx.github.io/heap/demo/">Try it in the browser</a> ·
  <a href="https://github.com/sectapunterx/heap/releases/latest"><b>Download</b></a> ·
  <a href="https://sectapunterx.github.io/heap/docs/">Docs</a>
</p>

<div align="center">

[![Release](https://img.shields.io/github/v/release/sectapunterx/heap?sort=semver)](https://github.com/sectapunterx/heap/releases)
[![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)](https://github.com/sectapunterx/heap/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-blue)](#license)

</div>

<p align="center">
  <img src="docs/assets/img/screens/board-kanban.png?v=0.5.5" width="100%" alt="heap. board: kanban columns, today's calendar, people to ping">
</p>

Your tickets from GitHub, Jira, GitLab and nine more trackers, your meetings and focus time, your notes — side by side
in one fast desktop app. Capture anything with a hotkey, drive everything from the keyboard, and keep it all in a file
on your own disk.

## Highlights

### Type it the way you'd say it

Press `Ctrl+Shift+Space` from anywhere and write one line. heap. works out what it is and where it belongs — in
English or Russian.

<p align="center">
  <img src="docs/assets/img/readme/quick-capture.png?v=0.5.5" width="70%" alt="Quick-capture parsing a ticket id, priority, date, label and mention out of one line">
</p>

| You type | You get |
| --- | --- |
| `APP-231 fix login race with @Masha !! tomorrow 15:00 #auth` | task `APP-231`, priority P1, due tomorrow at 15:00, labelled `auth`, linked to Masha |
| `1:1 with @anna thursday 12:00` | a 1:1 on Thursday's calendar with Anna as an attendee |
| `focus refactor parser 10:00` | a focus block on today's calendar |
| `review PRs every weekday 10:00` | a task that repeats every weekday at 10:00 |
| `ping @viktor about the release` | a reminder in your People to ping list |

Full syntax: [First day in heap.](docs/TUTORIAL.md#quick-capture-syntax)

### A board that knows your branch

heap. watches your working copy. Check out a branch with the ticket in its name — `feature/app-101-login-rate-limit`
— and the top bar says you're working on `APP-101`, with its pull request and CI checks one click away. The card
carries the PR state too. Need a branch? Create one from the task's menu. No manual linking.

### Every tracker, one board

Sign in through the browser or paste a token, and issues from **GitHub, GitLab, Jira, Trello, Gitea, Forgejo,
Redmine, Todoist, Asana, ClickUp, Sentry and Bitbucket** land as cards, with their statuses mapped onto your columns.
Move a card to Done and the issue is closed upstream (GitHub, GitLab, Gitea, Forgejo). Tokens live in the OS
keychain. Mattermost brings in the people you work with. [More →](docs/INTEGRATIONS.md)

<p align="center">
  <img src="docs/assets/img/readme/integrations.png?v=0.5.5" width="80%" alt="Tracker integrations in Settings">
</p>

### Plan your day, not just your backlog

Tasks and calendar share one window. Drag a task onto the day to book a focus block; the week view keeps a rail of
what still needs a slot. Repeating events with this-and-following edits, all-day and past-midnight events, meeting
reminders, `.ics` import and export.

<p align="center">
  <img src="docs/assets/img/screens/board-week.png?v=0.5.5" width="100%" alt="Week view with events, deadlines and the Needs a slot rail">
</p>

### Notes that link to your work

Markdown notes with folders, a daily note, task lists, tables and highlighted code. `[[Wiki-links]]` with backlinks,
`#APP-101` points at the ticket, `@masha` at the person. Import and export as a folder of `.md` files — Obsidian
works with the same files. Long-form docs, snippets and contact cards live next door.

<p align="center">
  <img src="docs/assets/img/readme/notes.png?v=0.5.5" width="100%" alt="Notes in split view: markdown on the left, rendered on the right">
</p>

### Never reach for the mouse

`Ctrl+K` searches tasks, notes, docs and snippets at once. `J` `K` `H` `L` walk the board, `Shift` with the same keys
moves the card, `Ctrl+1`…`8` switch views. Every shortcut is rebindable from one panel (`Ctrl+/`).

## Also in the box

- **Timeline, month and archive** views of the same tasks
- **Recurring tasks** and **automation**: auto-archive, stuck-task warnings, deadline and standup reminders, quiet hours
- **Undo and redo** for every change
- **Profiles** — separate workspaces per project or job, with JSON import / export
- **Themes** — heap. ink in the brand's colours by default, more dark and light presets, your own themes, contrast modes, density
- **Weekly report**, one keystroke away (`Ctrl+Shift+W`)
- A sample board and a replayable **guided tour** on first run

## Yours, and only yours

**Local-first** — one JSON file on your disk, backed up daily ([where](docs/DATA.md)) ·
**No account** · **No telemetry** · **Works offline** · **Native** — a single Qt binary, not a browser in disguise ·
**Open source** under MIT.

## Get it

Grab the latest build from [**Releases**](https://github.com/sectapunterx/heap/releases/latest):

- **Windows** — installer or portable zip. Or with [Scoop](https://scoop.sh):
  `scoop bucket add heap https://github.com/sectapunterx/heap` then `scoop install heap`
- **macOS** — `.dmg`
- **Linux** — AppImage, runs on any distro: `chmod +x heap-*.AppImage && ./heap-*.AppImage`

Prefer to build it yourself? See [docs/BUILDING.md](docs/BUILDING.md).

## Five keys to start with

| Key | Does |
| --- | --- |
| `Ctrl+Shift+Space` | Quick-capture from anywhere |
| `Ctrl+K` | Command palette and search |
| `Ctrl+1` … `8` | Board, Timeline, Week, Month, Archive, Docs, Notes, Settings |
| `J` / `K` / `H` / `L` | Move around the board |
| `Ctrl+/` | Every shortcut, rebindable |

## Documentation

- [**First day in heap.**](docs/TUTORIAL.md) — a ten-minute walkthrough
- [**Keyboard reference**](docs/HOTKEYS.md) — every shortcut
- [**Tracker integrations**](docs/INTEGRATIONS.md) — connecting GitHub, Jira and the rest
- [**Data & backups**](docs/DATA.md) — where your data lives, moving between machines

Also on the website, with search: [sectapunterx.github.io/heap/docs](https://sectapunterx.github.io/heap/docs/).

## Contributing

Issues and pull requests are welcome. Building, tests, CI and the code map are in
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE). Brand assets under `design/brand-export/` are MIT for use within this codebase. The
referenced fonts (IBM Plex Sans, JetBrains Mono) ship under the SIL Open Font License; see their upstream repositories.
