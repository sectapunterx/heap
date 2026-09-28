// The browser demo's data model — a small, honest sketch of heap.'s own
// (tasks in columns, calendar events, markdown notes, a focused git branch).

export type ColId = 'backlog' | 'todo' | 'prog' | 'review' | 'done';
export type Prio = 'P0' | 'P1' | 'P2' | 'P3';
export type View = 'board' | 'week' | 'notes';

export const COLUMNS: Array<{ id: ColId; name: string }> = [
  { id: 'backlog', name: 'Backlog' },
  { id: 'todo', name: 'To do' },
  { id: 'prog', name: 'In progress' },
  { id: 'review', name: 'Review' },
  { id: 'done', name: 'Done' },
];

export const PRIOS: Prio[] = ['P0', 'P1', 'P2', 'P3'];

export interface Task {
  id: string;
  title: string;
  prio: Prio;
  col: ColId;
  /** Order inside the column, ascending. */
  rank: number;
  /** Deadline as a day offset from today; null = someday. */
  due: number | null;
  desc?: string;
  branch?: string;
  pr?: string;
  recurring?: string;
  mentions?: string[];
  /** Set on cards mirrored from a tracker. */
  source?: string;
}

export interface CalEvent {
  id: string;
  title: string;
  /** 0 = Monday … 6 = Sunday of the current week. */
  day: number;
  /** Minutes from midnight. */
  start: number;
  end: number;
  kind: 'meeting' | 'focus' | 'event';
  taskId?: string;
}

export interface Note {
  id: string;
  title: string;
  body: string;
  pinned?: boolean;
  daily?: boolean;
}

export type Achievement = 'moved' | 'palette' | 'git' | 'week' | 'notes' | 'capture';

export interface DemoState {
  v: 1;
  tasks: Task[];
  events: CalEvent[];
  notes: Note[];
  activeNoteId: string;
  view: View;
  selectedId: string | null;
  focusedBranch: string | null;
  termLines: string[];
  guideStep: number;
  guideOpen: boolean;
  done: Partial<Record<Achievement, true>>;
  seq: number;
}

export const TASK_ID = /\b([A-Z][A-Z0-9]{1,9}-\d{1,6})\b/;

export function dueLabel(due: number | null): string {
  if (due === null) return 'someday';
  if (due < -1) return `overdue ${-due}d`;
  if (due === -1) return 'overdue 1d';
  if (due === 0) return 'due today';
  if (due === 1) return 'due tomorrow';
  return `due in ${due}d`;
}

export function fmtTime(min: number): string {
  const h = Math.floor(min / 60);
  const m = min % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

export function tasksIn(tasks: Task[], col: ColId): Task[] {
  return tasks.filter((t) => t.col === col).sort((a, b) => a.rank - b.rank);
}
