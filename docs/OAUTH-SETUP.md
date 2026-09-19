# Enabling one-click browser sign-in

Everything in this file is **maintainer work you do once**. Until it is done,
every integration still works — the cards just show a token field instead of a
**Connect with browser** button. Nothing here is required to build or ship heap.

The short version:

1. Register an OAuth app with each provider, using the callback URL in the table below.
2. Put the resulting credentials into the repository's Actions secrets.
3. Tag a release. The build bakes them in; local builds stay without.

---

## 0. The one value everything depends on

heap listens on a fixed loopback port and expects the browser to be redirected
back to it:

```
http://127.0.0.1:51789/
```

Plain `http`, fixed port, trailing slash. This is the standard native-app
pattern (RFC 8252 §7.3) and the port is `OAuthManager::kRedirectPort`.

Two traps, both of which have cost people days:

- **`localhost` and `127.0.0.1` are not interchangeable.** They reach the same
  socket, but a redirect-URI *allowlist* is a string match. Todoist documents
  `localhost`; Atlassian wants the IP literal. heap advertises whichever the
  provider needs (`OAuthConfig::redirectHost`), and the table below says which.
  **Where a provider accepts several redirect URIs, register both forms** — it
  costs nothing and removes the guesswork.
- **The trailing slash matters** to several providers. Register it exactly as
  written.

Every step below was walked through against the live consoles on 2026-09-20.
Where a provider's own documentation disagrees with what the console actually
did, this file records what the console did.

---

## 1. Register the apps

Nothing below needs a paid plan. Where a step says "workspace admin", that is a
restriction the provider imposes, not heap.

### Jira Cloud — `HEAP_OAUTH_JIRA_CLIENT_ID` + `_CLIENT_SECRET`

1. <https://developer.atlassian.com/console/myapps/> → **Create → OAuth 2.0 integration**, name it `heap`.
   Pick **Access type: Resource-level** — the token is then scoped to the one
   site the user selects while authorizing, which is exactly what
   `pickJiraSite()` expects. Account-level would hand heap every site on the
   customer's account for no benefit. Tick the developer-terms box and Create.
2. **Permissions → Jira API → Add**, then **Configure → Edit Scopes** and enable
   the three classic scopes `read:jira-work`, `read:jira-user`,
   `write:jira-work`. The footer counts them: it must say *add 3 new scopes*.
   Ignore the console's nudge about granular scopes — heap uses the classic set.
3. **Authorization → OAuth 2.0 (3LO) → Add** → Callback URLs:
   `http://127.0.0.1:51789/` → Save changes.
   It is a textarea taking up to 30 URIs, one per line. Plain `http` on loopback
   **is accepted** — that is the documented RFC 8252 exception, and the console
   applies it. Use the IP literal; Atlassian's allowlist is known to reject
   `localhost`.
4. **Settings** → copy the Client ID and Secret.

After saving, the same page prints an **Authorization URL generator**. Use it as
a cross-check: it should read
`audience=api.atlassian.com`, the three scopes space-separated, the loopback
`redirect_uri`, and `prompt=consent` — which is what `ProviderRegistry.cpp`
builds. `offline_access` is absent there but heap adds it; without it Atlassian
issues no refresh token and the session would die after an hour.

**Rotating refresh tokens are now mandatory** for every newly created 3LO app:
each refresh returns a *new* refresh token and invalidates the old one, and
reuse is treated as a breach. heap handles this — it writes the rotated token
back before the access token, and keeps the stored one when a provider returns
none (see `ARefreshThatReturnsNoNewRefreshTokenKeepsTheOldOne`).

Jira **Server/Data Center** does not use any of this — it takes a Personal
Access Token and needs no registration.

### Trello — `HEAP_OAUTH_TRELLO_CLIENT_ID` only (no secret)

**Prerequisite that stops most people at step zero:** you must belong to a
Trello **Workspace**. Until you do, <https://trello.com/power-ups/admin> shows
only *"you are not a member of a Trello workspace"* and offers no way to create
anything. Create or join one first, then come back.

