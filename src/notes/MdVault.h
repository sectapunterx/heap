#pragma once

#include "Models.h"

#include <QDateTime>
#include <QString>
#include <QStringList>
#include <QVector>

// Notes as a folder of .md files.
//
// Notes that only exist inside one application's state file are notes people
// keep somewhere else as well. The format everyone already has a folder of is
// markdown on disk, one file per note, directories for folders — which is
// exactly what Obsidian, Foam, Dendron and a shell prompt all agree on.
//
// This is the pure half: turning notes into files and files back into notes.
// Reading and writing the disk is AppController's, so the decisions worth
// arguing about — what a note is called when its title contains a slash, what
// happens when two files claim the same name, which files are not notes at all
// — can be tested without a filesystem.
namespace heap::notes {

// One file, as it will be written.
struct VaultFile {
  // Relative to the vault root, with '/' separators: "meetings/2026/standup.md".
  QString path;
  QString contents;
};

// What came back from a folder.
struct VaultImport {
  QVector<Note> notes;
  // Files that were not notes, or could not be read as one.
  int skipped = 0;
  QStringList warnings;
};

namespace detail {

// A title as a filename. Windows forbids \ / : * ? " < > | and Obsidian avoids
// them too, so a note called "Q3: plan" becomes "Q3 plan.md" rather than a file
// that cannot be created on half the machines it is synced to.
inline QString sanitiseFileName(const QString& title) {
  static const QString kForbidden = QStringLiteral("\\/:*?\"<>|");
  QString out;
  out.reserve(title.size());
  for(const QChar c : title) {
    if(kForbidden.contains(c) || c < QChar(0x20)) {
      out.append(QLatin1Char(' '));
    } else {
      out.append(c);
    }
  }
  out = out.simplified();
  // A trailing dot or space is legal in the string and not on Windows.
  while(out.endsWith(QLatin1Char('.')) || out.endsWith(QLatin1Char(' '))) {
    out.chop(1);
  }
  if(out.isEmpty()) {
    out = QStringLiteral("untitled");
  }
  // Long enough for any real title, short enough to survive a deep folder on a
  // filesystem with a path limit.
  return out.left(120);
}

inline QString sanitiseFolder(const QString& folder) {
  QStringList parts;
  for(const QString& piece : folder.split(QLatin1Char('/'), Qt::SkipEmptyParts)) {
    const QString clean = sanitiseFileName(piece);
    // ".." would write outside the vault; a folder is a name, not a path
    // expression.
    if(clean == QLatin1String("..") || clean == QLatin1String(".")) {
      continue;
    }
    parts << clean;
  }
  return parts.join(QLatin1Char('/'));
}

inline QString escapeYaml(const QString& in) {
  QString out = in;
  out.replace(QLatin1Char('\\'), QLatin1String("\\\\"));
  out.replace(QLatin1Char('"'), QLatin1String("\\\""));
  out.replace(QLatin1Char('\n'), QLatin1String(" "));
  return out;
}

}  // namespace detail

// Directories a vault contains that are not notes. Obsidian keeps its settings
// in `.obsidian` and its deletions in `.trash`; importing either would fill the
// list with configuration and things the user already threw away.
inline bool isIgnoredPath(const QString& relativePath) {
  for(const QString& part : relativePath.split(QLatin1Char('/'), Qt::SkipEmptyParts)) {
    if(part.startsWith(QLatin1Char('.'))) {
      return true;
    }
  }
  return false;
}

// The frontmatter heap writes. Only what the app actually holds: anything
// invented here would be lost on the next round trip and read as heap
// corrupting the file.
inline QString frontmatterFor(const Note& n) {
  QStringList lines;
  lines << QStringLiteral("---");
  lines << QStringLiteral("title: \"%1\"").arg(detail::escapeYaml(n.title));
  if(n.pinned) {
    lines << QStringLiteral("pinned: true");
  }
  if(n.created.isValid()) {
    lines << QStringLiteral("created: %1").arg(n.created.toString(Qt::ISODate));
  }
  if(n.updated.isValid()) {
    lines << QStringLiteral("updated: %1").arg(n.updated.toString(Qt::ISODate));
  }
  lines << QStringLiteral("---");
  lines << QString();
  return lines.join(QLatin1Char('\n'));
}

// Every note as a file, with unique paths.
//
// Two notes may legitimately share a title — "Meeting" in two folders, or twice
// in one. Within a folder the second gets a numeric suffix, because a vault is
// a filesystem and the alternative is one note silently overwriting another.
inline QVector<VaultFile> exportVault(const QVector<Note>& notes) {
  QVector<VaultFile> out;
  QSet<QString> used;
  for(const Note& n : notes) {
    const QString folder = detail::sanitiseFolder(n.folder);
    const QString base = detail::sanitiseFileName(n.title.isEmpty() ? n.id : n.title);
    QString candidate = base;
    int suffix = 2;
    const auto full = [&folder](const QString& name) {
      return folder.isEmpty() ? name + QStringLiteral(".md") : folder + QLatin1Char('/') + name + QStringLiteral(".md");
    };
    while(used.contains(full(candidate).toLower())) {
      candidate = QStringLiteral("%1 %2").arg(base).arg(suffix++);
    }
    used.insert(full(candidate).toLower());
    out.append({full(candidate), frontmatterFor(n) + n.body});
  }
  return out;
}

// Reads one file back.
//
// `relativePath` gives the folder and the fallback title; frontmatter, when
// present, wins over both, because the file may have been renamed on disk while
// the note it holds kept its name.
inline Note importFile(const QString& relativePath, const QString& contents) {
  Note n;

  const int slash = relativePath.lastIndexOf(QLatin1Char('/'));
  n.folder = slash > 0 ? relativePath.left(slash) : QString();
  QString stem = slash >= 0 ? relativePath.mid(slash + 1) : relativePath;
  if(stem.endsWith(QStringLiteral(".md"), Qt::CaseInsensitive)) {
    stem.chop(3);
  } else if(stem.endsWith(QStringLiteral(".markdown"), Qt::CaseInsensitive)) {
    stem.chop(9);
  }
  n.title = stem;
  n.body = contents;

  // Frontmatter is a --- fence at the very start and the next --- on its own
  // line. A --- further down is a horizontal rule, not a fence.
  QString body = contents;
  body.replace(QLatin1String("\r\n"), QLatin1String("\n"));
  if(body.startsWith(QStringLiteral("---\n"))) {
    const int end = body.indexOf(QStringLiteral("\n---"), 3);
    if(end > 0) {
      const QString block = body.mid(4, end - 4);
      for(const QString& raw : block.split(QLatin1Char('\n'))) {
        const int colon = raw.indexOf(QLatin1Char(':'));
        if(colon <= 0) {
          continue;
        }
        const QString key = raw.left(colon).trimmed().toLower();
        QString value = raw.mid(colon + 1).trimmed();
        if(value.startsWith(QLatin1Char('"')) && value.endsWith(QLatin1Char('"')) && value.size() >= 2) {
          value = value.mid(1, value.size() - 2);
          value.replace(QLatin1String("\\\""), QLatin1String("\""));
          value.replace(QLatin1String("\\\\"), QLatin1String("\\"));
        }
        if(key == QLatin1String("title") && !value.isEmpty()) {
          n.title = value;
        } else if(key == QLatin1String("pinned")) {
          n.pinned = (value.compare(QLatin1String("true"), Qt::CaseInsensitive) == 0);
        } else if(key == QLatin1String("created")) {
          n.created = QDateTime::fromString(value, Qt::ISODate);
        } else if(key == QLatin1String("updated")) {
          n.updated = QDateTime::fromString(value, Qt::ISODate);
        }
      }
      // Past the closing fence and the newline after it.
      int after = end + 4;
      while(after < body.size() && body.at(after) != QLatin1Char('\n')) {
        ++after;
      }
      body = body.mid(qMin(after + 1, body.size()));
      // One blank line after the fence is the writer's, not the note's.
      if(body.startsWith(QLatin1Char('\n'))) {
        body = body.mid(1);
      }
      n.body = body;
    }
  }

  // A file with no frontmatter dates still has to sort somewhere.
  if(!n.created.isValid()) {
    n.created = QDateTime::currentDateTime();
  }
  if(!n.updated.isValid()) {
    n.updated = n.created;
  }
  return n;
}

}  // namespace heap::notes
