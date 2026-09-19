# Tracker integrations

`heap.` syncs issues from external trackers into its columns. The provider layer
is **descriptor-driven**: every tracker is one `ProviderDescriptor` in
[`src/integrations/ProviderRegistry.cpp`](../src/integrations/ProviderRegistry.cpp),
executed by the generic `RestIssueProvider`. Adding a REST tracker is a registry
entry — no networking or UI code. Jira and Trello are the two bespoke exceptions.

Access tokens live in the **OS keychain** (QtKeychain), never in `state.json`.
See [`docs/DATA.md`](DATA.md) for what does get persisted.

## Connecting a tracker (users)

Open **Settings → Integrations**. Each card is collapsed; click it to expand.
There are three ways to authenticate, depending on the provider:

| Method | Providers | What you do |
|--------|-----------|-------------|
| **One-click browser** | GitHub, GitLab* | Click **Connect with browser**, authorize, done. No fields. |
| **Personal access token** | all | Open **Advanced**, paste a token. Fallback everywhere. |
| **Device code** | GitHub | The card shows a short code — enter it on the page that opens. |

\* GitLab/Gitea/Forgejo one-click only lights up once a client ID is registered
(see below); until then use a token under **Advanced**.

Once connected, **Sync now** pulls issues; **Test connection** validates the
credentials. If you leave the repo/project field blank, GitHub and GitLab pull
the issues **assigned to you** across all repos — no repo to configure.

## Enabling one-click OAuth (maintainers)

One-click needs an **OAuth app registered with the provider**. Where those
credentials come from depends on what the provider accepts.

A `client_id` is **public by design** (it ships in every binary — the GitHub CLI
does the same), so the ones for public clients are committed in
[`OAuthClients.h`](../src/integrations/OAuthClients.h). A **client secret is
not**, and is never committed. But several providers (Atlassian, Todoist,
ClickUp, Bitbucket, Sentry) refuse a public client and will not do PKCE-only, so
for those the choice is "ship a secret" or "no browser sign-in at all". Release
builds take them from CI:

```bash
HEAP_OAUTH_JIRA_CLIENT_ID=… HEAP_OAUTH_JIRA_CLIENT_SECRET=… cmake -S . -B build
```

CMake reads `HEAP_OAUTH_*` from the **environment** and generates
`build/generated/OAuthClients.gen.h`. Deliberately not a `-D`: CI uploads the
whole `build/` tree as an artifact, and a cache variable would leak through
`CMakeCache.txt` and `compile_commands.json`. The configure log prints provider
names only, never values. `release.yml` passes them from repository secrets of
the same name.

Locally, an untracked `oauth-clients.local.cmake` at the repo root works too:

```cmake
set(HEAP_OAUTH_JIRA_CLIENT_ID "…")
set(HEAP_OAUTH_JIRA_CLIENT_SECRET "…")
```

This is **not real secrecy** — `strings heap.exe` finds an embedded secret, the
same as for any desktop OAuth client. It means an attacker has to extract it
rather than read it in the repo, and it lets the credential be rotated without a
commit.

**Nothing here is required.** An unset variable is an empty value: that
provider's browser button is hidden and the card falls back to a personal access
token. That is what a local build, a fork's CI and every test target get — see
"No browser button?" below.

The loopback redirect URI every OAuth app must register is
**`http://127.0.0.1:51789/`** (`OAuthManager::redirectUri()`; device flow ignores it).

### GitHub — done (Device Flow)

GitHub OAuth Apps can't do PKCE and would need a client secret for the web flow,
which is unsafe to embed. `heap.` uses the **Device Authorization Grant** instead
(client ID only, no secret). The app is registered:

- OAuth App **heap**, owner `sectapunterx` — <https://github.com/settings/applications/3713650>
- **Enable Device Flow** is checked; scope `repo`.

To recreate: <https://github.com/settings/applications/new> → name `heap`,
homepage `https://github.com/sectapunterx/heap`, callback `http://127.0.0.1:51789/`,
tick **Enable Device Flow** → Register → copy the **Client ID** into `kGithubClientId`.

### GitLab — done (PKCE, no secret)

Registered on gitlab.com as app **heap** (owner `sectapunterx`), Confidential=No,
scope `api`, callback `http://127.0.0.1:51789/`; the Application ID is baked into
`kGitlabClientId`. To recreate:

1. <https://gitlab.com/-/user_settings/applications>
2. **Redirect URI:** `http://127.0.0.1:51789/`
3. Uncheck **Confidential** (native/PKCE client).
4. **Scopes:** `api`
5. Save → copy the **Application ID** into `kGitlabClientId`.

Self-hosted GitLab: users register the same under their instance and paste the
Application ID under **Advanced** (the host field points the flow at their server).

### Gitea / Forgejo (per-instance)

These are self-hosted, so there is no single client ID to ship. Users create an
OAuth2 application under **Settings → Applications** on their instance
(redirect `http://127.0.0.1:51789/`) and paste the client ID under **Advanced**.

## No browser button?

The card offers **Connect with browser** only when this build can run the flow
with no help from you. It is hidden when any of these is true:

| Reason | What to do |
|--------|------------|
| You built heap yourself, and the provider needs a client secret | Register your own OAuth app and pass `HEAP_OAUTH_<PROVIDER>_CLIENT_ID/_SECRET` at configure time, or paste a client ID under **Advanced** |
| Self-hosted provider (Gitea, Forgejo, self-managed GitLab) | There is no single app to ship — register one on your instance and paste its client ID under **Advanced** |
| The provider has no OAuth at all (Redmine) | Use the API key; this is not going to change |
| GitHub on a build against Qt < 6.9 | The device grant needs Qt 6.9 (`OAuthManager::deviceFlowAvailable()`); use a token |

In every case the personal-access-token path under **Advanced** is fully
supported — it is not a degraded mode.

## How auth is applied

`RestIssueProvider::buildRequest` sends the token per the descriptor's `AuthRecipe`
(GitHub `token `, GitLab `PRIVATE-TOKEN`, …). An **OAuth** access token is always
sent as `Authorization: Bearer` regardless — the config carries `authMode=oauth`,
set when a browser sign-in succeeds. PAT and OAuth therefore coexist on one card.

## Token refresh

Short-lived OAuth tokens (GitLab ~2 h) are renewed automatically. Before a sync
or a status write-back, `AppController::ensureFreshToken` checks the stored
`tokenExpiresAt`; within a minute of expiry it spends the refresh token
(`OAuthRefresh.h`, a plain form POST that also works on Qt 6.4). A session with
no recorded expiry gets one refresh-and-retry on its first `401`. Providers
rotate the refresh token, so the new one is stored **before** the new access
token. If the grant is gone (revoked, or a rotated token was reused) the card
drops back to disconnected and asks you to sign in again. GitHub device-flow
tokens don't expire, so there is nothing to refresh.

## Where secrets live

The OS keychain, service `heap.integrations`, key `<provider>/<field>`
(`github/token`, `gitlab/refreshToken`). Values over ~2 KB (Windows Credential
Manager caps a blob at 2560 bytes) are split across `<key>#0`, `<key>#1`, … .
A run that must not touch your real data — `--data-dir` / `HEAP_DATA_DIR`, or
the test suites — never opens the keychain: it keeps a `secrets.json` next to its
own `state.json` instead. Builds without QtKeychain always use that file.

## Limitations (v1)

- **Push in self-scope.** When repo/project is blank (my-issues mode), status
  write-back is skipped — there's no single repo to write to.
