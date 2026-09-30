#pragma once

#include "Models.h"

#include <QHash>
#include <QSet>
#include <QString>
#include <QStringList>
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
      model,
      edits,
      [](const Edit<T>& e) {
        return e.rowBefore;
      },
      [](const Edit<T>& e) -> const T& {
        return e.before;
      },
      [](const Edit<T>& e) {
        return e.existedBefore;
      },
      [](const Edit<T>& e) {
        return e.existsAfter;
      });
}

// Re-apply the operation.
template<class Model, class T>
void applyForward(Model& model, const Edits<T>& edits) {
  detail::apply(
      model,
      edits,
      [](const Edit<T>& e) {
        return e.rowAfter;
      },
      [](const Edit<T>& e) -> const T& {
        return e.after;
      },
      [](const Edit<T>& e) {
        return e.existsAfter;
      },
      [](const Edit<T>& e) {
        return e.existedBefore;
      });
}

// True when every element `edits` touched is still exactly as the operation
// left it — the precondition for reversing that one operation while later ones
// stay in place.
template<class Model, class T>
bool untouchedSince(const Model& model, const Edits<T>& edits) {
  for(const Edit<T>& e : edits) {
    const int row = model.indexOfId(e.id);
    if((row >= 0) != e.existsAfter) {
      return false;
    }
    if(row >= 0 && !(model.items().at(row) == e.after)) {
      return false;
    }
  }
  return true;
}

namespace detail {
inline QString statusIdOf(const QVariant& v) {
  return v.toMap().value(QStringLiteral("id")).toString();
}

inline int statusRow(const QVariantList& xs, const QString& id) {
  for(int i = 0; i < xs.size(); ++i) {
    if(statusIdOf(xs.at(i)) == id) {
      return i;
    }
  }
  return -1;
}
}  // namespace detail

// The board columns are kept whole per entry, which is exact for Ctrl+Z (the
// entries come off in order). Reversing one entry out of order must not throw
// away the column edits made after it, so this reverts only the columns that
// entry changed: a column it deleted comes back where it was, one it added
// goes, one it edited gets its old fields. `ok` is false when a column it
// changed has been changed again since.
inline QVariantList revertStatusesOnly(const QVariantList& current, const QVariantList& before, const QVariantList& after, bool* ok) {
  QVariantList out = current;
  bool clean = true;
  // Columns the entry added: drop them.
  for(const QVariant& a : after) {
    const QString id = detail::statusIdOf(a);
    if(detail::statusRow(before, id) < 0) {
      const int at = detail::statusRow(out, id);
      if(at >= 0) {
        clean = clean && out.at(at) == a;
        out.removeAt(at);
      }
    }
  }
  // Columns the entry edited: restore their fields in place.
  for(const QVariant& b : before) {
    const QString id = detail::statusIdOf(b);
    const int inAfter = detail::statusRow(after, id);
    if(inAfter >= 0 && !(after.at(inAfter) == b)) {
      const int at = detail::statusRow(out, id);
      if(at >= 0) {
        clean = clean && out.at(at) == after.at(inAfter);
        out[at] = b;
      }
    }
  }
  // Columns the entry removed: put them back at their old index.
  for(int i = 0; i < before.size(); ++i) {
    const QString id = detail::statusIdOf(before.at(i));
    if(detail::statusRow(after, id) < 0 && detail::statusRow(out, id) < 0) {
      out.insert(qBound(0, i, static_cast<int>(out.size())), before.at(i));
    }
  }
  // An entry that only reordered columns: its old order can be restored only
  // if nothing has moved since.
  if(out == current && before != after) {
    if(current == after) {
      out = before;
    } else {
      clean = false;
    }
  }
  if(ok != nullptr) {
    *ok = clean;
  }
  return out;
}

// One undoable operation.
struct Entry {
  QString label;  // what the toast says, already translated
  // Stable identity for the operation, so a toast's Undo button can take back
  // the action it names even after something else was done in between. 0 =
  // unassigned (entries built by hand in tests).
  quint64 serial = 0;
  Edits<Task> tasks;
  Edits<CalEvent> events;
  Edits<Person> people;
  // Docs pages are a tree, and deleting one takes its whole subtree — which is
  // the operation most in need of an undo, and the one that would otherwise
  // leave the stack silently unable to put it back.
  Edits<DocPage> docPages;
  // A deleted note used to be gone for good: the menu item removed it at once
  // and nothing recorded what it held.
  Edits<Note> notes;
  // Statuses are a handful of maps with no model behind them, so the whole
  // list is cheaper to keep than a diff.
  bool statusesTouched = false;
  QVariantList statusesBefore;
  QVariantList statusesAfter;
  // The Docs catalog (links, snippets, contacts) is one JSON blob, so it is
  // kept whole, like the statuses.
  bool docsStateTouched = false;
  QString docsStateBefore;
  QString docsStateAfter;
  // A deleted profile is not a diff: restoring it swaps the whole workspace,
  // including which tasks the models hold. Such an entry stands alone — see
  // UndoStack::pushProfileRemoval.
  bool profileRemoved = false;
  ::Profile profile;
  int profileRow = -1;
  // Events the deletion detached from the profile (profileId cleared), so the
  // undo can hand them back (PLAT-14).
  QStringList profileEventIds;

  bool isEmpty() const {
    return !profileRemoved && !statusesTouched && !docsStateTouched && tasks.isEmpty() && events.isEmpty() && people.isEmpty() &&
           docPages.isEmpty() && notes.isEmpty();
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

  // The undoable entry recorded under `serial`, or nullptr when it has been
  // undone already, fell off the bottom of the stack or never existed.
  const Entry* findUndoable(quint64 serial) const {
    if(serial == 0) {
      return nullptr;
    }
    for(int i = 0; i < m_cursor; ++i) {
      if(m_entries.at(i).serial == serial) {
        return &m_entries.at(i);
      }
    }
    return nullptr;
  }

  // Takes one entry out of the undoable part of the stack after it has been
  // reversed out of order. The redoable tail goes too: those entries were
  // recorded on top of a state that no longer exists.
  bool removeUndoable(quint64 serial) {
    for(int i = 0; i < m_cursor; ++i) {
      if(m_entries.at(i).serial == serial) {
        m_entries.resize(m_cursor);
        m_entries.remove(i);
        m_cursor = static_cast<int>(m_entries.size());
        return true;
      }
    }
    return false;
  }

  int depth() const {
    return static_cast<int>(m_entries.size());
  }

 private:
  QVector<Entry> m_entries;
  int m_cursor = 0;  // entries[0, cursor) are undoable
};

}  // namespace heap::undo
