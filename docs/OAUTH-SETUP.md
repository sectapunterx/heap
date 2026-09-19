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

---

## 1. Register the apps

Nothing below needs a paid plan. Where a step says "workspace admin", that is a
restriction the provider imposes, not heap.

### Jira Cloud — `HEAP_OAUTH_JIRA_CLIENT_ID` + `_CLIENT_SECRET`

1. <https://developer.atlassian.com/console/myapps/> → **Create → OAuth 2.0 integration**, name it `heap`.
2. **Permissions → Jira API → Add**, then **Configure** and enable:
   `read:jira-work`, `write:jira-work`, `read:jira-user`.
3. **Authorization → OAuth 2.0 (3LO) → Configure** → Callback URL:
   `http://127.0.0.1:51789/` → Save.
   The console greys out Save for plain `http` on a normal host; loopback is the
   documented exception. Use the **IP literal** — Atlassian's allowlist is known
   to reject `localhost`.
4. **Settings** → copy the Client ID and Secret.

`offline_access` is requested by heap automatically; without it Atlassian issues
no refresh token and the session would die after an hour. Jira **Server/Data
Center** does not use this at all — it takes a Personal Access Token and needs
no registration.

### Trello — `HEAP_OAUTH_TRELLO_CLIENT_ID` only (no secret)

1. <https://trello.com/apps/admin> → **New**. When asked, choose that the app
   **does not** use Power-Up capabilities — a REST integration needs no Power-Up.
2. Open the **Trello Auth** (API Key) tab → **Generate a new API Key**.
3. In **Allowed Origins**, add both:
   `http://127.0.0.1:51789` and `http://localhost:51789`
   (origins, so no trailing slash). **If Allowed Origins is empty, no redirect
   works at all** — this is the single most common Trello mistake.
4. Copy the API Key. That is the client id; there is no secret to store.

Trello is not OAuth 2.0 and returns the token in the URL *fragment*, which a
server never receives. heap serves a small page that posts it back — that is
expected, not a bug.

### Todoist — `HEAP_OAUTH_TODOIST_CLIENT_ID` + `_CLIENT_SECRET`

1. <https://app.todoist.com/app/settings/integrations/app-management> → **Add new integration**.
2. OAuth redirect URL: `http://localhost:51789/` — **`localhost`, not the IP**.
   Todoist's docs say "must be HTTPS (localhost is allowed for testing)"; the IP
   literal is not mentioned. It accepts up to 10 entries, so add
   `http://127.0.0.1:51789/` as a second one too.
3. Copy the Client ID and Client Secret.

heap requests the `data:read` scope — read-only, since Todoist sync is pull-only.

### Asana — `HEAP_OAUTH_ASANA_CLIENT_ID` + `_CLIENT_SECRET`

1. <https://app.asana.com/0/my-apps> → **Create new app**.
2. Redirect URL: `http://127.0.0.1:51789/` — **the trailing slash is mandatory**
   here. Add `http://localhost:51789/` as well if it lets you.
3. Under OAuth Permission Scopes enable: `tasks:read`, `projects:read`,
   `workspaces:read`, `users:read`.
4. Copy the Client ID and Secret.

> **Try this one first.** Asana's docs say non-native apps "must supply an https
> URL" and an Asana engineer has said plain-http loopback is "not supported right
> now" — yet Asana's own MCP setup page instructs users to register
> `http://127.0.0.1:33418/`. The contradiction is real and only a live attempt
> settles it. If registration is rejected, Asana browser sign-in is not possible
> as built and the card stays on a personal access token; nothing else breaks.

### ClickUp — `HEAP_OAUTH_CLICKUP_CLIENT_ID` + `_CLIENT_SECRET`

1. You must be the **Workspace owner or admin**: avatar → **Settings → Apps → Create new app**.
2. Redirect URL: `http://127.0.0.1:51789/`.
3. Copy the Client ID and Secret.

ClickUp has no scopes — the user picks which workspaces to share on the consent
screen. Its access token does not expire. Note ClickUp's own warning that
"non-SSL redirect URIs may not be supported in the future", so this one may need
revisiting.

### Sentry — `HEAP_OAUTH_SENTRY_CLIENT_ID` + `_CLIENT_SECRET`

1. **Settings → API → Applications → Create New Application.**
   This is the plain *OAuth Application*, **not** a Developer-Settings
   Integration — that other thing needs a publicly reachable webhook URL and is
   the wrong tool for a desktop app.
2. Authorized Redirect URIs: `http://127.0.0.1:51789/`.
3. Copy the Client ID and Secret.

heap requests `org:read project:read event:read`. Sentry's access token lives 30
days and comes with a refresh token.

### Bitbucket Cloud — `HEAP_OAUTH_BITBUCKET_CLIENT_ID` + `_CLIENT_SECRET`

1. Avatar → pick the workspace → **Settings → Workspace settings → OAuth consumers → Add consumer**.
2. Callback URL: `http://127.0.0.1:51789/`.
   Bitbucket implements the RFC 8252 loopback rule properly and matches the port
   dynamically, so plain `http://localhost` also works.
3. Tick the read permissions: **Account**, **Issues: Read**, **Repositories: Read**.
4. Copy the Key (client id) and Secret.

Scopes are fixed on the consumer, so heap sends none. The token lives two hours
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
