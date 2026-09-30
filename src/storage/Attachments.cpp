#include "storage/Attachments.h"

#include <QCryptographicHash>
#include <QDesktopServices>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QMimeDatabase>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QThread>
#include <QUrl>
#include <QUuid>
#include <QVariantMap>

#include <algorithm>

namespace heap::attachments {

namespace {

const QRegularExpression& idPattern() {
  static const QRegularExpression re(QStringLiteral("^[0-9a-f]{32}(?:\\.[a-z0-9]{1,12})?$"));
  return re;
}

// "attachments/<id>" anywhere. The id's own pattern ends at the first
// character that cannot be part of it, so ")" and "#" stop it.
const QRegularExpression& refPattern() {
  static const QRegularExpression re(QStringLiteral("attachments/([0-9a-f]{32}(?:\\.[a-z0-9]{1,12})?)(?![a-z0-9.])"));
  return re;
}

// `[label](target "title")` and `![label](<target>)`. Good enough for the
// links a person writes; md4c is not needed to find a path.
const QRegularExpression& linkPattern() {
  static const QRegularExpression re(
      QStringLiteral("(!?)\\[((?:\\\\.|[^\\]\\\\\\n])*)\\]\\(\\s*(<[^>\\n]+>|[^)\\s]+)((?:\\s+\"[^\"\\n]*\")?\\s*)\\)"));
  return re;
}

constexpr qint64 kChunk = 1 << 20;

// A file that has just been written is often held for a moment by a virus
// scanner or an indexer, and a rename fails while it is. Retry for a couple of
// seconds, then fall back to a copy — the temp file is ours either way.
bool moveIntoPlace(const QString& from, const QString& to) {
  for(int attempt = 0; attempt < 10; ++attempt) {
    if(QFile::rename(from, to)) {
      return true;
    }
    if(QFileInfo::exists(to)) {
      break;
    }
    QThread::msleep(50);
  }
  if(!QFileInfo::exists(to) && QFile::copy(from, to)) {
    QFile::remove(from);
    return true;
  }
  return false;
}

bool isLinkLike(const QFileInfo& fi) {
  return fi.isSymLink() || fi.isJunction() || fi.isShortcut() || fi.isAlias();
}

}  // namespace

bool isValidId(const QString& id) {
  return idPattern().match(id).hasMatch();
}

QString extensionOf(const QString& name) {
  const QString suffix = QFileInfo(name).suffix().toLower();
  static const QRegularExpression ok(QStringLiteral("^[a-z0-9]{1,12}$"));
  return ok.match(suffix).hasMatch() ? suffix : QString();
}

QString idFor(const QByteArray& sha256, const QString& originalName) {
  const QString hex = QString::fromLatin1(sha256.toHex()).left(32);
  const QString ext = extensionOf(originalName);
  return ext.isEmpty() ? hex : hex + QLatin1Char('.') + ext;
}

QString mimeFor(const QString& name, const QByteArray& head) {
  static const QMimeDatabase db;
  const QMimeType type =
      head.isEmpty() ? db.mimeTypeForFile(name, QMimeDatabase::MatchExtension) : db.mimeTypeForFileNameAndData(name, head);
  return type.isValid() ? type.name() : QStringLiteral("application/octet-stream");
}

bool isDisplayableImage(const QString& mime) {
  static const QSet<QString> kShown = {QStringLiteral("image/png"),
                                       QStringLiteral("image/jpeg"),
                                       QStringLiteral("image/gif"),
                                       QStringLiteral("image/webp"),
                                       QStringLiteral("image/bmp"),
                                       QStringLiteral("image/svg+xml")};
  return kShown.contains(mime);
}

bool needsOpenConfirmation(const QString& name) {
  // What Windows, macOS and the Linux desktops run, or hand to an interpreter,
  // when a file of this type is opened.
  static const QSet<QString> kRuns = {QStringLiteral("exe"),         QStringLiteral("com"),        QStringLiteral("bat"),
                                      QStringLiteral("cmd"),         QStringLiteral("msi"),        QStringLiteral("msp"),
                                      QStringLiteral("scr"),         QStringLiteral("pif"),        QStringLiteral("cpl"),
                                      QStringLiteral("lnk"),         QStringLiteral("url"),        QStringLiteral("ps1"),
                                      QStringLiteral("psm1"),        QStringLiteral("vbs"),        QStringLiteral("vbe"),
                                      QStringLiteral("js"),          QStringLiteral("jse"),        QStringLiteral("wsf"),
                                      QStringLiteral("wsh"),         QStringLiteral("hta"),        QStringLiteral("reg"),
                                      QStringLiteral("jar"),         QStringLiteral("appx"),       QStringLiteral("msix"),
                                      QStringLiteral("app"),         QStringLiteral("command"),    QStringLiteral("sh"),
                                      QStringLiteral("bash"),        QStringLiteral("zsh"),        QStringLiteral("run"),
                                      QStringLiteral("desktop"),     QStringLiteral("appimage"),   QStringLiteral("py"),
                                      QStringLiteral("pyw"),         QStringLiteral("pl"),         QStringLiteral("rb"),
                                      QStringLiteral("scpt"),        QStringLiteral("workflow"),   QStringLiteral("dll"),
                                      QStringLiteral("sys"),         QStringLiteral("library-ms"), QStringLiteral("settingcontent-ms"),
                                      QStringLiteral("application"), QStringLiteral("gadget")};
  const QString suffix = QFileInfo(name).suffix().toLower();
  // No extension at all: on Unix that is how a program looks.
  return suffix.isEmpty() || kRuns.contains(suffix);
}

QString markdownRef(const Attachment& a) {
  QString label = a.name.isEmpty() ? a.id : a.name;
  label.replace(QLatin1Char('\\'), QStringLiteral("\\\\"));
  label.replace(QLatin1Char('['), QStringLiteral("\\["));
  label.replace(QLatin1Char(']'), QStringLiteral("\\]"));
  label.replace(QLatin1Char('\n'), QLatin1Char(' '));
  const QString target = QString::fromLatin1(kRefPrefix) + a.id;
  return (isDisplayableImage(a.mime) ? QStringLiteral("![%1](%2)") : QStringLiteral("[%1](%2)")).arg(label, target);
}

QStringList refsIn(const QString& markdown) {
  QStringList out;
  if(!markdown.contains(QLatin1String(kRefPrefix))) {
    return out;
  }
  auto it = refPattern().globalMatch(markdown);
  while(it.hasNext()) {
    const QString id = it.next().captured(1);
    if(!out.contains(id)) {
      out.append(id);
    }
  }
  return out;
}

QHash<QString, QString> refLabelsIn(const QString& markdown) {
  QHash<QString, QString> out;
  for(const QString& id : refsIn(markdown)) {
    out.insert(id, QString());
  }
  if(out.isEmpty()) {
    return out;
  }
  auto it = linkPattern().globalMatch(markdown);
  while(it.hasNext()) {
    const QRegularExpressionMatch m = it.next();
    QString target = m.captured(3);
    if(target.startsWith(QLatin1Char('<'))) {
      target = target.mid(1, target.size() - 2);
    }
    if(!target.startsWith(QLatin1String(kRefPrefix))) {
      continue;
    }
    const QString id = target.mid(static_cast<int>(qstrlen(kRefPrefix)));
    auto slot = out.find(id);
    if(slot != out.end() && slot->isEmpty()) {
      QString label = m.captured(2);
      label.replace(QStringLiteral("\\]"), QStringLiteral("]"));
      label.replace(QStringLiteral("\\["), QStringLiteral("["));
      label.replace(QStringLiteral("\\\\"), QStringLiteral("\\"));
      *slot = label;
    }
  }
  return out;
}

QString remapRefs(const QString& markdown, const QHash<QString, QString>& idMap) {
  if(idMap.isEmpty() || !markdown.contains(QLatin1String(kRefPrefix))) {
    return markdown;
  }
  QString out;
  out.reserve(markdown.size());
  qsizetype last = 0;
  auto it = refPattern().globalMatch(markdown);
  while(it.hasNext()) {
    const QRegularExpressionMatch m = it.next();
    const auto to = idMap.constFind(m.captured(1));
    if(to == idMap.constEnd()) {
      continue;
    }
    out += QStringView(markdown).mid(last, m.capturedStart(1) - last);
    out += *to;
    last = m.capturedEnd(1);
  }
  out += QStringView(markdown).mid(last);
  return out;
}

QVariantList toVariantList(const QVector<Attachment>& xs) {
  QVariantList out;
  out.reserve(xs.size());
  for(const Attachment& a : xs) {
    QVariantMap m;
    m[QStringLiteral("id")] = a.id;
    m[QStringLiteral("name")] = a.name;
    m[QStringLiteral("size")] = static_cast<double>(a.size);
    m[QStringLiteral("mime")] = a.mime;
    out.append(m);
  }
  return out;
}

QVector<Attachment> fromVariantList(const QVariantList& xs) {
  QVector<Attachment> out;
  for(const QVariant& v : xs) {
    const QVariantMap m = v.toMap();
    Attachment a{m.value(QStringLiteral("id")).toString(),
                 m.value(QStringLiteral("name")).toString(),
                 static_cast<qint64>(m.value(QStringLiteral("size")).toDouble()),
                 m.value(QStringLiteral("mime")).toString()};
    const bool dup = std::any_of(out.cbegin(), out.cend(), [&](const Attachment& x) {
      return x.id == a.id;
    });
    if(isValidId(a.id) && !dup) {
      out.append(a);
    }
  }
  return out;
}

void remapProfile(Profile& p, const QHash<QString, QString>& idMap) {
  if(idMap.isEmpty()) {
    return;
  }
  for(Task& t : p.tasks) {
    for(Attachment& a : t.attachments) {
      a.id = idMap.value(a.id, a.id);
    }
    t.desc = remapRefs(t.desc, idMap);
  }
  for(Note& n : p.notes) {
    n.body = remapRefs(n.body, idMap);
  }
  for(DocPage& d : p.docPages) {
    d.body = remapRefs(d.body, idMap);
  }
  p.notesState = remapRefs(p.notesState, idMap);
  p.docsState = remapRefs(p.docsState, idMap);
}

QString formatSize(qint64 bytes, bool ru) {
  const double b = static_cast<double>(qMax<qint64>(0, bytes));
  const auto num = [](double v) {
    return v < 10.0 ? QString::number(v, 'f', 1) : QString::number(qRound64(v));
  };
  if(b < 1024.0) {
    return QString::number(qMax<qint64>(0, bytes)) + (ru ? QStringLiteral(" Б") : QStringLiteral(" B"));
  }
  if(b < 1024.0 * 1024.0) {
    return num(b / 1024.0) + (ru ? QStringLiteral(" КБ") : QStringLiteral(" KB"));
  }
  if(b < 1024.0 * 1024.0 * 1024.0) {
    return num(b / (1024.0 * 1024.0)) + (ru ? QStringLiteral(" МБ") : QStringLiteral(" MB"));
  }
  return num(b / (1024.0 * 1024.0 * 1024.0)) + (ru ? QStringLiteral(" ГБ") : QStringLiteral(" GB"));
}

namespace {
Shell& shellSlot() {
  static Shell slot;
  return slot;
}
}  // namespace

void setShellForTesting(Shell s) {
  shellSlot() = std::move(s);
}

bool shell(const QString& path, bool reveal) {
  if(shellSlot()) {
    return shellSlot()(path, reveal);
  }
  if(!reveal) {
    return QDesktopServices::openUrl(QUrl::fromLocalFile(path));
  }
#if defined(Q_OS_WIN)
  // One argument: explorer parses "/select,<path>" itself, quotes included.
  return QProcess::startDetached(QStringLiteral("explorer.exe"), {QStringLiteral("/select,") + QDir::toNativeSeparators(path)});
#elif defined(Q_OS_MACOS)
  return QProcess::startDetached(QStringLiteral("open"), {QStringLiteral("-R"), path});
#else
  // No portable "select this file"; the folder is the next best thing.
  return QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(path).absolutePath()));
