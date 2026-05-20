#include "ChronoParser.h"

#include "ChronoLocale.h"
#include "ChronoTokenizer.h"

#include <QChar>
#include <QDate>
#include <QTime>

#include <algorithm>
#include <functional>

namespace heap::chrono {

namespace {

bool hasCyrillic(const QString &s) {
    for (const QChar &c : s) {
        if (c.script() == QChar::Script_Cyrillic) return true;
    }
    return false;
}

QString isoDay3(int iso) {
    switch (iso) {
        case 1: return QStringLiteral("mon");
        case 2: return QStringLiteral("tue");
        case 3: return QStringLiteral("wed");
        case 4: return QStringLiteral("thu");
        case 5: return QStringLiteral("fri");
        case 6: return QStringLiteral("sat");
        case 7: return QStringLiteral("sun");
    }
    return QString();
}

int lookupHash(const QHash<QString,int> &h, const QString &k, bool *found) {
    auto it = h.constFind(k);
    if (it == h.cend()) { *found = false; return 0; }
    *found = true;
    return *it;
}

int lookupHashAny(const QString &k, const QHash<QString,int> &a, const QHash<QString,int> &b, bool *found) {
    bool f1 = false;
    int v = lookupHash(a, k, &f1);
    if (f1) { *found = true; return v; }
    return lookupHash(b, k, found);
}

bool inListAny(const QString &k, const QStringList &a, const QStringList &b) {
    return a.contains(k) || b.contains(k);
}

} // namespace

class ChronoParser::Impl {
public:
    explicit Impl(QLocale loc) : m_loc(loc) {}

    ParseResult parse(const QString &input, const QDateTime &refIn) const {
        const QDateTime ref = refIn.isValid() ? refIn : QDateTime::currentDateTime();
        const bool cyr = hasCyrillic(input);
        const ChronoLocale *primary  = cyr ? &russianLocale() : &englishLocale();
        const ChronoLocale *fallback = cyr ? &englishLocale() : &russianLocale();

        ChronoTokenizer tk;
        auto toks = tk.tokenize(input);

        for (int start = 0; start < toks.size(); ++start) {
            const Token &t = toks[start];
            if (t.kind == TokenKind::End) break;
            if (t.kind == TokenKind::Punct) continue;
            ParseResult r = tryFrom(input, toks, start, ref, primary, fallback);
            if (r.ok) return r;
        }
        return {};
    }

    QVector<ParseResult> parseAll(const QString &input, const QDateTime &refIn) const {
        QVector<ParseResult> out;
        QString remaining = input;
        QDateTime ref = refIn.isValid() ? refIn : QDateTime::currentDateTime();
        int globalOffset = 0;

        while (!remaining.isEmpty()) {
            ParseResult r = parse(remaining, ref);
            if (!r.ok) break;
            r.startOffset += globalOffset;
            r.endOffset   += globalOffset;
            out.push_back(r);
            // advance past consumed range
            int adv = r.endOffset - globalOffset;
            if (adv <= 0) break;
            remaining = remaining.mid(adv);
            globalOffset += adv;
        }
        return out;
    }

private:
    QLocale m_loc;

    struct DateMatch {
        QDate date;
        int firstTok = -1;
        int lastTok  = -1;
    };
    struct TimeMatch {
        QTime time;
        QTime endTime;
        bool hasRange = false;
        bool hasMeridiem = false;
        bool pm = false;
        bool bare = false;     // true when first hour had no explicit marker
        int firstTok = -1;
        int lastTok  = -1;
    };

