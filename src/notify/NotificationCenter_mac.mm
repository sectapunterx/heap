#include "NotificationCenter.h"

#include <QCryptographicHash>
#include <QMetaObject>
#include <QSet>
#include <QString>

#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>

// macOS notifications with buttons (APP-155): UNUserNotificationCenter, one
// category per set of buttons, and a delegate that hands clicks back to the
// Qt thread. Needs a real .app bundle (an identifier) — a bare binary, such as
// a test executable, gets nullptr and the tray balloon instead.
//
// Built without ARC, like the rest of heap's Objective-C++: every alloc has
// its release.

namespace heap::notify {
std::unique_ptr<NotificationCenter> createTrayFallback(QObject* parent);
}

// What the delegate reports: a click on the notification, on a button, or the
// notification closed.
enum class HeapNotifyResponse { Activated, Action, Dismissed };

@interface HeapNotificationDelegate : NSObject <UNUserNotificationCenterDelegate>
- (instancetype)initWithOwner:(heap::notify::NotificationCenter*)owner;
- (void)detach;
@end

@implementation HeapNotificationDelegate {
  heap::notify::NotificationCenter* _owner;
}

- (instancetype)initWithOwner:(heap::notify::NotificationCenter*)owner {
  self = [super init];
  if(self) {
    _owner = owner;
  }
  return self;
}

- (void)detach {
  _owner = nullptr;
}

// Shown also while heap is in front: the reminder is still the point.
- (void)userNotificationCenter:(UNUserNotificationCenter*)center
       willPresentNotification:(UNNotification*)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
  (void)center;
  (void)notification;
  completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList | UNNotificationPresentationOptionSound);
}

// May arrive on any thread; the signal is emitted on the owner's.
- (void)userNotificationCenter:(UNUserNotificationCenter*)center
    didReceiveNotificationResponse:(UNNotificationResponse*)response
             withCompletionHandler:(void (^)(void))completionHandler {
  (void)center;
  heap::notify::NotificationCenter* owner = _owner;
  if(owner != nullptr) {
    const QString notificationId = QString::fromNSString(response.notification.request.identifier);
    const QString actionId = QString::fromNSString(response.actionIdentifier);
    HeapNotifyResponse kind = HeapNotifyResponse::Action;
    if([response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier]) {
      kind = HeapNotifyResponse::Activated;
    } else if([response.actionIdentifier isEqualToString:UNNotificationDismissActionIdentifier]) {
      kind = HeapNotifyResponse::Dismissed;
    }
    QMetaObject::invokeMethod(
        owner,
        [owner, notificationId, actionId, kind]() {
          switch(kind) {
            case HeapNotifyResponse::Activated:
              emit owner->activated(notificationId);
              break;
            case HeapNotifyResponse::Dismissed:
              emit owner->dismissed(notificationId);
              break;
            case HeapNotifyResponse::Action:
              emit owner->actionInvoked(notificationId, actionId);
              break;
          }
        },
        Qt::QueuedConnection);
  }
  completionHandler();
}

@end

namespace heap::notify {

namespace {

class MacNotifyBackend : public NotificationCenter {
 public:
  explicit MacNotifyBackend(QObject* parent) : NotificationCenter(parent), m_tray(createTrayFallback(this)) {
    // The menu-bar icon stays: it is heap's presence while the window is hidden.
    connect(m_tray.get(), &NotificationCenter::showWindowRequested, this, &NotificationCenter::showWindowRequested);
    connect(m_tray.get(), &NotificationCenter::quitRequested, this, &NotificationCenter::quitRequested);
    connect(m_tray.get(), &NotificationCenter::activated, this, &NotificationCenter::activated);

    m_delegate = [[HeapNotificationDelegate alloc] initWithOwner:this];
    m_categories = [[NSMutableSet alloc] init];
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = m_delegate;
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                          completionHandler:^(BOOL granted, NSError* error) {
                            (void)granted;
                            (void)error;
                          }];
  }

  ~MacNotifyBackend() override {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    if(center.delegate == m_delegate) {
      center.delegate = nil;
    }
    [m_delegate detach];
    [m_delegate release];
    [m_categories release];
  }

  MacNotifyBackend(const MacNotifyBackend&) = delete;
  MacNotifyBackend& operator=(const MacNotifyBackend&) = delete;

  void post(const Notification& n) override {
    UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
    content.title = n.title.toNSString();
    content.body = n.body.toNSString();
    content.sound = [UNNotificationSound defaultSound];
    if(!n.actions.isEmpty()) {
      content.categoryIdentifier = categoryFor(n.actions);
    }
    UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:n.id.toNSString() content:content trigger:nil];
    [content release];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
  }

  void dismiss(const QString& id) override {
    NSArray<NSString*>* ids = @[ id.toNSString() ];
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    [center removeDeliveredNotificationsWithIdentifiers:ids];
    [center removePendingNotificationRequestsWithIdentifiers:ids];
  }

  bool supportsActions() const override {
    return true;
  }

 private:
  // A category per distinct set of buttons (ids and labels: the labels follow
  // the language and the snooze settings), registered once.
  NSString* categoryFor(const QVector<NotificationAction>& actions) {
    QByteArray key;
    for(const NotificationAction& a : actions) {
      key += a.id.toUtf8() + '=' + a.label.toUtf8() + '|';
    }
    const QString categoryId =
        QStringLiteral("heap.") + QString::fromLatin1(QCryptographicHash::hash(key, QCryptographicHash::Md5).toHex().left(12));
    if(!m_categoryIds.contains(categoryId)) {
      NSMutableArray* buttons = [NSMutableArray array];
      for(const NotificationAction& a : actions) {
        // "Open" brings heap forward; the snoozes act from the banner.
        const UNNotificationActionOptions options =
            a.id == QStringLiteral("open") ? UNNotificationActionOptionForeground : UNNotificationActionOptionNone;
        [buttons addObject:[UNNotificationAction actionWithIdentifier:a.id.toNSString() title:a.label.toNSString() options:options]];
      }
      UNNotificationCategory* category = [UNNotificationCategory categoryWithIdentifier:categoryId.toNSString()
                                                                                actions:buttons
                                                                      intentIdentifiers:@[]
                                                                                options:UNNotificationCategoryOptionCustomDismissAction];
      [m_categories addObject:category];
      [[UNUserNotificationCenter currentNotificationCenter] setNotificationCategories:m_categories];
      m_categoryIds.insert(categoryId);
    }
    return categoryId.toNSString();
  }

  std::unique_ptr<NotificationCenter> m_tray;
  HeapNotificationDelegate* m_delegate = nil;
  NSMutableSet<UNNotificationCategory*>* m_categories = nil;
  QSet<QString> m_categoryIds;
};

}  // namespace

std::unique_ptr<NotificationCenter> createMacNative(QObject* parent) {
  // UNUserNotificationCenter throws for a process without a bundle identifier.
  if([[NSBundle mainBundle] bundleIdentifier] == nil) {
    return nullptr;
  }
  return std::make_unique<MacNotifyBackend>(parent);
}

}  // namespace heap::notify