#endif
}

QString errorText(AddResult::Error error, const QString& name, bool ru) {
  switch(error) {
    case AddResult::None:
      return QString();
    case AddResult::NotFound:
      return (ru ? QStringLiteral("Файл «%1» не найден") : QStringLiteral("%1 was not found")).arg(name);
    case AddResult::NotAFile:
      return (ru ? QStringLiteral("«%1» — не файл, прикрепить можно только файл")
                 : QStringLiteral("%1 is not a file — only files can be attached"))
          .arg(name);
    case AddResult::Link:
      return (ru ? QStringLiteral("«%1» — ссылка на другой файл; прикрепите сам файл")
                 : QStringLiteral("%1 is a link to another file — attach the file itself"))
          .arg(name);
    case AddResult::TooLarge:
      return (ru ? QStringLiteral("«%1» больше %2 — такой файл не прикрепить")
                 : QStringLiteral("%1 is larger than %2 and was not attached"))
          .arg(name, formatSize(kMaxFileBytes, ru));
    case AddResult::Unreadable:
      return (ru ? QStringLiteral("Не удалось прочитать «%1»") : QStringLiteral("Could not read %1")).arg(name);
    case AddResult::WriteFailed:
      return (ru ? QStringLiteral("Не удалось сохранить «%1» в папку вложений")
                 : QStringLiteral("Could not save %1 to the attachments folder"))
          .arg(name);
  }
  return QString();
}

