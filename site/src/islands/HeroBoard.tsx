import Board from '../demo/Board';
import { useDemoStore } from '../demo/store';
import { BranchIcon, Mark, SearchIcon, BoardIcon, WeekIcon, NotesIcon } from '../demo/icons';
import type { DemoState } from '../demo/model';
import '../demo/demo.css';
import './hero-board.css';

const KEEP = new Set(['APP-108', 'APP-110', 'APP-101', 'APP-102', 'APP-103', 'APP-099']);
const init = (s: DemoState): DemoState => ({ ...s, tasks: s.tasks.filter((t) => KEEP.has(t.id)), focusedBranch: 'APP-101-login-rate-limit' });

/** The live mini board in the home-page hero: click or drag a card. */
export default function HeroBoard() {
  const { state, dispatch } = useDemoStore(undefined, init);
  const active = state.tasks.filter((t) => t.col === 'prog').length;
  const review = state.tasks.filter((t) => t.col === 'review').length;
  return (
    <div className="hb">
      <div className="hb__top">
        <div className="hb__brand">
          <Mark size={20} />
          <span>
            heap<span style={{ color: 'var(--accent)' }}>.</span>
          </span>
        </div>
        <div className="hb__crumbs">
          acme-web <span>/</span> sprint-14 <span>/</span> You
        </div>
        <span className="d-spacer" />
        <div className="hb__search" aria-hidden="true">
          <SearchIcon size={14} />
          <span>Search tasks, IDs, branches…</span>
          <kbd className="kbd kbd--sm">Ctrl K</kbd>
        </div>
      </div>
      <div className="hb__body">
        <div className="hb__rail" aria-hidden="true">
          <span className="hb__railbtn hb__railbtn--on">
            <BoardIcon />
          </span>
          <span className="hb__railbtn">
            <WeekIcon />
          </span>
          <span className="hb__railbtn">
            <NotesIcon />
          </span>
        </div>
        <div className="hb__main">
          <div className="d-toolbar">
            <strong>Board</strong>
            <span className="d-count">
              {state.tasks.length} tasks · {active} active · {review} in review
            </span>
          </div>
          <div className="d-banner d-banner--live">
            <BranchIcon />
            <span className="d-mono">APP-101-login-rate-limit</span> matched <strong className="d-mono">APP-101</strong>
            <span style={{ color: 'var(--text4)' }}>· PR #4468 open</span>
          </div>
          <Board
            tasks={state.tasks}
            dispatch={dispatch}
            focusedBranch={state.focusedBranch}
            columns={['todo', 'prog', 'review', 'done']}
            clickToAdvance
            label="Live board: click or drag a card to move it"
          />
        </div>
      </div>
    </div>
  );
}
