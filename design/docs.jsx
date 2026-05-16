// Docs view — specs, wiki, references, snippets, contacts (editable)

const DOCS_DATA = {
  sections: [
    {
      id: "3gpp",
      title: "3GPP / ETSI Standards",
      subtitle: "External — LTE / E-UTRAN protocol specifications",
      accent: "var(--m-standup)",
      items: [
        { ref: "TS 36.331", title: "RRC Protocol Specification",
          desc: "Radio Resource Control — connection setup, reconfiguration, handover, measurements, SIB.",
          url: "https://www.etsi.org/deliver/etsi_ts/136300_136399/136331/",
          source: "ETSI", version: "v17.5.0" },
        { ref: "TS 36.323", title: "PDCP Specification",
          desc: "Packet Data Convergence Protocol — ciphering / integrity, ROHC, SN handling.",
          url: "https://www.etsi.org/deliver/etsi_ts/136300_136399/136323/",
          source: "ETSI", version: "v17.0.0" },
        { ref: "TS 36.322", title: "RLC Protocol Specification",
          desc: "Radio Link Control — AM / UM / TM modes, ARQ, segmentation, reassembly.",
          url: "https://www.etsi.org/deliver/etsi_ts/136300_136399/136322/",
          source: "ETSI", version: "v17.0.0" },
        { ref: "TS 36.321", title: "MAC Protocol Specification",
          desc: "Medium Access Control — HARQ, scheduling, BSR, PHR, RACH, DRX.",
          url: "https://www.etsi.org/deliver/etsi_ts/136300_136399/136321/",
          source: "ETSI", version: "v17.4.0" },
        { ref: "TS 36.211", title: "Physical Channels & Modulation",
          desc: "PHY — OFDM/SC-FDMA, reference signals, channel mapping, frame structure.",
          url: "https://www.etsi.org/deliver/etsi_ts/136200_136299/136211/",
          source: "ETSI", version: "v17.5.0" },
        { ref: "TS 36.213", title: "Physical Layer Procedures",
          desc: "PHY procedures — power control, CQI/PMI/RI, link adaptation, scheduling.",
          url: "https://www.etsi.org/deliver/etsi_ts/136200_136299/136213/",
          source: "ETSI", version: "v17.5.0" },
        { ref: "TS 36.413", title: "S1AP — S1 Application Protocol",
          desc: "eNB ↔ MME signalling — UE context, handover, paging, NAS transport.",
          url: "https://www.etsi.org/deliver/etsi_ts/136400_136499/136413/",
          source: "ETSI", version: "v17.5.0" },
        { ref: "TS 36.423", title: "X2AP — X2 Application Protocol",
          desc: "eNB ↔ eNB signalling — handover prep, load balancing, dual connectivity.",
          url: "https://www.etsi.org/deliver/etsi_ts/136400_136499/136423/",
          source: "ETSI", version: "v17.5.0" },
        { ref: "TS 24.301", title: "NAS — EPS Mobility / Session Mgmt",
          desc: "Non-Access Stratum — EMM (attach/detach), ESM (bearer mgmt), security.",
          url: "https://www.etsi.org/deliver/etsi_ts/124300_124399/124301/",
          source: "ETSI", version: "v17.7.0" },
        { ref: "TS 29.281", title: "GTPv1-U",
          desc: "GPRS Tunneling Protocol user plane — bearer encapsulation S1-U / X2-U.",
          url: "https://www.etsi.org/deliver/etsi_ts/129200_129299/129281/",
          source: "ETSI", version: "v17.0.0" },
      ]
    },
    {
      id: "internal",
      title: "Internal — eNB-core",
      subtitle: "Wiki, runbooks, coding standards, on-call",
      accent: "var(--m-oneone)",
      items: [
        { ref: "ARCH-001", title: "eNB-core Architecture Overview",
          desc: "Слой-диаграмма, thread model, message dispatch, IPC между PHY и L2/L3.",
          url: "#/wiki/lte-core/architecture", source: "wiki.internal", updated: "2 weeks ago" },
        { ref: "STYLE-CPP", title: "C++ Coding Standard (eNB-core)",
          desc: "RAII обязателен, smart ptr only, no exceptions в hot path, naming rules.",
          url: "#/wiki/lte-core/cpp-style", source: "wiki.internal", updated: "1 month ago" },
        { ref: "BUILD-101", title: "Build & CI Guide",
          desc: "Bazel targets, sanitizers, cross-compile ARM SoC, release pipeline.",
          url: "#/wiki/lte-core/build", source: "wiki.internal", updated: "3 days ago" },
        { ref: "RUN-001", title: "Runbook · UE Attach Failures",
          desc: "Cause codes по 24.301, NAS trace collection, S1AP correlation IDs.",
          url: "#/runbooks/attach-fail", source: "runbook", updated: "1 week ago" },
        { ref: "RUN-007", title: "Runbook · PDCP/RLC Drops",
          desc: "Buffer occupancy, SN gap analysis, retx counters, perf knobs.",
          url: "#/runbooks/pdcp-rlc-drops", source: "runbook", updated: "5 days ago" },
        { ref: "RUN-012", title: "Runbook · HARQ Stuck Detection",
          desc: "Когда NDI не флипается; шаги диагностики со стороны MAC scheduler.",
          url: "#/runbooks/harq-stuck", source: "runbook", updated: "yesterday" },
        { ref: "OPS-CALL", title: "On-call Rotation & Escalation",
          desc: "PagerDuty, severity levels, customer-impact decision matrix.",
          url: "#/wiki/oncall", source: "wiki.internal", updated: "today" },
        { ref: "REL-24.06.2", title: "Release Notes · 24.06.2",
          desc: "Latest internal cut — HARQ retx fix, GTP-U SIMD, S1AP timeout.",
          url: "#/releases/24.06.2", source: "release", updated: "today" },
        { ref: "TPL-PR", title: "PR Template & Review Checklist",
          desc: "Что должно быть в PR description: spec ref, перф, тесты, riscs.",
          url: "#/wiki/pr-template", source: "wiki.internal", updated: "2 months ago" },
      ]
    },
    {
      id: "cpp",
      title: "C++ Reference",
      subtitle: "Language, ABI, modern best practices",
      accent: "var(--m-sync)",
      items: [
        { ref: "cppreference", title: "C++ Reference",
          desc: "Полный справочник по языку и stdlib. Главный daily-driver.",
          url: "https://en.cppreference.com/", source: "cppreference.com" },
        { ref: "ISO C++20", title: "ISO/IEC 14882:2020",
          desc: "Официальный стандарт C++20 — concepts, ranges, coroutines, modules.",
          url: "https://www.iso.org/standard/79358.html", source: "iso.org" },
        { ref: "Itanium ABI", title: "Itanium C++ ABI",
          desc: "Стандартный ABI для GCC / Clang — name mangling, vtables, RTTI.",
          url: "https://itanium-cxx-abi.github.io/cxx-abi/", source: "itanium-cxx-abi" },
        { ref: "Core G.", title: "C++ Core Guidelines",
          desc: "Bjarne & Herb — modern C++ best practices, GSL.",
          url: "https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines",
          source: "isocpp.github.io" },
        { ref: "Godbolt", title: "Compiler Explorer",
          desc: "Интерактивный ASM viewer — GCC, Clang, MSVC, ICC, multiple archs.",
          url: "https://godbolt.org/", source: "godbolt.org" },
        { ref: "Quick C++", title: "Quick C++ Benchmarks",
          desc: "Микро-бенчмарки на Google Benchmark прямо в браузере.",
          url: "https://quick-bench.com/", source: "quick-bench" },
      ]
    },
    {
      id: "tools",
      title: "Tools & Debug",
      subtitle: "Профилирование, packet analysis, sanitizers",
      accent: "var(--m-focus)",
      items: [
        { ref: "Wireshark", title: "Wireshark — LTE dissectors",
          desc: "S1AP, X2AP, NAS, RRC dissectors. mac-lte / rlc-lte / pdcp-lte protos.",
          url: "https://www.wireshark.org/docs/dfref/", source: "wireshark.org" },
        { ref: "GDB", title: "GDB Documentation",
          desc: "Threading, watchpoints, conditional breakpoints, pretty-printers.",
          url: "https://sourceware.org/gdb/current/onlinedocs/gdb.html/", source: "sourceware" },
        { ref: "perf", title: "Linux perf",
          desc: "Sampling profiler, hardware counters, FlameGraph workflow.",
          url: "https://perf.wiki.kernel.org/index.php/Main_Page", source: "kernel.org" },
        { ref: "ASan", title: "AddressSanitizer",
          desc: "Memory bugs в runtime — out-of-bounds, UAF. -fsanitize=address.",
          url: "https://clang.llvm.org/docs/AddressSanitizer.html", source: "clang.llvm" },
        { ref: "TSan", title: "ThreadSanitizer",
          desc: "Гонки данных — must-have для multi-threaded eNB hot path.",
          url: "https://clang.llvm.org/docs/ThreadSanitizer.html", source: "clang.llvm" },
        { ref: "valgrind", title: "Valgrind",
          desc: "Memcheck, helgrind, callgrind. Дорогой но точный.",
          url: "https://valgrind.org/docs/manual/manual.html", source: "valgrind.org" },
      ]
    },
  ],
  snippets: [
    { title: "Build с sanitizers", lang: "sh",
      code: "# AddressSanitizer\nbazel build --config=asan //enb/core/...\n\n# ThreadSanitizer (для гонок)\nbazel build --config=tsan //enb/core/...\n\n# UBSan + ASan combo\nbazel build --config=asan-ubsan //enb/core/..." },
    { title: "GDB · attach к running eNB", lang: "sh",
      code: "sudo gdb -p $(pgrep -f enb-core)\n(gdb) info threads\n(gdb) thread apply all bt 30\n(gdb) bt full\n(gdb) p *self  # пример pretty-print" },
    { title: "PCAP capture per-cell", lang: "sh",
      code: "# S1AP (port 36412) + X2AP (36422) к указанному MME\ntcpdump -i any -w /tmp/lte-cell-3.pcap \\\n  'host 10.0.0.5 and (port 36412 or port 36422)'\n\n# C-plane + U-plane всё разом\ntcpdump -i any -w /tmp/full.pcap \\\n  'port 36412 or port 36422 or port 2152'" },
    { title: "S1AP cause codes (36.413 §9.2.1.3)", lang: "cpp",
      code: "enum class S1apCause : uint8_t {\n  RadioNetwork_Unspecified = 0,\n  Transport_Unspecified    = 1,\n  NAS_Unspecified          = 2,\n  Protocol_Unspecified     = 3,\n  Misc_Unspecified         = 4,\n};\n\n// Для UE Context Release Request (§9.1.4.5)\nconstexpr auto kUeCtxRelTimeout =\n  std::chrono::seconds{10};" },
    { title: "Logging hot-path safe", lang: "cpp",
      code: "// В hot path — только структурированный bin-log,\n// никаких fmt::format / std::ostream.\nLOG_BIN(kHarqRetx, ueId, harqId, ndi, rv);\n\n// Slow-path (ошибки, init) — обычный log OK\nLOG_WARN(\"PDCP SN wrap on bearer {}\", drbId);" },
  ],
  contacts: [
    { name: "Олег Т.",    role: "Tech Lead",        channel: "#lte-core-leads", mattermost: "@oleg.t",     color: "oklch(0.72 0.12 25)" },
    { name: "Andrey S.",  role: "Senior C++",       channel: "#lte-core",       mattermost: "@andrey.s",   color: "oklch(0.74 0.12 175)" },
    { name: "Hiroshi M.", role: "PHY team",         channel: "#lte-phy",        mattermost: "@hiroshi.m",  color: "oklch(0.74 0.12 145)" },
    { name: "Маша К.",    role: "QA Lead",          channel: "#lte-qa",         mattermost: "@masha.k",    color: "oklch(0.72 0.12 305)" },
    { name: "Виктор Л.",  role: "Architect",        channel: "#lte-arch",       mattermost: "@viktor.l",   color: "oklch(0.74 0.12 235)" },
    { name: "On-call",    role: "PagerDuty rotation", channel: "#enb-oncall",   mattermost: "page: lte-oncall", color: "var(--p0)" },
  ],
};