    // ── Top-level dispatcher ─────────────────────────────────────────────
    ParseResult tryFrom(const QString &input,
                        const QVector<Token> &toks, int i,
                        const QDateTime &ref,
                        const ChronoLocale *primary,
                        const ChronoLocale *fallback) const
    {
        ParseResult r;
        DateMatch dm;
        bool dateOk = false;
        QString recurrence;
        int recFirst = -1, recLast = -1;

        // Recurrence first ("every monday" — strongest signal).
        if (tryEveryPhrase(toks, i, ref, primary, fallback, dm, recurrence)) {
            dateOk = true;
            recFirst = dm.firstTok;
            recLast = dm.lastTok;
        }
        else if (tryNumericDate(toks, i, dm)) {
            dateOk = true;
        }
        else if (tryMonthNameDate(toks, i, primary, fallback, dm)) {
            dateOk = true;
        }
        else if (tryAgoPhrase(toks, i, ref, primary, fallback, dm)) {
            dateOk = true;
        }
        else if (tryRelativeOffsetPhrase(toks, i, ref, primary, fallback, dm)) {
            dateOk = true;
        }
        else if (tryNextWeekday(toks, i, ref, primary, fallback, dm)) {
            dateOk = true;
        }
        else if (tryRelativeAdjective(toks, i, ref, primary, fallback, dm)) {
            dateOk = true;
        }
        else if (tryBareWeekday(toks, i, ref, primary, fallback, dm)) {
            dateOk = true;
        }

        TimeMatch tm;
        bool timeOk = false;

        if (dateOk) {
            // Look for an optional time after the date.
            int j = dm.lastTok + 1;
            // Skip a connector (at / в / на / @).
            while (j < toks.size() && toks[j].kind == TokenKind::Punct) ++j;
            bool consumedAt = false;
            if (j < toks.size() && toks[j].kind == TokenKind::Word &&
                inListAny(toks[j].lower, primary->atWords, fallback->atWords))
            {
                consumedAt = true;
                ++j;
            }
            TimeMatch maybe;
            if (tryRangeOrSingleTime(toks, j, primary, fallback, /*allowBareHour=*/consumedAt, maybe)) {
                tm = maybe;
                timeOk = true;
            }
        } else {
            // Time-only expression (no date).
            int ti = i;
            bool consumedAtOnly = false;
            if (ti < toks.size() && toks[ti].kind == TokenKind::Word &&
                inListAny(toks[ti].lower, primary->atWords, fallback->atWords))
            {
                consumedAtOnly = true;
                ++ti;
            }
            if (tryFromToTime(toks, ti, primary, fallback, tm) ||
                tryRangeOrSingleTime(toks, ti, primary, fallback,
                                     /*allowBareHour=*/consumedAtOnly, tm))
            {
                timeOk = true;
                dm.date = ref.date();
                dm.firstTok = consumedAtOnly ? i : tm.firstTok;
                dm.lastTok  = tm.lastTok;
                dateOk = true;
            }
        }

        if (!dateOk) return r;

        // ── Assemble result ──
        r.ok = true;
        r.recurrence = recurrence;

        QTime startTime(0, 0);
        QTime endTime;
        bool hasTime = false;

        if (timeOk) {
            startTime = applyMeridiem(tm.time, tm.hasMeridiem, tm.pm);
            hasTime = true;
            if (tm.hasRange) {
                endTime = applyMeridiem(tm.endTime, tm.hasMeridiem, tm.pm);
            }
            // include time tokens in consumed range
            if (recFirst < 0) {
                dm.lastTok = std::max(dm.lastTok, tm.lastTok);
            } else {
                dm.lastTok = std::max(recLast, tm.lastTok);
            }
        }

        r.start = QDateTime(dm.date, startTime);
        if (timeOk && tm.hasRange) {
            r.end = QDateTime(dm.date, endTime);
        }
        r.hasTime = hasTime;

        const Token &firstT = toks[recFirst >= 0 ? recFirst : dm.firstTok];
        const Token &lastT  = toks[dm.lastTok];
        r.startOffset = firstT.pos;
        r.endOffset   = lastT.pos + lastT.len;
        r.consumed    = input.mid(r.startOffset, r.endOffset - r.startOffset);
        return r;
    }

