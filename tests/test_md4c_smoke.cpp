// Vendored md4c — build and behaviour smoke test.
//
// This does not test CommonMark conformance; that is md4c's own test suite's
// job and the reason heap vendors a parser instead of writing one. What it
// pins down is that our copy is wired up correctly: it compiles and links as a
// static library on every platform CI builds, the GitHub-flavoured extensions
// heap depends on are actually enabled by the flags we pass, and the text
// callbacks hand back pointers into the caller's own buffer — which is the
// property the whole source-range design rests on.

#include "md4c.h"

#include <gtest/gtest.h>

#include <algorithm>
#include <string>
#include <vector>

namespace {

// Everything the callbacks record about one parse.
struct Capture {
  const char* base = nullptr;
  std::string text;                     // concatenated text, in document order
  std::vector<MD_BLOCKTYPE> blocks;     // block types, in open order
  std::vector<MD_SPANTYPE> spans;       // span types, in open order
  std::vector<unsigned> headingLevels;  // level of every heading opened
  int taskMarks = 0;                    // task list items seen
  char firstTaskMark = '\0';            // the character between '[' and ']'
};

int onEnterBlock(MD_BLOCKTYPE type, void* detail, void* userdata) {
  auto* cap = static_cast<Capture*>(userdata);
  cap->blocks.push_back(type);
  if(type == MD_BLOCK_H && detail != nullptr) {
    cap->headingLevels.push_back(static_cast<MD_BLOCK_H_DETAIL*>(detail)->level);
  }
  if(type == MD_BLOCK_LI && detail != nullptr) {
    auto* li = static_cast<MD_BLOCK_LI_DETAIL*>(detail);
    if(li->is_task != 0) {
      if(cap->taskMarks == 0) {
        cap->firstTaskMark = cap->base[li->task_mark_offset];
      }
      ++cap->taskMarks;
    }
  }
  return 0;
}

int onLeaveBlock(MD_BLOCKTYPE, void*, void*) {
  return 0;
}

int onEnterSpan(MD_SPANTYPE type, void*, void* userdata) {
  static_cast<Capture*>(userdata)->spans.push_back(type);
  return 0;
}

int onLeaveSpan(MD_SPANTYPE, void*, void*) {
  return 0;
}

int onText(MD_TEXTTYPE type, const MD_CHAR* text, MD_SIZE size, void* userdata) {
  auto* cap = static_cast<Capture*>(userdata);
  if(type == MD_TEXT_NORMAL || type == MD_TEXT_CODE) {
    cap->text.append(text, size);
  }
  return 0;
}

// The extension set heap's notes editor parses with. Underline is deliberately
// absent: it would take '_' away from ordinary emphasis.
constexpr unsigned kHeapFlags =
    MD_FLAG_TABLES | MD_FLAG_STRIKETHROUGH | MD_FLAG_TASKLISTS | MD_FLAG_PERMISSIVEAUTOLINKS | MD_FLAG_LATEXMATHSPANS | MD_FLAG_WIKILINKS;

Capture parse(const std::string& markdown, unsigned flags = kHeapFlags) {
  Capture cap;
  cap.base = markdown.data();
  MD_PARSER parser{};
  parser.abi_version = 0;
  parser.flags = flags;
  parser.enter_block = onEnterBlock;
  parser.leave_block = onLeaveBlock;
  parser.enter_span = onEnterSpan;
  parser.leave_span = onLeaveSpan;
  parser.text = onText;
  parser.debug_log = nullptr;
  parser.syntax = nullptr;

  const int rc = md_parse(markdown.data(), static_cast<MD_SIZE>(markdown.size()), &parser, &cap);
  EXPECT_EQ(rc, 0);
  return cap;
}

bool hasBlock(const Capture& cap, MD_BLOCKTYPE type) {
  return std::find(cap.blocks.begin(), cap.blocks.end(), type) != cap.blocks.end();
}

bool hasSpan(const Capture& cap, MD_SPANTYPE type) {
  return std::find(cap.spans.begin(), cap.spans.end(), type) != cap.spans.end();
}

}  // namespace

TEST(Md4cSmokeTest, ParsesCoreBlocks) {
  const Capture cap = parse("# Title\n\nA paragraph.\n\n> quoted\n\n- one\n- two\n\n```cpp\nint x;\n```\n");

  EXPECT_TRUE(hasBlock(cap, MD_BLOCK_H));
  EXPECT_TRUE(hasBlock(cap, MD_BLOCK_P));
  EXPECT_TRUE(hasBlock(cap, MD_BLOCK_QUOTE));
  EXPECT_TRUE(hasBlock(cap, MD_BLOCK_UL));
  EXPECT_TRUE(hasBlock(cap, MD_BLOCK_CODE));
  ASSERT_FALSE(cap.headingLevels.empty());
  EXPECT_EQ(cap.headingLevels.front(), 1u);
}

