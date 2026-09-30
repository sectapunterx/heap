# Data, backups & moving your work

heap. stores everything locally — there is no account and no server. This page
covers where your data lives, how backups work, and how to move a profile
between machines today.

## Where your data lives

All state is one JSON file, `state.json`, under the platform's application-data
location (`QStandardPaths::AppDataLocation`):

| OS | Typical path |
|----|--------------|
| Windows | `%APPDATA%\heap\heap\state.json` |
| macOS | `~/Library/Application Support/heap/heap/state.json` |
| Linux | `~/.local/share/heap/heap/state.json` |

(The folder is named twice — organisation, then application.) **Settings →
About** shows the exact folder of the running copy.

`state.json` holds every profile (tasks, people, statuses, docs, notes), the
global events, and your settings blob. It is human-readable — safe to inspect,
and easy to back up by copying.

An event carries, besides its title, type, hours and dates, a few optional
fields a file from before 0.5.3 simply lacks: `location`, `notes`, `url`,
`reminderMinutes` (-1 = the notification setting, -2 = none, else minutes
before) and `tz`. `tz` is empty for an ordinary event (it is at that hour
wherever you are); a series imported from another time zone keeps the zone's
IANA name there, its hours are that zone's, and every occurrence is converted
on its own day so it follows that zone's daylight-saving changes.

### Attachments

Files attached to a task or linked from a note live in `attachments/`, next to
`state.json` (so `--data-dir` moves them too). Each file is stored once, named
by its content: the first 32 hex digits of its SHA-256 plus the original
extension, e.g. `attachments/3fa94c…c1.png`. The same file attached to three
tasks is one copy; a stored file is read-only and never changes.

- A task lists its files in an optional `attachments` array — `{id, name,
  size, mime}` per file, the name and size being what the file was when it was
  attached. A task without files has no key, and a `state.json` from before
  attachments simply has none (no schema bump).
- A note, a doc page or a task description links a file as markdown:
  `![shot.png](attachments/<id>)` for an image (shown inline in the preview),
  `[spec.pdf](attachments/<id>)` for anything else. The text is the reference —
  there is no separate list for notes.
- Detaching a file, or deleting the link, only drops the reference. **Settings →
  Data → Unused attachments** shows how many files (and how many bytes) nothing
  refers to any more and deletes them after a second press. A file counts as in
  use while any profile's tasks, descriptions, notes or pages link it, or while
  undo or redo could bring such a link back.
- A file missing from the folder (deleted by hand, or a profile imported without
  its files) shows as a broken chip; the task keeps its name and size.
- One file may be at most 100 MB. Symbolic links, junctions and shortcuts are
  never followed: attach the file itself.
- Opening a file uses its default application; a type that would run
  something (a program, a script, a shortcut) is confirmed first.

**Backups do not include attachments.** The files in `backups/` are copies of
`state.json` only; restoring one brings back the references, and the files are
still in `attachments/` unless the cleanup removed them since. To back up
everything, copy the whole data folder.

### Saved views

A profile may carry `savedViews`, the sidebar's saved views in their order. The
key is optional: a profile without views — and every file written before saved
views existed — simply has none, and no schema bump was needed. Each entry:

```json
{ "id": "view-3f9c2a1b", "name": "Urgent",
  "query": "priority:P0,P1 is:open", "priorities": ["P0"],
  "sort": "manual", "archived": false, "showDone": false, "view": "board" }
```

`query` is the search box text exactly as typed (whitespace collapsed) and is
read again against the current columns every time, so a view naming a column
that has since been deleted shows the search box's "not understood" badge
rather than an empty board. `priorities` are the filter bar chips that were
on, `sort` the board order (`manual`, `priority`, `due`, `updated`, `title`),
`archived` the Archived toggle, `showDone` the timeline's Show done, `view` the
view it opens in (`board`, `timeline`, `week`, `month`, `archive`). Unknown
values read as the defaults; entries without an id or a name are dropped.
Views travel with a profile export/import and a profile duplicate. The three
starter views a new profile gets are ordinary entries, written once when the
profile is created: delete them and they stay deleted.

The filters the window is showing right now are not per profile: they live in
the settings blob under `settings.app.filters` (`search`, `priorities`, `sort`,
`archived`, `showDone`, and `savedView`, the id of the view they were last set
from).

`reminders.json`, next to `state.json`, remembers which reminders were already
shown in the last three days, so a restart does not show them again. Deleting
it is harmless.

### Using a different directory

`--data-dir <dir>` puts `state.json`, `backups/`, `logs/` and the keychain-less
`secrets.json` fallback somewhere else for that run:

```bash
heap --data-dir /path/to/throwaway-profile
```

`HEAP_DATA_DIR` does the same for a whole shell; the flag wins when both are
set. Use it to try a build against a scratch profile, reproduce a bug, or take
screenshots without touching your real data. `--data-dir ""` is an error, never
a silent fall-back to the real profile, and an unknown option or `--view` name
exits with the usage text (code 2). Run `heap --help` for the full option list.

`heap --smoke --data-dir <dir>` checks a build against a *copy* of that
profile's `state.json` in a temporary folder: the real file is never migrated
or rewritten, and the temporary folder is removed on exit.

### One heap per data folder

