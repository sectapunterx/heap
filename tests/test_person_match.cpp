#include "text/PersonMatch.h"

#include <gtest/gtest.h>

using heap::text::personMatchRank;
namespace R = heap::text::PersonRank;

namespace {

const QString kRoman = QStringLiteral("Роман Лосев");
const QString kRomanId = QStringLiteral("r.losev");

int rank(const char* query, const QString& name, const QString& id = QString()) {
  return personMatchRank(QString::fromUtf8(query), name, id);
}

}  // namespace

// ─── login-style handles derived from the name ───────────────────────

TEST(PersonMatch, LoginFormsFindCyrillicName) {
  // The id is not the login here: whatever it is, the name's logins match.
  const QString id = QStringLiteral("p-17");
  for(const char* q : {"r.losev", "rlosev", "r_losev", "r-losev", "losev.r", "roman.losev", "romanlosev", "losev", "R.Losev"}) {
    EXPECT_EQ(rank(q, kRoman, id), R::ExactHandle) << q;
  }
}

TEST(PersonMatch, LoginFormsFindLatinName) {
  const QString name = QStringLiteral("Roman Losev");
  for(const char* q : {"r.losev", "rlosev", "losev_r", "roman-losev", "roman", "losev"}) {
    EXPECT_EQ(rank(q, name), R::ExactHandle) << q;
  }
}

TEST(PersonMatch, LoginBeingTypedIsAPrefix) {
  EXPECT_EQ(rank("r.lo", kRoman), R::HandlePrefix);
  EXPECT_EQ(rank("r", kRoman), R::HandlePrefix);
  EXPECT_EQ(rank("roman.lo", kRoman), R::HandlePrefix);
  EXPECT_EQ(rank("romanlos", kRoman), R::HandlePrefix);
  EXPECT_EQ(rank("лос", kRoman), R::HandlePrefix);
}

// ─── words, any order, either script ─────────────────────────────────

TEST(PersonMatch, WordsWithASpace) {
  EXPECT_EQ(rank("roman losev", kRoman), R::ExactHandle);
  EXPECT_EQ(rank("losev roman", kRoman), R::ExactHandle);
  EXPECT_EQ(rank("роман лосев", kRoman), R::ExactHandle);
  EXPECT_EQ(rank("Роман Лосев", QStringLiteral("Roman Losev")), R::ExactHandle);
  EXPECT_EQ(rank("roman lo", kRoman), R::HandlePrefix);
  EXPECT_EQ(rank("lo rom", kRoman), R::WordPrefix);
  EXPECT_EQ(rank("ro los", kRoman), R::WordPrefix);
}

TEST(PersonMatch, NoMatch) {
  EXPECT_EQ(rank("roman zavtra", kRoman), R::NoMatch);
  EXPECT_EQ(rank("ivanov", kRoman), R::NoMatch);
  EXPECT_EQ(rank("r.losev x", kRoman), R::NoMatch);
  EXPECT_EQ(rank("roman roman", kRoman), R::NoMatch);  // one word cannot serve twice
}

TEST(PersonMatch, TransliterationVariants) {
  // й/y/i, х/kh/h, ц/ts/c, ю/yu/iu, я/ya/ia, ё/е, щ/sch/shch, x/ks.
  EXPECT_EQ(rank("sergey", QStringLiteral("Сергей")), R::ExactHandle);
  EXPECT_EQ(rank("sergei", QStringLiteral("Сергей")), R::ExactHandle);
  EXPECT_EQ(rank("mikhail", QStringLiteral("Михаил")), R::ExactHandle);
  EXPECT_EQ(rank("mihail", QStringLiteral("Михаил")), R::ExactHandle);
  EXPECT_EQ(rank("tsoi", QStringLiteral("Виктор Цой")), R::ExactHandle);
  EXPECT_EQ(rank("v.coy", QStringLiteral("Виктор Цой")), R::ExactHandle);
  EXPECT_EQ(rank("yulia", QStringLiteral("Юлия")), R::ExactHandle);
  EXPECT_EQ(rank("iuliia", QStringLiteral("Юлия")), R::ExactHandle);
  EXPECT_EQ(rank("maria", QStringLiteral("Мария")), R::ExactHandle);
  EXPECT_EQ(rank("maryana", QStringLiteral("Марьяна")), R::ExactHandle);
  EXPECT_EQ(rank("fedorov", QStringLiteral("Пётр Фёдоров")), R::ExactHandle);
  EXPECT_EQ(rank("p.shchukin", QStringLiteral("Павел Щукин")), R::ExactHandle);
  EXPECT_EQ(rank("p.schukin", QStringLiteral("Павел Щукин")), R::ExactHandle);
  EXPECT_EQ(rank("alexey", QStringLiteral("Алексей")), R::ExactHandle);
  EXPECT_EQ(rank("yevgeny", QStringLiteral("Евгений")), R::ExactHandle);
  // ж is "zh" whole and "z" as an initial: the words still find her.
  EXPECT_EQ(rank("zh.ivanova", QStringLiteral("Жанна Иванова")), R::WordPrefix);
  EXPECT_EQ(rank("z.ivanova", QStringLiteral("Жанна Иванова")), R::ExactHandle);
  // And Latin typed into Cyrillic for a Latin name.
  EXPECT_EQ(rank("лосев", QStringLiteral("Roman Losev")), R::ExactHandle);
}

