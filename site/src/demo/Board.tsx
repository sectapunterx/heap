import { useMemo, useRef, useState, type Dispatch, type KeyboardEvent } from 'react';
import {
  DndContext,
  DragOverlay,
  PointerSensor,
  TouchSensor,
  pointerWithin,
  closestCenter,
  useDraggable,
  useDroppable,
  useSensor,
  useSensors,
  type CollisionDetection,
  type DragEndEvent,
  type DragOverEvent,
  type DragStartEvent,
} from '@dnd-kit/core';
import { COLUMNS, dueLabel, tasksIn, type ColId, type Prio, type Task } from './model';
import type { Action } from './store';
import { BranchIcon } from './icons';

export type SortMode = 'manual' | 'priority' | 'due';

interface BoardProps {
  tasks: Task[];
  dispatch: Dispatch<Action>;
  selectedId?: string | null;
  focusedBranch?: string | null;
  columns?: ColId[];
  hidden?: Partial<Record<Prio, boolean>>;
  sort?: SortMode;
  /** Click a card to push it one column right (the home-page board). */
  clickToAdvance?: boolean;
  label?: string;
  onMoved?: (task: Task, to: ColId) => void;
}

const COL_COLOR: Record<ColId, string> = {
  backlog: 'var(--st-backlog)',
  todo: 'var(--st-todo)',
  prog: 'var(--st-prog)',
  review: 'var(--st-review)',
  done: 'var(--st-done)',
};

const collision: CollisionDetection = (args) => {
  const hits = pointerWithin(args);
  return hits.length ? hits : closestCenter(args);
};

function sorted(list: Task[], sort: SortMode): Task[] {
  if (sort === 'priority') return [...list].sort((a, b) => a.prio.localeCompare(b.prio) || a.rank - b.rank);
  if (sort === 'due') return [...list].sort((a, b) => (a.due ?? 999) - (b.due ?? 999) || a.rank - b.rank);
  return list;
}

export default function Board({
  tasks,
  dispatch,
  selectedId = null,
  focusedBranch = null,
  columns = COLUMNS.map((c) => c.id),
  hidden = {},
  sort = 'manual',
  clickToAdvance = false,
  label = 'Board',
  onMoved,
}: BoardProps) {
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 160, tolerance: 8 } }),
  );
  const [dragId, setDragId] = useState<string | null>(null);
  const [overId, setOverId] = useState<string | null>(null);
  const boardRef = useRef<HTMLDivElement>(null);

  const visible = useMemo(() => tasks.filter((t) => !hidden[t.prio]), [tasks, hidden]);
  const byCol = useMemo(() => {
    const m = new Map<ColId, Task[]>();
    for (const c of columns) m.set(c, sorted(tasksIn(visible, c), sort));
    return m;
  }, [visible, columns, sort]);

  const dragTask = dragId ? tasks.find((t) => t.id === dragId) : undefined;

  const moveTo = (task: Task, col: ColId, before: string | null) => {
    dispatch({ type: 'move', id: task.id, col, before });
    if (task.col !== col) onMoved?.(task, col);
  };

  const onDragStart = (e: DragStartEvent) => setDragId(String(e.active.id));
  const onDragOver = (e: DragOverEvent) => setOverId(e.over ? String(e.over.id) : null);
  const onDragEnd = (e: DragEndEvent) => {
    setDragId(null);
    setOverId(null);
    const task = tasks.find((t) => t.id === String(e.active.id));
    const over = e.over ? String(e.over.id) : null;
    if (!task || !over) return;
    if (over.startsWith('card:')) {
      const targetId = over.slice(5);
      if (targetId === task.id) return;
      const target = tasks.find((t) => t.id === targetId);
      if (target) moveTo(task, target.col, target.id);
    } else if (over.startsWith('col:')) {
      moveTo(task, over.slice(4) as ColId, null);
    }
  };

  const focusCard = (id: string) => {
    dispatch({ type: 'select', id });
    requestAnimationFrame(() => boardRef.current?.querySelector<HTMLElement>(`[data-card="${id}"]`)?.focus());
  };

  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    const key = e.key.toLowerCase();
    if (!['j', 'k', 'h', 'l', 'arrowdown', 'arrowup', 'arrowleft', 'arrowright'].includes(key)) return;
    const cur = tasks.find((t) => t.id === selectedId) ?? byCol.get(columns[0])?.[0] ?? visible[0];
    if (!cur) return;
    e.preventDefault();
    const ci = columns.indexOf(cur.col);
    const list = byCol.get(cur.col) ?? [];
    const ri = list.findIndex((t) => t.id === cur.id);
    const down = key === 'j' || key === 'arrowdown';
    const up = key === 'k' || key === 'arrowup';
    const left = key === 'h' || key === 'arrowleft';
    if (e.shiftKey && (left || key === 'l' || key === 'arrowright')) {
      const to = columns[ci + (left ? -1 : 1)];
      if (to) {
        moveTo(cur, to, null);
        focusCard(cur.id);
      }
      return;
    }
    if (down || up) {
      const next = list[ri + (down ? 1 : -1)];
      if (next) focusCard(next.id);
      return;
    }
    for (let step = 1; step < columns.length; step++) {
      const col = columns[ci + (left ? -step : step)];
      if (!col) break;
      const target = byCol.get(col) ?? [];
      if (target.length) {
        focusCard(target[Math.min(Math.max(ri, 0), target.length - 1)].id);
        break;
      }
    }
  };

  return (
    <DndContext sensors={sensors} collisionDetection={collision} onDragStart={onDragStart} onDragOver={onDragOver} onDragEnd={onDragEnd} onDragCancel={() => setDragId(null)}>
      <div className="d-board" ref={boardRef} role="group" aria-label={label} onKeyDown={onKeyDown}>
        {columns.map((col) => {
          const meta = COLUMNS.find((c) => c.id === col)!;
          const list = byCol.get(col) ?? [];
          return (
            <Column key={col} id={col} name={meta.name} color={COL_COLOR[col]} count={list.length} isOver={overId === `col:${col}`}>
              {list.map((t) => (
                <Card
                  key={t.id}
                  task={t}
                  selected={t.id === selectedId}
                  matched={!!focusedBranch && t.branch === focusedBranch}
                  ghost={t.id === dragId}
                  dropBefore={overId === `card:${t.id}` && dragId !== t.id}
                  onClick={() => (clickToAdvance ? dispatch({ type: 'advance', id: t.id }) : dispatch({ type: 'select', id: t.id }))}
                  nextName={clickToAdvance ? nextColName(t.col) : undefined}
                />
              ))}
              {list.length === 0 && <div className="d-col__empty">Drop a card here</div>}
            </Column>
          );
        })}
      </div>
      <DragOverlay dropAnimation={null}>{dragTask ? <CardBody task={dragTask} className="d-card d-card--overlay" /> : null}</DragOverlay>
    </DndContext>
  );
}

