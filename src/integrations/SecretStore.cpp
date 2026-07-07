#include "integrations/SecretStore.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTimer>

#include <memory>

#ifdef HEAP_USE_KEYCHAIN
#include <qt6keychain/keychain.h>
#endif

namespace heap::integrations {

namespace {
const QString kService = QStringLiteral("heap.integrations");
}

SecretStore::SecretStore(QObject* parent) : QObject(parent) {
#ifdef HEAP_USE_KEYCHAIN
  m_keychain = true;
#else

  loadFallbackFile();
#endif
}

QString SecretStore::cacheKey(const QString& providerId, const QString& field) {
  return providerId + QLatin1Char('/') + field;
}

QString SecretStore::value(const QString& providerId, const QString& field) const {
  return m_cache.value(cacheKey(providerId, field));
}

bool SecretStore::has(const QString& providerId, const QString& field) const {
  return !m_cache.value(cacheKey(providerId, field)).isEmpty();
}

void SecretStore::setValue(const QString& providerId, const QString& field, const QString& value) {
  const QString key = cacheKey(providerId, field);
  if(value.isEmpty()) {
    remove(providerId, field);
    return;
  }
  m_cache.insert(key, value);
#ifdef HEAP_USE_KEYCHAIN
  auto* job = new QKeychain::WritePasswordJob(kService, this);
  job->setAutoDelete(true);
  job->setKey(key);
  job->setTextData(value);
  job->start();
#else
  writeFallbackFile();
#endif
}

void SecretStore::remove(const QString& providerId, const QString& field) {
  const QString key = cacheKey(providerId, field);
  m_cache.remove(key);
#ifdef HEAP_USE_KEYCHAIN
  auto* job = new QKeychain::DeletePasswordJob(kService, this);
  job->setAutoDelete(true);
  job->setKey(key);
  job->start();
#else
  writeFallbackFile();
#endif
}

void SecretStore::load(const QVector<QPair<QString, QString>>& keys, const std::function<void()>& done) {
#ifdef HEAP_USE_KEYCHAIN
  if(keys.isEmpty()) {
    QTimer::singleShot(0, this, [done]() {
      if(done) {
        done();
      }
    });
    return;
  }
  auto remaining = std::make_shared<int>(keys.size());
  for(const auto& k : keys) {
    const QString cache = cacheKey(k.first, k.second);
    auto* job = new QKeychain::ReadPasswordJob(kService, this);
    job->setAutoDelete(true);
    job->setKey(cache);
    connect(job, &QKeychain::Job::finished, this, [this, cache, remaining, done](QKeychain::Job* j) {
      if(j->error() == QKeychain::NoError) {
        const QString text = static_cast<QKeychain::ReadPasswordJob*>(j)->textData();
        if(!text.isEmpty()) {
          m_cache.insert(cache, text);
        }
      }
      if(--(*remaining) == 0 && done) {
        done();
      }
    });
    job->start();
  }
#else
  (void)keys;
  loadFallbackFile();
  if(done) {
    done();
  }
#endif
}

QString SecretStore::fallbackPath() const {
  return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/secrets.json");
}

void SecretStore::loadFallbackFile() {
  QFile f(fallbackPath());
  if(!f.open(QIODevice::ReadOnly)) {
    return;
  }
  const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
  if(!doc.isObject()) {
    return;
  }
  const QJsonObject obj = doc.object();
  for(auto it = obj.constBegin(); it != obj.constEnd(); ++it) {
    m_cache.insert(it.key(), it.value().toString());
  }
}

void SecretStore::writeFallbackFile() const {
  const QString path = fallbackPath();
  QDir().mkpath(QFileInfo(path).absolutePath());
  QJsonObject obj;
  for(auto it = m_cache.constBegin(); it != m_cache.constEnd(); ++it) {
    obj.insert(it.key(), it.value());
  }
  QSaveFile f(path);
  if(!f.open(QIODevice::WriteOnly)) {
    return;
  }
  f.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
  f.commit();
}

}  // namespace heap::integrations
