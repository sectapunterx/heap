// Settings — section renderers

function SecProfile({ s, set }) {
  const initials = s.name.split(/\s+/).map(w => w[0]).slice(0,2).join("").toUpperCase();
  return (
    <div className="set-grid">
      <div className="set-card set-profile-card">
        <div className="set-avatar-big" style={{background: s.color}}>{initials}</div>
        <div style={{flex:1, display:"flex", flexDirection:"column", gap:"12px", minWidth: 0}}>
          <TextField label="Полное имя" value={s.name} onChange={(v) => set("name", v)} />
          <div className="set-row2">
            <TextField label="Handle" mono value={s.handle} onChange={(v) => set("handle", v)} placeholder="alex.t" />
            <TextField label="Роль" value={s.role} onChange={(v) => set("role", v)} />
          </div>
        </div>
      </div>
      <div className="set-row2">
        <TextField label="Команда" value={s.team} onChange={(v) => set("team", v)} />
        <TextField label="Часовой пояс" mono value={s.timezone} onChange={(v) => set("timezone", v)} />
      </div>
      <SwatchPicker
        label="Цвет аватара"
        value={s.color}
        onChange={(c) => set("color", c)}
        options={[
          "oklch(0.74 0.12 25)", "oklch(0.76 0.14 60)", "oklch(0.78 0.14 100)",
          "oklch(0.74 0.12 145)", "oklch(0.74 0.12 175)", "oklch(0.74 0.12 200)",
          "oklch(0.72 0.13 240)", "oklch(0.72 0.12 270)", "oklch(0.72 0.12 305)",
        ]}
      />
    </div>
  );
}

function SecAppearance({ s, set }) {
  return (
    <div className="set-grid">
      <SegmentedRadio
        label="Тема" value={s.theme} onChange={(v) => set("theme", v)}
        options={[{value:"dark", label:"Тёмная"}, {value:"light", label:"Светлая"}, {value:"auto", label:"Авто (системная)"}]}
      />
      <SegmentedRadio
        label="Плотность интерфейса" value={s.density} onChange={(v) => set("density", v)}
        options={[{value:"compact", label:"Compact"}, {value:"comfy", label:"Comfy"}]}
      />
      <SwatchPicker label="Акцентный цвет" value={s.accent} onChange={(v) => set("accent", v)} options={ACCENT_OPTIONS} />
      <div className="set-row2">
        <SegmentedRadio
          label="UI шрифт" value={s.fontUI} onChange={(v) => set("fontUI", v)}
          options={["IBM Plex Sans", "Inter", "System"]}
        />
        <SegmentedRadio
          label="Mono шрифт" value={s.fontMono} onChange={(v) => set("fontMono", v)}
          options={["JetBrains Mono", "Fira Code", "SF Mono"]}
        />
      </div>
      <SwitchToggle label="Reduced motion" hint="Отключить анимации и плавные переходы"
        checked={s.reducedMotion} onChange={(v) => set("reducedMotion", v)} />
      <SwitchToggle label="High contrast" hint="Увеличить контраст текста и границ"
        checked={s.highContrast} onChange={(v) => set("highContrast", v)} />
    </div>
  );
}

function SecNotifications({ s, set }) {
  return (
    <div className="set-grid">
      <div className="set-sub">Дедлайны и созвоны</div>
      <SwitchToggle label="Напоминать о дедлайнах" hint="Уведомлять заранее, если приближается deadline"
        checked={s.deadlineReminders} onChange={(v) => set("deadlineReminders", v)} />
      {s.deadlineReminders && (
        <SliderField label="За сколько часов до дедлайна" hint="Сколько времени до deadline должно остаться"
          unit="h" min={1} max={72} step={1}
          value={s.deadlineLeadHours} onChange={(v) => set("deadlineLeadHours", v)} />
      )}
      <SwitchToggle label="Standup reminder" hint="Pop-up за минуты до daily standup"
        checked={s.standupReminder} onChange={(v) => set("standupReminder", v)} />
      <SliderField label="За сколько минут до встречи" unit=" min" min={0} max={30} step={1}
        value={s.meetingLead} onChange={(v) => set("meetingLead", v)} />
      <div className="set-sub">Каналы доставки</div>
      <SwitchToggle label="Desktop notifications"
        checked={s.desktopNotif} onChange={(v) => set("desktopNotif", v)} />
      <SwitchToggle label="Slack pings при code-review"
        hint="Авто-пинг ревьюера, если PR висит >24ч"
        checked={s.slackPingsOnReview} onChange={(v) => set("slackPingsOnReview", v)} />
      <SwitchToggle label="Daily digest по Blocked"
        hint="Сводка задач в Blocked в 9:00"
        checked={s.blockedDailyDigest} onChange={(v) => set("blockedDailyDigest", v)} />
      <SwitchToggle label="Звук при ping"
        checked={s.soundOnPing} onChange={(v) => set("soundOnPing", v)} />
      <div className="set-sub">Quiet hours</div>
      <SwitchToggle label="Не беспокоить вечером" hint="Ничего не присылать в указанное окно"
        checked={s.quietHours} onChange={(v) => set("quietHours", v)} />
      {s.quietHours && (
        <div className="set-row2">
          <TextField label="С" mono value={s.quietFrom} onChange={(v) => set("quietFrom", v)} placeholder="19:00" />
          <TextField label="До" mono value={s.quietTo} onChange={(v) => set("quietTo", v)} placeholder="09:00" />
        </div>
      )}
    </div>
  );
}

