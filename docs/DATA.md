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
  moving), the newest usable backup is loaded, and a notice names both files.
  If the damaged file cannot be set aside at all, the session is read-only.
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

## Multi-device sync (roadmap)

Continuous multi-device sync — pointing heap. at your own **private git remote**
as canonical storage, with one human-readable file per profile and git history
for free — is on the roadmap. The serialization layer that produces those
stable, diff-friendly per-entity files already exists
(`src/sync/SyncSerializer`); the git backend, scheduler and conflict resolver
land in a later release. Until then, the export/import flow above is the
supported way to move work between machines.
