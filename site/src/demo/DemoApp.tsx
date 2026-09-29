import { useCallback, useEffect, useMemo, useState } from 'react';
import Board from './Board';
import Week from './Week';
import Notes from './Notes';
import Palette, { type Command } from './Palette';
import Terminal from './Terminal';
import { CaptureField, CaptureNotice } from './Capture';
import type { Captured } from './capture';
import { useDemoStore } from './store';
import { useToast } from './useToast';
import { COLUMNS, type Achievement, type View } from './model';
import { weekdayIndex } from './calendar';
import { toggleTheme } from '../lib/theme';
import { BoardIcon, Mark, NotesIcon, PlusIcon, SearchIcon, TerminalIcon, ThemeIcon, WeekIcon, BranchIcon } from './icons';
import './demo.css';
import './demo-app.css';

const GUIDE: Array<{ title: string; body: string; goal: Achievement }> = [
  { title: 'This is your board', body: 'Drag a card into another column — or select one and press Shift+L. In the app it works the same way.', goal: 'moved' },
  { title: 'Everything is one keystroke away', body: 'Press Ctrl+K (⌘K on a Mac) to search tasks, notes and commands at once.', goal: 'palette' },
  { title: 'It follows your git branch', body: 'Open the terminal (the ` key) and run the suggested git command. Watch APP-112 get matched.', goal: 'git' },
  { title: 'Your week, next to your work', body: 'Press 2 or pick Week in the rail. Drag an event, pull its edge, or book a focus block for a task.', goal: 'week' },
  { title: 'Capture without leaving the flow', body: 'Press N and type “focus refactor parser 16:00” — heap. books the block for you.', goal: 'capture' },
];

const VIEWS: Array<{ id: View; label: string; key: string }> = [
  { id: 'board', label: 'Board', key: '1' },
  { id: 'week', label: 'Week', key: '2' },
  { id: 'notes', label: 'Notes', key: '3' },
];

function typing(el: EventTarget | null) {
  const n = el as HTMLElement | null;
  return !!n && (n.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(n.tagName));
}

