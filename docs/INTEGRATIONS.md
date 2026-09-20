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
| **One-click browser** | GitHub, GitLab, Jira, Trello, Todoist, Asana, ClickUp, Sentry, Bitbucket* | Click **Connect with browser**, authorize, done. |
| **Personal access token** | all | Open **Advanced**, paste a token. Fallback everywhere. |
| **Device code** | GitHub | The card shows a short code — enter it on the page that opens. |

\* Only in a build that carries the OAuth app credentials, and Gitea/Forgejo/
self-hosted GitLab only once you register a client ID on your instance. If the
button is missing, see "No browser button?" below — the token path always works.

Signing in tells the tracker who you are, not what to sync. Asana, ClickUp,
Sentry and Bitbucket also need a scope — a workspace, list, org/project or repo;
the card names what is missing and opens **Advanced** at it. GitHub, GitLab and
Jira need nothing: leave the repo/project/JQL blank and they pull the issues
**assigned to you**, and Jira picks your Atlassian site by itself.

Once connected, **Sync now** pulls issues and **Test connection** validates the
credentials.

## Enabling one-click OAuth (maintainers)

> Step-by-step registration for every provider — where to click, which scopes,
> which loopback literal — lives in **[OAUTH-SETUP.md](OAUTH-SETUP.md)**. This
> section is the mechanism behind it.

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
tick **Enable Device Flow** → Register → copy the **Client ID** into
`HEAP_OAUTH_GITHUB_CLIENT_ID` in `OAuthClients.h`.

### GitLab — done (PKCE, no secret)

Registered on gitlab.com as app **heap** (owner `sectapunterx`), Confidential=No,
scope `api`, callback `http://127.0.0.1:51789/`; the Application ID is committed
as `HEAP_OAUTH_GITLAB_CLIENT_ID`. To recreate:

1. <https://gitlab.com/-/user_settings/applications>
2. **Redirect URI:** `http://127.0.0.1:51789/`
3. Uncheck **Confidential** (native/PKCE client).
4. **Scopes:** `api`
5. Save → copy the **Application ID** into `HEAP_OAUTH_GITLAB_CLIENT_ID`.

Self-hosted GitLab: users register the same under their instance and paste the
Application ID under **Advanced** (the host field points the flow at their server).

### Gitea / Forgejo (per-instance)

These are self-hosted, so there is no single client ID to ship. Users create an
OAuth2 application under **Settings → Applications** on their instance
(redirect `http://127.0.0.1:51789/`) and paste the client ID under **Advanced**.

### The confidential five

Todoist, Asana, ClickUp, Sentry and Bitbucket all refuse a public client, so each
needs both halves in `HEAP_OAUTH_<PROVIDER>_CLIENT_ID` / `_CLIENT_SECRET`.
Register at:

| Provider | Where | Notes |
|---|---|---|
| Todoist | <https://developer.todoist.com/appconsole.html> | Scope `data:read`; the token never expires |
| Asana | <https://app.asana.com/0/my-apps> | PKCE *and* a secret; 1h token + refresh |
| ClickUp | Workspace **Settings → Apps** | Scopes are picked on ClickUp's consent screen, not in the URL; token exchange is JSON |
| Sentry | **Settings → Developer Settings → New Public Integration** | Scopes `org:read project:read event:read` |
| Bitbucket | Workspace **Settings → OAuth consumers** | Client credentials go in an HTTP Basic header; tick the `issue` permission; 2h token + refresh |

### Jira — Atlassian 3LO

<https://developer.atlassian.com/console/myapps/> → **Create → OAuth 2.0
integration**, add the **Jira API** permission with scopes
`read:jira-work write:jira-work read:jira-user offline_access`, and set the
callback to `http://127.0.0.1:51789/`.

Two Atlassian-specific details the flow handles:

- The authorize URL carries `audience=api.atlassian.com` and `prompt=consent`.
  Without `prompt=consent` Atlassian issues no refresh token, and the session
  would die an hour later.
- **A 3LO token is not bound to a site.** It is only accepted at
  `https://api.atlassian.com/ex/jira/{cloudId}`, never at `acme.atlassian.net`.
  After sign-in heap calls `/oauth/token/accessible-resources`, picks the site
  (keeping the one the card already names, so a second site can't silently
  repoint synced issues) and caches `cloudId` + `siteUrl` in the card's config.

Atlassian has no PKCE-only mode, so this needs a client secret. Browser sign-in
is **Cloud only**; Server/DC uses a Personal Access Token (below).

### Jira Server / Data Center

