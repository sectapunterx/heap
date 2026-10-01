#include "AltGrGuard.h"

#include <QGuiApplication>
#include <QKeyEvent>
#include <QVariant>

namespace heap::platform {

bool AltGrGuard::isAltGrText(const QKeyEvent& event) {
  const Qt::KeyboardModifiers mods = event.modifiers();
  if(!mods.testFlag(Qt::ControlModifier) || !mods.testFlag(Qt::AltModifier)) {
    return false;
  }
  const QString text = event.text();
  if(text.isEmpty()) {
    return false;
  }
  for(const QChar ch : text) {
    if(!ch.isPrint()) {
      return false;
    }
  }
  return true;
}

bool AltGrGuard::isEditableText(const QObject* item) {
  if(item == nullptr) {
    return false;
  }
  if(!item->inherits("QQuickTextInput") && !item->inherits("QQuickTextEdit")) {
    return false;
  }
  return !item->property("readOnly").toBool();
}

bool AltGrGuard::eventFilter(QObject* watched, QEvent* event) {
  if(event->type() == QEvent::ShortcutOverride && isAltGrText(*static_cast<QKeyEvent*>(event)) &&
     isEditableText(QGuiApplication::focusObject())) {
    // Accepting the override is how a widget claims a key from the shortcut
    // map; the key press that follows reaches the field and types the text.
    event->accept();
    return true;
  }
  return QObject::eventFilter(watched, event);
}

}  // namespace heap::platform
