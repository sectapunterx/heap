// The Linux global hotkey (APP-171). Two backends, picked by the session:
//
//   X11      → xcb_grab_key on the root window, through the xcb connection Qt
//              already has open, and a native event filter for the key press.
//   Wayland  → the org.freedesktop.portal.GlobalShortcuts desktop portal over
//              D-Bus: heap asks for the binding, the desktop shows the user a
//              dialog to confirm (or change) it and reports each press.
//
// Wayland without the portal (or another session type) gets the no-op
// backend; Settings then says how to bind `heap --capture` in the desktop's
// own keyboard settings instead.
#include "platform/GlobalHotkey.h"
#include "platform/X11Keys.h"

#include <QAbstractNativeEventFilter>
#include <QByteArray>
#include <QCoreApplication>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QGuiApplication>
#include <QHash>
#include <QList>
#include <QMetaType>
#include <QUuid>
#include <QVariantMap>

#include <cstdlib>
#include <memory>
#include <utility>
#include <vector>

#if defined(HEAP_HAVE_XCB) && QT_CONFIG(xcb)
#define HEAP_X11_HOTKEY
#include <xcb/xcb.h>
#endif

namespace heap::platform {

namespace {

#ifdef HEAP_X11_HOTKEY

// What the X server hands back is malloc'ed and must be freed with free().
struct XcbFree {
  void operator()(void* p) const {
    std::free(p);  // NOLINT(cppcoreguidelines-no-malloc)
  }
};

template<typename T>
using XcbReply = std::unique_ptr<T, XcbFree>;

class X11Hotkey : public GlobalHotkey, public QAbstractNativeEventFilter {
 public:
  X11Hotkey(xcb_connection_t* connection, QObject* parent) : GlobalHotkey(parent), connection_(connection) {
    const xcb_setup_t* setup = xcb_get_setup(connection_);
    const xcb_screen_iterator_t screens = xcb_setup_roots_iterator(setup);
    root_ = screens.data != nullptr ? screens.data->root : 0;
    if(auto* app = QCoreApplication::instance()) {
      app->installNativeEventFilter(this);
    }
  }

  ~X11Hotkey() override {
    unregisterAll();
    if(auto* app = QCoreApplication::instance()) {
      app->removeNativeEventFilter(this);
    }
  }

  X11Hotkey(const X11Hotkey&) = delete;
  X11Hotkey& operator=(const X11Hotkey&) = delete;

  QString backend() const override {
    return QStringLiteral("x11");
  }

