#pragma once

#include <QDate>
#include <QDateTime>
#include <QString>
#include <QStringList>
#include <QVector>

// One day as the Today screen and the calendars draw it (APP-260/247): the
// meetings and the task blocks by the hour, the free windows between them as
// a fact, and how much of the working day is taken. A pure function of what
// it is handed and `now`: it shows, it never places anything.
namespace heap::plan {

// A meeting occurrence that touches the day. Hours are wall-clock, 0..24;
// a meeting that crosses midnight has `endDate` after `date`.
struct EventIn {
  QString id;
  QString title;
  QString type;  // none / standup / oneone / sync / focus
  QString taskId;
  QString attendees;
  QDate date;
  QDate endDate;
  double start = 0;
  double end = 0;
  bool allDay = false;
  QString occurrence;  // the occurrence's date, ISO, for opening it
};

// A task with a time on the day.
struct TaskIn {
  QString id;
  QString title;
  QString status;
  QString category;  // the column's stage
  QDateTime scheduledAt;
  int minutes = 60;     // the block's length: the estimate, else the setting
  QString profileName;  // when the day shows every profile
};

struct Block {
  QString kind;  // "meeting" or "task"
  QString id;
  QString title;
  QString eventType;
  QString status;
  QString category;
  QString attendees;
  QString occurrence;
  QString profileName;
  double start = 0;  // hours on this day, may run below 0 / past 24 for display
  double end = 0;
  bool past = false;
  bool fromPrevDay = false;  // began the day before ("since 23:00")
  bool toNextDay = false;    // runs into the next day ("until 01:00")
  QStringList overlapsWith;  // titles of what shares its time
};

struct Gap {
  double start = 0;
  double end = 0;
};

// Minutes, each counted once however many things overlap.
struct Load {
  int meetings = 0;
  int tasks = 0;     // task time not already under a meeting
  int free = 0;      // working time left
  int overWork = 0;  // planned beyond the working hours
};

struct Day {
  QDate date;
  bool workday = true;
  double workStart = 9;
  double workEnd = 19;
  // The hours the list spans: the working day, widened for anything outside.
  double fromHour = 9;
  double toHour = 19;
  QVector<Block> allDay;  // all-day and multi-day meetings, above the hours
  QVector<Block> blocks;  // by start time
  QVector<Gap> free;      // working-time gaps of at least `minGap` minutes
  Load load;
};

Day buildDay(const QDate& date,
             const QDateTime& now,
             const QVector<EventIn>& events,
             const QVector<TaskIn>& tasks,
             double workStart,
             double workEnd,
             bool workday,
             int minGap = 30);

}  // namespace heap::plan
