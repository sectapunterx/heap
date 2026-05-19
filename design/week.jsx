// Week view — 7-day calendar with deadline chips per day + scheduled events
function WeekView({ tasks, events, selectedIso, onSelectDay, onOpen, onEventOpen, statuses }) {
  const todayIso = window.__APP_DATA__.isoToday;
  const sel = new Date(selectedIso);
  const dow = sel.getDay();
  const offset = (dow === 0 ? -6 : 1 - dow);
  const startD = new Date(sel.getFullYear(), sel.getMonth(), sel.getDate() + offset);
  const days = [];
  for (let i = 0; i < 7; i++) {
    days.push(new Date(startD.getFullYear(), startD.getMonth(), startD.getDate() + i));
  }

  const goWeek = (delta) => {
    const d = new Date(sel.getFullYear(), sel.getMonth(), sel.getDate() + delta*7);
    onSelectDay(toIso(d));
  };

  const tasksByDay = {};
  tasks.forEach(t => {
    if (!t.deadline || t.status === "done") return;
    (tasksByDay[t.deadline] = tasksByDay[t.deadline] || []).push(t);
  });
  Object.values(tasksByDay).forEach(arr => arr.sort((a,b) => a.priority.localeCompare(b.priority)));

  const eventsByDay = {};
  events.forEach(e => {
    const d = e.date || todayIso;
    (eventsByDay[d] = eventsByDay[d] || []).push(e);
  });

  const dowLabels = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"];

  const startLabel = days[0].toLocaleDateString("ru-RU", { day: "numeric", month: "short" });
  const endLabel = days[6].toLocaleDateString("ru-RU", { day: "numeric", month: "short", year: "numeric" });
  // ISO week number
  const target = new Date(days[0].valueOf());
  target.setDate(target.getDate() + 3 - ((target.getDay()+6)%7));
  const firstThursday = new Date(target.getFullYear(), 0, 4);
  const weekNum = 1 + Math.round(((target - firstThursday) / 86400000 - 3 + ((firstThursday.getDay()+6)%7))/7);

  const HOURS = [];
  for (let h = HOURS_START; h < HOURS_END; h++) HOURS.push(h);
  const HOUR_H = 38;

  // overflow-task counts per day
  const totalTasks = Object.values(tasksByDay).reduce((s,a) => s+a.length, 0);
  const totalEvents = events.filter(e => {
    const iso = e.date || todayIso;
    return iso >= toIso(days[0]) && iso <= toIso(days[6]);
  }).length;

  return (
    <div className="week-view">
      <div className="week-head">
        <button className="btn" onClick={() => goWeek(-1)} title="Previous week">←</button>
        <div className="week-title">
          <span className="mono" style={{color:"var(--text-dim)", fontSize:"11px", letterSpacing:"0.08em"}}>WEEK {weekNum}</span>
          <span style={{marginLeft:"10px"}}>{startLabel} — {endLabel}</span>
        </div>
        <span style={{color:"var(--text-dim)", fontFamily:"var(--font-mono)", fontSize:"11px"}}>
          {totalTasks} deadlines · {totalEvents} events
        </span>
        <button className="btn" onClick={() => onSelectDay(todayIso)}>Today</button>
        <button className="btn" onClick={() => goWeek(1)} title="Next week">→</button>
      </div>
      <div className="week-grid-wrap">
        <div className="week-grid" style={{"--hour-h-w": HOUR_H + "px"}}>
          <div className="week-gutter">
            <div className="week-gutter-spacer" />
            {HOURS.map(h => (
              <div key={h} className="week-hour-label mono" style={{height: HOUR_H + "px"}}>
                {String(h).padStart(2,"0")}:00
              </div>
            ))}
          </div>
          {days.map((d, i) => {
            const iso = toIso(d);
            const isToday = iso === todayIso;
            const isWeekend = i >= 5;
            const dayEvents = eventsByDay[iso] || [];
            const dayTasks = tasksByDay[iso] || [];
            return (
              <div key={iso} className={"week-day" + (isToday ? " today":"") + (isWeekend ? " weekend":"")}>
                <div className="week-day-head" onClick={() => onSelectDay(iso)}>
                  <div className="wdh-row">
                    <div className="wdh-dow">{dowLabels[i]}</div>
                    {isToday && <div className="wdh-badge mono">TODAY</div>}
                  </div>
                  <div className="wdh-num mono">{d.getDate()}</div>
                </div>
                <div className="week-day-due">
                  {dayTasks.length === 0 ? (
                    <div className="wdd-empty mono">·</div>
                  ) : (
                    dayTasks.slice(0, 4).map(t => (
                      <div
                        key={t.id}
                        className={"wdd-chip pri-" + t.priority}
                        onClick={() => onOpen(t)}
                        title={t.title}
                      >
                        <div className="wdd-chip-row">
                          <span className="mono wdd-id">{t.id}</span>
                          <span className={"pri " + t.priority} style={{padding:"0 4px", fontSize:"9px"}}>{t.priority}</span>
                        </div>
                        <div className="wdd-chip-title">{t.title}</div>
                      </div>
                    ))
                  )}
                  {dayTasks.length > 4 && (
                    <div className="wdd-more mono">+ {dayTasks.length - 4} more</div>
                  )}
                </div>
                <div className="week-day-grid" style={{height: HOURS.length * HOUR_H + "px"}}>
                  {HOURS.map(h => (
                    <div key={h} className="week-hour-slot" style={{height: HOUR_H + "px"}} />
                  ))}
                  {dayEvents.map(ev => {
                    const top = (ev.start - HOURS_START) * HOUR_H;
                    const height = Math.max(18, (ev.end - ev.start) * HOUR_H - 2);
                    return (
                      <div
                        key={ev.id}
                        className={"week-event " + (ev.type || "")}
                        style={{ top: top + "px", height: height + "px" }}
                        onClick={() => onEventOpen(ev)}
                      >
                        <div className="we-time mono">{fmtHour(ev.start)}</div>
                        <div className="we-title">{ev.title}</div>
                      </div>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { WeekView });
