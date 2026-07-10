#include <gtest/gtest.h>

#include "text/TaskTextUtils.h"

using heap::text::classifyKind;
using heap::text::extractMeta;
using heap::text::slugifyPersonName;
using heap::text::TaskKind;

// ─── classifyKind ────────────────────────────────────────────────────

TEST(Classify, EmptyIsNone) {
    EXPECT_EQ(classifyKind(QString()), TaskKind::None);
}

TEST(Classify, NoKeywordIsNone) {
    EXPECT_EQ(classifyKind(QStringLiteral("купить хлеб завтра в 18:00")),
              TaskKind::None);
}

TEST(Classify, FocusEnglish) {
    EXPECT_EQ(classifyKind(QStringLiteral("focus mode tomorrow 9am")),
              TaskKind::Focus);
}

TEST(Classify, FocusRussian) {
    EXPECT_EQ(classifyKind(QStringLiteral("фокус завтра 9:00")),
              TaskKind::Focus);
    EXPECT_EQ(classifyKind(QStringLiteral("фокус-режим")), TaskKind::Focus);
    EXPECT_EQ(classifyKind(QStringLiteral("deepwork session")),
              TaskKind::Focus);
}

TEST(Classify, SyncRussian) {
    EXPECT_EQ(classifyKind(QStringLiteral("синк с командой в 14:00")),
              TaskKind::Sync);
    EXPECT_EQ(classifyKind(QStringLiteral("созвон по PR")), TaskKind::Sync);
    EXPECT_EQ(classifyKind(QStringLiteral("митап завтра")), TaskKind::Sync);
}

TEST(Classify, SyncEnglish) {
    EXPECT_EQ(classifyKind(QStringLiteral("standup at 10")), TaskKind::Sync);
    EXPECT_EQ(classifyKind(QStringLiteral("Code Review")), TaskKind::Sync);
    EXPECT_EQ(classifyKind(QStringLiteral("1:1 with manager")), TaskKind::Sync);
}

TEST(Classify, TicketWinsOverSync) {
    // "задача" is the explicit "todo only" hint — beats "синк".
    EXPECT_EQ(classifyKind(QStringLiteral("задача: подготовить синк")),
              TaskKind::Ticket);
}

TEST(Classify, TicketWinsOverFocus) {
    EXPECT_EQ(classifyKind(QStringLiteral("задача фокус-режим")),
              TaskKind::Ticket);
}

TEST(Classify, FocusBeatsSyncWhenBothPresent) {
    // Order rule: focus > sync (after ticket).
    EXPECT_EQ(classifyKind(QStringLiteral("focus, потом созвон")),
              TaskKind::Focus);
}

TEST(Classify, WordBoundaryDoesNotMatchSubstring) {
    // "focused" must not light up the "focus" path — strict word boundary.
    EXPECT_EQ(classifyKind(QStringLiteral("stay focused")), TaskKind::None);
    EXPECT_EQ(classifyKind(QStringLiteral("recall")), TaskKind::None);
}

TEST(Classify, CaseInsensitive) {
    EXPECT_EQ(classifyKind(QStringLiteral("СИНК завтра")), TaskKind::Sync);
    EXPECT_EQ(classifyKind(QStringLiteral("FOCUS")), TaskKind::Focus);
}

// ─── contact-ping branch ─────────────────────────────────────────────

TEST(Classify, ContactRequiresHandleAndVerb) {
    // Verb without a handle → Sync / None depending on other content.
    EXPECT_EQ(classifyKind(QStringLiteral("написать письмо")), TaskKind::None);
    // Handle without a contact verb → not Contact (Sync wins if "созвон").
    EXPECT_EQ(classifyKind(QStringLiteral("просто заметка @viktor")),
              TaskKind::None);
    // Verb + handle → Contact.
    EXPECT_EQ(classifyKind(QStringLiteral("написать @viktor про релиз")),
              TaskKind::Contact);
}