function SecCalendar({ s, set }) {
  return (
    <div className="set-grid">
      <div className="set-row2">
        <SegmentedRadio
          label="Начало недели" value={s.weekStart} onChange={(v) => set("weekStart", v)}
          options={[{value:"mon", label:"Понедельник"}, {value:"sun", label:"Воскресенье"}]}
        />
        <SegmentedRadio
          label="Формат времени" value={s.timeFormat} onChange={(v) => set("timeFormat", v)}
          options={[{value:"24h", label:"24h"}, {value:"12h", label:"12h"}]}
        />
      </div>
      <div className="set-sub">Рабочие часы</div>
      <div className="set-row2">
        <SliderField label="Начало" unit=":00" min={6} max={12} step={1}
          value={s.workStart} onChange={(v) => set("workStart", v)} />
        <SliderField label="Окончание" unit=":00" min={14} max={23} step={1}
          value={s.workEnd} onChange={(v) => set("workEnd", v)} />
      </div>
      <SegmentedRadio
        label="Сетка слотов" value={s.snapMinutes} onChange={(v) => set("snapMinutes", Number(v))}
        options={[{value:5, label:"5 min"}, {value:15, label:"15 min"}, {value:30, label:"30 min"}]}
      />
      <SwitchToggle label="Показывать выходные"
        checked={s.showWeekends} onChange={(v) => set("showWeekends", v)} />
      <div className="set-sub">Focus time</div>
      <SwitchToggle label="Автоматически создавать focus-блок"
        hint="Когда задача переходит в In Progress — добавлять блок в календарь"
        checked={s.autoFocusBlock} onChange={(v) => set("autoFocusBlock", v)} />
      {s.autoFocusBlock && (
        <SliderField label="Длительность focus-блока" unit=" min" min={30} max={240} step={15}
          value={s.focusBlockDuration} onChange={(v) => set("focusBlockDuration", v)} />
      )}
      <TextField label="Время daily standup" mono value={s.standupTime}
        onChange={(v) => set("standupTime", v)} placeholder="10:00" />
    </div>
  );
}

function SecTasks({ s, set }) {
  return (
    <div className="set-grid">
      <div className="set-row2">
        <TextField label="Префикс ID" mono value={s.idPrefix} onChange={(v) => set("idPrefix", v)}
          hint={`Новые задачи: ${s.idPrefix}-XXXX`} />
        <SegmentedRadio
          label="Дефолтный приоритет" value={s.defaultPriority} onChange={(v) => set("defaultPriority", v)}
          options={["P0","P1","P2","P3"]}
        />
      </div>
      <SegmentedRadio
        label="Дефолтная колонка для новых задач" value={s.defaultStatus} onChange={(v) => set("defaultStatus", v)}
        options={[
          {value:"backlog", label:"Backlog"}, {value:"todo", label:"To Do"},
          {value:"prog", label:"In Progress"},
        ]}
      />
      <div className="set-sub">Автоматизации</div>
      <SliderField label="Архивировать Done через" unit=" дней" min={0} max={30} step={1}
        hint="0 — никогда не архивировать"
        value={s.archiveDoneAfterDays} onChange={(v) => set("archiveDoneAfterDays", v)} />
      <SliderField label="Подсвечивать Blocked после" unit=" дней" min={1} max={14} step={1}
        hint="Задача в Blocked дольше указанного — помечается красным"
        value={s.autoMoveBlockedAfterDays} onChange={(v) => set("autoMoveBlockedAfterDays", v)} />
      <SwitchToggle label="Требовать branch перед Code Review"
        hint="Запрещать перевод задачи в Review без указанного branch name"
        checked={s.requireBranchOnReview} onChange={(v) => set("requireBranchOnReview", v)} />
      <SwitchToggle label="Показывать subtasks"
        checked={s.showSubtasks} onChange={(v) => set("showSubtasks", v)} />
    </div>
  );
}

