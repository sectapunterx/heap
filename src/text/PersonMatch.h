#pragma once

#include <QString>
#include <QStringView>

namespace heap::text {

// How well a typed query finds a person, for every box where someone is looked
// up by what the user types: the @-mention dropdowns, the people picker, the
// command palette. Higher is better; NoMatch means "not this person".
//
// A person is found the way a colleague's login would be written, derived
// from their name (no stored login field): for "Роман Лосев" or "Roman Losev"
//   r.losev  rlosev  r_losev  r-losev  losev.r  roman.losev  romanlosev  losev
// and the words themselves in any order and script: "roman losev",
// "losev roman", "роман лосев", "roman lo". Cyrillic and Latin are compared
// through one transliteration that also folds the usual spelling variants
// (й/y/i, х/kh/h, ц/ts/c, щ/sch/shch, ю/yu/iu, я/ya/ia, x/ks).
namespace PersonRank {
constexpr int NoMatch = 0;
constexpr int Substring = 20;     // somewhere inside the name ("ман")
constexpr int WordPrefix = 50;    // every query word starts a name word ("roman lo")
constexpr int HandlePrefix = 60;  // a login form being typed ("r.lo", "romanlos")
constexpr int IdPrefix = 70;      // the person's own id, being typed
constexpr int ExactHandle = 90;   // a whole login form ("r.losev", "roman losev")
constexpr int ExactId = 100;      // the person's own id
}  // namespace PersonRank

// The rank of `query` against a person with `name` and `id`. The query is
// matched case-insensitively; an empty query matches everyone at Substring
// rank, so callers keep their own order for it.
int personMatchRank(QStringView query, QStringView name, QStringView id);

}  // namespace heap::text
