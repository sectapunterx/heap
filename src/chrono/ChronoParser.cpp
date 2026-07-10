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

        // ── Primary pass ──
        // Left-to-right, take the first position that yields a date (with an
        // optional adjacent time) or a bare time. Behaviour here is identical to
        // the original single-pass parser, so every existing expression resolves
        // exactly as before.
        FromMatch best;
        for (int start = 0; start < toks.size(); ++start) {
            const Token &t = toks[start];
            if (t.kind == TokenKind::End) break;
            if (t.kind == TokenKind::Punct) continue;
            FromMatch m = tryFromEx(toks, start, ref, primary, fallback);
            if (m.ok) { best = m; break; }
        }
        if (!best.ok) return {};

        // ── Complementary pass ──
        // A date (weekday, "tomorrow", …) and a clock time are two orderable
        // halves the user may type in either order — "понедельник 13:00" or
        // "13:00 понедельник" — and a mention or connector can sit between them.
        // When the primary pass captured only one half, look for the other half
        // elsewhere in the token stream and fold it in. We only bridge a gap of
        // pure "noise" (punctuation, an at-connector like "в"/"at", or an
        // @handle) so real title words that merely sit between two far-apart
        // phrases are never swallowed.
        if (best.hasExplicitDate && !best.hasTime) {
            TimeMatch tm;
            int tFirst = -1, tLast = -1;
            if (findTimeOutside(toks, best.dateFirst, best.dateLast, primary, fallback, tm, tFirst, tLast) &&
                gapIsNoise(toks, best.dateFirst, best.dateLast, tFirst, tLast, primary, fallback))
            {
                best.hasTime = true;
                best.start = applyMeridiem(tm.time, tm.hasMeridiem, tm.pm);
                best.hasRange = tm.hasRange;
                if (tm.hasRange) best.end = applyMeridiem(tm.endTime, tm.hasMeridiem, tm.pm);
                best.timeFirst = tFirst;
                best.timeLast = tLast;
            }
        } else if (!best.hasExplicitDate && best.hasTime) {
            DateMatch dm;
            QString rec;
            int recF = -1, recL = -1;
            if (findDateOutside(toks, best.timeFirst, best.timeLast, ref, primary, fallback, dm, rec, recF, recL) &&
                gapIsNoise(toks, best.timeFirst, best.timeLast, (recF >= 0 ? recF : dm.firstTok), dm.lastTok,
                           primary, fallback))
            {
                best.hasExplicitDate = true;
                best.date = dm.date;
                best.recurrence = rec;
                best.dateFirst = (recF >= 0 ? recF : dm.firstTok);
                best.dateLast = dm.lastTok;
            }
        }

        return assemble(input, toks, best);
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

    // One dispatcher outcome, kept as separable halves so the complementary
    // pass can fold in a missing date or time. Times are stored post-meridiem.
    struct FromMatch {
        bool ok = false;
        bool hasExplicitDate = false;  // a real date matched (not the ref-date default)
        bool hasTime = false;
        QDate date;
        QTime start{0, 0};
        QTime end;
        bool hasRange = false;
        QString recurrence;
        int dateFirst = -1, dateLast = -1;  // token span of the date half
        int timeFirst = -1, timeLast = -1;  // token span of the time half
    };

    // ── Date cascade ─────────────────────────────────────────────────────
    // Runs the date sub-matchers in priority order. recFirst/recLast are set
    // only for a recurrence ("every monday"), otherwise left at -1.
    bool matchDate(const QVector<Token> &toks, int i, const QDateTime &ref,
                   const ChronoLocale *primary, const ChronoLocale *fallback,
                   DateMatch &dm, QString &recurrence, int &recFirst, int &recLast) const
    {
        recFirst = -1;
        recLast = -1;
        // Recurrence first ("every monday" — strongest signal).
        if (tryEveryPhrase(toks, i, ref, primary, fallback, dm, recurrence)) {
            recFirst = dm.firstTok;
            recLast = dm.lastTok;
            return true;
        }
        if (tryNumericDate(toks, i, dm)) return true;
        if (tryMonthNameDate(toks, i, primary, fallback, dm)) return true;
        if (tryAgoPhrase(toks, i, ref, primary, fallback, dm)) return true;
        if (tryRelativeOffsetPhrase(toks, i, ref, primary, fallback, dm)) return true;
        if (tryNextWeekday(toks, i, ref, primary, fallback, dm)) return true;
        if (tryRelativeAdjective(toks, i, ref, primary, fallback, dm)) return true;
        if (tryBareWeekday(toks, i, ref, primary, fallback, dm)) return true;
        return false;
    }

    // ── Top-level dispatcher ─────────────────────────────────────────────
    // Same grammar as before: a date with an optional adjacent time, or a bare
    // time. Result is returned as separable halves (see FromMatch).
    FromMatch tryFromEx(const QVector<Token> &toks, int i,
                        const QDateTime &ref,
                        const ChronoLocale *primary,
                        const ChronoLocale *fallback) const
    {
        FromMatch out;
        DateMatch dm;
        QString recurrence;
        int recFirst = -1, recLast = -1;
        const bool dateOk = matchDate(toks, i, ref, primary, fallback, dm, recurrence, recFirst, recLast);

        TimeMatch tm;
        bool timeOk = false;

        if (dateOk) {
            out.hasExplicitDate = true;
            out.date = dm.date;
            out.recurrence = recurrence;
            out.dateFirst = (recFirst >= 0 ? recFirst : dm.firstTok);
            out.dateLast = dm.lastTok;

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
                out.timeFirst = tm.firstTok;
                out.timeLast = tm.lastTok;
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
                out.hasExplicitDate = false;
                out.date = ref.date();
                out.timeFirst = consumedAtOnly ? i : tm.firstTok;
                out.timeLast = tm.lastTok;
            }
        }

        if (!dateOk && !timeOk) return out;  // ok == false

        out.hasTime = timeOk;
        if (timeOk) {
            out.start = applyMeridiem(tm.time, tm.hasMeridiem, tm.pm);
            out.hasRange = tm.hasRange;
            if (tm.hasRange) out.end = applyMeridiem(tm.endTime, tm.hasMeridiem, tm.pm);
        }
        out.ok = true;
        return out;
    }

    // ── Assemble a ParseResult from a (possibly merged) FromMatch ──────────
    ParseResult assemble(const QString &input, const QVector<Token> &toks,
                         const FromMatch &m) const
    {
        ParseResult r;
        r.ok = true;
        r.recurrence = m.recurrence;
        r.hasTime = m.hasTime;
        r.start = QDateTime(m.date, m.hasTime ? m.start : QTime(0, 0));
        if (m.hasTime && m.hasRange) r.end = QDateTime(m.date, m.end);

        // Consumed span = union of the date and time halves. B (the time or the
        // complementary date) is always to the right of A here, but min/max keeps
        // this order-independent.
        int first = m.dateFirst;
        int last = m.dateLast;
        if (m.timeFirst >= 0) {
            first = (first < 0 ? m.timeFirst : std::min(first, m.timeFirst));
            last = std::max(last, m.timeLast);
        }
        const Token &firstT = toks[first];
        const Token &lastT = toks[last];
        r.startOffset = firstT.pos;
        r.endOffset = lastT.pos + lastT.len;
        r.consumed = input.mid(r.startOffset, r.endOffset - r.startOffset);
        return r;
    }

    // ── Complementary date search ─────────────────────────────────────────
    // Find a date anywhere outside [exclFirst, exclLast] (the already-matched
    // time span). Used to recover "13:00 понедельник" (time before date).
    bool findDateOutside(const QVector<Token> &toks, int exclFirst, int exclLast,
                         const QDateTime &ref,
                         const ChronoLocale *primary, const ChronoLocale *fallback,
                         DateMatch &dm, QString &rec, int &recF, int &recL) const
    {
        for (int p = 0; p < toks.size(); ++p) {
            const Token &t = toks[p];
            if (t.kind == TokenKind::End) break;
            if (t.kind == TokenKind::Punct) continue;
            if (p >= exclFirst && p <= exclLast) continue;
            DateMatch cand;
            QString r;
            int rf = -1, rl = -1;
            if (!matchDate(toks, p, ref, primary, fallback, cand, r, rf, rl)) continue;
            const int cf = (rf >= 0 ? rf : cand.firstTok);
            if (cf <= exclLast && cand.lastTok >= exclFirst) continue;  // overlaps the time
            dm = cand;
            rec = r;
            recF = rf;
            recL = rl;
            return true;
        }
        return false;
    }

    // ── Complementary time search ─────────────────────────────────────────
    // Find a clock time anywhere outside [exclFirst, exclLast] (the matched date
    // span). Recovers "понедельник @el 13:00" where a mention breaks adjacency.
    bool findTimeOutside(const QVector<Token> &toks, int exclFirst, int exclLast,
                         const ChronoLocale *primary, const ChronoLocale *fallback,
                         TimeMatch &out, int &spanFirst, int &spanLast) const
    {
        for (int p = 0; p < toks.size(); ++p) {
            const Token &t = toks[p];
            if (t.kind == TokenKind::End) break;
            if (t.kind == TokenKind::Punct) continue;
            if (p >= exclFirst && p <= exclLast) continue;
            int ti = p;
            bool consumedAt = false;
            if (toks[p].kind == TokenKind::Word &&
                inListAny(toks[p].lower, primary->atWords, fallback->atWords))
            {
                consumedAt = true;
                ti = p + 1;
            }
            if (ti >= exclFirst && ti <= exclLast) continue;
            TimeMatch tm;
            if (tryFromToTime(toks, ti, primary, fallback, tm) ||
                tryRangeOrSingleTime(toks, ti, primary, fallback, /*allowBareHour=*/consumedAt, tm))
            {
                if (tm.firstTok <= exclLast && tm.lastTok >= exclFirst) continue;  // overlaps the date
                out = tm;
                spanFirst = p;  // include a leading at-connector
                spanLast = tm.lastTok;
                return true;
            }
        }
        return false;
    }

    // Every token strictly between the two spans must be "noise" — punctuation,
    // an at-connector, or an @handle word — so bridging two halves never eats a
    // real title word that happens to sit between two far-apart phrases.
    bool gapIsNoise(const QVector<Token> &toks, int aFirst, int aLast, int bFirst, int bLast,
                    const ChronoLocale *primary, const ChronoLocale *fallback) const
    {
        int lo, hi;
        if (aLast < bFirst) { lo = aLast + 1; hi = bFirst - 1; }
        else if (bLast < aFirst) { lo = bLast + 1; hi = aFirst - 1; }
        else return true;  // adjacent or overlapping — no gap
        for (int k = lo; k <= hi; ++k) {
            const Token &t = toks[k];
            // A bare number is content (a ticket id, quantity, version), never
            // noise — bridging across it would swallow it out of the title.
            if (t.kind == TokenKind::Number) return false;
            if (t.kind != TokenKind::Word) continue;  // punctuation is always noise
            if (inListAny(t.lower, primary->atWords, fallback->atWords)) continue;
            if (inListAny(t.lower, primary->fromWords, fallback->fromWords)) continue;
            if (inListAny(t.lower, primary->toWords, fallback->toWords)) continue;
            // An @handle: a word immediately preceded by a bare '@'.
            if (k > 0 && toks[k - 1].kind == TokenKind::Punct &&
                toks[k - 1].text == QStringLiteral("@"))
                continue;
            return false;  // a real word — refuse to bridge
        }
        return true;
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
