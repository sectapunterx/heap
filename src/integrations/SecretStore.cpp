#include "integrations/SecretStore.h"
#include "platform/Paths.h"

#include <QDebug>
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

#ifdef HEAP_USE_KEYCHAIN
// Windows Credential Manager refuses blobs over 2560 bytes and an Atlassian
// access token is a JWT that can be longer, so a big value is spread over
// "<key>#0", "<key>#1", … with the plain key holding this marker + the count.
const QString kChunkMarker = QStringLiteral("heap-chunked:");
constexpr int kMaxKeychainBytes = 2000;

QString chunkKey(const QString& key, int index) {
  return key + QLatin1Char('#') + QString::number(index);
}
#endif
}  // namespace

SecretStore::SecretStore(QObject* parent) : QObject(parent) {
#ifdef HEAP_USE_KEYCHAIN
  // A redirected data dir (--data-dir, HEAP_DATA_DIR) or Qt's test mode means
  // "don't touch this user's real data" — and the OS keychain is per-user, not
  // per-data-dir, so a test run or a throwaway profile would otherwise read and
  // overwrite the real tokens. Those runs keep their secrets next to state.json.
  m_keychain = !heap::paths::dataDirOverridden() && !QStandardPaths::isTestModeEnabled();
#endif
  if(!m_keychain) {
    loadFallbackFile();
  }
}

QString SecretStore::cacheKey(const QString& providerId, const QString& field) {
  return providerId + QLatin1Char('/') + field;
}

QStringList SecretStore::chunkValue(const QString& value, int maxBytes) {
  if(maxBytes <= 0 || value.toUtf8().size() <= maxBytes) {
    return {value};
  }
  // Tokens are ASCII in practice, where one char is one byte. Anything else
  // gets the worst case UTF-8 can produce from one UTF-16 unit (3 bytes), so a
  // chunk never splits into something over the limit.
  const bool ascii = value.toUtf8().size() == value.size();
  const int step = qMax(1, ascii ? maxBytes : maxBytes / 3);
  QStringList out;
  for(int pos = 0; pos < value.size(); pos += step) {
    out.append(value.mid(pos, step));
  }
  return out;
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
  if(m_keychain) {
    const QStringList chunks = chunkValue(value, kMaxKeychainBytes);
    const int newCount = chunks.size() > 1 ? static_cast<int>(chunks.size()) : 0;
    const int oldCount = m_chunkCounts.value(key);
    // Chunks first, marker last: a reader that sees the marker finds its parts.
    for(int i = 0; i < newCount; ++i) {
      writeKeychain(chunkKey(key, i), chunks.at(i));
    }
    writeKeychain(key, newCount > 0 ? kChunkMarker + QString::number(newCount) : value);
    for(int i = newCount; i < oldCount; ++i) {
      deleteKeychain(chunkKey(key, i));
    }
    if(newCount > 0) {
      m_chunkCounts.insert(key, newCount);
    } else {
      m_chunkCounts.remove(key);
    }
    return;
  }
#endif
  writeFallbackFile();
}

void SecretStore::remove(const QString& providerId, const QString& field) {
  const QString key = cacheKey(providerId, field);
  m_cache.remove(key);
#ifdef HEAP_USE_KEYCHAIN
  if(m_keychain) {
    deleteKeychain(key);
    const int oldCount = m_chunkCounts.take(key);
    for(int i = 0; i < oldCount; ++i) {
      deleteKeychain(chunkKey(key, i));
    }
    return;
  }
#endif
  writeFallbackFile();
}

#ifdef HEAP_USE_KEYCHAIN
void SecretStore::writeKeychain(const QString& key, const QString& value) {
  auto* job = new QKeychain::WritePasswordJob(kService, this);
  job->setAutoDelete(true);
  job->setKey(key);
  job->setTextData(value);
  // A failed write used to vanish: the token worked until restart (the cache
  // still had it) and then the integration was silently signed out.
  connect(job, &QKeychain::Job::finished, this, [key](QKeychain::Job* j) {
    if(j->error() != QKeychain::NoError) {
      qWarning() << "keychain write failed for" << key << ":" << j->errorString();
    }
  });
  job->start();
}

void SecretStore::deleteKeychain(const QString& key) {
  auto* job = new QKeychain::DeletePasswordJob(kService, this);
  job->setAutoDelete(true);
  job->setKey(key);
  job->start();
}
#endif

void SecretStore::load(const QVector<QPair<QString, QString>>& keys, const std::function<void()>& done) {
#ifdef HEAP_USE_KEYCHAIN
  if(m_keychain) {
    if(keys.isEmpty()) {
      QTimer::singleShot(0, this, [done]() {
        if(done) {
          done();
        }
      });
      return;
    }
    auto remaining = std::make_shared<int>(keys.size());
    const auto finishOne = [remaining, done]() {
      if(--(*remaining) == 0 && done) {
        done();
      }
    };
    for(const auto& k : keys) {
      const QString cache = cacheKey(k.first, k.second);
      auto* job = new QKeychain::ReadPasswordJob(kService, this);
      job->setAutoDelete(true);
      job->setKey(cache);
      connect(job, &QKeychain::Job::finished, this, [this, cache, remaining, finishOne](QKeychain::Job* j) {
        QString text;
        if(j->error() == QKeychain::NoError) {
          text = static_cast<QKeychain::ReadPasswordJob*>(j)->textData();
        }
        const int count = text.startsWith(kChunkMarker) ? text.mid(kChunkMarker.size()).toInt() : 0;
        if(count <= 0) {
          if(!text.isEmpty()) {
            m_cache.insert(cache, text);
          }
          finishOne();
          return;
        }
        // Chunked value: read every part, then stitch them together. One
        // missing part makes the whole value useless, so it is dropped.
        m_chunkCounts.insert(cache, count);
        auto parts = std::make_shared<QStringList>(count);
        auto partsLeft = std::make_shared<int>(count);
        auto partsOk = std::make_shared<bool>(true);
        for(int i = 0; i < count; ++i) {
          auto* partJob = new QKeychain::ReadPasswordJob(kService, this);
          partJob->setAutoDelete(true);
          partJob->setKey(chunkKey(cache, i));
          connect(partJob, &QKeychain::Job::finished, this, [this, cache, i, parts, partsLeft, partsOk, finishOne](QKeychain::Job* pj) {
            if(pj->error() == QKeychain::NoError) {
              (*parts)[i] = static_cast<QKeychain::ReadPasswordJob*>(pj)->textData();
            } else {
              *partsOk = false;
            }
            if(--(*partsLeft) > 0) {
              return;
            }
            if(*partsOk) {
              m_cache.insert(cache, parts->join(QString()));
            } else {
              qWarning() << "keychain value for" << cache << "is missing a part — ignoring it";
            }
            finishOne();
          });
          partJob->start();
        }
      });
      job->start();
    }
    return;
  }
#endif
  (void)keys;
  loadFallbackFile();
  if(done) {
    done();
  }
}

QString SecretStore::fallbackPath() const {
  return heap::paths::dataDir() + QStringLiteral("/secrets.json");
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
    qWarning() << "cannot write" << path << ":" << f.errorString();
    return;
  }
  f.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
  if(!f.commit()) {
    qWarning() << "cannot write" << path << ":" << f.errorString();
  }
}

}  // namespace heap::integrations
