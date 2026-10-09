#pragma once

#include <QElapsedTimer>
#include <QJSValue>
#include <QObject>
#include <QPointer>
#include <QQmlParserStatus>
#include <QStringList>
#include <QTimer>
#include <QtQml/qqmlregistration.h>
#include <QVariantList>

class QKeyEvent;

// The keys of the 0.8.0 keymap that a Qt Shortcut cannot carry (APP-272):
// bare letters that must stand down while the person types, two-key
// sequences with a prefix ("g b", "y y", "z a") that wait a second for their
// second key, and every binding read by the physical key, so "п и" on a
// Russian layout is "g b" and Ctrl+Л is Ctrl+K.
//
// Installed on the application, first in line: it sees each key press before
// the shortcut map and TypeAhead do. A key it answers is taken whole (the
// ShortcutOverride and the press that follows); anything else goes on as if
// it were not there.
//
// It knows the bindings (AppController.shortcuts), not what they do: for a
// key that matches, it calls `handler(ids, dryRun)` with the matching ids
// joined by ",". The handler runs the first one that is live where the
// person is and returns its id, or "" when none is — then the key is left
// alone. With dryRun it only answers whether one would run.
class KeyRouter : public QObject, public QQmlParserStatus {
  Q_OBJECT
  Q_INTERFACES(QQmlParserStatus)
  QML_ELEMENT
  Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
  Q_PROPERTY(QObject* window READ window WRITE setWindow NOTIFY windowChanged)
  Q_PROPERTY(QVariantList bindings READ bindings WRITE setBindings NOTIFY bindingsChanged)
  Q_PROPERTY(QJSValue handler READ handler WRITE setHandler NOTIFY handlerChanged)
  // Catalogue ids a Qt Shortcut in Main already runs: left to it, unless the
  // key came from a layout that does not type Latin letters.
  Q_PROPERTY(QStringList qtOwned READ qtOwned WRITE setQtOwned NOTIFY qtOwnedChanged)
  // The first key of a two-key sequence, waiting for the second
  // (PortableText, "G"); empty when nothing waits.
  Q_PROPERTY(QString pending READ pending NOTIFY pendingChanged)
  Q_PROPERTY(int timeoutMs READ timeoutMs WRITE setTimeoutMs NOTIFY timeoutMsChanged)
  // "" follows the system's keyboard layout; "latin" / "other" pin it (tests).
  Q_PROPERTY(QString layout READ layout WRITE setLayout NOTIFY layoutChanged)

 public:
  explicit KeyRouter(QObject* parent = nullptr);
  ~KeyRouter() override;

  void classBegin() override {
  }

  void componentComplete() override;

  bool enabled() const {
    return m_enabled;
  }

  void setEnabled(bool on);

  QObject* window() const {
    return m_window;
  }

  void setWindow(QObject* w);

  QVariantList bindings() const {
    return m_bindings;
  }

  void setBindings(const QVariantList& list);

  QJSValue handler() const {
    return m_handler;
  }

  void setHandler(const QJSValue& fn);

  QStringList qtOwned() const {
    return m_qtOwned;
  }

  void setQtOwned(const QStringList& ids);

  QString pending() const {
    return m_pending;
  }

  int timeoutMs() const {
    return m_timeout.interval();
  }

  void setTimeoutMs(int ms);

  QString layout() const {
    return m_layout;
  }

  void setLayout(const QString& l);

  // Lets go of a waiting prefix.
  Q_INVOKABLE void cancel();
  // The chord a key press is read as (KeyNames::chordFor), for QML tests.
  Q_INVOKABLE QString chordOf(int key, int modifiers, const QString& text) const;

 signals:
  void enabledChanged();
  void windowChanged();
  void bindingsChanged();
  void handlerChanged();
  void qtOwnedChanged();
  void pendingChanged();
  void timeoutMsChanged();
  void layoutChanged();
  // Every key the person pressed outside a text field (and every chord with
  // Ctrl/Alt anywhere), as a chord — for the one-time "this key moved" notice.
  void chordPressed(const QString& chord);

 protected:
  bool eventFilter(QObject* watched, QEvent* event) override;

 private:
  struct Binding {
    QString id;
    QString sequence;
    bool router = false;  // bare or two-key: never a Qt Shortcut
  };

  bool belongsToWindow(QObject* watched) const;
  bool latinLayout() const;
  // Decides and, unless dry, runs. True when the key is taken.
  bool decide(QKeyEvent* ke, bool focusTyping);
  QString callHandler(const QStringList& ids, bool dry);
  void setPending(const QString& chord);

  bool m_enabled = true;
  QPointer<QObject> m_window;
  QVariantList m_bindings;
  QList<Binding> m_parsed;
  QJSValue m_handler;
  QStringList m_qtOwned;
  QString m_pending;
  QString m_layout;
  QTimer m_timeout;
  // The press whose ShortcutOverride was taken: its KeyPress is swallowed.
  int m_takenKey = 0;
  // The press whose ShortcutOverride was seen and left alone.
  int m_seenKey = 0;
};
