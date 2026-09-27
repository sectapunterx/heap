import { useEffect, useMemo, useRef, useState } from 'react';
import { search, highlight, type Searchable } from '../lib/search';
import type { Note, Task } from './model';
import { SearchIcon } from './icons';

export interface Command {
  id: string;
  title: string;
  hint?: string;
  run: () => void;
}

interface PaletteProps {
  tasks: Task[];
  notes: Note[];
  commands: Command[];
  onTask: (id: string) => void;
  onNote: (id: string) => void;
  onClose?: () => void;
  /** Inline = rendered inside a page section instead of as a modal. */
  inline?: boolean;
  initialQuery?: string;
}

interface Row extends Searchable {
  hint?: string;
  act: () => void;
}

export default function Palette({ tasks, notes, commands, onTask, onNote, onClose, inline, initialQuery = '' }: PaletteProps) {
  const [query, setQuery] = useState(initialQuery);
  const [cursor, setCursor] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!inline) inputRef.current?.focus();
  }, [inline]);

  const rows = useMemo<Row[]>(() => {
    const all: Row[] = [
      ...tasks.map((t) => ({ id: `t-${t.id}`, title: `${t.id} ${t.title}`, keywords: [t.desc, t.branch].filter(Boolean).join(' '), group: 'Tasks', hint: t.col === 'done' ? 'done' : undefined, act: () => onTask(t.id) })),
      ...notes.map((n) => ({ id: `n-${n.id}`, title: n.title, keywords: n.body, group: 'Notes', act: () => onNote(n.id) })),
      ...commands.map((c) => ({ id: `c-${c.id}`, title: c.title, group: 'Commands', hint: c.hint, act: c.run })),
    ];
    const hits = search(all, query, 14);
    return query.trim() ? hits : [...hits.filter((r) => r.group === 'Commands'), ...all.filter((r) => r.group === 'Tasks').slice(0, 4)];
  }, [tasks, notes, commands, query, onTask, onNote]);

  const choose = (row: Row | undefined) => {
    if (!row) return;
    row.act();
    onClose?.();
  };

  let last = '';
  const body = (
    <div className="d-dialog" role={inline ? undefined : 'dialog'} aria-modal={inline ? undefined : true} aria-label="Command palette" style={inline ? { width: '100%' } : undefined}>
      <div className="d-dialog__bar">
        <SearchIcon size={16} />
        <input
          ref={inputRef}
          className="d-dialog__input"
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            setCursor(0);
          }}
          onKeyDown={(e) => {
            e.stopPropagation();
            if (e.key === 'ArrowDown') {
              e.preventDefault();
              setCursor((c) => Math.min(rows.length - 1, c + 1));
            } else if (e.key === 'ArrowUp') {
              e.preventDefault();
              setCursor((c) => Math.max(0, c - 1));
            } else if (e.key === 'Enter') {
              e.preventDefault();
              choose(rows[cursor]);
            } else if (e.key === 'Escape') {
              onClose?.();
            }
          }}
          placeholder="Search tasks, notes and commands…"
          aria-label="Search tasks, notes and commands"
          role="combobox"
          aria-expanded="true"
          aria-controls="demo-palette-list"
          aria-activedescendant={rows[cursor] ? `dp-${rows[cursor].id}` : undefined}
          spellCheck={false}
          autoComplete="off"
        />
        {onClose && (
          <button type="button" className="kbd kbd--sm" onClick={onClose} style={{ cursor: 'pointer' }}>
            Esc
          </button>
        )}
      </div>
      <ul className="d-results" id="demo-palette-list" role="listbox" style={inline ? { maxHeight: 300 } : undefined}>
        {rows.length === 0 && <li style={{ padding: '18px 10px', color: 'var(--text3)', fontSize: 14 }}>Nothing matches “{query}”.</li>}
        {rows.map((r, i) => {
          const head = r.group !== last;
          last = r.group;
          return (
            <li key={r.id} role="presentation">
              {head && <div className="d-results__group">{r.group}</div>}
              <button type="button" id={`dp-${r.id}`} role="option" aria-selected={i === cursor} className="d-result" onMouseMove={() => setCursor(i)} onClick={() => choose(r)} tabIndex={-1}>
                <span>{highlight(r.title, query).map((h, j) => (h.hit ? <mark key={j}>{h.text}</mark> : <span key={j}>{h.text}</span>))}</span>
                {r.hint && <span className="d-result__hint">{r.hint}</span>}
              </button>
            </li>
          );
        })}
      </ul>
    </div>
  );

  if (inline) return body;
  return (
    <div className="d-scrim" onMouseDown={(e) => e.target === e.currentTarget && onClose?.()}>
      {body}
    </div>
  );
}
