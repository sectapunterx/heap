# What the site promises, and what backs it

Every claim on the site (both languages, home page and download page), the app feature behind it, and
its state when the site was written (branch `heap2/0.8.0` at `deeb506`, 2026-10-09). Before the 0.8.0
site goes live, check each row against the 0.8.0 build and tick it. A claim the build does not back is
either built or taken off the site — never left in.

Status: **built** — in the code today · **planned** — in the mockups / `keymap.md` / 0.8.0 tickets,
not in the code yet · **gap** — the site says it, the code says something else; owner decides.

Copy lives in `src/data/i18n.ts`; section names below follow the page.

## Hero, noise, demo

| # | Claim | Backed by | Status | 0.8.0 ✓ |
|---|---|---|---|---|
| 1 | No sign-up, works offline, Windows / macOS / Linux | no account code; `release.yml` builds all three | built | ☐ |
| 2 | Tracker tasks and calendar meetings in one feed for the day | Today screen (`TodayView.qml`), .ics subscriptions | built | ☐ |
| 3 | Capture: date, time, `#label`, priority `p0`–`p3` picked up from the words (ru + en) | `CaptureParse.h`, `ChronoLocale_ru/en.cpp`, `TaskTextUtils.cpp` | built | ☐ |
| 4 | `d` or a click on the circle closes a task | `AppController.cpp` shortcut list (`d`) | built | ☐ |
| 5 | Demo empty state «Пусто. Можно выдохнуть.» / "Empty. Breathe out." | site demo only (one of the two emotional lines) | — | — |

## A day with lowkey

| # | Claim | Backed by | Status | 0.8.0 ✓ |
|---|---|---|---|---|
| 6 | Meetings and tasks for the day in one feed on Today | `TodayView.qml` | built | ☐ |
| 7 | Calendar week and tasks in one view; drag a task onto a slot schedules it | `WeekView.qml:1165`, `DayCalendar.qml:534`, `scheduleTask` | built | ☐ |
| 8 | Ctrl Shift Space from any app, even minimized; Ctrl Shift N for a note | global hotkeys, `CaptureWindow.qml` (Wayland needs the GlobalShortcuts portal) | built | ☐ |
| 9 | A task opens as a document: properties on top, text and checklist, saves itself | `TaskDocument.qml` (APP-265), autosave 600 ms | built | ☐ |
| 10 | Knowledge: notes and docs in one section; `#APP-112` in a note becomes a link with the task's title | `Sidebar.qml` "Knowledge", `MdHtml.cpp:71` | built | ☐ |
| 11 | The five screens shown are the heap 2 mockups (`src/screens/*`, from `New heap design/screens`) | mockups H2-Today, H2-Calendar, X-Oth-Capture, H2-Task, H2-Knowledge | planned — the 0.8.0 UI must match them | ☐ |

## Git

