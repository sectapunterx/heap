#include "TypeAhead.h"

#include "platform/AltGrGuard.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QKeyEvent>

TypeAhead::TypeAhead(QObject* parent) : QObject(parent) {
  QCoreApplication::instance()->installEventFilter(this);
}

TypeAhead::~TypeAhead() {
  if(QCoreApplication::instance() != nullptr) {
    QCoreApplication::instance()->removeEventFilter(this);
  }
}

void TypeAhead::setEnabled(bool on) {
  if(m_enabled == on) {
    return;
  }
  m_enabled = on;
  emit enabledChanged();
}

QString TypeAhead::startingText(const QKeyEvent& event, const QObject* focus) {
  const Qt::KeyboardModifiers mods = event.modifiers() & ~(Qt::ShiftModifier | Qt::KeypadModifier);
  if(mods != Qt::NoModifier) {
    return {};
  }
  QString text = event.text();
  if(text.size() != 1 || !text.at(0).isPrint() || text.at(0).isSpace()) {
    return {};
  }
  if(heap::platform::AltGrGuard::isEditableText(focus)) {
    return {};
  }
  return text;
}

bool TypeAhead::eventFilter(QObject* watched, QEvent* event) {
  // The window sees a key press first, then hands it to its focus item; take
  // it at the window so it is looked at once.
  if(m_enabled && event->type() == QEvent::KeyPress && watched->isWindowType()) {
    const QString text = startingText(*static_cast<QKeyEvent*>(event), QGuiApplication::focusObject());
    if(!text.isEmpty()) {
      emit typed(text);
      return true;
    }
  }
  return QObject::eventFilter(watched, event);
}
