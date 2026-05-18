// Settings — reusable controls + defaults
const { useState: sUseState, useMemo: sUseMemo } = React;

function SwitchToggle({ checked, onChange, label, hint }) {
  return (
    <div className="set-switch">
      <div className="set-switch-text">
        <div className="set-switch-label">{label}</div>
        {hint && <div className="set-switch-hint">{hint}</div>}
      </div>
      <button
        className={"switch" + (checked ? " on" : "")}
        onClick={() => onChange(!checked)}
        role="switch"
        aria-checked={checked}
      >
        <span className="switch-thumb" />
      </button>
    </div>
  );
}

function SegmentedRadio({ value, onChange, options, label, hint }) {
  return (
    <div className="set-field">
      {label && (
        <div className="set-field-label">
          {label}{hint && <span className="set-field-hint"> · {hint}</span>}
        </div>
      )}
      <div className="segmented">
        {options.map(opt => {
          const v = typeof opt === "string" ? opt : opt.value;
          const l = typeof opt === "string" ? opt : opt.label;
          return (
            <button
              key={v}
              className={"segmented-opt" + (value === v ? " on" : "")}
              onClick={() => onChange(v)}
            >{l}</button>
          );
        })}
      </div>
    </div>
  );
}

function SwatchPicker({ value, onChange, options, label }) {
  return (
    <div className="set-field">
      {label && <div className="set-field-label">{label}</div>}
      <div className="swatches">
        {options.map(c => (
          <button
            key={c}
            className={"swatch-btn" + (value === c ? " on" : "")}
            style={{background: c}}
            onClick={() => onChange(c)}
          />
        ))}
      </div>
    </div>
  );
}

function TextField({ value, onChange, label, hint, placeholder, mono, type }) {
  return (
    <label className="set-field">
      {label && (
        <div className="set-field-label">
          {label}{hint && <span className="set-field-hint"> · {hint}</span>}
        </div>
      )}
      <input
        className={mono ? "mono" : ""}
        type={type || "text"}
        value={value == null ? "" : value}
        onChange={(e) => onChange(type === "number" ? Number(e.target.value) : e.target.value)}
        placeholder={placeholder}
      />
    </label>
  );
}

function SliderField({ value, onChange, min, max, step, label, hint, unit }) {
  return (
    <div className="set-field">
      {label && (
        <div className="set-field-label">
          {label}
          <span className="set-field-value mono">{value}{unit || ""}</span>
        </div>
      )}
      {hint && <div className="set-field-hint" style={{marginBottom:"6px"}}>{hint}</div>}
      <input
        type="range"
        className="set-slider"
        min={min} max={max} step={step}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
      />
    </div>
  );
}

function SelectField({ value, onChange, label, options }) {
  return (
    <label className="set-field">
      {label && <div className="set-field-label">{label}</div>}
      <select value={value} onChange={(e) => onChange(e.target.value)}>
        {options.map(o => {
          const v = typeof o === "string" ? o : o.value;
          const l = typeof o === "string" ? o : o.label;
          return <option key={v} value={v}>{l}</option>;
        })}
      </select>
    </label>
  );
}

const ACCENT_OPTIONS = [
  "oklch(0.78 0.12 205)",
  "oklch(0.78 0.14 145)",
  "oklch(0.76 0.16 295)",
  "oklch(0.78 0.16 80)",
  "oklch(0.74 0.18 25)",
  "oklch(0.78 0.14 240)",
];

const DEFAULT_SETTINGS = {
  profile: {
    name: "Алексей Тимофеев",
    handle: "alex.t",
    role: "C++ Engineer · LTE",
    team: "eNB-core",
    timezone: "Europe/Moscow",
    color: "oklch(0.74 0.12 200)",
  },
  appearance: {
    theme: "dark", density: "comfy", accent: ACCENT_OPTIONS[0],
    fontUI: "IBM Plex Sans", fontMono: "JetBrains Mono",
    reducedMotion: false, highContrast: false,
  },
  notifications: {
    deadlineReminders: true, deadlineLeadHours: 24,
    standupReminder: true, meetingLead: 5,
    slackPingsOnReview: true, blockedDailyDigest: false,
    soundOnPing: false, desktopNotif: true,
    quietHours: true, quietFrom: "19:00", quietTo: "09:00",
  },
  calendar: {
    weekStart: "mon", timeFormat: "24h",
    workStart: 9, workEnd: 19, snapMinutes: 15,
    showWeekends: false, autoFocusBlock: true,
    focusBlockDuration: 90, standupTime: "10:00",
  },
  tasks: {
    idPrefix: "LTE", defaultPriority: "P2", defaultStatus: "todo",
    archiveDoneAfterDays: 7, autoMoveBlockedAfterDays: 3,
    requireBranchOnReview: true, showSubtasks: true,
  },
  shortcuts: {
    "Создать задачу":            "⌘ N",
    "Поиск":                     "⌘ K",
    "Board view":                "G then B",
    "Timeline view":             "G then T",
    "Week view":                 "G then W",
    "Docs view":                 "G then D",
    "Settings":                  "⌘ ,",
    "Запланировать в календарь": "S",
    "Изменить приоритет":        "P",
    "Изменить статус":           "X",
  },
  cpp: {
    defaultCompiler: "clang-17", defaultStandard: "C++20",
    defaultSanitizer: "asan", defaultBuildType: "RelWithDebInfo",
    bazelArgs: "--jobs=12 --keep_going",
    compilerExplorerUrl: "https://godbolt.org/",
    showAsmInline: false,
  },
  integrations: {
    jira:       { connected: true,  url: "jira.internal.corp", project: "LTE" },
    github:     { connected: true,  org: "lte-core", branchTemplate: "{type}/{id}-{slug}" },
    slack:      { connected: true,  workspace: "lte-team", dmChannel: "#enb-oncall" },
    pagerduty:  { connected: false, schedule: "" },
    confluence: { connected: false, space: "" },
  },
  data: { autoBackup: true, backupInterval: "daily" },
};

Object.assign(window, {
  SwitchToggle, SegmentedRadio, SwatchPicker, TextField, SliderField, SelectField,
  ACCENT_OPTIONS, DEFAULT_SETTINGS,
});