// ─── the person's own id ─────────────────────────────────────────────

TEST(PersonMatch, IdExactAndPrefix) {
  EXPECT_EQ(rank("olga.t", QStringLiteral("Ольга Т."), QStringLiteral("olga.t")), R::ExactId);
  EXPECT_EQ(rank("OLGA.T", QStringLiteral("Ольга Т."), QStringLiteral("olga.t")), R::ExactId);
  EXPECT_EQ(rank("olga.", QStringLiteral("Someone"), QStringLiteral("olga.t")), R::IdPrefix);
  // An imported handle unrelated to the name still finds its person.
  EXPECT_EQ(rank("xq", QStringLiteral("Роман Лосев"), QStringLiteral("xq-42")), R::IdPrefix);
  EXPECT_EQ(rank("xq_42", QStringLiteral("Роман Лосев"), QStringLiteral("xq-42")), R::ExactHandle);
}

// ─── names that worked before keep working ───────────────────────────

TEST(PersonMatch, OneWordName) {
  const QString name = QStringLiteral("Екатерина");
  EXPECT_EQ(rank("екатерина", name), R::ExactHandle);
  EXPECT_EQ(rank("ека", name), R::HandlePrefix);
  EXPECT_EQ(rank("eka", name), R::HandlePrefix);
  EXPECT_EQ(rank("катер", name), R::Substring);
  EXPECT_EQ(rank("ekaterina", name), R::ExactHandle);
}

TEST(PersonMatch, NameWithInitial) {
  const QString name = QStringLiteral("Олег Т.");
  EXPECT_EQ(rank("олег", name), R::ExactHandle);
  EXPECT_EQ(rank("o.t", name), R::ExactHandle);
  EXPECT_EQ(rank("oleg t", name), R::ExactHandle);
  EXPECT_EQ(rank("ол", name), R::HandlePrefix);
  // A lone initial is no login of its own.
  EXPECT_LT(rank("t", name), R::ExactHandle);
}

TEST(PersonMatch, SubstringAnywhere) {
  EXPECT_EQ(rank("named", QStringLiteral("AcatokpNamedPerson")), R::Substring);
  EXPECT_EQ(rank("ман", kRoman), R::Substring);
}

TEST(PersonMatch, ScriptWithoutTransliteration) {
  EXPECT_EQ(rank("李 小龙", QStringLiteral("李 小龙")), R::ExactHandle);
  EXPECT_EQ(rank("小", QStringLiteral("李 小龙")), R::HandlePrefix);
}

TEST(PersonMatch, EmptyQueryMatchesEveryone) {
  EXPECT_EQ(rank("", kRoman), R::Substring);
  EXPECT_EQ(rank("   ", kRoman), R::Substring);
}

// ─── ambiguity and ranking ───────────────────────────────────────────

TEST(PersonMatch, SameLoginFitsTwoPeople) {
  const QString ruslan = QStringLiteral("Руслан Лосев");
  EXPECT_EQ(rank("r.losev", kRoman), R::ExactHandle);
  EXPECT_EQ(rank("r.losev", ruslan), R::ExactHandle);
  EXPECT_EQ(rank("roman", kRoman), R::ExactHandle);
  EXPECT_EQ(rank("roman", ruslan), R::NoMatch);
  EXPECT_EQ(rank("roman.losev", ruslan), R::NoMatch);
  EXPECT_EQ(rank("ru", ruslan), R::HandlePrefix);
  EXPECT_EQ(rank("ru", kRoman), R::NoMatch);
}

TEST(PersonMatch, RankOrder) {
  // Exact id > exact login > id being typed > login being typed > word
  // prefixes > substring.
  EXPECT_GT(rank("r.losev", kRoman, kRomanId), rank("r.losev", kRoman, QStringLiteral("p-1")));
  EXPECT_GT(R::ExactHandle, R::IdPrefix);
  EXPECT_GT(rank("r.lo", kRoman, kRomanId), rank("r.lo", kRoman));
  EXPECT_GT(rank("r.lo", kRoman), rank("ro los", kRoman));
  EXPECT_GT(rank("ro los", kRoman), rank("ман", kRoman));
}