1. <https://trello.com/power-ups/admin> → **New**. Pick *"My app doesn't use
   Power-Up capabilities"* — a REST integration needs no Power-Up, and choosing
   it also drops the mandatory iframe-connector URL. Name it `heap` and pick
   your Workspace. **Email, Support contact and Author are all required**; the
   Create button stays disabled until they are filled.
2. In the app, **Authorization → Trello Auth → Generate a new Trello Auth API
   key for this app**. Confirm the dialog (it warns that generating replaces the
   key used for GDPR compliance and gives you 14 days to roll it over — harmless
   for a brand-new app).
3. In **Allowed origins**, add both, one at a time via **Add**:
   `http://127.0.0.1:51789` and `http://localhost:51789`
   (origins, so no trailing slash). **If Allowed origins is empty, no redirect
   works at all** — this is the single most common Trello mistake, and it
   presents as the browser simply doing nothing after you approve.
4. Copy the API Key. That is the client id; heap needs no secret. The page also
   shows a Secret for OAuth 1 — heap does not use it.

The path heap uses is not OAuth 2.0: it returns the token in the URL *fragment*,
which a server never receives, so heap serves a small page that posts it back —
expected, not a bug. Trello has since shipped a real OAuth 2.0 flow (the
**OAuth 2.0** entry in the developer sidebar). Moving to it would replace the
fragment dance with an ordinary authorization-code exchange, but it is a code
change in `ProviderRegistry.cpp`, not a registration choice; the API-key path
above is what the shipped build expects.

### Todoist — `HEAP_OAUTH_TODOIST_CLIENT_ID` + `_CLIENT_SECRET`

1. <https://app.todoist.com/app/settings/integrations/app-management> → **Add new integration**.
2. OAuth redirect URL: `http://localhost:51789/`. Todoist's docs say "must be
   HTTPS (localhost is allowed for testing)" and never mention the IP literal —
   but the console **accepted `http://127.0.0.1:51789/` as well**. Register
   both; `OAuthConfig::redirectHost` still pins Todoist to `localhost`, so that
   is the one that must be there.
3. Copy the Client ID and Client Secret.

heap requests the `data:read` scope — read-only, since Todoist sync is pull-only.

### Asana — `HEAP_OAUTH_ASANA_CLIENT_ID` + `_CLIENT_SECRET`

1. <https://app.asana.com/0/my-apps> → **Create new app** → open its **OAuth** tab.
2. Redirect URL: `http://127.0.0.1:51789/` — **the trailing slash is mandatory**
   here. Leave the *"this is a native or command-line app"* checkbox **off**:
   ticking it switches Asana to the `oob` out-of-band redirect, which is not
   what heap does.
3. **App type: API app.**
4. Under Permission scopes enable Read on: Projects, Tasks, Users, Workspaces
   (`projects:read`, `tasks:read`, `users:read`, `workspaces:read`), then Save.
   The scope list is long; flip **Show only selected scopes** on to check your
   four before and after saving — the toggle resets on reload, which makes a
   saved selection look lost when it is not.
5. Copy the Client ID and Secret.

> Asana's own docs say non-native apps "must supply an https URL", and Asana
> staff have called plain-http loopback unsupported. **That is not what the
> console does:** `http://127.0.0.1:51789/` was accepted outright, with the
> native-app checkbox off, and the scopes saved alongside it. The published
> pessimism is stale; treat Asana as an ordinary provider.

### ClickUp — `HEAP_OAUTH_CLICKUP_CLIENT_ID` + `_CLIENT_SECRET`

1. You must be the **Workspace owner or admin**, and a Workspace has to exist at
   all — a brand-new ClickUp account has none.
2. Avatar → **Settings → ClickUp API → the "ClickUp API Settings" tab → Create an App**.
   Not *Settings → Apps*: that page lists authorized apps and only links to the
   API docs, with no way to create anything. This trips people up because the
   older docs still say "Apps".
3. Redirect URL(s): one per line — `http://127.0.0.1:51789/` and, harmlessly,
   `http://localhost:51789/`. Both are accepted.
