import { useEffect, useReducer, useRef } from 'react';
import { COLUMNS, TASK_ID, tasksIn, type Achievement, type CalEvent, type ColId, type DemoState, type Task, type View } from './model';
import { seedState } from './seed';
import type { Captured } from './capture';
import { runCommand } from './terminal';

export type Action =
  | { type: 'move'; id: string; col: ColId; before?: string | null }
  | { type: 'advance'; id: string }
  | { type: 'shift'; id: string; dir: -1 | 1 }
  | { type: 'select'; id: string | null }
  | { type: 'view'; view: View }
  | { type: 'capture'; item: Captured; todayIndex: number }
  | { type: 'event'; id: string; patch: Partial<CalEvent> }
  | { type: 'addEvent'; event: Omit<CalEvent, 'id'> }
  | { type: 'note'; id: string; body: string }
  | { type: 'openNote'; id: string }
  | { type: 'openNoteByTitle'; title: string }
  | { type: 'term'; input: string }
  | { type: 'achieve'; what: Achievement }
  | { type: 'guide'; step?: number; open?: boolean }
  | { type: 'setTasks'; tasks: Task[] }
  | { type: 'reset' };

function nextRankBefore(tasks: Task[], col: ColId, before: string | null | undefined, movingId: string): Task[] {
  const list = tasksIn(tasks, col).filter((t) => t.id !== movingId);
  const idx = before ? list.findIndex((t) => t.id === before) : -1;
  const moving = tasks.find((t) => t.id === movingId)!;
  const ordered = [...list];
  ordered.splice(idx < 0 ? ordered.length : idx, 0, { ...moving, col });
  const ranks = new Map(ordered.map((t, i) => [t.id, i + 1]));
  return tasks.map((t) => (ranks.has(t.id) ? { ...t, col: t.id === movingId ? col : t.col, rank: ranks.get(t.id)! } : t));
}

function achieve(state: DemoState, what: Achievement): DemoState {
  return state.done[what] ? state : { ...state, done: { ...state.done, [what]: true } };
}

