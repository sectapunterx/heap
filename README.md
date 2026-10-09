<p align="center">
  <img src="design/brand-export/lowkey/lowkey-wordmark-on-dark.svg" width="320" alt="lowkey">
</p>

<h3 align="center">Quiet by default.</h3>

<p align="center">A developer’s workday in one window — tickets, calendar and notes, native and keyboard-first.<br>
<sub>Formerly <b>heap</b>. Same app, same data — it moves over on the first start.</sub></p>

<p align="center">
  <a href="https://sectapunterx.github.io/heap/"><b>Website</b></a> ·
  <a href="https://sectapunterx.github.io/heap/#try">Try it in the browser</a> ·
  <a href="https://github.com/sectapunterx/heap/releases/latest"><b>Download</b></a> ·
  <a href="#documentation">Docs</a>
</p>

<div align="center">

[![Release](https://img.shields.io/github/v/release/sectapunterx/heap?sort=semver)](https://github.com/sectapunterx/heap/releases)
[![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)](https://github.com/sectapunterx/heap/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-blue)](#license)

</div>

<p align="center">
  <img src="docs/assets/img/screens/board-kanban.png" width="100%" alt="lowkey board: kanban columns, today's calendar, people to ping">
</p>

Your tickets from GitHub, Jira, GitLab and nine more trackers, your meetings and focus time, your notes — side by side
in one fast desktop app. Capture anything with a hotkey, drive everything from the keyboard, and keep it all in a file
on your own disk.

## Highlights

### Type it the way you'd say it

Press `Ctrl+Shift+Space` from anywhere and write one line. lowkey works out what it is and where it belongs — in
English or Russian.

<p align="center">
  <img src="docs/assets/img/readme/quick-capture.png" width="70%" alt="Quick-capture parsing a ticket id, priority, date, label and mention out of one line">
</p>

| You type | You get |
| --- | --- |
| `APP-231 fix login race with @Masha !! tomorrow 15:00 #auth` | task `APP-231`, priority P1, due tomorrow at 15:00, labelled `auth`, linked to Masha |
| `1:1 with @anna thursday 12:00` | a 1:1 on Thursday's calendar with Anna as an attendee |
| `focus refactor parser 10:00` | a focus block on today's calendar |
| `review PRs every weekday 10:00` | a task that repeats every weekday at 10:00 |
| `ping @viktor about the release` | a reminder in your People to ping list |

Full syntax: [First day in lowkey](docs/TUTORIAL.md#quick-capture-syntax)

### A board that knows your branch

lowkey watches your working copy. Check out a branch with the ticket in its name — `feature/app-101-login-rate-limit`
— and the top bar says you're working on `APP-101`, with its pull request and CI checks one click away. The card
carries the PR state too. Need a branch? Create one from the task's menu. No manual linking.

### Every tracker, one board

Sign in through the browser or paste a token, and issues from **GitHub, GitLab, Jira, Trello, Gitea, Forgejo,
Redmine, Todoist, Asana, ClickUp, Sentry and Bitbucket** land as cards, with their statuses mapped onto your columns.
Move a card to Done and the issue is closed upstream (GitHub, GitLab, Gitea, Forgejo). Tokens never go into
`state.json`: the Windows build keeps them in the system credential store, the macOS and Linux builds in a
`secrets.json` only your user can read. Mattermost brings in the people you work with. [More →](docs/INTEGRATIONS.md)

<p align="center">
  <img src="docs/assets/img/readme/integrations.png" width="80%" alt="Tracker integrations in Settings">
</p>

### Plan your day, not just your backlog

Tasks and calendar share one window. Drag a task onto the day to book a focus block; the week view keeps a rail of
what still needs a slot. Repeating events with this-and-following edits, all-day and past-midnight events, meeting
reminders, `.ics` import and export.

<p align="center">
  <img src="docs/assets/img/screens/board-week.png" width="100%" alt="Week view with events, deadlines and the Needs a slot rail">
</p>

### Notes that link to your work

Markdown notes with folders, a daily note, task lists, tables and highlighted code. `[[Wiki-links]]` with backlinks,
`#APP-101` points at the ticket, `@masha` at the person. Import and export as a folder of `.md` files — Obsidian
works with the same files. Long-form docs, snippets and contact cards live next door.

<p align="center">
  <img src="docs/assets/img/readme/notes.png" width="100%" alt="Notes in split view: markdown on the left, rendered on the right">
</p>

### Never reach for the mouse

`Ctrl+K` searches tasks, notes, docs and snippets at once. `J` `K` `H` `L` walk the board, `Shift` with the same keys
moves the card, `Ctrl+1`…`8` switch views. Every shortcut is rebindable from one panel (`Ctrl+/`).

## Also in the box

- **Timeline, month and archive** views of the same tasks
- **Recurring tasks** and **automation**: auto-archive, stuck-task warnings, deadline and standup reminders, quiet hours
- **Undo and redo** for every change
- **Profiles** — separate workspaces per project or job, with JSON import / export
- **Themes** — lowkey in the brand's colours by default, more dark and light presets, your own themes, contrast modes, density
- **Weekly report**, one keystroke away (`Ctrl+Shift+W`)
- A sample board and a replayable **guided tour** on first run

## Yours, and only yours

**Local-first** — one JSON file on your disk, backed up daily ([where](docs/DATA.md)) ·
**No account** · **No telemetry** · **Works offline** · **Native** — a single Qt binary, not a browser in disguise ·
**Open source** under MIT.

## Get it

Grab the latest build from [**Releases**](https://github.com/sectapunterx/heap/releases/latest):

- **Windows** — installer or portable zip. Or with [Scoop](https://scoop.sh):
  `scoop bucket add heap https://github.com/sectapunterx/heap` then `scoop install heap` (the bucket keeps the old name until the repository is renamed)
- **macOS** — `.dmg`
- **Linux** — AppImage, runs on any distro: `chmod +x lowkey-*.AppImage && ./lowkey-*.AppImage`

Prefer to build it yourself? See [docs/BUILDING.md](docs/BUILDING.md).

## Five keys to start with

| Key | Does |
| --- | --- |
| `Ctrl+Shift+Space` | Quick-capture from anywhere |
| `Ctrl+K` | Command palette and search |
| `Ctrl+1` … `8` | Board, Timeline, Week, Month, Archive, Docs, Notes, Settings |
| `J` / `K` / `H` / `L` | Move around the board |
| `Ctrl+/` | Every shortcut, rebindable |

## Command line

Note a task or check the current one without leaving the terminal. With lowkey open on the same data
directory, commands go to the window — a change shows up there at once and can be undone there; with it
closed, lowkey reads and saves `state.json` itself. Nothing here talks to the network.

```sh
lowkey add "fix login tomorrow 14:00 p1 #backend // check the refresh token"   # read like quick capture
lowkey now                    # the task with a running timer, else the one your git branch names
lowkey list --status prog     # also --profile <name>, --json
lowkey today                  # in progress, or scheduled or due today
lowkey done APP-12
lowkey open APP-12            # show it in the window (starts lowkey if it is closed)
lowkey help
```

`lowkey now` prints nothing and exits 0 when there is no current task, so it fits a shell prompt.
`--format` takes `{id} {title} {status} {priority} {profile} {source} {elapsed}`:

```toml
# starship.toml
[custom.lowkey]
command = "lowkey now --format '{id} {title}'"
when = true
format = "[$output]($style) "
```

```sh
# bash / zsh
PS1='$(lowkey now --format "[{id}] ")'"$PS1"
```

Exit codes: `0` ok, `1` usage, `2` no such task, profile or column, `3` data error. `--data-dir` and
`HEAP_DATA_DIR` work as for the app.

**Windows:** in cmd and PowerShell use `lowkey-cli` (it sits next to `lowkey.exe`): lowkey.exe is a
windowed program, so those shells neither wait for it nor see its output. `lowkey-cli` answers `now`,
`list` and `today` itself, fast enough for a prompt, and passes the rest to lowkey.exe. Add the install
folder to `PATH`, and `Set-Alias lowkey lowkey-cli` in your PowerShell profile if you like the short name.
In git-bash plain `lowkey` works too.

## Documentation

- [**First day in lowkey**](docs/TUTORIAL.md) — a ten-minute walkthrough
- [**Keyboard reference**](docs/HOTKEYS.md) — every shortcut
- [**Tracker integrations**](docs/INTEGRATIONS.md) — connecting GitHub, Jira and the rest
- [**Data & backups**](docs/DATA.md) — where your data lives, moving between machines

## Contributing

Issues and pull requests are welcome. Building, tests, CI and the code map are in
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE). Brand assets under `design/brand-export/` are MIT for use within this codebase. The
referenced fonts (IBM Plex Sans, JetBrains Mono) ship under the SIL Open Font License; see their upstream repositories.
The fonts bundled into the app (Golos Text, JetBrains Mono — `resources/fonts/`) are SIL OFL 1.1 too; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
