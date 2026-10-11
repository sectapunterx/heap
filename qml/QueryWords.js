// A query clause as words (R2-016/017): "is:archived" reads "статус в архиве"
// on a chip and in "Ничего под «…»", never as the raw token.
// Not a library: it uses the I18n and AppController singletons of the file
// that imports it.

// "status:review" -> { key: "статус", value: "На ревью", neg: false }; null
// for a plain word (it stays as typed).
function clause(raw) {
    const neg = raw.startsWith("-");
    const body = neg ? raw.slice(1) : raw;
    const at = body.indexOf(":");
    // "status:" not finished yet stays as typed: it read "status Backlog",
    // the first column (IDIOT-TASKS-22).
    if (at <= 0 || at === body.length - 1) return null;
    // The chips' Russian keys typed back ("статус:заблок", "приоритет:p0")
    // are the same clauses (DG-080, R3-136).
    const ruKeys = { "статус": "status", "приоритет": "priority" };
    const k0 = body.slice(0, at).toLowerCase();
    const k = ruKeys[k0] || k0;
    const v = body.slice(at + 1);
    const lv = v.toLowerCase();
    const keys = { status: "status", priority: "priority", tag: "label", due: "due", deadline: "due",
                   is: "is", mention: "mention" };
    // "is:open" is the default "статус не готово" of the sheets (DG-020);
    // "is:archived" is a status too: "статус в архиве" (X-Oth-Archive-People).
    const notDone = !neg && k === "is" && lv === "open";
    const asStatus = notDone || (k === "is" && lv === "archived");
    const key = I18n.t("query.key." + (asStatus ? "status" : (keys[k] || "other")));
    let value = v;
    if (notDone) value = I18n.t("query.notDone");
    else if (k === "is") value = I18n.t("query.is." + lv);
    else if (k === "priority") value = v.toUpperCase().split(",").join(", ");
    else if (k === "status") {
        const sts = AppController.statuses;
        // By id, else by the start of the name ("заблок" → Заблокировано).
        value = v.split(",").map(id => {
            const l = id.toLowerCase();
            const st = sts.find(x => x.id === l) || sts.find(x => String(x.name || "").toLowerCase().startsWith(l));
            return st ? st.name : id;
        }).join(", ");
    } else if (k === "due" || k === "deadline") {
        const words = ["today", "tomorrow", "week", "overdue", "none"];
        value = words.indexOf(lv) >= 0 ? I18n.t("query.due." + lv) : v;
    }
    if (value.indexOf("query.") === 0) value = v;
    return { key: (neg ? I18n.t("query.not") + " " : "") + key, value: value, neg: neg };
}

// The whole filter as words for an empty state: clauses as "key value",
// plain words as typed, priorities picked in the bar last.
function label(searchText, priorities) {
    const parts = String(searchText || "").trim().split(/\s+/).filter(x => x.length > 0).map(raw => {
        const c = clause(raw);
        return c ? c.key + " " + c.value : raw;
    });
    for (const p of priorities || []) parts.push(String(p).toUpperCase());
    return parts.join(" · ");
}
