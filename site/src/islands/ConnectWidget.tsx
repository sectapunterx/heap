import { useEffect, useState } from 'react';
import Board from '../demo/Board';
import { useDemoStore } from '../demo/store';
import { useToast } from '../demo/useToast';
import type { ColId, Task } from '../demo/model';

// A walk-through of connecting a tracker. Nothing here talks to the network:
// the "issues" are sample data.

interface Provider {
  id: string;
  mono: string;
  name: string;
  auth: string;
  /** Status is written back on column moves (open/closed). */
  writeBack: boolean;
  ref: (n: number) => string;
  people?: boolean;
}

const PROVIDERS: Provider[] = [
  { id: 'github', mono: 'GH', name: 'GitHub', auth: 'Browser sign-in, device code or token', writeBack: true, ref: (n) => `acme/web#${n}` },
  { id: 'gitlab', mono: 'GL', name: 'GitLab', auth: 'Browser sign-in or token', writeBack: true, ref: (n) => `acme/web!${n}` },
  { id: 'jira', mono: 'Ji', name: 'Jira', auth: 'Browser sign-in or token', writeBack: false, ref: (n) => `WEB-${n}` },
  { id: 'trello', mono: 'Tr', name: 'Trello', auth: 'Browser sign-in or token', writeBack: false, ref: (n) => `card ${n}` },
  { id: 'gitea', mono: 'Gt', name: 'Gitea', auth: 'Token', writeBack: true, ref: (n) => `acme/web#${n}` },
  { id: 'forgejo', mono: 'Fj', name: 'Forgejo', auth: 'Token', writeBack: true, ref: (n) => `acme/web#${n}` },
  { id: 'redmine', mono: 'Rm', name: 'Redmine', auth: 'Token', writeBack: false, ref: (n) => `#${n}` },
  { id: 'todoist', mono: 'Td', name: 'Todoist', auth: 'Browser sign-in or token', writeBack: false, ref: (n) => `task ${n}` },
  { id: 'asana', mono: 'As', name: 'Asana', auth: 'Browser sign-in or token', writeBack: false, ref: (n) => `task ${n}` },
  { id: 'clickup', mono: 'Cu', name: 'ClickUp', auth: 'Browser sign-in or token', writeBack: false, ref: (n) => `#${n}` },
  { id: 'sentry', mono: 'Se', name: 'Sentry', auth: 'Browser sign-in or token', writeBack: false, ref: (n) => `WEB-${n.toString(36).toUpperCase()}` },
  { id: 'bitbucket', mono: 'Bb', name: 'Bitbucket', auth: 'Browser sign-in or token', writeBack: false, ref: (n) => `acme/web#${n}` },
  { id: 'mattermost', mono: 'Mm', name: 'Mattermost', auth: 'Token', writeBack: false, ref: (n) => `@${n}`, people: true },
];

const ISSUES = [
  { n: 231, title: 'Session cookie not refreshed after SSO login', prio: 'P1' as const, col: 'todo' as ColId, due: 2 },
  { n: 227, title: 'Crash when a webhook payload is empty', prio: 'P0' as const, col: 'prog' as ColId, due: 0 },
  { n: 219, title: 'Document the rate-limit headers', prio: 'P3' as const, col: 'todo' as ColId, due: 6 },
];

type Phase = 'idle' | 'auth' | 'syncing' | 'done';

