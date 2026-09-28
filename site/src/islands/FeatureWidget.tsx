import { useState, useMemo } from 'react';
import Board, { type SortMode } from '../demo/Board';
import Week from '../demo/Week';
import Notes from '../demo/Notes';
import Palette from '../demo/Palette';
import Terminal from '../demo/Terminal';
import { CaptureField } from '../demo/Capture';
import { useDemoStore } from '../demo/store';
import { useToast } from '../demo/useToast';
import { weekdayIndex } from '../demo/calendar';
import { COLUMNS, PRIOS, type Prio } from '../demo/model';
import ConnectWidget from './ConnectWidget';
import type { WidgetKind } from '../data/features';
import '../demo/demo.css';
import './widgets.css';

/** The interactive piece at the top of each /features/* page. */
export default function FeatureWidget({ kind }: { kind: WidgetKind }) {
  if (kind === 'plan') return <PlanWidget />;
  if (kind === 'week') return <WeekWidget />;
  if (kind === 'notes') return <NotesWidget />;
  if (kind === 'connect') return <ConnectWidget />;
  return <FlowWidget />;
}

function Toast({ msg }: { msg: string | null }) {
  return msg ? (
    <div className="d-toast" role="status">
      {msg}
    </div>
  ) : null;
}

function PlanWidget() {
  const { state, dispatch } = useDemoStore();
  const [hidden, setHidden] = useState<Partial<Record<Prio, boolean>>>({});
  const [sort, setSort] = useState<SortMode>('manual');
  const [toast, show] = useToast();
  const shown = state.tasks.filter((t) => !hidden[t.prio]).length;
  return (
    <div className="fw">
      <div className="d-toolbar">
        <span className="d-toolbar__label">Show</span>
        {PRIOS.map((p) => (
          <button key={p} type="button" className={`d-pill d-pill--prio d-chip--${p}`} aria-pressed={!hidden[p]} onClick={() => setHidden((h) => ({ ...h, [p]: !h[p] }))}>
            {p}
          </button>
        ))}
        <span className="d-toolbar__label" style={{ marginLeft: 12 }}>
          Sort
        </span>
        {(
          [
            ['manual', 'Manual'],
            ['priority', 'Priority'],
            ['due', 'Due date'],
          ] as Array<[SortMode, string]>
        ).map(([id, label]) => (
          <button key={id} type="button" className="d-pill" aria-pressed={sort === id} onClick={() => setSort(id)}>
            {label}
          </button>
        ))}
        <span className="d-spacer" />
        <span className="d-count">
          {shown} of {state.tasks.length} tasks
        </span>
      </div>
      <div className="fw__fill">
        <Board
          tasks={state.tasks}
          dispatch={dispatch}
          selectedId={state.selectedId}
          hidden={hidden}
          sort={sort}
          onMoved={(t, to) => show(`${t.id} → ${COLUMNS.find((c) => c.id === to)!.name}`)}
        />
      </div>
      <Toast msg={toast} />
    </div>
  );
}

function WeekWidget() {
  const { state, dispatch } = useDemoStore();
  const [toast, show] = useToast();
  return (
    <div className="fw">
      <div className="fw__fill fw__fill--tall">
        <Week events={state.events} tasks={state.tasks} dispatch={dispatch} onToast={show} />
      </div>
      <Toast msg={toast} />
    </div>
  );
}

function NotesWidget() {
  const { state, dispatch } = useDemoStore();
  const [toast, show] = useToast();
  return (
    <div className="fw">
      <div className="fw__fill fw__fill--tall">
        <Notes
          notes={state.notes}
          activeNoteId={state.activeNoteId}
          tasks={state.tasks}
          dispatch={dispatch}
          onTask={(id) => show(`In the app this opens ${id} on the board`)}
        />
      </div>
      <Toast msg={toast} />
    </div>
  );
}

function FlowWidget() {
  const { state, dispatch } = useDemoStore();
  const [toast, show] = useToast();
  const todayIndex = weekdayIndex(new Date());
  const matched = state.focusedBranch ? state.tasks.find((t) => t.branch === state.focusedBranch) : undefined;
  const commands = useMemo(() => [{ id: 'reset', title: 'Reset this example', run: () => dispatch({ type: 'reset' }) }], [dispatch]);
  return (
    <div className="fw fw--flow">
      <div className="fw__pane">
        <span className="eyebrow">Quick capture</span>
        <div className="d-dialog" style={{ width: '100%' }}>
          <CaptureField
            todayIndex={todayIndex}
            onSubmit={(item) => {
              dispatch({ type: 'capture', item, todayIndex });
              show(item.kind === 'task' ? `Added “${item.title}” to To do` : `${item.kind === 'focus' ? 'Focus block' : 'Meeting'} booked for today at ${String(Math.floor(item.start! / 60)).padStart(2, '0')}:${String(item.start! % 60).padStart(2, '0')}`);
            }}
          />
        </div>
        <span className="eyebrow" style={{ marginTop: 8 }}>
          Board
        </span>
        <div className={`d-banner${matched ? ' d-banner--live' : ''}`}>
          {matched ? (
            <>
              ⎇ <span className="d-mono">{state.focusedBranch}</span> matched <strong className="d-mono">{matched.id}</strong>
            </>
          ) : (
            <>⎇ main · run the git command on the right</>
          )}
        </div>
        <Board tasks={state.tasks} dispatch={dispatch} selectedId={state.selectedId} focusedBranch={state.focusedBranch} columns={['todo', 'prog', 'review']} />
      </div>
      <div className="fw__pane">
        <span className="eyebrow">Command palette</span>
        <Palette
          inline
          tasks={state.tasks}
          notes={state.notes}
          commands={commands}
          initialQuery="rate lim"
          onTask={(id) => {
            dispatch({ type: 'select', id });
            show(`Selected ${id} on the board`);
          }}
          onNote={(id) => show(`In the app this opens the note “${state.notes.find((n) => n.id === id)?.title}”`)}
        />
        <span className="eyebrow" style={{ marginTop: 8 }}>
          Terminal
        </span>
        <Terminal lines={state.termLines} dispatch={dispatch} branch={state.focusedBranch} style={{ height: 180 }} suggestion={state.done.git ? 'git switch main' : 'git switch -c APP-112-flaky-sync-test'} />
      </div>
      <Toast msg={toast} />
    </div>
  );
}
