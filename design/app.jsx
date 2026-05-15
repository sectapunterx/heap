// Main app
const { useState: aUseState, useEffect: aUseEffect, useMemo: aUseMemo, useRef: aUseRef } = React;

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "theme": "dark",
  "density": "comfy"
}/*EDITMODE-END*/;

function priorityToBars(p) {
  return { P0: "▰▰▰▰", P1: "▰▰▰▱", P2: "▰▰▱▱", P3: "▰▱▱▱" }[p] || "";
}

function TaskModal({ task, onClose, onSave, onDelete, onSchedule, statuses }) {
  const [draft, setDraft] = aUseState(task);
  aUseEffect(() => setDraft(task), [task]);
  if (!task) return null;
  const update = (k, v) => setDraft({...draft, [k]: v});
  const isNew = task._isNew;

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h2>
          {isNew ? "Новая задача" : "Редактировать задачу"}
          {!isNew && <span className="id">{draft.id}</span>}
        </h2>
        <label>
          ID тикета
          <input
            className="mono"
            value={draft.id || ""}
            onChange={(e) => update("id", e.target.value.toUpperCase())}
            placeholder="LTE-XXXX"
          />
        </label>
        <label>
          Заголовок
          <input
            value={draft.title || ""}
            onChange={(e) => update("title", e.target.value)}
            placeholder="Короткое summary"
            autoFocus
          />
        </label>
        <label>
          Описание
          <textarea
            value={draft.desc || ""}
            onChange={(e) => update("desc", e.target.value)}
            rows={3}
            placeholder="Контекст, ссылки, спецификация…"
          />
        </label>
        <div className="row2">
          <label>
            Статус
            <select value={draft.status} onChange={(e) => update("status", e.target.value)}>
              {statuses.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </label>
          <label>
            Приоритет
            <select value={draft.priority} onChange={(e) => update("priority", e.target.value)}>
              {["P0","P1","P2","P3"].map(p => <option key={p} value={p}>{p}</option>)}
            </select>
          </label>
        </div>
        <div className="row2">
          <label>
            Дедлайн
            <input type="date" value={draft.deadline || ""} onChange={(e) => update("deadline", e.target.value)} />
          </label>
          <label>
            Branch
            <input className="mono" value={draft.branch || ""} onChange={(e) => update("branch", e.target.value)} placeholder="fix/..." />
          </label>
        </div>
        <div className="actions">
          {!isNew && <button className="btn danger" onClick={() => onDelete(draft.id)}>Удалить</button>}
          <button className="btn" onClick={onClose}>Отмена</button>
          <button className="btn primary" onClick={() => onSave(draft)}>{isNew ? "Создать" : "Сохранить"}</button>
        </div>
      </div>
    </div>
  );
}

function EventModal({ event, tasks, onClose, onSave, onDelete }) {
  const [draft, setDraft] = aUseState(event);
  aUseEffect(() => setDraft(event), [event]);
  if (!event) return null;
  const update = (k, v) => setDraft({...draft, [k]: v});

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h2>Событие в календаре</h2>
        <label>
          Название
          <input value={draft.title || ""} onChange={(e) => update("title", e.target.value)} autoFocus />
        </label>
        <div className="row2">
          <label>
            Тип
            <select value={draft.type || "sync"} onChange={(e) => update("type", e.target.value)}>
              <option value="standup">Daily standup</option>
              <option value="oneone">1:1</option>
              <option value="sync">Team sync</option>
              <option value="focus">Focus time</option>
            </select>
          </label>
          <label>
            Участники
            <input value={draft.attendees || ""} onChange={(e) => update("attendees", e.target.value)} />
          </label>
        </div>
        <div className="row2">
          <label>
            Начало
            <input
              className="mono"
              value={fmtHour(draft.start)}
              onChange={(e) => {
                const [h, m] = e.target.value.split(":").map(Number);
                if (!isNaN(h)) update("start", h + (m||0)/60);
              }}
            />
          </label>
          <label>
            Конец
            <input
              className="mono"
              value={fmtHour(draft.end)}
              onChange={(e) => {
                const [h, m] = e.target.value.split(":").map(Number);
                if (!isNaN(h)) update("end", h + (m||0)/60);
              }}
            />
          </label>
        </div>
        <label>
          Привязать задачу
          <select value={draft.taskId || ""} onChange={(e) => update("taskId", e.target.value || null)}>
            <option value="">— нет —</option>
            {tasks.map(t => <option key={t.id} value={t.id}>{t.id} · {t.title.slice(0,40)}</option>)}
          </select>
        </label>
        <div className="actions">
          <button className="btn danger" onClick={() => onDelete(draft.id)}>Удалить</button>
          <button className="btn" onClick={onClose}>Отмена</button>
          <button className="btn primary" onClick={() => onSave(draft)}>Сохранить</button>
        </div>
      </div>
    </div>
  );
}

