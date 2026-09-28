import { useEffect, useMemo, useRef, useState, type Dispatch, type PointerEvent as RPointerEvent, type KeyboardEvent } from 'react';
import { fmtTime, type CalEvent, type Task } from './model';
import type { Action } from './store';
import { SNAP, clamp, findFreeSlot, layoutDay, snap, weekDates, weekdayIndex } from './calendar';

interface WeekProps {
  events: CalEvent[];
  tasks: Task[];
  dispatch: Dispatch<Action>;
  startHour?: number;
  endHour?: number;
  hourPx?: number;
  showRail?: boolean;
  onToast?: (msg: string) => void;
}

type Drag = {
  id: string;
  mode: 'move' | 'resize' | 'create';
  x0: number;
  y0: number;
  colW: number;
  day: number;
  start: number;
  end: number;
  orig: { day: number; start: number; end: number };
  moved: boolean;
};

const DOW = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

export default function Week({ events, tasks, dispatch, startHour = 7, endHour = 21, hourPx = 48, showRail = true, onToast }: WeekProps) {
  const [now, setNow] = useState(() => new Date());
  const [drag, setDrag] = useState<Drag | null>(null);
  const [editing, setEditing] = useState<string | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const dragRef = useRef<Drag | null>(null);
  dragRef.current = drag;

  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 60_000);
    return () => clearInterval(t);
  }, []);

  const today = weekdayIndex(now);
  const dates = useMemo(() => weekDates(now), [now]);
  const minMin = startHour * 60;
  const maxMin = endHour * 60;
  const px = (min: number) => ((min - minMin) / 60) * hourPx;
  const nowMin = now.getHours() * 60 + now.getMinutes();

  // Open on the part of the day you're in.
  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    // Outside working hours, open on the morning instead of an empty evening.
    const target = nowMin >= 9 * 60 && nowMin <= 18 * 60 ? nowMin - 90 : 8 * 60 + 30;
    el.scrollTop = px(target);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const shown = useMemo(() => {
    const list = events.map((e) => (drag && drag.mode !== 'create' && e.id === drag.id ? { ...e, day: drag.day, start: drag.start, end: drag.end } : e));
    if (drag?.mode === 'create') list.push({ id: '__draft', title: 'New event', day: drag.day, start: drag.start, end: drag.end, kind: 'event' });
    return list;
  }, [events, drag]);

  const perDay = useMemo(() => Array.from({ length: 7 }, (_, d) => layoutDay(shown.filter((e) => e.day === d && e.end > minMin && e.start < maxMin))), [shown, minMin, maxMin]);

  const needSlot = tasks.filter(
    (t) => (t.col === 'todo' || t.col === 'prog') && t.due !== null && t.due <= 7 && !events.some((e) => e.taskId === t.id),
  );

  const colWidth = () => {
    const col = scrollRef.current?.querySelector<HTMLElement>('.d-week__day');
    return col?.getBoundingClientRect().width ?? 100;
  };

  const minuteAt = (e: RPointerEvent | React.DragEvent, col: HTMLElement) => {
    const r = col.getBoundingClientRect();
    return clamp(Math.floor((minMin + ((e.clientY - r.top) / hourPx) * 60) / SNAP) * SNAP, minMin, maxMin - SNAP);
  };

  const beginEvent = (e: RPointerEvent<HTMLElement>, ev: CalEvent, mode: 'move' | 'resize') => {
    if (e.button !== 0 || editing === ev.id) return;
    e.stopPropagation();
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    setDrag({ id: ev.id, mode, x0: e.clientX, y0: e.clientY, colW: colWidth(), day: ev.day, start: ev.start, end: ev.end, orig: { day: ev.day, start: ev.start, end: ev.end }, moved: false });
  };

  const beginCreate = (e: RPointerEvent<HTMLDivElement>, day: number) => {
    if (e.button !== 0 || e.target !== e.currentTarget || e.pointerType === 'touch') return;
    const m = minuteAt(e, e.currentTarget);
    e.currentTarget.setPointerCapture(e.pointerId);
    setDrag({ id: '__draft', mode: 'create', x0: e.clientX, y0: e.clientY, colW: colWidth(), day, start: m, end: m + 30, orig: { day, start: m, end: m + 30 }, moved: false });
  };

  const onMove = (e: RPointerEvent) => {
    const d = dragRef.current;
    if (!d) return;
    const dm = snap(((e.clientY - d.y0) / hourPx) * 60);
    const dd = Math.round((e.clientX - d.x0) / d.colW);
    const moved = d.moved || Math.abs(e.clientY - d.y0) > 3 || Math.abs(e.clientX - d.x0) > 3;
    if (d.mode === 'move') {
      const dur = d.orig.end - d.orig.start;
      const start = clamp(d.orig.start + dm, minMin, maxMin - dur);
      setDrag({ ...d, moved, day: clamp(d.orig.day + dd, 0, 6), start, end: start + dur });
    } else if (d.mode === 'resize') {
      setDrag({ ...d, moved, end: clamp(d.orig.end + dm, d.orig.start + SNAP, maxMin) });
    } else {
      setDrag({ ...d, moved, end: clamp(d.orig.start + Math.max(SNAP * 2, dm + 30), d.orig.start + SNAP, maxMin) });
    }
  };

  const onUp = () => {
    const d = dragRef.current;
    setDrag(null);
    if (!d) return;
    if (d.mode === 'create') {
      dispatch({ type: 'addEvent', event: { title: 'New event', day: d.day, start: d.start, end: d.end, kind: 'event' } });
      requestAnimationFrame(() => setEditing('__last'));
      return;
    }
    if (!d.moved) return;
    dispatch({ type: 'event', id: d.id, patch: { day: d.day, start: d.start, end: d.end } });
  };

  // Rename the event just created.
  const lastId = events[events.length - 1]?.id;
  const editingId = editing === '__last' ? lastId : editing;

  const onEventKey = (e: KeyboardEvent<HTMLElement>, ev: CalEvent) => {
    if (e.key === 'Enter' || e.key === 'F2') {
      e.preventDefault();
      setEditing(ev.id);
      return;
    }
    const dur = ev.end - ev.start;
    let patch: Partial<CalEvent> | null = null;
    if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
      const d = e.key === 'ArrowUp' ? -SNAP : SNAP;
      patch = e.shiftKey ? { end: clamp(ev.end + d, ev.start + SNAP, maxMin) } : { start: clamp(ev.start + d, minMin, maxMin - dur), end: clamp(ev.start + d, minMin, maxMin - dur) + dur };
    } else if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
      patch = { day: clamp(ev.day + (e.key === 'ArrowLeft' ? -1 : 1), 0, 6) };
    }
    if (patch) {
      e.preventDefault();
      dispatch({ type: 'event', id: ev.id, patch });
    }
  };

  const book = (t: Task) => {
    for (let d = today; d < 7; d++) {
      const slot = findFreeSlot(events, d, d === today ? nowMin : 9 * 60, 90);
      if (slot !== null) {
        dispatch({ type: 'addEvent', event: { title: `Focus: ${t.id}`, day: d, start: slot, end: slot + 90, kind: 'focus', taskId: t.id } });
        onToast?.(`Booked 90 min for ${t.id} — ${DOW[d].toLowerCase()} ${fmtTime(slot)}`);
        return;
      }
    }
    onToast?.('No free 90-minute slot left this week.');
  };

  const onDrop = (e: React.DragEvent<HTMLDivElement>, day: number) => {
    const id = e.dataTransfer.getData('text/heap-task');
    const t = tasks.find((x) => x.id === id);
    if (!t) return;
    e.preventDefault();
    const start = clamp(minuteAt(e, e.currentTarget), minMin, maxMin - 90);
    dispatch({ type: 'addEvent', event: { title: `Focus: ${t.id}`, day, start, end: start + 90, kind: 'focus', taskId: t.id } });
    onToast?.(`Focus block for ${t.id} booked`);
  };

  const hours = Array.from({ length: endHour - startHour }, (_, i) => startHour + i);
  const height = (endHour - startHour) * hourPx;

  return (
    <div className="d-week">
      <div className="d-week__scroll" ref={scrollRef}>
        <div className="d-week__grid" onPointerMove={onMove} onPointerUp={onUp} onPointerCancel={() => setDrag(null)}>
          <div className="d-week__corner" />
          {dates.map((d, i) => (
            <div key={i} className={`d-week__dayhead${i === today ? ' d-week__dayhead--today' : ''}`}>
              <span className="d-week__dow">{DOW[i]}</span>
              <span className="d-week__date">{d.getDate()}</span>
            </div>
          ))}
          <div className="d-week__hours" style={{ height }}>
            {hours.slice(1).map((h) => (
              <span key={h} className="d-week__hour" style={{ top: px(h * 60) }}>
                {String(h).padStart(2, '0')}:00
              </span>
            ))}
          </div>
          {perDay.map((placed, day) => (
            <div
              key={day}
              className={`d-week__day${day === today ? ' d-week__day--today' : ''}`}
              style={{ height, backgroundSize: `100% ${hourPx}px` }}
              onPointerDown={(e) => beginCreate(e, day)}
              onDragOver={(e) => e.dataTransfer.types.includes('text/heap-task') && e.preventDefault()}
              onDrop={(e) => onDrop(e, day)}
              aria-label={`${DOW[day]} ${dates[day].getDate()}`}
            >
              {placed.map(({ event: ev, lane, lanes }) => {
                const top = px(Math.max(ev.start, minMin));
                const h = Math.max(18, px(Math.min(ev.end, maxMin)) - top - 2);
                const isDraft = ev.id === '__draft';
                const cls = `d-event d-event--${isDraft ? 'draft' : ev.kind}${drag?.id === ev.id ? ' d-event--dragging' : ''}`;
                const style = { top: top + 1, height: h, left: `calc(${(lane / lanes) * 100}% + 3px)`, width: `calc(${100 / lanes}% - 6px)` };
                return (
                  <div
                    key={ev.id}
                    className={cls}
                    style={style}
                    tabIndex={isDraft ? -1 : 0}
                    role={isDraft ? undefined : 'button'}
                    aria-label={`${ev.title}, ${DOW[ev.day]} ${fmtTime(ev.start)} to ${fmtTime(ev.end)}. Arrows move it, Shift+arrows resize, Enter renames.`}
                    onPointerDown={(e) => !isDraft && beginEvent(e, ev, 'move')}
                    onKeyDown={(e) => onEventKey(e, ev)}
                    onDoubleClick={() => setEditing(ev.id)}
                  >
                    {editingId === ev.id ? (
                      <input
                        className="d-event__title"
                        style={{ width: '100%', border: 0, outline: 0, background: 'transparent', color: 'inherit', padding: 0 }}
                        defaultValue={ev.title}
                        aria-label="Event title"
                        autoFocus
                        onFocus={(e) => e.currentTarget.select()}
                        onPointerDown={(e) => e.stopPropagation()}
                        onKeyDown={(e) => {
                          e.stopPropagation();
                          if (e.key === 'Enter') e.currentTarget.blur();
                          if (e.key === 'Escape') setEditing(null);
                        }}
                        onBlur={(e) => {
                          const title = e.currentTarget.value.trim();
                          if (title) dispatch({ type: 'event', id: ev.id, patch: { title } });
                          setEditing(null);
                        }}
                      />
                    ) : (
                      <span className="d-event__title">{ev.title}</span>
                    )}
                    {h > 30 && (
                      <span className="d-event__time">
                        {fmtTime(ev.start)}–{fmtTime(ev.end)}
                      </span>
                    )}
                    {!isDraft && <span className="d-event__resize" onPointerDown={(e) => beginEvent(e, ev, 'resize')} />}
                  </div>
                );
              })}
              {day === today && nowMin > minMin && nowMin < maxMin && <div className="d-now" style={{ top: px(nowMin) }} />}
            </div>
          ))}
        </div>
      </div>
      {showRail && (
        <aside className="d-rail" aria-label="Tasks that still need a slot">
          <span className="d-notes__group" style={{ padding: '2px 2px 4px' }}>
            Needs a slot
          </span>
          {needSlot.length === 0 && <span style={{ fontSize: 13, color: 'var(--text4)' }}>Everything due this week has time booked.</span>}
          {needSlot.map((t) => (
            <div key={t.id} className="d-rail__item" draggable onDragStart={(e) => e.dataTransfer.setData('text/heap-task', t.id)}>
              <span className="d-card__row">
                <span className="d-card__id">{t.id}</span>
                <span className={`d-chip d-chip--${t.prio}`}>{t.prio}</span>
              </span>
              <span className="d-card__title">{t.title}</span>
              <button type="button" className="d-rail__book" onClick={() => book(t)}>
                Book 90 min
              </button>
            </div>
          ))}
          <span style={{ marginTop: 'auto', fontSize: 12, lineHeight: 1.5, color: 'var(--text4)' }}>Drag a task onto the grid, or book the next free slot.</span>
        </aside>
      )}
    </div>
  );
}