  bool registerHotkey(int id, const QString& seq) override {
    unregister(id);
    int key = 0;
    int mods = 0;
    x11::KeyGrab grab;
    if(root_ == 0 || !decodeSequence(seq, key, mods) || !x11::toKeyGrab(key, mods, grab)) {
      return false;
    }
    const std::uint8_t keycode = keycodeFor(grab.keysym);
    if(keycode == 0) {
      return false;
    }
    // Every lock-key state, or the hotkey dies with Num Lock on. The grab is
    // checked: another program holding the combination is a BadAccess, and
    // then the in-app shortcut stays the only way in.
    const QList<std::uint16_t> variants = x11::lockVariants(grab.mods);
    bool ok = true;
    for(const std::uint16_t m : variants) {
      const xcb_void_cookie_t cookie = xcb_grab_key_checked(connection_, 1, root_, m, keycode, XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
      const XcbReply<xcb_generic_error_t> error(xcb_request_check(connection_, cookie));
      if(error) {
        ok = false;
      }
    }
    if(!ok) {
      for(const std::uint16_t m : variants) {
        xcb_ungrab_key(connection_, keycode, root_, m);
      }
      xcb_flush(connection_);
      return false;
    }
    xcb_flush(connection_);
    grabs_.insert(id, Grab{keycode, grab.mods});
    return true;
  }

  void unregister(int id) override {
    const auto it = grabs_.constFind(id);
    if(it == grabs_.constEnd()) {
      return;
    }
    ungrab(*it);
    grabs_.erase(it);
    xcb_flush(connection_);
  }

  void unregisterAll() override {
    for(const Grab& g : std::as_const(grabs_)) {
      ungrab(g);
    }
    grabs_.clear();
    xcb_flush(connection_);
  }

  bool nativeEventFilter(const QByteArray& event_type, void* message, qintptr* /*result*/) override {
    if(event_type != "xcb_generic_event_t" || message == nullptr) {
      return false;
    }
    const auto* event = static_cast<const xcb_generic_event_t*>(message);
    constexpr std::uint8_t kSendEventBit = 0x80;
    if((event->response_type & static_cast<std::uint8_t>(~kSendEventBit)) != XCB_KEY_PRESS) {
      return false;
    }
    const auto* press = reinterpret_cast<const xcb_key_press_event_t*>(event);
    const std::uint16_t mods = x11::significantMods(press->state);
    for(auto it = grabs_.constBegin(); it != grabs_.constEnd(); ++it) {
      if(it->keycode == press->detail && it->mods == mods) {
        emit activated(it.key());
        return true;
      }
    }
    return false;
  }

 private:
  struct Grab {
    std::uint8_t keycode = 0;
    std::uint16_t mods = 0;
  };

  void ungrab(const Grab& g) const {
    for(const std::uint16_t m : x11::lockVariants(g.mods)) {
      xcb_ungrab_key(connection_, g.keycode, root_, m);
    }
  }

  // The keycode that types `keysym` on the keyboard as it is mapped now.
  std::uint8_t keycodeFor(std::uint32_t keysym) const {
    const xcb_setup_t* setup = xcb_get_setup(connection_);
    const int min = setup->min_keycode;
    const int count = setup->max_keycode - setup->min_keycode + 1;
    const xcb_get_keyboard_mapping_cookie_t cookie =
        xcb_get_keyboard_mapping(connection_, setup->min_keycode, static_cast<std::uint8_t>(count));
    const XcbReply<xcb_get_keyboard_mapping_reply_t> reply(xcb_get_keyboard_mapping_reply(connection_, cookie, nullptr));
    if(!reply) {
      return 0;
    }
    const xcb_keysym_t* syms = xcb_get_keyboard_mapping_keysyms(reply.get());
    const int length = xcb_get_keyboard_mapping_keysyms_length(reply.get());
    const std::vector<std::uint32_t> table(syms, syms + length);
    return x11::keycodeFor(table, reply->keysyms_per_keycode, min, keysym);
  }

  xcb_connection_t* connection_ = nullptr;
  xcb_window_t root_ = 0;
  QHash<int, Grab> grabs_;
};

xcb_connection_t* x11Connection() {
  auto* app = qobject_cast<QGuiApplication*>(QCoreApplication::instance());
  if(app == nullptr || QGuiApplication::platformName() != QLatin1String("xcb")) {
    return nullptr;
  }
  auto* x11 = app->nativeInterface<QNativeInterface::QX11Application>();
  return x11 != nullptr ? x11->connection() : nullptr;
}

#endif  // HEAP_X11_HOTKEY

// ── Wayland: the GlobalShortcuts desktop portal ─────────────────────────

constexpr QLatin1String kPortalService("org.freedesktop.portal.Desktop");
constexpr QLatin1String kPortalPath("/org/freedesktop/portal/desktop");
constexpr QLatin1String kShortcutsInterface("org.freedesktop.portal.GlobalShortcuts");
constexpr QLatin1String kRequestInterface("org.freedesktop.portal.Request");

// Whether the session bus has a desktop portal that does global shortcuts.
bool portalAvailable() {
  const QDBusConnection bus = QDBusConnection::sessionBus();
  if(!bus.isConnected() || bus.interface() == nullptr || !bus.interface()->isServiceRegistered(kPortalService).value()) {
    return false;
  }
  QDBusMessage get =
      QDBusMessage::createMethodCall(kPortalService, kPortalPath, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
  get << QString(kShortcutsInterface) << QStringLiteral("version");
  constexpr int kTimeoutMs = 1500;
  const QDBusMessage reply = bus.call(get, QDBus::Block, kTimeoutMs);
  return reply.type() == QDBusMessage::ReplyMessage;
}

}  // namespace

// One entry of BindShortcuts' a(sa{sv}).
struct PortalShortcut {
  QString id;
  QVariantMap properties;
};

QDBusArgument& operator<<(QDBusArgument& arg, const PortalShortcut& s) {
  arg.beginStructure();
  arg << s.id << s.properties;
  arg.endStructure();
  return arg;
}

const QDBusArgument& operator>>(const QDBusArgument& arg, PortalShortcut& s) {
  arg.beginStructure();
  arg >> s.id >> s.properties;
  arg.endStructure();
  return arg;  // NOLINT(bugprone-return-const-ref-from-parameter): QtDBus streaming shape
}

}  // namespace heap::platform

Q_DECLARE_METATYPE(heap::platform::PortalShortcut)

namespace heap::platform {

// The portal is asynchronous: CreateSession answers through a Request
// object's Response signal, and the desktop asks the user before it binds
// anything. registerHotkey() therefore records what is wanted and (re)binds
// the whole set once the session exists; a press arrives as Activated.
class PortalHotkey : public GlobalHotkey {
  Q_OBJECT
 public:
  explicit PortalHotkey(QObject* parent) : GlobalHotkey(parent) {
    qDBusRegisterMetaType<PortalShortcut>();
    qDBusRegisterMetaType<QList<PortalShortcut>>();
    QDBusConnection::sessionBus().connect(kPortalService,
                                          kPortalPath,
                                          kShortcutsInterface,
                                          QStringLiteral("Activated"),
                                          this,
                                          SLOT(onActivated(QDBusObjectPath, QString, qulonglong, QVariantMap)));
  }