// ── Store ──

Store::Store(QString dir) : m_dir(QDir::cleanPath(std::move(dir))) {
}

QString Store::pathFor(const QString& id) const {
  if(!isValidId(id) || m_dir.isEmpty()) {
    return QString();
  }
  return m_dir + QLatin1Char('/') + id;
}

bool Store::contains(const QString& id) const {
  const QString p = pathFor(id);
  if(p.isEmpty()) {
    return false;
  }
  const QFileInfo fi(p);
  return fi.isFile() && !isLinkLike(fi);
}

qint64 Store::sizeOf(const QString& id) const {
  return contains(id) ? QFileInfo(pathFor(id)).size() : -1;
}

AddResult Store::commitTemp(const QString& tempPath, const QByteArray& sha, const QString& name, const QString& mime, qint64 size) const {
  AddResult r;
  r.attachment.id = idFor(sha, name);
  r.attachment.name = name;
  r.attachment.size = size;
  r.attachment.mime = mime;
  const QString dest = pathFor(r.attachment.id);
  if(contains(r.attachment.id) && QFileInfo(dest).size() == size) {
    // Same bytes, same name: already here. The id is a hash of the content, so
    // the file on disk is this file.
    QFile::remove(tempPath);
    r.deduplicated = true;
    return r;
  }
  // A file under the id that is not the right size is damage (a copy cut
  // short); the fresh bytes replace it.
  if(QFileInfo::exists(dest)) {
    QFile::setPermissions(dest, QFile::ReadOwner | QFile::WriteOwner);
    QFile::remove(dest);
  }
  if(!moveIntoPlace(tempPath, dest)) {
    QFile::remove(tempPath);
    r.error = AddResult::WriteFailed;
    return r;
  }
  // Read-only, so an editor the file is opened in cannot change the bytes the
  // name promises.
  QFile::setPermissions(dest, QFile::ReadOwner | QFile::ReadUser | QFile::ReadGroup | QFile::ReadOther);
  return r;
}

