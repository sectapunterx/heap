#pragma once

#include "Models.h"

#include <QByteArray>
#include <QDir>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVector>

#include <functional>

// Files attached to tasks and notes.
//
// Every attachment is one file in <dataDir>/attachments, named by its content:
// the first 32 hex digits of its SHA-256 plus the original extension
// ("3fa9…c1.png"). That makes a stored file immutable — changing a byte would
// change its name — so the same screenshot attached to three tasks is one copy,
// detaching never has to decide whether anyone else still needs the bytes, and
// an import can tell a file it already holds from a different one by name.
//
// The id is also the whole of what a note or description writes to point at a
// file: `![shot.png](attachments/3fa9…c1.png)`. The markdown renderer resolves
// that against the attachments folder (see md::resolveImage), and the same text
// works in a folder of .md files exported next to an `attachments/` folder.
//
// Ids are validated against a fixed pattern before any path is built from one,
// so an id read from an imported file can never name "../state.json".
namespace heap::attachments {

// A single file larger than this is refused with a toast. Big enough for a
// screen recording or a log bundle, small enough that nobody attaches a disk
// image by mistake and a profile export stays loadable.
inline constexpr qint64 kMaxFileBytes = 100LL * 1024 * 1024;
// What a profile export may carry, in attachment bytes (before base64). Past
// this the export still writes every task and note, without the files, and
// says so.
inline constexpr qint64 kMaxExportBytes = 64LL * 1024 * 1024;

// The prefix a markdown reference carries: "attachments/<id>".
inline constexpr char kRefPrefix[] = "attachments/";

// True for "3fa9…c1" (32 lowercase hex digits) with an optional ".ext" of 1–12
// lowercase letters and digits. Nothing else is ever turned into a path.
bool isValidId(const QString& id);

// The id a file with these bytes and this original name is stored under.
QString idFor(const QByteArray& sha256, const QString& originalName);

// "png" for "Screen Shot.PNG"; empty when the name has no usable extension.
QString extensionOf(const QString& name);

// A best guess at the type, from the name and the first bytes.
QString mimeFor(const QString& name, const QByteArray& head = QByteArray());

// Images the notes preview can draw inline.
bool isDisplayableImage(const QString& mime);

// Whether opening the file waits for a confirmation: everything but the plain
// picture, document, media and archive types, since the shell may run it.
bool needsOpenConfirmation(const QString& name);

// `![name](attachments/<id>)` for an image, `[name](attachments/<id>)` for any
// other file. Brackets in the name are escaped so the reference stays one link.
QString markdownRef(const Attachment& a);

// Every attachment id mentioned in a piece of markdown, in order of first
// appearance. Deliberately loose — any "attachments/<valid id>" counts, inside
// a link or not — because this is also what decides which files the cleanup
// keeps: a false positive keeps a file, a false negative would delete one.
QStringList refsIn(const QString& markdown);

// The label a reference was written with, for every id in `markdown`
// ("shot.png" for `![shot.png](attachments/…)`). An id mentioned without a
// label maps to an empty string.
QHash<QString, QString> refLabelsIn(const QString& markdown);

// Replaces every "attachments/<from>" with "attachments/<to>".
QString remapRefs(const QString& markdown, const QHash<QString, QString>& idMap);

// Puts `prefix` ("../", "../../") in front of every link target that is
// "attachments/<id>", for a note written into a subfolder of an exported
// vault whose attachments/ folder sits at the root. Only link targets: a
// mention in plain text is not a path anyone resolves. Import reads the
// prefixed form back to "attachments/<id>" (importVaultRefs).
QString prefixRefLinks(const QString& markdown, const QString& prefix);

// The stored metadata as QML sees it ({id, name, size, mime}) and back. Entries
// whose id is not valid are dropped on the way in.
QVariantList toVariantList(const QVector<Attachment>& xs);
QVector<Attachment> fromVariantList(const QVariantList& xs);

// Applies remapRefs() to everything in a profile that can point at a file:
// task lists and descriptions, notes, doc pages, the docs catalog.
void remapProfile(Profile& p, const QHash<QString, QString>& idMap);

// "12 KB", "3.4 MB" — in Russian units when `ru`.
QString formatSize(qint64 bytes, bool ru);

// What adding a file did.
struct AddResult {
  enum Error {
    None,
    NotFound,    // no such file
    NotAFile,    // a folder, a device
    Link,        // a symbolic link, junction or shortcut: never followed
    TooLarge,    // over kMaxFileBytes
    Unreadable,  // could not be opened or read
    WriteFailed  // the attachments folder could not be written
  };

  Error error = None;
  Attachment attachment;
  bool deduplicated = false;  // the store already held these bytes

  bool ok() const {
    return error == None;
  }
};

// The attachments folder. Cheap to construct; creates the folder on the first
// write only, so reading a profile never leaves an empty folder behind.
class Store {
 public:
  explicit Store(QString dir);

  const QString& dir() const {
    return m_dir;
  }

  // Absolute path of a stored file, or empty for an id that is not valid.
  QString pathFor(const QString& id) const;
  bool contains(const QString& id) const;
  // Size on disk, -1 when the file is not there.
  qint64 sizeOf(const QString& id) const;

  // Copies a file in. `displayName` overrides the name kept as metadata (a
  // pasted image has no file name of its own).
  AddResult addFile(const QString& path, const QString& displayName = QString(), qint64 maxBytes = kMaxFileBytes) const;
  // Stores bytes that did not come from a file: a pasted image, an import.
  AddResult addBytes(const QByteArray& bytes, const QString& name, const QString& mime = QString(), qint64 maxBytes = kMaxFileBytes) const;

  // Ids of every file in the folder that has a valid name. Anything else in
  // there (a temp file, something the user dropped in by hand) is ignored.
  QStringList ids() const;

  // Deletes one stored file. Only the cleanup does this.
  bool remove(const QString& id) const;

 private:
  AddResult commitTemp(const QString& tempPath, const QByteArray& sha, const QString& name, const QString& mime, qint64 size) const;

  QString m_dir;
};

// Opens a file in its default application, or (`reveal`) shows it in the
// file manager. Replaceable so a test never launches anything.
using Shell = std::function<bool(const QString& path, bool reveal)>;
void setShellForTesting(Shell shell);
bool shell(const QString& path, bool reveal);

// Why an import refused a file, for a toast. `name` is the file name.
QString errorText(AddResult::Error error, const QString& name, bool ru);

// A folder of .md files: the relative links a note makes to files next to it.
//
// For each `[..](target)` / `![..](target)` whose target is a relative path to
// a file inside `vaultRoot` — resolved against the note's own folder first,
// then the vault root, the way Obsidian does — the file is stored (or, with a
// null store, only hashed) and the target rewritten to "attachments/<id>".
// Links to other notes, URLs, absolute paths, anything outside the root, links
// and oversized files are left alone. `stored` receives what was brought in.
struct VaultRefResult {
  QString text;
  QVector<Attachment> attachments;
  QStringList warnings;  // relative paths that were skipped, and why
};

VaultRefResult importVaultRefs(
    const QString& markdown, const QDir& vaultRoot, const QString& noteRelativePath, const Store* store, bool ru);

}  // namespace heap::attachments
