#pragma once

#include <QString>
#include <QStringList>

// The views Main.qml can show, by the name AppController.currentView carries.
// One list for the --view flag, setCurrentView() and the value read back from
// state.json, so a typo can never leave the content area blank (PLAT-8).
namespace heap::views {

inline const QStringList& all() {
  static const QStringList names = {QStringLiteral("board"),
                                    QStringLiteral("timeline"),
                                    QStringLiteral("week"),
                                    QStringLiteral("month"),
                                    QStringLiteral("docs"),
                                    QStringLiteral("notes"),
                                    QStringLiteral("archive"),
                                    QStringLiteral("settings")};
  return names;
}

inline bool isKnown(const QString& name) {
  return all().contains(name);
}

}  // namespace heap::views
