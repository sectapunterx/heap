// Quick task edits that do not need the editor: priority and labels, on one
// card or on the whole selection (audit TASKS-32 / UX-26). Kept out of
// AppController.cpp, which is long enough; these are ordinary members.

#include "AppController.h"

#include <QRegularExpression>

namespace {

bool validPriority(const QString& p) {
  static const QRegularExpression kPriority(QStringLiteral("^P[0-3]$"));
  return kPriority.match(p).hasMatch();
}

}  // namespace

bool AppController::setPriorityOf(const QString& id, const QString& priority) {
  const int row = m_tasks.indexOfId(id);
  if(row < 0) {
    return false;
  }
  Task t = m_tasks.items().at(row);
  if(t.priority == priority) {
    return false;
  }
  t.priority = priority;
  m_tasks.upsert(t);
  return true;
}

void AppController::setTaskPriority(const QString& taskId, const QString& priority) {
  if(!validPriority(priority)) {
    return;
  }
  const UndoScope scope(this, tr_("task.editUndone").arg(taskId));
  if(setPriorityOf(taskId, priority)) {
    emit undoableToast(tr_("task.moved").arg(taskId, priority), 5);
    scheduleSave();
  }
}

void AppController::setSelectedTasksPriority(const QString& priority) {
  if(!validPriority(priority) || m_selectedTaskIdsList.isEmpty()) {
    return;
  }
  UndoScope scope(this, tr_("undo.bulkEdit").arg(m_selectedTaskIdsList.size()));
  int n = 0;
  for(const QString& id : m_selectedTaskIdsList) {
    n += setPriorityOf(id, priority) ? 1 : 0;
  }
  if(n > 0) {
    scope.setLabel(tr_("undo.bulkEdit").arg(n));
    emit undoableToast(tr_("task.bulkPriority").arg(n).arg(priority), 5);
    scheduleSave();
  }
}

void AppController::setSelectedTasksLabel(const QString& label, bool present) {
  const QString name = label.trimmed().remove(QRegularExpression(QStringLiteral("^#+")));
  if(name.isEmpty() || m_selectedTaskIdsList.isEmpty()) {
    return;
  }
  UndoScope scope(this, tr_("undo.bulkEdit").arg(m_selectedTaskIdsList.size()));
  int n = 0;
  for(const QString& id : m_selectedTaskIdsList) {
    const int row = m_tasks.indexOfId(id);
    if(row < 0) {
      continue;
    }
    Task t = m_tasks.items().at(row);
    int at = -1;
    for(int i = 0; i < t.labels.size(); ++i) {
      if(t.labels.at(i).id.compare(name, Qt::CaseInsensitive) == 0) {
        at = i;
        break;
      }
    }
    if(present && at < 0) {
      // Reuse the colour the label already has elsewhere on the board.
      QString color;
      for(const Task& other : m_tasks.items()) {
        for(const Label& l : other.labels) {
          if(l.id.compare(name, Qt::CaseInsensitive) == 0 && !l.color.isEmpty()) {
            color = l.color;
            break;
          }
        }
        if(!color.isEmpty()) {
          break;
        }
      }
      t.labels.append(Label{name, color});
    } else if(!present && at >= 0) {
      t.labels.removeAt(at);
    } else {
      continue;
    }
    m_tasks.upsert(t);
    ++n;
  }
  if(n > 0) {
    scope.setLabel(tr_("undo.bulkEdit").arg(n));
    emit undoableToast(tr_(present ? "task.bulkLabel" : "task.bulkUnlabel").arg(n).arg(name), 5);
    scheduleSave();
  }
}
