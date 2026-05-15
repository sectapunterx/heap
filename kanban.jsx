// Kanban board component
const { useState, useRef } = React;

function priorityIcon(p) {
  // simple bar visualization
  const filled = { P0: 4, P1: 3, P2: 2, P3: 1 }[p] || 0;
  return (
    <span className={"pri " + p} title={"Priority " + p}>
      <span>{p}</span>
    </span>
  );
}

function deadlineLabel(iso, todayIso) {
  if (!iso) return null;
  const a = new Date(iso); const b = new Date(todayIso);
  const days = Math.round((a - b) / 86400000);
  let cls = "";
  let txt = "";
  if (days < 0) { cls = "urgent"; txt = `${-days}d overdue`; }
  else if (days === 0) { cls = "urgent"; txt = "today"; }
  else if (days === 1) { cls = "soon"; txt = "tomorrow"; }
  else if (days <= 3) { cls = "soon"; txt = `${days}d`; }
  else { txt = `${days}d`; }
  return <span className={"deadline " + cls}>⏱ {txt}</span>;
}

function TaskCard({ task, onDragStart, onClick, onDragToCalStart, scheduled }) {
  return (
    <div
      className="task"
      draggable
      onDragStart={(e) => onDragStart(e, task)}
      onClick={() => onClick(task)}
    >
      <div className="row">
        <span className="id mono">{task.id}</span>
        {priorityIcon(task.priority)}
        {task.branch && (
          <span className="mono" style={{marginLeft:"auto", color:"var(--text-dim)", fontSize:"10px"}}>
            ⎇ {task.branch.split("/").pop().slice(0,18)}
          </span>
        )}
      </div>
      <div className="title">{task.title}</div>
      {task.desc && <div className="desc">{task.desc}</div>}
      <div className="foot">
        {deadlineLabel(task.deadline, window.__APP_DATA__.isoToday)}
        {scheduled && <span className="ev-tag mono">⏰ {scheduled}</span>}
      </div>
    </div>
  );
}

function KanbanBoard({ tasks, statuses, filters, onMove, onOpen, onCreate, onTaskDragStart, scheduleMap }) {
  const [dragOver, setDragOver] = useState(null);
  const dragRef = useRef(null);

  const handleDragStart = (e, task) => {
    dragRef.current = task;
    e.dataTransfer.setData("text/plain", task.id);
    e.dataTransfer.setData("application/x-task-id", task.id);
    e.dataTransfer.effectAllowed = "move";
    if (onTaskDragStart) onTaskDragStart(task);
  };

  const handleDragOver = (e, statusId) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
    setDragOver(statusId);
  };

  const handleDrop = (e, statusId) => {
    e.preventDefault();
    const taskId = e.dataTransfer.getData("application/x-task-id");
    if (taskId) onMove(taskId, statusId);
    setDragOver(null);
    dragRef.current = null;
  };

  const visibleStatuses = statuses;

  return (
    <div className="kanban-wrap">
      <div className="kanban">
        {visibleStatuses.map((s) => {
          const colTasks = tasks.filter(
            (t) => t.status === s.id
              && (!filters.q || (t.title + " " + t.id + " " + (t.desc||"")).toLowerCase().includes(filters.q.toLowerCase()))
              && (filters.priorities.size === 0 || filters.priorities.has(t.priority))
          );
          return (
            <div
              key={s.id}
              className={"col" + (dragOver === s.id ? " drag-over" : "")}
              onDragOver={(e) => handleDragOver(e, s.id)}
              onDragLeave={() => setDragOver((d) => d === s.id ? null : d)}
              onDrop={(e) => handleDrop(e, s.id)}
            >
              <div className="col-head">
                <span className="dot" style={{background: s.color}} />
                <span className="name">{s.name}</span>
                <span className="cnt">{colTasks.length}</span>
                <button className="add" title="Add task" onClick={() => onCreate(s.id)}>+</button>
              </div>
              <div className="col-body">
                {colTasks.map((t) => (
                  <TaskCard
                    key={t.id}
                    task={t}
                    onDragStart={handleDragStart}
                    onClick={onOpen}
                    scheduled={scheduleMap[t.id]}
                  />
                ))}
                {colTasks.length === 0 && (
                  <div style={{fontSize:"11px", color:"var(--text-dim)", textAlign:"center", padding:"16px 4px", fontStyle:"italic"}}>
                    — пусто —
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

Object.assign(window, { TaskCard, KanbanBoard });
