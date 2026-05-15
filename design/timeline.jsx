// Timeline view — tasks grouped by deadline bucket
const { useMemo: tlUseMemo } = React;

function getBucket(iso, todayIso) {
  if (!iso) return "nodl";
  const a = new Date(iso), b = new Date(todayIso);
  const d = Math.round((a - b) / 86400000);
  if (d < 0) return "overdue";
  if (d === 0) return "today";
  if (d === 1) return "tomorrow";
  if (d <= 6) return "thisweek";
  if (d <= 13) return "nextweek";
  return "later";
}

const BUCKET_META = {
  overdue:  { name: "Overdue",      icon: "!",  color: "var(--p0)",       accent: "overdue" },
  today:    { name: "Today",        icon: "●",  color: "var(--accent)",   accent: "today" },
  tomorrow: { name: "Tomorrow",     icon: "○",  color: "var(--p1)",       accent: "tomorrow" },
  thisweek: { name: "This week",    icon: "▷",  color: "var(--st-prog)",  accent: "" },
  nextweek: { name: "Next week",    icon: "›",  color: "var(--text-muted)", accent: "" },
  later:    { name: "Later",        icon: "…",  color: "var(--text-dim)", accent: "" },
  nodl:     { name: "No deadline",  icon: "—",  color: "var(--text-dim)", accent: "" },
};

function diffLabel(iso, todayIso) {
  if (!iso) return "—";
  const a = new Date(iso), b = new Date(todayIso);
  const d = Math.round((a - b) / 86400000);
  if (d < 0) return `${-d}d overdue`;
  if (d === 0) return "today";
  if (d === 1) return "+1 day";
  if (d < 7) return `+${d} days`;
  return `+${d}d`;
}

function fmtBucketDate(iso) {
  if (!iso) return "";
  const d = new Date(iso);
  return d.toLocaleDateString("ru-RU", { weekday: "short", day: "numeric", month: "short" });
}

function TimelineView({ tasks, statuses, onOpen, filters, scheduleMap, showDone, onToggleDone }) {
  const todayIso = window.__APP_DATA__.isoToday;

  const grouped = tlUseMemo(() => {
    let filt = tasks.filter(t =>
      (!filters.q || (t.title + " " + t.id + " " + (t.desc||"")).toLowerCase().includes(filters.q.toLowerCase()))
      && (filters.priorities.size === 0 || filters.priorities.has(t.priority))
      && (showDone || t.status !== "done")
    );
    const by = {};
    filt.forEach(t => {
      const b = getBucket(t.deadline, todayIso);
      (by[b] = by[b] || []).push(t);
    });
    Object.keys(by).forEach(b => {
      by[b].sort((a,bb) => {
        const da = a.deadline || "9999"; const db = bb.deadline || "9999";
        if (da !== db) return da.localeCompare(db);
        return a.priority.localeCompare(bb.priority);
      });
    });
    return by;
  }, [tasks, filters.q, filters.priorities, showDone]);

  const statusOf = (id) => statuses.find(s => s.id === id) || {name: id, color: "var(--text-dim)"};
  const order = ["overdue","today","tomorrow","thisweek","nextweek","later","nodl"];

  // sub-groups inside thisweek/nextweek/later by exact date
  const renderDateSubgroups = (list) => {
    const byDate = {};
    list.forEach(t => {
      const key = t.deadline || "—";
      (byDate[key] = byDate[key] || []).push(t);
    });
    const keys = Object.keys(byDate).sort();
    return keys.map(k => (
      <div key={k} className="tl-subgroup">
        {k !== "—" && <div className="tl-subdate mono">{fmtBucketDate(k)} · {k}</div>}
        {byDate[k].map(t => renderRow(t))}
      </div>
    ));
  };

  const renderRow = (t) => {
    const s = statusOf(t.status);
    const sched = scheduleMap[t.id];
    return (
      <div key={t.id} className="tl-row" onClick={() => onOpen(t)}>
        <span className="tl-status-dot" style={{background: s.color}} title={s.name} />
        <span className={"pri " + t.priority}>{t.priority}</span>
        <span className="tl-id mono">{t.id}</span>
        <span className="tl-title">
          {t.title}
          {t.desc && <span className="tl-desc">{t.desc.slice(0, 80)}{t.desc.length>80 ? "…" : ""}</span>}
        </span>
        <span className="tl-meta">
          <span className="tl-state" style={{borderColor: `oklch(from ${s.color} l c h / 0.4)`, color: s.color}}>{s.name}</span>
          {t.branch && <span className="mono tl-branch">⎇ {t.branch.split('/').pop()}</span>}
          {sched && <span className="mono tl-sched">⏰ {sched}</span>}
          <span className="tl-deadline mono">{diffLabel(t.deadline, todayIso)}</span>
        </span>
      </div>
    );
  };

  const totalShown = order.reduce((acc, b) => acc + ((grouped[b]||[]).length), 0);

  return (
    <div className="timeline">
      <div className="tl-head">
        <div>
          <div className="tl-h-title">Timeline · по дедлайнам</div>
          <div className="tl-h-sub mono">{totalShown} task{totalShown===1?"":"s"} · today is {todayIso}</div>
        </div>
        <div style={{display:"flex", gap:"6px", alignItems:"center"}}>
          <button
            className={"filter-chip" + (showDone ? " active":"")}
            onClick={onToggleDone}
          >
            <span className="swatch" style={{background:"var(--st-done)"}} />
            Show done
          </button>
        </div>
      </div>
      <div className="tl-body">
        {order.map(b => {
          const list = grouped[b];
          if (!list || !list.length) return null;
          const meta = BUCKET_META[b];
          const groupCls = "tl-group" + (meta.accent ? " tl-" + meta.accent : "");
          const showSubgroups = b === "thisweek" || b === "nextweek" || b === "later";
          return (
            <div key={b} className={groupCls}>
              <div className="tl-side">
                <div className="tl-marker" style={{background: meta.color}}>{meta.icon}</div>
                <div className="tl-name">{meta.name}</div>
                {(b === "overdue" || b === "today" || b === "tomorrow") && list[0].deadline && (
                  <div className="tl-date mono">{fmtBucketDate(list[0].deadline)}</div>
                )}
                <div className="tl-count mono">{list.length} task{list.length===1?"":"s"}</div>
              </div>
              <div className="tl-rows">
                {showSubgroups ? renderDateSubgroups(list) : list.map(t => renderRow(t))}
              </div>
            </div>
          );
        })}
        {totalShown === 0 && (
          <div className="tl-empty">
            <div className="tl-empty-icon">✓</div>
            <div>Нет задач по фильтрам.</div>
            <div style={{color:"var(--text-dim)", fontSize:"12px", marginTop:"4px"}}>Сбрось фильтры или добавь задачу.</div>
          </div>
        )}
      </div>
    </div>
  );
}

Object.assign(window, { TimelineView });