TEST(Classify, ContactRussianVerbs) {
    EXPECT_EQ(classifyKind(QStringLiteral("напомни @andrey про PR")),
              TaskKind::Contact);
    EXPECT_EQ(classifyKind(QStringLiteral("пиши @oleg сегодня")),
              TaskKind::Contact);
}

TEST(Classify, ContactBeatsSync) {
    // Contact-ping is a stronger intent than a generic meeting word.
    EXPECT_EQ(classifyKind(QStringLiteral("напомни @viktor про созвон")),
              TaskKind::Contact);
}

TEST(Classify, ContactLosesToTicket) {
    // Explicit "задача" still wins so the user can opt out of pinging.
    EXPECT_EQ(classifyKind(QStringLiteral("задача: написать @viktor")),
              TaskKind::Ticket);
}

// ─── extractMeta ─────────────────────────────────────────────────────

TEST(ExtractMeta, NoMarkup) {
    const auto m = extractMeta(QStringLiteral("купить хлеб"));
    EXPECT_EQ(m.title, QString("купить хлеб"));
    EXPECT_TRUE(m.desc.isEmpty());
    EXPECT_TRUE(m.handles.isEmpty());
}

TEST(ExtractMeta, DoubleSlashSplitsDesc) {
    const auto m = extractMeta(QStringLiteral(
        "созвон по релизу // обсудить блокеры и even more"));
    EXPECT_EQ(m.title, QString("созвон по релизу"));
    EXPECT_EQ(m.desc,  QString("обсудить блокеры и even more"));
}

TEST(ExtractMeta, AtHandleCollectedButKeptInTitle) {
    // Handles are recorded but NOT stripped — the user keeps the context
    // they typed ("синк @andrey @alex.t" reads naturally on the card).
    const auto m = extractMeta(QStringLiteral("синк @andrey @alex.t"));
    EXPECT_EQ(m.title, QString("синк @andrey @alex.t"));
    ASSERT_EQ(m.handles.size(), 2);
    EXPECT_EQ(m.handles.at(0), QString("andrey"));
    EXPECT_EQ(m.handles.at(1), QString("alex.t"));
}

TEST(ExtractMeta, AtHandleMixedWithBody) {
    const auto m = extractMeta(
        QStringLiteral("митап с @viktor завтра в 11:00"));
    EXPECT_EQ(m.title, QString("митап с @viktor завтра в 11:00"));
    ASSERT_EQ(m.handles.size(), 1);
    EXPECT_EQ(m.handles.at(0), QString("viktor"));
}

TEST(ExtractMeta, CyrillicHandle) {
    const auto m = extractMeta(QStringLiteral("созвон @Андрей"));
    EXPECT_EQ(m.title, QString("созвон @Андрей"));
    ASSERT_EQ(m.handles.size(), 1);
    EXPECT_EQ(m.handles.at(0), QString("Андрей"));
}

TEST(ExtractMeta, EmailNotCapturedAsHandle) {
    // "x@y" inside an email has no leading whitespace → must NOT match.
    const auto m = extractMeta(QStringLiteral("contact me at a@b.com"));
    EXPECT_TRUE(m.handles.isEmpty());
}

TEST(ExtractMeta, MetaAndDescTogether) {
    const auto m = extractMeta(QStringLiteral(
        "созвон @viktor завтра в 14:00 // обсудить SIMD"));
    EXPECT_EQ(m.title, QString("созвон @viktor завтра в 14:00"));
    EXPECT_EQ(m.desc,  QString("обсудить SIMD"));
    ASSERT_EQ(m.handles.size(), 1);
    EXPECT_EQ(m.handles.at(0), QString("viktor"));
}

TEST(ExtractMeta, DoubleSlashNoSpaceBefore) {
    // "//" glued to the end of the body still splits off the comment.
    const auto m = extractMeta(QStringLiteral("синк понедельник 13 00//lol"));
    EXPECT_EQ(m.title, QString::fromUtf8("синк понедельник 13 00"));
    EXPECT_EQ(m.desc, QString("lol"));
}

