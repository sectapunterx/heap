#include "SampleData.h"

namespace {
Task mkTask(const char *id, const char *title, const char *desc,
            const char *pri, const char *status, const QDate &dl,
            const char *branch) {
    Task t;
    t.id = id; t.title = QString::fromUtf8(title); t.desc = QString::fromUtf8(desc);
    t.priority = pri; t.status = status; t.deadline = dl; t.branch = branch;
    return t;
}
}

namespace SampleData {

QVector<QVariantMap> statuses() {
    // { id, name, color }
    return {
        { { "id", "backlog" }, { "name", "Backlog"     }, { "color", QColor("#8a8e98") } },
        { { "id", "todo"    }, { "name", "To Do"       }, { "color", QColor("#9aa3b4") } },
        { { "id", "prog"    }, { "name", "In Progress" }, { "color", QColor("#5aa9e6") } },
        { { "id", "half"    }, { "name", "50/50"       }, { "color", QColor("#dcb86b") } },
        { { "id", "blocked" }, { "name", "Blocked"     }, { "color", QColor("#e6624c") } },
        { { "id", "review"  }, { "name", "Code Review" }, { "color", QColor("#c07acf") } },
        { { "id", "done"    }, { "name", "Done"        }, { "color", QColor("#6ec18a") } },
    };
}

QVector<Task> tasks(Lang lang) {
  const QDate today = QDate::currentDate();
    auto d = [&](int n){ return today.addDays(n); };
  if(lang == Lang::Ru) {
    return {
        mkTask("LTE-2398",
               "PDCP SN wraparound при ре-ESTABLISHMENT",
               "После re-establishment PDCP SN иногда коллапсирует к 0 раньше HFN rollover. Воспроизводится на UE Cat 6.",
               "P0",
               "prog",
               d(1),
               "fix/pdcp-sn-wrap-2398"),
        mkTask("LTE-2412",
               "HARQ retx scheduler: учёт PUSCH grant gaps",
               "Оптимизация по результатам profiling-а: при потерях grant ID HARQ RV выбирается не оптимально.",
               "P1",
               "prog",
               d(4),
               "feat/harq-retx-gaps-2412"),
        mkTask("LTE-2467",
               "NAS EMM Attach Reject — корректные cause codes",
               "Не уверен в интерпретации 24.301 §5.5.1.2.5 для cause #15 vs #11. Нужен совет от Олега.",
               "P1",
               "half",
               d(2),
               "feat/nas-attach-reject-2467"),
        mkTask("LTE-2520",
               "SIB1 broadcast scheduling: TDD config 2",
               "В TDD UL/DL config 2 SIB1 иногда мапится на DL subframe с PHICH коллизией.",
               "P2",
               "half",
               d(6),
               "fix/sib1-tdd2-2520"),
        mkTask("LTE-2401",
               "S1AP UE Context Release: timeout 10s",
               "Жду trace от QA: воспроизводится только у одного оператора с ENDC fallback.",
               "P0",
               "blocked",
               d(0),
               "fix/s1ap-ctxrel-2401"),
        mkTask("LTE-2289",
               "PCAP capture rotation: per-cell файлы",
               "PR #4471. Жду Andrey, маленький review.",
               "P2",
               "review",
               d(3),
               "feat/pcap-rotate-2289"),
        mkTask("LTE-2502",
               "GTP-U packet processing: SIMD сериализация",
               "PR #4488. +18% throughput на x86, -3% на ARM — обсудить trade-off.",
               "P1",
               "review",
               d(2),
               "perf/gtpu-simd-2502"),
        mkTask("LTE-2511",
               "LTE-A CA: secondary cell activation race",
               "Активация SCell иногда приходит до завершения RRC reconfig — race на shared state.",
               "P1",
               "todo",
               d(5),
               ""),
        mkTask("LTE-2341",
               "Refactor RRC Connection Reconfiguration handler",
               "Разбить монолитный 1.4k LOC handler на secure mode + bearer config + meas config.",
               "P2",
               "todo",
               d(8),
               ""),
        mkTask("LTE-2455",
               "PHY: SRS configuration по dedicated RRC",
               "Добавить поддержку srs-ConfigDedicated в RRC reconfig path.",
               "P2",
               "todo",
               d(9),
               ""),
        mkTask("LTE-2099",
               "RLC AM: memory leak в re-transmission buffer",
               "valgrind clean, merged в master сегодня утром.",
               "P1",
               "done",
               d(-1),
               "fix/rlc-am-leak-2099"),
        mkTask("LTE-2470", "eNB лог: structured fields для PHY trace", "Готово, merged.", "P3", "done", d(-2), ""),
        mkTask("LTE-2123", "eNB internal logging улучшения", "Slow-path логи в горячем цикле, нужен ring buffer.", "P3", "backlog", {}, ""),
        mkTask("LTE-2602",
               "MAC: BSR triggering для VoLTE",
               "Edge case: paddingBSR vs regularBSR при низкой нагрузке.",
               "P3",
               "backlog",
               {},
               ""),
        mkTask("LTE-2611", "RACH preamble groupB threshold tuning", "Профилировать на нагрузке >200 UE/cell.", "P3", "backlog", {}, ""),
    };
  }
  // English seed (default).
  return {
      mkTask("LTE-2398",
             "PDCP SN wraparound on re-ESTABLISHMENT",
             "After re-establishment, PDCP SN sometimes collapses to 0 before HFN rollover. Repros on UE Cat 6.",
             "P0",
             "prog",
             d(1),
             "fix/pdcp-sn-wrap-2398"),
      mkTask("LTE-2412",
             "HARQ retx scheduler: account for PUSCH grant gaps",
             "Profiling outcome: when grant IDs are lost, HARQ RV selection is sub-optimal.",
             "P1",
             "prog",
             d(4),
             "feat/harq-retx-gaps-2412"),
      mkTask("LTE-2467",
             "NAS EMM Attach Reject — correct cause codes",
             "Unsure about 24.301 §5.5.1.2.5 reading for cause #15 vs #11. Need Oleg's input.",
             "P1",
             "half",
             d(2),
             "feat/nas-attach-reject-2467"),
      mkTask("LTE-2520",
             "SIB1 broadcast scheduling: TDD config 2",
             "In TDD UL/DL config 2, SIB1 sometimes maps to a DL subframe with PHICH collision.",
             "P2",
             "half",
             d(6),
             "fix/sib1-tdd2-2520"),
      mkTask("LTE-2401",
             "S1AP UE Context Release: timeout 10s",
             "Waiting on QA trace: only repros at one operator with ENDC fallback.",
             "P0",
             "blocked",
             d(0),
             "fix/s1ap-ctxrel-2401"),
      mkTask("LTE-2289",
             "PCAP capture rotation: per-cell files",
             "PR #4471. Waiting on Andrey, small review.",
             "P2",
             "review",
             d(3),
             "feat/pcap-rotate-2289"),
      mkTask("LTE-2502",
             "GTP-U packet processing: SIMD serialization",
             "PR #4488. +18% throughput on x86, -3% on ARM — discuss trade-off.",
             "P1",
             "review",
             d(2),
             "perf/gtpu-simd-2502"),
      mkTask("LTE-2511",
             "LTE-A CA: secondary cell activation race",
             "SCell activation sometimes arrives before RRC reconfig completion — race on shared state.",
             "P1",
             "todo",
             d(5),
             ""),
      mkTask("LTE-2341",
             "Refactor RRC Connection Reconfiguration handler",
             "Split the 1.4k LOC monolith into secure mode + bearer config + meas config.",
             "P2",
             "todo",
             d(8),
             ""),
      mkTask("LTE-2455",
             "PHY: SRS configuration via dedicated RRC",
             "Add srs-ConfigDedicated support to the RRC reconfig path.",
             "P2",
             "todo",
             d(9),
             ""),
      mkTask("LTE-2099",
             "RLC AM: memory leak in re-transmission buffer",
             "valgrind clean, merged into master this morning.",
             "P1",
             "done",
             d(-1),
             "fix/rlc-am-leak-2099"),
      mkTask("LTE-2470", "eNB log: structured fields for PHY trace", "Done, merged.", "P3", "done", d(-2), ""),
      mkTask("LTE-2123",
             "eNB internal logging improvements",
             "Slow-path logs inside the hot loop — need a ring buffer.",
             "P3",
             "backlog",
             {},
             ""),
      mkTask("LTE-2602", "MAC: BSR triggering for VoLTE", "Edge case: paddingBSR vs regularBSR under low load.", "P3", "backlog", {}, ""),
      mkTask("LTE-2611", "RACH preamble groupB threshold tuning", "Profile under load >200 UE/cell.", "P3", "backlog", {}, ""),
  };
}

QVector<CalEvent> events(const QDate& today, Lang lang) {
  auto mk = [&](const char* id, const char* title, const char* type, double s, double e, const char* att) {
    CalEvent ev;
    ev.id = id;
    ev.title = QString::fromUtf8(title);
    ev.type = type;
    ev.start = s;
    ev.end = e;
    ev.attendees = QString::fromUtf8(att);
    ev.date = today;
    return ev;
  };
  if(lang == Lang::Ru) {
    return {
        mk("ev-1", "Daily standup", "standup", 10.0,  10.25, "LTE Core team"),
            mk("ev-2", "1:1 с Олегом",       "oneone",  11.0,  11.5,  "Олег Т."),
            mk("ev-3", "Focus: LTE-2398",    "focus",   13.0,  15.0,  "🔒 deep work"),
            mk("ev-4", "LTE Team Sync",      "sync",    16.0,  16.5,  "8 человек"),
            mk("ev-5", "Code review: GTP-U", "sync", 17.0, 17.5, "Andrey, Виктор"),
    };
  }
  return {
      mk("ev-1", "Daily standup", "standup", 10.0, 10.25, "LTE Core team"),
      mk("ev-2", "1:1 with Oleg", "oneone", 11.0, 11.5, "Oleg T."),
      mk("ev-3", "Focus: LTE-2398", "focus", 13.0, 15.0, "🔒 deep work"),
      mk("ev-4", "LTE Team Sync", "sync", 16.0, 16.5, "8 people"),
      mk("ev-5", "Code review: GTP-U", "sync", 17.0, 17.5, "Andrey, Victor"),
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
        mk("p1", "Олег Т.", "Tech Lead", "Уточнить интерпретацию 24.301 §5.5.1.2.5 (cause #15 vs #11)", "todo", QColor("#d97a6c")),
        mk("p2", "Маша К.", "QA", "Попросить полный S1AP trace по LTE-2401 от оператора X", "todo", QColor("#c87fc7")),
        mk("p3", "Andrey S.", "Senior C++ dev", "Пнуть на review PR #4471 (PCAP rotation)", "pinged", QColor("#6cc4b8")),
        mk("p4", "Виктор Л.", "Architect", "Слот на 30 мин — обсудить SIMD trade-off на ARM (LTE-2502)", "todo", QColor("#7da8d9")),
        mk("p5", "Екатерина", "PM", "Подтвердить acceptance criteria для LTE-2412", "replied", QColor("#dcc06a")),
        mk("p6", "Hiroshi M.", "PHY team", "Спросить про SRS dedicated config, есть ли тесты", "todo", QColor("#7cc492")),
    };
  }
  return {
      mk("p1", "Oleg T.",    "Tech Lead",       "Clarify reading of 24.301 §5.5.1.2.5 (cause #15 vs #11)",     "todo",    QColor("#d97a6c")),
        mk("p2", "Masha K.",   "QA",              "Ask for the full S1AP trace on LTE-2401 from operator X",     "todo",    QColor("#c87fc7")),
        mk("p3", "Andrey S.",  "Senior C++ dev",  "Nudge review on PR #4471 (PCAP rotation)",                    "pinged",  QColor("#6cc4b8")),
        mk("p4", "Victor L.",  "Architect",       "30 min slot — discuss SIMD trade-off on ARM (LTE-2502)",      "todo",    QColor("#7da8d9")),
        mk("p5", "Ekaterina",  "PM",              "Confirm acceptance criteria for LTE-2412",                    "replied", QColor("#dcc06a")),
        mk("p6", "Hiroshi M.", "PHY team",        "Ask about SRS dedicated config — are there tests?",            "todo",    QColor("#7cc492")),
    };
}

} // namespace SampleData
