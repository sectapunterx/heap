// Calendar (mini-week navigator + day grid)
const { useEffect: calUseEffect, useState: calUseState, useRef: calUseRef } = React;

const HOURS_START = 8;
const HOURS_END = 22; // exclusive end label

function fmtHour(h) {
  const hh = Math.floor(h);
  const mm = Math.round((h - hh) * 60);
  return `${String(hh).padStart(2,"0")}:${String(mm).padStart(2,"0")}`;
}

function MiniWeek({ selectedIso, onSelect, eventsByDay }) {
  const sel = new Date(selectedIso);
  const dow = sel.getDay(); // 0=Sun
  const offset = (dow === 0 ? -6 : 1 - dow); // start Monday
  const start = new Date(sel.getFullYear(), sel.getMonth(), sel.getDate() + offset);
  const days = [];
  for (let i = 0; i < 7; i++) {
    const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
    days.push(d);
  }
  const dowLabels = ["MO","TU","WE","TH","FR","SA","SU"];
  const monthName = sel.toLocaleString("ru-RU", { month: "long" });

  const goWeek = (delta) => {
    const d = new Date(sel.getFullYear(), sel.getMonth(), sel.getDate() + delta*7);
    onSelect(toIso(d));
  };

  return (
    <div className="miniweek">
      <div className="month">
        <div className="label">
          <span style={{textTransform:"capitalize"}}>{monthName}</span>
          <span className="y mono">{sel.getFullYear()}</span>
        </div>
        <div className="nav">
          <button onClick={() => goWeek(-1)} title="Previous week">‹</button>
          <button onClick={() => onSelect(window.__APP_DATA__.isoToday)} title="Today" style={{fontSize:"10px", padding:"0 6px", color:"var(--accent-strong)"}}>•</button>
          <button onClick={() => goWeek(1)} title="Next week">›</button>
        </div>
      </div>
      <div className="days">
        {days.map((d, i) => {
          const iso = toIso(d);
          const isToday = iso === window.__APP_DATA__.isoToday;
          const isSel = iso === selectedIso;
          const cnt = (eventsByDay[iso] || []).length;
          return (
            <div
              key={iso}
              className={"day" + (isToday ? " today":"") + (isSel ? " selected":"")}
              onClick={() => onSelect(iso)}
            >
              <div className="dow">{dowLabels[i]}</div>
              <div className="num">{d.getDate()}</div>
              <div className={"pip" + (cnt === 0 ? " empty":"")} />
            </div>
          );
        })}
      </div>
    </div>
  );
}

