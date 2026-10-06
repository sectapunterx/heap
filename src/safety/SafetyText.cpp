#include "safety/SafetyText.h"

#include <QHash>
#include <QStringList>

namespace heap::safety {

namespace {

struct Entry {
  const char* en;
  const char* ru;
};

const QHash<QString, Entry>& table() {
  static const QHash<QString, Entry> t = {
      // ── APP-157: end of day ──
      {QStringLiteral("safety.eod.title"), {"Before you wrap up", "Перед концом дня"}},
      {QStringLiteral("safety.eod.timer"), {"Timer still running", "Таймер всё ещё идёт"}},
      // ── APP-190: the day's summary ──
      {QStringLiteral("safety.eod.closed"), {"%1 closed today", "Закрыто сегодня: %1"}},
      {QStringLiteral("safety.eod.carryOver"), {"%1 carry over to tomorrow", "Переходит на завтра: %1"}},
      {QStringLiteral("safety.eod.timers"), {"%1 timers still running", "Таймеров всё ещё идёт: %1"}},
      {QStringLiteral("safety.eod.files"), {"%1 %2 in %3", "%1 %2 в %3"}},
      {QStringLiteral("safety.eod.filesNoRepo"), {"%1 %2", "%1 %2"}},
      {QStringLiteral("safety.eod.fileForms"),
       {"uncommitted file|uncommitted files|uncommitted files", "незакоммиченный файл|незакоммиченных файла|незакоммиченных файлов"}},
      {QStringLiteral("safety.eod.stash"), {"%1 %2 in %3", "%1 %2 в %3"}},
      {QStringLiteral("safety.eod.stashNoRepo"), {"%1 %2", "%1 %2"}},
      {QStringLiteral("safety.eod.stashForms"), {"stash|stashes|stashes", "стеш|стеша|стешей"}},
      {QStringLiteral("safety.eod.stale"), {"%1 %2 in progress without a move for %3+ %4", "%1 %2 в работе без движения %3+ %4"}},
      {QStringLiteral("safety.dayForms"), {"day|days|days", "день|дня|дней"}},
      {QStringLiteral("safety.eod.taskForms"), {"task|tasks|tasks", "задача|задачи|задач"}},
      // ── APP-160: focus mode ──
      {QStringLiteral("shortcut.focus.immersion.label"), {"Focus mode", "Режим погружения"}},
      {QStringLiteral("shortcut.focus.immersion.desc"),
       {"Hold notifications back and time the current task; again to leave.",
        "Придержать уведомления и засечь время текущей задачи; ещё раз — выйти."}},
      // ── APP-170: standup draft ──
      {QStringLiteral("safety.standup.yesterday"), {"Yesterday:", "Вчера:"}},
      {QStringLiteral("safety.standup.today"), {"Today:", "Сегодня:"}},
      {QStringLiteral("safety.standup.blockers"), {"Blockers:", "Блокеры:"}},
      {QStringLiteral("safety.standup.meeting"), {"Meeting: %1", "Встреча: %1"}},
      {QStringLiteral("safety.standup.timer"), {"worked on it (timer)", "работа по таймеру"}},
      {QStringLiteral("safety.standup.commitForms"), {"commit|commits|commits", "коммит|коммита|коммитов"}},
      // ── APP-158: waiting on a reply ──
      {QStringLiteral("safety.waiting.title"), {"Still waiting on a reply", "Ждёте ответа"}},
      // %1 person, %2 days, %3 "day(s)", %4 task title. No declension of the
      // name in Russian: "спрашивали Олег" would read wrong, so it leads.
      {QStringLiteral("safety.waiting.body"), {"You asked %1 %2 %3 ago: %4", "%1 · спрашивали %2 %3 назад: %4"}},
  };
  return t;
}

}  // namespace

QString text(const QString& key, bool ru) {
  const auto it = table().constFind(key);
  if(it == table().constEnd()) {
    return {};
  }
  return QString::fromUtf8(ru ? it->ru : it->en);
}

QString plural(int n, const QString& forms) {
  const QStringList f = forms.split(QLatin1Char('|'));
  if(f.size() < 3) {
    return forms;
  }
  const int abs = n < 0 ? -n : n;
  const int mod10 = abs % 10;
  const int mod100 = abs % 100;
  // The Russian rule; for English the "few" form is the plural, so it reads
  // the same: 1 → one, everything else → many.
  if(mod10 == 1 && mod100 != 11) {
    return f.at(0);
  }
  if(mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return f.at(1);
  }
  return f.at(2);
}

QString endOfDaySummary(const EndOfDayFindings& f, int staleDays, bool ru) {
  QStringList parts;
  if(f.timerTaskIds.size() == 1) {
    parts << text(QStringLiteral("safety.eod.timer"), ru);
  } else if(f.timerTaskIds.size() > 1) {
    parts << text(QStringLiteral("safety.eod.timers"), ru).arg(f.timerTaskIds.size());
  }
  if(f.changedFiles > 0) {
    const QString forms = plural(f.changedFiles, text(QStringLiteral("safety.eod.fileForms"), ru));
    parts << (f.repo.isEmpty() ? text(QStringLiteral("safety.eod.filesNoRepo"), ru).arg(f.changedFiles).arg(forms)
                               : text(QStringLiteral("safety.eod.files"), ru).arg(f.changedFiles).arg(forms).arg(f.repo));
  }
  if(f.stashes > 0) {
    const QString forms = plural(f.stashes, text(QStringLiteral("safety.eod.stashForms"), ru));
    parts << (f.repo.isEmpty() ? text(QStringLiteral("safety.eod.stashNoRepo"), ru).arg(f.stashes).arg(forms)
                               : text(QStringLiteral("safety.eod.stash"), ru).arg(f.stashes).arg(forms).arg(f.repo));
  }
  if(!f.staleTaskIds.isEmpty()) {
    const int n = static_cast<int>(f.staleTaskIds.size());
    parts << text(QStringLiteral("safety.eod.stale"), ru)
                 .arg(n)
                 .arg(plural(n, text(QStringLiteral("safety.eod.taskForms"), ru)))
                 .arg(staleDays)
                 .arg(plural(staleDays, text(QStringLiteral("safety.dayForms"), ru)));
  }
  return parts.join(QStringLiteral(" · "));
}

QString daySummaryLine(const DaySummary& s, bool ru) {
  QStringList parts;
  if(!s.closedTaskIds.isEmpty()) {
    parts << text(QStringLiteral("safety.eod.closed"), ru).arg(s.closedTaskIds.size());
  }
  if(!s.carryOverTaskIds.isEmpty()) {
    parts << text(QStringLiteral("safety.eod.carryOver"), ru).arg(s.carryOverTaskIds.size());
  }
  return parts.join(QStringLiteral(" · "));
}

}  // namespace heap::safety
