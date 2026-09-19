#pragma once

#include "markdown/MdEditOps.h"

#include <QObject>
#include <QQmlEngine>
#include <QQuickTextDocument>

namespace heap::md {

// The editor's keyboard behaviour, in one place QML can call.
//
// NotesView used to carry this as a few hundred lines of JavaScript in a
// Keys.onPressed handler: what Enter does on a list item, what Tab does inside
// a fence, and nothing at all for bold or italic. Moving it here means the
// rules can be tested directly, and it leaves the QML handler short enough to
// read in one go.
//
// Each operation is one undo step, because each goes through a QTextCursor
// inside a single edit block — see MdEditOps.
class MarkdownEditorController : public QObject {
  Q_OBJECT
  QML_ELEMENT

  // The editor's document. Everything here is a no-op until this is set.
  Q_PROPERTY(QQuickTextDocument* target READ target WRITE setTarget NOTIFY targetChanged)
  // Caret and selection, kept in step with the editor's own. The controller
  // writes back to these after an operation, and the editor binds them to its
  // cursorPosition and selection.
  Q_PROPERTY(int cursorPosition READ cursorPosition WRITE setCursorPosition NOTIFY selectionChanged)
  Q_PROPERTY(int selectionStart READ selectionStart WRITE setSelectionStart NOTIFY selectionChanged)
  Q_PROPERTY(int selectionEnd READ selectionEnd WRITE setSelectionEnd NOTIFY selectionChanged)

 public:
  explicit MarkdownEditorController(QObject* parent = nullptr);

  QQuickTextDocument* target() const {
    return m_target;
  }

  void setTarget(QQuickTextDocument* target);

  int cursorPosition() const {
    return m_selection.end;
  }

  void setCursorPosition(int position);

  int selectionStart() const {
    return m_selection.start;
  }

  void setSelectionStart(int position);

  int selectionEnd() const {
    return m_selection.end;
  }

  void setSelectionEnd(int position);

  // ── Operations, each one undo step ──────────────────────────────
  Q_INVOKABLE void toggleBold();
  Q_INVOKABLE void toggleItalic();
  Q_INVOKABLE void toggleStrikethrough();
  Q_INVOKABLE void toggleCode();
  Q_INVOKABLE void toggleHighlight();
  Q_INVOKABLE void insertLink(const QString& url = {});
  Q_INVOKABLE void cycleHeading();
  Q_INVOKABLE void toggleTask();
  Q_INVOKABLE void indent();
  Q_INVOKABLE void outdent();
  Q_INVOKABLE void paste(const QString& text);

  // Enter, with markdown continuation. Returns true when it did something, so
  // the QML handler knows whether to let the key through: an unhandled Enter
  // must still insert a plain newline.
  Q_INVOKABLE bool handleReturn();

  // True when the caret sits inside a fenced code block. The view asks so it
  // can tell a code Tab from a list Tab.
  Q_INVOKABLE bool insideFence() const;

 signals:
  void targetChanged();
  void selectionChanged();
  // Emitted after an operation, with where the caret and selection should now
  // be. The editor applies it: only the editor can move its own cursor.
  void selectionRequested(int start, int end);

 private:
  QTextDocument* document() const;
  void apply(const Selection& result);

  QQuickTextDocument* m_target = nullptr;
  Selection m_selection;
};

}  // namespace heap::md