| # | Claim | Backed by | Status | 0.8.0 ✓ |
|---|---|---|---|---|
| 12 | Repositories are added in Settings → Git; the branch is read from `.git/HEAD` | `GitWatcher.cpp` ("Watched repositories") | built | ☐ |
| 13 | A branch name with a task id (APP-112) puts that task at the top of the window | `TopBar.qml` "Working on %1" | built | ☐ |
| 14 | Heading: "the right task is already highlighted" | the top bar names the task (git "работаю над…" line, `TopBar.qml`); the board card itself is **not** highlighted — the APP-281 A3 branch row was reverted in 0.8.1 review 3 (the sheet's cards show no branch), and `focusedTaskId` is used nowhere on the board | **gap** — highlight the card, or reword to what the top bar does; owner decides | ☐ |
| 15 | PR state from your own `gh` / `glab`, about once a minute; on the card under the cursor | `GitWatcher.cpp:517`, `TaskCard.qml:761`; "Pull PR state (gh / glab)" | built | ☐ |
| 16 | On a branch switch the task moves to In Progress; off in Settings → Git | "Move task to In Progress", on by default | built | ☐ |
| 17 | No bindings, no plugins | matching by id in the branch name; no IDE plugin | built | ☐ |
| 18 | The scene uses `git switch APP-112-…` (an existing branch), not `git switch -c` | a new branch has no PR yet, so the PR line would be false with `-c` | — | — |

Only the card whose branch is checked out shows it (branch icon + name); every other card shows no branch (DG-023).

## Keyboard (per `New heap design/keymap.md`)

| # | Claim | Backed by | Status | 0.8.0 ✓ |
|---|---|---|---|---|
| 19 | `j` `k` through a list, a board column and the Today feed | shortcut list | built | ☐ |
| 20 | `d` — done; on a done task brings it back; Ctrl Z undoes | `AppController.h:602` | built | ☐ |
| 21 | `s` — schedule, date in words | keymap.md | planned | ☐ |
| 22 | Ctrl 1–3 — Today, Tasks, Knowledge | shortcut list | built | ☐ |
| 23 | `g b` / `g l` / `g c` / `g t` | keymap.md (no prefix handling in code yet) | planned | ☐ |
| 24 | `y y` copy id, `y b` branch name, `y l` tracker link | keymap.md | planned | ☐ |
| 25 | Ctrl K — command line | shortcut list | built | ☐ |
| 26 | `?` — cheat sheet with every key | APP-272 | planned | ☐ |
| 27 | Keys follow the physical key, so they work in any layout | keymap.md rule 4 | planned | ☐ |
| 28 | Any shortcut can be rebound | keymap.md rule 7 (APP-272) | planned | ☐ |
| 29 | Single letters only act while you aren't typing; Ctrl shortcuts work everywhere | keymap.md rule 1 | planned | ☐ |
| 30 | Site demo ignores a second `d` within 0.5 s | keymap.md rule 6 (site mimics it) | planned | ☐ |

The site's own keys: Ctrl K and `/` open the search, `g g` goes to the top, Shift G to the end.

## Style

| # | Claim | Backed by | Status | 0.8.0 ✓ |
|---|---|---|---|---|
| 31 | Bold style by default, quiet on request | `qml/Style.qml` (default `bold`) | built (the styles) | ☐ |
| 32 | Switch in Settings, no restart | mockup N-Set-StyleKeys; `Style.apply` is called nowhere yet | planned | ☐ |
| 33 | Tagline "Quiet by default." next to "Bold style by default" | owner's tagline; reads as the product's attitude, not the style setting | — owner may want one of them reworded | — |

## Built like a tool, not a service

| # | Claim | Backed by | Status | 0.8.0 ✓ |
|---|---|---|---|---|
| 34 | Native, Qt 6 · C++20, no browser inside | `CMakeLists.txt:19, 62` | built | ☐ |
| 35 | The Linux AppImage carries its own Qt | `release.yml` linuxdeploy-plugin-qt | built | ☐ |
| 36 | Nothing in the background: runs while the window or tray icon is open | no service/daemon; tray in `NotificationCenter_tray.cpp` | built | ☐ |
| 37 | Start at login only if you turn it on | "Start at login", off by default (`lowkey.iss` adds no entry) | built | ☐ |
| 38 | MIT, source on GitHub; free, no paid tier, no trial, no account | `LICENSE` | built | ☐ |

## Your data

| # | Claim | Backed by | Status | 0.8.0 ✓ |
|---|---|---|---|---|
| 39 | Paths: `%APPDATA%\lowkey\lowkey`, `~/Library/Application Support/lowkey/lowkey`, `~/.local/share/lowkey/lowkey` | `main.cpp:275`, `Paths.cpp:31`, `Brand.h` | built | ☐ |
| 40 | heap 0.7 data copied once on first start; old folder kept with `MOVED-TO-LOWKEY.txt` | `LegacyData.cpp`, `Brand.h:27` | built | ☐ |
| 41 | `backups` next to state.json: daily by default, last 20 kept | `AppController.cpp:171, 7873`, "Auto backup" | built | ☐ |
| 42 | `history` time machine: hourly for 48 h, daily for 30 days | `Snapshots.h` | built | ☐ |
| 43 | Tokens not in state.json: Windows → system credential store; macOS / Linux builds → `secrets.json`, owner-only | `SecretStore.h`; `release.yml` (QtKeychain only in the Windows build) | built — **gap vs. APP-281 B4** ("tokens in the system keychain"): the macOS and Linux release builds have no QtKeychain. Add it, or keep this honest wording | ☐ |
| 44 | Notes export as a Markdown folder Obsidian opens, and import back | `MdVault.h` | built | ☐ |
| 45 | state.json example is schema 12 (`statuses[].category`, `scheduledAt` / `dueAt`, no `deadline`) | generated by `tools/state-example.mjs` from `tests/fixtures/state/v0.7.2.json` + the v11→v12 rung; `tests/unit/state-example.test.ts` fails when it lags `kSchemaVersion` | built | ☐ |
| 46 | Tracker cards carry a `local` layer (notes, checklist, tags, dates) a sync never overwrites | `TaskLocal.cpp`, APP-244 | built | ☐ |
| 47 | Read-only by default; status write-back per tracker ("Change the status in %1 when I move a card"); titles, descriptions, comments never written | `integrations.<id>.writeStatus`, `IntegrationProvider.h:33` | built | ☐ |
| 48 | Write-back exists for GitHub, GitLab, Gitea, Forgejo, Jira (the rest are pull-only) | `ProviderRegistry.cpp` | built | ☐ |
| 49 | Backups and time machine: "Nothing gets lost" | rows 41–42 | built | ☐ |

### What the app sends on its own ("the complete list")

| # | Claim | Backed by | Status | 0.8.0 ✓ |
|---|---|---|---|---|
| 50 | Update check on start, off in Settings → About; downloads only on Update; checked against SHA256SUMS | `Updater.cpp`, `SettingsView.qml:3521` | built | ☐ |
| 51 | Trackers: only connected; by hand or on a timer you set (auto-sync is off by default) | `autoSyncMinutes: 0` | built | ☐ |
| 52 | Browser sign-in opens the tracker's own page; the app never sees the password | `OAuthManager.cpp` (loopback 127.0.0.1:51789) | built | ☐ |
| 53 | Calendar links: the .ics at your URL, every 15 min by default | `AppController.cpp:4510` | built | ☐ |
| 54 | PR state: your `gh` / `glab`, ~once a minute, only for added repositories | `GitWatcher.cpp` | built | ☐ |
| 55 | Mattermost: reads the people of your channels for @mentions, posts nothing | `MattermostClient.cpp` | built | ☐ |
| 56 | Pictures from the web in notes only on click | `MdHtml.h:41` | built | ☐ |
| 57 | No analytics, no crash reports | `RecoveryLog.h:10`; nothing else found | built | ☐ |

Recheck this list against every `QNetworkRequest` in the 0.8.0 build: the site says it is complete.

### Trackers and sign-in

| # | Claim | Backed by | Status | 0.8.0 ✓ |
|---|---|---|---|---|
| 58 | GitHub, GitLab, Jira, Trello, Gitea, Forgejo, Redmine, Todoist, Asana, ClickUp, Sentry, Bitbucket, Mattermost | `ProviderRegistry.cpp:660` | built | ☐ |
| 59 | Browser sign-in: GitHub, GitLab, Sentry (any build); Jira, Trello, Todoist, Asana, ClickUp, Bitbucket (release builds, OAuth secrets) | `OAuthClients.h`, `release.yml:180` | built | ☐ |
| 60 | Gitea / Forgejo: token, or your own OAuth app; Redmine: API key; Mattermost: token or login, password not stored | `ProviderRegistry.cpp:219, 278, 642` | built | ☐ |

## FAQ

| # | Claim | Backed by | Status | 0.8.0 ✓ |
|---|---|---|---|---|
| 61 | Several machines: profile export / import as JSON, import only adds; or copy state.json while closed | row 7 of the code check (`AppController.cpp:12392`) | built | ☐ |
| 62 | Not for teams; the tracker stays the shared place | rows 47–48 | built | ☐ |
| 63 | Obsidian: import with a preview, export to a new folder, `[[wiki-links]]` kept, `.obsidian` skipped | `MdVault.h` | built | ☐ |
| 64 | English and Russian, switchable in Settings | `I18n.qml` | built | ☐ |
| 65 | heap 0.7's own update check finds 0.8.0 | `release.yml:697` also uploads `heap-*` copies of the assets | built | ☐ |

## Download

| # | Claim | Backed by | Status | 0.8.0 ✓ |
|---|---|---|---|---|
| 66 | Files and sizes of the latest release | GitHub Releases API at build time; `src/data/releases.fallback.json` (0.7.2 snapshot) | built | ☐ |
| 67 | Installer adds a Start menu entry and an uninstaller; portable zip runs from any folder | `installer/lowkey.iss` | built | ☐ |
| 68 | macOS: open the disk image, drag lowkey into Applications | `packaging/macos/make-dmg.sh` | built | ☐ |
| 69 | AppImage: chmod +x and run, Qt inside | `release.yml` | built | ☐ |
| 70 | From source: Qt 6.9+ and a C++20 compiler | `CMakeLists.txt:62–69` | built | ☐ |
| 71 | Scoop | `bucket/heap.json` — **shown only while its version equals the latest release** (`src/lib/scoop.ts`). Today it is 0.5.0 under the heap name, so the page hides it. Bump the bucket (lowkey 0.8.0, `lowkey.exe`) and Scoop appears by itself | hidden | ☐ |
| 72 | Uninstall leaves the data folder | data folder is outside the install dir | built | ☐ |

winget and Flathub manifests are drafts at 0.5.0 (`docs/DISTRIBUTION.md`), so the site does not mention them.

## The site itself

- Makes no third-party requests, sets no cookies, runs no analytics (e2e test `renders cleanly`).
- The product name is lowercase everywhere and never starts a sentence (e2e tests).
- At most two emotional lines per page: «Восемь вкладок, чтобы понять, что делать сейчас?» and «Пусто. Можно выдохнуть.».
