#include "update/Updater.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QList>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QStringList>
#include <QUrl>

#include <utility>

namespace heap::update {

namespace {

// GitHub REST endpoint for the newest *published* (non-draft, non-prerelease)
// release of the repo.
constexpr auto kLatestReleaseUrl = "https://api.github.com/repos/sectapunterx/heap/releases/latest";

struct ParsedVersion {
  QList<int> parts;
  bool preRelease = false;
};

ParsedVersion parseVersion(QString v) {
  v = v.trimmed();
  if(v.startsWith('v') || v.startsWith('V')) {
    v.remove(0, 1);
  }
  const qsizetype dash = v.indexOf('-');
  ParsedVersion parsed;
  parsed.preRelease = dash >= 0;
  const QString core = parsed.preRelease ? v.left(dash) : v;
  const QStringList comps = core.split('.', Qt::SkipEmptyParts);
  for(const QString& c : comps) {
    bool ok = false;
    const int n = c.toInt(&ok);
    parsed.parts.append(ok ? n : 0);
  }
  return parsed;
}

}  // namespace

bool isNewerVersion(const QString& current, const QString& latest) {
  const ParsedVersion a = parseVersion(current);
  const ParsedVersion b = parseVersion(latest);
  const qsizetype n = qMax(a.parts.size(), b.parts.size());
  for(qsizetype i = 0; i < n; ++i) {
    const int av = i < a.parts.size() ? a.parts.at(i) : 0;
    const int bv = i < b.parts.size() ? b.parts.at(i) : 0;
    if(bv != av) {
      return bv > av;
    }
  }
  // Equal numeric core: a plain release outranks a pre-release of the same core.
  if(a.preRelease != b.preRelease) {
    return a.preRelease && !b.preRelease;
  }
  return false;
}

Updater::Updater(QString currentVersion, QObject* parent) :
    QObject(parent), m_currentVersion(std::move(currentVersion)), m_nam(new QNetworkAccessManager(this)) {
}

Updater::~Updater() = default;

void Updater::checkForUpdates() {
  if(m_checking) {
    return;
  }
  m_checking = true;

  QNetworkRequest req{QUrl(QLatin1String(kLatestReleaseUrl))};
  req.setRawHeader("Accept", "application/vnd.github+json");
  req.setRawHeader("User-Agent", "heap-updater");

  QNetworkReply* reply = m_nam->get(req);
  connect(reply, &QNetworkReply::finished, this, [this, reply]() {
    reply->deleteLater();
    m_checking = false;

    if(reply->error() != QNetworkReply::NoError) {
      emit checkFailed(reply->errorString());
      return;
    }

    const QJsonObject obj = QJsonDocument::fromJson(reply->readAll()).object();
    const QString tag = obj.value(QStringLiteral("tag_name")).toString();
    const QString url = obj.value(QStringLiteral("html_url")).toString();
    if(tag.isEmpty()) {
      emit checkFailed(QStringLiteral("no release tag in GitHub response"));
      return;
    }

    if(isNewerVersion(m_currentVersion, tag)) {
      emit updateAvailable(tag, url);
    } else {
      emit upToDate(m_currentVersion);
    }
  });
}

}  // namespace heap::update
