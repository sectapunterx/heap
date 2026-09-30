#pragma once

#include <QObject>
#include <QString>

#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <optional>
#include <thread>

// Runs state.json saves off the UI thread (PLAT-23).
//
// A save used to serialize the whole state on the UI thread: ~215 ms of frozen
// window per edit at 10k tasks. The UI thread now only takes a snapshot —
// implicitly shared copies of the collections, a refcount bump each — and this
// worker turns it into JSON, rotates the backup and writes the file.
//
// One job runs at a time, in submission order; a job submitted while another
// is waiting replaces it (only the newest state is worth writing). flush()
// blocks until everything submitted so far is on disk, which is what the quit
// path, a backup restore and the tests need.
namespace heap::storage {

struct SaveOutcome {
  quint64 generation = 0;
  bool ok = false;
  QString error;
  qint64 bytes = 0;
};

class AsyncSaver : public QObject {
  Q_OBJECT
 public:
  using Job = std::function<SaveOutcome()>;

  explicit AsyncSaver(QObject* parent = nullptr);
  ~AsyncSaver() override;

  // Queue `job` under `generation` (stamped onto its outcome).
  void submit(quint64 generation, Job job);

  // Blocks until no job is pending or running, then delivers every finished
  // outcome synchronously through finished().
  void flush();

  // Delivers finished outcomes. Called from the UI thread's event loop after a
  // job completes, and by flush(). Never emits the same outcome twice.
  void drain();

 signals:
  void finished(const heap::storage::SaveOutcome& outcome);

 private:
  void run();

  std::mutex m_mutex;
  std::condition_variable m_wake;
  std::condition_variable m_idle;
  std::optional<std::pair<quint64, Job>> m_pending;
  bool m_busy = false;
  bool m_stop = false;
  std::deque<SaveOutcome> m_done;
  std::thread m_thread;
};

}  // namespace heap::storage
