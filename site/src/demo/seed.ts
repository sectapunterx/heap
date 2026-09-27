import type { CalEvent, DemoState, Note, Task } from './model';

export const SEED_TASKS: Task[] = [
  { id: 'APP-113', title: 'Internal logging improvements', prio: 'P3', col: 'backlog', rank: 1, due: null, desc: 'Slow-path logs inside the hot loop — needs a ring buffer.' },
  { id: 'APP-114', title: 'Export: empty report edge case', prio: 'P3', col: 'backlog', rank: 2, due: null },
  { id: 'APP-108', title: 'Race condition on profile update', prio: 'P1', col: 'todo', rank: 1, due: 5, desc: 'Avatar save sometimes lands before the profile update completes.' },
  { id: 'APP-112', title: 'Flaky test in the sync suite', prio: 'P2', col: 'todo', rank: 2, due: 3, desc: 'Fails one run in twenty on CI — timing around the rate-limit wait.' },
  { id: 'APP-110', title: 'Notification settings: granular toggles', prio: 'P2', col: 'todo', rank: 3, due: 9 },
  { id: 'APP-101', title: 'Login rate-limit bypass', prio: 'P0', col: 'prog', rank: 1, due: 1, branch: 'APP-101-login-rate-limit', pr: 'PR #4468' },
  { id: 'APP-102', title: 'API pagination: cursor drift', prio: 'P1', col: 'prog', rank: 2, due: 4, branch: 'APP-102-api-pagination' },
  { id: 'OPS-7', title: 'Rotate staging certificates', prio: 'P2', col: 'prog', rank: 3, due: 2, recurring: 'weekly' },
  { id: 'APP-103', title: 'Dashboard: empty state for new accounts', prio: 'P1', col: 'review', rank: 1, due: 2, pr: 'PR #4471' },
  { id: 'APP-099', title: 'Retry backoff for webhook delivery', prio: 'P3', col: 'done', rank: 1, due: -1 },
];

export const SEED_EVENTS: CalEvent[] = [
  ...[0, 1, 2, 3, 4].map((day) => ({ id: `standup-${day}`, title: 'Daily standup', day, start: 600, end: 630, kind: 'meeting' as const })),
  { id: 'planning', title: 'Sprint planning', day: 0, start: 840, end: 930, kind: 'meeting' },
  { id: 'review-sync', title: 'Review sync', day: 1, start: 960, end: 1020, kind: 'meeting' },
  { id: 'focus-101', title: 'Focus: APP-101', day: 2, start: 780, end: 900, kind: 'focus', taskId: 'APP-101' },
  { id: 'one-on-one', title: '1:1 with Priya', day: 3, start: 690, end: 720, kind: 'meeting' },
  { id: 'demo-day', title: 'Sprint demo', day: 4, start: 900, end: 960, kind: 'meeting' },
];

export const SEED_NOTES: Note[] = [
  {
    id: 'standup',
    title: 'Standup notes',
    pinned: true,
    body: `## Standup notes

Shipped the rate-limit fix for @Oleg — needs a second review before I flip #APP-108 to done. Follow-ups:

- [x] reuse the backoff helper on the pagination path
- [ ] ping the #APP-112 owner about the flaky test

Design lives in [[Rate limiter design]].
Open question in [[Retry budget]].`,
  },
  {
    id: 'rate-limiter',
    title: 'Rate limiter design',
    pinned: true,
    body: `## Rate limiter design

Token bucket per account, refilled every second. Burst of **10**, steady rate of **2/s**.

> Keep the counter in memory; a restart forgiving a few attempts is fine.

\`\`\`cpp
bool allow(Account& a) {
  a.refill(now());
  return a.tokens-- > 0;
}
\`\`\`

Tracked in #APP-101. See [[Standup notes]] for the rollout.`,
  },
  {
    id: 'daily',
    title: 'Today',
    daily: true,
    body: `## Today

- [ ] review #APP-103 with @Priya
- [ ] book a focus block for #APP-108
- [x] standup`,
  },
];

export function seedState(): DemoState {
  return {
    v: 1,
    tasks: SEED_TASKS.map((t) => ({ ...t })),
    events: SEED_EVENTS.map((e) => ({ ...e })),
    notes: SEED_NOTES.map((n) => ({ ...n })),
    activeNoteId: 'standup',
    view: 'board',
    selectedId: null,
    focusedBranch: null,
    termLines: ['Simulated shell in ~/src/acme-web. Type `help` for what works.'],
    guideStep: 0,
    guideOpen: true,
    done: {},
    seq: 1,
  };
}