AddResult Store::addFile(const QString& path, const QString& displayName, qint64 maxBytes) const {
  AddResult r;
  const QFileInfo fi(path);
  const QString name = displayName.isEmpty() ? fi.fileName() : displayName;
  r.attachment.name = name;
  if(isLinkLike(fi)) {
    r.error = AddResult::Link;
    return r;
  }
  if(!fi.exists()) {
    r.error = AddResult::NotFound;
    return r;
  }
  if(!fi.isFile()) {
    r.error = AddResult::NotAFile;
    return r;
  }
  if(fi.size() > maxBytes) {
    r.error = AddResult::TooLarge;
    return r;
  }
  QFile src(fi.absoluteFilePath());
  if(!src.open(QIODevice::ReadOnly)) {
    r.error = AddResult::Unreadable;
    return r;
  }
  if(!QDir().mkpath(m_dir)) {
    r.error = AddResult::WriteFailed;
    return r;
  }
  // A plain QFile under a name of our own rather than QTemporaryFile, which
  // on Windows can keep its handle past close() and make the rename fail.
  QFile tmp(m_dir + QStringLiteral("/.incoming-") + QUuid::createUuid().toString(QUuid::Id128));
  if(!tmp.open(QIODevice::WriteOnly | QIODevice::NewOnly)) {
    r.error = AddResult::WriteFailed;
    return r;
  }
  QCryptographicHash hash(QCryptographicHash::Sha256);
  QByteArray head;
  qint64 total = 0;
  while(!src.atEnd()) {
    const QByteArray chunk = src.read(kChunk);
    if(chunk.isEmpty() && src.error() != QFileDevice::NoError) {
      tmp.close();
      QFile::remove(tmp.fileName());
      r.error = AddResult::Unreadable;
      return r;
    }
    if(head.isEmpty()) {
      head = chunk.left(4096);
    }
    total += chunk.size();
    // The file grew while it was read.
    if(total > maxBytes) {
      tmp.close();
      QFile::remove(tmp.fileName());
      r.error = AddResult::TooLarge;
      return r;
    }
    hash.addData(chunk);
    if(tmp.write(chunk) != chunk.size()) {
      tmp.close();
      QFile::remove(tmp.fileName());
      r.error = AddResult::WriteFailed;
      return r;
    }
  }
  const QString tempPath = tmp.fileName();
  if(!tmp.flush()) {
    tmp.close();
    QFile::remove(tempPath);
    r.error = AddResult::WriteFailed;
    return r;
  }
  tmp.close();
  return commitTemp(tempPath, hash.result(), name, mimeFor(name, head), total);
}