    // ── Numeric date (ISO / DD.MM[.YYYY] / D/M[/Y]) ───────────────────────
    bool tryNumericDate(const QVector<Token> &toks, int i, DateMatch &out) const {
        if (i + 4 < toks.size() &&
            toks[i].kind == TokenKind::Number &&
            toks[i+1].kind == TokenKind::Dash &&
            toks[i+2].kind == TokenKind::Number &&
            toks[i+3].kind == TokenKind::Dash &&
            toks[i+4].kind == TokenKind::Number)
        {
            int a = toks[i].value, b = toks[i+2].value, c = toks[i+4].value;
            QDate d;
            if (toks[i].len == 4) d = QDate(a, b, c);        // YYYY-MM-DD
            else                  d = makeSlashDate(a, b, c, /*dotted=*/true); // fallback
            if (d.isValid()) {
                out.date = d;
                out.firstTok = i;
                out.lastTok  = i + 4;
                return true;
            }
        }

        // DD.MM[.YYYY]
        if (i + 2 < toks.size() &&
            toks[i].kind == TokenKind::Number &&
            toks[i+1].kind == TokenKind::Dot &&
            toks[i+2].kind == TokenKind::Number)
        {
            int day = toks[i].value;
            int month = toks[i+2].value;
            int year = QDate::currentDate().year();
            int last = i + 2;
            if (i + 4 < toks.size() &&
                toks[i+3].kind == TokenKind::Dot &&
                toks[i+4].kind == TokenKind::Number)
            {
                year = toks[i+4].value;
                if (year < 100) year += 2000;
                last = i + 4;
            }
            QDate d(year, month, day);
            if (d.isValid()) {
                out.date = d;
                out.firstTok = i;
                out.lastTok  = last;
                return true;
            }
        }

        // D/M[/Y] — slashes
        if (i + 2 < toks.size() &&
            toks[i].kind == TokenKind::Number &&
            toks[i+1].kind == TokenKind::Slash &&
            toks[i+2].kind == TokenKind::Number)
        {
            int a = toks[i].value;
            int b = toks[i+2].value;
            int year = QDate::currentDate().year();
            int last = i + 2;
            if (i + 4 < toks.size() &&
                toks[i+3].kind == TokenKind::Slash &&
                toks[i+4].kind == TokenKind::Number)
            {
                year = toks[i+4].value;
                if (year < 100) year += 2000;
                last = i + 4;
            }
            QDate d = makeSlashDate(a, b, year, /*dotted=*/false);
            if (d.isValid()) {
                out.date = d;
                out.firstTok = i;
                out.lastTok  = last;
                return true;
            }
        }
        return false;
    }

    QDate makeSlashDate(int a, int b, int year, bool dotted) const {
        // dotted: D.M (European convention always)
        // slashed: M/D or D/M based on user locale
        int day, month;
        if (a > 12) { day = a; month = b; }
        else if (b > 12) { month = a; day = b; }
        else if (dotted) { day = a; month = b; }
        else {
            bool monthFirst =
                m_loc.dateFormat(QLocale::ShortFormat).startsWith(QLatin1Char('M'),
                                                                  Qt::CaseInsensitive);
            if (monthFirst) { month = a; day = b; }
            else            { day = a; month = b; }
        }
        return QDate(year, month, day);
    }

