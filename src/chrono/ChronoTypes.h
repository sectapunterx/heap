#pragma once

#include <QDateTime>
#include <QString>

namespace heap::chrono {

struct ParseResult {
    bool ok = false;
    QDateTime start;
    QDateTime end;
    bool hasTime = false;
    QString recurrence;
    QString consumed;
    int startOffset = -1;
    int endOffset = -1;
};

enum class TokenKind {
    Word,
    Number,
    Punct,
    Colon,
    Dot,
    Dash,
    Slash,
    End
};

struct Token {
    TokenKind kind = TokenKind::End;
    QString text;       // original substring (case-preserved)
    QString lower;      // lower-cased lexeme for dictionary lookup
    int value = 0;      // parsed integer when kind == Number
    int pos = -1;       // start offset in original input
    int len = 0;        // length in original input
};

} // namespace heap::chrono