AddResult Store::addBytes(const QByteArray& bytes, const QString& name, const QString& mime, qint64 maxBytes) const {
  AddResult r;
  r.attachment.name = name;
  if(bytes.size() > maxBytes) {
    r.error = AddResult::TooLarge;
    return r;
  }
  if(!QDir().mkpath(m_dir)) {
    r.error = AddResult::WriteFailed;
    return r;
  }
  QFile tmp(m_dir + QStringLiteral("/.incoming-") + QUuid::createUuid().toString(QUuid::Id128));
  if(!tmp.open(QIODevice::WriteOnly | QIODevice::NewOnly) || tmp.write(bytes) != bytes.size() || !tmp.flush()) {
    const QString p = tmp.fileName();
    tmp.close();
    QFile::remove(p);
    r.error = AddResult::WriteFailed;
    return r;
  }
  const QString tempPath = tmp.fileName();
  tmp.close();
  const QByteArray sha = QCryptographicHash::hash(bytes, QCryptographicHash::Sha256);
  return commitTemp(tempPath, sha, name, mime.isEmpty() ? mimeFor(name, bytes.left(4096)) : mime, bytes.size());
}

QStringList Store::ids() const {
  QStringList out;
  const QDir d(m_dir);
  if(!d.exists()) {
    return out;
  }
  for(const QFileInfo& fi : d.entryInfoList(QDir::Files | QDir::Hidden | QDir::System, QDir::Name)) {
    if(isValidId(fi.fileName()) && !isLinkLike(fi)) {
      out.append(fi.fileName());
    }
  }
  return out;
}

bool Store::remove(const QString& id) const {
  const QString p = pathFor(id);
  if(p.isEmpty() || !QFileInfo::exists(p)) {
    return false;
  }
  QFile::setPermissions(p, QFile::ReadOwner | QFile::WriteOwner);
  return QFile::remove(p);
}

// ── Folder of .md files ──

namespace {

// The file a relative link names, or an empty path when it names something
// that is not a plain file inside the vault.
QString resolveInVault(const QString& target, const QDir& root, const QString& rootCanonical, const QString& noteDir) {
  QString decoded = QUrl::fromPercentEncoding(target.toUtf8());
  const qsizetype hash = decoded.indexOf(QLatin1Char('#'));
  if(hash >= 0) {
    decoded.truncate(hash);
  }
  decoded = QDir::fromNativeSeparators(decoded.trimmed());
  if(decoded.isEmpty() || decoded.startsWith(QLatin1Char('/')) || decoded.startsWith(QLatin1Char('#'))) {
    return QString();
  }
  // Any scheme, or a drive letter.
  const qsizetype colon = decoded.indexOf(QLatin1Char(':'));
  const qsizetype slash = decoded.indexOf(QLatin1Char('/'));
  if(colon >= 0 && (slash < 0 || colon < slash)) {
    return QString();
  }
  const QString suffix = QFileInfo(decoded).suffix().toLower();
  if(suffix == QLatin1String("md") || suffix == QLatin1String("markdown")) {
    return QString();
  }
  const QStringList candidates = {QDir::cleanPath(root.filePath(noteDir.isEmpty() ? decoded : noteDir + QLatin1Char('/') + decoded)),
                                  QDir::cleanPath(root.filePath(decoded))};
  for(const QString& c : candidates) {
    const QFileInfo fi(c);
    if(isLinkLike(fi) || !fi.isFile()) {
      continue;
    }
    // The canonical path settles "..", and a junction somewhere up the path.
    const QString real = fi.canonicalFilePath();
    if(real.isEmpty() || !real.startsWith(rootCanonical + QLatin1Char('/'), Qt::CaseInsensitive)) {
      continue;
    }
    return real;
  }
  return QString();
}

// Hash a file without storing it (the import preview).
bool hashFile(const QString& path, qint64 maxBytes, QByteArray* sha, QByteArray* head, qint64* size) {
  QFile f(path);
  if(f.size() > maxBytes || !f.open(QIODevice::ReadOnly)) {
    return false;
  }
  QCryptographicHash hash(QCryptographicHash::Sha256);
  *size = 0;
  while(!f.atEnd()) {
    const QByteArray chunk = f.read(kChunk);
    if(chunk.isEmpty()) {
      break;
    }
    if(head->isEmpty()) {
      *head = chunk.left(4096);
    }
    *size += chunk.size();
    hash.addData(chunk);
  }
  *sha = hash.result();
  return *size <= maxBytes;
}

}  // namespace