    // ── Month-name date ("22 May" / "May 22" / "22 мая [2026]") ───────────
    bool tryMonthNameDate(const QVector<Token> &toks, int i,
                          const ChronoLocale *primary,
                          const ChronoLocale *fallback,
                          DateMatch &out) const
    {
        if (i >= toks.size()) return false;
        // "22 mayWord"
        if (toks[i].kind == TokenKind::Number &&
            i + 1 < toks.size() &&
            toks[i+1].kind == TokenKind::Word)
        {
            bool found = false;
            int m = lookupHashAny(toks[i+1].lower, primary->monthNames, fallback->monthNames, &found);
            if (found) {
                int day = toks[i].value;
                int year = QDate::currentDate().year();
                int last = i + 1;
                if (i + 2 < toks.size() && toks[i+2].kind == TokenKind::Number) {
                    year = toks[i+2].value;
                    if (year < 100) year += 2000;
                    last = i + 2;
                }
                QDate d(year, m, day);
                if (d.isValid()) {
                    out.date = d;
                    out.firstTok = i;
                    out.lastTok = last;
                    return true;
                }
            }
        }
        // "mayWord 22 [2026]"
        if (toks[i].kind == TokenKind::Word &&
            i + 1 < toks.size() &&
            toks[i+1].kind == TokenKind::Number)
        {
            bool found = false;
            int m = lookupHashAny(toks[i].lower, primary->monthNames, fallback->monthNames, &found);
            if (found) {
                int day = toks[i+1].value;
                int year = QDate::currentDate().year();
                int last = i + 1;
                if (i + 2 < toks.size() && toks[i+2].kind == TokenKind::Number &&
                    toks[i+2].value >= 1000)
                {
                    year = toks[i+2].value;
                    last = i + 2;
                }
                QDate d(year, m, day);
                if (d.isValid()) {
                    out.date = d;
                    out.firstTok = i;
                    out.lastTok = last;
                    return true;
                }
            }
        }
        return false;
    }

    // ── Relative offset ("in 3 days" / "через 2 недели") ──────────────────
    bool tryRelativeOffsetPhrase(const QVector<Token> &toks, int i,
                                 const QDateTime &ref,
                                 const ChronoLocale *primary,
                                 const ChronoLocale *fallback,
                                 DateMatch &out) const
    {
        if (i >= toks.size() || toks[i].kind != TokenKind::Word) return false;
        if (!inListAny(toks[i].lower, primary->relPrefixes, fallback->relPrefixes))
            return false;
        if (i + 2 >= toks.size()) return false;
        if (toks[i+1].kind != TokenKind::Number) return false;
        if (toks[i+2].kind != TokenKind::Word) return false;
        bool foundUnit = false;
        int days = lookupHashAny(toks[i+2].lower, primary->unitToDays, fallback->unitToDays, &foundUnit);
        if (!foundUnit) return false;
        int n = toks[i+1].value;

        bool isMonth = primary->monthUnits.contains(toks[i+2].lower) ||
                       fallback->monthUnits.contains(toks[i+2].lower);
        bool isYear  = primary->yearUnits.contains(toks[i+2].lower) ||
                       fallback->yearUnits.contains(toks[i+2].lower);

        QDate d = ref.date();
        if (isYear)       d = d.addYears(n);
        else if (isMonth) d = d.addMonths(n);
        else              d = d.addDays(days * n);

        out.date = d;
        out.firstTok = i;
        out.lastTok = i + 2;
        return true;
    }

    // ── "N units ago" / "N единиц назад" ──────────────────────────────────
    bool tryAgoPhrase(const QVector<Token> &toks, int i,
                      const QDateTime &ref,
                      const ChronoLocale *primary,
                      const ChronoLocale *fallback,
                      DateMatch &out) const
    {
        if (i + 2 >= toks.size()) return false;
        if (toks[i].kind != TokenKind::Number) return false;
        if (toks[i+1].kind != TokenKind::Word) return false;
        if (toks[i+2].kind != TokenKind::Word) return false;
        bool foundUnit = false;
        int days = lookupHashAny(toks[i+1].lower, primary->unitToDays, fallback->unitToDays, &foundUnit);
        if (!foundUnit) return false;
        if (!inListAny(toks[i+2].lower, primary->suffixes, fallback->suffixes)) return false;

        int n = toks[i].value;
        bool isMonth = primary->monthUnits.contains(toks[i+1].lower) ||
                       fallback->monthUnits.contains(toks[i+1].lower);
        bool isYear  = primary->yearUnits.contains(toks[i+1].lower) ||
                       fallback->yearUnits.contains(toks[i+1].lower);

        QDate d = ref.date();
        if (isYear)       d = d.addYears(-n);
        else if (isMonth) d = d.addMonths(-n);
        else              d = d.addDays(-days * n);

        out.date = d;
        out.firstTok = i;
        out.lastTok = i + 2;
        return true;
    }

