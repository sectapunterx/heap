#include "SampleData.h"

namespace {
Task mkTask(const char* id, const char* title, const char* desc, const char* pri, const char* status, const QDate& dl, const char* branch) {
  Task t;
  t.id = id;
  t.title = QString::fromUtf8(title);
  t.desc = QString::fromUtf8(desc);
  t.priority = pri;
  t.status = status;
  if(dl.isValid()) {
    t.scheduledAt = QDateTime(dl, QTime(0, 0));
    t.dueAt = t.scheduledAt;
  }
  t.branch = branch;
  return t;
}
}  // namespace

namespace SampleData {

QVector<QVariantMap> statuses(Lang lang) {
  // { id, name, color }
  if(lang == Lang::Ru) {
    return {
        {{"id", "backlog"}, {"name", "Бэклог"}, {"color", QColor("#8a8e98")}},
        {{"id", "todo"}, {"name", "К выполнению"}, {"color", QColor("#9aa3b4")}},
        {{"id", "prog"}, {"name", "В работе"}, {"color", QColor("#5aa9e6")}},
        {{"id", "half"}, {"name", "50/50"}, {"color", QColor("#dcb86b")}},
        {{"id", "blocked"}, {"name", "Заблокировано"}, {"color", QColor("#e6624c")}},
        {{"id", "review"}, {"name", "Ревью кода"}, {"color", QColor("#a4a4d6")}},
        {{"id", "done"}, {"name", "Готово"}, {"color", QColor("#6ec18a")}},
    };
  }
  return {
      {{"id", "backlog"}, {"name", "Backlog"}, {"color", QColor("#8a8e98")}},
      {{"id", "todo"}, {"name", "To Do"}, {"color", QColor("#9aa3b4")}},
      {{"id", "prog"}, {"name", "In Progress"}, {"color", QColor("#5aa9e6")}},
      {{"id", "half"}, {"name", "50/50"}, {"color", QColor("#dcb86b")}},
      {{"id", "blocked"}, {"name", "Blocked"}, {"color", QColor("#e6624c")}},
      {{"id", "review"}, {"name", "Code Review"}, {"color", QColor("#a4a4d6")}},
      {{"id", "done"}, {"name", "Done"}, {"color", QColor("#6ec18a")}},
  };
}

QVector<Task> tasks(Lang lang) {
  const QDate today = QDate::currentDate();
  auto d = [&](int n) {
    return today.addDays(n);
  };
  if(lang == Lang::Ru) {
    return {
        mkTask("APP-101",
               "Обход ограничения попыток входа",
               "После сброса пароля счётчик попыток иногда обнуляется — возможен перебор. Воспроизводится на мобильных клиентах.",
               "P0",
               "prog",
               d(1),
               "fix/login-rate-limit"),
        mkTask("APP-102",
               "Постраничный API: сдвиг курсора на больших списках",
               "По результатам профилирования: при удалении элементов во время прокрутки курсор пропускает страницу.",
               "P1",
               "prog",
               d(4),
               "feat/api-pagination"),
        mkTask("APP-103",
               "Дашборд: пустое состояние для новых аккаунтов",
               "Не уверен, какие метрики показывать новым и активным аккаунтам. Нужен совет от Олега.",
               "P1",
               "half",
               d(2),
               "feat/dashboard-widgets"),
        mkTask("APP-104",
               "Поиск: некорректное пустое состояние",
               "При нулевой выдаче иногда мелькает старый список перед сообщением «ничего не найдено».",
               "P2",
               "half",
               d(6),
               "fix/search-empty-state"),
        mkTask("APP-105",
               "Оформление заказа: таймаут 10с",
               "Жду трассировку от QA: воспроизводится только у одного клиента с медленной сетью.",
               "P0",
               "blocked",
               d(0),
               "fix/checkout-timeout"),
        mkTask("APP-106",
               "Экспорт в CSV: постраничная выгрузка",
               "PR #4471. Жду Андрея, ревью небольшое.",
               "P2",
               "review",
               d(3),
               "feat/csv-export"),
        mkTask("APP-107",
               "Генерация превью изображений: кэширование",
               "PR #4488. +18% скорости на сервере, −3% памяти — обсудить компромисс.",
               "P1",
               "review",
               d(2),
               "perf/image-thumbnails"),
        mkTask("APP-108",
               "Гонка при обновлении профиля",
               "Сохранение аватара иногда приходит до завершения обновления профиля — гонка на общем состоянии.",
               "P1",
               "todo",
               d(5),
               ""),
        mkTask("APP-109",
               "Рефакторинг обработчика вебхуков",
               "Разбить монолитный обработчик на 1,4 тыс. строк на проверку, маршрутизацию и доставку.",
               "P2",
               "todo",
               d(8),
               ""),
        mkTask("APP-110",
               "Настройки уведомлений: переключатели по каналам",
               "Добавить настройки для каждого канала в экран уведомлений.",
               "P2",
               "todo",
               d(9),
               ""),
        mkTask("APP-111",
               "Утечка памяти в хранилище сессий",
               "Профилировщик чист, влито в master сегодня утром.",
               "P1",
               "done",
               d(-1),
               "fix/session-memory-leak"),
        mkTask("APP-112", "Логи: структурированные поля для API-запросов", "Готово, смёржено.", "P3", "done", d(-2), ""),
        mkTask("APP-113",
               "Улучшения внутреннего логирования",
               "Медленное логирование в горячем цикле, нужен кольцевой буфер.",
               "P3",
               "backlog",
               {},
               ""),
        mkTask("APP-114",
               "Экспорт: граничный случай пустого отчёта",
               "Граничный случай: пустой отчёт и отчёт из одной строки при низкой нагрузке.",
               "P3",
               "backlog",
               {},
               ""),
        mkTask("APP-115", "Тюнинг порога кэша поиска", "Профилировать на нагрузке >200 запросов/сек.", "P3", "backlog", {}, ""),
    };
  }
  // English seed (default).
  return {
      mkTask("APP-101",
             "Login rate-limit bypass",
             "After a password reset the attempt counter sometimes resets — brute force is possible. Repros on mobile clients.",
             "P0",
             "prog",
             d(1),
             "fix/login-rate-limit"),
      mkTask("APP-102",
             "API pagination: cursor drift on large lists",
             "Profiling outcome: when items are deleted mid-scroll, the cursor skips a page.",
             "P1",
             "prog",
             d(4),
             "feat/api-pagination"),
      mkTask("APP-103",
             "Dashboard: empty state for new accounts",
             "Unsure which metrics to show for new vs active accounts. Need Oleg's input.",
             "P1",
             "half",
             d(2),
             "feat/dashboard-widgets"),
      mkTask("APP-104",
             "Search: incorrect empty state",
             "On a zero-result query the old list flashes before the 'nothing found' message.",
             "P2",
             "half",
             d(6),
             "fix/search-empty-state"),
      mkTask("APP-105",
             "Checkout: 10s timeout",
             "Waiting on QA trace: only repros for one customer on a slow network.",
             "P0",
             "blocked",
             d(0),
             "fix/checkout-timeout"),
      mkTask("APP-106",
             "CSV export: paginated download",
             "PR #4471. Waiting on Andrey, small review.",
             "P2",
             "review",
             d(3),
             "feat/csv-export"),
      mkTask("APP-107",
             "Image thumbnail generation: caching",
             "PR #4488. +18% speed on the server, -3% memory — discuss trade-off.",
             "P1",
             "review",
             d(2),
             "perf/image-thumbnails"),
      mkTask("APP-108",
             "Race condition on profile update",
             "Avatar save sometimes arrives before the profile update completes — race on shared state.",
             "P1",
             "todo",
             d(5),
             ""),
      mkTask("APP-109",
             "Refactor the webhook handler",
             "Split the 1.4k LOC monolith into validation + routing + delivery.",
             "P2",
             "todo",
             d(8),
             ""),
      mkTask("APP-110",
             "Notification settings: granular toggles",
             "Add per-channel support to the notification settings path.",
             "P2",
             "todo",
             d(9),
             ""),
      mkTask("APP-111",
             "Memory leak in session store",
             "Profiler clean, merged into master this morning.",
             "P1",
             "done",
             d(-1),
             "fix/session-memory-leak"),
      mkTask("APP-112", "Logs: structured fields for API requests", "Done, merged.", "P3", "done", d(-2), ""),
      mkTask(
          "APP-113", "Internal logging improvements", "Slow-path logs inside the hot loop — need a ring buffer.", "P3", "backlog", {}, ""),
      mkTask("APP-114",
             "Export: empty report edge case",
             "Edge case: empty report vs single-row report under low load.",
             "P3",
             "backlog",
             {},
             ""),
      mkTask("APP-115", "Search cache threshold tuning", "Profile under load >200 req/s.", "P3", "backlog", {}, ""),
  };
}

QVector<CalEvent> events(const QDate& today, Lang lang) {
  auto mk = [&](const char* id, const char* title, const char* type, double s, double e, const char* att, int off) {
    CalEvent ev;
    ev.id = id;
    ev.title = QString::fromUtf8(title);
    ev.type = type;
    ev.start = s;
    ev.end = e;
    ev.attendees = QString::fromUtf8(att);
    ev.date = today.addDays(off);
    return ev;
  };
  if(lang == Lang::Ru) {
    return {
        mk("ev-1", "Дейли стендап", "standup", 10.0, 10.25, "Команда продукта", 0),
        mk("ev-2", "1:1 с Олегом", "oneone", 11.0, 11.5, "Олег Т.", 1),
        mk("ev-3", "Фокус-блок", "focus", 13.0, 15.0, "🔒 глубокая работа", 0),
        mk("ev-4", "Планирование спринта", "sync", 16.0, 16.5, "Вся команда", 2),
        mk("ev-5", "Ревью кода", "sync", 17.0, 17.5, "Андрей, Виктор", 3),
    };
  }
  return {
      mk("ev-1", "Daily standup", "standup", 10.0, 10.25, "Product team", 0),
      mk("ev-2", "1:1 with Oleg", "oneone", 11.0, 11.5, "Oleg T.", 1),
      mk("ev-3", "Focus block", "focus", 13.0, 15.0, "🔒 deep work", 0),
      mk("ev-4", "Sprint planning", "sync", 16.0, 16.5, "Whole team", 2),
      mk("ev-5", "Code review", "sync", 17.0, 17.5, "Andrey, Victor", 3),
  };
}

QVector<Person> people(Lang lang) {
  auto mk = [](const char* id, const char* n, const char* r, const char* q, const char* st, const QColor& c) {
    Person p;
    p.id = id;
    p.name = QString::fromUtf8(n);
    p.role = QString::fromUtf8(r);
    p.question = QString::fromUtf8(q);
    p.state = st;
    p.color = c;
    return p;
  };
  if(lang == Lang::Ru) {
    return {
        mk("p1",
           "Олег Т.",
           "Tech Lead",
           "Уточнить, какие метрики показывать в пустом состоянии дашборда (новые vs активные)",
           "todo",
           QColor("#d97a6c")),
        mk("p2", "Маша К.", "QA", "Попросить полный repro-trace по APP-105 от клиента X", "todo", QColor("#c87fc7")),
        mk("p3", "Andrey S.", "Backend dev", "Пнуть на review PR #4471 (CSV export)", "pinged", QColor("#6cc4b8")),
        mk("p4",
           "Priya N.",
           "Designer",
           "Слот на 30 мин — обсудить иллюстрации пустого состояния поиска (APP-104)",
           "todo",
           QColor("#7da8d9")),
        mk("p5", "Екатерина", "PM", "Подтвердить acceptance criteria для APP-102", "replied", QColor("#dcc06a")),
        mk("p6", "Hiroshi M.", "Frontend dev", "Спросить про тумблеры уведомлений (APP-110), есть ли тесты", "todo", QColor("#7cc492")),
    };
  }
  return {
      mk("p1",
         "Oleg T.",
         "Tech Lead",
         "Clarify which metrics to show in the dashboard empty state (new vs active)",
         "todo",
         QColor("#d97a6c")),
      mk("p2", "Masha K.", "QA", "Ask for the full repro trace on APP-105 from customer X", "todo", QColor("#c87fc7")),
      mk("p3", "Andrey S.", "Backend dev", "Nudge review on PR #4471 (CSV export)", "pinged", QColor("#6cc4b8")),
      mk("p4", "Priya N.", "Designer", "30 min slot — discuss search empty-state illustrations (APP-104)", "todo", QColor("#7da8d9")),
      mk("p5", "Ekaterina", "PM", "Confirm acceptance criteria for APP-102", "replied", QColor("#dcc06a")),
      mk("p6", "Hiroshi M.", "Frontend dev", "Ask about notification toggles (APP-110) — are there tests?", "todo", QColor("#7cc492")),
  };
}

QVector<Note> notes(Lang lang) {
  Note n;
  n.id = QStringLiteral("note-welcome");
  n.created = QDateTime::currentDateTime();
  n.updated = n.created;
  if(lang == Lang::Ru) {
    n.title = QStringLiteral("С чего начать");
    n.body = QStringLiteral(
        "# С чего начать\n\n"
        "Заметки — это markdown: **жирный**, *курсив*, `код`, списки и таблицы.\n\n"
        "- [ ] Открыть задачу APP-101 на доске\n"
        "- [ ] Перетащить задачу в календарь справа\n"
        "- [x] Прочитать эту заметку\n\n"
        "Ссылка на задачу: [[APP-101]].\n\n"
        "> Нажмите «Начать с чистого листа» на баннере, чтобы убрать демо-данные.\n");
  } else {
    n.title = QStringLiteral("Getting started");
    n.body = QStringLiteral(
        "# Getting started\n\n"
        "Notes are markdown: **bold**, *italic*, `code`, lists and tables.\n\n"
        "- [ ] Open APP-101 on the board\n"
        "- [ ] Drag a task onto the calendar on the right\n"
        "- [x] Read this note\n\n"
        "Link to a task: [[APP-101]].\n\n"
        "> Press \"Start fresh\" on the banner to clear the demo data.\n");
  }
  return {n};
}

}  // namespace SampleData
