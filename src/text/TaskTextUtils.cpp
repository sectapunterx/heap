#include "TaskTextUtils.h"

#include <QChar>
#include <QHash>
#include <QRegularExpression>

namespace heap::text {

namespace {

// Latin + Cyrillic + digit + underscore. Used as the "word character" class so
// "созвон" and "митап" match cleanly. Avoids ES2018 \p{L} (unsupported in
// Qt6's V4 JS engine, but here we are pure C++ — still cheaper than a Unicode
// table lookup).
constexpr const char *kWordRx = "[^a-zA-Zа-яА-ЯёЁ0-9_]";

bool containsWord(const QString &haystackLowered, const QString &needleLowered) {
    if (needleLowered.isEmpty()) return false;
    QString escaped = QRegularExpression::escape(needleLowered);
    // (^|<non-word>)needle(<non-word>|$)
    const QString pattern = QStringLiteral("(?:^|") + kWordRx + ")"
                          + escaped + QStringLiteral("(?:") + kWordRx + "|$)";
    QRegularExpression rx(pattern);
    return rx.match(haystackLowered).hasMatch();
}

bool anyHits(const QString &lowered, const QStringList &words) {
    for (const QString &w : words)
        if (containsWord(lowered, w)) return true;
    return false;
}

const QStringList &focusWords() {
    static const QStringList w = {
        "focus", "focusmode", "focus-mode", "focus mode", "focus_mode",
        "фокус", "фокус-режим", "фокус режим", "фокус-мод",
        "deep work", "deepwork", "глубокая работа"
    };
    return w;
}

const QStringList &syncWords() {
    static const QStringList w = {
        "синк", "sync", "созвон", "созвоны", "созвонимся", "созвониться",
        "митап", "meetup", "meet", "meeting", "митинг", "митинги",
        "звонок", "видеозвонок", "call", "conference", "конференция",
        "standup", "стендап", "дейли", "daily",
        "ревью", "review", "code review", "код-ревью",
        "one-on-one", "one on one", "1:1", "1-1", "1on1", "one to one"
    };
    return w;
}

const QStringList &ticketWords() {
    static const QStringList w = {
        "тикет", "тикета", "тикеты", "задача", "задачу", "задачи",
        "task", "tasks", "issue", "issues", "story",
        "эпик", "epic", "bug", "баг"
    };
    return w;
}

const QStringList &contactWords() {
    static const QStringList w = {
        "написать", "напиши", "пиши", "написал", "пишу", "напомни",
        "напомнить", "спросить", "спроси", "ответить",
        "ping", "ask", "remind", "message", "msg", "dm"
    };
    return w;
}

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
    if (anyHits(s, syncWords()))   return TaskKind::Sync;
    return TaskKind::None;
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

TaskMeta extractMeta(QStringView raw) {
    TaskMeta out;
    QString text = raw.toString();

    // 1. "// comment" → desc. Split on the first occurrence.
    const int dslash = text.indexOf(QStringLiteral("//"));
    QString body = text;
    if (dslash >= 0) {
        out.desc = text.mid(dslash + 2).trimmed();
        body     = text.left(dslash);
    }

    // 2. "@handle" tokens → collected into handles[], but LEFT IN PLACE in
    //    the title so the user keeps the context they typed ("синк с
    //    @viktor"). Leading boundary must be start-of-string or one of
    //    whitespace / punctuation, so e-mail addresses are not picked up.
    static const QRegularExpression rx(
        QStringLiteral("(?:^|[\\s,;\\(])@([A-Za-zА-Яа-яЁё0-9_.\\-]+)"));
    QRegularExpressionMatchIterator it = rx.globalMatch(body);
    while (it.hasNext()) {
        const auto m = it.next();
        out.handles.append(m.captured(1));
    }

    // Collapse whitespace but otherwise preserve body verbatim.
    out.title = body.simplified();
    return out;
}

} // namespace heap::text