    // ── Relative adjective ("today"/"завтра") ─────────────────────────────
    bool tryRelativeAdjective(const QVector<Token> &toks, int i,
                              const QDateTime &ref,
                              const ChronoLocale *primary,
                              const ChronoLocale *fallback,
                              DateMatch &out) const
    {
        if (i >= toks.size() || toks[i].kind != TokenKind::Word) return false;
        bool found = false;
        int off = lookupHashAny(toks[i].lower,
                                primary->relativeAdjectives,
                                fallback->relativeAdjectives, &found);
        if (!found) return false;
        out.date = ref.date().addDays(off);
        out.firstTok = i;
        out.lastTok = i;
        return true;
    }

    // ── "next monday" / "след пн" / "след. понедельник" ───────────────────
    bool tryNextWeekday(const QVector<Token> &toks, int i,
                        const QDateTime &ref,
                        const ChronoLocale *primary,
                        const ChronoLocale *fallback,
                        DateMatch &out) const
    {
        if (i >= toks.size() || toks[i].kind != TokenKind::Word) return false;
        if (!inListAny(toks[i].lower, primary->nextAdjectives, fallback->nextAdjectives))
            return false;
        int j = i + 1;
        // Allow "след." (next + dot) idiom.
        if (j < toks.size() && toks[j].kind == TokenKind::Dot) ++j;
        if (j >= toks.size() || toks[j].kind != TokenKind::Word) return false;
        bool found = false;
        int iso = lookupHashAny(toks[j].lower,
                                primary->weekdayNames,
                                fallback->weekdayNames, &found);
        if (!found) return false;
        int curIso = ref.date().dayOfWeek();
        int delta = (iso - curIso + 7) % 7;
        if (delta == 0) delta = 7;
        out.date = ref.date().addDays(delta);
        out.firstTok = i;
        out.lastTok = j;
        return true;
    }

    // ── Bare weekday ("monday") — upcoming, today included ────────────────
    bool tryBareWeekday(const QVector<Token> &toks, int i,
                        const QDateTime &ref,
                        const ChronoLocale *primary,
                        const ChronoLocale *fallback,
                        DateMatch &out) const
    {
        if (i >= toks.size() || toks[i].kind != TokenKind::Word) return false;
        bool found = false;
        int iso = lookupHashAny(toks[i].lower,
                                primary->weekdayNames,
                                fallback->weekdayNames, &found);
        if (!found) return false;
        int curIso = ref.date().dayOfWeek();
        int delta = (iso - curIso + 7) % 7;
        out.date = ref.date().addDays(delta);
        out.firstTok = i;
        out.lastTok = i;
        return true;
    }

