#pragma once

#include <QString>

// Russian for the text the integrations produce (audit INT-7).
//
// Two kinds of string end up in a toast: heap's own messages about a sync,
// looked up by key like the rest of AppController's table; and the reason a
// provider, the OAuth flow or the token endpoint gave, which arrives as an
// English sentence built deep inside a provider. The second kind is matched
// against the sentences heap itself writes and translated; anything else (a
// tracker's own error text, Qt's network messages) passes through unchanged,
// because a half-translated guess reads worse than the original.

namespace heap::integrations {

// Toast text for `key` in the UI language, or a null QString when the key is
// not one of the integration strings.
QString integrationText(const QString& key, bool ru);

// `reason` in Russian when `ru` and heap knows the sentence; otherwise as is.
QString translateProviderReason(const QString& reason, bool ru);

}  // namespace heap::integrations
