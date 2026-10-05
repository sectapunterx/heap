#pragma once

#include "markdown/MdBlockModel.h"
#include "markdown/MdHtml.h"
#include "markdown/MdOutline.h"
#include "markdown/MdParser.h"
#include "markdown/MdSourceMap.h"

#include <QObject>
#include <QQmlEngine>
#include <QQuickTextDocument>
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
  // Ticket id → title: a "#APP-12" in the rendered view reads as the ticket's
  // title (APP-121). Bound to AppController.taskTitles.
  Q_PROPERTY(QVariantMap ticketTitles READ ticketTitles WRITE setTicketTitles NOTIFY ticketTitlesChanged)
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
  // Parse as the text changes (true), or only when asked (false): an editor
  // with its preview hidden has no use for a parse of every pause, and at
  // megabytes each one is a visible stall. A query (rowForLine, flush, …)
  // still parses on demand, and going live again catches up.
  Q_PROPERTY(bool live READ live WRITE setLive NOTIFY liveChanged)
  // Where relative image paths are looked up (see resolveImage()).
  Q_PROPERTY(QString imageBaseDir READ imageBaseDir WRITE setImageBaseDir NOTIFY imageBaseDirChanged)

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

  QVariantMap ticketTitles() const {
    return m_ticketTitles;
  }

  void setTicketTitles(const QVariantMap& titles);

  bool allowRemoteImages() const {
    return m_allowRemoteImages;
  }

  void setAllowRemoteImages(bool allow);

  bool live() const {
    return m_live;
  }

  void setLive(bool live);

  QString imageBaseDir() const {
    return m_imageBaseDir;
  }

  void setImageBaseDir(const QString& dir);

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
  Q_INVOKABLE int rowForFootnote(const QString& id);
  // 0-based line holding a UTF-16 cursor position, and the position at which
  // a line starts. The editor counts in cursor positions; the model counts in
  // lines.
  Q_INVOKABLE int lineForPosition(int position);
  Q_INVOKABLE int positionForLine(int line);

  // What it takes to flip the checkbox drawn by `row`:
  //   { "position": <utf-16>, "from": "x", "to": " " }
  // or an empty map when the row is not a task, or when the parse no longer
  // matches the text. Exposed mostly so tests can assert the arithmetic
  // without a document.
  Q_INVOKABLE QVariantMap taskToggleForRow(int row);

  // Flip that checkbox in the editor's own document. Returns false when the
  // row is not a task or the parse has fallen behind the text.
  //
  // The write goes through a QTextCursor inside a single edit block, so it is
  // one undo step. Doing it as a remove followed by an insert looks the same
  // until Ctrl+Z, which then takes back only the insert and leaves "[]" —
  // markdown that is no longer a task at all.
  Q_INVOKABLE bool toggleTask(QQuickTextDocument* target, int row);

 signals:
  void textChanged();
  void paletteChanged();
  void ticketTitlesChanged();
  void allowRemoteImagesChanged();
  void liveChanged();
  void imageBaseDirChanged();
  void parsed();

 private:
  void scheduleParse();
  void reparse();
  MdHtmlOptions buildOptions() const;

  QString m_text;
  QVariantMap m_palette;
  QVariantMap m_ticketTitles;
  bool m_allowRemoteImages = false;
  bool m_live = true;
  QString m_imageBaseDir;

  MdSourceMap m_src;
  MdAst m_ast;
  MdBlockModel m_model;
  QVariantList m_outline;

  QTimer m_parseTimer;
  bool m_dirty = false;
  int m_lastParseMs = 0;
};

}  // namespace heap::md
