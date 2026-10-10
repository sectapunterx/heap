.pragma library

// "What's new" per release line (R2-054): what the line changed for someone
// coming from the one before, in the UI language. Facts of the release only
// — every entry here is something the build does. A line without an entry
// shows nothing after an update.
//
// line: "0.8" for 0.8.0, 0.8.1, …
var notes = {
    "0.8": {
        sections: [
            { title: { en: "Today", ru: "Сегодня" },
              body: { en: "the home screen: the day by the hour, in progress, deadlines",
                      ru: "главный экран: день по часам, в работе, сроки" } },
            { title: { en: "Tasks", ru: "Задачи" },
              body: { en: "board, list and calendar — one section with one filter",
                      ru: "доска, список и календарь — один раздел с общим фильтром" } },
            { title: { en: "Task as a document", ru: "Задача — документ" },
              body: { en: "a panel on the right, saves by itself, “Done” — D",
                      ru: "панель справа, сохраняется сама, «Готово» — D" } },
            { title: { en: "One input", ru: "Один ввод" },
              body: { en: "“tomorrow 15:00 p1” is understood wherever a task is created",
                      ru: "«завтра 15:00 p1» понимается везде, где создаётся задача" } },
            { title: { en: "Two styles", ru: "Два стиля" },
              body: { en: "“Bold” by default, “Quiet” in Settings → Appearance",
                      ru: "«Насыщенный» по умолчанию, «Тихий» — в Настройки → Внешний вид" } }
        ],
        moved: { en: "“Focus” and “Saved views” → “My views” · Timeline, Week, Month → Tasks · Docs + Notes → Knowledge · Tweaks → Settings",
                 ru: "«Фокус» и «Сохранённые виды» → «Мои виды» · Лента, Неделя, Месяц → Задачи · Доки + Заметки → Знания · Твики → Настройки" }
    }
};

function lineOf(version) {
    var m = /^(\d+)\.(\d+)/.exec(String(version || ""));
    return m ? m[1] + "." + m[2] : "";
}

function forVersion(version) {
    return notes[lineOf(version)] || null;
}