    // ── "every monday" / "каждую среду" / "every weekday" / "every day" ──
    bool tryEveryPhrase(const QVector<Token> &toks, int i,
                        const QDateTime &ref,
                        const ChronoLocale *primary,
                        const ChronoLocale *fallback,
                        DateMatch &out, QString &recurrence) const
    {
        if (i >= toks.size() || toks[i].kind != TokenKind::Word) return false;
        if (!inListAny(toks[i].lower, primary->everyAdjectives, fallback->everyAdjectives))
            return false;
        if (i + 1 >= toks.size() || toks[i+1].kind != TokenKind::Word) return false;
        QString w = toks[i+1].lower;

        // "every weekday"
        if (w == QStringLiteral("weekday") || w == QString::fromUtf8("будни")) {
            int curIso = ref.date().dayOfWeek();
            QDate d = ref.date();
            if (curIso > 5) d = d.addDays(8 - curIso); // Sat->Mon, Sun->Mon
            recurrence = QStringLiteral("every:weekday");
            out.date = d;
            out.firstTok = i;
            out.lastTok = i + 1;
            return true;
        }
        // "every day" / "каждый день"
        bool foundUnit = false;
        int days = lookupHashAny(w, primary->unitToDays, fallback->unitToDays, &foundUnit);
        if (foundUnit && days == 1) {
            recurrence = QStringLiteral("every:day");
            out.date = ref.date();
            out.firstTok = i;
            out.lastTok = i + 1;
            return true;
        }
        if (foundUnit && days == 7) {
            recurrence = QStringLiteral("every:week");
            out.date = ref.date();
            out.firstTok = i;
            out.lastTok = i + 1;
            return true;
        }
        // "every <weekday>"
        bool found = false;
        int iso = lookupHashAny(w, primary->weekdayNames, fallback->weekdayNames, &found);
        if (!found) return false;
        recurrence = QStringLiteral("every:") + isoDay3(iso);
        int curIso = ref.date().dayOfWeek();
        int delta = (iso - curIso + 7) % 7;
        out.date = ref.date().addDays(delta);
        out.firstTok = i;
        out.lastTok = i + 1;
        return true;
    }

    // ── Time-of-day (single) ──────────────────────────────────────────────
    bool tryTimeOfDay(const QVector<Token> &toks, int i,
                      const ChronoLocale *primary,
                      const ChronoLocale *fallback,
                      bool allowBareHour,
                      TimeMatch &out) const
    {
        if (i >= toks.size() || toks[i].kind != TokenKind::Number) return false;
        int hour = toks[i].value;
        if (hour < 0 || hour > 23) return false;

        int last = i;
        int minute = 0;
        bool explicitMarker = false;
        bool hasMer = false;
        bool pm = false;

        // HH:MM
        if (i + 2 < toks.size() &&
            toks[i+1].kind == TokenKind::Colon &&
            toks[i+2].kind == TokenKind::Number)
        {
            minute = toks[i+2].value;
            if (minute < 0 || minute > 59) return false;
            last = i + 2;
            explicitMarker = true;
        }
        // HH MM (space-separated; require 2-digit minute 0..59 so we don't
        // collide with "in 2 weeks" or "every 1 day").
        else if (i + 1 < toks.size() &&
                 toks[i+1].kind == TokenKind::Number &&
                 toks[i+1].len == 2 &&
                 toks[i+1].value >= 0 && toks[i+1].value < 60)
        {
            minute = toks[i+1].value;
            last = i + 1;
            explicitMarker = true;
        }

        // Optional am/pm or hour-suffix word glued (e.g. "2pm", "14ч").
        if (last + 1 < toks.size() && toks[last+1].kind == TokenKind::Word) {
            const QString &w = toks[last+1].lower;
            if (!primary->amSuffix.isEmpty() && w == primary->amSuffix) {
                hasMer = true; pm = false; ++last;
            } else if (!primary->pmSuffix.isEmpty() && w == primary->pmSuffix) {
                hasMer = true; pm = true; ++last;
            } else if (!fallback->amSuffix.isEmpty() && w == fallback->amSuffix) {
                hasMer = true; pm = false; ++last;
            } else if (!fallback->pmSuffix.isEmpty() && w == fallback->pmSuffix) {
                hasMer = true; pm = true; ++last;
            } else if (inListAny(w, primary->hourSuffixes, fallback->hourSuffixes)) {
                explicitMarker = true; ++last;
            }
        }

        if (!explicitMarker && !hasMer && !allowBareHour) return false;

        out.time = QTime(hour, minute);
        out.firstTok = i;
        out.lastTok = last;
        out.hasMeridiem = hasMer;
        out.pm = pm;
        out.hasRange = false;
        out.bare = (!explicitMarker && !hasMer);
        return true;
    }

