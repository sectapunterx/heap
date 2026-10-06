#pragma once

#include "Models.h"

#include <QByteArray>
#include <QCryptographicHash>
#include <QDateTime>
#include <QHash>
#include <QSet>
#include <QString>
#include <QStringDecoder>
#include <QStringList>
#include <QVector>

#include <functional>
#include <optional>

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
// happens when two files claim the same name, which files are not notes at all,
// which side wins when both changed — can be tested without a filesystem.
namespace heap::notes {

// One file, as it will be written.
struct VaultFile {
  // Relative to the vault root, with '/' separators: "meetings/2026/standup.md".
  QString path;
  QString contents;
  // The note it came from, so the caller can remember where the note went.
  QString noteId;
};

// What came back from a folder.
struct VaultImport {
  QVector<Note> notes;
  // Files that were not notes, or could not be read as one.
  int skipped = 0;
  QStringList warnings;
};

// Bigger than any note a person writes by hand. A 20 MB "note" is a log or a
// dump, and every keystroke in it would re-parse the whole thing.
constexpr qsizetype kMaxVaultFileBytes = 4 * 1024 * 1024;

namespace detail {

// Device names Windows reserves in every directory, with or without an
// extension: a note called "CON" cannot be written as CON.md.
inline bool isReservedWindowsName(const QString& name) {
  static const QSet<QString> kReserved = {
      QStringLiteral("con"),  QStringLiteral("prn"),  QStringLiteral("aux"),  QStringLiteral("nul"),  QStringLiteral("com1"),
      QStringLiteral("com2"), QStringLiteral("com3"), QStringLiteral("com4"), QStringLiteral("com5"), QStringLiteral("com6"),
      QStringLiteral("com7"), QStringLiteral("com8"), QStringLiteral("com9"), QStringLiteral("lpt1"), QStringLiteral("lpt2"),
      QStringLiteral("lpt3"), QStringLiteral("lpt4"), QStringLiteral("lpt5"), QStringLiteral("lpt6"), QStringLiteral("lpt7"),
      QStringLiteral("lpt8"), QStringLiteral("lpt9"),
  };
  const qsizetype dot = name.indexOf(QLatin1Char('.'));
  const QString stem = (dot >= 0 ? name.left(dot) : name).trimmed().toLower();
  return kReserved.contains(stem);
}

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
  out = out.left(120);
  if(isReservedWindowsName(out)) {
    // After the device name, before any extension: NUL.txt is reserved too.
    const qsizetype dot = out.indexOf(QLatin1Char('.'));
    out.insert(dot >= 0 ? dot : out.size(), QLatin1Char('_'));
  }
  return out;
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

inline QString unquoteYaml(QString value) {
  if(value.size() >= 2 && value.startsWith(QLatin1Char('"')) && value.endsWith(QLatin1Char('"'))) {
    value = value.mid(1, value.size() - 2);
    value.replace(QLatin1String("\\\""), QLatin1String("\""));
    value.replace(QLatin1String("\\\\"), QLatin1String("\\"));
  } else if(value.size() >= 2 && value.startsWith(QLatin1Char('\'')) && value.endsWith(QLatin1Char('\''))) {
    value = value.mid(1, value.size() - 2);
    value.replace(QLatin1String("''"), QLatin1String("'"));
  }
  return value;
}

// The path a note would be exported to, ignoring collisions. Used to find the
// note a file belongs to when the note predates vault tracking.
inline QString naturalPath(const Note& n) {
  const QString folder = sanitiseFolder(n.folder);
  const QString name = sanitiseFileName(n.title.isEmpty() ? n.id : n.title) + QStringLiteral(".md");
  return folder.isEmpty() ? name : folder + QLatin1Char('/') + name;
}

}  // namespace detail

// What a re-import compares: the title and the body, the two things a person
// edits. Hashed so a note can remember the version it last agreed with a file
// on without keeping a second copy of the body.
inline QString contentHash(const QString& title, const QString& body) {
  QCryptographicHash h(QCryptographicHash::Sha1);
  h.addData(title.toUtf8());
  h.addData(QByteArrayView("\0", 1));
  h.addData(body.toUtf8());
  return QString::fromLatin1(h.result().toHex().left(20));
}

inline QString contentHash(const Note& n) {
  return contentHash(n.title, n.body);
}

namespace detail {

// Windows-1251, 0x80..0xFF. Spelled out rather than asked of the platform:
// Qt only knows the code page through ICU, which the Windows build has not
// got, and the answer must not depend on which machine imports the folder.
inline QString decodeCp1251(const QByteArray& data) {
  static const char16_t kHigh[128] = {
      0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021, 0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F,
      0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0xFFFD, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
      0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7, 0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
      0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7, 0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
  };
  QString out;
  out.reserve(data.size());
  for(const char c : data) {
    const auto b = static_cast<unsigned char>(c);
    if(b < 0x80) {
      out += QChar(b);
    } else if(b < 0xC0) {
      out += QChar(kHigh[b - 0x80]);
    } else {
      // А..я are contiguous: 0xC0 is U+0410.
      out += QChar(static_cast<char16_t>(0x0410 + (b - 0xC0)));
    }
  }
  return out;
}

// Whether bytes that are not UTF-8 read as Russian in Windows-1251 rather than
// as accented Latin. In 1251 every byte from 0xC0 up is a Cyrillic letter, and
// Cyrillic text is made of little else — words are runs of them. A Latin-1 or
// Windows-1252 file uses the same bytes for the odd é or ß among plain ASCII
// letters. So: what share of the letters are high bytes.
inline bool looksLikeCp1251(const QByteArray& data) {
  int ascii = 0;
  int cyrillic = 0;
  for(const char c : data) {
    const auto b = static_cast<unsigned char>(c);
    if((b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z')) {
      ++ascii;
    } else if(b >= 0xC0 || b == 0xA8 || b == 0xB8) {  // А..я, Ё, ё
      ++cyrillic;
    }
  }
  // Even an English-heavy Russian note ("сделать PR в heap") passes; even a
  // French one ("Réunion à l'école") does not come close.
  return cyrillic > 0 && cyrillic * 10 >= (ascii + cyrillic) * 3;
}

}  // namespace detail

// Bytes from disk as text. UTF-8 (with or without a BOM) is what every
// markdown tool writes, and a UTF-16 or UTF-32 file with its BOM — Notepad's
// "Unicode" — says what it is. A file that is not valid UTF-8 is an old
// Windows file: Windows-1251 when it reads as Russian, Latin-1 otherwise —
// either way not turned into replacement characters. A NUL byte in a file
// without a wide BOM means it is not text at all: `binary` is set and nothing
// returned.
inline QString decodeVaultBytes(const QByteArray& bytes, bool* binary = nullptr) {
  if(binary != nullptr) {
    *binary = false;
  }
  // Before the NUL check: half the bytes of a UTF-16 file are NULs.
  const std::optional<QStringConverter::Encoding> bom = QStringConverter::encodingForData(bytes);
  if(bom.has_value() && *bom != QStringConverter::Utf8) {
    QStringDecoder wide(*bom);
    QString text = wide.decode(bytes);
    if(!wide.hasError() && !text.contains(QChar(0))) {
      return text;
    }
  }
  QByteArray data = bytes;
  if(data.startsWith("\xEF\xBB\xBF")) {
    data.remove(0, 3);
  }
  if(data.contains('\0')) {
    if(binary != nullptr) {
      *binary = true;
    }
    return {};
  }
  QStringDecoder utf8(QStringDecoder::Utf8, QStringDecoder::Flag::Stateless);
  QString text = utf8.decode(data);
  if(!utf8.hasError()) {
    return text;
  }
  if(detail::looksLikeCp1251(data)) {
    return detail::decodeCp1251(data);
  }
  QStringDecoder latin1(QStringDecoder::Latin1);
  return latin1.decode(data);
}

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

// The frontmatter heap writes. What the app holds, the note's id — which is
// what lets a re-import find the note again when two share a title — and the
// keys heap has no field for, written back as they came.
//
// `writtenFolder` is where the file actually goes: when sanitising changed the
// folder ("Q3: plan" → "Q3 plan"), the real one is recorded so the round trip
// does not rename it.
inline QString frontmatterFor(const Note& n, const QString& writtenFolder = QString()) {
  QStringList lines;
  lines << QStringLiteral("---");
  lines << QStringLiteral("title: \"%1\"").arg(detail::escapeYaml(n.title));
  if(!n.id.isEmpty()) {
    lines << QStringLiteral("id: %1").arg(n.id);
  }
  if(!n.folder.isEmpty() && n.folder != writtenFolder) {
    lines << QStringLiteral("folder: \"%1\"").arg(detail::escapeYaml(n.folder));
  }
  if(n.pinned) {
    lines << QStringLiteral("pinned: true");
  }
  if(n.created.isValid()) {
    lines << QStringLiteral("created: %1").arg(n.created.toString(Qt::ISODate));
  }
  if(n.updated.isValid()) {
    lines << QStringLiteral("updated: %1").arg(n.updated.toString(Qt::ISODate));
  }
  if(!n.frontmatter.isEmpty()) {
    lines << n.frontmatter;
  }
  lines << QStringLiteral("---");
  // One blank line between the fence and the body. The reader takes exactly
  // one off, so a body that starts with a blank line of its own keeps it.
  lines << QString();
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
    out.append({full(candidate), frontmatterFor(n, folder) + n.body, n.id});
  }
  return out;
}

// Reads one file back.
//
// `relativePath` gives the folder and the fallback title; frontmatter, when
// present, wins over both, because the file may have been renamed on disk while
// the note it holds kept its name. `id` is whatever the frontmatter said — the
// caller decides whether that id still means anything.
inline Note importFile(const QString& relativePath, const QString& contents) {
  Note n;

  const int slash = static_cast<int>(relativePath.lastIndexOf(QLatin1Char('/')));
  n.folder = slash > 0 ? relativePath.left(slash) : QString();
  QString stem = slash >= 0 ? relativePath.mid(slash + 1) : relativePath;
  if(stem.endsWith(QStringLiteral(".md"), Qt::CaseInsensitive)) {
    stem.chop(3);
  } else if(stem.endsWith(QStringLiteral(".markdown"), Qt::CaseInsensitive)) {
    stem.chop(9);
  }
  n.title = stem;

  // Line ends as the editor has them. A body kept with "\r\n" read back as
  // something else the moment it was edited, and the next import of the same
  // file then took the note for one changed in heap and kept it over the file.
  QString body = contents;
  body.replace(QLatin1String("\r\n"), QLatin1String("\n"));
  n.body = body;

  // Frontmatter is a --- fence at the very start and the next --- on its own
  // line. A --- further down is a horizontal rule, not a fence.
  if(body.startsWith(QStringLiteral("---\n"))) {
    const int end = static_cast<int>(body.indexOf(QStringLiteral("\n---"), 3));
    if(end > 0) {
      const QString block = body.mid(4, end - 4);
      QStringList extra;
      bool inExtra = false;
      QString folderKey;
      bool hasFolderKey = false;
      for(const QString& raw : block.split(QLatin1Char('\n'))) {
        // A continuation of the key above — a YAML list item or an indented
        // value. It belongs to that key, known or not.
        if(!raw.isEmpty() && (raw.at(0).isSpace() || raw.startsWith(QLatin1Char('-')))) {
          if(inExtra) {
            extra << raw;
          }
          continue;
        }
        const int colon = static_cast<int>(raw.indexOf(QLatin1Char(':')));
        if(colon <= 0) {
          inExtra = false;
          if(!raw.trimmed().isEmpty()) {
            extra << raw;
          }
          continue;
        }
        const QString key = raw.left(colon).trimmed().toLower();
        const QString value = detail::unquoteYaml(raw.mid(colon + 1).trimmed());
        inExtra = false;
        if(key == QLatin1String("title")) {
          if(!value.isEmpty()) {
            n.title = value;
          }
        } else if(key == QLatin1String("id")) {
          n.id = value;
        } else if(key == QLatin1String("folder")) {
          folderKey = value;
          hasFolderKey = true;
        } else if(key == QLatin1String("pinned")) {
          n.pinned = (value.compare(QLatin1String("true"), Qt::CaseInsensitive) == 0);
        } else if(key == QLatin1String("created")) {
          n.created = QDateTime::fromString(value, Qt::ISODate);
        } else if(key == QLatin1String("updated")) {
          n.updated = QDateTime::fromString(value, Qt::ISODate);
        } else {
          // tags, aliases, anything another tool keeps: not heap's to drop.
          extra << raw;
          inExtra = true;
        }
      }
      n.frontmatter = extra.join(QLatin1Char('\n'));
      // The folder heap recorded, for a name sanitising had to change — but
      // only while the file is still where heap wrote it. A file moved to
      // another directory on disk was re-filed on purpose.
      if(hasFolderKey && detail::sanitiseFolder(folderKey) == n.folder) {
        n.folder = folderKey;
      }
      // Past the closing fence and the newline after it.
      int after = end + 4;
      while(after < body.size() && body.at(after) != QLatin1Char('\n')) {
        ++after;
      }
      body = body.mid(qMin(after + 1, static_cast<int>(body.size())));
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

// ── Importing into notes that already exist ─────────────────────────────
//
// A vault is edited in two places, so a second import is the normal case and
// the dangerous one: the file and the note may both have changed since they
// last agreed. Each note remembers the hash of the file version it last saw
// (Note::vaultHash), which is enough to tell the four cases apart without
// keeping a copy of the old text.

enum class VaultAction {
  Create,     // a file with no note behind it
  Update,     // the file changed, the note did not: the file wins
  Unchanged,  // both say the same thing
  KeepLocal,  // the note changed in heap, the file did not: the note wins
  Conflict,   // both changed: the note stays, the file arrives as a copy
};

struct VaultPlanItem {
  QString path;
  VaultAction action = VaultAction::Create;
  // The note as it should be after the import. For Conflict, the existing
  // note with only its bookkeeping refreshed; `copy` is the file's version.
  Note note;
  Note copy;
};

// One file as read from disk, already decoded.
struct VaultSource {
  QString path;
  QString text;
};

// Decide, file by file, what an import does. Pure: nothing is changed until
// the caller applies the plan, so the same function drives a preview.
//
// A file finds its note by the id heap wrote into its frontmatter, then by the
// path it was last imported from or exported to, then — for notes that predate
// this bookkeeping — by the path an export would give the note. Never by a
// lowercased title: "Meeting", "Meeting" and "meeting" are three notes.
inline QVector<VaultPlanItem> planImport(const QVector<Note>& existing,
                                         const QVector<VaultSource>& files,
                                         const std::function<QString()>& newId,
                                         const QString& conflictSuffix) {
  QHash<QString, int> byId;
  QHash<QString, int> byVaultPath;
  QHash<QString, int> byNaturalPath;
  QSet<QString> naturalTaken;
  for(int i = 0; i < existing.size(); ++i) {
    const Note& n = existing.at(i);
    byId.insert(n.id, i);
    if(!n.vaultPath.isEmpty()) {
      byVaultPath.insert(n.vaultPath.toLower(), i);
    } else {
      const QString natural = detail::naturalPath(n).toLower();
      // Two old notes that would export to the same name cannot be told apart
      // by it; neither claims the file.
      if(naturalTaken.contains(natural)) {
        byNaturalPath.remove(natural);
      } else {
        byNaturalPath.insert(natural, i);
        naturalTaken.insert(natural);
      }
    }
  }

  QSet<int> claimed;
  QSet<QString> usedIds;
  for(const Note& n : existing) {
    usedIds.insert(n.id);
  }
  const auto freshId = [&]() {
    QString id;
    do {
      id = newId();
    } while(usedIds.contains(id));
    usedIds.insert(id);
    return id;
  };

  QVector<VaultPlanItem> plan;
  plan.reserve(files.size());
  for(const VaultSource& src : files) {
    Note fromFile = importFile(src.path, src.text);
    const QString fileHash = contentHash(fromFile);

    int match = -1;
    if(!fromFile.id.isEmpty()) {
      const auto it = byId.constFind(fromFile.id);
      if(it != byId.constEnd() && !claimed.contains(it.value())) {
        match = it.value();
      }
    }
    if(match < 0) {
      const auto it = byVaultPath.constFind(src.path.toLower());
      if(it != byVaultPath.constEnd() && !claimed.contains(it.value())) {
        match = it.value();
      }
    }
    if(match < 0) {
      const auto it = byNaturalPath.constFind(src.path.toLower());
      if(it != byNaturalPath.constEnd() && !claimed.contains(it.value())) {
        match = it.value();
      }
    }

    VaultPlanItem item;
    item.path = src.path;
    if(match < 0) {
      item.action = VaultAction::Create;
      // Keep the id the file carries when it is free: that is the same note
      // coming home, and links and history keep pointing at it.
      if(fromFile.id.isEmpty() || usedIds.contains(fromFile.id)) {
        fromFile.id = freshId();
      } else {
        usedIds.insert(fromFile.id);
      }
      fromFile.vaultPath = src.path;
      fromFile.vaultHash = fileHash;
      item.note = fromFile;
      plan.append(item);
      continue;
    }

    claimed.insert(match);
    const Note& local = existing.at(match);
    const QString localHash = contentHash(local);
    Note next = local;
    next.vaultPath = src.path;
    // The file version heap has now seen, whatever it decides below: the
    // next import of the same file is then not a conflict all over again.
    next.vaultHash = fileHash;

    if(localHash == fileHash) {
      item.action = VaultAction::Unchanged;
      if(next.frontmatter.isEmpty()) {
        next.frontmatter = fromFile.frontmatter;
      }
    } else if(!local.vaultHash.isEmpty() && local.vaultHash == localHash) {
      // Untouched in heap since the last import: the file is the newer one.
      item.action = VaultAction::Update;
      next.title = fromFile.title;
      next.folder = fromFile.folder;
      next.body = fromFile.body;
      next.pinned = fromFile.pinned;
      next.frontmatter = fromFile.frontmatter;
      next.updated = fromFile.updated.isValid() ? fromFile.updated : QDateTime::currentDateTime();
    } else if(!local.vaultHash.isEmpty() && local.vaultHash == fileHash) {
      item.action = VaultAction::KeepLocal;
    } else {
      // Both changed, or there is no record of when they last agreed. Either
      // way somebody's words would be lost by picking one, so both stay.
      item.action = VaultAction::Conflict;
      Note copy = fromFile;
      copy.id = freshId();
      copy.title = fromFile.title + conflictSuffix;
      copy.vaultPath.clear();
      copy.vaultHash.clear();
      item.copy = copy;
    }
    item.note = next;
    plan.append(item);
  }
  return plan;
}

}  // namespace heap::notes
