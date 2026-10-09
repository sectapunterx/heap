#pragma once

#include <QString>
#include <QStringList>

// The views Main.qml can show, by the name AppController.currentView carries.
// One list for the --view flag, setCurrentView() and the value read back from
// state.json, so a typo can never leave the content area blank (PLAT-8).
namespace heap::views {

inline const QStringList& all() {
  static const QStringList names = {QStringLiteral("today"),
                                    QStringLiteral("board"),
                                    QStringLiteral("list"),
                                    // The calendar lens at the day zoom (APP-264).
                                    QStringLiteral("day"),
                                    QStringLiteral("week"),
                                    QStringLiteral("month"),
                                    QStringLiteral("docs"),
                                    QStringLiteral("notes"),
                                    QStringLiteral("settings")};
  return names;
}

// The views 0.8.0 had and the sheets replaced (DG-161, DG-162): the
// timeline is the list, the archive is the list with "is:archived". A name
// from an older state.json, a saved view or --view still lands somewhere.
inline QString canonical(const QString& name) {
  if(name == QStringLiteral("timeline") || name == QStringLiteral("archive")) {
    return QStringLiteral("list");
  }
  // The 0.7 Docs catalogue is part of the Knowledge screen since 0.8.1
  // (DG-070): "docs" is still accepted (a saved view, --view docs, Ctrl+4)
  // and lands there.
  if(name == QStringLiteral("docs")) {
    return QStringLiteral("notes");
  }
  return name;
}

inline bool isKnown(const QString& name) {
  return all().contains(canonical(name));
}

// heap 2 (APP-258): the sidebar has four places, and each view belongs to
// one. Board, list and the calendars are lenses of Tasks;
// notes and docs are Knowledge.
inline const QStringList& sections() {
  static const QStringList names = {
      QStringLiteral("today"), QStringLiteral("tasks"), QStringLiteral("knowledge"), QStringLiteral("settings")};
  return names;
}

inline QString sectionOf(const QString& view) {
  if(view == QStringLiteral("today") || view == QStringLiteral("settings")) {
    return view;
  }
  if(view == QStringLiteral("notes") || view == QStringLiteral("docs")) {
    return QStringLiteral("knowledge");
  }
  return QStringLiteral("tasks");
}

// Where a section opens the first time, before it has a last view.
inline QString defaultViewOf(const QString& section) {
  if(section == QStringLiteral("tasks")) {
    return QStringLiteral("board");
  }
  if(section == QStringLiteral("knowledge")) {
    return QStringLiteral("notes");
  }
  return sections().contains(section) ? section : QStringLiteral("today");
}

}  // namespace heap::views
