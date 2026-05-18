// Settings — top-level container

const SETTINGS_SECTIONS = [
  { id: "profile",       icon: "◉",   title: "Profile",          sub: "Имя, роль, команда" },
  { id: "appearance",    icon: "◑",   title: "Appearance",       sub: "Тема, акцент, плотность" },
  { id: "notifications", icon: "◔",   title: "Notifications",    sub: "Дедлайны, созвоны, Slack" },
  { id: "calendar",      icon: "◫",   title: "Calendar",         sub: "Часы, focus time" },
  { id: "tasks",         icon: "▦",   title: "Tasks & Workflow", sub: "Префикс ID, дефолты" },
  { id: "shortcuts",     icon: "⌘",   title: "Shortcuts",        sub: "Горячие клавиши" },
  { id: "cpp",           icon: "C++", title: "C++ Defaults",     sub: "Сборка, sanitizers" },
  { id: "integrations",  icon: "⎘",   title: "Integrations",     sub: "Jira, GitHub, Slack" },
  { id: "data",          icon: "↯",   title: "Data",             sub: "Export, import, reset" },
  { id: "about",         icon: "?",   title: "About",            sub: "Версия, лицензии" },
];

function SettingsView({ settings, setSettings, onToast }) {
  const [activeSection, setActiveSection] = sUseState("profile");
  const [search, setSearch] = sUseState("");

  const filteredSections = sUseMemo(() => {
    if (!search.trim()) return SETTINGS_SECTIONS;
    const q = search.toLowerCase();
    return SETTINGS_SECTIONS.filter(s =>
      s.title.toLowerCase().includes(q) || s.sub.toLowerCase().includes(q)
    );
  }, [search]);

  const setGroup = (group) => (key, value) => {
    setSettings(prev => ({ ...prev, [group]: { ...prev[group], [key]: value } }));
  };

  const resetShortcuts = () => {
    setSettings(prev => ({ ...prev, shortcuts: { ...DEFAULT_SETTINGS.shortcuts } }));
    onToast && onToast("Shortcuts сброшены");
  };

  const exportJson = () => {
    const data = JSON.stringify(settings, null, 2);
    const blob = new Blob([data], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "todo-cpp-settings.json";
    a.click();
    URL.revokeObjectURL(url);
    onToast && onToast("Экспортировано: todo-cpp-settings.json");
  };

  const importJson = () => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = "application/json,.json";
    input.onchange = (e) => {
      const file = e.target.files[0];
      if (!file) return;
      const reader = new FileReader();
      reader.onload = () => {
        try {
          const parsed = JSON.parse(reader.result);
          setSettings(parsed);
          onToast && onToast("Настройки импортированы");
        } catch (err) {
          alert("Ошибка парсинга JSON: " + err.message);
        }
      };
      reader.readAsText(file);
    };
    input.click();
  };

  const resetAll = () => {
    if (confirm("Сбросить все настройки к значениям по умолчанию?")) {
      setSettings(DEFAULT_SETTINGS);
      onToast && onToast("Настройки сброшены");
    }
  };

  const renderSection = () => {
    const s = settings;
    switch (activeSection) {
      case "profile":       return <SecProfile s={s.profile} set={setGroup("profile")} />;
      case "appearance":    return <SecAppearance s={s.appearance} set={setGroup("appearance")} />;
      case "notifications": return <SecNotifications s={s.notifications} set={setGroup("notifications")} />;
      case "calendar":      return <SecCalendar s={s.calendar} set={setGroup("calendar")} />;
      case "tasks":         return <SecTasks s={s.tasks} set={setGroup("tasks")} />;
      case "shortcuts":     return <SecShortcuts s={s.shortcuts} set={setGroup("shortcuts")} onReset={resetShortcuts} />;
      case "cpp":           return <SecCpp s={s.cpp} set={setGroup("cpp")} />;
      case "integrations":  return <SecIntegrations s={s.integrations} set={setGroup("integrations")} />;
      case "data":          return <SecData s={s.data} set={setGroup("data")} onExport={exportJson} onImport={importJson} onReset={resetAll} />;
      case "about":         return <SecAbout />;
      default:              return null;
    }
  };

  const activeMeta = SETTINGS_SECTIONS.find(s => s.id === activeSection) || SETTINGS_SECTIONS[0];

  return (
    <div className="settings">
      <aside className="settings-nav">
        <div className="settings-nav-head">
          <div className="settings-nav-title">Settings</div>
          <div className="settings-nav-sub mono">{Object.keys(settings).length} groups · {settings.profile.handle}</div>
        </div>
        <div className="settings-search">
          <span style={{color:"var(--text-dim)", fontSize:"11px"}}>⌕</span>
          <input
            placeholder="Search settings…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <div className="settings-nav-list">
          {filteredSections.map(s => (
            <button
              key={s.id}
              className={"settings-nav-item" + (activeSection === s.id ? " active" : "")}
              onClick={() => setActiveSection(s.id)}
            >
              <span className="settings-nav-icon">{s.icon}</span>
              <span className="settings-nav-text">
                <span className="settings-nav-name">{s.title}</span>
                <span className="settings-nav-desc">{s.sub}</span>
              </span>
            </button>
          ))}
          {filteredSections.length === 0 && (
            <div className="settings-empty mono">Ничего не найдено</div>
          )}
        </div>
        <div className="settings-nav-foot mono">v0.4.2 · stable</div>
      </aside>
      <main className="settings-main">
        <header className="settings-main-head">
          <div className="settings-bread mono">Settings / <b>{activeMeta.title}</b></div>
          <h1 className="settings-main-title">{activeMeta.icon}  {activeMeta.title}</h1>
          <div className="settings-main-sub">{activeMeta.sub}</div>
        </header>
        <div className="settings-main-body">
          {renderSection()}
        </div>
      </main>
    </div>
  );
}

Object.assign(window, { SettingsView, SETTINGS_SECTIONS });
