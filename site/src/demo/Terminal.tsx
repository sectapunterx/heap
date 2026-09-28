import { useEffect, useRef, useState, type Dispatch } from 'react';
import type { Action } from './store';
import { TerminalIcon } from './icons';

interface TerminalProps {
  lines: string[];
  dispatch: Dispatch<Action>;
  branch: string | null;
  suggestion?: string;
  autoFocus?: boolean;
  onClose?: () => void;
  style?: React.CSSProperties;
}

export default function Terminal({ lines, dispatch, branch, suggestion = 'git switch -c APP-112-flaky-sync-test', autoFocus, onClose, style }: TerminalProps) {
  const [value, setValue] = useState('');
  const [history, setHistory] = useState<string[]>([]);
  const [hi, setHi] = useState(-1);
  const outRef = useRef<HTMLPreElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    outRef.current?.scrollTo({ top: outRef.current.scrollHeight });
  }, [lines]);

  useEffect(() => {
    if (autoFocus) inputRef.current?.focus();
  }, [autoFocus]);

  const run = (cmd: string) => {
    if (!cmd.trim()) return;
    dispatch({ type: 'term', input: cmd.trim() });
    setHistory((h) => [cmd.trim(), ...h].slice(0, 20));
    setHi(-1);
    setValue('');
  };

  return (
    <div className="d-term" style={style}>
      <div className="d-term__bar">
        <TerminalIcon size={13} />
        <span>~/src/acme-web</span>
        <span style={{ color: 'var(--accent)' }}>({branch ?? 'main'})</span>
        <span className="d-spacer" />
        {!value && suggestion && (
          <button type="button" className="d-pill" style={{ height: 22, fontSize: 11 }} onClick={() => run(suggestion)}>
            run: {suggestion}
          </button>
        )}
        {onClose && (
          <button type="button" className="d-pill" style={{ height: 22, fontSize: 11 }} onClick={onClose} aria-label="Close terminal">
            ✕
          </button>
        )}
      </div>
      <pre className="d-term__out" ref={outRef} aria-live="polite">
        {lines.map((l, i) => (
          <div key={i} className={l.startsWith('$ ') ? 'd-term__cmd' : l.startsWith('heap. ⎇') ? 'd-term__hit' : undefined}>
            {l}
          </div>
        ))}
      </pre>
      <form
        className="d-term__form"
        onSubmit={(e) => {
          e.preventDefault();
          run(value);
        }}
      >
        <span className="d-term__prompt" aria-hidden="true">
          $
        </span>
        <input
          ref={inputRef}
          className="d-term__input"
          value={value}
          onChange={(e) => setValue(e.target.value)}
          onKeyDown={(e) => {
            e.stopPropagation();
            if (e.key === 'ArrowUp' && history.length) {
              e.preventDefault();
              const n = Math.min(history.length - 1, hi + 1);
              setHi(n);
              setValue(history[n]);
            } else if (e.key === 'ArrowDown') {
              e.preventDefault();
              const n = hi - 1;
              setHi(Math.max(-1, n));
              setValue(n >= 0 ? history[n] : '');
            } else if (e.key === 'Escape' && onClose) {
              onClose();
            }
          }}
          placeholder={suggestion}
          aria-label="Command"
          spellCheck={false}
          autoComplete="off"
          autoCapitalize="off"
        />
      </form>
    </div>
  );
}