4. Copy the Client ID and Secret. The secret is hidden behind **Show** and has a
   **Regenerate** button, so losing it is recoverable.

ClickUp has no scopes — the user picks which workspaces to share on the consent
screen. Its access token does not expire. Note ClickUp's own warning that
"non-SSL redirect URIs may not be supported in the future", so this one may need
revisiting.

### Sentry — `HEAP_OAUTH_SENTRY_CLIENT_ID` + `_CLIENT_SECRET`

1. **Settings → Account → API → Applications → Create New Application.**
   This is the plain *OAuth Application*, **not** a Developer-Settings
   Integration — that other thing needs a publicly reachable webhook URL and is
   the wrong tool for a desktop app.
2. Sentry asks for a client type. Choose **Confidential**, which is what the
   shipped descriptor is built for (client secret, form-encoded token request,
   no PKCE). The **Public** option — PKCE, device authorization, rotating
   refresh tokens — is the better fit for a desktop app on paper, but heap would
   have to be changed to use it; see "What this is not" below.
3. **Copy the Client Secret immediately.** The page says it plainly: the secret
   is shown once, right after creation, and there is no reveal button afterwards
   — only deleting the application and starting over.
4. Sentry auto-fills a random two-word Name; replace it with `heap`. Authorized
   Redirect URIs: `http://127.0.0.1:51789/`. Both fields save on blur — a green
   *Changes applied* toast is the confirmation, there is no Save button.

heap requests `org:read project:read event:read`. Sentry's access token lives 30
days and comes with a refresh token. The Authorization and Token URLs printed on
that page (`https://sentry.io/oauth/authorize/`, `https://sentry.io/oauth/token/`)
should match `ProviderRegistry.cpp` exactly, trailing slashes included.

### Bitbucket Cloud — `HEAP_OAUTH_BITBUCKET_CLIENT_ID` + `_CLIENT_SECRET`

You need a Bitbucket **workspace**; a fresh account has none and the settings
page below simply will not exist.

1. <https://bitbucket.org/account/workspaces/> → **Manage** on your workspace →
   **Apps and features → OAuth clients → Create OAuth client**.
   It used to be called *OAuth consumers*; older docs and the URL
   `/workspace/settings/api` are both dead — the page is now
   `/workspace/settings/oauth-clients`.
2. **Details** tab: Name `heap`. The other fields (description, EULA, privacy
   URL) are optional.
3. **Authorization** tab: tick **Authorization code**. *Refresh token* then
   ticks itself and greys out, and a **Callback URL** field appears — fill in
   `http://127.0.0.1:51789/`. Leave *Client credentials* off.
   Bitbucket implements the RFC 8252 loopback rule properly and matches the port
   dynamically, so plain `http://localhost` also works.
4. **Scopes** tab: **Account → Read** (Email ticks itself),
   **Repositories → Read**, **Issues → Read**. Nothing else.
5. Save, then copy the Client ID and Secret from the confirmation dialog.

Scopes are fixed on the client, so heap sends none. The token lives two hours
and refreshes.

### GitHub and GitLab — already done

GitHub uses the device-code grant with a public client id, and GitLab.com uses
PKCE with a public application id. Both are committed in
[`OAuthClients.h`](../src/integrations/OAuthClients.h) and need no secret and no
action from you.

**Gitea, Forgejo and self-hosted GitLab** are per-instance: there is no app
anyone could ship for every server. Users register one on their own instance
(**Settings → Applications**, redirect `http://127.0.0.1:51789/`) and paste the
client ID under **Advanced** on the card.

**Redmine** has no OAuth at all — API key only, and that will not change.

**Mattermost** needs nothing here: it signs in with the same username and
password as the Mattermost app, or a personal access token.

---

## 2. Store the credentials

Repository **Settings → Secrets and variables → Actions → New repository secret**.
Name them exactly:

