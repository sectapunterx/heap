#include "keys/KeyNames.h"
#include "keys/KeyRouter.h"
#include "platform/AltGrGuard.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QInputMethod>
#include <QKeyEvent>
#include <QLocale>
#include <QQuickItem>
#include <QQuickWindow>
#include <QWindow>

KeyRouter::KeyRouter(QObject* parent) : QObject(parent) {
  m_timeout.setSingleShot(true);
  m_timeout.setInterval(1000);
  connect(&m_timeout, &QTimer::timeout, this, &KeyRouter::cancel);
  QCoreApplication::instance()->installEventFilter(this);
}

KeyRouter::~KeyRouter() {
  if(QCoreApplication::instance() != nullptr) {
    QCoreApplication::instance()->removeEventFilter(this);
  }
}

void KeyRouter::componentComplete() {
  // Installed again so it runs before every filter installed while the rest
  // of the window was built (TypeAhead): the last one installed runs first.
  QCoreApplication::instance()->installEventFilter(this);
}

void KeyRouter::setEnabled(bool on) {
  if(m_enabled == on) {
    return;
  }
  m_enabled = on;
  if(!on) {
    cancel();
  }
  emit enabledChanged();
}

void KeyRouter::setWindow(QObject* w) {
  if(m_window == w) {
    return;
  }
  m_window = w;
  emit windowChanged();
}

void KeyRouter::setBindings(const QVariantList& list) {
  m_bindings = list;
  m_parsed.clear();
  for(const QVariant& v : list) {
    const QVariantMap m = v.toMap();
    const QString seq = m.value(QStringLiteral("sequence")).toString();
    if(seq.isEmpty()) {
      continue;
    }
    m_parsed.append({m.value(QStringLiteral("id")).toString(), seq, heap::keys::isRouterSequence(seq)});
  }
  emit bindingsChanged();
}

void KeyRouter::setHandler(const QJSValue& fn) {
  m_handler = fn;
  emit handlerChanged();
}

void KeyRouter::setQtOwned(const QStringList& ids) {
  if(m_qtOwned == ids) {
    return;
  }
  m_qtOwned = ids;
  emit qtOwnedChanged();
}

void KeyRouter::setTimeoutMs(int ms) {
  if(m_timeout.interval() == ms) {
    return;
  }
  m_timeout.setInterval(ms);
  emit timeoutMsChanged();
}

void KeyRouter::setLayout(const QString& l) {
  if(m_layout == l) {
    return;
  }
  m_layout = l;
  emit layoutChanged();
}

void KeyRouter::cancel() {
  m_timeout.stop();
  setPending(QString());
}

void KeyRouter::setPending(const QString& chord) {
  if(m_pending == chord) {
    return;
  }
  m_pending = chord;
  emit pendingChanged();
}

QString KeyRouter::chordOf(int key, int modifiers, const QString& text) const {
  heap::keys::KeyInput in;
  in.key = key;
  in.modifiers = Qt::KeyboardModifiers(modifiers);
  in.text = text;
  return heap::keys::chordFor(in, heap::keys::NativeKeys::None, latinLayout());
}

bool KeyRouter::belongsToWindow(QObject* watched) const {
  if(m_window.isNull()) {
    return true;
  }
  if(watched == m_window) {
    return true;
  }
  if(const auto* item = qobject_cast<QQuickItem*>(watched)) {
    return static_cast<QObject*>(item->window()) == m_window.data();
  }
  return false;
}

bool KeyRouter::latinLayout() const {
  if(m_layout == QLatin1String("latin")) {
    return true;
  }
  if(m_layout == QLatin1String("other")) {
    return false;
  }
  const QInputMethod* im = QGuiApplication::inputMethod();
  if(im == nullptr) {
    return true;
  }
  const QLocale::Script s = im->locale().script();
  return s == QLocale::LatinScript || s == QLocale::AnyScript;
}

QString KeyRouter::callHandler(const QStringList& ids, bool dry) {
  if(ids.isEmpty() || !m_handler.isCallable()) {
    return {};
  }
  QJSValue fn = m_handler;
  const QJSValue r = fn.call({QJSValue(ids.join(QLatin1Char(','))), QJSValue(dry)});
  if(r.isError()) {
    qWarning("KeyRouter: handler threw: %s", qPrintable(r.toString()));
    return {};
  }
  if(r.isString()) {
    return r.toString();
  }
  return r.toBool() ? ids.first() : QString();
}

