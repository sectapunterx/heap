#include "markdown/MdOutline.h"
#include "markdown/MdParser.h"
#include "markdown/MdSourceMap.h"
#include "notes/NoteLinks.h"

#include <QHash>
#include <QSet>
#include <QVariantMap>

namespace heap::notes {

namespace {

// One parse serves whichever question was asked. These are called from QML on
// every keystroke in the notes view, so the work is kept to a single pass over
// the document rather than a regular expression per line.
struct Parsed {
  md::MdSourceMap src;
  md::MdAst ast;

  explicit Parsed(const QString& markdown) : src(markdown), ast(md::parse(src)) {
  }
};

}  // namespace

QStringList collectHeadings(const QString& markdown) {
  const Parsed parsed(markdown);

  QStringList out;
  QSet<QString> seen;
  for(const md::MdHeading& heading : md::outline(parsed.src, parsed.ast)) {
    // An empty heading ("#### " on its own) is a target nobody can link to.
    if(heading.text.isEmpty() || seen.contains(heading.text)) {
      continue;
    }
    seen.insert(heading.text);
    out.append(heading.text);
  }
  return out;
}

QVariantList collectBacklinks(const QString& markdown) {
  const Parsed parsed(markdown);

  // Heading lookup is case-insensitive, matching headingOffset(): a link
  // written [[setup]] should resolve to "# Setup" rather than dangle, and the
  // two functions disagreeing about that was a real inconsistency.
  QSet<QString> headings;
  for(const md::MdHeading& heading : md::outline(parsed.src, parsed.ast)) {
    if(!heading.text.isEmpty()) {
      headings.insert(heading.text.toCaseFolded());
    }
  }

  // First-seen order is kept while collecting, then sorted for display.
  QStringList order;
  QHash<QString, QVariantList> refsByTarget;

  for(const md::MdWikiRef& ref : md::wikiRefs(parsed.src, parsed.ast)) {
    if(!refsByTarget.contains(ref.target)) {
      order.append(ref.target);
    }
    QVariantMap entry;
    entry.insert(QStringLiteral("line"), ref.line + 1);  // 1-based for the UI
    entry.insert(QStringLiteral("text"), ref.lineText);
    refsByTarget[ref.target].append(entry);
  }

  QVariantList out;
  order.sort(Qt::CaseInsensitive);
  for(const QString& target : order) {
    QVariantMap entry;
    entry.insert(QStringLiteral("target"), target);
    entry.insert(QStringLiteral("resolved"), headings.contains(target.toCaseFolded()));
    entry.insert(QStringLiteral("refs"), refsByTarget.value(target));
    out.append(entry);
  }
  return out;
}

int headingOffset(const QString& markdown, const QString& heading) {
  const QString needle = heading.trimmed();
  if(needle.isEmpty()) {
    return -1;
  }
  const Parsed parsed(markdown);
  for(const md::MdHeading& candidate : md::outline(parsed.src, parsed.ast)) {
    if(candidate.text.compare(needle, Qt::CaseInsensitive) == 0) {
      return candidate.utf16Offset;
    }
  }
  return -1;
}

}  // namespace heap::notes
