# Data, backups & moving your work

heap. stores everything locally — there is no account and no server. This page
covers where your data lives, how backups work, and how to move a profile
between machines today.

## Where your data lives

All state is one JSON file, `state.json`, under the platform's application-data
location (`QStandardPaths::AppDataLocation`):

| OS | Typical path |
|----|--------------|
| Windows | `%APPDATA%\heap\state.json` |
| macOS | `~/Library/Application Support/heap/state.json` |
| Linux | `~/.local/share/heap/state.json` |

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
screenshots without touching your real data. Run `heap --help` for the full
option list.

## Automatic backups

heap. rotates a timestamped copy of `state.json` into `<AppDataLocation>/backups/`.
Retention (how many copies to keep) is configurable in **Settings → Data**. To
restore, pick a backup from the same panel — the current state is replaced and
a fresh backup of the pre-restore state is taken first.

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

## File format versions

`state.json` carries a `schemaVersion`. A newer build upgrades an older file in
place on first launch (keeping a pre-migration copy in `backups/`); an older
build refuses to save over a file written by a newer one, so nothing is lost by
running an old version by mistake.

**v10** (after 0.5.2) changed how a task records its times:

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