const CONTACT_COLORS = [
  "oklch(0.72 0.12 25)", "oklch(0.74 0.12 60)", "oklch(0.78 0.12 100)",
  "oklch(0.74 0.12 145)", "oklch(0.74 0.12 175)", "oklch(0.74 0.12 205)",
  "oklch(0.74 0.12 235)", "oklch(0.72 0.12 270)", "oklch(0.72 0.12 305)",
];

function docsCopyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    return navigator.clipboard.writeText(text);
  }
  const ta = document.createElement("textarea");
  ta.value = text;
  ta.style.position = "fixed";
  ta.style.left = "-9999px";
  document.body.appendChild(ta);
  ta.select();
  try { document.execCommand("copy"); } catch (e) {}
  document.body.removeChild(ta);
  return Promise.resolve();
}

function docsInitials(name) {
  return name.split(/\s+/).map(w => w[0]).slice(0,2).join("").toUpperCase();
}

// === Edit modal ===
function DocsEditModal({ editing, onClose, onSave, onDelete, sections }) {
  const [draft, setDraft] = React.useState(editing.item);
  React.useEffect(() => setDraft(editing.item), [editing]);
  const update = (k, v) => setDraft({ ...draft, [k]: v });

  const kind = editing.kind; // "doc" | "snippet" | "contact"
  const isNew = editing.isNew;

  const titleByKind = {
    doc:     isNew ? "Новая запись"      : "Редактировать запись",
    snippet: isNew ? "Новый snippet"     : "Редактировать snippet",
    contact: isNew ? "Новый контакт"     : "Редактировать контакт",
  };

  const handleSave = () => {
    if (kind === "doc" && !draft.title?.trim()) return;
    if (kind === "snippet" && !draft.title?.trim()) return;
    if (kind === "contact" && !draft.name?.trim()) return;
    onSave(draft);
  };

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()} style={{width: kind === "snippet" ? "640px" : "480px"}}>
        <h2>
          {titleByKind[kind]}
          {!isNew && draft.ref && <span className="id">{draft.ref}</span>}
        </h2>

        {kind === "doc" && (
          <>
            <div className="row2">
              <label>
                Ref / Code
                <input className="mono" value={draft.ref || ""} onChange={(e) => update("ref", e.target.value)} placeholder="TS 36.331" />
              </label>
              <label>
                Version
                <input className="mono" value={draft.version || ""} onChange={(e) => update("version", e.target.value)} placeholder="v17.5.0" />
              </label>
            </div>
            <label>
              Title
              <input value={draft.title || ""} onChange={(e) => update("title", e.target.value)} autoFocus />
            </label>
            <label>
              Description
              <textarea rows={3} value={draft.desc || ""} onChange={(e) => update("desc", e.target.value)} />
            </label>
            <label>
              URL
              <input className="mono" value={draft.url || ""} onChange={(e) => update("url", e.target.value)} placeholder="https://… или #/wiki/…" />
            </label>
            <div className="row2">
              <label>
                Source
                <input value={draft.source || ""} onChange={(e) => update("source", e.target.value)} placeholder="ETSI, wiki.internal…" />
              </label>
              <label>
                Updated
                <input value={draft.updated || ""} onChange={(e) => update("updated", e.target.value)} placeholder="today, 2 weeks ago…" />
              </label>
            </div>
            {isNew && (
              <label>
                Section
                <select value={draft._sectionId || editing.sectionId} onChange={(e) => update("_sectionId", e.target.value)}>
                  {sections.map(s => <option key={s.id} value={s.id}>{s.title}</option>)}
                </select>
              </label>
            )}
          </>
        )}

        {kind === "snippet" && (
          <>
            <div className="row2">
              <label>
                Title
                <input value={draft.title || ""} onChange={(e) => update("title", e.target.value)} autoFocus />
              </label>
              <label>
                Language
                <select value={draft.lang || "sh"} onChange={(e) => update("lang", e.target.value)}>
                  <option value="sh">sh</option>
                  <option value="cpp">cpp</option>
                  <option value="py">py</option>
                  <option value="js">js</option>
                  <option value="yaml">yaml</option>
                  <option value="text">text</option>
                </select>
              </label>
            </div>
            <label>
              Code
              <textarea
                className="mono"
                rows={10}
                style={{fontSize:"12px", lineHeight: 1.5}}
                value={draft.code || ""}
                onChange={(e) => update("code", e.target.value)}
                placeholder="// your snippet…"
              />
            </label>
          </>
        )}

        {kind === "contact" && (
          <>
            <div className="row2">
              <label>
                Name
                <input value={draft.name || ""} onChange={(e) => update("name", e.target.value)} autoFocus />
              </label>
              <label>
                Role
                <input value={draft.role || ""} onChange={(e) => update("role", e.target.value)} />
              </label>
            </div>
            <div className="row2">
              <label>
                Slack channel
                <input className="mono" value={draft.channel || ""} onChange={(e) => update("channel", e.target.value)} placeholder="#lte-core" />
              </label>
              <label>
                Slack handle
                <input className="mono" value={draft.mattermost || ""} onChange={(e) => update("slack", e.target.value)} placeholder="@name.surname" />
              </label>
            </div>
            <label>
              Avatar color
              <div style={{display:"flex", gap:"6px", flexWrap:"wrap", marginTop:"4px"}}>
                {CONTACT_COLORS.map(c => (
                  <button
                    key={c}
                    type="button"
                    onClick={() => update("color", c)}
                    style={{
                      width: 24, height: 24, borderRadius: 12, background: c, border: "2px solid",
                      borderColor: (draft.color === c ? "var(--text)" : "var(--border)"),
                      cursor: "pointer", padding: 0,
                    }}
                    aria-label="Pick color"
                  />
                ))}
              </div>
            </label>
          </>
        )}

        <div className="actions">
          {!isNew && <button className="btn danger" onClick={() => onDelete()}>Удалить</button>}
          <button className="btn" onClick={onClose}>Отмена</button>
          <button className="btn primary" onClick={handleSave}>{isNew ? "Создать" : "Сохранить"}</button>
        </div>
      </div>
    </div>
  );
}