TEST(Md4cSmokeTest, HeadingLevelsAreDistinct) {
  const Capture cap = parse("# one\n\n### three\n\n###### six\n");
  ASSERT_EQ(cap.headingLevels.size(), 3u);
  EXPECT_EQ(cap.headingLevels[0], 1u);
  EXPECT_EQ(cap.headingLevels[1], 3u);
  EXPECT_EQ(cap.headingLevels[2], 6u);
}

TEST(Md4cSmokeTest, GithubExtensionsAreEnabled) {
  // Tables, strikethrough and bare-URL autolinking all come from flags rather
  // than from plain CommonMark, so this asserts our flag set, not the parser.
  const Capture tables = parse("| a | b |\n|---|---|\n| 1 | 2 |\n");
  EXPECT_TRUE(hasBlock(tables, MD_BLOCK_TABLE));
  EXPECT_TRUE(hasBlock(tables, MD_BLOCK_TH));
  EXPECT_TRUE(hasBlock(tables, MD_BLOCK_TD));

  EXPECT_TRUE(hasSpan(parse("~~gone~~\n"), MD_SPAN_DEL));
  EXPECT_TRUE(hasSpan(parse("see https://example.com now\n"), MD_SPAN_A));
  EXPECT_TRUE(hasSpan(parse("[[Some heading]]\n"), MD_SPAN_WIKILINK));
  EXPECT_TRUE(hasSpan(parse("inline $x^2$ math\n"), MD_SPAN_LATEXMATH));
  EXPECT_TRUE(hasSpan(parse("$$\nx^2\n$$\n"), MD_SPAN_LATEXMATH_DISPLAY));
}

TEST(Md4cSmokeTest, TaskListsReportTheirMarkOffset) {
  // The offset of the character inside the brackets is what lets a checkbox
  // click rewrite exactly one character of the source.
  const std::string src = "- [ ] todo\n- [x] done\n";
  const Capture cap = parse(src);
  EXPECT_EQ(cap.taskMarks, 2);
  EXPECT_EQ(cap.firstTaskMark, ' ');

  const Capture done = parse("- [x] done\n");
  EXPECT_EQ(done.taskMarks, 1);
  EXPECT_EQ(done.firstTaskMark, 'x');
}

TEST(Md4cSmokeTest, UnderlineStaysOffSoEmphasisKeepsUnderscore) {
  // With MD_FLAG_UNDERLINE the same input would produce MD_SPAN_U instead.
  const Capture cap = parse("_emphasis_\n");
  EXPECT_TRUE(hasSpan(cap, MD_SPAN_EM));
  EXPECT_FALSE(hasSpan(cap, MD_SPAN_U));
}

TEST(Md4cSmokeTest, NormalTextPointsIntoTheCallersBuffer) {
  // The source-range design derives offsets as (pointer - base) and relies on
  // being able to tell a real slice from a synthesized chunk by whether the
  // pointer lies inside the input. Pin that property down here.
  const std::string src = "plain words only\n";

  struct Bounds {
    const char* base = nullptr;
    MD_SIZE size = 0;
    bool sawInside = false;
    bool sawOutside = false;
  } bounds{src.data(), static_cast<MD_SIZE>(src.size())};

  // md4c calls every structural callback unconditionally, so all of them must
  // be set even when a test only cares about text.
  MD_PARSER parser{};
  parser.flags = kHeapFlags;
  parser.enter_block = [](MD_BLOCKTYPE, void*, void*) {
    return 0;
  };
  parser.leave_block = [](MD_BLOCKTYPE, void*, void*) {
    return 0;
  };
  parser.enter_span = [](MD_SPANTYPE, void*, void*) {
    return 0;
  };
  parser.leave_span = [](MD_SPANTYPE, void*, void*) {
    return 0;
  };
  parser.text = [](MD_TEXTTYPE type, const MD_CHAR* text, MD_SIZE, void* userdata) {
    auto* b = static_cast<Bounds*>(userdata);
    if(type == MD_TEXT_NORMAL) {
      if(text >= b->base && text < b->base + b->size) {
        b->sawInside = true;
      } else {
        b->sawOutside = true;
      }
    }
    return 0;
  };

  ASSERT_EQ(md_parse(src.data(), bounds.size, &parser, &bounds), 0);
  EXPECT_TRUE(bounds.sawInside);
  EXPECT_FALSE(bounds.sawOutside);
}

TEST(Md4cSmokeTest, SurvivesDegenerateInput) {
  // Empty, unterminated and binary-ish input must return cleanly rather than
  // crash — the fuzz-style tests added later lean on this being true.
  EXPECT_NO_FATAL_FAILURE(parse(""));
  EXPECT_NO_FATAL_FAILURE(parse("```unterminated\ncode\n"));
  EXPECT_NO_FATAL_FAILURE(parse("| broken | table\n|---\n"));
  EXPECT_NO_FATAL_FAILURE(parse(std::string("a\0b\n", 4)));
  EXPECT_NO_FATAL_FAILURE(parse("> > > deeply\n\n- - - nested\n"));
}