export default function ConnectWidget() {
  const [pid, setPid] = useState('github');
  const [phase, setPhase] = useState<Phase>('idle');
  const { state, dispatch } = useDemoStore(undefined, (s) => ({ ...s, tasks: [] }));
  const [toast, show] = useToast(3200);
  const p = PROVIDERS.find((x) => x.id === pid)!;

  useEffect(() => {
    if (phase === 'auth') {
      const t = setTimeout(() => setPhase('syncing'), 1100);
      return () => clearTimeout(t);
    }
    if (phase === 'syncing') {
      const t = setTimeout(() => {
        const tasks: Task[] = ISSUES.map((i, k) => ({
          id: `WEB-${i.n}`,
          title: i.title,
          prio: i.prio,
          col: i.col,
          rank: k + 1,
          due: i.due,
          source: `${p.name} · ${p.ref(i.n)}`,
        }));
        dispatch({ type: 'setTasks', tasks });
        setPhase('done');
      }, 900);
      return () => clearTimeout(t);
    }
  }, [phase, p, dispatch]);

  const pick = (id: string) => {
    setPid(id);
    setPhase('idle');
    dispatch({ type: 'setTasks', tasks: [] });
  };

  const onMoved = (task: Task, to: ColId) => {
    const ref = task.source?.split(' · ')[1] ?? task.id;
    if (!p.writeBack) {
      show(`Moved on your board. ${p.name} isn’t written back — the change stays in heap.`);
    } else if (to === 'done') {
      show(`${ref} closed on ${p.name}`);
    } else if (task.col === 'done') {
      show(`${ref} reopened on ${p.name}`);
    } else {
      show(`Moved on your board — ${p.name} tracks open/closed, so nothing to send`);
    }
  };

  return (
    <div className="fw fw--connect">
      <nav className="cw__list" aria-label="Trackers">
        {PROVIDERS.map((x) => (
          <button key={x.id} type="button" className="cw__provider" aria-pressed={x.id === pid} onClick={() => pick(x.id)}>
            <span className="cw__mono d-mono">{x.mono}</span>
            {x.name}
            {x.writeBack && <span className="cw__tag d-mono">write-back</span>}
          </button>
        ))}
      </nav>
      <div className="cw__panel">
        <div className="cw__head">
          <div>
            <div className="cw__name">{p.name}</div>
            <div className="cw__auth">{p.auth}</div>
          </div>
          {phase === 'idle' && (
            <button type="button" className="d-btn d-btn--primary" onClick={() => setPhase('auth')}>
              {p.auth.startsWith('Token') ? 'Connect with a token' : 'Connect with browser'}
            </button>
          )}
          {phase !== 'idle' && (
            <button type="button" className="d-btn" onClick={() => pick(p.id)}>
              Disconnect
            </button>
          )}
        </div>
        <ol className="cw__steps" aria-live="polite">
          <li data-state={phase === 'idle' ? 'todo' : 'done'}>
            {p.auth.startsWith('Token') ? 'Paste a personal access token' : 'Your browser opens the sign-in page; heap. waits on 127.0.0.1'}
          </li>
          <li data-state={phase === 'auth' ? 'active' : phase === 'idle' ? 'todo' : 'done'}>Token saved to the OS keychain — never in state.json</li>
          <li data-state={phase === 'syncing' ? 'active' : phase === 'done' ? 'done' : 'todo'}>
            {p.people ? 'People you talk to arrive as contacts and @handles' : 'Issues assigned to you arrive as cards'}
          </li>
        </ol>
        {phase === 'done' && !p.people && (
          <>
            <div className="fw__fill">
              <Board tasks={state.tasks} dispatch={dispatch} columns={['todo', 'prog', 'done']} onMoved={onMoved} label={`${p.name} issues`} />
            </div>
            <p className="cw__note">{p.writeBack ? `Drag a card to Done and ${p.name} closes the issue.` : `${p.name} issues are mirrored read-only: moves stay on your board.`}</p>
          </>
        )}
        {phase === 'done' && p.people && (
          <div className="cw__people">
            {['Oleg T. · Tech lead', 'Masha K. · QA', 'Andrey S. · Backend'].map((name) => (
              <span key={name} className="cw__person">
                {name}
              </span>
            ))}
          </div>
        )}
      </div>
      {toast && (
        <div className="d-toast" role="status">
          {toast}
        </div>
      )}
    </div>
  );
}