  QString backend() const override {
    return QStringLiteral("portal");
  }

  bool registerHotkey(int id, const QString& seq) override {
    int key = 0;
    int mods = 0;
    const QString trigger = decodeSequence(seq, key, mods) ? x11::portalTrigger(key, mods) : QString();
    if(trigger.isEmpty()) {
      unregister(id);
      return false;
    }
    wanted_.insert(id, trigger);
    ensureSessionThenBind();
    return true;
  }

  void unregister(int id) override {
    // The portal has no "unbind one": the next BindShortcuts carries the
    // rest, and a press of a dropped id is ignored in onActivated.
    wanted_.remove(id);
  }

  void unregisterAll() override {
    wanted_.clear();
  }

 private slots:

  void onSessionResponse(uint response, const QVariantMap& results) {
    creating_ = false;
    if(response != 0) {
      return;  // the user or the desktop said no; the in-app shortcut remains
    }
    const QVariant handle = results.value(QStringLiteral("session_handle"));
    session_ = handle.canConvert<QDBusObjectPath>() && handle.metaType() == QMetaType::fromType<QDBusObjectPath>()
                   ? handle.value<QDBusObjectPath>().path()
                   : handle.toString();
    if(!session_.isEmpty()) {
      bind();
    }
  }

  void onActivated(const QDBusObjectPath& session, const QString& shortcut_id, qulonglong /*timestamp*/, const QVariantMap& /*options*/) {
    if(session.path() != session_) {
      return;
    }
    const QString prefix = QStringLiteral("heap-");
    if(!shortcut_id.startsWith(prefix)) {
      return;
    }
    bool ok = false;
    const int id = shortcut_id.mid(prefix.size()).toInt(&ok);
    if(ok && wanted_.contains(id)) {
      emit activated(id);
    }
  }

 private:
  // The object path a Request for `token` will have, so its Response can be
  // subscribed to before the call that creates it (no race).
  static QString requestPath(const QString& token) {
    QString sender = QDBusConnection::sessionBus().baseService();
    sender.remove(0, 1);  // the leading ':'
    sender.replace(QLatin1Char('.'), QLatin1Char('_'));
    return QStringLiteral("/org/freedesktop/portal/desktop/request/%1/%2").arg(sender, token);
  }

  static QString newToken() {
    return QStringLiteral("heap_") + QUuid::createUuid().toString(QUuid::Id128);
  }

  void ensureSessionThenBind() {
    if(!session_.isEmpty()) {
      bind();
      return;
    }
    if(creating_) {
      return;  // bound when the session arrives
    }
    creating_ = true;
    const QString token = newToken();
    QDBusConnection::sessionBus().connect(kPortalService,
                                          requestPath(token),
                                          kRequestInterface,
                                          QStringLiteral("Response"),
                                          this,
                                          SLOT(onSessionResponse(uint, QVariantMap)));
    QDBusMessage call = QDBusMessage::createMethodCall(kPortalService, kPortalPath, kShortcutsInterface, QStringLiteral("CreateSession"));
    const QVariantMap options{{QStringLiteral("handle_token"), token}, {QStringLiteral("session_handle_token"), newToken()}};
    call << options;
    QDBusConnection::sessionBus().asyncCall(call);
  }

  void bind() {
    QList<PortalShortcut> shortcuts;
    for(auto it = wanted_.constBegin(); it != wanted_.constEnd(); ++it) {
      shortcuts.append(PortalShortcut{.id = QStringLiteral("heap-%1").arg(it.key()),
                                      .properties = QVariantMap{{QStringLiteral("description"), QStringLiteral("lowkey: quick capture")},
                                                                {QStringLiteral("preferred_trigger"), it.value()}}});
    }
    QDBusMessage call = QDBusMessage::createMethodCall(kPortalService, kPortalPath, kShortcutsInterface, QStringLiteral("BindShortcuts"));
    call << QVariant::fromValue(QDBusObjectPath(session_)) << QVariant::fromValue(shortcuts) << QString()
         << QVariantMap{{QStringLiteral("handle_token"), newToken()}};
    QDBusConnection::sessionBus().asyncCall(call);
  }

  QHash<int, QString> wanted_;  // id -> preferred trigger
  QString session_;
  bool creating_ = false;
};

std::unique_ptr<GlobalHotkey> createLinuxHotkey(QObject* parent) {
#ifdef HEAP_X11_HOTKEY
  if(xcb_connection_t* connection = x11Connection()) {
    return std::make_unique<X11Hotkey>(connection, parent);
  }
#endif
  if(QGuiApplication::platformName().startsWith(QLatin1String("wayland")) && portalAvailable()) {
    return std::make_unique<PortalHotkey>(parent);
  }
  return nullptr;
}

}  // namespace heap::platform

#include "GlobalHotkey_linux.moc"
