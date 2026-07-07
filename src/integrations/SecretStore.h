#pragma once

#include <QHash>
#include <QObject>
#include <QPair>
#include <QString>
#include <QVector>

#include <functional>

namespace heap::integrations {

// Stores integration access tokens in the OS keychain (Windows Credential
// Manager / macOS Keychain / libsecret) via QtKeychain, keeping them out of
// state.json and its backups/exports. When QtKeychain is unavailable at build
// time — or no secret service exists at runtime — it degrades to a private
// `secrets.json` in the app data dir so the feature still works headless.
//
// An in-memory cache backs the synchronous value()/has() getters; the keychain
// reads that fill it are asynchronous (see load()).
class SecretStore : public QObject {
  Q_OBJECT

 public:
  explicit SecretStore(QObject* parent = nullptr);

  QString value(const QString& providerId, const QString& field) const;
  bool has(const QString& providerId, const QString& field) const;

  void setValue(const QString& providerId, const QString& field, const QString& value);
  void remove(const QString& providerId, const QString& field);

  // Populate the cache for the given (providerId, field) pairs, then invoke
  // `done`. Keychain reads are async; the fallback resolves immediately.
  void load(const QVector<QPair<QString, QString>>& keys, const std::function<void()>& done);

  // True when tokens live in the OS keychain; false when using the file fallback.
  bool usingKeychain() const {
    return m_keychain;
  }

 private:
  static QString cacheKey(const QString& providerId, const QString& field);
  QString fallbackPath() const;
  void loadFallbackFile();
  void writeFallbackFile() const;

  QHash<QString, QString> m_cache;
  bool m_keychain = false;
};

}  // namespace heap::integrations
