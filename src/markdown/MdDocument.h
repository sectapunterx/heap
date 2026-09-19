#pragma once

#include "markdown/MdBlockModel.h"
#include "markdown/MdHtml.h"
#include "markdown/MdOutline.h"
#include "markdown/MdParser.h"
#include "markdown/MdSourceMap.h"

#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantMap>

namespace heap::md {

// What QML talks to: markdown in, a model of rows out.
//
// One of these owns the parse for one document. The view binds to its model,
// the editor writes its text, and everything else — the outline, the backlinks
// pane, which row a line belongs to — is answered from the same parse instead
// of re-scanning the text per question.
//
// Re-parsing is debounced, and the delay adapts: a small note is parsed on the
// keystroke, a large one waits a moment. Typing must never be the thing that
// waits for markdown.
class MdDocument : public QObject {
  Q_OBJECT
  QML_ELEMENT

  // The markdown source. Assigning it schedules a re-parse.
  Q_PROPERTY(QString text READ text WRITE setText NOTIFY textChanged)
  // Rows to draw. Stable for the lifetime of this object.
  Q_PROPERTY(QObject* model READ model CONSTANT)
  // Theme colours, by the names in MdHtmlPalette: "text", "link", "code",
  // "codeBackground", "highlightBackground", "mention", "ticket", "tag",
  // "math", "dim". Set from QML's Theme so the rendered view matches the
  // editor in light and dark mode.
  Q_PROPERTY(QVariantMap palette READ palette WRITE setPalette NOTIFY paletteChanged)
  // Off by default. See MdHtmlOptions: rendering a remote image makes a
  // network request on the author's behalf, to a host chosen by whoever wrote
  // the note.
  Q_PROPERTY(bool allowRemoteImages READ allowRemoteImages WRITE setAllowRemoteImages NOTIFY allowRemoteImagesChanged)
  // Headings, for an outline or a jump list: [{ level, text, line, offset }].
  Q_PROPERTY(QVariantList outline READ outlineList NOTIFY parsed)
  // How long the last parse took, in milliseconds. Exposed so the view can be
  // honest about a document that has grown too large rather than just feeling
  // slow.
  Q_PROPERTY(int lastParseMs READ lastParseMs NOTIFY parsed)

 public:
  explicit MdDocument(QObject* parent = nullptr);

  QString text() const {
    return m_text;
  }

  void setText(const QString& text);

  QObject* model() {
    return &m_model;
  }

  QVariantMap palette() const {
    return m_palette;
  }

  void setPalette(const QVariantMap& palette);

  bool allowRemoteImages() const {
    return m_allowRemoteImages;
  }

  void setAllowRemoteImages(bool allow);

  QVariantList outlineList() const {
    return m_outline;
  }

  int lastParseMs() const {
    return m_lastParseMs;
  }

  // Parse now rather than on the timer. Called before any query that must see
  // the text as it stands this instant.
  Q_INVOKABLE void flush();

  // ── Source mapping, for scroll sync and click-to-source ─────────
  Q_INVOKABLE int rowForLine(int line);
  Q_INVOKABLE int firstLineOfRow(int row);
  Q_INVOKABLE int lastLineOfRow(int row);
  // 0-based line holding a UTF-16 cursor position, and the position at which
  // a line starts. The editor counts in cursor positions; the model counts in
  // lines.
  Q_INVOKABLE int lineForPosition(int position);
  Q_INVOKABLE int positionForLine(int line);

 signals:
  void textChanged();
  void paletteChanged();
  void allowRemoteImagesChanged();
  void parsed();

 private:
  void scheduleParse();
  void reparse();
  MdHtmlOptions buildOptions() const;

  QString m_text;
  QVariantMap m_palette;
  bool m_allowRemoteImages = false;

  MdSourceMap m_src;
  MdAst m_ast;
  MdBlockModel m_model;
  QVariantList m_outline;

  QTimer m_parseTimer;
  bool m_dirty = false;
  int m_lastParseMs = 0;
};

}  // namespace heap::md