function DocsView() {
  const [sections, setSections] = React.useState(() => DOCS_DATA.sections.map(s => ({...s, items: [...s.items]})));
  const [snippets, setSnippets] = React.useState(() => [...DOCS_DATA.snippets]);
  const [contacts, setContacts] = React.useState(() => [...DOCS_DATA.contacts]);
  const [q, setQ] = React.useState("");
  const [toast, setToast] = React.useState(null);
  const [activeSection, setActiveSection] = React.useState("3gpp");
  const [editMode, setEditMode] = React.useState(false);
  const [editing, setEditing] = React.useState(null);
  const bodyRef = React.useRef(null);

  const showToast = (msg) => {
    setToast(msg);
    clearTimeout(showToast._t);
    showToast._t = setTimeout(() => setToast(null), 1600);
  };

  const matches = (item) => {
    if (!q) return true;
    const s = (item.ref + " " + item.title + " " + (item.desc||"") + " " + (item.source||"")).toLowerCase();
    return s.includes(q.toLowerCase());
  };

  const jumpTo = (id) => {
    const el = document.getElementById("docs-" + id);
    if (el && bodyRef.current) {
      const top = el.offsetTop - 8;
      bodyRef.current.scrollTo({ top, behavior: "smooth" });
      setActiveSection(id);
    }
  };

  // === Doc ops ===
  const openDocEdit = (sectionId, item) => {
    setEditing({ kind: "doc", sectionId, item, isNew: false, originalRef: item.ref });
  };
  const openDocCreate = (sectionId) => {
    setEditing({
      kind: "doc",
      sectionId,
      item: { ref: "", title: "", desc: "", url: "", source: "", version: "", updated: "", _sectionId: sectionId },
      isNew: true,
    });
  };
  const saveDoc = (draft) => {
    const targetSectionId = draft._sectionId || editing.sectionId;
    const { _sectionId, ...cleaned } = draft;
    if (editing.isNew) {
      setSections(prev => prev.map(s => s.id === targetSectionId ? { ...s, items: [...s.items, cleaned] } : s));
      showToast(`Создано: ${cleaned.ref || cleaned.title}`);
    } else {
      setSections(prev => prev.map(s => {
        if (s.id === editing.sectionId) {
          if (targetSectionId === s.id) {
            return { ...s, items: s.items.map(i => i.ref === editing.originalRef ? cleaned : i) };
          } else {
            return { ...s, items: s.items.filter(i => i.ref !== editing.originalRef) };
          }
        }
        if (s.id === targetSectionId && targetSectionId !== editing.sectionId) {
          return { ...s, items: [...s.items, cleaned] };
        }
        return s;
      }));
      showToast(`Сохранено: ${cleaned.ref || cleaned.title}`);
    }
    setEditing(null);
  };
  const deleteDoc = () => {
    setSections(prev => prev.map(s =>
      s.id === editing.sectionId ? { ...s, items: s.items.filter(i => i.ref !== editing.originalRef) } : s
    ));
    showToast(`Удалено: ${editing.originalRef}`);
    setEditing(null);
  };

  // === Snippet ops ===
  const openSnippetEdit = (idx) => {
    setEditing({ kind: "snippet", item: { ...snippets[idx] }, isNew: false, idx });
  };
  const openSnippetCreate = () => {
    setEditing({
      kind: "snippet",
      item: { title: "", lang: "sh", code: "" },
      isNew: true,
    });
  };
  const saveSnippet = (draft) => {
    if (editing.isNew) {
      setSnippets(prev => [...prev, draft]);
      showToast(`Snippet создан: ${draft.title}`);
    } else {
      setSnippets(prev => prev.map((s, i) => i === editing.idx ? draft : s));
      showToast(`Snippet сохранён: ${draft.title}`);
    }
    setEditing(null);
  };
  const deleteSnippet = () => {
    setSnippets(prev => prev.filter((_, i) => i !== editing.idx));
    showToast(`Snippet удалён`);
    setEditing(null);
  };

  // === Contact ops ===
  const openContactEdit = (idx) => {
    setEditing({ kind: "contact", item: { ...contacts[idx] }, isNew: false, idx });
  };
  const openContactCreate = () => {
    setEditing({
      kind: "contact",
      item: { name: "", role: "", channel: "", mattermost: "", color: CONTACT_COLORS[0] },
      isNew: true,
    });
  };
  const saveContact = (draft) => {
    if (editing.isNew) {
      setContacts(prev => [...prev, draft]);
      showToast(`Контакт добавлен: ${draft.name}`);
    } else {
      setContacts(prev => prev.map((c, i) => i === editing.idx ? draft : c));
      showToast(`Контакт сохранён: ${draft.name}`);
    }
    setEditing(null);
  };
  const deleteContact = () => {
    setContacts(prev => prev.filter((_, i) => i !== editing.idx));
    showToast(`Контакт удалён`);
    setEditing(null);
  };

  const handleSaveModal = (draft) => {
    if (!editing) return;
    if (editing.kind === "doc") saveDoc(draft);
    else if (editing.kind === "snippet") saveSnippet(draft);
    else if (editing.kind === "contact") saveContact(draft);
  };
  const handleDeleteModal = () => {
    if (!editing) return;
    if (editing.kind === "doc") deleteDoc();
    else if (editing.kind === "snippet") deleteSnippet();
    else if (editing.kind === "contact") deleteContact();
  };

  const totalDocs = sections.reduce((n, s) => n + s.items.length, 0);

  return (
    <div className={"docs" + (editMode ? " edit-mode" : "")}>
      <div className="docs-head">
        <div>
          <div className="docs-h-title">Docs · spec &amp; references</div>
          <div className="docs-h-sub mono">
            {totalDocs} entries · {snippets.length} snippets · {contacts.length} contacts
            {editMode && <span style={{color:"var(--accent-strong)", marginLeft:"10px"}}>· EDITING</span>}
          </div>
        </div>
        <div className="docs-search">
          <span style={{color:"var(--text-dim)", fontSize:"11px"}}>⌕</span>
          <input
            placeholder="Поиск: 36.331, RRC, asan, valgrind…"
            value={q}
            onChange={(e) => setQ(e.target.value)}
          />
          {q && <button className="docs-clear" onClick={() => setQ("")}>×</button>}
        </div>
        <button
          className={"btn docs-edit-toggle" + (editMode ? " active" : "")}
          onClick={() => setEditMode(!editMode)}
          title={editMode ? "Готово" : "Включить редактирование"}
        >
          {editMode ? "✓ Готово" : "✎ Редактировать"}
        </button>
      </div>

      <div className="docs-layout">
        <nav className="docs-nav">
          {sections.map(s => (
            <button
              key={s.id}
              className={"docs-nav-link" + (activeSection === s.id ? " active" : "")}
              onClick={() => jumpTo(s.id)}
            >
              <span className="docs-nav-bar" style={{background: s.accent}} />
              <span>{s.title}</span>
              <span className="docs-nav-cnt mono">{s.items.length}</span>
            </button>
          ))}
          <div className="docs-nav-sep" />
          <button
            className={"docs-nav-link" + (activeSection === "snippets" ? " active" : "")}
            onClick={() => jumpTo("snippets")}
          >
            <span className="docs-nav-bar" style={{background:"var(--accent)"}} />
            <span>Snippets</span>
            <span className="docs-nav-cnt mono">{snippets.length}</span>
          </button>
          <button
            className={"docs-nav-link" + (activeSection === "contacts" ? " active" : "")}
            onClick={() => jumpTo("contacts")}
          >
            <span className="docs-nav-bar" style={{background:"var(--text-muted)"}} />
            <span>Contacts</span>
            <span className="docs-nav-cnt mono">{contacts.length}</span>
          </button>
        </nav>

        <div className="docs-body" ref={bodyRef}>
          {sections.map(s => {
            const items = s.items.filter(matches);
            if (q && items.length === 0) return null;
            return (
              <section key={s.id} id={"docs-" + s.id} className="docs-section">
                <div className="docs-section-head">
                  <span className="docs-section-bar" style={{background: s.accent}} />
                  <div>
                    <h2>{s.title}</h2>
                    <div className="docs-section-sub">{s.subtitle}</div>
                  </div>
                  <div className="docs-section-cnt mono">{items.length} / {s.items.length}</div>
                  {editMode && (
                    <button
                      className="docs-add-btn"
                      onClick={() => openDocCreate(s.id)}
                    >+ Add</button>
                  )}
                </div>
                <div className="docs-grid">
                  {items.map(it => {
                    const isInternal = (it.url || "").startsWith("#");
                    const cardProps = editMode
                      ? {
                          as: "div",
                          onClick: () => openDocEdit(s.id, it),
                        }
                      : {
                          href: it.url,
                          target: isInternal ? "_self" : "_blank",
                          rel: "noopener noreferrer",
                          onClick: (e) => {
                            if (isInternal) {
                              e.preventDefault();
                              showToast(`Open in wiki: ${it.url.slice(1)}`);
                            }
                          },
                        };
                    const Tag = editMode ? "div" : "a";
                    return (
                      <Tag
                        key={it.ref}
                        className={"doc-card" + (isInternal ? " internal" : "")}
                        {...(editMode ? {onClick: () => openDocEdit(s.id, it)} : {
                          href: it.url,
                          target: isInternal ? "_self" : "_blank",
                          rel: "noopener noreferrer",
                          onClick: (e) => {
                            if (isInternal) {
                              e.preventDefault();
                              showToast(`Open in wiki: ${it.url.slice(1)}`);
                            }
                          },
                        })}
                      >
                        {editMode && (
                          <div className="doc-card-actions">
                            <button
                              className="doc-action-btn"
                              title="Edit"
                              onClick={(e) => { e.stopPropagation(); openDocEdit(s.id, it); }}
                            >✎</button>
                            <button
                              className="doc-action-btn danger"
                              title="Delete"
                              onClick={(e) => {
                                e.stopPropagation();
                                if (confirm(`Удалить «${it.ref}»?`)) {
                                  setSections(prev => prev.map(sec =>
                                    sec.id === s.id ? { ...sec, items: sec.items.filter(i => i.ref !== it.ref) } : sec
                                  ));
                                  showToast(`Удалено: ${it.ref}`);
                                }
                              }}
                            >×</button>
                          </div>
                        )}
                        <div className="doc-card-top">
                          <span className="doc-ref mono" style={{borderColor: s.accent, color: s.accent}}>{it.ref}</span>
                          <span className="doc-card-flex" />
                          {it.version && <span className="doc-version mono">{it.version}</span>}
                          {!editMode && <span className="doc-ext">{isInternal ? "→" : "↗"}</span>}
                        </div>
                        <div className="doc-title">{it.title}</div>
                        <div className="doc-desc">{it.desc}</div>
                        <div className="doc-foot mono">
                          <span>{it.source}</span>
                          {it.updated && <span style={{color:"var(--text-dim)"}}>upd {it.updated}</span>}
                        </div>
                      </Tag>
                    );
                  })}
                  {editMode && (
                    <button
                      className="doc-card add-card"
                      onClick={() => openDocCreate(s.id)}
                    >
                      <div className="add-card-plus">+</div>
                      <div className="add-card-label">Add entry</div>
                    </button>
                  )}
                </div>
              </section>
            );
          })}

          <section id="docs-snippets" className="docs-section">
            <div className="docs-section-head">
              <span className="docs-section-bar" style={{background:"var(--accent)"}} />
              <div>
                <h2>Snippets</h2>
                <div className="docs-section-sub">Часто используемые команды и шаблоны кода</div>
              </div>
              <div className="docs-section-cnt mono">{snippets.length}</div>
              {editMode && (
                <button className="docs-add-btn" onClick={openSnippetCreate}>+ Add</button>
              )}
            </div>
            <div className="docs-snippets">
              {snippets.map((sn, i) => (
                <div key={i} className="snippet">
                  <div className="snippet-head">
                    <span className="snippet-title">{sn.title}</span>
                    <span className="snippet-lang mono">{sn.lang}</span>
                    {editMode ? (
                      <>
                        <button
                          className="snippet-copy"
                          onClick={() => openSnippetEdit(i)}
                        >✎ edit</button>
                        <button
                          className="snippet-copy danger"
                          onClick={() => {
                            if (confirm(`Удалить snippet «${sn.title}»?`)) {
                              setSnippets(prev => prev.filter((_, j) => j !== i));
                              showToast(`Snippet удалён`);
                            }
                          }}
                        >× del</button>
                      </>
                    ) : (
                      <button
                        className="snippet-copy"
                        onClick={(e) => { e.stopPropagation(); docsCopyText(sn.code); showToast(`Скопировано: ${sn.title}`); }}
                      >copy</button>
                    )}
                  </div>
                  <pre className="snippet-code mono">{sn.code}</pre>
                </div>
              ))}
              {editMode && (
                <button className="snippet add-card" onClick={openSnippetCreate}>
                  <div className="add-card-plus">+</div>
                  <div className="add-card-label">Add snippet</div>
                </button>
              )}
            </div>
          </section>

          <section id="docs-contacts" className="docs-section">
            <div className="docs-section-head">
              <span className="docs-section-bar" style={{background:"var(--text-muted)"}} />
              <div>
                <h2>Contacts &amp; Channels</h2>
                <div className="docs-section-sub">Кому пинговать в MM и где обсуждать</div>
              </div>
              <div className="docs-section-cnt mono">{contacts.length}</div>
              {editMode && (
                <button className="docs-add-btn" onClick={openContactCreate}>+ Add</button>
              )}
            </div>
            <div className="docs-contacts">
              {contacts.map((c, i) => (
                <div
                  key={i}
                  className="doc-contact"
                  style={editMode ? {cursor: "pointer"} : null}
                  onClick={editMode ? () => openContactEdit(i) : null}
                >
                  <div className="dc-avatar" style={{background: c.color}}>{docsInitials(c.name)}</div>
                  <div className="dc-info">
                    <div className="dc-name">{c.name}</div>
                    <div className="dc-role">{c.role}</div>
                  </div>
                  {editMode ? (
                    <div className="doc-card-actions" style={{position:"static"}}>
                      <button
                        className="doc-action-btn"
                        title="Edit"
                        onClick={(e) => { e.stopPropagation(); openContactEdit(i); }}
                      >✎</button>
                      <button
                        className="doc-action-btn danger"
                        title="Delete"
                        onClick={(e) => {
                          e.stopPropagation();
                          if (confirm(`Удалить контакт «${c.name}»?`)) {
                            setContacts(prev => prev.filter((_, j) => j !== i));
                            showToast(`Контакт удалён`);
                          }
                        }}
                      >×</button>
                    </div>
                  ) : (
                    <div className="dc-chans mono">
                      <div className="dc-channel">{c.channel}</div>
                      <div className="dc-slack">{c.mattermost}</div>
                    </div>
                  )}
                </div>
              ))}
              {editMode && (
                <button className="doc-contact add-card" onClick={openContactCreate}>
                  <div className="add-card-plus">+</div>
                  <div className="add-card-label">Add contact</div>
                </button>
              )}
            </div>
          </section>
        </div>
      </div>

      {editing && (
        <DocsEditModal
          editing={editing}
          sections={sections}
          onClose={() => setEditing(null)}
          onSave={handleSaveModal}
          onDelete={handleDeleteModal}
        />
      )}
      {toast && <div className="toast">{toast}</div>}
    </div>
  );
}

Object.assign(window, { DocsView });
