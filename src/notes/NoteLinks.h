#pragma once

#include <QString>
#include <QStringList>
#include <QVariantList>

namespace heap::notes {

// Pure note-graph helpers over a single markdown blob (heap. stores all of a
// profile's notes as one string). No QObject, no I/O — unit-tested directly.

// Every markdown heading's text (the part after the leading #'s), in document
// order, de-duplicated. Used to populate [[wiki-link]] autocomplete.
QStringList collectHeadings(const QString& markdown);

// Backlinks: group every [[target]] occurrence by its target. Returns
// [ { "target": <text>, "refs": [ { "line": <1-based>, "text": <trimmed line> }, … ] }, … ]
// sorted by target. `resolved` is true when a heading with that text exists.
QVariantList collectBacklinks(const QString& markdown);

// 0-based character offset of the first heading whose text equals `heading`
// (case-insensitive, trimmed), or -1. Lets the UI jump to a link target.
int headingOffset(const QString& markdown, const QString& heading);

}  // namespace heap::notes