TEST(ExtractMeta, DoubleSlashNoSpaceEitherSide) {
    // No space on either side of "//"; handle before it is still collected.
    const auto m = extractMeta(QStringLiteral("синк @el//lol"));
    EXPECT_EQ(m.title, QString::fromUtf8("синк @el"));
    EXPECT_EQ(m.desc, QString("lol"));
    ASSERT_EQ(m.handles.size(), 1);
    EXPECT_EQ(m.handles.at(0), QString("el"));
}

TEST(ExtractMeta, OnlyComment) {
    const auto m = extractMeta(QStringLiteral("// just a thought"));
    EXPECT_TRUE(m.title.isEmpty());
    EXPECT_EQ(m.desc, QString("just a thought"));
}

TEST(ExtractMeta, EmptyInput) {
    const auto m = extractMeta(QString());
    EXPECT_TRUE(m.title.isEmpty());
    EXPECT_TRUE(m.desc.isEmpty());
    EXPECT_TRUE(m.handles.isEmpty());
}

// ─── slugifyPersonName ────────────────────────────────────────────────

TEST(Slug, EmptyIsEmpty) {
    EXPECT_TRUE(slugifyPersonName(QString()).isEmpty());
    EXPECT_TRUE(slugifyPersonName(QStringLiteral("   ")).isEmpty());
}

TEST(Slug, CyrillicTwoTokens) {
    EXPECT_EQ(slugifyPersonName(QStringLiteral("Антон Иванов")),
              QString("a.ivanov"));
    EXPECT_EQ(slugifyPersonName(QStringLiteral("Олег Зайцев")),
              QString("o.zaicev"));
    EXPECT_EQ(slugifyPersonName(QStringLiteral("Екатерина Жукова")),
              QString("e.zhukova"));
}

TEST(Slug, LatinTwoTokens) {
    EXPECT_EQ(slugifyPersonName(QStringLiteral("Andrey Smirnov")),
              QString("a.smirnov"));
    EXPECT_EQ(slugifyPersonName(QStringLiteral("Hiroshi Matsui")),
              QString("h.matsui"));
}

TEST(Slug, SingleTokenKept) {
    EXPECT_EQ(slugifyPersonName(QStringLiteral("Hiroshi")),
              QString("hiroshi"));
    EXPECT_EQ(slugifyPersonName(QStringLiteral("Виктор")),
              QString("viktor"));
}

TEST(Slug, ThreeTokensUsesFirstAndLast) {
    EXPECT_EQ(slugifyPersonName(QStringLiteral("Иван Иванович Иванов")),
              QString("i.ivanov"));
}

TEST(Slug, StripsPunctuation) {
    // "Olga K." → "o.k"; period inside last token is dropped.
    EXPECT_EQ(slugifyPersonName(QStringLiteral("Olga K.")),
              QString("o.k"));
    // Surnames with hyphens collapse to letters only. "я" expands to "ya",
    // then "й"→"i", so "Кляйн" becomes "klyain".
    EXPECT_EQ(slugifyPersonName(QStringLiteral("Анна Лебедева-Кляйн")),
              QString("a.lebedevaklyain"));
}

TEST(Slug, MixedScripts) {
    EXPECT_EQ(slugifyPersonName(QStringLiteral("Виктор Smith")),
              QString("v.smith"));
    EXPECT_EQ(slugifyPersonName(QStringLiteral("John Зайцев")),
              QString("j.zaicev"));
}

TEST(Slug, AlreadyLowercase) {
    EXPECT_EQ(slugifyPersonName(QStringLiteral("alex zaharov")),
              QString("a.zaharov"));
}

// ─── classifyKind: Contact-vs-Focus precedence + EN verbs ─────────────

TEST(Classify, ContactBeatsFocus) {
    EXPECT_EQ(classifyKind(QStringLiteral("напомни @viktor фокус")),
              TaskKind::Contact);
    EXPECT_EQ(classifyKind(QStringLiteral("напомни @viktor про синк и фокус")),
              TaskKind::Contact);
}

TEST(Classify, ContactLosesToTicketWithFocus) {
    EXPECT_EQ(classifyKind(QStringLiteral("задача: напомни @viktor фокус")),
              TaskKind::Ticket);
}

