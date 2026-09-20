#pragma once

#include "Models.h"

#include <QHash>
#include <QSet>
#include <QString>
#include <QVariantList>
#include <QVector>

#include <algorithm>

// Multi-level undo/redo.
//
// Undo used to be a single slot with a five-second timer: the next destructive
// operation overwrote the previous one, there was no redo, and several
// operations (bulk move, bulk archive) armed nothing at all. It was also
// per-operation bespoke — every new mutator had to hand-write what to record
// and how to put it back, which is why some of them did not bother.
//
// This records what *changed* instead. An operation is wrapped in a scope that
// copies the collections on entry (QVector is implicitly shared, so that is a
// refcount bump) and diffs them by id on exit. The resulting entry holds only
// the differing elements, so a hundred entries do not hold a hundred copies of
// every task, and a mutator does not have to describe itself.
namespace heap::undo {

// One element of a collection that differs between the start and the end of an
// operation. The rows are where it sat on each side, so putting it back is an
// insertAt rather than an append.
template<class T>
struct Edit {
  QString id;
  int rowBefore = -1;
  int rowAfter = -1;
  bool existedBefore = false;
  bool existsAfter = false;
  T before;
  T after;
};

template<class T>
using Edits = QVector<Edit<T>>;

// Diff two snapshots of one collection, keyed by id. Only elements that were
// added, removed or actually changed are kept.
template<class T, class IdFn>
Edits<T> diff(const QVector<T>& before, const QVector<T>& after, IdFn idOf) {
  QHash<QString, int> afterIndex;
  afterIndex.reserve(after.size());
  for(int i = 0; i < after.size(); ++i) {
    afterIndex.insert(idOf(after.at(i)), i);
  }

  Edits<T> out;
  QSet<QString> seen;
  seen.reserve(before.size());
  for(int i = 0; i < before.size(); ++i) {
    const QString id = idOf(before.at(i));
    seen.insert(id);
    const auto it = afterIndex.constFind(id);
    if(it == afterIndex.constEnd()) {
      out.append(Edit<T>{id, i, -1, true, false, before.at(i), T{}});
    } else if(!(before.at(i) == after.at(*it))) {
      out.append(Edit<T>{id, i, *it, true, true, before.at(i), after.at(*it)});
    }
  }
  for(int i = 0; i < after.size(); ++i) {
    const QString id = idOf(after.at(i));
    if(!seen.contains(id)) {
      out.append(Edit<T>{id, -1, i, false, true, T{}, after.at(i)});
    }
  }
  return out;
}

namespace detail {

// Removals run before insertions, and insertions run in ascending row order,
// so every recorded row index still means what it meant when it was recorded.
template<class Model, class T, class PickRow, class PickValue, class WasPresent, class WillBePresent>
void apply(Model& model, const Edits<T>& edits, PickRow row, PickValue value, WasPresent from, WillBePresent to) {
  for(const Edit<T>& e : edits) {
    if(!from(e) && to(e)) {
      model.removeById(e.id);
    }
  }
  for(const Edit<T>& e : edits) {
    if(from(e) && to(e)) {
      model.upsert(value(e));
    }
  }
  QVector<const Edit<T>*> inserts;
  for(const Edit<T>& e : edits) {
    if(from(e) && !to(e)) {
      inserts.append(&e);
    }
  }
  std::sort(inserts.begin(), inserts.end(), [&](const Edit<T>* a, const Edit<T>* b) {
    return row(*a) < row(*b);
  });
  for(const Edit<T>* e : inserts) {
    model.insertAt(qBound(0, row(*e), static_cast<int>(model.rowCount())), value(*e));
  }
}

}  // namespace detail

// Put the collection back the way it was before the operation.
template<class Model, class T>
void applyBackward(Model& model, const Edits<T>& edits) {
  detail::apply(
      model, edits, [](const Edit<T>& e) { return e.rowBefore; }, [](const Edit<T>& e) -> const T& { return e.before; },
      [](const Edit<T>& e) { return e.existedBefore; }, [](const Edit<T>& e) { return e.existsAfter; });
}

// Re-apply the operation.
template<class Model, class T>
void applyForward(Model& model, const Edits<T>& edits) {
  detail::apply(
      model, edits, [](const Edit<T>& e) { return e.rowAfter; }, [](const Edit<T>& e) -> const T& { return e.after; },
      [](const Edit<T>& e) { return e.existsAfter; }, [](const Edit<T>& e) { return e.existedBefore; });
}

// One undoable operation.
struct Entry {
  QString label;  // what the toast says, already translated
  Edits<Task> tasks;
  Edits<CalEvent> events;
  Edits<Person> people;
  // Statuses are a handful of maps with no model behind them, so the whole
  // list is cheaper to keep than a diff.
  bool statusesTouched = false;
  QVariantList statusesBefore;
  QVariantList statusesAfter;
  // A deleted profile is not a diff: restoring it swaps the whole workspace,
  // including which tasks the models hold. Such an entry stands alone — see
  // UndoStack::pushProfileRemoval.
  bool profileRemoved = false;
  ::Profile profile;
  int profileRow = -1;

  bool isEmpty() const {
    return !profileRemoved && !statusesTouched && tasks.isEmpty() && events.isEmpty() && people.isEmpty();
  }
};

// The stack itself: entries below the cursor can be undone, entries at or above
// it can be redone. A new entry truncates whatever was redoable, which is what
// every editor does.
class UndoStack {
 public:
  // Deep enough to cover a working session, shallow enough that the diffs it
  // holds stay a rounding error next to the state they describe.
  static constexpr int kMaxDepth = 100;

  void push(Entry entry) {
    if(entry.isEmpty()) {
      return;
    }
    m_entries.resize(m_cursor);
    m_entries.append(std::move(entry));
    if(m_entries.size() > kMaxDepth) {
      m_entries.remove(0, m_entries.size() - kMaxDepth);
    }
    m_cursor = m_entries.size();
  }

  // A profile removal replaces the whole workspace, so nothing recorded before
  // it still describes the collections it would be applied to.
  void pushProfileRemoval(Entry entry) {
    clear();
    push(std::move(entry));
  }

  bool canUndo() const {
    return m_cursor > 0;
  }

  bool canRedo() const {
    return m_cursor < m_entries.size();
  }

  // The entry Ctrl+Z would reverse, or nullptr.
  const Entry* peekUndo() const {
    return canUndo() ? &m_entries.at(m_cursor - 1) : nullptr;
  }

  const Entry* peekRedo() const {
    return canRedo() ? &m_entries.at(m_cursor) : nullptr;
  }

  const Entry* takeUndo() {
    if(!canUndo()) {
      return nullptr;
    }
    --m_cursor;
    return &m_entries.at(m_cursor);
  }

  const Entry* takeRedo() {
    if(!canRedo()) {
      return nullptr;
    }
    const Entry* e = &m_entries.at(m_cursor);
    ++m_cursor;
    return e;
  }

  void clear() {
    m_entries.clear();
    m_cursor = 0;
  }

  int depth() const {
    return static_cast<int>(m_entries.size());
  }

 private:
  QVector<Entry> m_entries;
  int m_cursor = 0;  // entries[0, cursor) are undoable
};

}  // namespace heap::undo
