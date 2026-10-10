<p align="center">
  <img src="design/brand-export/lowkey/lowkey-wordmark-on-dark.svg" width="320" alt="lowkey">
</p>

<h3 align="center">Quiet by default.</h3>

<p align="center">A developer’s workday in one window — tickets, meetings and notes, from the keyboard.</p>

<p align="center">
  <a href="https://github.com/sectapunterx/lowkey/releases/latest"><b>Download</b></a> ·
  <a href="https://sectapunterx.github.io/lowkey/">Website — the tour</a> ·
  <a href="#documentation">Docs</a>
</p>

<div align="center">

[![Release](https://img.shields.io/github/v/release/sectapunterx/lowkey?sort=semver)](https://github.com/sectapunterx/lowkey/releases)
[![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)](https://github.com/sectapunterx/lowkey/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-blue)](#license)

</div>

lowkey is a personal desktop app: your tickets from GitHub, GitLab, Jira and nine more trackers, your meetings, and
your notes, in one window you drive from the keyboard. It keeps everything in a file on your disk, needs no
account, and writes nothing to your trackers unless you switch that on. What it looks like and why it exists is on
the [website](https://sectapunterx.github.io/lowkey/); this page is about getting it running and finding your way
around.

## Install

Download from [Releases](https://github.com/sectapunterx/lowkey/releases/latest):

| System | File | Then |
| --- | --- | --- |
| Windows | `lowkey-*-windows-setup.exe` | Run it. Or take `lowkey-*-windows-portable.zip` and start `lowkey.exe` from any folder. |
| macOS | `lowkey-*-macos.dmg` | Open it and drag lowkey into Applications. |
| Linux | `lowkey-*-linux-x86_64.AppImage` | `chmod +x lowkey-*.AppImage && ./lowkey-*.AppImage` — nothing else to install. |

Updates: lowkey checks for a new version on start and installs it only when you click **Update**. The check is
off-switchable in Settings → About.

## The first ten minutes

1. **Write a task.** The app opens on Today with an input line. Type `fix login tomorrow 15:00 p1 #auth` and
   press Enter. From anywhere else: `Ctrl+Shift+Space`.
2. **Connect a tracker.** Settings → Trackers → pick yours → sign in through the browser, or paste a token.
   Issues come in read-only. Moving a card changes the issue upstream only after you tick *Change the status in
   …* for that tracker.
3. **Add a repository.** Settings → Git Watcher. From then on the task named in your branch (`APP-112-…`) shows at the top
   of the window.
4. **Bring your notes.** Profile menu at the top of the sidebar → *Import notes folder…* — an Obsidian vault or
   any folder of `.md` files. You see what comes in before anything is copied.
5. **Look around without risk.** On the very first start, the empty Today offers an example: a filled profile of
   its own to try things on, kept apart from your data and easy to remove.

More: [First day in lowkey](docs/TUTORIAL.md).

## Keys to learn first

| Key | Does |
| --- | --- |
| `Ctrl+Shift+Space` | New task from any app |
| `Ctrl+K` | Command line: find, filter, run |
| `?` | Every key on one screen |
| `Ctrl+1` `2` `3` | Today, Tasks, Knowledge (`Ctrl+,` Settings) |
| `g b` `g l` `g c` | Board, List, Calendar |
| `j` `k` / `h` `l` | Move the cursor |
| `d` | Done (again: back) |
| `/` | Filter the section you are in |

Single letters never fire while you are typing, and they work in any keyboard layout. Every key can be changed:
`?` → *Change shortcuts…*. Full list: [docs/HOTKEYS.md](docs/HOTKEYS.md).

## Finding things

The line above Tasks takes plain words and conditions, the same way in Board, List and Calendar. A finished
condition turns into a chip; save the lot as a view and it stays in the sidebar.

```
status:blocked          due:week              scheduled:none        is:overdue
priority:p0,p1          #label                branch:login          estimate:>2h
has:notes               sprint:current        -status:done          bug OR crash
```

All of it: [Quick-capture and search syntax](docs/TUTORIAL.md#quick-capture-syntax).

## Your data

| | Windows | macOS | Linux |
| --- | --- | --- | --- |
| Data | `%APPDATA%\lowkey\lowkey\` | `~/Library/Application Support/lowkey/lowkey/` | `~/.local/share/lowkey/lowkey/` |

- `state.json` — everything: tasks, meetings, notes, settings.
- `backups/` — scheduled copies (daily, last 20 kept); `history/` — the time machine’s snapshots.
- `logs/lowkey.log` — attach it to a bug report.
- Tracker tokens are not in `state.json`: the Windows build keeps them in the system credential store, macOS and
  Linux in a `secrets.json` only your user can read.

Two machines: profile menu → *Export to JSON…*, then import it on the other one — importing only adds. Details:
[docs/DATA.md](docs/DATA.md).

## From the terminal

```sh
lowkey today            # overdue first, then today
lowkey add "review PR tomorrow 11:00 #api"
lowkey now              # the current task — fits a shell prompt
```

On Windows use `lowkey-cli` in cmd and PowerShell. Everything else: [docs/CLI.md](docs/CLI.md).

## Documentation

- [First day in lowkey](docs/TUTORIAL.md) — a ten-minute walkthrough, capture and search syntax
- [Keyboard](docs/HOTKEYS.md) — every key and how to change it
- [Trackers](docs/INTEGRATIONS.md) — connecting each one, what is read and what may be written
- [Data & backups](docs/DATA.md) — files, backups, moving between machines
- [Command line](docs/CLI.md)

## Contributing

Bug reports and pull requests are welcome — include `logs/lowkey.log` with a bug. Building from source and the
code map are in [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE). Brand assets under `design/brand-export/` are MIT for use within this codebase. The
fonts bundled into the app (Golos Text, JetBrains Mono) are SIL OFL 1.1; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
