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

One-click needs an **OAuth app registered with the provider**. The app's public
`client_id` is baked into the build; there is no way around registering it once.
Paste the IDs into the constants at the top of
[`ProviderRegistry.cpp`](../src/integrations/ProviderRegistry.cpp):

```cpp
constexpr const char* kGithubClientId = "Ov23ctU4qrY60Ac7lRy9";              // done (Device Flow)
constexpr const char* kGithubClientSecret = "";                              // Device Flow → none
constexpr const char* kGitlabClientId = "70b8f336…c200fbb9c74";              // done (gitlab.com, PKCE)
```

A `client_id` is **public by design** (it ships in every binary — GitHub CLI does
the same) and is safe to commit. A **client secret is not** — never commit one.
Empty constant → the card falls back to manual client-ID entry under Advanced.

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

## How auth is applied

`RestIssueProvider::buildRequest` sends the token per the descriptor's `AuthRecipe`
(GitHub `token `, GitLab `PRIVATE-TOKEN`, …). An **OAuth** access token is always
sent as `Authorization: Bearer` regardless — the config carries `authMode=oauth`,
set when a browser sign-in succeeds. PAT and OAuth therefore coexist on one card.

## Limitations (v1)

- **No token refresh.** Short-lived OAuth tokens (GitLab ~2 h) require signing in
  again; the refresh token is stored for a future auto-refresh. GitHub tokens
  from device flow don't expire.
- **Push in self-scope.** When repo/project is blank (my-issues mode), status
  write-back is skipped — there's no single repo to write to.
