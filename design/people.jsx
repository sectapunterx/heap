// People to ping
function initials(name) {
  return name.split(/\s+/).map(w => w[0]).slice(0,2).join("").toUpperCase();
}

const PING_CYCLE = ["todo", "pinged", "replied"];
const PING_LABEL = { todo: "написать", pinged: "написал", replied: "ответил" };

function PeopleList({ people, onCycle }) {
  const todoCount = people.filter(p => p.state === "todo").length;
  return (
    <div className="people">
      <h3>
        <span>Кому написать</span>
        <span className="badge">{todoCount} pending · {people.length}</span>
      </h3>
      <div className="list">
        {people.map((p) => (
          <div
            key={p.id}
            className={"person " + p.state}
            onClick={() => onCycle(p.id)}
            title="Клик переключает статус: написать → написал → ответил"
          >
            <div className="avatar" style={{background: p.color}}>{initials(p.name)}</div>
            <div className="info">
              <div className="nm">{p.name} <span style={{color:"var(--text-dim)", fontWeight:400, fontSize:"11px"}}>· {p.role}</span></div>
              <div className="q">{p.question}</div>
            </div>
            <div className="state">{PING_LABEL[p.state]}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

Object.assign(window, { PeopleList, PING_CYCLE });