A different product behind the same name, and heap detects which one it is
rather than asking: it reads `deploymentType` from `{site}/rest/api/2/serverInfo`
on the first request, falling back to the URL (`*.atlassian.net` is Cloud,
anything else self-hosted is Server/DC) when the instance refuses anonymous
reads.

| | Cloud | Server / Data Center |
|---|---|---|
| API | `/rest/api/3` | `/rest/api/2` |
| Credential | account email **+** API token, sent as HTTP Basic | Personal Access Token, sent as `Bearer` |
| Search | `POST /search/jql` | `POST /search` |
| Description | ADF, flattened to text | already plain text |
| Browser sign-in | yes (3LO) | no |

On Server/DC, **leave the Email field empty** and paste a Personal Access Token
from **your avatar → Profile → Personal Access Tokens**. An instance too old for
PATs still works: fill in your username and it falls back to HTTP Basic.

### Trello — token in the fragment

<https://trello.com/power-ups/admin> → your Power-Up → **API key**. Trello has
no authorization-code grant at all: `/1/authorize` returns the token in the URL
**fragment**, which a browser never puts on the wire. The loopback listener
serves a page whose script posts the token back and then scrubs the address bar.

No secret is involved — the app key is public, it appears in every authorize
URL — but the key's **allowed origins must include `http://127.0.0.1:51789`**
or Trello refuses the redirect. Only `HEAP_OAUTH_TRELLO_CLIENT_ID` is needed.

### Redmine — no OAuth

Redmine ships no OAuth 2.0 provider at all. The REST API only takes an API key
(**My account → API access key**), sent as `X-Redmine-API-Key`. This is not a
gap in heap and will not change until Redmine itself changes.

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

## Mattermost — people, not issues

The one integration that imports **contacts** instead of tasks. Its descriptor
is a `Directory` kind: no issues to pull, no status to map to a column, nothing
to push back.

**Signing in.** Most corporate servers switch personal access tokens off and
leave the OAuth provider disabled (both are System Console settings), so the
primary path is the same credentials you use in the Mattermost app. The password
is sent once to `POST /api/v4/users/login` and never stored — only the session
token it returns, which lives in the keychain like any other. heap refuses to
send it at all unless the server URL is `https` (or loopback). A personal access
token works too, where your admin allows them.

**What is imported.** Everyone you have a direct-message conversation with, plus
the members of your group DMs, plus the members of any channels you name in
**Also import members of**. Ordinary channels are opt-in on purpose: one
company-wide channel would otherwise import the entire company. Bots,
deactivated accounts and you are skipped, and a channel is read at most 1000
members deep.

**Where they land.** Docs → Contacts, with the person's name, job title (or the
role their permissions imply), handle and where you met them. People you have
DM'd also get an entry in the People rail with the state `idle` — so
`@their.handle` autocompletes, and the rail's pending badge keeps meaning
"people you owe an answer to".

**Your edits win.** Each imported contact remembers what the server last said.
A field still matching that follows the server; a field you changed is yours and
stays. Deleting an imported contact is remembered, so the next sync does not
bring it back — undo reverses that too. Nothing is ever deleted by a sync: a
colleague who leaves simply stops being updated.

**One workspace.** The card binds to the profile it was first synced in, so a
background sync cannot pour your colleagues into an unrelated workspace. A
manual **Sync now** rebinds it to wherever you are.

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

## What a pulled issue brings with it

A mirrored issue becomes an ordinary task carrying the tracker's own view of
it: assignee, reporter, issue type, project, milestone, comment count, due
date, label colours, and the created/updated timestamps. The card shows a
provider badge and the tracker's key (`#1234`, `PROJ-123`); `O` opens the
issue in your browser; the editor lists the rest in a read-only strip.

Not every provider exposes every field, and two are skipped on purpose:
Jira's comment count (asking for it inlines every comment body of all 100
issues in the search response) and Redmine's (it needs a per-issue request).
Asana's tags are not requested either — `tags:read` is not among the scopes
the card asks for, and an unscoped field fails the whole request.

The tracker owns a task's due date only while you have not touched it. Edit
or snooze the deadline and it becomes yours: later syncs leave it alone, and
a due date removed upstream no longer clears it.

## Limitations (v1)

- **Push in self-scope.** When repo/project is blank (my-issues mode), status
  write-back is skipped — there's no single repo to write to. The same applies
  to an individual issue that *arrived* through my-issues mode while a repo is
  now configured: it belongs to some other repo, so moving its card would
  otherwise close whichever issue shares its number in the configured one.