bool KeyRouter::decide(QKeyEvent* ke, bool focusTyping) {
  heap::keys::KeyInput in;
  in.key = ke->key();
  in.modifiers = ke->modifiers();
  in.text = ke->text();
  in.nativeVirtualKey = ke->nativeVirtualKey();
  in.nativeScanCode = ke->nativeScanCode();
  const bool latin = latinLayout();
  const QString chord = heap::keys::chordFor(in, heap::keys::nativeKeysFor(QGuiApplication::platformName()), latin);
  if(chord.isEmpty()) {
    return false;  // a modifier on its own: a prefix keeps waiting
  }
  const bool bare = heap::keys::isBareChord(chord);
  if(!ke->isAutoRepeat() && (!focusTyping || !bare)) {
    emit chordPressed(chord);
  }

  if(!m_pending.isEmpty()) {
    if(ke->isAutoRepeat()) {
      return true;
    }
    const QString seq = m_pending + QStringLiteral(", ") + chord;
    cancel();
    if(ke->key() == Qt::Key_Escape) {
      return true;
    }
    QStringList ids;
    for(const Binding& b : std::as_const(m_parsed)) {
      if(b.sequence == seq) {
        ids << b.id;
      }
    }
    callHandler(ids, false);
    // A second key that continues nothing is dropped, as in Vim.
    return true;
  }

  // A single letter is the field's while the person types (keymap rule 1).
  // A function key types nothing: F6 is how one leaves the field (APP-277).
  const bool functionKey = ke->key() >= Qt::Key_F1 && ke->key() <= Qt::Key_F35;
  if(focusTyping && bare && !functionKey) {
    return false;
  }

  QStringList prefixed;
  for(const Binding& b : std::as_const(m_parsed)) {
    if(heap::keys::isPrefixOf(chord, b.sequence)) {
      prefixed << b.id;
    }
  }
  if(!prefixed.isEmpty() && !callHandler(prefixed, true).isEmpty()) {
    if(!ke->isAutoRepeat()) {
      setPending(chord);
      m_timeout.start();
    }
    return true;
  }

  // The same key read as the layout typed it: a Latin layout's own chord is
  // already the Qt Shortcut's to take.
  heap::keys::KeyInput plain = in;
  plain.nativeVirtualKey = 0;
  plain.nativeScanCode = 0;
  const bool remapped = heap::keys::chordFor(plain, heap::keys::NativeKeys::None, true) != chord;
  QStringList ids;
  for(const Binding& b : std::as_const(m_parsed)) {
    if(b.sequence != chord) {
      continue;
    }
    if(!b.router && !remapped && m_qtOwned.contains(b.id)) {
      continue;
    }
    ids << b.id;
  }
  return !callHandler(ids, false).isEmpty();
}

bool KeyRouter::eventFilter(QObject* watched, QEvent* event) {
  const QEvent::Type type = event->type();
  if(!m_enabled || (type != QEvent::ShortcutOverride && type != QEvent::KeyPress)) {
    return QObject::eventFilter(watched, event);
  }
  auto* ke = static_cast<QKeyEvent*>(event);
  if(type == QEvent::ShortcutOverride) {
    if(!belongsToWindow(watched)) {
      return QObject::eventFilter(watched, event);
    }
    m_seenKey = ke->key();
    m_takenKey = 0;
    const bool typing = heap::platform::AltGrGuard::isEditableText(QGuiApplication::focusObject());
    if(decide(ke, typing)) {
      m_takenKey = ke->key();
      ke->accept();
      return true;
    }
    return QObject::eventFilter(watched, event);
  }
  // KeyPress: looked at once, where the window receives it, before its focus
  // item (and TypeAhead) does.
  if(!watched->isWindowType() || !belongsToWindow(watched)) {
    return QObject::eventFilter(watched, event);
  }
  if(m_takenKey != 0 && ke->key() == m_takenKey) {
    m_takenKey = 0;
    m_seenKey = 0;
    return true;
  }
  if(m_seenKey != 0 && ke->key() == m_seenKey) {
    m_seenKey = 0;
    return QObject::eventFilter(watched, event);
  }
  // No ShortcutOverride came first (the shortcut map was mid-sequence, or a
  // platform that skips it): decide here.
  const bool typing = heap::platform::AltGrGuard::isEditableText(QGuiApplication::focusObject());
  if(decide(ke, typing)) {
    return true;
  }
  return QObject::eventFilter(watched, event);
}
