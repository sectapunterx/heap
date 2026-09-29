import { useMemo, useState } from 'react';
import { captureNotice, fmtClock, parseCapture, type Captured, type MeetingType } from './capture';
import { dueLabel } from './model';

interface CaptureFieldProps {
  todayIndex: number;
  onSubmit: (item: Captured) => void;
  onCancel?: () => void;
  autoFocus?: boolean;
  examples?: string[];
}

export const CAPTURE_EXAMPLES = [
  'ship v1 tomorrow',
  'APP-231 urgent fix login by friday',
  'focus refactor parser 16:00',
  'call with @lena tomorrow 4pm // pricing',
  'standup every weekday 10:00',
  'ping @andrey about the release',
];

const KIND_LABEL: Record<Captured['kind'], string> = { task: 'task', focus: 'focus block', meeting: 'meeting', ping: 'ping' };
const MEETING_LABEL: Record<MeetingType, string> = { none: 'one-off', standup: 'standup', oneone: '1:1', sync: 'team sync' };

/** The notification heap. shows once a capture is saved. */
export function CaptureNotice({ item, todayIndex }: { item: Captured; todayIndex: number }) {
  const { headline, lines } = captureNotice(item, todayIndex);
  return (
    <div className="d-notice" role="status">
      <strong>{headline}</strong>
      {lines.map((l, i) => (
        <span key={i}>{l}</span>
      ))}
    </div>
  );
}

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
        {!parsed && <span style={{ color: 'var(--text4)' }}>Dates, times, priorities, ticket keys, @mentions and a // note are understood. Try one:</span>}
        {parsed && (
          <>
            <span className="d-parse__chip">
              <b>{parsed.kind === 'meeting' ? `meeting · ${MEETING_LABEL[parsed.meeting ?? 'none']}` : KIND_LABEL[parsed.kind]}</b>
              {parsed.title}
            </span>
            {parsed.kind === 'task' && (
              <span className="d-parse__chip">
                <b>deadline</b>
                {dueLabel(parsed.due)}
                {parsed.start !== undefined ? ` ${fmtClock(parsed.start)}` : ''}
              </span>
            )}
            {parsed.start !== undefined && (parsed.kind === 'focus' || parsed.kind === 'meeting') && (
              <span className="d-parse__chip">
                <b>{parsed.due === 1 ? 'tomorrow' : parsed.due ? `in ${parsed.due} days` : 'today'}</b>
                {fmtClock(parsed.start)}–{fmtClock(parsed.end!)}
              </span>
            )}
            {parsed.repeat && (
              <span className="d-parse__chip">
                <b>repeats</b>
                {parsed.repeat}
              </span>
            )}
            {parsed.prio && (
              <span className="d-parse__chip">
                <b>priority</b>
                {parsed.prio}
              </span>
            )}
            {parsed.ticket && (
              <span className="d-parse__chip">
                <b>ticket</b>
                {parsed.ticket}
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
