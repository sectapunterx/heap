// Docs view — spec / wiki / refs / snippets / contacts (editable)
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Controls as QQC
import TodoCpp

Item {
    id: root

    property string searchText: ""

    // ── Data ─────────────────────────────────────────────────────────────────

    property var sections: [
        {
            id: "3gpp",
            title: "3GPP / ETSI Standards",
            subtitle: "External — LTE / E-UTRAN protocol specifications",
            accent: Theme.mStandup,
            customFields: [],
            items: [
                { ref: "TS 36.331", title: "RRC Protocol Specification",
                  desc: "Radio Resource Control — connection setup, reconfiguration, handover, measurements, SIB.",
                  url: "https://www.etsi.org/deliver/etsi_ts/136300_136399/136331/", source: "ETSI", version: "v17.5.0", updated: "" },
                { ref: "TS 36.323", title: "PDCP Specification",
                  desc: "Packet Data Convergence Protocol — ciphering / integrity, ROHC, SN handling.",
                  url: "https://www.etsi.org/deliver/etsi_ts/136300_136399/136323/", source: "ETSI", version: "v17.0.0", updated: "" },
                { ref: "TS 36.322", title: "RLC Protocol Specification",
                  desc: "Radio Link Control — AM / UM / TM modes, ARQ, segmentation, reassembly.",
                  url: "https://www.etsi.org/deliver/etsi_ts/136300_136399/136322/", source: "ETSI", version: "v17.0.0", updated: "" },
                { ref: "TS 36.321", title: "MAC Protocol Specification",
                  desc: "Medium Access Control — HARQ, scheduling, BSR, PHR, RACH, DRX.",
                  url: "https://www.etsi.org/deliver/etsi_ts/136300_136399/136321/", source: "ETSI", version: "v17.4.0", updated: "" },
                { ref: "TS 36.211", title: "Physical Channels & Modulation",
                  desc: "PHY — OFDM/SC-FDMA, reference signals, channel mapping, frame structure.",
                  url: "https://www.etsi.org/deliver/etsi_ts/136200_136299/136211/", source: "ETSI", version: "v17.5.0", updated: "" },
                { ref: "TS 36.213", title: "Physical Layer Procedures",
                  desc: "PHY procedures — power control, CQI/PMI/RI, link adaptation, scheduling.",
                  url: "https://www.etsi.org/deliver/etsi_ts/136200_136299/136213/", source: "ETSI", version: "v17.5.0", updated: "" },
                { ref: "TS 36.413", title: "S1AP — S1 Application Protocol",
                  desc: "eNB ↔ MME signalling — UE context, handover, paging, NAS transport.",
                  url: "https://www.etsi.org/deliver/etsi_ts/136400_136499/136413/", source: "ETSI", version: "v17.5.0", updated: "" },
                { ref: "TS 36.423", title: "X2AP — X2 Application Protocol",
                  desc: "eNB ↔ eNB signalling — handover prep, load balancing, dual connectivity.",
                  url: "https://www.etsi.org/deliver/etsi_ts/136400_136499/136423/", source: "ETSI", version: "v17.5.0", updated: "" },
                { ref: "TS 24.301", title: "NAS — EPS Mobility / Session Mgmt",
                  desc: "Non-Access Stratum — EMM (attach/detach), ESM (bearer mgmt), security.",
                  url: "https://www.etsi.org/deliver/etsi_ts/124300_124399/124301/", source: "ETSI", version: "v17.7.0", updated: "" },
                { ref: "TS 29.281", title: "GTPv1-U",
                  desc: "GPRS Tunneling Protocol user plane — bearer encapsulation S1-U / X2-U.",
                  url: "https://www.etsi.org/deliver/etsi_ts/129200_129299/129281/", source: "ETSI", version: "v17.0.0", updated: "" }
            ]
        },
        {
            id: "internal",
            title: "Internal — eNB-core",
            subtitle: "Wiki, runbooks, coding standards, on-call",
            accent: Theme.mOneone,
            customFields: [],
            items: [
                { ref: "ARCH-001", title: "eNB-core Architecture Overview",
                  desc: "Слой-диаграмма, thread model, message dispatch, IPC между PHY и L2/L3.",
                  url: "#/wiki/lte-core/architecture", source: "wiki.internal", version: "", updated: "2 weeks ago" },
                { ref: "STYLE-CPP", title: "C++ Coding Standard (eNB-core)",
                  desc: "RAII обязателен, smart ptr only, no exceptions в hot path, naming rules.",
                  url: "#/wiki/lte-core/cpp-style", source: "wiki.internal", version: "", updated: "1 month ago" },
                { ref: "BUILD-101", title: "Build & CI Guide",
                  desc: "Bazel targets, sanitizers, cross-compile ARM SoC, release pipeline.",
                  url: "#/wiki/lte-core/build", source: "wiki.internal", version: "", updated: "3 days ago" },
                { ref: "RUN-001", title: "Runbook · UE Attach Failures",
                  desc: "Cause codes по 24.301, NAS trace collection, S1AP correlation IDs.",
                  url: "#/runbooks/attach-fail", source: "runbook", version: "", updated: "1 week ago" },
                { ref: "RUN-007", title: "Runbook · PDCP/RLC Drops",
                  desc: "Buffer occupancy, SN gap analysis, retx counters, perf knobs.",
                  url: "#/runbooks/pdcp-rlc-drops", source: "runbook", version: "", updated: "5 days ago" },
                { ref: "RUN-012", title: "Runbook · HARQ Stuck Detection",
                  desc: "Когда NDI не флипается; шаги диагностики со стороны MAC scheduler.",
                  url: "#/runbooks/harq-stuck", source: "runbook", version: "", updated: "yesterday" },
                { ref: "OPS-CALL", title: "On-call Rotation & Escalation",
                  desc: "PagerDuty, severity levels, customer-impact decision matrix.",
                  url: "#/wiki/oncall", source: "wiki.internal", version: "", updated: "today" },
                { ref: "REL-24.06.2", title: "Release Notes · 24.06.2",
                  desc: "Latest internal cut — HARQ retx fix, GTP-U SIMD, S1AP timeout.",
                  url: "#/releases/24.06.2", source: "release", version: "", updated: "today" },
                { ref: "TPL-PR", title: "PR Template & Review Checklist",
                  desc: "Что должно быть в PR description: spec ref, перф, тесты, riscs.",
                  url: "#/wiki/pr-template", source: "wiki.internal", version: "", updated: "2 months ago" }
            ]
        },
        {
            id: "cpp",
            title: "C++ Reference",
            subtitle: "Language, ABI, modern best practices",
            accent: Theme.mSync,
            customFields: [],
            items: [
                { ref: "cppreference", title: "C++ Reference",
                  desc: "Полный справочник по языку и stdlib. Главный daily-driver.",
                  url: "https://en.cppreference.com/", source: "cppreference.com", version: "", updated: "" },
                { ref: "ISO C++20", title: "ISO/IEC 14882:2020",
                  desc: "Официальный стандарт C++20 — concepts, ranges, coroutines, modules.",
                  url: "https://www.iso.org/standard/79358.html", source: "iso.org", version: "", updated: "" },
                { ref: "Itanium ABI", title: "Itanium C++ ABI",
                  desc: "Стандартный ABI для GCC / Clang — name mangling, vtables, RTTI.",
                  url: "https://itanium-cxx-abi.github.io/cxx-abi/", source: "itanium-cxx-abi", version: "", updated: "" },
                { ref: "Core G.", title: "C++ Core Guidelines",
                  desc: "Bjarne & Herb — modern C++ best practices, GSL.",
                  url: "https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines", source: "isocpp.github.io", version: "", updated: "" },
                { ref: "Godbolt", title: "Compiler Explorer",
                  desc: "Интерактивный ASM viewer — GCC, Clang, MSVC, ICC, multiple archs.",
                  url: "https://godbolt.org/", source: "godbolt.org", version: "", updated: "" },
                { ref: "Quick C++", title: "Quick C++ Benchmarks",
                  desc: "Микро-бенчмарки на Google Benchmark прямо в браузере.",
                  url: "https://quick-bench.com/", source: "quick-bench", version: "", updated: "" }
            ]
        },
        {
            id: "tools",
            title: "Tools & Debug",
            subtitle: "Профилирование, packet analysis, sanitizers",
            accent: Theme.mFocus,
            customFields: [],
            items: [
                { ref: "Wireshark", title: "Wireshark — LTE dissectors",
                  desc: "S1AP, X2AP, NAS, RRC dissectors. mac-lte / rlc-lte / pdcp-lte protos.",
                  url: "https://www.wireshark.org/docs/dfref/", source: "wireshark.org", version: "", updated: "" },
                { ref: "GDB", title: "GDB Documentation",
                  desc: "Threading, watchpoints, conditional breakpoints, pretty-printers.",
                  url: "https://sourceware.org/gdb/current/onlinedocs/gdb.html/", source: "sourceware", version: "", updated: "" },
                { ref: "perf", title: "Linux perf",
                  desc: "Sampling profiler, hardware counters, FlameGraph workflow.",
                  url: "https://perf.wiki.kernel.org/index.php/Main_Page", source: "kernel.org", version: "", updated: "" },
                { ref: "ASan", title: "AddressSanitizer",
                  desc: "Memory bugs в runtime — out-of-bounds, UAF. -fsanitize=address.",
                  url: "https://clang.llvm.org/docs/AddressSanitizer.html", source: "clang.llvm", version: "", updated: "" },
                { ref: "TSan", title: "ThreadSanitizer",
                  desc: "Гонки данных — must-have для multi-threaded eNB hot path.",
                  url: "https://clang.llvm.org/docs/ThreadSanitizer.html", source: "clang.llvm", version: "", updated: "" },
                { ref: "valgrind", title: "Valgrind",
                  desc: "Memcheck, helgrind, callgrind. Дорогой но точный.",
                  url: "https://valgrind.org/docs/manual/manual.html", source: "valgrind.org", version: "", updated: "" }
            ]
        }
    ]

    property var snippets: [
        { title: "Build с sanitizers", lang: "sh",
          code: "# AddressSanitizer\nbazel build --config=asan //enb/core/...\n\n# ThreadSanitizer (для гонок)\nbazel build --config=tsan //enb/core/...\n\n# UBSan + ASan combo\nbazel build --config=asan-ubsan //enb/core/..." },
        { title: "GDB · attach к running eNB", lang: "sh",
          code: "sudo gdb -p $(pgrep -f enb-core)\n(gdb) info threads\n(gdb) thread apply all bt 30\n(gdb) bt full\n(gdb) p *self  # пример pretty-print" },
        { title: "PCAP capture per-cell", lang: "sh",
          code: "# S1AP (port 36412) + X2AP (36422) к указанному MME\ntcpdump -i any -w /tmp/lte-cell-3.pcap \\\n  'host 10.0.0.5 and (port 36412 or port 36422)'\n\n# C-plane + U-plane всё разом\ntcpdump -i any -w /tmp/full.pcap \\\n  'port 36412 or port 36422 or port 2152'" },
        { title: "S1AP cause codes (36.413 §9.2.1.3)", lang: "cpp",
          code: "enum class S1apCause : uint8_t {\n  RadioNetwork_Unspecified = 0,\n  Transport_Unspecified    = 1,\n  NAS_Unspecified          = 2,\n  Protocol_Unspecified     = 3,\n  Misc_Unspecified         = 4,\n};\n\n// Для UE Context Release Request (§9.1.4.5)\nconstexpr auto kUeCtxRelTimeout =\n  std::chrono::seconds{10};" },
        { title: "Logging hot-path safe", lang: "cpp",
          code: "// В hot path — только структурированный bin-log,\n// никаких fmt::format / std::ostream.\nLOG_BIN(kHarqRetx, ueId, harqId, ndi, rv);\n\n// Slow-path (ошибки, init) — обычный log OK\nLOG_WARN(\"PDCP SN wrap on bearer {}\", drbId);" }
    ]

    property var contacts: [
        { name: "Олег Т.",    role: "Tech Lead",          channel: "#lte-core-leads", mattermost: "@oleg.t",          color: "#d97a6c" },
        { name: "Andrey S.",  role: "Senior C++",         channel: "#lte-core",       mattermost: "@andrey.s",        color: "#6cc4b8" },
        { name: "Hiroshi M.", role: "PHY team",           channel: "#lte-phy",        mattermost: "@hiroshi.m",       color: "#7cc492" },
        { name: "Маша К.",    role: "QA Lead",            channel: "#lte-qa",         mattermost: "@masha.k",         color: "#c87fc7" },
        { name: "Виктор Л.",  role: "Architect",          channel: "#lte-arch",       mattermost: "@viktor.l",        color: "#7da8d9" },
        { name: "On-call",    role: "PagerDuty rotation", channel: "#enb-oncall",     mattermost: "page: lte-oncall", color: "#e6624c" }
    ]

    readonly property var contactPalette: [
        "#d97a6c", "#dcb86b", "#dcc06a", "#7cc492",
        "#6cc4b8", "#5cc2dd", "#7da8d9", "#a4a4d6", "#c87fc7"
    ]

    readonly property var accentPalette: [
        Theme.mStandup, Theme.mOneone, Theme.mSync, Theme.mFocus,
        Theme.accent, Theme.p0, Theme.p1, Theme.p2, Theme.p3, Theme.textMuted
    ]

    // ── Helpers ─────────────────────────────────────────────────────────────

    function totalDocs() {
        let n = 0;
        for (let i = 0; i < sections.length; i++) n += sections[i].items.length;
        return n;
    }
    function passesSearch(item) {
        const q = (root.searchText || "").toLowerCase().trim();
        if (q.length === 0) return true;
        const hay = ((item.ref || "") + " " + (item.title || "") + " " + (item.desc || "") + " " + (item.source || "")).toLowerCase();
        return hay.indexOf(q) >= 0;
    }
    function initials(name) {
        const parts = (name || "").split(/\s+/);
        return (parts[0] ? parts[0][0] : "") + (parts[1] ? parts[1][0] : "");
    }
    function showToast(s) { if (toast) toast.show(s) }
    function showUndoToast(s, fn) {
        if (toast) toast.showWithAction(s, "Отменить", 5, fn);
    }

    // ── Persistence — JSON round-tripped through AppController.docsState ───

    property bool _loadedOnce: false
    Component.onCompleted: {
        const raw = AppController.docsState || "";
        if (raw.length > 0) {
            try {
                const o = JSON.parse(raw);
                if (o.sections) sections = o.sections;
                if (o.snippets) snippets = o.snippets;
                if (o.contacts) contacts = o.contacts;
            } catch (e) { /* corrupt — ignore */ }
        }
        _loadedOnce = true;
    }
    function persist() {
        if (!_loadedOnce) return;
        AppController.docsState = JSON.stringify({ sections: sections, snippets: snippets, contacts: contacts });
    }
    onSectionsChanged: persist()
    onSnippetsChanged: persist()
    onContactsChanged: persist()

    // ── Undo ────────────────────────────────────────────────────────────────
    property var pendingUndo: null

    function undoLastDeletion() {
        if (!pendingUndo) return;
        const u = pendingUndo;
        if (u.kind === "doc") {
            _replaceSections(function (copy) {
                const s = copy.find(function (x) { return x.id === u.sectionId; });
                if (s) s.items.splice(u.itemIdx, 0, u.item);
            });
            showToast("Восстановлено: " + (u.item.ref || u.item.title));
        } else if (u.kind === "snippet") {
            const list = snippets.slice();
            list.splice(u.idx, 0, u.item);
            snippets = list;
            showToast("Восстановлено: " + u.item.title);
        } else if (u.kind === "contact") {
            const list = contacts.slice();
            list.splice(u.idx, 0, u.item);
            contacts = list;
            showToast("Восстановлено: " + u.item.name);
        } else if (u.kind === "section") {
            const list = sections.slice();
            list.splice(u.idx, 0, u.item);
            sections = list;
            showToast("Восстановлена секция: " + u.item.title);
        }
        pendingUndo = null;
    }

    // ── Section ops ─────────────────────────────────────────────────────────

    function _replaceSections(updater) {
        const copy = sections.map(function (s) {
            return Object.assign({}, s, { items: s.items.slice() });
        });
        updater(copy);
        sections = copy;
    }

    function _sortedItems(section) {
        const arr = (section.items || []).slice();
        const mode = section.sortBy || "manual";
        if (mode === "manual") return arr;
        const desc = !!section.sortDesc;
        const k = mode === "ref" ? "ref"
                : mode === "title" ? "title"
                : mode === "updated" ? "updated"
                : "";
        if (!k) return arr;
        arr.sort(function (a, b) {
            const va = String((a && a[k]) || "").toLowerCase();
            const vb = String((b && b[k]) || "").toLowerCase();
            if (va < vb) return desc ? 1 : -1;
            if (va > vb) return desc ? -1 : 1;
            return 0;
        });
        return arr;
    }

    function setSortBy(sectionId, sortBy, sortDesc) {
        _replaceSections(function (copy) {
            const s = copy.find(function (x) { return x.id === sectionId; });
            if (!s) return;
            s.sortBy = sortBy;
            s.sortDesc = !!sortDesc;
        });
    }

    function _reorderDoc(srcSectionId, srcRef, dstSectionId, dstRef, before) {
        _replaceSections(function (copy) {
            const src = copy.find(function (x) { return x.id === srcSectionId; });
            if (!src) return;
            const i = src.items.findIndex(function (it) { return it.ref === srcRef; });
            if (i < 0) return;
            const moved = src.items.splice(i, 1)[0];

            const dst = copy.find(function (x) { return x.id === dstSectionId; });
            if (!dst) { src.items.splice(i, 0, moved); return; }
            let j;
            if (dstRef === "" || dstRef === undefined) {
                j = dst.items.length;
            } else {
                j = dst.items.findIndex(function (it) { return it.ref === dstRef; });
                if (j < 0) j = dst.items.length;
                if (!before) j += 1;
            }
            dst.items.splice(j, 0, moved);
            dst.sortBy = "manual";
        });
    }

    function _reorderSection(srcId, dstId, before) {
        if (srcId === dstId) return;
        const copy = sections.slice();
        const i = copy.findIndex(function (s) { return s.id === srcId; });
        if (i < 0) return;
        const moved = copy.splice(i, 1)[0];
        let j = copy.findIndex(function (s) { return s.id === dstId; });
        if (j < 0) j = copy.length;
        if (!before) j += 1;
        copy.splice(j, 0, moved);
        sections = copy;
    }

    function _moveSectionByDelta(sectionId, delta) {
        const copy = sections.slice();
        const i = copy.findIndex(function (s) { return s.id === sectionId; });
        if (i < 0) return;
        const j = Math.max(0, Math.min(copy.length - 1, i + delta));
        if (i === j) return;
        const moved = copy.splice(i, 1)[0];
        copy.splice(j, 0, moved);
        sections = copy;
    }

    function _moveDocByDelta(sectionId, ref, delta) {
        _replaceSections(function (copy) {
            const s = copy.find(function (x) { return x.id === sectionId; });
            if (!s) return;
            const i = s.items.findIndex(function (it) { return it.ref === ref; });
            if (i < 0) return;
            const j = Math.max(0, Math.min(s.items.length - 1, i + delta));
            if (i === j) return;
            const moved = s.items.splice(i, 1)[0];
            s.items.splice(j, 0, moved);
            s.sortBy = "manual";
        });
    }

    function _moveListItemByDelta(listName, idx, delta) {
        const list = (listName === "snippets" ? snippets : contacts).slice();
        const j = Math.max(0, Math.min(list.length - 1, idx + delta));
        if (idx === j) return;
        const moved = list.splice(idx, 1)[0];
        list.splice(j, 0, moved);
        if (listName === "snippets") snippets = list;
        else contacts = list;
    }

    function saveDoc(draft) {
        const targetSectionId = draft._sectionId || editor.sectionId;
        const cleaned = Object.assign({}, draft);
        delete cleaned._sectionId;
        delete cleaned._isNew;

        _replaceSections(copy => {
            if (editor.isNew) {
                const target = copy.find(s => s.id === targetSectionId);
                if (target) target.items.push(cleaned);
            } else {
                for (let s of copy) {
                    if (s.id === editor.sectionId) {
                        if (targetSectionId === s.id) {
                            s.items = s.items.map(i => i.ref === editor.originalRef ? cleaned : i);
                        } else {
                            s.items = s.items.filter(i => i.ref !== editor.originalRef);
                        }
                    } else if (s.id === targetSectionId) {
                        s.items.push(cleaned);
                    }
                }
            }
        });
        showToast(editor.isNew ? ("Создано: " + (cleaned.ref || cleaned.title)) : ("Сохранено: " + (cleaned.ref || cleaned.title)));
    }
    function deleteDoc(sectionId, ref) {
        // Capture for undo
        const sec = sections.find(function (s) { return s.id === sectionId; });
        if (!sec) return;
        const idx = sec.items.findIndex(function (i) { return i.ref === ref; });
        if (idx < 0) return;
        const captured = sec.items[idx];

        _replaceSections(function (copy) {
            for (let s of copy)
                if (s.id === sectionId) s.items = s.items.filter(function (i) { return i.ref !== ref; });
        });

        pendingUndo = { kind: "doc", sectionId: sectionId, itemIdx: idx, item: captured };
        showUndoToast("Удалено: " + ref, function () { root.undoLastDeletion() });
    }

    function saveSnippet(draft, idx) {
        const list = snippets.slice();
        if (idx < 0 || idx === undefined) { list.push(draft); showToast("Snippet создан: " + draft.title); }
        else { list[idx] = draft; showToast("Snippet сохранён: " + draft.title); }
        snippets = list;
    }
    function deleteSnippet(idx) {
        if (idx < 0 || idx >= snippets.length) return;
        const captured = snippets[idx];
        const list = snippets.slice();
        list.splice(idx, 1);
        snippets = list;
        pendingUndo = { kind: "snippet", idx: idx, item: captured };
        showUndoToast("Snippet удалён: " + captured.title, function () { root.undoLastDeletion() });
    }

    function saveContact(draft, idx) {
        const list = contacts.slice();
        if (idx < 0 || idx === undefined) { list.push(draft); showToast("Контакт добавлен: " + draft.name); }
        else { list[idx] = draft; showToast("Контакт сохранён: " + draft.name); }
        contacts = list;
    }
    function saveSection(draft, originalId) {
        const copy = sections.map(function (s) {
            return Object.assign({}, s, { items: s.items.slice(), customFields: (s.customFields || []).slice() });
        });
        if (originalId === "" || originalId === undefined) {
            // create — generate id
            let base = String(draft.title || "section").toLowerCase()
                            .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
            if (base.length === 0) base = "section";
            let id = base;
            let n = 2;
            while (copy.some(function (s) { return s.id === id; })) { id = base + "-" + n; n++; }
            copy.push({
                id: id,
                title: draft.title || "",
                subtitle: draft.subtitle || "",
                accent: draft.accent || Theme.accent,
                customFields: (draft.customFields || []).slice(),
                items: []
            });
            sections = copy;
            showToast("Создана секция: " + draft.title);
        } else {
            const i = copy.findIndex(function (s) { return s.id === originalId; });
            if (i < 0) return;
            copy[i].title        = draft.title || copy[i].title;
            copy[i].subtitle     = draft.subtitle || "";
            copy[i].accent       = draft.accent || copy[i].accent;
            copy[i].customFields = (draft.customFields || []).slice();
            sections = copy;
            showToast("Сохранено: " + draft.title);
        }
    }

    function deleteSection(sectionId) {
        const i = sections.findIndex(function (s) { return s.id === sectionId; });
        if (i < 0) return;
        const captured = sections[i];
        const copy = sections.slice();
        copy.splice(i, 1);
        sections = copy;
        pendingUndo = { kind: "section", idx: i, item: captured };
        showUndoToast("Удалена секция: " + captured.title, function () { root.undoLastDeletion() });
    }

    function deleteContact(idx) {
        if (idx < 0 || idx >= contacts.length) return;
        const captured = contacts[idx];
        const list = contacts.slice();
        list.splice(idx, 1);
        contacts = list;
        pendingUndo = { kind: "contact", idx: idx, item: captured };
        showUndoToast("Контакт удалён: " + captured.name, function () { root.undoLastDeletion() });
    }

    function openExternal(url) {
        if (!url) return;
        if (url.indexOf("#") === 0) {
            showToast("Open in wiki: " + url.substring(1));
        } else {
            Qt.openUrlExternally(url);
        }
    }

    // ── Layout ──────────────────────────────────────────────────────────────

    Rectangle { anchors.fill: parent; color: Theme.bg }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Head bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            color: Theme.panel
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: Theme.border }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18; anchors.rightMargin: 18
                spacing: 14

                ColumnLayout {
                    spacing: 1
                    Layout.alignment: Qt.AlignVCenter
                    Text { text: "Docs · spec & references"; color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Text {
                        text: root.totalDocs() + " entries · " + root.snippets.length + " snippets · " + root.contacts.length + " contacts"
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                }

                Item { Layout.fillWidth: true }

                // Search
                Rectangle {
                    Layout.preferredWidth: 320
                    Layout.preferredHeight: 28
                    radius: 6
                    color: Theme.panel2
                    border.color: Theme.border
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10; anchors.rightMargin: 6
                        spacing: 6
                        Text { text: "⌕"; color: Theme.textDim; font.pixelSize: 11 }
                        TextField {
                            id: docsSearch
                            Layout.fillWidth: true
                            placeholderText: "Поиск: 36.331, RRC, asan, valgrind…"
                            color: Theme.text
                            placeholderTextColor: Theme.textDim
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            background: Item {}
                            selectByMouse: true
                            text: root.searchText
                            onTextChanged: root.searchText = text
                        }
                        Rectangle {
                            visible: root.searchText.length > 0
                            width: 18; height: 18; radius: 9
                            color: clearMA.containsMouse ? Theme.panel3 : "transparent"
                            Text { anchors.centerIn: parent; text: "×"; color: Theme.textDim; font.pixelSize: 14 }
                            MouseArea {
                                id: clearMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.searchText = ""; docsSearch.text = "" }
                            }
                        }
                    }
                }

            }
        }

        // Body — nav + scrollable content
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Nav rail
            Rectangle {
                Layout.preferredWidth: 220
                Layout.fillHeight: true
                color: Theme.panel
                Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: Theme.border }

                Column {
                    id: navCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 2

                    Repeater {
                        model: root.sections
                        delegate: NavLink {
                            required property var modelData
                            required property int index
                            width: navCol.width
                            label: modelData.title
                            count: modelData.items.length
                            barColor: modelData.accent
                            anchorId: "sec-" + modelData.id
                            sectionId: modelData.id
                            sectionIndex: index
                        }
                    }

                    Item { width: navCol.width; height: 8 }
                    Rectangle { width: navCol.width; height: 1; color: Theme.border }
                    Item { width: navCol.width; height: 6 }

                    NavLink {
                        width: navCol.width
                        label: "Snippets"
                        count: root.snippets.length
                        barColor: Theme.accent
                        anchorId: "sec-snippets"
                    }
                    NavLink {
                        width: navCol.width
                        label: "Contacts"
                        count: root.contacts.length
                        barColor: Theme.textMuted
                        anchorId: "sec-contacts"
                    }

                    Item { width: navCol.width; height: 10 }

                    Rectangle {
                        width: navCol.width
                        height: 28
                        radius: 6
                        color: addSecMA.containsMouse ? Theme.accentSoft : Theme.panel2
                        border.color: Theme.border
                        border.width: 1
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8; anchors.rightMargin: 8
                            spacing: 6
                            Text {
                                text: "+"
                                color: addSecMA.containsMouse ? Theme.accentStrong : Theme.textDim
                                font.pixelSize: 14
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Новая секция"
                                color: addSecMA.containsMouse ? Theme.accentStrong : Theme.text
                                font.pixelSize: 12
                            }
                        }
                        MouseArea {
                            id: addSecMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openSectionCreate()
                        }
                    }
                }
            }

            // Body — explicit Flickable so we can fully control wheel speed
            // and pressDelay (so quick LMB-drag pans the page).
            Flickable {
                id: bodyScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: bodyCol.implicitHeight
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                pressDelay: 180

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        const dy = event.angleDelta.y;
                        if (dy === 0) return;
                        const maxY = Math.max(0, bodyScroll.contentHeight - bodyScroll.height);
                        if (maxY <= 0) return;
                        bodyScroll.contentY = Math.max(0, Math.min(maxY, bodyScroll.contentY - dy * 3));
                    }
                }

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                ColumnLayout {
                    id: bodyCol
                    width: bodyScroll.width
                    spacing: 24

                    // Doc sections
                    Repeater {
                        model: root.sections
                        delegate: ColumnLayout {
                            id: secCol
                            required property var modelData
                            required property int index
                            property var section: modelData
                            property var filtered: root._sortedItems(section).filter(root.passesSearch)
                            visible: !(root.searchText.length > 0 && filtered.length === 0)
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            Layout.rightMargin: 24
                            Layout.topMargin: index === 0 ? 20 : 0
                            spacing: 12

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                id: secAnchor
                                objectName: "sec-" + secCol.section.id

                                MouseArea {
                                    id: secHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.RightButton
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.RightButton) sectionMenu.popup()
                                    }
                                }

                                QQC.Menu {
                                    id: sectionMenu
                                    QQC.MenuItem { text: "Add entry";        onTriggered: root.openDocCreate(secCol.section.id) }
                                    QQC.MenuItem { text: "Rename / fields…"; onTriggered: root.openSectionEdit(secCol.section) }
                                    QQC.Menu {
                                        title: "Sort by"
                                        QQC.MenuItem { text: "Manual";     onTriggered: root.setSortBy(secCol.section.id, "manual", false) }
                                        QQC.MenuItem { text: "By ref";     onTriggered: root.setSortBy(secCol.section.id, "ref", false) }
                                        QQC.MenuItem { text: "By title";   onTriggered: root.setSortBy(secCol.section.id, "title", false) }
                                        QQC.MenuItem { text: "By updated"; onTriggered: root.setSortBy(secCol.section.id, "updated", true) }
                                    }
                                    QQC.MenuSeparator {}
                                    QQC.MenuItem { text: "Move up";   enabled: secCol.index > 0;                              onTriggered: root._moveSectionByDelta(secCol.section.id, -1) }
                                    QQC.MenuItem { text: "Move down"; enabled: secCol.index < root.sections.length - 1;       onTriggered: root._moveSectionByDelta(secCol.section.id, +1) }
                                    QQC.MenuSeparator {}
                                    QQC.MenuItem { text: "Delete section"; onTriggered: root.deleteSection(secCol.section.id) }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 12
                                    Rectangle { width: 4; height: 32; radius: 2; color: secCol.section.accent }
                                    ColumnLayout {
                                        spacing: 0
                                        Layout.fillWidth: true
                                        RowLayout {
                                            spacing: 6
                                            Text {
                                                text: secCol.section.title
                                                color: Theme.text
                                                font.pixelSize: 16
                                                font.weight: Font.DemiBold
                                            }
                                            Rectangle {
                                                visible: secHover.containsMouse
                                                width: 22; height: 22; radius: 5
                                                color: secEditMA.containsMouse ? Theme.panel2 : "transparent"
                                                border.color: Theme.border; border.width: 1
                                                Text { anchors.centerIn: parent; text: "✎"; color: Theme.textMuted; font.pixelSize: 11 }
                                                MouseArea {
                                                    id: secEditMA
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.openSectionEdit(secCol.section)
                                                }
                                            }
                                            Rectangle {
                                                visible: secHover.containsMouse
                                                width: 22; height: 22; radius: 5
                                                color: secDelMA.containsMouse ? Theme.withAlpha(Theme.p0, 0.16) : "transparent"
                                                border.color: secDelMA.containsMouse ? Theme.p0 : Theme.border; border.width: 1
                                                Text {
                                                    anchors.centerIn: parent; text: "×"
                                                    color: secDelMA.containsMouse ? Theme.p0 : Theme.textMuted
                                                    font.pixelSize: 12
                                                }
                                                MouseArea {
                                                    id: secDelMA
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.deleteSection(secCol.section.id)
                                                }
                                            }
                                        }
                                        Text { text: secCol.section.subtitle; color: Theme.textMuted; font.pixelSize: 12 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        visible: (secCol.section.sortBy || "manual") !== "manual"
                                        text: {
                                            const m = secCol.section.sortBy || "manual";
                                            const lbl = m === "ref" ? "ref" : m === "title" ? "title" : m === "updated" ? "upd" : m;
                                            return "▼ " + lbl + (secCol.section.sortDesc ? " ↓" : " ↑");
                                        }
                                        color: Theme.accentStrong
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                    }
                                    Text {
                                        text: secCol.filtered.length + " / " + secCol.section.items.length
                                        color: Theme.textDim
                                        font.family: Theme.fontMono
                                        font.pixelSize: 11
                                    }
                                    PillButton {
                                        text: "+ Add"
                                        onClicked: root.openDocCreate(secCol.section.id)
                                    }
                                }

                            }

                            // Grid of cards (2 columns)
                            Grid {
                                id: cardGrid
                                Layout.fillWidth: true
                                columns: Math.max(1, Math.floor(width / 340))
                                columnSpacing: 12
                                rowSpacing: 12

                                Repeater {
                                    model: secCol.filtered
                                    delegate: DocCard {
                                        required property var modelData
                                        required property int index
                                        item: modelData
                                        accent: secCol.section.accent
                                        sectionId: secCol.section.id
                                        customFields: secCol.section.customFields || []
                                        width: (cardGrid.width - (cardGrid.columns - 1) * cardGrid.columnSpacing) / cardGrid.columns
                                    }
                                }

                                Rectangle {
                                    id: addEntryTile
                                    width: cardGrid.columns > 0
                                           ? ((cardGrid.width - (cardGrid.columns - 1) * cardGrid.columnSpacing) / cardGrid.columns)
                                           : cardGrid.width
                                    height: 100
                                    radius: 10
                                    color: addCardMA.containsMouse ? Theme.panel2 : "transparent"
                                    border.color: Theme.border
                                    border.width: 1
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "+"; color: Theme.textDim; font.pixelSize: 22 }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Add entry"; color: Theme.textDim; font.pixelSize: 11 }
                                    }
                                    MouseArea {
                                        id: addCardMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.openDocCreate(secCol.section.id)
                                    }
                                }
                            }
                        }
                    }

                    // Snippets
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 24
                        Layout.rightMargin: 24
                        spacing: 12
                        Item {
                            Layout.fillWidth: true; Layout.preferredHeight: 44
                            objectName: "sec-snippets"
                            RowLayout {
                                anchors.fill: parent
                                spacing: 12
                                Rectangle { width: 4; height: 32; radius: 2; color: Theme.accent }
                                ColumnLayout {
                                    spacing: 0
                                    Text { text: "Snippets"; color: Theme.text; font.pixelSize: 16; font.weight: Font.DemiBold }
                                    Text { text: "Часто используемые команды и шаблоны кода"; color: Theme.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: root.snippets.length + ""
                                    color: Theme.textDim
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                }
                                PillButton {
                                    text: "+ Add"
                                    onClicked: root.openSnippetCreate()
                                }
                            }
                        }

                        Repeater {
                            model: root.snippets
                            delegate: SnippetCard {
                                required property var modelData
                                required property int index
                                snip: modelData
                                idx: index
                                Layout.fillWidth: true
                            }
                        }
                    }

                    // Contacts
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 24
                        Layout.rightMargin: 24
                        Layout.bottomMargin: 32
                        spacing: 12
                        Item {
                            Layout.fillWidth: true; Layout.preferredHeight: 44
                            objectName: "sec-contacts"
                            RowLayout {
                                anchors.fill: parent
                                spacing: 12
                                Rectangle { width: 4; height: 32; radius: 2; color: Theme.textMuted }
                                ColumnLayout {
                                    spacing: 0
                                    Text { text: "Contacts & Channels"; color: Theme.text; font.pixelSize: 16; font.weight: Font.DemiBold }
                                    Text { text: "Кому пинговать в ММ и где обсуждать"; color: Theme.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: root.contacts.length + ""
                                    color: Theme.textDim
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                }
                                PillButton {
                                    text: "+ Add"
                                    onClicked: root.openContactCreate()
                                }
                            }
                        }

                        Grid {
                            Layout.fillWidth: true
                            columns: Math.max(1, Math.floor(width / 280))
                            columnSpacing: 10
                            rowSpacing: 8
                            Repeater {
                                model: root.contacts
                                delegate: ContactCard {
                                    required property var modelData
                                    required property int index
                                    c: modelData
                                    idx: index
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Toast ───────────────────────────────────────────────────────────────
    Toast {
        id: toast
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        anchors.horizontalCenter: parent.horizontalCenter
        z: 80
    }

    // ── Editor ──────────────────────────────────────────────────────────────
    DocsEditor {
        id: editor
        sections: root.sections
        contactPalette: root.contactPalette
        accentPalette: root.accentPalette
        onSavedDoc:     (draft) => root.saveDoc(draft)
        onDeletedDoc:   () => root.deleteDoc(editor.sectionId, editor.originalRef)
        onSavedSnippet: (draft) => root.saveSnippet(draft, editor.idx)
        onDeletedSnippet: () => root.deleteSnippet(editor.idx)
        onSavedContact: (draft) => root.saveContact(draft, editor.idx)
        onDeletedContact: () => root.deleteContact(editor.idx)
        onSavedSection: (draft) => root.saveSection(draft, editor.sectionId)
        onDeletedSection: () => root.deleteSection(editor.sectionId)
    }

    function _sectionCustomFields(sectionId) {
        const s = sections.find(function (x) { return x.id === sectionId; });
        return s ? (s.customFields || []) : [];
    }
    function openDocCreate(sectionId) {
        editor.kind = "doc";
        editor.sectionId = sectionId;
        editor.originalRef = "";
        editor.isNew = true;
        editor.docCustomFields = root._sectionCustomFields(sectionId);
        editor.draft = ({ ref: "", title: "", desc: "", url: "", source: "", version: "", updated: "", extra: {}, _sectionId: sectionId });
        editor.open();
    }
    function openDocEdit(sectionId, item) {
        editor.kind = "doc";
        editor.sectionId = sectionId;
        editor.originalRef = item.ref;
        editor.isNew = false;
        editor.docCustomFields = root._sectionCustomFields(sectionId);
        editor.draft = Object.assign({ extra: {} }, item, { _sectionId: sectionId, extra: Object.assign({}, item.extra || {}) });
        editor.open();
    }
    function openSnippetCreate() {
        editor.kind = "snippet";
        editor.idx = -1;
        editor.isNew = true;
        editor.draft = ({ title: "", lang: "sh", code: "" });
        editor.open();
    }
    function openSnippetEdit(idx) {
        editor.kind = "snippet";
        editor.idx = idx;
        editor.isNew = false;
        editor.draft = Object.assign({}, root.snippets[idx]);
        editor.open();
    }
    function openContactCreate() {
        editor.kind = "contact";
        editor.idx = -1;
        editor.isNew = true;
        editor.draft = ({ name: "", role: "", channel: "", mattermost: "", color: root.contactPalette[0] });
        editor.open();
    }
    function openContactEdit(idx) {
        editor.kind = "contact";
        editor.idx = idx;
        editor.isNew = false;
        editor.draft = Object.assign({}, root.contacts[idx]);
        editor.open();
    }

    function openSectionCreate() {
        editor.kind = "section";
        editor.sectionId = "";        // empty = create
        editor.isNew = true;
        editor.draft = ({ title: "", subtitle: "", accent: root.accentPalette[0] });
        editor.open();
    }
    function openSectionEdit(s) {
        editor.kind = "section";
        editor.sectionId = s.id;
        editor.isNew = false;
        editor.draft = ({
            title: s.title,
            subtitle: s.subtitle,
            accent: String(s.accent),
            customFields: (s.customFields || []).slice()
        });
        editor.open();
    }

    // ── Inline components ───────────────────────────────────────────────────

    component NavLink: Rectangle {
        id: nav
        property string label: ""
        property int count: 0
        property color barColor: Theme.accent
        property string anchorId: ""
        property string sectionId: ""       // empty → not draggable (snippets/contacts links)
        property int    sectionIndex: -1
        readonly property bool draggable: sectionId.length > 0
        height: 30
        radius: 6
        color: navMA.containsMouse ? Theme.panel2 : "transparent"
        opacity: navDragMA.drag.active ? 0.5 : 1.0

        Drag.active: navDragMA.drag.active
        Drag.dragType: Drag.Internal
        Drag.keys: ["nav-section"]
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2
        property real homeX: 0
        property real homeY: 0

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8; anchors.rightMargin: 8
            spacing: 8
            Rectangle { width: 4; height: 16; radius: 2; color: nav.barColor }
            Text { text: nav.label; color: Theme.text; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
            Text { text: nav.count + ""; color: Theme.textDim; font.family: Theme.fontMono; font.pixelSize: 11 }
        }
        MouseArea {
            id: navMA
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }
        MouseArea {
            id: navDragMA
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            drag.target: nav.draggable ? nav : null
            drag.threshold: 6
            property bool didDrag: false
            onPressed: (mouse) => {
                nav.homeX = nav.x; nav.homeY = nav.y; didDrag = false;
                if (mouse.button === Qt.RightButton && nav.draggable) navMenu.popup();
            }
            onPositionChanged: if (drag.active) didDrag = true
            onReleased: (mouse) => {
                const wasDrag = didDrag;
                if (nav.draggable) nav.Drag.drop();
                nav.x = nav.homeX; nav.y = nav.homeY;
                didDrag = false;
                if (!wasDrag && mouse.button === Qt.LeftButton) scrollToAnchor(nav.anchorId);
            }
        }

        // Receive drops from sibling NavLinks — top/bottom halves decide insert side.
        DropArea {
            anchors.fill: parent
            keys: ["nav-section"]
            property bool insertBefore: true
            property bool over: false
            enabled: nav.draggable
            onEntered: over = true
            onExited:  over = false
            onPositionChanged: (drag) => { insertBefore = (drag.y < height / 2) }
            onDropped: (drop) => {
                over = false;
                const srcId = drop.source && drop.source.sectionId;
                if (srcId && srcId !== nav.sectionId) {
                    root._reorderSection(srcId, nav.sectionId, insertBefore);
                    drop.accept(Qt.MoveAction);
                }
            }
            Rectangle {
                visible: parent.over && parent.insertBefore
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                height: 2; color: Theme.accent
            }
            Rectangle {
                visible: parent.over && !parent.insertBefore
                anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                height: 2; color: Theme.accent
            }
        }

        QQC.Menu {
            id: navMenu
            QQC.MenuItem {
                text: "Rename / fields…"
                onTriggered: {
                    const s = root.sections.find(function (x) { return x.id === nav.sectionId; });
                    if (s) root.openSectionEdit(s);
                }
            }
            QQC.Menu {
                title: "Sort by"
                QQC.MenuItem { text: "Manual";     onTriggered: root.setSortBy(nav.sectionId, "manual", false) }
                QQC.MenuItem { text: "By ref";     onTriggered: root.setSortBy(nav.sectionId, "ref", false) }
                QQC.MenuItem { text: "By title";   onTriggered: root.setSortBy(nav.sectionId, "title", false) }
                QQC.MenuItem { text: "By updated"; onTriggered: root.setSortBy(nav.sectionId, "updated", true) }
            }
            QQC.MenuSeparator {}
            QQC.MenuItem { text: "Move up";   enabled: nav.sectionIndex > 0;                              onTriggered: root._moveSectionByDelta(nav.sectionId, -1) }
            QQC.MenuItem { text: "Move down"; enabled: nav.sectionIndex < root.sections.length - 1;        onTriggered: root._moveSectionByDelta(nav.sectionId, +1) }
            QQC.MenuSeparator {}
            QQC.MenuItem { text: "Delete section"; onTriggered: root.deleteSection(nav.sectionId) }
        }
    }

    function scrollToAnchor(objectName) {
        const target = findChildByName(bodyCol, objectName);
        if (!target) return;
        const p = target.mapToItem(bodyCol, 0, 0);
        bodyScroll.contentY = Math.max(0, Math.min(p.y - 8, bodyScroll.contentHeight - bodyScroll.height));
    }
    function findChildByName(parentItem, name) {
        if (!parentItem) return null;
        const kids = parentItem.children;
        for (let i = 0; i < kids.length; i++) {
            const k = kids[i];
            if (k && k.objectName === name) return k;
            const sub = findChildByName(k, name);
            if (sub) return sub;
        }
        return null;
    }

    component DocCard: Rectangle {
        id: card
        property var item: ({})
        property color accent: Theme.accent
        property string sectionId: ""
        property var customFields: []
        readonly property bool isInternal: (item.url || "").indexOf("#") === 0
        // Drag-source identifiers (read by DropArea.drop.source)
        property string docRef: item.ref || ""
        property string docSectionId: sectionId
        height: cardCol.implicitHeight + 24
        radius: 10
        color: cardMA.containsMouse ? Theme.panel2 : Theme.panel
        border.color: cardMA.containsMouse ? Theme.borderStrong : Theme.border
        border.width: 1
        opacity: handleMA.drag.active ? 0.5 : 1.0

        Drag.active: handleMA.drag.active
        Drag.dragType: Drag.Internal
        Drag.keys: ["doc"]
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: 24

        property real homeX: 0
        property real homeY: 0

        ColumnLayout {
            id: cardCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6

            RowLayout {
                spacing: 6
                Rectangle {
                    radius: 4
                    color: "transparent"
                    border.color: card.accent
                    border.width: 1
                    implicitWidth: refT.implicitWidth + 14
                    implicitHeight: 20
                    Text { id: refT; anchors.centerIn: parent
                           text: card.item.ref || ""
                           color: card.accent
                           font.family: Theme.fontMono
                           font.pixelSize: 11
                           font.weight: Font.DemiBold }
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: (card.item.version || "").length > 0
                    text: card.item.version || ""
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }
                Text {
                    text: card.isInternal ? "→" : "↗"
                    color: cardMA.containsMouse ? Theme.accentStrong : Theme.textDim
                    font.pixelSize: 12
                }
            }
            Text {
                Layout.fillWidth: true
                text: card.item.title || ""
                color: Theme.text
                font.pixelSize: 13
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                text: card.item.desc || ""
                color: Theme.textMuted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            // Custom extras — render rows for each field defined on the section
            Repeater {
                model: card.customFields
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 6
                    visible: (card.item && card.item.extra && String(card.item.extra[modelData.key] || "").length > 0)
                    Text {
                        text: (modelData.label || modelData.key) + ":"
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                    }
                    Text {
                        Layout.fillWidth: true
                        text: card.item && card.item.extra ? String(card.item.extra[modelData.key] || "") : ""
                        color: Theme.text
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Text {
                    text: card.item.source || ""
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: (card.item.updated || "").length > 0
                    text: "upd " + (card.item.updated || "")
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                }
            }
        }

        // Hover-overlay icons: ⋮⋮ drag handle (LMB drag-source), ✎ edit, × delete.
        // Keeping the drag-source to a small handle frees the rest of the card
        // for click + page-pan via the parent Flickable.
        Row {
            visible: cardMA.containsMouse && !handleMA.drag.active
            anchors.top: parent.top; anchors.right: parent.right
            anchors.margins: 6
            spacing: 4
            Rectangle {
                width: 18; height: 22; radius: 4
                color: handleMA.containsMouse ? Theme.panel3 : Theme.panel2
                border.color: Theme.border; border.width: 1
                Text { anchors.centerIn: parent; text: "⋮⋮"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 11 }
                MouseArea {
                    id: handleMA
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    drag.target: card
                    drag.threshold: 4
                    cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    onPressed: { card.homeX = card.x; card.homeY = card.y }
                    onReleased: { card.Drag.drop(); card.x = card.homeX; card.y = card.homeY }
                }
            }
            Rectangle {
                width: 22; height: 22; radius: 5
                color: editIcoMA.containsMouse ? Theme.panel3 : Theme.panel2
                border.color: Theme.border; border.width: 1
                Text { anchors.centerIn: parent; text: "✎"; color: Theme.textMuted; font.pixelSize: 11 }
                MouseArea {
                    id: editIcoMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openDocEdit(card.sectionId, card.item)
                }
            }
            Rectangle {
                width: 22; height: 22; radius: 5
                color: delIcoMA.containsMouse ? Theme.withAlpha(Theme.p0, 0.16) : Theme.panel2
                border.color: delIcoMA.containsMouse ? Theme.p0 : Theme.border; border.width: 1
                Text { anchors.centerIn: parent; text: "×"; color: delIcoMA.containsMouse ? Theme.p0 : Theme.textMuted; font.pixelSize: 12 }
                MouseArea {
                    id: delIcoMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.deleteDoc(card.sectionId, card.item.ref)
                }
            }
        }

        MouseArea {
            id: cardMA
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) docCardMenu.popup();
                else root.openExternal(card.item.url);
            }
        }

        // Drop target — top half inserts BEFORE, bottom half inserts AFTER
        DropArea {
            id: cardDrop
            anchors.fill: parent
            keys: ["doc"]
            property bool insertBefore: true
            property bool over: false
            onEntered: over = true
            onExited:  over = false
            onPositionChanged: (drag) => { insertBefore = (drag.y < height / 2) }
            onDropped: (drop) => {
                over = false;
                const src = drop.source;
                if (src && src !== card && src.docRef !== undefined && src.docSectionId !== undefined) {
                    root._reorderDoc(src.docSectionId, src.docRef, card.sectionId, card.item.ref, insertBefore);
                    drop.accept(Qt.MoveAction);
                }
            }
            Rectangle {
                visible: cardDrop.over && cardDrop.insertBefore
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                height: 3; radius: 2; color: Theme.accent
            }
            Rectangle {
                visible: cardDrop.over && !cardDrop.insertBefore
                anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                height: 3; radius: 2; color: Theme.accent
            }
        }

        QQC.Menu {
            id: docCardMenu
            QQC.MenuItem {
                text: card.isInternal ? "Open (wiki)" : "Open URL ↗"
                enabled: (card.item.url || "").length > 0
                onTriggered: root.openExternal(card.item.url)
            }
            QQC.MenuItem { text: "Edit…"; onTriggered: root.openDocEdit(card.sectionId, card.item) }
            QQC.MenuSeparator {}
            QQC.MenuItem { text: "Move up";   onTriggered: root._moveDocByDelta(card.sectionId, card.item.ref, -1) }
            QQC.MenuItem { text: "Move down"; onTriggered: root._moveDocByDelta(card.sectionId, card.item.ref, +1) }
            QQC.MenuSeparator {}
            QQC.MenuItem { text: "Delete"; onTriggered: root.deleteDoc(card.sectionId, card.item.ref) }
        }
    }

    component SnippetCard: Rectangle {
        id: sCard
        property var snip: ({})
        property int idx: -1
        radius: 10
        color: Theme.panel
        border.color: snHover.containsMouse ? Theme.borderStrong : Theme.border
        border.width: 1
        implicitHeight: sCol.implicitHeight + 20

        MouseArea {
            id: snHover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.RightButton
            onClicked: (mouse) => { if (mouse.button === Qt.RightButton) snipMenu.popup() }
        }

        ColumnLayout {
            id: sCol
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { text: sCard.snip.title || ""; color: Theme.text; font.pixelSize: 12; font.weight: Font.Medium; Layout.fillWidth: true; elide: Text.ElideRight }
                Rectangle {
                    radius: 4
                    color: Theme.panel2
                    border.color: Theme.border; border.width: 1
                    implicitWidth: lngT.implicitWidth + 12
                    implicitHeight: 18
                    Text { id: lngT; anchors.centerIn: parent; text: sCard.snip.lang || ""; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 10 }
                }
                Rectangle {
                    radius: 4
                    color: copySnMA.containsMouse ? Theme.accentSoft : Theme.panel2
                    border.color: copySnMA.containsMouse ? Theme.accent : Theme.border
                    border.width: 1
                    implicitWidth: copyT.implicitWidth + 14
                    implicitHeight: 22
                    Text { id: copyT; anchors.centerIn: parent; text: "copy"; color: copySnMA.containsMouse ? Theme.accentStrong : Theme.textMuted; font.pixelSize: 11 }
                    MouseArea {
                        id: copySnMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            AppController.copyToClipboard(sCard.snip.code || "");
                            root.showToast("Скопировано: " + (sCard.snip.title || ""));
                        }
                    }
                }
                Rectangle {
                    visible: snHover.containsMouse
                    radius: 4
                    color: editSnMA.containsMouse ? Theme.accentSoft : Theme.panel2
                    border.color: editSnMA.containsMouse ? Theme.accent : Theme.border
                    border.width: 1
                    implicitWidth: 26; implicitHeight: 22
                    Text { anchors.centerIn: parent; text: "✎"; color: editSnMA.containsMouse ? Theme.accentStrong : Theme.textMuted; font.pixelSize: 11 }
                    MouseArea { id: editSnMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openSnippetEdit(sCard.idx) }
                }
                Rectangle {
                    visible: snHover.containsMouse
                    radius: 4
                    color: delSnMA.containsMouse ? Theme.withAlpha(Theme.p0, 0.16) : Theme.panel2
                    border.color: delSnMA.containsMouse ? Theme.p0 : Theme.border; border.width: 1
                    implicitWidth: 26; implicitHeight: 22
                    Text { anchors.centerIn: parent; text: "×"; color: delSnMA.containsMouse ? Theme.p0 : Theme.textMuted; font.pixelSize: 12 }
                    MouseArea { id: delSnMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.deleteSnippet(sCard.idx) }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                color: Theme.bg2
                radius: 6
                border.color: Theme.border
                border.width: 1
                implicitHeight: codeText.implicitHeight + 18
                TextEdit {
                    id: codeText
                    anchors.fill: parent
                    anchors.margins: 10
                    text: sCard.snip.code || ""
                    color: Theme.text
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.NoWrap
                }
                CodeHighlighter {
                    target: codeText.textDocument
                    language: sCard.snip.lang || "text"
                    palette: ({
                        keyword: Theme.accent,
                        string:  Theme.p2,
                        comment: Theme.textDim,
                        number:  Theme.mFocus,
                        type:    Theme.mSync,
                        builtin: Theme.mOneone
                    })
                }
            }
        }

        QQC.Menu {
            id: snipMenu
            QQC.MenuItem {
                text: "Copy"
                onTriggered: {
                    AppController.copyToClipboard(sCard.snip.code || "");
                    root.showToast("Скопировано: " + (sCard.snip.title || ""));
                }
            }
            QQC.MenuItem { text: "Edit…"; onTriggered: root.openSnippetEdit(sCard.idx) }
            QQC.MenuSeparator {}
            QQC.MenuItem { text: "Move up";   enabled: sCard.idx > 0;                        onTriggered: root._moveListItemByDelta("snippets", sCard.idx, -1) }
            QQC.MenuItem { text: "Move down"; enabled: sCard.idx < root.snippets.length - 1; onTriggered: root._moveListItemByDelta("snippets", sCard.idx, +1) }
            QQC.MenuSeparator {}
            QQC.MenuItem { text: "Delete"; onTriggered: root.deleteSnippet(sCard.idx) }
        }
    }

    component ContactCard: Rectangle {
        id: cc
        property var c: ({})
        property int idx: -1
        width: parent ? ((parent.width - (parent.columns - 1) * parent.columnSpacing) / parent.columns) : 240
        height: 56
        radius: 10
        color: ccMA.containsMouse ? Theme.panel2 : Theme.panel
        border.color: ccMA.containsMouse ? Theme.borderStrong : Theme.border
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10; anchors.rightMargin: 10
            spacing: 10
            Rectangle {
                width: 32; height: 32; radius: 16
                color: cc.c.color || Theme.accent
                Text {
                    anchors.centerIn: parent
                    text: root.initials(cc.c.name || "")
                    color: "#06121a"
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text { text: cc.c.name || ""; color: Theme.text; font.pixelSize: 12; font.weight: Font.Medium; elide: Text.ElideRight; Layout.fillWidth: true }
                Text { text: cc.c.role || ""; color: Theme.textMuted; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
            }
            ColumnLayout {
                spacing: 0
                Text { text: cc.c.channel || ""; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 10 }
                Text { text: cc.c.slack || "";   color: Theme.textDim;   font.family: Theme.fontMono; font.pixelSize: 10 }
            }
            Row {
                visible: ccMA.containsMouse
                spacing: 4
                Rectangle {
                    width: 22; height: 22; radius: 5
                    color: editCMA.containsMouse ? Theme.panel3 : Theme.panel2
                    border.color: Theme.border; border.width: 1
                    Text { anchors.centerIn: parent; text: "✎"; color: Theme.textMuted; font.pixelSize: 11 }
                    MouseArea { id: editCMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openContactEdit(cc.idx) }
                }
                Rectangle {
                    width: 22; height: 22; radius: 5
                    color: delCMA.containsMouse ? Theme.withAlpha(Theme.p0, 0.16) : Theme.panel2
                    border.color: delCMA.containsMouse ? Theme.p0 : Theme.border; border.width: 1
                    Text { anchors.centerIn: parent; text: "×"; color: delCMA.containsMouse ? Theme.p0 : Theme.textMuted; font.pixelSize: 12 }
                    MouseArea { id: delCMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.deleteContact(cc.idx) }
                }
            }
        }
        MouseArea {
            id: ccMA
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) ccMenu.popup();
                else root.openContactEdit(cc.idx);
            }
            z: -1
        }

        QQC.Menu {
            id: ccMenu
            QQC.MenuItem { text: "Edit…"; onTriggered: root.openContactEdit(cc.idx) }
            QQC.MenuSeparator {}
            QQC.MenuItem { text: "Move up";   enabled: cc.idx > 0;                          onTriggered: root._moveListItemByDelta("contacts", cc.idx, -1) }
            QQC.MenuItem { text: "Move down"; enabled: cc.idx < root.contacts.length - 1;   onTriggered: root._moveListItemByDelta("contacts", cc.idx, +1) }
            QQC.MenuSeparator {}
            QQC.MenuItem { text: "Delete"; onTriggered: root.deleteContact(cc.idx) }
        }
    }
}
