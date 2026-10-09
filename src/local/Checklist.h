#pragma once

#include "local/TaskLocal.h"

#include <QString>
#include <QVector>

// The card's own checklist (APP-236), as pure functions over the flat list in
// TaskLocal::checklist. A line's depth is its `level`; an item's children are
// the run of items right after it with a deeper level.
//
// Text form, one item per line (owner's rules, 2026-10-08):
//   "item" and "- item"          level 1
//   "-- item" == "- - item"      level 2; every further dash one deeper
//   "--- [x] item"               done; "[ ]" or no mark = not done
//   "  -- item"                  leading spaces: not nested, level 1
// Blank lines are skipped. The canonical form written back is joined dashes
// and "[x]": "- item", "-- [x] item".
namespace heap::local::checklist {

struct Progress {
  int done = 0;
  int total = 0;
};

// Text → items. `previous` lends its ids (and the "became a card" link) to
// the lines that kept their text, so editing the text form is not a new list.
QVector<LocalCheckItem> parse(const QString& text, const QVector<LocalCheckItem>& previous = {});
QString serialize(const QVector<LocalCheckItem>& items);

// One line, for an item typed or edited in place: its level (0 when the line
// has no dashes) and done mark, and the text without them.
struct Line {
  int level = 0;
  bool done = false;
  QString text;
};

Line parseLine(const QString& line);

// Index one past the last descendant of items[i].
int subtreeEnd(const QVector<LocalCheckItem>& items, int i);
bool hasChildren(const QVector<LocalCheckItem>& items, int i);

// Ticks (or unticks) an item and everything under it, then settles the
// parents. A tick by hand is never "auto".
void setDone(QVector<LocalCheckItem>& items, int i, bool done);

// Parents follow their children (owner's rules): every child done → the
// parent is done, marked auto; a child not done → the parent is not done, and
// so on up. Leaves keep what they are and are never auto.
void settle(QVector<LocalCheckItem>& items);

// Moves an item and its subtree a level deeper (+1) or shallower (-1). Level 1
// stays 1.
void indent(QVector<LocalCheckItem>& items, int i, int delta);

// Moves an item with its subtree past the neighbouring sibling subtree (up =
// -1, down = +1). Returns the item's new index, or -1 when it could not move.
int move(QVector<LocalCheckItem>& items, int i, int dir);

// Removes an item and its subtree.
void remove(QVector<LocalCheckItem>& items, int i);

// Every item at every level counts one.
Progress progress(const QVector<LocalCheckItem>& items);

// The next step: the first unticked item from the top, then down its branch
// to the deepest first unticked item. -1 when everything is done or empty.
int nextStep(const QVector<LocalCheckItem>& items);

// A short unique id for a new item.
QString newId();

}  // namespace heap::local::checklist