| Provider | Secrets |
|---|---|
| Jira Cloud | `HEAP_OAUTH_JIRA_CLIENT_ID`, `HEAP_OAUTH_JIRA_CLIENT_SECRET` |
| Trello | `HEAP_OAUTH_TRELLO_CLIENT_ID` |
| Todoist | `HEAP_OAUTH_TODOIST_CLIENT_ID`, `HEAP_OAUTH_TODOIST_CLIENT_SECRET` |
| Asana | `HEAP_OAUTH_ASANA_CLIENT_ID`, `HEAP_OAUTH_ASANA_CLIENT_SECRET` |
| ClickUp | `HEAP_OAUTH_CLICKUP_CLIENT_ID`, `HEAP_OAUTH_CLICKUP_CLIENT_SECRET` |
| Sentry | `HEAP_OAUTH_SENTRY_CLIENT_ID`, `HEAP_OAUTH_SENTRY_CLIENT_SECRET` |
| Bitbucket | `HEAP_OAUTH_BITBUCKET_CLIENT_ID`, `HEAP_OAUTH_BITBUCKET_CLIENT_SECRET` |

`release.yml` already passes every one of these to all three packaging jobs.
**Add them one provider at a time if you like** — an unset secret is simply an
empty value, which hides that one button and leaves the token path. There is no
all-or-nothing step.

Paste the value with **no trailing newline**. CMake strips CR/LF and escapes
quotes and backslashes before generating the header, so a stray one will not
break the build — but it would silently become part of the secret.

---

## 3. Verify

### Locally, before touching CI

```bash
HEAP_OAUTH_JIRA_CLIENT_ID=… HEAP_OAUTH_JIRA_CLIENT_SECRET=… cmake -S . -B build
```

The configure log prints provider **names only**, never values:

```
-- heap: OAuth app credentials baked in for: jira
```

Then build and open **Settings → Integrations**. The Jira card should show
**Connect with browser**. Click it: your browser opens, you approve, and the
card goes to connected. heap then asks Atlassian which site the token was
granted and caches its cloudId.

A maintainer who would rather not export variables can drop an untracked
`oauth-clients.local.cmake` at the repo root:

```cmake
set(HEAP_OAUTH_JIRA_CLIENT_ID "…")
set(HEAP_OAUTH_JIRA_CLIENT_SECRET "…")
```

It is already in `.gitignore`.

### What "working" looks like

- The card shows **Connect with browser** instead of only token fields.
- After approving, the card says connected and shows when the session expires.
- **Sync now** pulls issues. Asana, ClickUp, Sentry and Bitbucket will first ask
  for a workspace / list / org+project / repo — signing in says who you are, not
  what to sync, and the card names what is missing.

### When it does not work

| What you see | What it means |
|---|---|
| Button never appears | That provider's secret is unset in this build. Check the configure log line. |
| Provider rejects the redirect at registration | The allowlist wants the other loopback literal, or the trailing slash. Try both forms. |
| `redirect port 51789 is busy` | Another copy of heap — or another app — holds the port. Close it. |
| Times out after 3 minutes | The provider never redirected back. Almost always a redirect URI that does not match **exactly**. |
| Trello: nothing happens after approving | Allowed Origins on the API key is empty or lacks the loopback origin. |

---

## 4. What this is not

The secrets end up **inside the shipped binary**. `strings heap.exe` will find
them, exactly as it would for the GitHub CLI or any other desktop OAuth client.
There is no way around that for a native app without running a server, which
heap deliberately does not do.

What this scheme does buy:

- the values are not in the repository, so a fork and a casual reader never see them;
- they can be rotated without a commit;
- they never reach `CMakeCache.txt`, `compile_commands.json` or the CI log —
  CMake reads them from the environment and writes a generated header, and the
  log prints only provider names.

Treat them as *app identity*, not as a secret that protects user data. The
user's own token is what protects that, and it lives in their OS keychain.

Two providers have since grown a public-client option that would remove their
secret from the binary altogether: **Sentry** (Confidential vs Public — PKCE,
device authorization, rotating refresh tokens) and **Trello** (a real OAuth 2.0
flow beside the legacy API-key one, with its own Public client type). Both are
the better shape for a desktop app, and both are code changes in
`ProviderRegistry.cpp` rather than registration choices — the steps above match
what the shipped build actually sends. Worth revisiting; not worth blocking a
release on.