A data folder is used by one running heap at a time (`heap.lock` in the
folder). Starting heap again — from the Start menu, a shortcut, or with
`--view <name>` — brings the running window forward (switching view if asked)
instead of opening a second copy that would save over the first one's edits.
A heap with a different `--data-dir` is a different workspace and runs
alongside.

### When state.json can't be used

heap never replaces a `state.json` it could not read with anything else:

- **Locked** (an antivirus scan, a backup or sync tool holding the file): heap
  waits about two seconds for the lock to lift. If it doesn't, the window opens
  **read-only** with a red banner, showing the newest backup (or an empty
  workspace) — nothing is saved over the real file. heap reopens it by itself
  once the lock lifts, or when you press **Retry** (after that, changes typed
  into the read-only session are not kept).
- **Damaged** (not JSON, or JSON without any profile): the file is kept as
  `state.corrupt-<time>.json` next to it (moved, or copied when a lock forbids
  moving) and the newest usable backup is loaded. A banner that stays up until
  you dismiss it names both files, with **Open data folder**: whatever changed
  after that backup is not in it. With no backup at all, heap opens an empty
  workspace under the same banner — not the demo and the welcome tour, since
  this is not a new install. If the damaged file cannot be set aside at all,
  the session is read-only.
- **From a newer heap** (a higher `schemaVersion`): opens read-only with a
  banner that stays up; a copy is kept once as
  `backups/state-premigration-v<N>-<time>.json`. Update heap to edit it.
- **A save fails** (read-only file, full disk, a lock): a red banner says why,
  your changes stay in memory, and heap retries on its own (2 s, 5 s, 15 s, …)
  or when you press **Retry**. An unwritable data folder is reported at start-up
  (banner, and on stderr).

Every one of these leaves a line in `logs/recovery.log`. Keys heap does not
know (from a newer point release or a hand edit) are kept on save at the
document, settings and profile level.

## Automatic backups

heap. copies `state.json` into the `backups/` folder next to it, at most once
per interval — hourly, daily (the default) or weekly, set in **Settings → Data**
— and keeps the newest 20 copies (`state-<time>.json`; the retention count is
fixed). Pre-migration copies (`state-premigration-*`) are kept apart from that
count.

To restore, pick a backup from the same panel. The current state is always
snapshotted first, whatever the interval (`state-<time>-prerestore.json`), then
replaced; undo history does not carry across a restore. If the current file
cannot even be copied (it is locked), the restore does not go ahead.

## Move one profile between machines

Each profile can be exported and re-imported independently:

1. **Export.** Top-bar profile menu → *Export* (or **Settings → Data → Export
   profile**) writes a `<profile>.todocpp.json` file.
2. **Import.** On the other machine, **Settings → Data → Import profile** (or the
   profile menu) reads that file and adds it as a new profile.
3. For a quick text snapshot instead, `Ctrl+Shift+E` copies a Markdown summary
   of the active profile to the clipboard.

Export/import is content-only — it never carries settings or other profiles, so
importing is always non-destructive.

The export carries the profile's attached files too, base64-encoded in a
top-level `attachments` array next to `profile`, so the file stands on its own
on another machine. Up to 64 MB of files are included; past that the export
still writes every task and note, leaves the files out (`attachmentsOmitted`
says how many) and says so — copy the `attachments/` folder alongside, or use
the notes-folder export. On import every file is re-hashed: its id is
recomputed from its bytes, never taken from the file, and the references follow
if the two disagree.

**Notes as a folder** (Notes → Export) copies the files the notes link into an
`attachments/` folder next to them, so `attachments/<id>` links read the same
in any markdown editor. Importing a folder brings those files back — and any
other file a note links by a relative path inside the folder (an Obsidian
`assets/shot 1.png`), which is stored and its link rewritten to
`attachments/<id>`. Links to other notes, to the web, or outside the folder are
left as written.

## Multi-device sync (roadmap)

Continuous multi-device sync — pointing heap. at your own **private git remote**
as canonical storage, with one human-readable file per profile and git history
for free — is on the roadmap. The serialization layer that produces those
stable, diff-friendly per-entity files already exists
(`src/sync/SyncSerializer`); the git backend, scheduler and conflict resolver
land in a later release. Until then, the export/import flow above is the
supported way to move work between machines.

## File format versions

`state.json` carries a `schemaVersion`. A newer build upgrades an older file in
place on first launch (keeping a pre-migration copy in `backups/`); an older
build refuses to save over a file written by a newer one, so nothing is lost by
running an old version by mistake.

**v10** (0.5.3) changed how a task records its times:

- `dueAt` and `scheduledAt` each say for themselves whether their clock time is
  real: `dueHasTime` / `scheduledHasTime` replace the single `hasTime` flag. A
  date-only deadline on a task scheduled for 14:00 used to read as "due at
  00:00" and reminded at midnight; it now stays a date and reminds at the end
  of that day. On upgrade a field keeps the old flag unless it sat at exactly
  00:00 next to a timed partner.
- Every task has a distinct `rank` (its manual place in the column). Columns
  where cards shared a rank — the demo seed, synced issues, cards saved from
  the editor — are renumbered once, in the order the board already showed.
- Recurrence may be monthly: `every:month` (this day each month) or
  `every:month:15` (the 15th, the last day in a shorter month).

Exported profiles from older builds (`hasTime`) import with the same rule.
