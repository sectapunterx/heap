import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { search, highlight } from '../lib/search';
import type { PaletteItem } from '../lib/palette-items';
import './palette.css';

interface Props {
  items: PaletteItem[];
}

const GROUP_ORDER: PaletteItem['group'][] = ['Pages', 'Features', 'Docs', 'Sections'];

function isTyping(el: EventTarget | null): boolean {
  const node = el as HTMLElement | null;
  return !!node && (node.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(node.tagName));
}

/** Site-wide Ctrl+K: jump to any page, feature, doc or doc section. */
export default function SitePalette({ items }: Props) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [cursor, setCursor] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLUListElement>(null);
  const lastFocus = useRef<HTMLElement | null>(null);

  const results = useMemo(() => {
    const pool = query.trim() ? items : items.filter((i) => i.group !== 'Sections');
    const hits = search(pool, query, 30);
    return [...hits].sort((a, b) => (query.trim() ? 0 : GROUP_ORDER.indexOf(a.group) - GROUP_ORDER.indexOf(b.group)));
  }, [items, query]);

  const show = useCallback(() => {
    lastFocus.current = document.activeElement as HTMLElement | null;
    setQuery('');
    setCursor(0);
    setOpen(true);
  }, []);

  const hide = useCallback(() => {
    setOpen(false);
    lastFocus.current?.focus?.();
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      // The browser demo owns Ctrl+K while it is on the page.
      if (document.body.dataset.demo === 'true') return;
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        open ? hide() : show();
      } else if (e.key === '/' && !open && !isTyping(e.target)) {
        e.preventDefault();
        show();
      }
    };
    const onEvent = () => show();
    window.addEventListener('keydown', onKey);
    window.addEventListener('heap:palette', onEvent);
    return () => {
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('heap:palette', onEvent);
    };
  }, [open, show, hide]);

  useEffect(() => {
    if (open) inputRef.current?.focus();
    document.documentElement.style.overflow = open ? 'hidden' : '';
  }, [open]);

  useEffect(() => {
    listRef.current?.querySelector<HTMLElement>('[aria-selected="true"]')?.scrollIntoView({ block: 'nearest' });
  }, [cursor]);

  if (!open) return null;

  const go = (item: PaletteItem | undefined) => {
    if (!item) return;
    setOpen(false);
    window.location.href = item.href;
  };

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setCursor((c) => Math.min(results.length - 1, c + 1));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setCursor((c) => Math.max(0, c - 1));
    } else if (e.key === 'Enter') {
      e.preventDefault();
      go(results[cursor]);
    } else if (e.key === 'Escape') {
      e.preventDefault();
      hide();
    } else if (e.key === 'Tab') {
      e.preventDefault();
    }
  };

  let lastGroup = '';
  return (
    <div className="pal-scrim" onMouseDown={(e) => e.target === e.currentTarget && hide()}>
      <div className="pal" role="dialog" aria-modal="true" aria-label="Search the site" onKeyDown={onKeyDown}>
        <div className="pal__bar">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
            <circle cx="11" cy="11" r="7" />
            <path d="M20 20l-3.5-3.5" />
          </svg>
          <input
            ref={inputRef}
            className="pal__input"
            value={query}
            onChange={(e) => {
              setQuery(e.target.value);
              setCursor(0);
            }}
            placeholder="Search pages, features and docs…"
            role="combobox"
            aria-expanded="true"
            aria-controls="site-pal-list"
            aria-activedescendant={results[cursor] ? `pal-${results[cursor].id}` : undefined}
            aria-label="Search the site"
            spellCheck={false}
            autoComplete="off"
          />
          <button type="button" className="kbd kbd--sm pal__esc" onClick={hide}>
            Esc
          </button>
        </div>
        <ul className="pal__list" id="site-pal-list" role="listbox" ref={listRef}>
          {results.length === 0 && <li className="pal__empty">Nothing matches “{query}”.</li>}
          {results.map((item, i) => {
            const header = !query.trim() && item.group !== lastGroup;
            lastGroup = item.group;
            return (
              <li key={item.id} role="presentation">
                {header && <div className="pal__group">{item.group}</div>}
                <a
                  id={`pal-${item.id}`}
                  href={item.href}
                  role="option"
                  aria-selected={i === cursor}
                  className="pal__item"
                  onMouseMove={() => setCursor(i)}
                  tabIndex={-1}
                >
                  <span className="pal__title">
                    {highlight(item.title, query).map((r, j) =>
                      r.hit ? <mark key={j}>{r.text}</mark> : <span key={j}>{r.text}</span>,
                    )}
                  </span>
                  {query.trim() && <span className="pal__tag">{item.group}</span>}
                </a>
              </li>
            );
          })}
        </ul>
        <div className="pal__foot">
          <span>
            <kbd className="kbd kbd--sm">↑</kbd> <kbd className="kbd kbd--sm">↓</kbd> move
          </span>
          <span>
            <kbd className="kbd kbd--sm">↵</kbd> open
          </span>
          <span>
            <kbd className="kbd kbd--sm">/</kbd> or <kbd className="kbd kbd--sm">Ctrl K</kbd> anywhere
          </span>
        </div>
      </div>
    </div>
  );
}