TEST(Classify, HandleAtStartOfString) {
    // '@' at start-of-string uses the '^' boundary alternative.
    EXPECT_EQ(classifyKind(QStringLiteral("@viktor напиши срочно")),
              TaskKind::Contact);
}

TEST(Classify, EmailWithVerbIsNotContact) {
    // Verb present, but the only '@' is inside an e-mail (letter before '@')
    // → not a valid handle → not Contact.
    EXPECT_EQ(classifyKind(QStringLiteral("написать на a@b.com")),
              TaskKind::None);
}

// ─── extractMeta: first-'//' split, URL footgun, desc handles ─────────

TEST(ExtractMeta, SplitsOnFirstDoubleSlashOnly) {
    const auto m = extractMeta(QStringLiteral("a // b // c"));
    EXPECT_EQ(m.title, QString("a"));
    EXPECT_EQ(m.desc, QString("b // c"));
}

TEST(ExtractMeta, TrailingDoubleSlashEmptyDesc) {
    const auto m = extractMeta(QStringLiteral("title //"));
    EXPECT_EQ(m.title, QString("title"));
    EXPECT_TRUE(m.desc.isEmpty());
}

TEST(ExtractMeta, UrlDoubleSlashFootgun) {
    // Documented limitation (TaskTextUtils.h): a URL '//' still trips the
    // comment split. Pinned so an intentional future fix is a conscious change.
    const auto m = extractMeta(QStringLiteral("see https://example.com"));
    EXPECT_EQ(m.title, QString("see https:"));
    EXPECT_EQ(m.desc, QString("example.com"));
    EXPECT_TRUE(m.handles.isEmpty());
}

TEST(ExtractMeta, HandleInDescNotCollected) {
    // Handle collection runs on the pre-'//' body only.
    const auto m = extractMeta(QStringLiteral("review PR // ask @viktor"));
    EXPECT_TRUE(m.handles.isEmpty());
    EXPECT_EQ(m.desc, QString("ask @viktor"));
}

TEST(ExtractMeta, MultiHandleCommaSemicolonParen) {
    const auto a = extractMeta(QStringLiteral("sync @alice, @bob; @carol"));
    ASSERT_EQ(a.handles.size(), 3);
    EXPECT_EQ(a.handles.at(0), QString("alice"));
    EXPECT_EQ(a.handles.at(1), QString("bob"));
    EXPECT_EQ(a.handles.at(2), QString("carol"));

    const auto b = extractMeta(QStringLiteral("call (@dave)"));
    ASSERT_EQ(b.handles.size(), 1);
    EXPECT_EQ(b.handles.at(0), QString("dave"));
}

// ─── slugifyPersonName: digraph initial, empty-transliteration fallback ─

TEST(Slug, DigraphFirstInitialTakesLeadingChar) {
    // A first name whose Cyrillic initial transliterates to a digraph keeps
    // only the leading char of that digraph.
    EXPECT_EQ(slugifyPersonName(QStringLiteral("Женя Иванов")), QString("z.ivanov"));
    EXPECT_EQ(slugifyPersonName(QStringLiteral("Юрий Петров")), QString("y.petrov"));
    EXPECT_EQ(slugifyPersonName(QStringLiteral("Яна Смирнова")), QString("y.smirnova"));
}

TEST(Slug, EmptyTransliterationFallbacks) {
    // First token → empty: bare last name, no initial/dot.
    EXPECT_EQ(slugifyPersonName(QStringLiteral("- Ivanov")), QString("ivanov"));
    // Last token → empty: full first token, not just its initial.
    EXPECT_EQ(slugifyPersonName(QStringLiteral("Ivan .")), QString("ivan"));
    // Both empty → empty.
    EXPECT_TRUE(slugifyPersonName(QStringLiteral("- .")).isEmpty());
    // Single soft-sign token transliterates to empty.
    EXPECT_TRUE(slugifyPersonName(QStringLiteral("ь")).isEmpty());
}
