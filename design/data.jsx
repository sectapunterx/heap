// Sample data for a C++ 3GPP LTE programmer's day

const STATUSES = [
  { id: "backlog",  name: "Backlog",      color: "var(--st-backlog)" },
  { id: "todo",     name: "To Do",        color: "var(--st-todo)" },
  { id: "prog",     name: "In Progress",  color: "var(--st-prog)" },
  { id: "half",     name: "50/50",        color: "var(--st-half)" },
  { id: "blocked",  name: "Blocked",      color: "var(--st-blocked)" },
  { id: "review",   name: "Code Review",  color: "var(--st-review)" },
  { id: "done",     name: "Done",         color: "var(--st-done)" },
];

const PRIORITIES = ["P0", "P1", "P2", "P3"];

const today = new Date();
const yyyy = today.getFullYear();
const mm = today.getMonth();
const dd = today.getDate();
const isoToday = `${yyyy}-${String(mm+1).padStart(2,"0")}-${String(dd).padStart(2,"0")}`;
const addDays = (n) => {
  const d = new Date(yyyy, mm, dd + n);
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`;
};

const SAMPLE_TASKS = [
  // --- In Progress ---
  {
    id: "LTE-2398", title: "PDCP SN wraparound при ре-ESTABLISHMENT",
    desc: "После re-establishment PDCP SN иногда коллапсирует к 0 раньше HFN rollover. Воспроизводится на UE Cat 6.",
    priority: "P0", status: "prog", deadline: addDays(1),
    branch: "fix/pdcp-sn-wrap-2398",
  },
  {
    id: "LTE-2412", title: "HARQ retx scheduler: учёт PUSCH grant gaps",
    desc: "Оптимизация по результатам profiling-а: при потерях grant ID HARQ RV выбирается не оптимально.",
    priority: "P1", status: "prog", deadline: addDays(4),
    branch: "feat/harq-retx-gaps-2412",
  },
  // --- 50/50 ---
  {
    id: "LTE-2467", title: "NAS EMM Attach Reject — корректные cause codes",
    desc: "Не уверен в интерпретации 24.301 §5.5.1.2.5 для cause #15 vs #11. Нужен совет от Олега.",
    priority: "P1", status: "half", deadline: addDays(2),
    branch: "feat/nas-attach-reject-2467",
  },
  {
    id: "LTE-2520", title: "SIB1 broadcast scheduling: TDD config 2",
    desc: "В TDD UL/DL config 2 SIB1 иногда мапится на DL subframe с PHICH коллизией.",
    priority: "P2", status: "half", deadline: addDays(6),
    branch: "fix/sib1-tdd2-2520",
  },
  // --- Blocked ---
  {
    id: "LTE-2401", title: "S1AP UE Context Release: timeout 10s",
    desc: "Жду trace от QA: воспроизводится только у одного оператора с ENDC fallback.",
    priority: "P0", status: "blocked", deadline: addDays(0),
    branch: "fix/s1ap-ctxrel-2401",
  },
  // --- Code Review ---
  {
    id: "LTE-2289", title: "PCAP capture rotation: per-cell файлы",
    desc: "PR #4471. Жду Andrey, маленький review.",
    priority: "P2", status: "review", deadline: addDays(3),
    branch: "feat/pcap-rotate-2289",
  },
  {
    id: "LTE-2502", title: "GTP-U packet processing: SIMD сериализация",
    desc: "PR #4488. +18% throughput на x86, -3% на ARM — обсудить trade-off.",
    priority: "P1", status: "review", deadline: addDays(2),
    branch: "perf/gtpu-simd-2502",
  },
  // --- To Do ---
  {
    id: "LTE-2511", title: "LTE-A CA: secondary cell activation race",
    desc: "Активация SCell иногда приходит до завершения RRC reconfig — race на shared state.",
    priority: "P1", status: "todo", deadline: addDays(5),
    branch: "",
  },
  {
    id: "LTE-2341", title: "Refactor RRC Connection Reconfiguration handler",
    desc: "Разбить монолитный 1.4k LOC handler на secure mode + bearer config + meas config.",
    priority: "P2", status: "todo", deadline: addDays(8),
    branch: "",
  },
  {
    id: "LTE-2455", title: "PHY: SRS configuration по dedicated RRC",
    desc: "Добавить поддержку srs-ConfigDedicated в RRC reconfig path.",
    priority: "P2", status: "todo", deadline: addDays(9),
    branch: "",
  },
  // --- Done (today) ---
  {
    id: "LTE-2099", title: "RLC AM: memory leak в re-transmission buffer",
    desc: "valgrind clean, merged в master сегодня утром.",
    priority: "P1", status: "done", deadline: addDays(-1),
    branch: "fix/rlc-am-leak-2099",
  },
  {
    id: "LTE-2470", title: "eNB лог: structured fields для PHY trace",
    desc: "Готово, merged.",
    priority: "P3", status: "done", deadline: addDays(-2),
    branch: "",
  },
  // --- Backlog ---
  {
    id: "LTE-2123", title: "eNB internal logging улучшения",
    desc: "Slow-path логи в горячем цикле, нужен ring buffer.",
    priority: "P3", status: "backlog", deadline: "",
    branch: "",
  },
  {
    id: "LTE-2602", title: "MAC: BSR triggering для VoLTE",
    desc: "Edge case: paddingBSR vs regularBSR при низкой нагрузке.",
    priority: "P3", status: "backlog", deadline: "",
    branch: "",
  },
  {
    id: "LTE-2611", title: "RACH preamble groupB threshold tuning",
    desc: "Профилировать на нагрузке >200 UE/cell.",
    priority: "P3", status: "backlog", deadline: "",
    branch: "",
  },
];

const SAMPLE_EVENTS = [
  { id: "ev-1", title: "Daily standup",       type: "standup", start: 10.0, end: 10.25, attendees: "LTE Core team" },
  { id: "ev-2", title: "1:1 с Олегом",         type: "oneone",  start: 11.0, end: 11.5,  attendees: "Олег Т." },
  { id: "ev-3", title: "Focus: LTE-2398",      type: "focus",   start: 13.0, end: 15.0,  attendees: "🔒 deep work" },
  { id: "ev-4", title: "LTE Team Sync",        type: "sync",    start: 16.0, end: 16.5,  attendees: "8 человек" },
  { id: "ev-5", title: "Code review: GTP-U",   type: "sync",    start: 17.0, end: 17.5,  attendees: "Andrey, Виктор" },
];

const SAMPLE_PEOPLE = [
  { id: "p1", name: "Олег Т.",     role: "Tech Lead",        question: "Уточнить интерпретацию 24.301 §5.5.1.2.5 (cause #15 vs #11)", state: "todo", color: "oklch(0.72 0.12 25)" },
  { id: "p2", name: "Маша К.",     role: "QA",               question: "Попросить полный S1AP trace по LTE-2401 от оператора X", state: "todo", color: "oklch(0.72 0.12 305)" },
  { id: "p3", name: "Andrey S.",   role: "Senior C++ dev",   question: "Пнуть на review PR #4471 (PCAP rotation)", state: "pinged", color: "oklch(0.74 0.12 175)" },
  { id: "p4", name: "Виктор Л.",   role: "Architect",        question: "Слот на 30 мин — обсудить SIMD trade-off на ARM (LTE-2502)", state: "todo", color: "oklch(0.74 0.12 235)" },
  { id: "p5", name: "Екатерина",   role: "PM",               question: "Подтвердить acceptance criteria для LTE-2412", state: "replied", color: "oklch(0.78 0.12 80)" },
  { id: "p6", name: "Hiroshi M.",  role: "PHY team",         question: "Спросить про SRS dedicated config, есть ли тесты", state: "todo", color: "oklch(0.74 0.12 145)" },
];

window.__APP_DATA__ = {
  STATUSES, PRIORITIES, SAMPLE_TASKS, SAMPLE_EVENTS, SAMPLE_PEOPLE,
  isoToday, addDays, today,
};
