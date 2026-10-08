pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp
import "Overlap.js" as Overlap
import "Segments.js" as Seg
import "Search.js" as Search
import "Reschedule.js" as Resched

Item {
    id: root

    property string searchText: ""
    property var prioritiesFilter: ({})
    property bool showArchived: false

    signal taskClicked(string id)
    // The occurrence, not just its id: a repeating event is stored once, so
    // every occurrence of a series carries the master's id and only the
    // occurrence map says which date was clicked.
    signal eventClicked(string id, var occurrence)
    signal dayClicked(date d)
    // An empty slot was clicked: the shell opens the event editor there.
    signal createRequested(real hour, date day)

    // Shift-click anchor + day for range select. Shift across days falls back
    // to single-toggle since the visible-chip order isn't a single flat list.
    property string shiftAnchorId: ""
    property int    shiftAnchorDay: -1
    Connections {
        target: AppController

        function onSelectedTaskIdsChanged() {
            if (AppController.selectionCount === 0) {
                root.shiftAnchorId = "";
                root.shiftAnchorDay = -1;
            }
        }
    }

    function _renderedIdsForDay(dayIdx) {
        if (dayIdx < 0 || dayIdx >= days.length) return [];
        const list = days[dayIdx].tasks.slice(0, 4);
        const ids = [];
        for (let i = 0; i < list.length; i++) ids.push(list[i].id);
        return ids;
    }

    function _dayIndexOfTask(taskId) {
        for (let i = 0; i < days.length; i++) {
            const ids = _renderedIdsForDay(i);
            if (ids.indexOf(taskId) >= 0) return i;
        }
        return -1;
    }

    function selectAllVisible() {
        const ids = [];
        for (let i = 0; i < days.length; i++) {
            const part = _renderedIdsForDay(i);
            for (let j = 0; j < part.length; j++) ids.push(part[j]);
        }
        AppController.setSelectedTaskIds(ids);
    }

    function _rangeSelect(targetId) {
        const targetDay = _dayIndexOfTask(targetId);
        if (targetDay < 0) return;
        if (root.shiftAnchorId === "" || root.shiftAnchorDay !== targetDay
            || _renderedIdsForDay(targetDay).indexOf(root.shiftAnchorId) < 0) {
            root.shiftAnchorId = targetId;
            root.shiftAnchorDay = targetDay;
            AppController.toggleTaskSelection(targetId);
            return;
        }
        const ordered = _renderedIdsForDay(targetDay);
        const ai = ordered.indexOf(root.shiftAnchorId);
        const ti = ordered.indexOf(targetId);
        const lo = Math.min(ai, ti);
        const hi = Math.max(ai, ti);
        const merged = AppController.selectedTaskIds.slice();
        for (let i = lo; i <= hi; i++) {
            if (merged.indexOf(ordered[i]) < 0) merged.push(ordered[i]);
        }
        AppController.setSelectedTaskIds(merged);
    }

    // The whole day, like the day grid. Clipping to workdayStart..workdayEnd
    // did not merely de-emphasise the rest — an 07:00 standup or a 21:00 call
    // was laid out off-grid and could not be reached at all.
    readonly property int hoursStart: 0
    readonly property int hoursEnd:   24
    readonly property int workStart:  AppController.workdayStart
    readonly property int workEnd:    AppController.workdayEnd

    property date now: new Date()

    // Returns false while the grid has no height to scroll yet.
    function scrollToWorkday() {
        const flick = hourScroll.contentItem;
        if (!flick || flick.height <= 0 || flick.contentHeight <= flick.height) return false;
        const nowHour = new Date().getHours();
        const first = Math.max(0, Math.min(root.workStart, nowHour - 1) - root.hoursStart);
        const maxY = Math.max(0, flick.contentHeight - flick.height);
        flick.contentY = Math.min(maxY, first * root.hourH);
        return true;
    }
    // Component.onCompleted runs before the ScrollView has been laid out, so
    // the scroll used to land on a zero-height grid and the week opened on
    // 00:00–09:00, empty. Try again each frame until there is something to
    // scroll, for at most a second.
    Timer {
        id: workdayScroll
        interval: 16
        repeat: true
        property int tries: 0
        onTriggered: if (root.scrollToWorkday() || ++tries > 60) stop()
    }

    // The "Needs a slot" rail, when the window has room for it. The header
    // button hides it for good on a window that has room but no need.
    property bool railWanted: true
    Timer { interval: 60000; repeat: true; running: true; onTriggered: root.now = new Date() }
    readonly property int hourH: 38
    // An event block's floor heights (APP-199): one line of small text, or
    // the time on top of a title.
    readonly property int eventOneLineH: Math.ceil(Theme.fsXs * 1.4) + 2 * Theme.sp2xs
    readonly property int eventTwoLineH: Math.ceil((Theme.fsXs + Theme.fsSm) * 1.4) + 2 * Theme.sp2xs
    function eventBlock(start, end) {
        return Overlap.block(start, end, root.hourH, root.eventOneLineH, root.eventTwoLineH);
    }
    // Indexed by JS day-of-week (0=Sun..6=Sat) so the label tracks the actual
    // date regardless of which day the week starts on. Names come from the app
    // language — they used to be hardcoded English next to a localised date
    // range in the same header.
    readonly property var dowLabelsByJsDow: {
        const out = [];
        for (let i = 0; i < 7; i++) out.push(I18n.dayName(i));
        return out;
    }

    function isSameDay(a, b) {
        if (!a || !b || !a.getFullYear || !b.getFullYear) return false;
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }
    function startOfWeek(d) {
        const dow = d.getDay();
        const sundayFirst = Theme.weekStart === "sun";
        const offset = sundayFirst ? -dow : (dow === 0 ? -6 : 1 - dow);
        return new Date(d.getFullYear(), d.getMonth(), d.getDate() + offset);
    }
    // Weekend shading must track the real day-of-week, not the column position:
    // under weekStart="sun" column 5 is Friday and column 0 is Sunday, so the
    // old `index >= 5` tinted Friday and missed Sunday.
    function isWeekendDate(d) {
        if (!d || !d.getDay) return false;
        const w = d.getDay();
        return w === 0 || w === 6;
    }
    function fmtShort(d) {
        return AppController.shortDate(d);
    }
    function snapHour(h)  {
        const step = Math.max(1, Theme.snapMinutes) / 60.0;
        return Math.round(h / step) * step;
    }
    function yToHour(y)   { return root.hoursStart + y / root.hourH; }
    function clampHour(h) { return Math.max(root.hoursStart, Math.min(root.hoursEnd, h)); }
    function passesFilter(t) {
        if (t.status === "done") return false;
        // Clauses filter structurally, leftover words stay a substring test.
        if (!Search.accepts(AppController, root.searchText, root.taskRev + ":" + AppController.today, t)) return false;
        let any = false;
        for (const k in root.prioritiesFilter) if (root.prioritiesFilter[k]) { any = true; break; }
        if (any && !root.prioritiesFilter[t.priority]) return false;
        return true;
    }

    // A burst of model changes (a tracker sync) rebuilds once, not per row (APP-203).
    ChangeTick { id: taskTick }
    ChangeTick { id: eventTick }
    readonly property int taskRev: taskTick.rev
    readonly property int eventRev: eventTick.rev
    Connections {
        target: AppController.tasks
        function onDataChanged()  { taskTick.bump() }
        function onRowsInserted() { taskTick.bump() }
        function onRowsRemoved()  { taskTick.bump() }
        function onModelReset()   { taskTick.bump() }
    }
    Connections {
        target: AppController.events
        function onDataChanged()  { eventTick.bump() }
        function onRowsInserted() { eventTick.bump() }
        function onRowsRemoved()  { eventTick.bump() }
        function onModelReset()   { eventTick.bump() }
    }

    // Declarative binding: re-evaluates on AppController.selectedDate and
    // Theme.weekStart changes — no manual Connections needed.
    property var weekStart: startOfWeek(AppController.selectedDate)

    // Every event in the model, in the shape Segments.js reads. Its own
    // binding rather than a local inside buildDays(), because the all-day strip
    // needs the same list and buildDays() must not write a property it is
    // itself bound to.
    // One week in either direction. Named to match MonthView.step(), so the
    // keyboard can move the date without knowing which calendar is on screen.
    function step(dir) {
        const w = root.weekStart;
        if (!w || !w.getFullYear) return;
        AppController.selectedDate = new Date(w.getFullYear(), w.getMonth(), w.getDate() + (7 * dir));
    }

    // The rebuild is one chain, each stage reading only the one before it:
    // weekStart / eventRev -> spans -> eventDays -> days -> overlaps, strip.
    // When a stage also read weekStart itself, a week step re-ran it twice —
    // once with the old week's input and again when that caught up — and
    // every extra run of eventDays rebuilt all the event delegates (TIME-18).
    function buildSpans() {
        const _e = root.eventRev;
        const start = root.weekStart;
        if (!start || !start.getFullYear) return [];
        // A day either side of the week: a timed event that crosses midnight
        // reaches in from the Sunday before, and out into the Monday after.
        const from = new Date(start.getFullYear(), start.getMonth(), start.getDate() - 1);
        const to = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 7);
        // Copied out into a plain array once. What comes back is a C++ list
        // the engine converts element by element on every index — and
        // buildEventDays() reads each occurrence once per day column, so a
        // week of 420 occurrences cost ~3000 full conversions, 2.4 s per
        // step or save (TIME-18).
        const raw = AppController.eventOccurrences(from, to);
        const n = raw.length;
        const out = new Array(n);
        for (let i = 0; i < n; i++) out[i] = raw[i];
        out.weekStart = start;
        return out;
    }
    readonly property var spans: buildSpans()

    // The event half of the week, on its own binding: it depends on the
    // events and the week only, so a task that changes mid-drag (a running
    // timer ticks every second) does not rebuild the event delegates and
    // drop the block out from under the pointer.
    function buildEventDays() {
        const spans = root.spans;
        const start = spans.weekStart || root.weekStart;
        const days = [];
        const showWeekends = Theme.showWeekends;
        // Column of each day of the week, by its offset from weekStart; -1
        // for a hidden weekend.
        const colOf = [];
        for (let i = 0; i < 7; i++) {
            const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
            if (!showWeekends && (d.getDay() === 0 || d.getDay() === 6)) { colOf.push(-1); continue; }
            colOf.push(days.length);
            days.push({ date: d, events: [] });
        }
        // An event is no longer pinned to one day: it may be all-day, or run
        // past midnight. Each day takes the piece that lands on it, so a
        // 22:00-02:00 call draws on both days instead of only the one its
        // `date` happens to name.
        const linked = [];   // per column: task ids a linked event stands in for
        for (let k = 0; k < days.length; k++) linked.push({});
        // Which days of the week each occurrence covers, found once by
        // arithmetic (as MonthView does) rather than by asking Segments.js
        // about every occurrence on every day: that was seven rounds of Date
        // construction per occurrence and most of a week step's time with a
        // few hundred occurrences on screen (TIME-18). The pieces are the
        // ones Seg.segmentOn() cuts: the first day keeps the start, the last
        // day the end, a day in between runs 0-24.
        const first = Date.UTC(start.getFullYear(), start.getMonth(), start.getDate());
        const dayOf = (d) => Math.round((Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) - first) / 86400000);
        for (let i = 0; i < spans.length; i++) {
            const e = spans[i];
            if (!e.date || !e.date.getFullYear) continue;
            const a = dayOf(e.date);
            const b = (e.endDate && e.endDate.getFullYear) ? Math.max(a, dayOf(e.endDate)) : a;
            const strip = Seg.isStrip(e);   // all-day events live in the strip
            for (let off = Math.max(0, a); off <= Math.min(6, b); off++) {
                const k = colOf[off];
                if (k < 0) continue;
                if (e.taskId) linked[k][String(e.taskId)] = true;
                if (strip) continue;
                const segFirst = off === a;
                const segLast = off === b;
                days[k].events.push({
                    id: e.id, title: e.title, type: e.type,
                    start: segFirst ? e.start : 0, end: segLast ? e.end : 24,
                    attendees: e.attendees, date: e.date, context: e.context,
                    masterId: e.masterId || "", occurrenceDate: e.occurrenceDate,
                    occ: e,
                    // Unique per piece: the same event can appear on several
                    // days, and the overlap map is keyed by this. Keying it by
                    // event id would let Tuesday's piece overwrite Monday's.
                    key: e.id + "@" + k,
                    segFirst: segFirst, segLast: segLast
                });
            }
        }
        return { days: days, colOf: colOf, linked: linked, spans: spans, weekStart: start };
    }
    readonly property var eventDays: buildEventDays()

    function buildDays() {
        const _t = root.taskRev;
        const ev = root.eventDays;
        const start = ev.weekStart;
        const colOf = ev.colOf;
        const linked = ev.linked;
        const days = [];
        for (let k = 0; k < ev.days.length; k++)
            days.push({ date: ev.days[k].date, tasks: [], events: ev.days[k].events, blocks: [] });
        // Tasks: C++ hands over only those due or scheduled this week, with
        // the day already worked out — reading ten roles of every task in the
        // profile to find the few that are this week took seconds at 10k.
        // A deadline is a chip in the header; so is a date-only schedule. A
        // task scheduled at a clock time is a block on the grid, next to the
        // events, unless a linked event already stands in for it.
        const end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 6);
        const list = AppController.calendarTasks(start, end, root.showArchived);
        for (let i = 0; i < list.length; i++) {
            const t = list[i];
            if (!root.passesFilter(t)) continue;
            const dueCol = t.dueDay >= 0 ? colOf[t.dueDay] : -1;
            const schedCol = t.schedDay >= 0 ? colOf[t.schedDay] : -1;
            if (dueCol >= 0) days[dueCol].tasks.push(t);
            if (schedCol >= 0) {
                if (t.schedHour >= 0) {
                    if (!linked[schedCol][t.id]) {
                        const len = t.estimateMinutes > 0 ? t.estimateMinutes / 60 : 1;
                        days[schedCol].blocks.push({
                            id: t.id, title: t.title, priority: t.priority,
                            start: t.schedHour, end: Math.min(24, t.schedHour + Math.max(Theme.minEventHours, len)),
                            key: "task:" + t.id + "@" + schedCol
                        });
                    }
                } else if (schedCol !== dueCol) {
                    days[schedCol].tasks.push(Object.assign({ scheduled: true }, t));
                }
            }
        }
        const priRank = { P0: 0, P1: 1, P2: 2, P3: 3 };
        for (let k = 0; k < days.length; k++) {
            days[k].tasks.sort((a, b) => (priRank[a.priority] ?? 9) - (priRank[b.priority] ?? 9));
        }
        return days;
    }

    // Declarative: buildDays() reads weekStart, taskRev, eventRev, showArchived,
    // searchText, prioritiesFilter, and Theme.showWeekends — QML auto-tracks
    // those reads and re-evaluates this binding when any of them changes.
    readonly property var days: buildDays()

    // True when the visible week has neither task deadlines nor events, so the
    // grid would otherwise read as blank/broken.
    readonly property bool weekEmpty: {
        for (let i = 0; i < days.length; i++)
            if (days[i].tasks.length > 0 || days[i].events.length > 0 || days[i].blocks.length > 0) return false;
        return true;
    }

    // Flattened events with per-week day index so interactive drag/resize
    // can position them absolutely (and move across day columns).
    function buildFlatEvents() {
        const out = [];
        const days = root.eventDays.days;
        for (let i = 0; i < days.length; i++) {
            for (let j = 0; j < days[i].events.length; j++) {
                const e = days[i].events[j];
                out.push({
                    id: e.id, title: e.title, type: e.type,
                    start: e.start, end: e.end, attendees: e.attendees,
                    date: e.date, dayIndex: i, context: e.context || "",
                    key: e.key, segFirst: e.segFirst, segLast: e.segLast,
                    masterId: e.masterId || "", occurrenceDate: e.occurrenceDate,
                    // The occurrence as it came from the expansion: a click
                    // opens the editor on this, not on a copy missing half
                    // its fields.
                    occ: e.occ
                });
            }
        }
        return out;
    }
    readonly property var flatEvents: buildFlatEvents()

    function buildFlatBlocks() {
        const out = [];
        for (let i = 0; i < days.length; i++)
            for (let j = 0; j < days[i].blocks.length; j++)
                out.push(Object.assign({ dayIndex: i }, days[i].blocks[j]));
        return out;
    }
    readonly property var flatBlocks: buildFlatBlocks()

    // A drag or resize on one occurrence of a series asks which ones it is
    // for, like the editor does; anything else applies at once.
    SeriesScopeDialog { id: scopeAsk }
    readonly property alias scopePrompt: scopeAsk
    function _commitMove(occ, deltaHours, cancel) {
        if (!occ || Math.abs(deltaHours) < 1e-9) { if (cancel) cancel(); return; }
        if (String(occ.masterId || "").length > 0)
            scopeAsk.ask("move", (scope) => AppController.moveOccurrence(occ, deltaHours, scope), cancel);
        else
            AppController.moveOccurrence(occ, deltaHours, "this");
    }
    function _commitResize(occ, start, end, cancel) {
        if (!occ) { if (cancel) cancel(); return; }
        if (String(occ.masterId || "").length > 0)
            scopeAsk.ask("move", (scope) => AppController.resizeOccurrence(occ, start, end, scope), cancel);
        else
            AppController.resizeOccurrence(occ, start, end, "this");
    }
    function _daysBetween(a, b) {
        return Math.round((Date.UTC(b.getFullYear(), b.getMonth(), b.getDate())
                         - Date.UTC(a.getFullYear(), a.getMonth(), a.getDate())) / 86400000);
    }

    // ── Moving a task to another day or time (APP-249) ───────────────
    // A task's own block moves and stretches like an event; a chip in the
    // day headers goes to another day. Both change when the task is planned
    // (scheduledAt), never its deadline: a chip dropped on a day header keeps
    // the time it was planned for, one dropped on the hour grid takes that
    // hour. The hint at the pointer says what a drop would set; Esc cancels.
    // { id, scheduledAt, timed } of the chip being carried.
    property var chipDrag: null
    // { day: index, hour: -1 for a header (date only) } under the pointer.
    property var chipTarget: null

    function _chipTargetAt(x, y) {
        // `x`, `y` in gridHost's coordinates.
        const col = Math.floor((x - gridHost.gutterW) / gridHost.dayW);
        if (x < gridHost.gutterW || col < 0 || col >= root.days.length) return null;
        if (y >= 0 && y < headerBand.height) return { day: col, hour: -1 };
        const p = gridContent.mapFromItem(gridHost, x, y);
        const top = hourScroll.mapToItem(gridHost, 0, 0).y;
        if (y < top || y >= top + hourScroll.height) return null;
        return { day: col, hour: root.clampHour(root.snapHour(root.yToHour(p.y))) };
    }
    function _chipLanding(tgt) {
        if (!root.chipDrag || !tgt) return null;
        const day = root.days[tgt.day].date;
        if (tgt.hour < 0) return Resched.dropOnDay(day, root.chipDrag.scheduledAt, root.chipDrag.timed);
        return { when: Resched.atHour(day, Math.min(tgt.hour, 24 - Theme.minEventHours)), timed: true };
    }
    function beginChipDrag(t) {
        const full = AppController.taskById(t.id);
        root.chipDrag = { id: t.id, scheduledAt: full.scheduledAt, timed: !!full.scheduledHasTime };
        root.chipTarget = null;
        dragLayer.begin(t.id, t.title, true);
    }
    // `x`, `y` in gridHost's coordinates.
    function moveChipDrag(x, y) {
        if (!root.chipDrag) return;
        root.chipTarget = root._chipTargetAt(x, y);
        const land = root._chipLanding(root.chipTarget);
        const p = dragLayer.mapFromItem(gridHost, x, y);
        dragLayer.update(p.x, p.y, land ? dragLayer.describe("scheduled", land.when, land.timed) : I18n.t("drag.notHere"), !!land);
    }
    function endChipDrag() {
        const d = root.chipDrag;
        const land = root._chipLanding(root.chipTarget);
        root.chipDrag = null;
        root.chipTarget = null;
        dragLayer.finish();
        if (!d || !land) return false;
        return AppController.rescheduleTask(d.id, "scheduled", land.when, land.timed);
    }

    // The task the move keys act on: the chip or block that has the
    // keyboard, else the one under the pointer. Kept after a move rebuilds
    // the week, so the next press moves the same task again.
    property string keyTaskId: ""
    property var keyTaskDay: null
    property string hoverTaskId: ""
    property var hoverTaskDay: null
    function _keyTask() {
        if (root.keyTaskId) return { id: root.keyTaskId, day: root.keyTaskDay };
        if (root.hoverTaskId) return { id: root.hoverTaskId, day: root.hoverTaskDay };
        return null;
    }
    function moveKeyTaskByDays(days) {
        const k = root._keyTask();
        if (!k) return false;
        const t = AppController.taskById(k.id);
        if (!t || !t.id) return false;
        const r = Resched.shiftByDays(t.scheduledAt, t.scheduledHasTime, days, k.day, AppController.today);
        return AppController.rescheduleTask(k.id, "scheduled", r.when, r.timed);
    }
    function moveKeyTaskByTime(steps) {
        const k = root._keyTask();
        if (!k) return false;
        const t = AppController.taskById(k.id);
        const r = t ? Resched.shiftByTime(t.scheduledAt, t.scheduledHasTime, steps, Theme.snapMinutes) : null;
        return r ? AppController.rescheduleTask(k.id, "scheduled", r.when, true) : false;
    }

    // All-day events, packed into rows so bars stack instead of overlapping.
    // Computed for the whole week at once: a bar's row has to be the same in
    // every column it crosses, or a trip would jump up and down across the
    // week.
    function buildStrip() {
        const ev = root.eventDays;
        const spans = ev.spans;
        const dates = [];
        for (let i = 0; i < ev.days.length; i++) dates.push(ev.days[i].date);
        const laid = Seg.stripRows(spans, dates);
        const bars = [];
        for (let i = 0; i < spans.length; i++) {
            const e = spans[i];
            if (!Seg.isStrip(e)) continue;
            const ext = Seg.barExtent(e, dates);
            if (!ext) continue;
            bars.push({
                id: e.id, title: e.title, type: e.type,
                from: ext.from, span: ext.span,
                clippedStart: ext.clippedStart, clippedEnd: ext.clippedEnd,
                row: laid.rows[e.id] || 0,
                occ: e
            });
        }
        return { bars: bars, rows: laid.count };
    }
    readonly property var strip: buildStrip()

    // Side-by-side layout for events that share a time window. Two meetings at
    // 10:00 were drawn exactly on top of each other here: the second hid the
    // first, and only the top one could be clicked. The day grid had solved
    // this; this one had never been taught. Both call the same module now.
    function buildOverlaps() {
        const perDay = [];
        for (let i = 0; i < days.length; i++) {
            const list = [];
            for (let j = 0; j < days[i].events.length; j++) {
                const e = days[i].events[j];
                // As tall as it is drawn: a half-hour block grown to two
                // lines sits beside the meeting after it, not on top of it.
                list.push({ id: e.key, start: e.start, end: root.eventBlock(e.start, e.end).visualEnd });
            }
            for (let j = 0; j < days[i].blocks.length; j++) {
                const b = days[i].blocks[j];
                list.push({ id: b.key, start: b.start, end: b.end });
            }
            perDay.push(list);
        }
        return Overlap.computeByDay(perDay);
    }
    readonly property var overlaps: buildOverlaps()

    function totalTasks() {
        let n = 0;
        for (let i = 0; i < days.length; i++)
            for (let j = 0; j < days[i].tasks.length; j++) if (!days[i].tasks[j].scheduled) n++;
        return n;
    }
    function totalEvents() {
        let n = 0;
        for (let i = 0; i < days.length; i++) n += days[i].events.length;
        return n;
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.px(50)
            color: Theme.panel
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 1; color: Theme.border
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.sp2xl; anchors.rightMargin: Theme.sp2xl
                spacing: Theme.spMd

                // An arrow says nothing to a screen reader, and the tooltip
                // names the key as bound now (design audit DES-22).
                PillButton {
                    id: prevWeekBtn
                    objectName: "week-prev"
                    text: "←"
                    Accessible.name: I18n.t("miniweek.prevWeek")
                    ToolTip.visible: prevWeekBtn.hovered || prevWeekBtn.visualFocus
                    ToolTip.delay: 500
                    ToolTip.text: I18n.t("miniweek.prevWeek") + "  " + AppController.shortcutFor("cal.prev")
                    onClicked: root.step(-1)
                }
                ColumnLayout {
                    spacing: 1
                    Layout.alignment: Qt.AlignVCenter
                    RowLayout {
                        spacing: Theme.spLg
                        Text {
                            text: I18n.t("week.number").arg(AppController.isoWeekNumber(weekStart))
                            color: Theme.textDim
                            font.family: Theme.fontUi
                            font.features: Theme.tabularNums
                            font.pixelSize: Theme.fsSm
                        }
                        Text {
                            text: I18n.relang(AppController.shortDate(weekStart)) + " — " + AppController.shortDate(new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() + 6))
                            color: Theme.text
                            font.pixelSize: Theme.fsLg
                            font.weight: Theme.fwHeading
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: I18n.t("week.summary").arg(I18n.deadlines(root.totalTasks())).arg(I18n.events(root.totalEvents()))
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.features: Theme.tabularNums
                    font.pixelSize: Theme.fsSm
                }
                PillButton {
                    objectName: "week-rail-toggle"
                    visible: gridHost.railFits
                    text: I18n.t("week.rail.toggle")
                    selected: root.railWanted
                    onClicked: root.railWanted = !root.railWanted
                }
                PillButton {
                    id: todayBtn
                    text: I18n.t("common.today")
                    ToolTip.visible: todayBtn.hovered || todayBtn.visualFocus
                    ToolTip.delay: 500
                    ToolTip.text: I18n.t("common.today") + "  " + AppController.shortcutFor("cal.today")
                    onClicked: AppController.selectedDate = AppController.today
                }
                PillButton {
                    id: nextWeekBtn
                    objectName: "week-next"
                    text: "→"
                    Accessible.name: I18n.t("miniweek.nextWeek")
                    ToolTip.visible: nextWeekBtn.hovered || nextWeekBtn.visualFocus
                    ToolTip.delay: 500
                    ToolTip.text: I18n.t("miniweek.nextWeek") + "  " + AppController.shortcutFor("cal.next")
                    onClicked: root.step(1)
                }
            }
        }

        // 7-column grid
        Item {
            id: gridHost
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Header, gutter and chip rows grow with the interface scale
            // (APP-183): at 150 % the fixed 60px header put the date on top
            // of the weekday and the gutter cut "10:00" to "0:00".
            readonly property int gutterW: Theme.px(50)
            readonly property int dayCount: Math.max(1, root.days.length)
            // Narrowest a day column may get before the rail has to give way.
            readonly property int minDayW: 96
            // The rail takes its width off the grid rather than overlapping it,
            // and folds away whenever keeping it would squeeze the days below
            // minDayW. The old test was a fixed 900px, while dayW refused to go
            // under 120 — so at 1400px the week overflowed its own view and the
            // weekend was cut off behind the rail.
            readonly property bool railFits: (width - gutterW - 240) / dayCount >= minDayW
            readonly property bool railVisible: root.railWanted && railFits
            readonly property int railW: railVisible ? 240 : 0
            // Never wider than the space there is: every day stays on screen.
            readonly property int dayW: Math.max(40, Math.floor((width - gutterW - railW) / dayCount))
            // As tall as the busiest day needs, not a fixed block of empty rows.
            readonly property int dueRowH: {
                let most = 0;
                for (let i = 0; i < root.days.length; i++) {
                    const n = root.days[i].tasks.length;
                    most = Math.max(most, n === 0 ? Theme.px(28) : Theme.px(12 + Math.min(4, n) * 26 + (n > 4 ? 16 : 0)));
                }
                return Math.max(Theme.px(28), most);
            }

            // Sticky header band for the day-header + due-chips area
            Rectangle {
                id: headerBand
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                anchors.rightMargin: gridHost.railW
                height: Theme.px(60) + gridHost.dueRowH
                color: Theme.panel
                z: 2

                // gutter spacer
                Rectangle {
                    width: gridHost.gutterW; height: parent.height
                    color: Theme.panel
                    Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: Theme.border }
                    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: Theme.border }
                }

                Repeater {
                    model: root.days
                    delegate: Item {
                        id: headCol
                        objectName: "wvHeadCol"
                        required property var modelData
                        required property int index
                        x: gridHost.gutterW + index * gridHost.dayW
                        y: 0
                        width: gridHost.dayW
                        height: headerBand.height
                        readonly property bool isToday: root.isSameDay(modelData.date, AppController.today)
                        readonly property bool isWeekend: root.isWeekendDate(modelData.date)

                        Rectangle {
                            anchors.fill: parent
                            color: headCol.isToday ? Theme.accentSoft
                                 : headCol.isWeekend ? Theme.withAlpha(Theme.textDim, 0.04)
                                 : "transparent"
                            Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: Theme.border }
                            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: Theme.border }
                        }

                        // Day header. Clipped: at a large scale the "today"
                        // badge ran into the next day's name (APP-183).
                        Item {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            height: Theme.px(60)
                            clip: true
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: AppController.selectedDate = headCol.modelData.date
                            }
                            RowLayout {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                anchors.margins: Theme.spLg
                                spacing: Theme.spSm
                                Text {
                                    text: root.dowLabelsByJsDow[headCol.modelData.date.getDay()]
                                    color: headCol.isToday ? Theme.accentStrong : Theme.textDim
                                    font.pixelSize: Theme.fsMd
                                    font.weight: Theme.fwTitle
                                }
                                // Today is an accent dot and the word, not a
                                // filled plate: the brightest thing on the week
                                // was a label (APP-194, APP-198).
                                Rectangle {
                                    visible: headCol.isToday
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitWidth: 6; implicitHeight: 6
                                    radius: Theme.radiusPill
                                    color: Theme.accent
                                }
                                Text {
                                    objectName: "week-today-label"
                                    visible: headCol.isToday
                                    text: I18n.t("week.todayBadge")
                                    color: Theme.accentStrong
                                    font.pixelSize: Theme.fsSm
                                    font.weight: Theme.fwBody
                                }
                            }
                            Text {
                                anchors.left: parent.left; anchors.bottom: parent.bottom
                                anchors.leftMargin: Theme.spLg; anchors.bottomMargin: Theme.spSm
                                text: headCol.modelData.date.getDate()
                                color: headCol.isToday ? Theme.accentStrong : Theme.text
                                font.family: Theme.fontUi
                                font.features: Theme.tabularNums
                                font.pixelSize: Theme.fsXl
                                font.weight: Theme.fwTitle
                            }
                        }

                        // Due chips strip
                        Item {
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.top: parent.top; anchors.topMargin: Theme.px(60)
                            height: gridHost.dueRowH

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.spSm
                                spacing: Theme.spXs

                                Repeater {
                                    model: headCol.modelData.tasks.slice(0, 4)
                                    delegate: Rectangle {
                                        id: dueChip
                                        required property var modelData
                                        readonly property bool _selected: AppController.selectionCount >= 0
                                            && AppController.isTaskSelected(modelData.id)
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Theme.px(22)
                                        radius: Theme.radiusSm
                                        color: _selected ? Theme.withAlpha(Theme.accent, 0.18)
                                            : chipMA.containsMouse ? Theme.panel2 : Theme.panel3
                                        border.color: _selected ? Theme.accent
                                            : Theme.withAlpha(Theme.priorityColor(modelData.priority), 0.45)
                                        border.width: _selected ? 2 : 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Theme.spSm; anchors.rightMargin: Theme.spSm
                                            spacing: Theme.spXs
                                            Text {
                                                id: chipKey
                                                objectName: "week-due-key"
                                                // The key goes first when the chip
                                                // is narrow, so the title keeps
                                                // some words: at 125 % every chip
                                                // read "APP-105 …" (SCALE-7).
                                                visible: dueChip.width - 2 * Theme.spSm - chipKey.implicitWidth
                                                         - chipPri.implicitWidth - 2 * Theme.spXs >= Theme.px(64)
                                                // A mirrored issue reads by its
                                                // tracker key, not the synthetic
                                                // heap id (HEAP-117).
                                                text: (modelData.ticket && modelData.ticket.key)
                                                      ? modelData.ticket.key : modelData.id
                                                textFormat: Text.PlainText
                                                color: Theme.accentStrong
                                                font.family: Theme.fontUi
                                                font.features: Theme.tabularNums
                                                font.pixelSize: Theme.fsXs
                                            }
                                            Text {
                                                objectName: "week-due-title"
                                                Layout.fillWidth: true
                                                // A planned day (no deadline here) reads
                                                // as planned, not as due.
                                                text: (modelData.scheduled ? "◷ " : "") + modelData.title
                                                textFormat: Text.PlainText
                                                color: Theme.text
                                                font.pixelSize: Theme.fsXs
                                                elide: Text.ElideRight
                                            }
                                            // Priority by shape too (APP-185).
                                            Text {
                                                id: chipPri
                                                objectName: "week-due-priority"
                                                text: Theme.priorityMark(modelData.priority)
                                                color: Theme.priorityColor(modelData.priority)
                                                font.pixelSize: Theme.fsXs
                                            }
                                        }
                                        // The keyboard's way in (design audit
                                        // DES-19). Under the MouseArea and deaf
                                        // to the pointer: a click still goes
                                        // there, with its Ctrl / Shift.
                                        ClickArea {
                                            id: dueKey
                                            objectName: "week-due-" + dueChip.modelData.id
                                            label: dueChip.modelData.title
                                            showTip: false
                                            acceptedButtons: Qt.NoButton
                                            onActivated: chipMA.open()
                                            // The move keys act on it (APP-249).
                                            onActiveFocusChanged: if (activeFocus) {
                                                root.keyTaskId = dueChip.modelData.id;
                                                root.keyTaskDay = headCol.modelData.date;
                                            }
                                        }
                                        MouseArea {
                                            id: chipMA
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: root.chipDrag ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton
                                            // Dragged to another day or onto the
                                            // hour grid (APP-249).
                                            preventStealing: true
                                            property real pressX: 0
                                            property real pressY: 0
                                            // Esc ended this press's drag.
                                            property bool inert: false
                                            onPressed: (mouse) => { pressX = mouse.x; pressY = mouse.y; inert = false; }
                                            onPositionChanged: (mouse) => {
                                                if (!pressed || inert) return;
                                                if (!root.chipDrag) {
                                                    if (Math.abs(mouse.x - pressX) < 6 && Math.abs(mouse.y - pressY) < 6) return;
                                                    root.beginChipDrag(dueChip.modelData);
                                                }
                                                const p = chipMA.mapToItem(gridHost, mouse.x, mouse.y);
                                                root.moveChipDrag(p.x, p.y);
                                            }
                                            onReleased: {
                                                if (root.chipDrag) { inert = true; root.endChipDrag(); }
                                            }
                                            onCanceled: if (root.chipDrag) { root.chipDrag = null; dragLayer.finish(); }
                                            onContainsMouseChanged: {
                                                if (containsMouse) { root.hoverTaskId = dueChip.modelData.id; root.hoverTaskDay = headCol.modelData.date; }
                                                else if (root.hoverTaskId === dueChip.modelData.id) root.hoverTaskId = "";
                                            }
                                            Connections {
                                                target: dragLayer
                                                function onCanceled() { if (chipMA.pressed) chipMA.inert = true; }
                                            }
                                            // A plain click, and Return on the
                                            // ClickArea above.
                                            function open() {
                                                if (AppController.selectionCount > 0) AppController.clearSelection();
                                                root.taskClicked(modelData.id);
                                            }
                                            onClicked: (mouse) => {
                                                if (inert) { inert = false; return; }
                                                const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
                                                const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                                                if (ctrl) {
                                                    AppController.toggleTaskSelection(modelData.id);
                                                } else if (shift) {
                                                    root._rangeSelect(modelData.id);
                                                } else {
                                                    chipMA.open();
                                                }
                                            }
                                            // The full title on Tab too (APP-184).
                                            ToolTip.visible: containsMouse || dueKey.activeFocus
                                            ToolTip.delay: 400
                                            ToolTip.text: modelData.title
                                        }
                                    }
                                }
                                // The overflow count was dead text — the only way
                                // to reach the hidden deadlines was to guess.
                                // It selects the day, which is what the day view
                                // on the right follows.
                                Text {
                                    visible: headCol.modelData.tasks.length > 4
                                    text: I18n.t("week.more").arg(headCol.modelData.tasks.length - 4)
                                    color: moreMA.hovered ? Theme.accentStrong : Theme.textDim
                                    font.family: Theme.fontUi
                                    font.features: Theme.tabularNums
                                    font.pixelSize: Theme.fsXs
                                    ClickArea {
                                        id: moreMA
                                        label: I18n.t("cal.moreOnDay").arg(headCol.modelData.tasks.length - 4)
                                        onActivated: AppController.selectedDate = headCol.modelData.date
                                    }
                                }
                                Text {
                                    visible: headCol.modelData.tasks.length === 0
                                    text: "·"
                                    color: Theme.textDim
                                    font.pixelSize: Theme.fsLg
                                    horizontalAlignment: Text.AlignHCenter
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                Item { Layout.fillHeight: true }
                            }
                        }
                    }
                }
            }

            // All-day events. No hours, so no place on the grid; a strip under
            // the header is where every calendar puts them, and it keeps them
            // visible however far the grid is scrolled.
            Rectangle {
                id: weekStrip
                objectName: "allday-strip"
                anchors.top: headerBand.bottom
                anchors.left: parent.left; anchors.right: parent.right
                anchors.rightMargin: gridHost.railW
                height: visible ? (root.strip.rows * Theme.px(24) + 8) : 0
                visible: root.strip.rows > 0
                color: Theme.panel
                z: 2

                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    height: 1; color: Theme.border
                }

                Repeater {
                    model: root.strip.bars
                    Rectangle {
                        id: weekBar
                        required property var modelData
                        objectName: "allday-" + weekBar.modelData.id
                        x: gridHost.gutterW + weekBar.modelData.from * gridHost.dayW + 2
                        y: 4 + weekBar.modelData.row * Theme.px(24)
                        width: weekBar.modelData.span * gridHost.dayW - 4
                        height: Theme.px(22)
                        // Square off the clipped end so a bar that runs past
                        // the week reads as continuing rather than ending here.
                        radius: Theme.radiusSm
                        color: Theme.withAlpha(Theme.eventColor(weekBar.modelData.type || "sync"), 0.16)

                        Rectangle {
                            visible: !weekBar.modelData.clippedStart
                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                            width: 3; radius: 1
                            color: Theme.eventColor(weekBar.modelData.type || "sync")
                        }

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: weekBar.modelData.clippedStart ? 16 : 10
                            anchors.rightMargin: Theme.spMd
                            verticalAlignment: Text.AlignVCenter
                            // A bar continued from last week says so, so the
                            // title is not read as starting on Monday.
                            text: (weekBar.modelData.clippedStart ? "‹ " : "")
                                  + (weekBar.modelData.title || "")
                                  + (weekBar.modelData.clippedEnd ? " ›" : "")
                            color: Theme.text
                            font.pixelSize: Theme.fsMd
                            elide: Text.ElideRight
                        }

                        ClickArea {
                            label: weekBar.modelData.title || ""
                            showTip: false
                            onActivated: root.eventClicked(weekBar.modelData.id, weekBar.modelData.occ)
                        }
                    }
                }
            }

            // What still needs a slot, beside the grid that has the slots.
            UnscheduledRail {
                id: unscheduledRail
                objectName: "unscheduled-rail"
                visible: gridHost.railVisible
                anchors.top: parent.top; anchors.bottom: parent.bottom
                anchors.right: parent.right
                width: gridHost.railW
                // From the week's dates alone: read off `root.days`, every
                // task change handed the rail a new array and it rebuilt
                // twice, once for the change and once for the array (APP-203).
                days: {
                    const out = [];
                    const ev = root.eventDays.days;
                    for (let i = 0; i < ev.length; i++) out.push(ev[i].date);
                    return out;
                }
                searchText: root.searchText
                taskRev: root.taskRev
                eventRev: root.eventRev
                onTaskClicked: (id) => root.taskClicked(id)
                z: 3
            }

            // Scrollable hour grid
            ScrollView {
                id: hourScroll
                objectName: "week-hour-scroll"
                // Open on the working day (or the current hour, if that is
                // earlier), not on midnight.
                Component.onCompleted: workdayScroll.start()
                anchors.left: parent.left; anchors.right: parent.right
                anchors.rightMargin: gridHost.railW
                anchors.top: weekStrip.bottom; anchors.bottom: parent.bottom
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                // Said outright: the grid has a height but no implicit one,
                // so the ScrollView's own guess was 0 and the first scroll to
                // the working day had nothing to scroll.
                contentWidth: gridContent.width
                contentHeight: gridContent.height

                Item {
                    id: gridContent
                    width: gridHost.width - gridHost.railW
                    height: (root.hoursEnd - root.hoursStart) * root.hourH + 4

                    // Hour-label gutter
                    Item {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: gridHost.gutterW

                        Repeater {
                            model: root.hoursEnd - root.hoursStart
                            Text {
                                required property int index
                                x: 0
                                // Centred on its hour line, but never above the
                                // top of the scroll area — the first label used
                                // to be cut in half by the sticky header.
                                y: Math.max(0, index * root.hourH - 6)
                                width: gridHost.gutterW - 8
                                horizontalAlignment: Text.AlignRight
                                text: Theme.fmtHour(root.hoursStart + index)
                                color: Theme.textDim
                                font.family: Theme.fontUi
                                font.features: Theme.tabularNums
                                font.pixelSize: Theme.fsXs
                            }
                        }
                        Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: Theme.border }
                    }

                    // 7 day columns
                    Repeater {
                        model: root.days
                        delegate: Item {
                            id: dayCol
                            required property var modelData
                            required property int index
                            x: gridHost.gutterW + index * gridHost.dayW
                            y: 0
                            width: gridHost.dayW
                            height: (root.hoursEnd - root.hoursStart) * root.hourH
                            readonly property bool isToday: root.isSameDay(modelData.date, AppController.today)
                            readonly property bool isWeekend: root.isWeekendDate(modelData.date)

                            Rectangle {
                                anchors.fill: parent
                                color: dayCol.isToday ? Theme.withAlpha(Theme.accent, 0.04)
                                     : dayCol.isWeekend ? Theme.withAlpha(Theme.textDim, 0.04)
                                     : "transparent"
                                Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: Theme.border }
                            }

                            // Outside the working day. Dimmed, not missing.
                            Repeater {
                                model: root.hoursEnd - root.hoursStart
                                Rectangle {
                                    required property int index
                                    visible: index < root.workStart || index >= root.workEnd
                                    // The column by id: under Bound a Repeater's
                                    // row is built before it has a parent.
                                    width: dayCol.width
                                    y: index * root.hourH
                                    height: root.hourH
                                    color: Theme.bg2
                                    opacity: 0.55
                                }
                            }

                            // Hour separators
                            Repeater {
                                model: root.hoursEnd - root.hoursStart
                                Rectangle {
                                    required property int index
                                    width: dayCol.width
                                    y: index * root.hourH
                                    height: 1
                                    color: Theme.border
                                    opacity: 0.5
                                }
                            }

                            // Drop a card from the board onto an hour to
                            // time-block it. The day grid had this; the week
                            // is where a week's worth of planning happens.
                            DropArea {
                                objectName: "week-drop-" + dayCol.index
                                anchors.fill: parent
                                property real hoverY: -1
                                onPositionChanged: (drag) => hoverY = drag.y
                                onExited: hoverY = -1
                                onDropped: (drop) => {
                                    hoverY = -1;
                                    const src = drop.source;
                                    if (!src || !src.taskId) return;
                                    AppController.scheduleTask(String(src.taskId),
                                                               root.clampHour(root.snapHour(root.yToHour(drop.y))),
                                                               dayCol.modelData.date);
                                    drop.accept(Qt.MoveAction);
                                }
                                Rectangle {
                                    visible: parent.hoverY >= 0
                                    x: 2; width: parent.width - 4
                                    y: parent.hoverY - 1
                                    height: 2
                                    radius: 1
                                    color: Theme.accent
                                }
                            }

                            // Click an empty slot to add something there. It
                            // opens the editor rather than saving an untitled
                            // event, so the user names it before it exists.
                            MouseArea {
                                anchors.fill: parent
                                z: -1
                                acceptedButtons: Qt.LeftButton
                                onClicked: (mouse) => {
                                    const h = root.clampHour(root.snapHour(root.yToHour(mouse.y)));
                                    root.createRequested(h, dayCol.modelData.date);
                                }
                            }

                            // Where the day is now. Only on today, and only
                            // the column it belongs to.
                            Rectangle {
                                visible: dayCol.isToday
                                anchors.left: parent.left; anchors.right: parent.right
                                y: (root.now.getHours() + root.now.getMinutes() / 60 - root.hoursStart) * root.hourH
                                height: 2
                                color: Theme.nowLine
                                z: 9
                                Rectangle {
                                    x: -3; y: -2
                                    width: 6; height: 6; radius: 3
                                    color: Theme.nowLine
                                }
                            }
                        }
                    }

                    // Flat interactive events layer — declared after the day
                    // columns so it sits on top, and uses absolute coords
                    // (dayIndex × dayW) to allow drag between columns.
                    Repeater {
                        model: root.flatEvents
                        delegate: Rectangle {
                            id: weEv
                            required property var modelData

                            property real dragDx: 0
                            property real dragDy: 0
                            property real pendingStartH: NaN
                            property real pendingEndH:   NaN

                            readonly property int effDayIndex: {
                                const raw = modelData.dayIndex + Math.round(dragDx / gridHost.dayW);
                                return Math.max(0, Math.min(root.days.length - 1, raw));
                            }
                            readonly property real effStart: !isNaN(pendingStartH) ? pendingStartH : modelData.start
                            readonly property real effEnd:   !isNaN(pendingEndH)   ? pendingEndH   : modelData.end

                            // Its slot within the day's overlap cluster. A
                            // dragged event goes full width: it is following
                            // the pointer, not sitting in a cluster any more.
                            readonly property var _slot: root.overlaps[modelData.key] || ({ col: 0, cols: 1 })
                            readonly property int _cols: (dragDx !== 0 || dragDy !== 0) ? 1 : Math.max(1, _slot.cols)
                            readonly property int _col:  (dragDx !== 0 || dragDy !== 0) ? 0 : _slot.col
                            // Tiled, or cascaded once lanes would get
                            // narrower than a readable title (VISU-15).
                            readonly property var _lane: Overlap.lane(weEv._col, weEv._cols, gridHost.dayW - 4)

                            x: gridHost.gutterW + weEv.effDayIndex * gridHost.dayW + 2 + weEv._lane.x
                            y: (weEv.effStart - root.hoursStart) * root.hourH + weEv.dragDy
                            width: weEv._lane.w - (weEv._cols > 1 ? 2 : 0)
                            // Half an hour or more is at least two lines high,
                            // the time small on top of the title; anything
                            // shorter is one line (APP-199). A half-hour
                            // meeting used to be 17px, its title clipped away.
                            readonly property var _block: root.eventBlock(effStart, effEnd)
                            height: weEv._block.height
                            readonly property bool compact: !weEv._block.twoLine
                            radius: Theme.radiusSm
                            color: Theme.withAlpha(Theme.eventColor(modelData.type), 0.18)
                            border.color: Theme.withAlpha(Theme.eventColor(modelData.type), 0.55)
                            border.width: 1
                            // A later lane is drawn over an earlier one where
                            // they cascade; a dragged event above them all.
                            z: (weEv.dragDx !== 0 || weEv.dragDy !== 0) ? 7 : 5 + weEv._col / Math.max(1, weEv._cols)

                            Rectangle {
                                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                width: 3
                                color: Theme.eventColor(weEv.modelData.type)
                                radius: 1
                            }
                            Column {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spMd; anchors.rightMargin: Theme.spSm; anchors.topMargin: Theme.sp2xs
                                spacing: 0
                                clip: true
                                Text {
                                    visible: !weEv.compact
                                    text: Theme.fmtHour(weEv.effStart)
                                    color: Theme.textMuted
                                    font.family: Theme.fontUi
                                    font.features: Theme.tabularNums
                                    font.pixelSize: Theme.fsXs
                                }
                                RowLayout {
                                    id: evLine
                                    width: parent.width
                                    spacing: Theme.spXs
                                    // On one line the time and the context give
                                    // way before the title does: a 15-minute
                                    // meeting beside a focus block read "15:00"
                                    // and nothing else (SCALE-7). The time is on
                                    // the block's edge in the grid anyway.
                                    readonly property bool roomy: evLine.width - evTime.implicitWidth - Theme.spXs >= Theme.px(64)
                                    Text {
                                        id: evTime
                                        objectName: "week-event-time"
                                        visible: weEv.compact && evLine.roomy
                                        text: Theme.fmtHour(weEv.effStart)
                                        color: Theme.textMuted
                                        font.family: Theme.fontUi
                                        font.features: Theme.tabularNums
                                        font.pixelSize: Theme.fsXs
                                    }
                                    Text {
                                        visible: (weEv.modelData.context || "").length > 0 && evLine.roomy
                                        text: weEv.modelData.context
                                        color: Theme.textMuted
                                        font.pixelSize: Theme.fsXs
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: parent.width * 0.5
                                    }
                                    Rectangle {
                                        visible: (weEv.modelData.context || "").length > 0 && evLine.roomy
                                        Layout.preferredWidth: 5; Layout.preferredHeight: 5
                                        radius: 2.5
                                        color: Theme.eventColor(weEv.modelData.type)
                                    }
                                    Text {
                                        objectName: "week-event-title"
                                        Layout.fillWidth: true
                                        text: weEv.modelData.title
                                        color: Theme.text
                                        font.pixelSize: weEv.compact ? Theme.fsXs : Theme.fsSm
                                        font.weight: weEv.compact ? Theme.fwBody : Theme.fwTitle
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // Opening from the keyboard (design audit DES-19).
                            // Under the drag areas and deaf to the pointer, so
                            // a press still starts a move or a resize.
                            ClickArea {
                                objectName: "week-event-open"
                                label: weEv.modelData.title
                                showTip: false
                                acceptedButtons: Qt.NoButton
                                cursorShape: Qt.ArrowCursor
                                onActivated: weMove.open()
                            }

                            // Move-drag — vertical = time, horizontal = day.
                            MouseArea {
                                id: weMove
                                anchors.fill: parent
                                anchors.topMargin: Theme.spSm
                                anchors.bottomMargin: Theme.spSm
                                cursorShape: didDrag ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                // The ScrollView's Flickable took the vertical
                                // drag: a move in time or any resize snapped back.
                                preventStealing: true
                                property real grabX: 0
                                property real grabY: 0
                                property real baseX: 0
                                property real baseY: 0
                                property bool didDrag: false
                                // A click that did not drag, and Return on the
                                // ClickArea below.
                                function open() { root.eventClicked(weEv.modelData.id, weEv.modelData.occ); }

                                onPressed: (mouse) => {
                                    grabX = mouse.x; grabY = mouse.y;
                                    baseX = weEv.x; baseY = weEv.y;
                                    didDrag = false;
                                    weEv.dragDx = 0; weEv.dragDy = 0;
                                }
                                onPositionChanged: (mouse) => {
                                    const pt = weMove.mapToItem(gridContent, mouse.x, mouse.y);
                                    const wantX = pt.x - grabX;
                                    // grabY is weMove-local; its origin sits topMargin below the event
                                    // top while pt/baseY are gridContent-absolute. Subtract the inset so
                                    // a still pointer yields dy == 0 (no constant +6px bias). No left
                                    // margin, so wantX needs no such correction.
                                    const wantY = pt.y - grabY - weMove.anchors.topMargin;
                                    const dx = wantX - baseX;
                                    const dy = wantY - baseY;
                                    if (!didDrag && (Math.abs(dx) > 5 || Math.abs(dy) > 5)) didDrag = true;
                                    if (didDrag) {
                                        weEv.dragDx = dx;
                                        weEv.dragDy = dy;
                                    }
                                }
                                onReleased: {
                                    if (didDrag) {
                                        // A shift of the whole event by what
                                        // this piece moved: hours, plus whole
                                        // days by date (hidden weekends make
                                        // columns and days differ).
                                        const dur = weEv.modelData.end - weEv.modelData.start;
                                        const newY = (weEv.modelData.start - root.hoursStart) * root.hourH + weEv.dragDy;
                                        let ns = root.snapHour(root.yToHour(newY));
                                        ns = Math.max(root.hoursStart, Math.min(ns, root.hoursEnd - dur));
                                        const dayShift = root._daysBetween(root.days[weEv.modelData.dayIndex].date,
                                                                           root.days[weEv.effDayIndex].date);
                                        didDrag = false;
                                        root._commitMove(weEv.modelData.occ, (ns - weEv.modelData.start) + dayShift * 24,
                                                         () => { if (weEv) { weEv.dragDx = 0; weEv.dragDy = 0; } });
                                        return;
                                    }
                                    weMove.open();
                                    weEv.dragDx = 0; weEv.dragDy = 0;
                                    didDrag = false;
                                }
                                onCanceled: { weEv.dragDx = 0; weEv.dragDy = 0; didDrag = false; }
                            }

                            // Top resize handle.
                            MouseArea {
                                id: weTop
                                // A piece of an overnight event has no edge of
                                // its own on this day, as in the day panel.
                                enabled: weEv.modelData.segFirst && weEv.modelData.segLast
                                visible: enabled
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                height: 6
                                cursorShape: Qt.SizeVerCursor
                                preventStealing: true
                                property bool resizing: false
                                onPressed: { resizing = true; weEv.pendingStartH = weEv.modelData.start; }
                                onPositionChanged: (mouse) => {
                                    if (!resizing) return;
                                    const pt = weTop.mapToItem(gridContent, mouse.x, mouse.y);
                                    const h = root.snapHour(root.yToHour(pt.y));
                                    const clamped = Math.min(h, weEv.modelData.end - Theme.minEventHours);
                                    weEv.pendingStartH = Math.max(root.hoursStart, clamped);
                                }
                                onReleased: {
                                    if (!resizing) return;
                                    resizing = false;
                                    const ns = weEv.pendingStartH;
                                    if (Math.abs(ns - weEv.modelData.start) < 1e-9) { weEv.pendingStartH = NaN; return; }
                                    root._commitResize(weEv.modelData.occ, ns, weEv.modelData.end, () => { if (weEv) weEv.pendingStartH = NaN; });
                                }
                                onCanceled: { resizing = false; weEv.pendingStartH = NaN; }
                            }

                            // Bottom resize handle.
                            MouseArea {
                                id: weBot
                                enabled: weEv.modelData.segFirst && weEv.modelData.segLast
                                visible: enabled
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                height: 6
                                cursorShape: Qt.SizeVerCursor
                                preventStealing: true
                                property bool resizing: false
                                onPressed: { resizing = true; weEv.pendingEndH = weEv.modelData.end; }
                                onPositionChanged: (mouse) => {
                                    if (!resizing) return;
                                    const pt = weBot.mapToItem(gridContent, mouse.x, mouse.y);
                                    const h = root.snapHour(root.yToHour(pt.y));
                                    const clamped = Math.max(h, weEv.modelData.start + Theme.minEventHours);
                                    weEv.pendingEndH = Math.min(root.hoursEnd, clamped);
                                }
                                onReleased: {
                                    if (!resizing) return;
                                    resizing = false;
                                    const ne = weEv.pendingEndH;
                                    if (Math.abs(ne - weEv.modelData.end) < 1e-9) { weEv.pendingEndH = NaN; return; }
                                    root._commitResize(weEv.modelData.occ, weEv.modelData.start, ne, () => { if (weEv) weEv.pendingEndH = NaN; });
                                }
                                onCanceled: { resizing = false; weEv.pendingEndH = NaN; }
                            }
                        }
                    }

                    // Tasks scheduled at a clock time. The week used to show
                    // only deadlines, so a task planned for Thursday 14:00
                    // without one appeared nowhere but the day panel.
                    Repeater {
                        model: root.flatBlocks
                        delegate: Rectangle {
                            id: wkBlock
                            required property var modelData
                            objectName: "week-taskblock-" + wkBlock.modelData.id
                            // Moved and stretched like an event (APP-249): the
                            // drag follows the pointer, the drop sets when the
                            // task is planned, a stretch sets its estimate.
                            property real dragDx: 0
                            property real dragDy: 0
                            property real pendingStartH: NaN
                            property real pendingEndH: NaN
                            readonly property bool moving: dragDx !== 0 || dragDy !== 0
                            readonly property int effDayIndex: Math.max(0, Math.min(root.days.length - 1,
                                wkBlock.modelData.dayIndex + Math.round(wkBlock.dragDx / gridHost.dayW)))
                            readonly property real effStart: !isNaN(pendingStartH) ? pendingStartH : modelData.start
                            readonly property real effEnd: !isNaN(pendingEndH) ? pendingEndH : modelData.end
                            readonly property var _slot: root.overlaps[wkBlock.modelData.key] || ({ col: 0, cols: 1 })
                            readonly property int _cols: wkBlock.moving ? 1 : Math.max(1, wkBlock._slot.cols)
                            readonly property var _lane: Overlap.lane(wkBlock.moving ? 0 : wkBlock._slot.col, wkBlock._cols, gridHost.dayW - 4)
                            x: gridHost.gutterW + wkBlock.effDayIndex * gridHost.dayW + 2 + wkBlock._lane.x
                            y: (wkBlock.effStart - root.hoursStart) * root.hourH + wkBlock.dragDy
                            width: wkBlock._lane.w - (wkBlock._cols > 1 ? 2 : 0)
                            height: Math.max(18, (wkBlock.effEnd - wkBlock.effStart) * root.hourH - 2)
                            radius: Theme.radiusSm
                            color: Theme.withAlpha(Theme.eventColor("focus"), wkBlockMA.hovered || wkMove.containsMouse ? 0.18 : 0.10)
                            border.color: Theme.withAlpha(Theme.eventColor("focus"), 0.6)
                            border.width: 1
                            // Task blocks sit under events (4 < 5), as in the
                            // day grid; a carried one above everything.
                            z: wkBlock.moving ? 7 : 4 + wkBlock._slot.col / Math.max(1, wkBlock._slot.cols)

                            // Where the block would land, for the hint and the drop.
                            function landing() {
                                const dur = wkBlock.modelData.end - wkBlock.modelData.start;
                                const newY = (wkBlock.modelData.start - root.hoursStart) * root.hourH + wkBlock.dragDy;
                                let ns = root.snapHour(root.yToHour(newY));
                                ns = Math.max(root.hoursStart, Math.min(ns, root.hoursEnd - dur));
                                return { day: root.days[wkBlock.effDayIndex].date, start: ns };
                            }
                            function resetDrag() {
                                wkBlock.dragDx = 0; wkBlock.dragDy = 0;
                                wkBlock.pendingStartH = NaN; wkBlock.pendingEndH = NaN;
                            }
                            function hintAt(mouseItem, mx, my, text) {
                                const p = dragLayer.mapFromItem(mouseItem, mx, my);
                                dragLayer.update(p.x, p.y, text, true);
                            }
                            function rangeText(day, s, e) {
                                return dragLayer.describe("scheduled", Resched.atHour(day, s), true) + "–" + Theme.fmtHour(e);
                            }
                            Connections {
                                target: dragLayer
                                function onCanceled() {
                                    if (!wkMove.pressed && !wkTop.pressed && !wkBot.pressed) return;
                                    wkBlock.resetDrag();
                                    wkMove.inert = true; wkTop.inert = true; wkBot.inert = true;
                                }
                            }

                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spMd; anchors.rightMargin: Theme.spSm; anchors.topMargin: Theme.sp2xs
                                text: "▸ " + (wkBlock.modelData.title || "")
                                color: Theme.text
                                font.pixelSize: Theme.fsXs
                                font.weight: Theme.fwTitle
                                elide: Text.ElideRight
                            }
                            // Opening from the keyboard; under the drag areas
                            // and deaf to the pointer, like an event's.
                            ClickArea {
                                id: wkBlockMA
                                label: wkBlock.modelData.title || ""
                                showTip: false
                                acceptedButtons: Qt.NoButton
                                cursorShape: Qt.ArrowCursor
                                onActivated: root.taskClicked(wkBlock.modelData.id)
                                onActiveFocusChanged: if (activeFocus) {
                                    root.keyTaskId = wkBlock.modelData.id;
                                    root.keyTaskDay = root.days[wkBlock.modelData.dayIndex].date;
                                }
                            }
                            // Move — vertical = time, horizontal = day.
                            MouseArea {
                                id: wkMove
                                objectName: "week-taskblock-move"
                                anchors.fill: parent
                                anchors.topMargin: Theme.spSm
                                anchors.bottomMargin: Theme.spSm
                                hoverEnabled: true
                                cursorShape: didDrag ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                preventStealing: true
                                property real grabX: 0
                                property real grabY: 0
                                property real baseX: 0
                                property real baseY: 0
                                property bool didDrag: false
                                property bool inert: false
                                onContainsMouseChanged: {
                                    if (containsMouse) { root.hoverTaskId = wkBlock.modelData.id; root.hoverTaskDay = root.days[wkBlock.modelData.dayIndex].date; }
                                    else if (root.hoverTaskId === wkBlock.modelData.id) root.hoverTaskId = "";
                                }
                                onPressed: (mouse) => {
                                    grabX = mouse.x; grabY = mouse.y;
                                    baseX = wkBlock.x; baseY = wkBlock.y;
                                    didDrag = false; inert = false;
                                    wkBlock.resetDrag();
                                }
                                onPositionChanged: (mouse) => {
                                    if (!pressed || inert) return;
                                    const pt = wkMove.mapToItem(gridContent, mouse.x, mouse.y);
                                    const dx = pt.x - grabX - baseX;
                                    const dy = pt.y - grabY - wkMove.anchors.topMargin - baseY;
                                    if (!didDrag && (Math.abs(dx) > 5 || Math.abs(dy) > 5)) {
                                        didDrag = true;
                                        dragLayer.begin(wkBlock.modelData.id, wkBlock.modelData.title, false);
                                    }
                                    if (!didDrag) return;
                                    wkBlock.dragDx = dx;
                                    wkBlock.dragDy = dy;
                                    const l = wkBlock.landing();
                                    wkBlock.hintAt(wkMove, mouse.x, mouse.y, dragLayer.describe("scheduled", Resched.atHour(l.day, l.start), true));
                                }
                                onReleased: {
                                    if (inert) return;
                                    if (didDrag) {
                                        const l = wkBlock.landing();
                                        didDrag = false;
                                        dragLayer.finish();
                                        const changed = AppController.rescheduleTask(wkBlock.modelData.id, "scheduled", Resched.atHour(l.day, l.start), true);
                                        if (!changed && wkBlock) wkBlock.resetDrag();
                                        return;
                                    }
                                    root.taskClicked(wkBlock.modelData.id);
                                }
                                onCanceled: { wkBlock.resetDrag(); didDrag = false; dragLayer.finish(); }
                            }
                            // Top edge: the start moves, the end stays.
                            MouseArea {
                                id: wkTop
                                objectName: "week-taskblock-top"
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                height: Theme.spSm
                                cursorShape: Qt.SizeVerCursor
                                preventStealing: true
                                property bool inert: false
                                // By how far the pointer moved, not where it is:
                                // the handle sits a few pixels inside the edge.
                                property real pressY: 0
                                onPressed: (mouse) => {
                                    inert = false;
                                    pressY = wkTop.mapToItem(gridContent, mouse.x, mouse.y).y;
                                    wkBlock.pendingStartH = wkBlock.modelData.start;
                                    dragLayer.begin(wkBlock.modelData.id, wkBlock.modelData.title, false);
                                }
                                onPositionChanged: (mouse) => {
                                    if (!pressed || inert) return;
                                    const pt = wkTop.mapToItem(gridContent, mouse.x, mouse.y);
                                    const h = Math.min(root.snapHour(wkBlock.modelData.start + (pt.y - wkTop.pressY) / root.hourH),
                                                       wkBlock.modelData.end - Theme.minEventHours);
                                    wkBlock.pendingStartH = Math.max(root.hoursStart, h);
                                    wkBlock.hintAt(wkTop, mouse.x, mouse.y,
                                                   wkBlock.rangeText(root.days[wkBlock.modelData.dayIndex].date, wkBlock.pendingStartH, wkBlock.modelData.end));
                                }
                                onReleased: {
                                    dragLayer.finish();
                                    if (inert) return;
                                    const ns = wkBlock.pendingStartH;
                                    if (isNaN(ns) || Math.abs(ns - wkBlock.modelData.start) < 1e-9) { wkBlock.resetDrag(); return; }
                                    AppController.resizeTaskBlock(wkBlock.modelData.id, root.days[wkBlock.modelData.dayIndex].date, ns, wkBlock.modelData.end);
                                }
                                onCanceled: { wkBlock.resetDrag(); dragLayer.finish(); }
                            }
                            // Bottom edge: the length, which becomes the estimate.
                            MouseArea {
                                id: wkBot
                                objectName: "week-taskblock-bottom"
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                height: Theme.spSm
                                cursorShape: Qt.SizeVerCursor
                                preventStealing: true
                                property bool inert: false
                                // By how far the pointer moved, not where it is:
                                // the handle sits a few pixels inside the edge.
                                property real pressY: 0
                                onPressed: (mouse) => {
                                    inert = false;
                                    pressY = wkBot.mapToItem(gridContent, mouse.x, mouse.y).y;
                                    wkBlock.pendingEndH = wkBlock.modelData.end;
                                    dragLayer.begin(wkBlock.modelData.id, wkBlock.modelData.title, false);
                                }
                                onPositionChanged: (mouse) => {
                                    if (!pressed || inert) return;
                                    const pt = wkBot.mapToItem(gridContent, mouse.x, mouse.y);
                                    const h = Math.max(root.snapHour(wkBlock.modelData.end + (pt.y - wkBot.pressY) / root.hourH),
                                                       wkBlock.modelData.start + Theme.minEventHours);
                                    wkBlock.pendingEndH = Math.min(root.hoursEnd, h);
                                    wkBlock.hintAt(wkBot, mouse.x, mouse.y,
                                                   wkBlock.rangeText(root.days[wkBlock.modelData.dayIndex].date, wkBlock.modelData.start, wkBlock.pendingEndH));
                                }
                                onReleased: {
                                    dragLayer.finish();
                                    if (inert) return;
                                    const ne = wkBlock.pendingEndH;
                                    if (isNaN(ne) || Math.abs(ne - wkBlock.modelData.end) < 1e-9) { wkBlock.resetDrag(); return; }
                                    AppController.resizeTaskBlock(wkBlock.modelData.id, root.days[wkBlock.modelData.dayIndex].date, wkBlock.modelData.start, ne);
                                }
                                onCanceled: { wkBlock.resetDrag(); dragLayer.finish(); }
                            }
                        }
                    }
                }
            }
        }
    }

    // Empty-week hint — shown only when the week has no tasks and no events, so
    // the grid does not read as blank. Non-interactive: a click goes through
    // to the slot under it, which is what the hint says to do.
    EmptyState {
        objectName: "week-empty"
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.sp3xl, 420)
        visible: root.weekEmpty
        readonly property bool searching: root.searchText.trim().length > 0
        icon: searching ? "" : "heap-03-week"
        title: I18n.t(searching ? "view.empty.noMatch.title" : "week.empty.title")
        line: searching ? I18n.t("view.empty.noMatch.hint")
                        : I18n.t("week.empty.hint").arg(AppController.shortcutFor("task.new"))
    }

    // What a drag would set, at the pointer; Esc cancels it (APP-249).
    RescheduleDrag {
        id: dragLayer
        objectName: "week-drag"
        onCanceled: { root.chipDrag = null; root.chipTarget = null; }
    }
}
