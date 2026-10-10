# ADR 0001: The task's local layer (`Task.local`)

- Status: accepted (2026-10-08)
- Ticket: APP-244; implementation tickets APP-236…241 (0.8.0)

## Context

0.8.0 adds data the developer keeps on top of a tracker issue: a personal
notepad (APP-237), a local checklist (APP-236), my own due date and priority
(APP-238), local tags (APP-239), "related" and "blocks" links (APP-240) and a
comment draft (APP-241). The owner's rule, which every one of them repeats:
sync never overwrites local data. That covers a pull, "take the tracker's
version" in a conflict, an issue that went upstream or out of scope,
reconnecting an integration, and an import.

Today a `Task` mixes tracker-owned and local fields. `priority` and `labels`
merge three-way against `ExternalMeta.priority/labels`, so the local value and
the shared value are the same field. Building each feature on its own would
mean 5–6 schema bumps, the `fieldCount` guard rewritten each time, and six
copies of the same "sync must not touch it" test matrix.

## Decision

1. Everything the developer keeps locally lives in one sub-struct,
   `Task.local` (`TaskLocal`): notes, checklist, myPriority, myDueAt (and its
   has-time flag), tags, related links, commentDraft, plus `extra` for keys
   this build doesn't know. No sync path writes it.
2. Tracker fields and `ExternalMeta` are written only by pull/merge, as they
   are now.
3. Effective values come from one place: `effectivePriority(t)` and
   `effectiveDue(t)` (local override, else the tracker's value). Planning,
   sorting, search, reminders, "today" and the CLI read only these.
4. The schema moves to v12 once for the release, in both serializers, with the
   `fieldCount` guard, a v12 state fixture and a v11→v12 migration rung.
5. One parameterised invariant test runs every sync path (pull, take-theirs,
   goneUpstream, outOfScope, reconnect, vault/JSON import, JsonMerger across
   devices) and checks that `local` is the same before and after. Feature
   tickets add their fields to this fixture rather than writing their own
   matrix.
6. JsonMerger merges `local` per element, the way it merges `rank`.
7. The layer's logic lives in `src/local/` as pure functions, not in
   `AppController.cpp`.

## Consequences

- One schema bump and one guard change per release, not one per feature.
- APP-238 gets clean semantics: the tracker's priority and due date stay
  visible and untouched, and mine sits beside them.
- Every reader of priority or due date in planning code has to switch to the
  effective getters. A grep audit is part of APP-244.
- Order of work: APP-244, then APP-238, then 237/236/239/240/241 grouped by
  theme. APP-243 (write-back off by default) is a precondition.

## Upgrade guarantee

The owner's call (2026-10-08): upgrading from 0.7.x to 0.8.0 loses no data at
all. Downgrading promises nothing. A v11 build opens a v12 file read-only, as
any older build does with a newer schema, and that stays as it is.

What makes the guarantee hold:

- A v11→v12 rung in `migrateState`, with the pre-migration copy
  (`backups/state-premigration-v11-<time>.json`) checked to be written.
- The rung loses nothing and changes the meaning of nothing:
  - `local` starts empty;
  - `trackedSeconds` becomes one session dated "before 0.8.0" (APP-251);
  - unknown keys survive. Today `dropPassThrough` clears `extra` on any
    document below the current schema (AppController.cpp ~10479), which would
    be a loss for v11→v12. A v11 document's pass-through has to be kept.
- Local divergence moves into `local` (owner's call, 2026-10-08). Sync with
  the remote host must never overwrite any local note or edit. For every card
  with an `externalId`:
  - `priority` differs from `ExternalMeta.priority`: it goes to
    `local.myPriority`, and the tracker field gets the tracker's value;
  - `dueAt` (and its has-time flag) differs from `ExternalMeta.dueAt`: it goes
    to `local.myDueAt` the same way;
  - labels absent from `ExternalMeta.labels` become `local.tags`, keeping
    their colour;
  - `desc` differs from `ExternalMeta.body`: the whole text goes to
    `local.notes` under a "My version of the description (before 0.8.0)"
    header, and `desc` takes the tracker's body. A differing title is kept in
    the notes the same way;
  - open `conflicts` on these fields are cleared, since the local side now
    lives in `local`;
  - an empty `ExternalMeta` value (a card from before three-way merge) is not
    a divergence, so nothing moves.
- The same rule holds at runtime in 0.8.0: "take the tracker's version" in a
  body or title conflict puts the discarded local text in `local.notes`
  instead of dropping it.
- Not just `state.json`:
  - time-machine snapshots and v11 backups restored in 0.8.0 go through the
    same migration;
  - sync files with a v11 device on the other side are read without loss;
  - attachments, secrets, settings, notes, saved views, the status log and
    task history are untouched.
- An "upgrade without loss" test. The inputs are a state fixture from every
  released 0.7.x plus an anonymised copy of a large real profile. Each goes
  load in 0.8.0, then save, then load. Afterwards every v11 field equals its
  original (apart from the additions), `extra` is intact and `--smoke` reports
  0 problems. The same runs for restoring a v11 time-machine snapshot. This
  pairs with APP-227 (migration from every version, for 1.0).
