#pragma once

#include <QString>
#include <QStringList>
#include <QStringView>

namespace heap::text {

enum class TaskKind { None, Focus, Sync, Ticket, Contact };

struct TaskMeta {
    QString     title;     // raw input with "// …" and "@handles" stripped
    QString     desc;      // text after "// "
    QStringList handles;   // raw identifiers (without leading '@')
};

// Classify free-form input against three keyword lists. Order of precedence:
//   ticket > focus > sync > none. "ticket" wins because it is an explicit
//   "todo only, never put on the calendar" hint.
TaskKind classifyKind(QStringView text);

// Strip "// comment" tail (→ desc) and "@handle" tokens (→ handles) from a
// title. "//" must be exact two-slash sequence (URLs like "https://" are NOT
// stripped because the scheme is followed by non-slash chars on the *left*
// side, but pure "https://example" still trips this — caller is responsible
// for picking inputs where "//" denotes a comment).
TaskMeta extractMeta(QStringView raw);

// Generate a human-readable slug for a person's name, of the form
// "<first-initial>.<last-name>" with Cyrillic transliterated to Latin.
//   "Антон Иванов"  → "a.ivanov"
//   "Andrey S."     → "a.s"
//   "Hiroshi"       → "hiroshi"   (single token → kept as-is, lowercased)
// All output is ASCII-only, lowercase, [a-z0-9._-]. Empty input → "".
QString slugifyPersonName(QStringView name);

} // namespace heap::text
