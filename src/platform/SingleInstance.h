#pragma once

#include <QByteArray>
#include <QObject>
#include <QString>

#include <functional>
#include <memory>
#include <optional>

class QLocalServer;
class QLockFile;

// One heap per data directory (PLAT-2).
//
// Close-to-tray makes a second launch the normal way to "open heap" again, and
// two processes on one state.json each save their own copy: whichever writes
// last silently erases the other's edits. The first process takes a QLockFile
// in the data dir and listens on a QLocalServer named after that dir; a second
// one finds the lock, hands its request ("activate", optionally a view) to the
// first over the socket, and exits.
//
// Keyed by data dir, not by user: `heap --data-dir /tmp/x` next to the real
// profile is a different workspace and may run alongside it.
namespace heap::platform {

class SingleInstance : public QObject {
  Q_OBJECT
 public:
  enum class Result {
    Primary,    // this process owns the data dir
    Forwarded,  // another heap owns it and got our message: exit now
    Busy,       // another heap owns it but did not answer
  };

  explicit SingleInstance(const QString& dataDir, QObject* parent = nullptr);
  ~SingleInstance() override;

  // Takes the lock, or forwards `message` to the process holding it.
  Result acquire(const QByteArray& message);

  // Takes the lock without listening: a command-line run that changes the
  // data while no window is open (APP-173). True when this process now owns
  // the data dir (or nothing can be coordinated: a read-only dir).
  bool tryLock();

  // Answers a request line (one line of JSON, see cli/CliCore.h) that a `heap`
  // command sent; the reply goes back on the same connection. A line that is
  // not JSON keeps the plain "ok" + messageReceived protocol.
  using RequestHandler = std::function<QByteArray(const QByteArray& line)>;
  void setRequestHandler(RequestHandler handler);

  // Sends `line` to the heap that owns `dataDir` and returns its reply line.
  // Empty when no heap is listening there, or it did not answer in time.
  static std::optional<QByteArray> request(const QString& dataDir, const QByteArray& line, int timeoutMs);

  // The local-socket name for a data dir (exposed for tests).
  static QString serverName(const QString& dataDir);

 signals:
  // Another launch asked this one to come forward; `message` is what it sent.
  void messageReceived(const QByteArray& message);

 private:
  bool listen();
  static bool forward(const QString& name, const QByteArray& message);

  QString m_dataDir;
  std::unique_ptr<QLockFile> m_lock;
  QLocalServer* m_server = nullptr;
  RequestHandler m_requestHandler;
};

}  // namespace heap::platform
