// Writes src/data/state-example.json: the abridged state.json shown in the "Your data" block.
// It is cut from the newest release fixture in this repository (tests/fixtures/state/v*.json),
// brought up to the app's current schema (kSchemaVersion in src/StateSerializer.h) with the same
// steps as heap::state::migrateState, so the example is never typed by hand and never shows a
// key the app no longer writes (`deadline`, `hasTime`).
//   node tools/state-example.mjs
// Rerun when a release adds a fixture or the schema moves; tests/unit/state-example.test.ts
// fails while the committed example is behind the app.
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const repo = new URL('../../', import.meta.url);
const dir = new URL('tests/fixtures/state/', repo);

/** The schema version the app writes, read from its source. */
export function currentSchema() {
  const h = readFileSync(new URL('src/StateSerializer.h', repo), 'utf8');
  const m = h.match(/kSchemaVersion\s*=\s*(\d+)/);
  if (!m) throw new Error('kSchemaVersion not found in src/StateSerializer.h');
  return Number(m[1]);
}

const ver = (f) => f.slice(1, -5).split('.').map(Number);
const byVersion = (a, b) => ver(a).reduce((d, n, i) => d || n - ver(b)[i], 0);

// The column stages added by schema 12 (src/board/ColumnCategory.h): a built-in column is its own
// stage, any other column starts at "todo".
const STAGES = ['backlog', 'todo', 'prog', 'half', 'blocked', 'review', 'done'];

// v11 → v12 for the parts the example shows. Tracker cards also move their local edits into
// `local` (migrateTaskV11ToV12); a fixture task that is a tracker card would need that rung too.
function toV12(s) {
  for (const p of s.profiles ?? []) {
    for (const st of p.statuses ?? []) st.category ??= STAGES.includes(st.id) ? st.id : 'todo';
    if ((p.tasks ?? []).some((t) => t.externalId)) throw new Error('fixture has tracker cards: port migrateTaskV11ToV12 first');
  }
  s.schemaVersion = 12;
  return s;
}

export function buildExample() {
  const newest = readdirSync(dir).filter((f) => /^v[\d.]+\.json$/.test(f)).sort(byVersion).pop();
  let s = JSON.parse(readFileSync(new URL(newest, dir), 'utf8'));
  const target = currentSchema();
  if (s.schemaVersion < 11) throw new Error(`${newest} is schema ${s.schemaVersion}; expected 11 or newer`);
  if (s.schemaVersion < 12 && target >= 12) s = toV12(s);
  if (s.schemaVersion !== target) throw new Error(`example is schema ${s.schemaVersion}, the app writes ${target}: add the missing rung here`);

  const p = s.profiles[0];
  const t = p.tasks.find((x) => x.id === 'APP-101') ?? p.tasks[0];
  const col = p.statuses.find((x) => x.id === t.status) ?? p.statuses[0];
  const pick = (o, keys) => Object.fromEntries(keys.filter((k) => k in o).map((k) => [k, o[k]]));
  const MORE = '…'; // rendered as [ … ] on the page
  const state = {
    schemaVersion: s.schemaVersion,
    profiles: [
      {
        id: p.id,
        name: p.name,
        statuses: [pick(col, ['id', 'name', 'category']), MORE],
        tasks: [pick(t, ['id', 'title', 'status', 'priority', 'branch', 'scheduledAt', 'dueAt', 'scheduledHasTime', 'dueHasTime', 'local']), MORE],
        notes: MORE,
        people: MORE,
      },
    ],
    events: MORE,
  };
  return { source: newest, state };
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) {
  const out = buildExample();
  writeFileSync(new URL('../src/data/state-example.json', import.meta.url), JSON.stringify(out, null, 2) + '\n');
  console.log(out.source, '→ schema', out.state.schemaVersion);
}
