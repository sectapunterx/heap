import { useMemo, useState } from 'react';
import { parseCapture, type Captured } from './capture';
import { dueLabel, fmtTime } from './model';

interface CaptureFieldProps {
  todayIndex: number;
  onSubmit: (item: Captured) => void;
  onCancel?: () => void;
  autoFocus?: boolean;
  examples?: string[];
}

export const CAPTURE_EXAMPLES = ['ship v1 tomorrow', 'pay invoice // net-30, portal is slow', 'review PR @andrey @lena', 'focus refactor parser 16:00', 'standup 10:00'];

/** The quick-capture line with a live preview of what heap. understood. */
export function CaptureField({ todayIndex, onSubmit, onCancel, autoFocus, examples = CAPTURE_EXAMPLES }: CaptureFieldProps) {
  const [value, setValue] = useState('');
  const parsed = useMemo(() => parseCapture(value, todayIndex), [value, todayIndex]);

  const submit = () => {
    if (!parsed) return;
    onSubmit(parsed);
    setValue('');
  };

  return (
    <>
      <form
        className="d-dialog__bar"
        onSubmit={(e) => {
          e.preventDefault();
          submit();
        }}
      >
        <span className="d-mono" style={{ color: 'var(--accent)' }} aria-hidden="true">
          +
        </span>
        <input
          className="d-dialog__input"
          value={value}
          onChange={(e) => setValue(e.target.value)}
          onKeyDown={(e) => {
            e.stopPropagation();
            if (e.key === 'Escape') onCancel?.();
          }}
          placeholder="Capture a task… try “ship v1 tomorrow”"
          aria-label="Quick capture"
          autoFocus={autoFocus}
          spellCheck={false}
          autoComplete="off"
        />
        <button type="submit" className="d-btn d-btn--primary" disabled={!parsed}>
          Add
        </button>
      </form>
      <div className="d-parse" aria-live="polite">
        {!parsed && <span style={{ color: 'var(--text4)' }}>Dates, times, @mentions and a // description are understood. Try one:</span>}
        {parsed && (
          <>
            <span className="d-parse__chip">
              <b>{parsed.kind === 'task' ? 'task' : parsed.kind === 'focus' ? 'focus block' : 'meeting'}</b>
              {parsed.title}
            </span>
            {parsed.kind === 'task' && (
              <span className="d-parse__chip">
                <b>deadline</b>
                {dueLabel(parsed.due)}
              </span>
            )}
            {parsed.start !== undefined && parsed.kind !== 'task' && (
              <span className="d-parse__chip">
                <b>today</b>
                {fmtTime(parsed.start)}–{fmtTime(parsed.end!)}
              </span>
            )}
            {parsed.desc && (
              <span className="d-parse__chip">
                <b>description</b>
                {parsed.desc}
              </span>
            )}
            {parsed.mentions.map((m) => (
              <span key={m} className="d-parse__chip">
                <b>mention</b>@{m}
              </span>
            ))}
          </>
        )}
      </div>
      {!value && (
        <div className="d-examples">
          {examples.map((ex) => (
            <button key={ex} type="button" className="d-example" onClick={() => setValue(ex)}>
              {ex}
            </button>
          ))}
        </div>
      )}
    </>
  );
}