function SecShortcuts({ s, set, onReset }) {
  return (
    <div className="set-grid">
      <div className="set-sub">
        Горячие клавиши
        <button className="btn" style={{marginLeft:"auto"}} onClick={onReset}>Reset</button>
      </div>
      <div className="set-shortcuts">
        {Object.entries(s).map(([action, keys]) => {
          // Split on " then " to preserve separator, otherwise on whitespace
          const parts = keys.includes(" then ")
            ? keys.split(" then ").map((segment, segIdx, segArr) => ({
                keys: segment.trim().split(/\s+/),
                hasThen: segIdx < segArr.length - 1,
              }))
            : [{ keys: keys.trim().split(/\s+/), hasThen: false }];
          return (
            <div key={action} className="shortcut-row">
              <div className="shortcut-action">{action}</div>
              <div className="shortcut-keys">
                {parts.map((seg, segIdx) => (
                  <React.Fragment key={segIdx}>
                    {seg.keys.map((k, i) => (
                      <kbd key={i} className="kbd">{k}</kbd>
                    ))}
                    {seg.hasThen && <span className="shortcut-sep">then</span>}
                  </React.Fragment>
                ))}
                <button
                  className="shortcut-edit"
                  title="Edit"
                  onClick={() => {
                    const v = prompt(`Новая комбинация для «${action}»:\nПример: ⌘ K  или  G then B`, keys);
                    if (v !== null && v.trim()) set(action, v.trim());
                  }}
                >✎</button>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function SecCpp({ s, set }) {
  return (
    <div className="set-grid">
      <div className="set-row2">
        <SegmentedRadio
          label="Компилятор" value={s.defaultCompiler} onChange={(v) => set("defaultCompiler", v)}
          options={["gcc-13", "clang-17", "clang-18"]}
        />
        <SegmentedRadio
          label="Стандарт C++" value={s.defaultStandard} onChange={(v) => set("defaultStandard", v)}
          options={["C++17", "C++20", "C++23"]}
        />
      </div>
      <div className="set-row2">
        <SegmentedRadio
          label="Sanitizer по умолчанию" value={s.defaultSanitizer} onChange={(v) => set("defaultSanitizer", v)}
          options={[{value:"none", label:"None"}, {value:"asan", label:"ASan"}, {value:"tsan", label:"TSan"}, {value:"ubsan", label:"UBSan"}]}
        />
        <SegmentedRadio
          label="Build type" value={s.defaultBuildType} onChange={(v) => set("defaultBuildType", v)}
          options={["Debug", "RelWithDebInfo", "Release"]}
        />
      </div>
      <TextField label="Bazel args" mono value={s.bazelArgs} onChange={(v) => set("bazelArgs", v)}
        placeholder="--jobs=12 --keep_going" />
      <TextField label="Compiler Explorer URL" mono value={s.compilerExplorerUrl}
        onChange={(v) => set("compilerExplorerUrl", v)} placeholder="https://godbolt.org/" />
      <SwitchToggle label="Inline ASM preview в карточках"
        hint="Показывать компиляторный вывод прямо в task card (если есть godbolt link)"
        checked={s.showAsmInline} onChange={(v) => set("showAsmInline", v)} />
    </div>
  );
}

function IntegrationCard({ icon, name, color, desc, conn, children, onToggle }) {
  return (
    <div className={"integration" + (conn ? " on" : "")}>
      <div className="integration-head">
        <div className="integration-icon" style={{background: color}}>{icon}</div>
        <div style={{flex:1, minWidth: 0}}>
          <div className="integration-name">{name}</div>
          <div className="integration-desc">{desc}</div>
        </div>
        <div className={"integration-status" + (conn ? " on" : "")}>
          {conn ? "● connected" : "○ disconnected"}
        </div>
        <button className={"btn" + (conn ? "" : " primary")} onClick={onToggle}>
          {conn ? "Disconnect" : "Connect"}
        </button>
      </div>
      {conn && children && <div className="integration-body">{children}</div>}
    </div>
  );
}

function SecIntegrations({ s, set }) {
  return (
    <div className="set-grid">
      <IntegrationCard
        icon="J" name="Jira" color="oklch(0.6 0.18 240)"
        desc="Sync задач, ID prefix, статусов"
        conn={s.jira.connected} onToggle={() => set("jira", {...s.jira, connected: !s.jira.connected})}
      >
        <div className="set-row2">
          <TextField label="URL" mono value={s.jira.url} onChange={(v) => set("jira", {...s.jira, url: v})} />
          <TextField label="Project key" mono value={s.jira.project} onChange={(v) => set("jira", {...s.jira, project: v})} />
        </div>
      </IntegrationCard>

      <IntegrationCard
        icon="◯" name="GitHub" color="oklch(0.4 0.02 250)"
        desc="PR статус, branch template, code-review pings"
        conn={s.github.connected} onToggle={() => set("github", {...s.github, connected: !s.github.connected})}
      >
        <div className="set-row2">
          <TextField label="Organization" mono value={s.github.org} onChange={(v) => set("github", {...s.github, org: v})} />
          <TextField label="Branch template" mono value={s.github.branchTemplate}
            onChange={(v) => set("github", {...s.github, branchTemplate: v})}
            hint="{type}/{id}-{slug}" />
        </div>
      </IntegrationCard>

      <IntegrationCard
        icon="#" name="Slack" color="oklch(0.7 0.15 300)"
        desc="Notification routing, follow-ups"
        conn={s.slack.connected} onToggle={() => set("slack", {...s.slack, connected: !s.slack.connected})}
      >
        <div className="set-row2">
          <TextField label="Workspace" mono value={s.slack.workspace} onChange={(v) => set("slack", {...s.slack, workspace: v})} />
          <TextField label="On-call channel" mono value={s.slack.dmChannel} onChange={(v) => set("slack", {...s.slack, dmChannel: v})} />
        </div>
      </IntegrationCard>

      <IntegrationCard
        icon="!" name="PagerDuty" color="oklch(0.65 0.18 145)"
        desc="On-call schedule, incident escalation"
        conn={s.pagerduty.connected} onToggle={() => set("pagerduty", {...s.pagerduty, connected: !s.pagerduty.connected})}
      >
        <TextField label="Schedule ID" mono value={s.pagerduty.schedule}
          onChange={(v) => set("pagerduty", {...s.pagerduty, schedule: v})} placeholder="PXXXXXX" />
      </IntegrationCard>

      <IntegrationCard
        icon="§" name="Confluence" color="oklch(0.6 0.15 240)"
        desc="Wiki + runbooks, link previews"
        conn={s.confluence.connected} onToggle={() => set("confluence", {...s.confluence, connected: !s.confluence.connected})}
      >
        <TextField label="Space" mono value={s.confluence.space}
          onChange={(v) => set("confluence", {...s.confluence, space: v})} placeholder="LTE" />
      </IntegrationCard>
    </div>
  );
}

function SecData({ s, set, onExport, onImport, onReset }) {
  return (
    <div className="set-grid">
      <div className="set-sub">Резервные копии</div>
      <SwitchToggle label="Auto backup в localStorage"
        hint="Сохранять состояние задач/событий локально"
        checked={s.autoBackup} onChange={(v) => set("autoBackup", v)} />
      {s.autoBackup && (
        <SegmentedRadio
          label="Интервал" value={s.backupInterval} onChange={(v) => set("backupInterval", v)}
          options={[{value:"hourly", label:"Каждый час"}, {value:"daily", label:"Каждый день"}, {value:"weekly", label:"Раз в неделю"}]}
        />
      )}
      <div className="set-sub">Импорт / Экспорт</div>
      <div className="set-actions">
        <button className="btn" onClick={onExport}>↓ Export as JSON</button>
        <button className="btn" onClick={onImport}>↑ Import from JSON</button>
      </div>
      <div className="set-sub" style={{color:"var(--p0)", marginTop:"12px"}}>Опасная зона</div>
      <div className="set-danger">
        <div>
          <div style={{fontWeight: 500}}>Сбросить все настройки</div>
          <div className="set-field-hint">Откатить к значениям по умолчанию. Задачи останутся.</div>
        </div>
        <button className="btn danger-btn" onClick={onReset}>Reset all</button>
      </div>
    </div>
  );
}

function SecAbout() {
  return (
    <div className="set-grid">
      <div className="set-about-card">
        <div className="set-about-logo">
          <div className="set-about-dot" />
          <div>
            <div className="set-about-name mono">todo·cpp</div>
            <div className="set-about-tag">A C++ programmer's day, structured.</div>
          </div>
        </div>
        <div className="set-about-meta">
          <div><span className="set-about-key">Version</span><span className="mono">0.4.2 — build 240617</span></div>
          <div><span className="set-about-key">Channel</span><span className="mono">stable</span></div>
          <div><span className="set-about-key">Storage</span><span className="mono">localStorage</span></div>
          <div><span className="set-about-key">Engine</span><span className="mono">React 18.3 + Babel standalone</span></div>
        </div>
        <div className="set-about-links">
          <a href="#" onClick={(e) => e.preventDefault()}>Release notes</a>
          <a href="#" onClick={(e) => e.preventDefault()}>License</a>
          <a href="#" onClick={(e) => e.preventDefault()}>Report a bug</a>
          <a href="#" onClick={(e) => e.preventDefault()}>Keyboard shortcuts</a>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, {
  SecProfile, SecAppearance, SecNotifications, SecCalendar,
  SecTasks, SecShortcuts, SecCpp, SecIntegrations, SecData, SecAbout,
});
