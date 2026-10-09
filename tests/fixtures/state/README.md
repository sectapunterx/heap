# Profiles from released versions

Each `<version>.json` is a `state.json` written by that release's own code:
its `AppController`, started on a fresh test-mode profile (the demo seed),
given a typed note with non-ASCII text, and saved. `heap_state_fixture_tests`
opens every file here with the current code and checks that each task, event,
person and the note come through, and survive a save and the next launch.

| File | Schema | Releases |
|---|---|---|
| `v0.4.7.json` | 3 | up to 0.4.7 |
| `v0.4.9.json` | 4 | 0.4.8 – 0.4.9 |
| `v0.5.1.json` | 9 | 0.5.0 – 0.5.2 |
| `v0.5.3.json` | 10 | the release after 0.5.2 (per-field clock flags, spread ranks) |
| `v0.5.4.json` | 11 | the release after 0.5.3 (task attachments, saved views; one file is attached to APP-101 — the file itself is not here, so it reads as a broken chip) |
| `v0.7.2.json` | 11 | 0.7.0 – 0.7.2, written by 0.7.2 (the last schema-11 release; `heap_upgrade_lossless_tests` checks the 0.7.x → 0.8.0 upgrade key by key against it) |

**A release that bumps `heap::state::kSchemaVersion` adds its own file** before
it ships, so the version after it is tested against it. To make one: build the
release's `AppController` (any of its AppController test suites' sources), boot
it with `QStandardPaths::setTestModeEnabled(true)` on an empty profile, call
`setNotesState()` with the note used in the files above, save, and copy the
`state.json` it wrote. Never commit a real user profile.