export default function DemoApp() {
  const { state, dispatch } = useDemoStore('heap-demo-v1');
  const [palette, setPalette] = useState(false);
  const [capture, setCapture] = useState(false);
  const [term, setTerm] = useState(false);
  const [toast, showToast] = useToast();
  const [notice, showNotice] = useToast<Captured>(6000);
  const todayIndex = weekdayIndex(new Date());

  const openTask = useCallback(
    (id: string) => {
      dispatch({ type: 'view', view: 'board' });
      dispatch({ type: 'select', id });
      requestAnimationFrame(() => document.querySelector<HTMLElement>(`[data-card="${id}"]`)?.focus());
    },
    [dispatch],
  );

  const commands = useMemo<Command[]>(
    () => [
      ...VIEWS.map((v) => ({ id: `go-${v.id}`, title: `Go to ${v.label}`, hint: v.key, run: () => dispatch({ type: 'view', view: v.id }) })),
      { id: 'capture', title: 'Quick-capture a task', hint: 'N', run: () => setCapture(true) },
      { id: 'terminal', title: 'Open the terminal', hint: '`', run: () => setTerm(true) },
      { id: 'theme', title: 'Toggle light / dark theme', run: () => toggleTheme() },
      { id: 'tour', title: 'Restart the guided tour', run: () => dispatch({ type: 'guide', step: 0, open: true }) },
      { id: 'reset', title: 'Reset the demo', run: () => dispatch({ type: 'reset' }) },
    ],
    [dispatch],
  );

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        setPalette((p) => !p);
        dispatch({ type: 'achieve', what: 'palette' });
        return;
      }
      if (e.ctrlKey && e.shiftKey && e.code === 'Space') {
        e.preventDefault();
        setCapture(true);
        return;
      }
      if (typing(e.target) || e.ctrlKey || e.metaKey || e.altKey) return;
      if (e.key === 'Escape') {
        setPalette(false);
        setCapture(false);
      } else if (e.key === 'n' || e.key === 'N') {
        if (e.shiftKey) return;
        e.preventDefault();
        setCapture(true);
      } else if (e.key === '`') {
        e.preventDefault();
        setTerm((t) => !t);
      } else {
        const v = VIEWS.find((x) => x.key === e.key);
        if (v) dispatch({ type: 'view', view: v.id });
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [dispatch]);

  const step = GUIDE[state.guideStep];
  const stepDone = step ? !!state.done[step.goal] : false;
  const matched = state.focusedBranch ? state.tasks.find((t) => t.branch === state.focusedBranch) : undefined;
  const inProgress = state.tasks.filter((t) => t.col === 'prog').length;

  return (
    <div className="da">
      <div className="da__top">
        <div className="da__brand">
          <Mark size={20} />
          <span>
            heap<span style={{ color: 'var(--accent)' }}>.</span>
          </span>
        </div>
        <div className="da__crumbs">
          acme-web <span>/</span> sprint-14 <span>/</span> You
        </div>
        <span className="d-spacer" />
        <button
          type="button"
          className="da__search"
          aria-label="Search tasks, notes and commands (Ctrl K)"
          onClick={() => {
            setPalette(true);
            dispatch({ type: 'achieve', what: 'palette' });
          }}
        >
          <SearchIcon size={14} />
          <span className="da__search-label">Search tasks, notes, commands…</span>
          <kbd className="kbd kbd--sm">Ctrl K</kbd>
        </button>
        <button type="button" className="d-btn da__hide-sm" onClick={() => setTerm((t) => !t)} aria-pressed={term}>
          <TerminalIcon size={13} /> Terminal
        </button>
        <button type="button" className="d-btn d-btn--primary" onClick={() => setCapture(true)}>
          <PlusIcon size={13} /> Task
        </button>
      </div>

      <div className="da__body">
        <nav className="da__rail" aria-label="Views">
          {VIEWS.map((v) => (
            <button key={v.id} type="button" className="da__railbtn" aria-pressed={state.view === v.id} aria-label={`${v.label} (${v.key})`} title={`${v.label} · ${v.key}`} onClick={() => dispatch({ type: 'view', view: v.id })}>
              {v.id === 'board' ? <BoardIcon /> : v.id === 'week' ? <WeekIcon /> : <NotesIcon />}
            </button>
          ))}
          <span className="d-spacer" />
          <button type="button" className="da__railbtn" aria-label="Toggle theme" title="Toggle theme" onClick={() => toggleTheme()}>
            <ThemeIcon />
          </button>
        </nav>

        <main className="da__main">
          {state.view === 'board' && (
            <>
              <div className="d-toolbar">
                <strong>Board</strong>
                <span className="d-count">
                  {state.tasks.length} tasks · {inProgress} in progress
                </span>
                <span className="d-spacer" />
                <span className="da__hint">
                  Drag cards · <kbd className="kbd kbd--sm">J</kbd> <kbd className="kbd kbd--sm">K</kbd> <kbd className="kbd kbd--sm">⇧ L</kbd>
                </span>
              </div>
              <div className={`d-banner${matched ? ' d-banner--live' : ''}`}>
                <BranchIcon />
                {matched ? (
                  <>
                    <span className="d-mono">{state.focusedBranch}</span> matched <strong className="d-mono">{matched.id}</strong> · focused repo acme-web
                  </>
                ) : (
                  <>
                    <span className="d-mono">{state.focusedBranch ?? 'main'}</span> · no task on this branch —
                    <button type="button" className="d-pill" style={{ height: 24 }} onClick={() => setTerm(true)}>
                      open the terminal
                    </button>
                  </>
                )}
              </div>
              <div className="da__fill">
                <Board
                  tasks={state.tasks}
                  dispatch={dispatch}
                  selectedId={state.selectedId}
                  focusedBranch={state.focusedBranch}
                  onMoved={(t, to) => showToast(`${t.id} → ${COLUMNS.find((c) => c.id === to)!.name}`)}
                />
              </div>
            </>
          )}
          {state.view === 'week' && (
            <>
              <div className="d-toolbar">
                <strong>Week</strong>
                <span className="d-spacer" />
                <span className="da__hint">Drag to create · drag to move · pull the bottom edge to resize</span>
              </div>
              <div className="da__fill">
                <Week events={state.events} tasks={state.tasks} dispatch={dispatch} onToast={showToast} />
              </div>
            </>
          )}
          {state.view === 'notes' && (
            <div className="da__fill">
              <Notes notes={state.notes} activeNoteId={state.activeNoteId} tasks={state.tasks} dispatch={dispatch} onTask={openTask} />
            </div>
          )}
          {term && (
            <Terminal
              lines={state.termLines}
              dispatch={dispatch}
              branch={state.focusedBranch}
              autoFocus
              onClose={() => setTerm(false)}
              suggestion={state.done.git ? 'git switch main' : 'git switch -c APP-112-flaky-sync-test'}
              style={{ height: 190, flexShrink: 0 }}
            />
          )}
        </main>
      </div>

      {step && state.guideOpen && (
        <aside className="d-guide" aria-label="Guided tour" aria-live="polite">
          <span className="d-guide__step">
            Tour · {state.guideStep + 1} of {GUIDE.length}
          </span>
          <span className="d-guide__title">{step.title}</span>
          <span className="d-guide__body">{step.body}</span>
          {stepDone && <span className="d-guide__done">✓ Done</span>}
          <div className="d-guide__actions">
            <button
              type="button"
              className={`d-btn${stepDone ? ' d-btn--primary' : ''}`}
              onClick={() => dispatch(state.guideStep === GUIDE.length - 1 ? { type: 'guide', open: false } : { type: 'guide', step: state.guideStep + 1 })}
            >
              {state.guideStep === GUIDE.length - 1 ? 'Finish' : stepDone ? 'Next' : 'Skip step'}
            </button>
            <button type="button" className="d-btn" onClick={() => dispatch({ type: 'guide', open: false })}>
              Close tour
            </button>
          </div>
        </aside>
      )}

      {palette && (
        <Palette
          tasks={state.tasks}
          notes={state.notes}
          commands={commands}
          onTask={openTask}
          onNote={(id) => dispatch({ type: 'openNote', id })}
          onClose={() => setPalette(false)}
        />
      )}

      {capture && (
        <div className="d-scrim" onMouseDown={(e) => e.target === e.currentTarget && setCapture(false)}>
          <div className="d-dialog" role="dialog" aria-modal="true" aria-label="Quick capture">
            <CaptureField
              autoFocus
              todayIndex={todayIndex}
              onCancel={() => setCapture(false)}
              onSubmit={(item) => {
                dispatch({ type: 'capture', item, todayIndex });
                setCapture(false);
                if (item.kind === 'focus' || item.kind === 'meeting') dispatch({ type: 'view', view: 'week' });
                else if (item.kind === 'task') dispatch({ type: 'view', view: 'board' });
                showNotice(item);
              }}
            />
          </div>
        </div>
      )}

      {notice && <CaptureNotice item={notice} todayIndex={todayIndex} />}
      {toast && (
        <div className="d-toast" role="status">
          {toast}
        </div>
      )}
    </div>
  );
}
