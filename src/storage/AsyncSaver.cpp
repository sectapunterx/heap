#include "storage/AsyncSaver.h"

#include <QMetaObject>

namespace heap::storage {

AsyncSaver::AsyncSaver(QObject* parent) : QObject(parent) {
  m_thread = std::thread([this]() {
    run();
  });
}

AsyncSaver::~AsyncSaver() {
  {
    std::unique_lock lock(m_mutex);
    // Whatever was submitted still reaches disk: the destructor is the last
    // chance, and a pending job is the user's newest edit.
    m_idle.wait(lock, [this]() {
      return !m_pending && !m_busy;
    });
    m_stop = true;
  }
  m_wake.notify_all();
  if(m_thread.joinable()) {
    m_thread.join();
  }
}

void AsyncSaver::submit(quint64 generation, Job job) {
  {
    const std::lock_guard lock(m_mutex);
    m_pending = std::make_pair(generation, std::move(job));
  }
  m_wake.notify_all();
}

void AsyncSaver::flush() {
  {
    std::unique_lock lock(m_mutex);
    m_idle.wait(lock, [this]() {
      return !m_pending && !m_busy;
    });
  }
  drain();
}

void AsyncSaver::drain() {
  std::deque<SaveOutcome> done;
  {
    const std::lock_guard lock(m_mutex);
    done.swap(m_done);
  }
  for(const SaveOutcome& o : done) {
    emit finished(o);
  }
}

void AsyncSaver::run() {
  for(;;) {
    std::pair<quint64, Job> job;
    {
      std::unique_lock lock(m_mutex);
      m_wake.wait(lock, [this]() {
        return m_stop || m_pending.has_value();
      });
      if(!m_pending) {
        return;  // stopping, nothing left to write
      }
      job = std::move(*m_pending);
      m_pending.reset();
      m_busy = true;
    }
    SaveOutcome outcome = job.second ? job.second() : SaveOutcome{};
    outcome.generation = job.first;
    {
      const std::lock_guard lock(m_mutex);
      m_done.push_back(outcome);
    }
    // Hand the result to the owner's thread. drain() is idempotent, so a flush
    // that already delivered it makes this a no-op. Posted while still busy, so
    // the destructor (which waits for idle) cannot run underneath it.
    QMetaObject::invokeMethod(this, &AsyncSaver::drain, Qt::QueuedConnection);
    {
      const std::lock_guard lock(m_mutex);
      m_busy = false;
    }
    m_idle.notify_all();
  }
}

}  // namespace heap::storage