export function reducer(state: DemoState, action: Action): DemoState {
  switch (action.type) {
    case 'move': {
      const task = state.tasks.find((t) => t.id === action.id);
      if (!task) return state;
      const moved = task.col !== action.col;
      const next = { ...state, tasks: nextRankBefore(state.tasks, action.col, action.before, action.id) };
      return moved ? achieve(next, 'moved') : next;
    }
    case 'advance':
    case 'shift': {
      const task = state.tasks.find((t) => t.id === action.id);
      if (!task) return state;
      const order = COLUMNS.map((c) => c.id);
      const i = order.indexOf(task.col);
      const j = action.type === 'advance' ? (i + 1) % order.length : Math.min(order.length - 1, Math.max(0, i + action.dir));
      if (j === i) return state;
      return reducer(state, { type: 'move', id: task.id, col: order[j], before: null });
    }
    case 'select':
      return { ...state, selectedId: action.id };
    case 'view': {
      const next = { ...state, view: action.view };
      if (action.view === 'week') return achieve(next, 'week');
      if (action.view === 'notes') return achieve(next, 'notes');
      return next;
    }
    case 'capture': {
      const { item } = action;
      const seq = state.seq + 1;
      if (item.kind === 'task') {
        const id = `NEW-${seq}`;
        const task: Task = {
          id,
          title: item.title,
          prio: 'P2',
          col: 'todo',
          rank: 0,
          due: item.due,
          desc: item.desc,
          mentions: item.mentions.length ? item.mentions : undefined,
        };
        const tasks = [task, ...state.tasks];
        return achieve({ ...state, seq, tasks: nextRankBefore(tasks, 'todo', tasksIn(state.tasks, 'todo')[0]?.id ?? null, id), selectedId: id }, 'capture');
      }
      const event: CalEvent = {
        id: `ev-${seq}`,
        title: item.kind === 'focus' ? `Focus: ${item.title}` : item.title,
        day: action.todayIndex,
        start: item.start!,
        end: Math.min(24 * 60, item.end!),
        kind: item.kind,
      };
      return achieve({ ...state, seq, events: [...state.events, event] }, 'capture');
    }
    case 'event':
      return achieve({ ...state, events: state.events.map((e) => (e.id === action.id ? { ...e, ...action.patch } : e)) }, 'week');
    case 'addEvent': {
      const seq = state.seq + 1;
      return achieve({ ...state, seq, events: [...state.events, { ...action.event, id: `ev-${seq}` }] }, 'week');
    }
    case 'note':
      return { ...state, notes: state.notes.map((n) => (n.id === action.id ? { ...n, body: action.body, title: titleOf(action.body, n.title) } : n)) };
    case 'openNote':
      return achieve({ ...state, activeNoteId: action.id, view: 'notes' }, 'notes');
    case 'openNoteByTitle': {
      const existing = state.notes.find((n) => n.title.toLowerCase() === action.title.toLowerCase());
      if (existing) return achieve({ ...state, activeNoteId: existing.id, view: 'notes' }, 'notes');
      const seq = state.seq + 1;
      const id = `note-${seq}`;
      const note = { id, title: action.title, body: `## ${action.title}\n\n` };
      return achieve({ ...state, seq, notes: [...state.notes, note], activeNoteId: id, view: 'notes' }, 'notes');
    }
    case 'term': {
      const res = runCommand(action.input, state.focusedBranch, state.tasks);
      const echoed = [...(res.clear ? [] : state.termLines), `$ ${action.input}`, ...res.lines].slice(-40);
      if (res.clear) return { ...state, termLines: [] };
      if (res.branch === undefined) return { ...state, termLines: echoed };
      const id = res.branch.toUpperCase().match(TASK_ID)?.[1];
      const matched = id && state.tasks.some((t) => t.id === id) ? id : null;
      const tasks = matched ? state.tasks.map((t) => (t.id === matched ? { ...t, branch: res.branch } : t)) : state.tasks;
      const next = { ...state, tasks, termLines: echoed, focusedBranch: res.branch, selectedId: matched ?? state.selectedId };
      return matched ? achieve(next, 'git') : next;
    }
    case 'achieve':
      return achieve(state, action.what);
    case 'guide':
      return { ...state, guideStep: action.step ?? state.guideStep, guideOpen: action.open ?? state.guideOpen };
    case 'setTasks':
      return { ...state, tasks: action.tasks };
    case 'reset':
      return seedState();
  }
}

function titleOf(body: string, fallback: string): string {
  const h = body.match(/^#{1,3}\s+(.+)$/m);
  return h ? h[1].trim() : fallback;
}

const isState = (x: unknown): x is DemoState =>
  !!x && typeof x === 'object' && (x as DemoState).v === 1 && Array.isArray((x as DemoState).tasks);

function load(persistKey: string | undefined): DemoState | null {
  if (!persistKey || typeof window === 'undefined') return null;
  try {
    const parsed: unknown = JSON.parse(localStorage.getItem(persistKey) ?? 'null');
    return isState(parsed) ? parsed : null;
  } catch {
    return null; // storage blocked or corrupt — start from the seed
  }
}

/**
 * The demo's store. With `persistKey` the state survives reloads in this
 * browser's localStorage (and nowhere else) — use it only in a client-only
 * island, since the stored state can't match server-rendered HTML.
 */
export function useDemoStore(persistKey?: string, init?: (s: DemoState) => DemoState) {
  const [state, dispatch] = useReducer(reducer, undefined, () => {
    const saved = load(persistKey);
    if (saved) return saved;
    const base = seedState();
    return init ? init(base) : base;
  });
  const first = useRef(true);

  useEffect(() => {
    if (first.current) {
      first.current = false;
      return;
    }
    if (!persistKey) return;
    try {
      localStorage.setItem(persistKey, JSON.stringify(state));
    } catch {
      /* quota or privacy mode — the demo still works, it just won't persist */
    }
  }, [persistKey, state]);

  return { state, dispatch };
}