function App() {
  const D = window.__APP_DATA__;
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const [tasks, setTasks] = aUseState(D.SAMPLE_TASKS);
  const [events, setEvents] = aUseState(D.SAMPLE_EVENTS.map(e => ({...e, date: D.isoToday})));
  const [people, setPeople] = aUseState(D.SAMPLE_PEOPLE);
  const [selectedDate, setSelectedDate] = aUseState(D.isoToday);
  const [editingTask, setEditingTask] = aUseState(null);
  const [editingEvent, setEditingEvent] = aUseState(null);
  const [search, setSearch] = aUseState("");
  const [priFilter, setPriFilter] = aUseState(new Set());
  const [toast, setToast] = aUseState(null);
  const [view, setView] = aUseState("board"); // 'board' | 'timeline' | 'week'
  const [showDoneTimeline, setShowDoneTimeline] = aUseState(false);

  // Apply theme + density to <html>
  aUseEffect(() => {
    document.documentElement.setAttribute("data-theme", t.theme);
    document.documentElement.setAttribute("data-density", t.density);
  }, [t.theme, t.density]);

  const showToast = (msg) => {
    setToast(msg);
    clearTimeout(showToast._t);
    showToast._t = setTimeout(() => setToast(null), 2400);
  };

  // ---- Task ops ----
  const moveTask = (taskId, newStatus) => {
    setTasks(prev => prev.map(t => t.id === taskId ? {...t, status: newStatus} : t));
    const t = tasks.find(x => x.id === taskId);
    const s = D.STATUSES.find(s => s.id === newStatus);
    if (t && s && t.status !== newStatus) showToast(`${t.id} → ${s.name}`);
  };

  const openTask = (task) => setEditingTask(task);

  const createTaskInStatus = (statusId) => {
    const nextNum = 2700 + tasks.length;
    setEditingTask({
      _isNew: true,
      id: `LTE-${nextNum}`,
      title: "",
      desc: "",
      priority: "P2",
      status: statusId,
      deadline: "",
      branch: "",
    });
  };

  const saveTask = (draft) => {
    if (draft._isNew) {
      const {_isNew, ...rest} = draft;
      if (!rest.title.trim()) { setEditingTask(null); return; }
      setTasks(prev => [...prev, rest]);
      showToast(`Создано: ${rest.id}`);
    } else {
      setTasks(prev => prev.map(x => x.id === draft.id ? draft : x));
    }
    setEditingTask(null);
  };

  const deleteTask = (id) => {
    setTasks(prev => prev.filter(x => x.id !== id));
    setEvents(prev => prev.map(e => e.taskId === id ? {...e, taskId: null} : e));
    setEditingTask(null);
    showToast(`Удалена: ${id}`);
  };

  // ---- Event ops ----
  const changeEvent = (id, patch) => {
    setEvents(prev => prev.map(e => e.id === id ? {...e, ...patch} : e));
  };
  const createEvent = ({start, end, date}) => {
    const id = "ev-" + Date.now();
    const nev = {
      id, start, end, date,
      title: "Новое событие",
      type: "sync",
      attendees: "",
    };
    setEvents(prev => [...prev, nev]);
    setEditingEvent(nev);
  };
  const saveEvent = (draft) => {
    setEvents(prev => prev.map(e => e.id === draft.id ? draft : e));
    setEditingEvent(null);
  };
  const deleteEvent = (id) => {
    setEvents(prev => prev.filter(e => e.id !== id));
    setEditingEvent(null);
  };

  // Drop a task onto calendar → create focus block tied to task
  const handleTaskDrop = (taskId, startHour, date) => {
    const t = tasks.find(x => x.id === taskId);
    if (!t) return;
    const id = "ev-" + Date.now();
    const ev = {
      id, start: startHour, end: startHour + 1,
      date,
      title: `Focus · ${t.title.slice(0, 36)}`,
      type: "focus",
      attendees: "🔒 deep work",
      taskId: t.id,
    };
    setEvents(prev => [...prev, ev]);
    showToast(`${t.id} запланировано на ${fmtHour(startHour)}`);
  };

  // ---- People ops ----
  const cyclePerson = (id) => {
    setPeople(prev => prev.map(p => {
      if (p.id !== id) return p;
      const idx = PING_CYCLE.indexOf(p.state);
      return {...p, state: PING_CYCLE[(idx + 1) % PING_CYCLE.length]};
    }));
  };

  // ---- Derived ----
  const eventsByDay = aUseMemo(() => {
    const m = {};
    events.forEach(e => {
      const d = e.date || D.isoToday;
      (m[d] = m[d] || []).push(e);
    });
    return m;
  }, [events]);

  const scheduleMap = aUseMemo(() => {
    const m = {};
    events.forEach(e => {
      if (e.taskId && e.date === selectedDate) {
        m[e.taskId] = fmtHour(e.start);
      }
    });
    return m;
  }, [events, selectedDate]);

  const togglePri = (p) => {
    setPriFilter(prev => {
      const n = new Set(prev);
      if (n.has(p)) n.delete(p); else n.add(p);
      return n;
    });
  };

  const filters = { q: search, priorities: priFilter };

  const stats = aUseMemo(() => {
    const by = {};
    D.STATUSES.forEach(s => by[s.id] = 0);
    tasks.forEach(t => { by[t.status] = (by[t.status]||0) + 1; });
    return by;
  }, [tasks]);

  const viewTitle = { board: "Board", timeline: "Timeline", week: "Week" }[view];

  return (
    <div className={"app view-" + view}>
      <div className="topbar">
        <div className="brand">
          <span className="dot" />
          <span>todo<span style={{color:"var(--text-muted)"}}>·</span>cpp</span>
        </div>
        <div className="crumbs mono">
          <b>eNB-core</b> / sprint-{Math.floor((D.today.getMonth()+1)*2.1)} / <b>You</b>
        </div>
        <div className="grow" />
        <div className="search">
          <span style={{color:"var(--text-dim)", fontSize:"11px"}}>⌕</span>
          <input
            placeholder="Поиск задач, ID, branch…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <span className="kbd">⌘K</span>
        </div>
        <button className="btn primary" onClick={() => createTaskInStatus("todo")}>+ Task</button>
      </div>

      {/* Side rail */}
      <div className="rail">
        <button
          className={"rail-btn" + (view === "board" ? " active" : "")}
          title="Board (Kanban)"
          onClick={() => setView("board")}
        >▦</button>
        <button
          className={"rail-btn" + (view === "timeline" ? " active" : "")}
          title="Timeline (по дедлайнам)"
          onClick={() => setView("timeline")}
        >☰</button>
        <button
          className={"rail-btn" + (view === "week" ? " active" : "")}
          title="Week (7 дней)"
          onClick={() => setView("week")}
        >◫</button>
        <div className="sep" />
        <div className="rail-btn" title="Blocked">
          ⊘
          {stats.blocked > 0 && <span className="count">{stats.blocked}</span>}
        </div>
        <div className="rail-btn" title="Code Review">
          ⎇
          {stats.review > 0 && <span className="count" style={{background:"var(--st-review)"}}>{stats.review}</span>}
        </div>
        <div className="sep" />
        <button
          className={"rail-btn" + (view === "docs" ? " active" : "")}
          title="C++ References (Docs)"
          onClick={() => setView("docs")}
        >C++</button>
        <button
          className={"rail-btn" + (view === "docs" ? " active" : "")}
          title="Docs"
          onClick={() => setView("docs")}
        >§</button>
        <div style={{flex:1}} />
        <div className="rail-btn" title="Settings">⚙</div>
      </div>

      {/* Main */}
      <div className="main">
        <div className="toolbar">
          <span className="filter-chip" style={{background:"transparent", border:"none", color:"var(--text-muted)", padding:"4px 4px"}}>
            <b style={{color:"var(--text)", fontWeight:600, marginRight:"4px"}}>{viewTitle}</b>
            · Filters:
          </span>
          {["P0","P1","P2","P3"].map(p => (
            <button
              key={p}
              className={"filter-chip" + (priFilter.has(p) ? " active":"")}
              onClick={() => togglePri(p)}
            >
              <span className="swatch" style={{background:`var(--${p.toLowerCase()})`}} />
              {p}
            </button>
          ))}
          {priFilter.size > 0 && (
            <button className="filter-chip" style={{color:"var(--text-dim)"}} onClick={() => setPriFilter(new Set())}>clear</button>
          )}
          <span className="count">
            {tasks.length} tasks · {stats.prog + stats.half} active · {stats.blocked} blocked · {stats.review} review
          </span>
        </div>
        {view === "board" && (
          <KanbanBoard
            tasks={tasks}
            statuses={D.STATUSES}
            filters={filters}
            onMove={moveTask}
            onOpen={openTask}
            onCreate={createTaskInStatus}
            scheduleMap={scheduleMap}
          />
        )}
        {view === "timeline" && (
          <TimelineView
            tasks={tasks}
            statuses={D.STATUSES}
            onOpen={openTask}
            filters={filters}
            scheduleMap={scheduleMap}
            showDone={showDoneTimeline}
            onToggleDone={() => setShowDoneTimeline(v => !v)}
          />
        )}
        {view === "week" && (
          <WeekView
            tasks={tasks}
            events={events}
            statuses={D.STATUSES}
            selectedIso={selectedDate}
            onSelectDay={(d) => { setSelectedDate(d); }}
            onOpen={openTask}
            onEventOpen={setEditingEvent}
          />
        )}
        {view === "docs" && (
          <DocsView />
        )}
      </div>

      {/* Right column: mini-week + day cal + people */}
      <div className="right">
        <MiniWeek
          selectedIso={selectedDate}
          onSelect={setSelectedDate}
          eventsByDay={eventsByDay}
        />
        <DayCalendar
          selectedIso={selectedDate}
          events={events}
          tasks={tasks}
          onEventChange={changeEvent}
          onEventCreate={createEvent}
          onEventOpen={setEditingEvent}
          onTaskDrop={handleTaskDrop}
        />
        <PeopleList people={people} onCycle={cyclePerson} />
      </div>

      {/* Tweaks panel */}
      <TweaksPanel title="Tweaks">
        <TweakSection title="Внешний вид">
          <TweakRadio
            label="Тема"
            value={t.theme}
            onChange={(v) => setTweak("theme", v)}
            options={[{value:"dark", label:"Тёмная"}, {value:"light", label:"Светлая"}]}
          />
          <TweakRadio
            label="Плотность"
            value={t.density}
            onChange={(v) => setTweak("density", v)}
            options={[{value:"compact", label:"Compact"}, {value:"comfy", label:"Comfy"}]}
          />
        </TweakSection>
      </TweaksPanel>

      {editingTask && (
        <TaskModal
          task={editingTask}
          statuses={D.STATUSES}
          onClose={() => setEditingTask(null)}
          onSave={saveTask}
          onDelete={deleteTask}
        />
      )}
      {editingEvent && (
        <EventModal
          event={editingEvent}
          tasks={tasks}
          onClose={() => setEditingEvent(null)}
          onSave={saveEvent}
          onDelete={deleteEvent}
        />
      )}

      {toast && <div className="toast">{toast}</div>}
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