VaultRefResult importVaultRefs(
    const QString& markdown, const QDir& vaultRoot, const QString& noteRelativePath, const Store* store, bool ru) {
  VaultRefResult out;
  out.text = markdown;
  if(!markdown.contains(QLatin1String("](")) && !markdown.contains(QLatin1String("]( "))) {
    return out;
  }
  const QString rootCanonical = QFileInfo(vaultRoot.absolutePath()).canonicalFilePath();
  if(rootCanonical.isEmpty()) {
    return out;
  }
  QString noteDir = QFileInfo(noteRelativePath).path();
  if(noteDir == QLatin1String(".")) {
    noteDir.clear();
  }
  QHash<QString, QString> done;  // resolved path → id
  QString rebuilt;
  qsizetype last = 0;
  auto it = linkPattern().globalMatch(markdown);
  while(it.hasNext()) {
    const QRegularExpressionMatch m = it.next();
    QString target = m.captured(3);
    const bool angled = target.startsWith(QLatin1Char('<'));
    if(angled) {
      target = target.mid(1, target.size() - 2);
    }
    const QString real = resolveInVault(target, vaultRoot, rootCanonical, noteDir);
    if(real.isEmpty()) {
      continue;
    }
    QString id = done.value(real);
    if(id.isEmpty()) {
      const QString label = m.captured(2);
      const QString fileName = QFileInfo(real).fileName();
      // A file heap exported keeps the name it had in heap, which the link
      // label carries; one written by hand keeps its own file name.
      const bool heapNamed = isValidId(fileName);
      QString name = heapNamed && !label.isEmpty() ? label : fileName;
      // The extension decides the id, so it has to be the file's own.
      if(heapNamed && extensionOf(name) != extensionOf(fileName) && !extensionOf(fileName).isEmpty()) {
        name += QLatin1Char('.') + extensionOf(fileName);
      }
      Attachment a;
      if(QFileInfo(real).size() > kMaxFileBytes) {
        out.warnings << errorText(AddResult::TooLarge, fileName, ru);
        continue;
      }
      if(store != nullptr) {
        const AddResult r = store->addFile(real, name);
        if(!r.ok()) {
          out.warnings << errorText(r.error, fileName, ru);
          continue;
        }
        a = r.attachment;
      } else {
        QByteArray sha;
        QByteArray head;
        qint64 size = 0;
        if(!hashFile(real, kMaxFileBytes, &sha, &head, &size)) {
          out.warnings << errorText(AddResult::Unreadable, fileName, ru);
          continue;
        }
        a.id = idFor(sha, name);
        a.name = name;
        a.size = size;
        a.mime = mimeFor(name, head);
      }
      id = a.id;
      done.insert(real, id);
      out.attachments.append(a);
    }
    const QString newTarget = QString::fromLatin1(kRefPrefix) + id;
    if(newTarget == target) {
      continue;
    }
    rebuilt += QStringView(markdown).mid(last, m.capturedStart(3) - last);
    rebuilt += newTarget;
    last = m.capturedEnd(3);
  }
  if(last > 0) {
    rebuilt += QStringView(markdown).mid(last);
    out.text = rebuilt;
  }
  return out;
}

}  // namespace heap::attachments