function nextColName(col: ColId): string {
  const i = COLUMNS.findIndex((c) => c.id === col);
  return COLUMNS[(i + 1) % COLUMNS.length].name;
}

function Column({ id, name, color, count, isOver, children }: { id: ColId; name: string; color: string; count: number; isOver: boolean; children: React.ReactNode }) {
  const { setNodeRef } = useDroppable({ id: `col:${id}` });
  return (
    <section ref={setNodeRef} className={`d-col${isOver ? ' d-col--over' : ''}`} aria-label={`${name}, ${count} cards`}>
      <div className="d-col__head">
        <span className="d-col__dot" style={{ background: color }} />
        <span className="d-col__name">{name}</span>
        <span className="d-col__count">{count}</span>
      </div>
      {children}
    </section>
  );
}

interface CardProps {
  task: Task;
  selected: boolean;
  matched: boolean;
  ghost: boolean;
  dropBefore: boolean;
  onClick: () => void;
  nextName?: string;
}

function Card({ task, selected, matched, ghost, dropBefore, onClick, nextName }: CardProps) {
  const drag = useDraggable({ id: task.id });
  const drop = useDroppable({ id: `card:${task.id}` });
  const cls = [
    'd-card',
    task.col === 'done' && 'd-card--done',
    selected && 'd-card--selected',
    matched && 'd-card--matched',
    ghost && 'd-card--ghost',
    dropBefore && 'd-card--drop-before',
  ]
    .filter(Boolean)
    .join(' ');
  const { role: _role, tabIndex: _tab, ...attrs } = drag.attributes;
  return (
    <button
      {...attrs}
      {...drag.listeners}
      type="button"
      ref={(node) => {
        drag.setNodeRef(node);
        drop.setNodeRef(node);
      }}
      data-card={task.id}
      className={cls}
      onClick={onClick}
      aria-pressed={selected}
    >
      <CardInner task={task} />
      <span className="sr-only">{nextName ? `. Activate to move to ${nextName}.` : '. Shift+H or Shift+L moves it.'}</span>
    </button>
  );
}

function CardBody({ task, className }: { task: Task; className: string }) {
  return (
    <div className={className}>
      <CardInner task={task} />
    </div>
  );
}

function CardInner({ task }: { task: Task }) {
  const due = dueLabel(task.due);
  const dueCls = task.col !== 'done' && task.due !== null && task.due < 0 ? 'd-overdue' : task.col !== 'done' && task.due !== null && task.due <= 1 ? 'd-soon' : undefined;
  return (
    <>
      <span className="d-card__row">
        <span className="d-card__id">{task.id}</span>
        <span className={`d-chip d-chip--${task.prio}`}>{task.prio}</span>
        {task.recurring && <span className="d-card__meta" style={{ marginLeft: 'auto' }}>↻ {task.recurring}</span>}
      </span>
      <span className="d-card__title">{task.title}</span>
      {task.branch && (
        <span className="d-card__branch">
          <BranchIcon size={10} /> {task.branch}
        </span>
      )}
      <span className="d-card__meta">
        <span className={dueCls}>{task.col === 'done' ? 'closed' : due}</span>
        {task.pr && <span>{task.pr}</span>}
        {task.source && <span>{task.source}</span>}
        {task.mentions?.map((m) => <span key={m}>@{m}</span>)}
      </span>
    </>
  );
}
