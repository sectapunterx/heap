import { useMemo, useState, type Dispatch, type MouseEvent } from 'react';
import type { Note, Task } from './model';
import type { Action } from './store';
import { renderNote, wikiTargets } from './markdown';

interface NotesProps {
  notes: Note[];
  activeNoteId: string;
  tasks: Task[];
  dispatch: Dispatch<Action>;
  onTask?: (id: string) => void;
}

type Mode = 'edit' | 'split' | 'preview';

export default function Notes({ notes, activeNoteId, tasks, dispatch, onTask }: NotesProps) {
  const [mode, setMode] = useState<Mode>('split');
  const note = notes.find((n) => n.id === activeNoteId) ?? notes[0];
  const titles = useMemo(() => notes.map((n) => n.title), [notes]);
  const taskIds = useMemo(() => tasks.map((t) => t.id), [tasks]);
  const html = useMemo(() => renderNote(note.body, titles, taskIds), [note.body, titles, taskIds]);
  const backlinks = notes.filter((n) => n.id !== note.id && wikiTargets(n.body).some((t) => t.toLowerCase() === note.title.toLowerCase()));

  const onPreviewClick = (e: MouseEvent<HTMLDivElement>) => {
    const el = (e.target as HTMLElement).closest<HTMLElement>('[data-note],[data-task]');
    if (!el) return;
    e.preventDefault();
    if (el.dataset.note) dispatch({ type: 'openNoteByTitle', title: el.dataset.note });
    else if (el.dataset.task) onTask?.(el.dataset.task);
  };

  const toggleCheckbox = (e: MouseEvent<HTMLDivElement>) => {
    const box = e.target as HTMLInputElement;
    if (box.tagName !== 'INPUT' || box.type !== 'checkbox') return;
    const all = [...e.currentTarget.querySelectorAll('input[type="checkbox"]')];
    const idx = all.indexOf(box);
    let n = -1;
    const body = note.body.replace(/^(\s*[-*] \[)( |x|X)(\])/gm, (m, a, c, b) => (++n === idx ? `${a}${c === ' ' ? 'x' : ' '}${b}` : m));
    dispatch({ type: 'note', id: note.id, body });
  };

  const groups: Array<[string, Note[]]> = [
    ['Pinned', notes.filter((n) => n.pinned)],
    ['Daily', notes.filter((n) => n.daily)],
    ['Notes', notes.filter((n) => !n.pinned && !n.daily)],
  ];

  return (
    <div className="d-notes" data-mode={mode}>
      <nav className="d-notes__list" aria-label="Notes">
        {groups.map(([title, list]) =>
          list.length ? (
            <div key={title} style={{ display: 'contents' }}>
              <span className="d-notes__group">{title}</span>
              {list.map((n) => (
                <button key={n.id} type="button" className="d-notes__link" aria-current={n.id === note.id} onClick={() => dispatch({ type: 'openNote', id: n.id })}>
                  {n.title}
                </button>
              ))}
            </div>
          ) : null,
        )}
      </nav>
      <div className="d-notes__tabs" role="tablist" aria-label="Editor mode">
        {(['edit', 'preview'] as Mode[]).map((m) => (
          <button key={m} type="button" role="tab" aria-selected={mode === m || (m === 'preview' && mode === 'split')} className="d-pill" aria-pressed={mode === m} onClick={() => setMode(m)}>
            {m === 'edit' ? 'Edit' : 'Preview'}
          </button>
        ))}
      </div>
      <div className="d-notes__editor">
        <label htmlFor={`note-${note.id}`} className="sr-only">
          Markdown for {note.title}
        </label>
        <textarea
          id={`note-${note.id}`}
          className="d-notes__textarea"
          value={note.body}
          spellCheck={false}
          onChange={(e) => dispatch({ type: 'note', id: note.id, body: e.target.value })}
        />
      </div>
      <div className="d-notes__preview" onClick={(e) => (toggleCheckbox(e), onPreviewClick(e))}>
        <div className="md" dangerouslySetInnerHTML={{ __html: html.replace(/(<input[^>]*?) disabled=""/g, '$1') }} />
        <div className="d-notes__backlinks">
          <span className="d-notes__group" style={{ padding: 0 }}>
            Linked from
          </span>
          {backlinks.length === 0 && <span>nothing yet</span>}
          {backlinks.map((n) => (
            <a key={n.id} href="#" onClick={(e) => (e.preventDefault(), dispatch({ type: 'openNote', id: n.id }))}>
              {n.title}
            </a>
          ))}
        </div>
      </div>
    </div>
  );
}