function toIso(d) {
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`;
}

function DayCalendar({ selectedIso, events, onEventChange, onEventCreate, onEventOpen, onTaskDrop, tasks }) {
  const gridRef = calUseRef(null);
  const [dragTargetHour, setDragTargetHour] = calUseState(null);
  const [ghostEvent, setGhostEvent] = calUseState(null); // { start, end }
  const [resizing, setResizing] = calUseState(null); // { id, startY, origEnd }
  const [now, setNow] = calUseState(new Date());

  calUseEffect(() => {
    const t = setInterval(() => setNow(new Date()), 60000);
    return () => clearInterval(t);
  }, []);

  // pixel-per-hour from CSS var
  const HOUR_H = parseInt(getComputedStyle(document.documentElement).getPropertyValue('--hour-h')) || 56;

  // Build hour rows
  const hours = [];
  for (let h = HOURS_START; h < HOURS_END; h++) hours.push(h);

  const dayEvents = events.filter(e => (e.date || window.__APP_DATA__.isoToday) === selectedIso);

  // ---- Drag-to-create new event (mousedown on slot) ----
  const slotMouseDown = (e, hour) => {
    if (e.button !== 0) return;
    const rect = gridRef.current.getBoundingClientRect();
    const y = e.clientY - rect.top;
    const startH = HOURS_START + (y / HOUR_H);
    const snappedStart = Math.round(startH * 4) / 4; // 15-min snap
    setGhostEvent({ start: snappedStart, end: snappedStart + 0.5 });
    const move = (ev) => {
      const y2 = ev.clientY - rect.top;
      const endH = HOURS_START + (y2 / HOUR_H);
      const snappedEnd = Math.max(snappedStart + 0.25, Math.round(endH * 4) / 4);
      setGhostEvent({ start: snappedStart, end: snappedEnd });
    };
    const up = (ev) => {
      window.removeEventListener("mousemove", move);
      window.removeEventListener("mouseup", up);
      const y2 = ev.clientY - rect.top;
      const endH = HOURS_START + (y2 / HOUR_H);
      const snappedEnd = Math.max(snappedStart + 0.5, Math.round(endH * 4) / 4);
      setGhostEvent(null);
      if (snappedEnd - snappedStart >= 0.25) {
        onEventCreate({ start: snappedStart, end: snappedEnd, date: selectedIso });
      }
    };
    window.addEventListener("mousemove", move);
    window.addEventListener("mouseup", up);
  };

  // ---- Drop a task onto an hour slot ----
  const slotDragOver = (e, hour) => {
    if (e.dataTransfer.types.includes("application/x-task-id") ||
        e.dataTransfer.types.includes("text/plain")) {
      e.preventDefault();
      e.dataTransfer.dropEffect = "copy";
      const rect = gridRef.current.getBoundingClientRect();
      const y = e.clientY - rect.top;
      const h = HOURS_START + (y / HOUR_H);
      setDragTargetHour(Math.round(h*4)/4);
    }
  };

  const slotDrop = (e) => {
    e.preventDefault();
    const taskId = e.dataTransfer.getData("application/x-task-id") || e.dataTransfer.getData("text/plain");
    if (!taskId) { setDragTargetHour(null); return; }
    const rect = gridRef.current.getBoundingClientRect();
    const y = e.clientY - rect.top;
    const startH = HOURS_START + (y / HOUR_H);
    const snapped = Math.round(startH * 4) / 4;
    onTaskDrop(taskId, snapped, selectedIso);
    setDragTargetHour(null);
  };

  // ---- Resize event ----
  const startResize = (e, ev) => {
    e.stopPropagation();
    e.preventDefault();
    const origEnd = ev.end;
    const startY = e.clientY;
    const move = (mv) => {
      const dy = mv.clientY - startY;
      const newEnd = Math.max(ev.start + 0.25, Math.round((origEnd + dy/HOUR_H) * 4) / 4);
      onEventChange(ev.id, { end: newEnd });
    };
    const up = () => {
      window.removeEventListener("mousemove", move);
      window.removeEventListener("mouseup", up);
    };
    window.addEventListener("mousemove", move);
    window.addEventListener("mouseup", up);
  };

  // ---- Move event ----
  const startMove = (e, ev) => {
    if (e.target.classList.contains("ev-resize")) return;
    e.preventDefault();
    const origStart = ev.start;
    const origEnd = ev.end;
    const startY = e.clientY;
    let moved = false;
    const move = (mv) => {
      const dy = mv.clientY - startY;
      if (Math.abs(dy) > 3) moved = true;
      const delta = Math.round((dy/HOUR_H) * 4) / 4;
      let newStart = Math.max(HOURS_START, origStart + delta);
      let newEnd = newStart + (origEnd - origStart);
      if (newEnd > HOURS_END) { newEnd = HOURS_END; newStart = newEnd - (origEnd - origStart); }
      onEventChange(ev.id, { start: newStart, end: newEnd });
    };
    const up = () => {
      window.removeEventListener("mousemove", move);
      window.removeEventListener("mouseup", up);
      if (!moved) onEventOpen(ev);
    };
    window.addEventListener("mousemove", move);
    window.addEventListener("mouseup", up);
  };

  // Now indicator
  const nowDate = new Date(now);
  const nowIso = toIso(nowDate);
  const showNow = nowIso === selectedIso;
  const nowH = nowDate.getHours() + nowDate.getMinutes()/60;
  const nowTop = (nowH - HOURS_START) * HOUR_H;
  const nowVisible = showNow && nowH >= HOURS_START && nowH <= HOURS_END;

  const headDate = new Date(selectedIso);
  const headLabel = headDate.toLocaleDateString("ru-RU", { weekday: "long", day: "numeric", month: "long" });

  return (
    <div className="calendar">
      <div className="cal-head">
        <div>
          <div className="title" style={{textTransform:"capitalize"}}>{headLabel}</div>
          <div className="sub">{selectedIso} · {dayEvents.length} event{dayEvents.length===1?"":"s"}</div>
        </div>
        <div className="sub">Drag empty slot → создать · Drop задачу → запланировать</div>
      </div>
      <div className="grid-wrap" ref={gridRef}>
        {hours.map((h) => (
          <div
            key={h}
            className={"hour-row" + (dragTargetHour !== null && Math.floor(dragTargetHour) === h ? " drag-target" : "")}
            onDragOver={(e) => slotDragOver(e, h)}
            onDragLeave={() => setDragTargetHour(null)}
            onDrop={slotDrop}
          >
            <div className="label mono">{String(h).padStart(2,"0")}:00</div>
            <div className="slot" onMouseDown={(e) => slotMouseDown(e, h)} />
          </div>
        ))}
        <div className="events-layer">
          {dayEvents.map((ev) => {
            const top = (ev.start - HOURS_START) * HOUR_H;
            const height = (ev.end - ev.start) * HOUR_H - 2;
            const t = tasks.find(x => x.id === ev.taskId);
            return (
              <div
                key={ev.id}
                className={"event " + (ev.type || "")}
                style={{ top: top + "px", height: height + "px" }}
                onMouseDown={(e) => startMove(e, ev)}
              >
                <div className="ev-title">{ev.title}{t ? <span style={{color:"var(--text-dim)", fontWeight:"normal", marginLeft:"6px", fontFamily:"var(--font-mono)", fontSize:"10px"}}>{t.id}</span> : null}</div>
                <div className="ev-time mono">{fmtHour(ev.start)} – {fmtHour(ev.end)}</div>
                {ev.attendees && height > 50 && <div className="ev-meta">· {ev.attendees}</div>}
                <div className="ev-resize" onMouseDown={(e) => startResize(e, ev)} />
              </div>
            );
          })}
          {ghostEvent && (
            <div
              className="event ghost"
              style={{
                top: ((ghostEvent.start - HOURS_START) * HOUR_H) + "px",
                height: ((ghostEvent.end - ghostEvent.start) * HOUR_H - 2) + "px",
              }}
            >
              <div className="ev-title">Новое событие…</div>
              <div className="ev-time mono">{fmtHour(ghostEvent.start)} – {fmtHour(ghostEvent.end)}</div>
            </div>
          )}
          {nowVisible && (
            <div className="now-line" style={{ top: nowTop + "px", left: 0, right: 0 }} />
          )}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { MiniWeek, DayCalendar, toIso, fmtHour, HOURS_START, HOURS_END });
