#include "TaskTextUtils.h"

#include <QChar>
#include <QHash>
#include <QPair>
#include <QRegularExpression>
#include <QVector>

namespace heap::text {

namespace {

// Latin + Cyrillic + digit + underscore. Used as the "word character" class so
// "созвон" and "митап" match cleanly. Avoids ES2018 \p{L} (unsupported in
// Qt6's V4 JS engine, but here we are pure C++ — still cheaper than a Unicode
// table lookup).
constexpr const char* kWordRx = "[^a-zA-Zа-яА-ЯёЁ0-9_]";

// A trailing '*' makes the entry a stem: "встреч*" matches "встреча",
// "встречу", "встречей" — Russian inflects every noun, and listing each case
// of each word is how the list used to miss "созвона" and "синке". The stem
// still has to start a word, so "встреч*" does not fire inside "навстречу".
bool containsWord(const QString &haystackLowered, const QString &needleLowered) {
    if (needleLowered.isEmpty()) return false;
    const bool stem = needleLowered.endsWith(QChar('*'));
    const QString escaped = QRegularExpression::escape(stem ? needleLowered.chopped(1) : needleLowered);
    // (^|<non-word>)needle[<word>*](<non-word>|$)
    const QString pattern = QStringLiteral("(?:^|") + kWordRx + ")" + escaped + (stem ? QStringLiteral("[a-zа-яё]*") : QString()) +
                            QStringLiteral("(?:") + kWordRx + "|$)";
    const QRegularExpression rx(pattern);
    return rx.match(haystackLowered).hasMatch();
}

bool anyHits(const QString &lowered, const QStringList &words) {
    for (const QString &w : words)
        if (containsWord(lowered, w)) return true;
    return false;
}

const QStringList &focusWords() {
  static const QStringList w = {"focus",          "focusmode",   "focus-mode", "focus mode",      "focus_mode",      "focus time",
                                "focus block",    "deep work",   "deepwork",   "heads down",      "heads-down",      "no meetings",
                                "фокус",          "фокуса",      "фокусе",     "фокусом",         "фокус-режим",     "фокус режим",
                                "фокус-мод",      "фокус-время", "фокус-блок", "глубокая работа", "глубокой работы", "глубокую работу",
                                "без отвлечений", "без созвонов"};
  return w;
}

// Meeting words, grouped by the calendar type they book (see meetingType).
const QStringList& standupWords() {
  static const QStringList w = {
      "standup", "stand-up", "daily", "daily sync", "scrum", "стендап*", "дейли", "дэйли", "планерк*", "планёрк*", "летучк*", "скрам*"};
  return w;
}

const QStringList& oneOnOneWords() {
  static const QStringList w = {
      "one-on-one", "one on one", "1:1", "1-1", "1on1", "one to one", "1x1", "один на один", "тет-а-тет", "ван-ту-ван"};
  return w;
}

const QStringList& teamSyncWords() {
  static const QStringList w = {"sync", "sync-up", "team sync", "синк*"};
  return w;
}

const QStringList& meetingWords() {
  static const QStringList w = {
      // one-offs: calls, meetings and the rituals that are not a standup
      "созвон*",    "созвонимся",    "созвониться", "позвонить",   "позвоним",     "встреч*",     "митап*",        "митинг*",  "звонок",
      "звонка",     "звонку",        "звонком",     "видеозвонок", "колл*",        "конференци*", "совещани*",     "собрани*", "обсуждени*",
      "ретро",      "ретроспектив*", "демо",        "груминг*",    "планировани*", "собес*",      "собеседовани*", "интервью", "ревью",
      "код-ревью",  "зум",           "зуме",        "meetup",      "meet",         "meeting",     "meetings",      "call",     "calls",
      "conference", "huddle",        "catch up",    "catch-up",    "catchup",      "retro",       "retrospective", "demo",     "grooming",
      "refinement", "planning",      "interview",   "review",      "code review",  "zoom",        "hangout",       "workshop", "воркшоп*"};
  return w;
}

const QStringList &ticketWords() {
  static const QStringList w = {"тикет*", "задача", "задачу", "задачи", "задачей", "задач",     "эпик*",  "баг",    "бага",
                                "багу",   "баги",   "багов",  "фич*",   "фикс",    "пофиксить", "task",   "tasks",  "issue",
                                "issues", "story",  "epic",   "bug",    "bugs",    "feature",   "bugfix", "hotfix", "todo"};
  return w;
}

const QStringList &contactWords() {
  static const QStringList w = {
      "написать", "напиши",    "пиши",      "написал",    "пишу",      "напишу",  "напомни",   "напомнить", "спросить", "спроси", "спрошу",
      "ответить", "ответь",    "уточнить",  "уточни",     "попросить", "попроси", "пингануть", "пингани",   "пинг",     "пнуть",  "дёрнуть",
      "дернуть",  "передать",  "передай",   "сказать",    "скажи",     "ping",    "ask",       "remind",    "message",  "msg",    "dm",
      "tell",     "follow up", "follow-up", "check with", "email",     "text",    "slack",     "nudge"};
  return w;
}

// Priority words. A word is taken out of the title the way a
// date is: "срочно починить прод" is the task "починить прод" at P1.
struct PriorityWord {
  const char* word;
  const char* priority;
};

// "не срочно" is listed before "срочно", which it contains.
constexpr PriorityWord kPriorityWords[] = {
    {"не срочно", "P3"}, {"несрочно", "P3"},     {"критично", "P0"}, {"критичный", "P0"}, {"критичная", "P0"}, {"блокер", "P0"},
    {"critical", "P0"},  {"blocker", "P0"},      {"p0", "P0"},       {"!!!", "P0"},       {"срочно", "P1"},    {"срочная", "P1"},
    {"срочный", "P1"},   {"горит", "P1"},        {"urgent", "P1"},   {"asap", "P1"},      {"p1", "P1"},        {"!!", "P1"},
    {"p2", "P2"},        {"low priority", "P3"}, {"p3", "P3"},
};

bool hasHandle(QStringView text) {
    // Quick scan for an "@token" outside of e-mail context. Mirrors the
    // boundary used by extractMeta.
    static const QRegularExpression rx(
        QStringLiteral("(?:^|[\\s,;\\(])@[A-Za-zА-Яа-яЁё0-9_.\\-]+"));
    return rx.match(text.toString()).hasMatch();
}

} // namespace

TaskKind classifyKind(QStringView text) {
    const QString s = text.toString().toLower();
    if (s.isEmpty()) return TaskKind::None;
    // Priority: Ticket > Contact > Focus > Sync > None.
    //  - "задача"/"ticket" is the explicit opt-out: it stays a pure todo
    //    even if the body also mentions @handles or meeting words.
    //  - Contact-ping needs BOTH a contact verb AND a "@handle".
    if (anyHits(s, ticketWords())) return TaskKind::Ticket;
    if (hasHandle(text) && anyHits(s, contactWords())) return TaskKind::Contact;
    if (anyHits(s, focusWords()))  return TaskKind::Focus;
    if(anyHits(s, standupWords()) || anyHits(s, oneOnOneWords()) || anyHits(s, teamSyncWords()) || anyHits(s, meetingWords())) {
      return TaskKind::Sync;
    }
    return TaskKind::None;
}

QString meetingType(QStringView text) {
  const QString s = text.toString().toLower();
  if(anyHits(s, standupWords())) {
    return QStringLiteral("standup");
  }
  if(anyHits(s, oneOnOneWords())) {
    return QStringLiteral("oneone");
  }
  if(anyHits(s, teamSyncWords())) {
    return QStringLiteral("sync");
  }
  return QStringLiteral("none");
}

namespace {

// Russian → Latin transliteration. Lowercase keys only; caller lowercases
// input first. Returns either a single char or a multi-char digraph.
QString translitRu(QChar ch) {
    static const QHash<QChar, QString> table = {
        {QChar(0x0430), "a"}, {QChar(0x0431), "b"}, {QChar(0x0432), "v"},
        {QChar(0x0433), "g"}, {QChar(0x0434), "d"}, {QChar(0x0435), "e"},
        {QChar(0x0451), "e"}, {QChar(0x0436), "zh"}, {QChar(0x0437), "z"},
        {QChar(0x0438), "i"}, {QChar(0x0439), "i"}, {QChar(0x043A), "k"},
        {QChar(0x043B), "l"}, {QChar(0x043C), "m"}, {QChar(0x043D), "n"},
        {QChar(0x043E), "o"}, {QChar(0x043F), "p"}, {QChar(0x0440), "r"},
        {QChar(0x0441), "s"}, {QChar(0x0442), "t"}, {QChar(0x0443), "u"},
        {QChar(0x0444), "f"}, {QChar(0x0445), "h"}, {QChar(0x0446), "c"},
        {QChar(0x0447), "ch"}, {QChar(0x0448), "sh"}, {QChar(0x0449), "sch"},
        {QChar(0x044A), ""},  {QChar(0x044B), "y"},  {QChar(0x044C), ""},
        {QChar(0x044D), "e"}, {QChar(0x044E), "yu"}, {QChar(0x044F), "ya"}
    };
    const auto it = table.find(ch);
    return it == table.end() ? QString() : *it;
}

// Translit + ascii-fold + strip punctuation. Result is lowercase ascii.
QString tokenToAscii(const QString &token) {
    QString out;
    out.reserve(token.size());
    for (QChar c : token) {
        const QChar lo = c.toLower();
        if (lo.unicode() >= 0x0400 && lo.unicode() <= 0x04FF) {
            out += translitRu(lo);
        } else if (lo.isLetterOrNumber() && lo.unicode() < 128) {
            out += lo;
        }
        // Other glyphs (punctuation, accents) are dropped.
    }
    return out;
}

} // namespace

QString asciiFold(QStringView token) {
  return tokenToAscii(token.toString());
}

QString slugifyPersonName(QStringView name) {
    const QString trimmed = name.toString().trimmed();
    if (trimmed.isEmpty()) return QString();
    // Split on whitespace, drop empties.
    const QStringList tokens = trimmed.split(QRegularExpression("\\s+"),
                                             Qt::SkipEmptyParts);
    if (tokens.isEmpty()) return QString();

    if (tokens.size() == 1) {
        return tokenToAscii(tokens.first());
    }

    // first-initial + "." + last-token (transliterated).
    const QString firstAscii = tokenToAscii(tokens.first());
    const QString lastAscii  = tokenToAscii(tokens.last());
    if (firstAscii.isEmpty() && lastAscii.isEmpty()) return QString();
    if (firstAscii.isEmpty()) return lastAscii;
    if (lastAscii.isEmpty())  return firstAscii;
    return QString(firstAscii.front()) + QChar('.') + lastAscii;
}

TaskMeta extractMeta(QStringView raw, bool keepTicketKey) {
  TaskMeta out;
  QString text = raw.toString();

  // 1. "// comment" → desc. Split on the first occurrence outside a URL:
  //    "see https://example.com/a" used to lose everything after "https:".
  static const QRegularExpression urlRx(QStringLiteral("[A-Za-z][A-Za-z0-9+.\\-]*://\\S*"));
  int dslash = text.indexOf(QStringLiteral("//"));
  while(dslash >= 0) {
    bool inUrl = false;
    QRegularExpressionMatchIterator ui = urlRx.globalMatch(text);
    while(ui.hasNext() && !inUrl) {
      const auto m = ui.next();
      inUrl = dslash >= m.capturedStart(0) && dslash < m.capturedEnd(0);
    }
    if(!inUrl) {
      break;
    }
    dslash = text.indexOf(QStringLiteral("//"), dslash + 2);
  }
  QString body = text;
  if(dslash >= 0) {
    out.desc = text.mid(dslash + 2).trimmed();
    body = text.left(dslash);
  }
  out.head = body;

  // 2. "@handle" tokens → collected into handles[], but LEFT IN PLACE in
  //    the title so the user keeps the context they typed ("синк с
  //    @viktor"). Leading boundary must be start-of-string or one of
  //    whitespace / punctuation, so e-mail addresses are not picked up.
  static const QRegularExpression rx(QStringLiteral("(?:^|[\\s,;\\(])@([A-Za-zА-Яа-яЁё0-9_.\\-]+)"));
  QRegularExpressionMatchIterator it = rx.globalMatch(body);
  while(it.hasNext()) {
    const auto m = it.next();
    out.handles.append(m.captured(1));
  }

  // 3. A tracker key ("LTE-2398", "HEAP-12") names the ticket the task is
  //    about; it becomes the task id, so it leaves the title. Upper-case
  //    only: "covid-19" or "utf-8" in a sentence are not tickets. A key the
  //    caller cannot use as the id stays where it was typed: "APP-101 follow
  //    up" used to become "follow up" with the ticket gone (TASKS-22, audit
  //    2026-09-30).
  static const QRegularExpression keyRx(QStringLiteral("(?:^|[\\s,;(\\[])([A-Z][A-Z0-9]{1,9}-\\d{1,7})(?=$|[\\s,;:)\\]])"));
  const auto km = keyRx.match(body);
  if(km.hasMatch()) {
    out.ticketKey = km.captured(1);
    if(!keepTicketKey) {
      body.remove(km.capturedStart(1), km.capturedLength(1));
    }
  }

  // 4. Priority: "p1", "!!", "срочно", "urgent". The first one wins and is
  //    removed from the title; any other stays as typed.
  const QString lowered = body.toLower();
  for(const PriorityWord& pw : kPriorityWords) {
    const QString w = QString::fromUtf8(pw.word);
    const QString boundary = w.startsWith(QChar('!')) ? QStringLiteral("(?:^|\\s)") : QStringLiteral("(?:^|") + kWordRx + ")";
    const QString tail = w.startsWith(QChar('!')) ? QStringLiteral("(?=$|\\s)") : QStringLiteral("(?=$|") + kWordRx + ")";
    const QRegularExpression rx(boundary + QStringLiteral("(") + QRegularExpression::escape(w) + QStringLiteral(")") + tail);
    const auto pm = rx.match(lowered);
    if(pm.hasMatch()) {
      out.priority = QString::fromLatin1(pw.priority);
      body.remove(pm.capturedStart(1), pm.capturedLength(1));
      break;
    }
  }

  // 5. "#label" tokens are labels, the way p1 is a priority: they leave the
  //    title. "#42" is an issue number and "C#" is a word, so a label needs
  //    a boundary before it and a letter first.
  static const QRegularExpression labelRx(QStringLiteral("(?:^|(?<=[\\s,;(]))#([A-Za-zА-Яа-яЁё][A-Za-zА-Яа-яЁё0-9_.\\-/]*)"));
  QRegularExpressionMatchIterator li = labelRx.globalMatch(body);
  QVector<QPair<int, int>> spans;
  while(li.hasNext()) {
    const auto m = li.next();
    QString label = m.captured(1);
    while(label.endsWith(QChar('.')) || label.endsWith(QChar('-')) || label.endsWith(QChar('/'))) {
      label.chop(1);  // sentence punctuation, not part of the label
    }
    if(!label.isEmpty() && !out.labels.contains(label, Qt::CaseInsensitive)) {
      out.labels.append(label);
    }
    spans.append({m.capturedStart(0), m.capturedLength(0)});
  }
  for(int i = static_cast<int>(spans.size()) - 1; i >= 0; --i) {
    body.remove(spans[i].first, spans[i].second);
  }

  // 6. A leading "ticket:" / "task:" / "todo:" / "задача:" says what the
  //    line is; it is not part of what the task is called.
  static const QRegularExpression markerRx(QStringLiteral("^\\s*(?:ticket|task|todo|тикет|задача)\\s*:\\s*"),
                                           QRegularExpression::CaseInsensitiveOption);
  body.remove(markerRx);

  // Collapse whitespace but otherwise preserve body verbatim.
  out.title = body.simplified();
  return out;
}

} // namespace heap::text
