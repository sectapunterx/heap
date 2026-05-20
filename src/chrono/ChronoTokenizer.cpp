#include "ChronoTokenizer.h"

#include <QChar>

namespace heap::chrono {

namespace {

bool isWordChar(QChar c) {
    if (c.isLetter()) return true;
    if (c == QLatin1Char('\'')) return true;
    return false;
}

bool isDigit(QChar c) {
    return c.isDigit();
}

bool isPunctEmitted(QChar c, TokenKind &kindOut) {
    if (c == QLatin1Char(':')) { kindOut = TokenKind::Colon; return true; }
    if (c == QLatin1Char('.')) { kindOut = TokenKind::Dot;   return true; }
    if (c == QLatin1Char('-')) { kindOut = TokenKind::Dash;  return true; }
    if (c == QLatin1Char('/')) { kindOut = TokenKind::Slash; return true; }
    return false;
}

} // namespace

QVector<Token> ChronoTokenizer::tokenize(const QString &input) const {
    QVector<Token> out;
    const int n = input.size();
    int i = 0;
    while (i < n) {
        const QChar c = input[i];
        if (c.isSpace()) { ++i; continue; }

        TokenKind punctKind;
        if (isPunctEmitted(c, punctKind)) {
            Token t;
            t.kind = punctKind;
            t.text = QString(c);
            t.lower = t.text;
            t.pos = i;
            t.len = 1;
            out.push_back(t);
            ++i;
            continue;
        }

        if (isDigit(c)) {
            int start = i;
            while (i < n && isDigit(input[i])) ++i;
            Token t;
            t.kind = TokenKind::Number;
            t.text = input.mid(start, i - start);
            t.lower = t.text;
            t.value = t.text.toInt();
            t.pos = start;
            t.len = i - start;
            out.push_back(t);
            // Possible am/pm suffix glued to digits, e.g. "2pm".
            if (i < n && input[i].isLetter()) {
                int wStart = i;
                while (i < n && input[i].isLetter()) ++i;
                Token w;
                w.kind = TokenKind::Word;
                w.text = input.mid(wStart, i - wStart);
                w.lower = w.text.toLower();
                w.pos = wStart;
                w.len = i - wStart;
                out.push_back(w);
            }
            continue;
        }

        if (isWordChar(c)) {
            int start = i;
            while (i < n && isWordChar(input[i])) ++i;
            Token t;
            t.kind = TokenKind::Word;
            t.text = input.mid(start, i - start);
            t.lower = t.text.toLower();
            t.pos = start;
            t.len = i - start;
            out.push_back(t);
            continue;
        }

        // Any other character (comma, exclamation, etc.) is treated as a
        // soft separator. Emit a generic Punct token so the parser can break
        // contiguous expressions on it.
        Token t;
        t.kind = TokenKind::Punct;
        t.text = QString(c);
        t.lower = t.text;
        t.pos = i;
        t.len = 1;
        out.push_back(t);
        ++i;
    }

    Token endTok;
    endTok.kind = TokenKind::End;
    endTok.pos = n;
    out.push_back(endTok);
    return out;
}

} // namespace heap::chrono
