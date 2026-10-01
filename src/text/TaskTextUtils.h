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
    QString ticketKey;     // "LTE-2398" when the text names a tracker ticket
    QString priority;      // "P0".."P3" from "p1" / "!!" / "срочно"; "" if none
    QStringList labels;    // "#backend" → "backend", removed from the title
    QString head;          // the input before the "// …" tail, nothing else removed
};

// Classify free-form input against three keyword lists. Order of precedence:
//   ticket > focus > sync > none. "ticket" wins because it is an explicit
//   "todo only, never put on the calendar" hint.
TaskKind classifyKind(QStringView text);

// For text classifyKind calls a Sync, the calendar type the meeting books:
// "standup" (дейли, планёрка), "oneone" (1:1), "sync" (синк with the team) or
// "none" for a one-off call or meeting (созвон, встреча, демо, интервью).
QString meetingType(QStringView text);

// Strip "// comment" tail (→ desc) and "@handle" tokens (→ handles) from a
// title. A "//" inside a URL ("https://example.com/a") is part of the URL,
// never the start of a comment. With `keepTicketKey` a tracker key is still
// reported in ticketKey but stays in the title: the caller cannot make it the
// task's id (another task holds it), so it is the only trace of the ticket.
TaskMeta extractMeta(QStringView raw, bool keepTicketKey = false);

// Generate a human-readable slug for a person's name, of the form
// "<first-initial>.<last-name>" with Cyrillic transliterated to Latin.
//   "Антон Иванов"  → "a.ivanov"
//   "Andrey S."     → "a.s"
//   "Hiroshi"       → "hiroshi"   (single token → kept as-is, lowercased)
// All output is ASCII-only, lowercase, [a-z0-9._-]. Empty input → "".
QString slugifyPersonName(QStringView name);

} // namespace heap::text
