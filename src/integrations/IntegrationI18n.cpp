#include "integrations/IntegrationI18n.h"

#include <QHash>
#include <QList>
#include <QPair>
#include <QRegularExpression>

namespace heap::integrations {

namespace {

struct Entry {
  const char* en;
  const char* ru;
};

const QHash<QString, Entry>& table() {
  static const QHash<QString, Entry> t = {
      {QStringLiteral("sync.headline"), {"%1: %2", "%1: %2"}},
      {QStringLiteral("sync.outOfScope"),
       {"%1 outside the current filter (kept — archive them from Settings → Integrations)",
        "%1 вне текущего фильтра (оставлены — архивировать можно в Настройки → Интеграции)"}},
      {QStringLiteral("sync.queued"),
       {"%1: the tracker is out of reach — the move goes out after the next sync",
        "%1: трекер недоступен — перемещение уйдёт после следующей синхронизации"}},
      {QStringLiteral("sync.queuedDisconnected"),
       {"%1: %2 is not connected — the move goes out once you reconnect and sync",
        "%1: %2 не подключён — перемещение уйдёт после переподключения и синхронизации"}},
      {QStringLiteral("int.offline"),
       {"%1 is out of reach — still signed in, retrying", "%1 недоступен — вход сохранён, повторяю попытку"}},
      {QStringLiteral("int.backOnline"), {"%1 is reachable again", "%1 снова доступен"}},
      {QStringLiteral("int.transitionRefused"),
       {"%1: the %2 workflow has no step to “%3” from here — it can go to %4",
        "%1: в workflow %2 отсюда нет перехода в «%3» — доступно: %4"}},
      {QStringLiteral("int.transitionNone"),
       {"%1: the %2 workflow has no step to “%3” from here", "%1: в workflow %2 отсюда нет перехода в «%3»"}},
      {QStringLiteral("int.outOfScopeArchived"), {"Archived %1 card(s) outside the filter", "В архив: %1 карточек вне фильтра"}},
      {QStringLiteral("task.conflictTookTracker"), {"%1: took the tracker's version", "%1: взята версия из трекера"}},
      {QStringLiteral("task.conflictKeptMine"), {"%1: kept your version", "%1: оставлена ваша версия"}},
      {QStringLiteral("update.couldNotCheck"), {"Couldn't check for updates — %1", "Не удалось проверить обновления — %1"}},
      {QStringLiteral("update.rateLimited"),
       {"GitHub's rate limit was hit, try again later", "исчерпан лимит запросов GitHub, попробуйте позже"}},
      {QStringLiteral("update.offline"), {"no connection", "нет соединения"}},
      {QStringLiteral("issue.logCopied"),
       {"Full diagnostics copied — paste them into the issue if they help",
        "Полная диагностика скопирована — вставьте её в issue, если пригодится"}},
  };
  return t;
}

// Whole sentences heap's providers write, English → Russian.
const QList<QPair<QString, QString>>& phrases() {
  static const QList<QPair<QString, QString>> p = {
      {QStringLiteral("the browser session is no longer valid; sign in again"),
       QStringLiteral("сессия браузера больше не действительна — войдите снова")},
      {QStringLiteral("use an API token from id.atlassian.com, with the email of that same Atlassian account"),
       QStringLiteral("используйте API-токен с id.atlassian.com и email того же аккаунта Atlassian")},
      {QStringLiteral("Jira browser sign-in is incomplete — sign in again"),
       QStringLiteral("вход в Jira через браузер не завершён — войдите снова")},
      {QStringLiteral("Jira URL/email/token not configured"), QStringLiteral("не заданы адрес, email или токен Jira")},
      {QStringLiteral("Mattermost server URL or token is missing"), QStringLiteral("не заданы адрес сервера Mattermost или токен")},
      {QStringLiteral("Mattermost server URL must be https"), QStringLiteral("адрес сервера Mattermost должен начинаться с https")},
      {QStringLiteral("Mattermost is not configured"), QStringLiteral("Mattermost не настроен")},
      {QStringLiteral("the server accepted the sign-in but returned no session token"),
       QStringLiteral("сервер принял вход, но не вернул токен сессии")},
      {QStringLiteral("timed out waiting for browser sign-in"), QStringLiteral("не дождались входа в браузере")},
      {QStringLiteral("timed out waiting for device authorization"), QStringLiteral("не дождались подтверждения устройства")},
      {QStringLiteral("browser sign-in for this provider needs Qt 6.9 or newer — use an access token"),
       QStringLiteral("вход через браузер для этого трекера требует Qt 6.9 или новее — используйте токен доступа")},
      {QStringLiteral("authorization was denied, expired, or failed"), QStringLiteral("доступ отклонён, истёк или не выдан")},
      {QStringLiteral("you declined the authorization request"), QStringLiteral("вы отклонили запрос доступа")},
      {QStringLiteral("no access token in the response"), QStringLiteral("в ответе нет токена доступа")},
      {QStringLiteral("nothing to refresh with"), QStringLiteral("нечем обновить сессию")},
      {QStringLiteral("nothing to exchange"), QStringLiteral("нечего обменивать")},
      {QStringLiteral("the issue's repo is unknown — sync it again first"),
       QStringLiteral("репозиторий задачи неизвестен — сначала синхронизируйте её ещё раз")},
      {QStringLiteral("not configured"), QStringLiteral("не настроено")},
      {QStringLiteral("unsupported"), QStringLiteral("не поддерживается")},
  };
  return p;
}

}  // namespace

QString integrationText(const QString& key, bool ru) {
  const auto it = table().constFind(key);
  if(it == table().constEnd()) {
    return {};
  }
  return QString::fromUtf8(ru ? it->ru : it->en);
}

QString translateProviderReason(const QString& reason, bool ru) {
  if(!ru || reason.isEmpty()) {
    return reason;
  }
  // Parameterised sentences first; each recurses on its own tail.
  static const QRegularExpression noTransition(
      QStringLiteral(R"(^this issue has no transition to a status mapped to '([^']*)' — map one in Settings → Integrations$)"));
  if(const auto m = noTransition.match(reason); m.hasMatch()) {
    return QStringLiteral("у задачи нет перехода в статус, сопоставленный с «%1», — сопоставьте его в Настройки → Интеграции")
        .arg(m.captured(1));
  }
  static const QRegularExpression pagesOnly(QStringLiteral(R"(^(\w+): only (\d+) page\(s\) — (.*)$)"),
                                            QRegularExpression::DotMatchesEverythingOption);
  if(const auto m = pagesOnly.match(reason); m.hasMatch()) {
    return QStringLiteral("%1: получено страниц — %2; %3").arg(m.captured(1), m.captured(2), translateProviderReason(m.captured(3), ru));
  }
  static const QRegularExpression pageLimit(QStringLiteral(R"(^stopped at the (\d+)-page limit$)"));
  if(const auto m = pageLimit.match(reason); m.hasMatch()) {
    return QStringLiteral("остановлено на пределе в %1 стр.").arg(m.captured(1));
  }
  static const QRegularExpression portBusy(QStringLiteral(R"(^redirect port (\d+) is busy — close the other app and retry$)"));
  if(const auto m = portBusy.match(reason); m.hasMatch()) {
    return QStringLiteral("порт %1 для возврата из браузера занят — закройте другое приложение и повторите").arg(m.captured(1));
  }
  // Whole known sentences, possibly behind an "HTTP 401 — " prefix or joined
  // with " · ". Exact phrases only, longest first by construction of the list.
  QString out = reason;
  bool any = false;
  for(const auto& [en, rus] : phrases()) {
    const qsizetype at = out.indexOf(en);
    if(at < 0) {
      continue;
    }
    // A short phrase ("not configured") must be the whole reason or a whole
    // clause, never a fragment of the tracker's own sentence.
    const qsizetype end = at + en.size();
    const bool startsClause = at == 0 || out.mid(0, at).endsWith(QStringLiteral("— ")) || out.mid(0, at).endsWith(QStringLiteral("· "));
    const bool endsClause = end == out.size() || out.mid(end).startsWith(QStringLiteral(" ·"));
    if(!startsClause || !endsClause) {
      continue;
    }
    out.replace(at, en.size(), rus);
    any = true;
  }
  return any ? out : reason;
}

}  // namespace heap::integrations
