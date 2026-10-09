#include "cli/CliConsole.h"
#include "cli/CliQuery.h"
#include "platform/Paths.h"
#include "platform/SingleInstance.h"
#include "storage/StateIO.h"

#include <QDateTime>
#include <QDir>
#include <QJsonDocument>

#ifndef HEAP_VERSION
#define HEAP_VERSION "0.0.0-dev"
#endif

namespace heap::cli {

namespace {
// How long a command waits for the window to answer (a big list, a slow save).
constexpr int kRequestTimeoutMs = 10000;
}  // namespace

bool changesData(Verb v) {
  return v == Verb::Add || v == Verb::Done;
}

std::optional<Snapshot> readSnapshot(QString* error) {
  const QString path = QDir(heap::paths::dataDir()).filePath(QStringLiteral("state.json"));
  const heap::storage::ReadResult read = heap::storage::readWithRetry(path, {100, 300});
  if(read.kind == heap::storage::ReadResult::Missing) {
    return Snapshot{};  // nothing written yet: no tasks
  }
  if(read.kind == heap::storage::ReadResult::Unreadable) {
    *error = QStringLiteral("cannot read %1: %2").arg(QDir::toNativeSeparators(path), read.error);
    return std::nullopt;
  }
  QJsonParseError parseError{};
  const QJsonDocument doc = QJsonDocument::fromJson(read.bytes, &parseError);
  if(!doc.isObject()) {
    *error = QStringLiteral("%1 is damaged (%2); open lowkey to recover it").arg(QDir::toNativeSeparators(path), parseError.errorString());
    return std::nullopt;
  }
  return snapshotFromState(doc.object(), error);
}

QString unusableState() {
  const QString path = QDir(heap::paths::dataDir()).filePath(QStringLiteral("state.json"));
  const heap::storage::ReadResult read = heap::storage::readWithRetry(path, {100, 300});
  if(read.kind == heap::storage::ReadResult::Missing) {
    return {};
  }
  if(read.kind == heap::storage::ReadResult::Unreadable) {
    return QStringLiteral("cannot read %1: %2").arg(QDir::toNativeSeparators(path), read.error);
  }
  // The same test the window's load applies before it recovers.
  QJsonParseError parseError{};
  const QJsonDocument doc = QJsonDocument::fromJson(read.bytes, &parseError);
  QString reason = parseError.errorString();
  if(doc.isObject() && heap::storage::validateShape(doc.object(), &reason)) {
    return {};
  }
  return QStringLiteral("%1 is damaged (%2); open lowkey to recover it").arg(QDir::toNativeSeparators(path), reason);
}

std::optional<Response> askWindow(const QByteArray& requestLine) {
  const std::optional<QByteArray> reply = heap::platform::SingleInstance::request(heap::paths::dataDir(), requestLine, kRequestTimeoutMs);
  if(!reply) {
    return std::nullopt;
  }
  if(const std::optional<Response> r = decodeResponse(*reply)) {
    return r;
  }
  // A heap from before APP-173 answers "ok" to anything and only comes forward.
  Response old;
  old.exitCode = kExitData;
  old.err = QStringLiteral("lowkey: the lowkey window open on this data directory is too old for commands; restart it\n");
  return old;
}

std::optional<int> runQuery(Request request) {
  if(request.verb == Verb::Help) {
    write(false, helpText());
    return kExitOk;
  }
  if(request.verb == Verb::Version) {
    write(false, QStringLiteral("lowkey %1\n").arg(QStringLiteral(HEAP_VERSION)));
    return kExitOk;
  }
  if(changesData(request.verb) || request.verb == Verb::Open) {
    return std::nullopt;
  }
  if(request.verb == Verb::Now) {
    // Read where the command runs: the window's own working directory is
    // somewhere else.
    request.branch = branchAt(QDir::currentPath());
  }
  // The window's live models when it is open, else state.json.
  if(const std::optional<Response> r = askWindow(encodeRequest(request))) {
    return report(*r);
  }
  QString error;
  const std::optional<Snapshot> s = readSnapshot(&error);
  if(!s) {
    return report({kExitData, QString(), QStringLiteral("lowkey: %1\n").arg(error)});
  }
  return report(answer(*s, request, QDateTime::currentDateTime()));
}

}  // namespace heap::cli