    // ── Range or single ("9-10", "2-3pm", "14:00") ────────────────────────
    bool tryRangeOrSingleTime(const QVector<Token> &toks, int i,
                              const ChronoLocale *primary,
                              const ChronoLocale *fallback,
                              bool allowBareHour,
                              TimeMatch &out) const
    {
        // Try first time. For range form "N-M", allow bare hour.
        TimeMatch first;
        // Detect range "N - M[pm/am/:MM]" by lookahead.
        bool isRangeShape = (i + 2 < toks.size() &&
                             toks[i].kind == TokenKind::Number &&
                             toks[i+1].kind == TokenKind::Dash &&
                             toks[i+2].kind == TokenKind::Number);

        if (!tryTimeOfDay(toks, i, primary, fallback, /*allowBareHour=*/(allowBareHour || isRangeShape), first))
            return false;

        // Range?
        if (first.lastTok + 1 < toks.size() &&
            toks[first.lastTok+1].kind == TokenKind::Dash)
        {
            TimeMatch second;
            if (tryTimeOfDay(toks, first.lastTok+2, primary, fallback,
                             /*allowBareHour=*/true, second))
            {
                // Meridiem on second propagates to first if first had none.
                bool hasMer = second.hasMeridiem || first.hasMeridiem;
                bool pm = second.hasMeridiem ? second.pm : first.pm;

                out = first;
                out.hasRange = true;
                out.endTime = second.time;
                out.hasMeridiem = hasMer;
                out.pm = pm;
                out.lastTok = second.lastTok;
                return true;
            }
        }
        // Bare-hour first match only kept when caller permitted it.
        if (first.bare && !allowBareHour) return false;
        out = first;
        return true;
    }

    // ── "from X to Y" / "с X до Y" ────────────────────────────────────────
    bool tryFromToTime(const QVector<Token> &toks, int i,
                       const ChronoLocale *primary,
                       const ChronoLocale *fallback,
                       TimeMatch &out) const
    {
        if (i >= toks.size() || toks[i].kind != TokenKind::Word) return false;
        if (!inListAny(toks[i].lower, primary->fromWords, fallback->fromWords))
            return false;
        TimeMatch first;
        if (!tryTimeOfDay(toks, i + 1, primary, fallback, /*allowBareHour=*/true, first))
            return false;
        int j = first.lastTok + 1;
        if (j >= toks.size() || toks[j].kind != TokenKind::Word) return false;
        if (!inListAny(toks[j].lower, primary->toWords, fallback->toWords)) return false;
        TimeMatch second;
        if (!tryTimeOfDay(toks, j + 1, primary, fallback, /*allowBareHour=*/true, second))
            return false;

        out.time = first.time;
        out.endTime = second.time;
        out.hasRange = true;
        out.hasMeridiem = first.hasMeridiem || second.hasMeridiem;
        out.pm = second.hasMeridiem ? second.pm : first.pm;
        out.firstTok = i;
        out.lastTok = second.lastTok;
        return true;
    }

    QTime applyMeridiem(const QTime &t, bool hasMer, bool pm) const {
        if (!hasMer) return t;
        int h = t.hour();
        if (pm && h < 12) h += 12;
        else if (!pm && h == 12) h = 0;
        return QTime(h, t.minute());
    }
};

ChronoParser::ChronoParser(const QLocale &userLocale)
    : m_impl(std::make_unique<Impl>(userLocale)) {}

ChronoParser::~ChronoParser() = default;

ParseResult ChronoParser::parse(const QString &text, const QDateTime &now) const {
    return m_impl->parse(text, now);
}

QVector<ParseResult> ChronoParser::parseAll(const QString &text, const QDateTime &now) const {
    return m_impl->parseAll(text, now);
}

} // namespace heap::chrono
