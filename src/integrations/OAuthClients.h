#pragma once

// OAuth app credentials baked into a release build.
//
// One-click "Connect with browser" needs an OAuth app registered with each
// provider. A `client_id` is public by design and is committed here. A
// `client_secret` is not — but several providers (Atlassian, Todoist, ClickUp,
// Bitbucket, Sentry) refuse a public client and will not do PKCE-only, so the
// alternative to shipping one is no browser sign-in at all for those. Release
// builds therefore take the secrets from CI: CMake reads HEAP_OAUTH_*_CLIENT_ID
// and HEAP_OAUTH_*_CLIENT_SECRET from the environment and generates
// OAuthClients.gen.h into the build tree.
//
// This is not real secrecy — `strings heap.exe` finds them, the same as for
// GitHub Desktop or the gh CLI. It only means an attacker has to extract the
// value rather than read it here, and it lets the secret be rotated without a
// commit. The credentials are never passed on a command line, so they stay out
// of CMakeCache.txt, compile_commands.json and the CI build artifact.
//
// Nothing here is required: an empty value simply hides the browser button for
// that provider and the card falls back to a personal access token. That is
// what a local build, a fork's CI and every test target get.

#if __has_include("OAuthClients.gen.h")
#include "OAuthClients.gen.h"
#endif

// Public client IDs, committed. Overridable through the generated header so a
// fork can point at its own OAuth apps.
#ifndef HEAP_OAUTH_GITHUB_CLIENT_ID
// GitHub OAuth App "heap" (owner: sectapunterx), Device Flow enabled. The
// client ID is public by design for device flow — safe to ship, no secret.
#define HEAP_OAUTH_GITHUB_CLIENT_ID "Ov23ctU4qrY60Ac7lRy9"
#endif
#ifndef HEAP_OAUTH_GITLAB_CLIENT_ID
// GitLab.com OAuth app "heap" (owner: sectapunterx), Confidential=No → PKCE,
// no secret. The Application ID is public by design for PKCE clients.
#define HEAP_OAUTH_GITLAB_CLIENT_ID "70b8f336ebd850a26e629b82e1388fac9464886befaf85674b402c200fbb9c74"
#endif

// Everything below is supplied by CI, empty otherwise.
#ifndef HEAP_OAUTH_GITHUB_CLIENT_SECRET
#define HEAP_OAUTH_GITHUB_CLIENT_SECRET ""
#endif
#ifndef HEAP_OAUTH_GITLAB_CLIENT_SECRET
#define HEAP_OAUTH_GITLAB_CLIENT_SECRET ""
#endif
#ifndef HEAP_OAUTH_JIRA_CLIENT_ID
#define HEAP_OAUTH_JIRA_CLIENT_ID ""
#endif
#ifndef HEAP_OAUTH_JIRA_CLIENT_SECRET
#define HEAP_OAUTH_JIRA_CLIENT_SECRET ""
#endif
#ifndef HEAP_OAUTH_TRELLO_CLIENT_ID
#define HEAP_OAUTH_TRELLO_CLIENT_ID ""
#endif
#ifndef HEAP_OAUTH_TODOIST_CLIENT_ID
#define HEAP_OAUTH_TODOIST_CLIENT_ID ""
#endif
#ifndef HEAP_OAUTH_TODOIST_CLIENT_SECRET
#define HEAP_OAUTH_TODOIST_CLIENT_SECRET ""
#endif
#ifndef HEAP_OAUTH_ASANA_CLIENT_ID
#define HEAP_OAUTH_ASANA_CLIENT_ID ""
#endif
#ifndef HEAP_OAUTH_ASANA_CLIENT_SECRET
#define HEAP_OAUTH_ASANA_CLIENT_SECRET ""
#endif
#ifndef HEAP_OAUTH_CLICKUP_CLIENT_ID
#define HEAP_OAUTH_CLICKUP_CLIENT_ID ""
#endif
#ifndef HEAP_OAUTH_CLICKUP_CLIENT_SECRET
#define HEAP_OAUTH_CLICKUP_CLIENT_SECRET ""
#endif
#ifndef HEAP_OAUTH_BITBUCKET_CLIENT_ID
#define HEAP_OAUTH_BITBUCKET_CLIENT_ID ""
#endif
#ifndef HEAP_OAUTH_BITBUCKET_CLIENT_SECRET
#define HEAP_OAUTH_BITBUCKET_CLIENT_SECRET ""
#endif
#ifndef HEAP_OAUTH_SENTRY_CLIENT_ID
#define HEAP_OAUTH_SENTRY_CLIENT_ID ""
#endif
#ifndef HEAP_OAUTH_SENTRY_CLIENT_SECRET
#define HEAP_OAUTH_SENTRY_CLIENT_SECRET ""
#endif
