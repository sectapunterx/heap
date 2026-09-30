#include "ChronoLocale.h"

namespace heap::chrono {

namespace {

ChronoLocale buildRussian() {
  ChronoLocale loc;

  // ── Weekdays (full, short, and abbreviated forms) ──
  // Plus the cases a deadline or a routine is written in ("до понедельника",
  // "к пятнице", "по средам"), and the weekend, which starts on Saturday.
  const struct {
    const char* name;
    int iso;
  } weekdays[] = {
      {"понедельник", 1},  {"пн", 1},           {"понед", 1},
      {"вторник", 2},      {"вт", 2},           {"среда", 3},
      {"среду", 3},        {"среды", 3},        {"ср", 3},
      {"четверг", 4},      {"чт", 4},           {"четв", 4},
      {"пятница", 5},      {"пятницу", 5},      {"пятницы", 5},
      {"пт", 5},           {"суббота", 6},      {"субботу", 6},
      {"субботы", 6},      {"сб", 6},           {"воскресенье", 7},
      {"воскресение", 7},  {"вс", 7},           {"воскр", 7},
      {"понедельника", 1}, {"понедельнику", 1}, {"понедельникам", 1},
      {"вторника", 2},     {"вторнику", 2},     {"вторникам", 2},
      {"среде", 3},        {"средам", 3},       {"четверга", 4},
      {"четвергу", 4},     {"четвергам", 4},    {"пятнице", 5},
      {"пятницам", 5},     {"субботе", 6},      {"субботам", 6},
      {"воскресенья", 7},  {"воскресенью", 7},  {"воскресеньям", 7},
      {"выходные", 6},     {"выходных", 6},
  };

  for(const auto& w : weekdays) {
    loc.weekdayNames.insert(QString::fromUtf8(w.name), w.iso);
  }

  // ── Months (nominative + genitive, both common) ──
  const struct {
    const char* name;
    int m;
  } months[] = {
      {"январь", 1},   {"января", 1},   {"янв", 1},      {"февраль", 2},  {"февраля", 2},  {"фев", 2},     {"март", 3},    {"марта", 3},
      {"мар", 3},      {"апрель", 4},   {"апреля", 4},   {"апр", 4},      {"май", 5},      {"мая", 5},     {"июнь", 6},    {"июня", 6},
      {"июн", 6},      {"июль", 7},     {"июля", 7},     {"июл", 7},      {"август", 8},   {"августа", 8}, {"авг", 8},     {"сентябрь", 9},
      {"сентября", 9}, {"сен", 9},      {"сент", 9},     {"октябрь", 10}, {"октября", 10}, {"окт", 10},    {"ноябрь", 11}, {"ноября", 11},
      {"ноя", 11},     {"декабрь", 12}, {"декабря", 12}, {"дек", 12},
  };

  for(const auto& mo : months) {
    loc.monthNames.insert(QString::fromUtf8(mo.name), mo.m);
  }

  // ── Relative adjectives ──
  loc.relativeAdjectives.insert(QString::fromUtf8("сегодня"), 0);
  loc.relativeAdjectives.insert(QString::fromUtf8("сейчас"), 0);
  loc.relativeAdjectives.insert(QString::fromUtf8("завтра"), 1);
  loc.relativeAdjectives.insert(QString::fromUtf8("послезавтра"), 2);
  loc.relativeAdjectives.insert(QString::fromUtf8("вчера"), -1);
  loc.relativeAdjectives.insert(QString::fromUtf8("позавчера"), -2);

  // ── Unit names → days ──
  const struct {
    const char* name;
    int days;
  } units[] = {
      {"день", 1},   {"дням", 1},   {"дня", 1},    {"дней", 1},  {"д", 1},      {"дн", 1},      {"неделя", 7},
      {"недели", 7}, {"недель", 7}, {"неделю", 7}, {"нед", 7},   {"месяц", 30}, {"месяца", 30}, {"месяцев", 30},
      {"мес", 30},   {"год", 365},  {"года", 365}, {"лет", 365}, {"г", 365},
  };

  for(const auto& u : units) {
    loc.unitToDays.insert(QString::fromUtf8(u.name), u.days);
  }

  auto fillSet = [](QHash<QString, int>& h, std::initializer_list<const char*> names) {
    for(const char* n : names) {
      h.insert(QString::fromUtf8(n), 1);
    }
  };
  fillSet(loc.weekUnits, {"неделя", "недели", "недель", "неделю", "неделе", "нед"});
  fillSet(loc.monthUnits, {"месяц", "месяца", "месяцев", "месяце", "мес"});
  fillSet(loc.yearUnits, {"год", "года", "году", "лет", "г"});

  // ── Prefixes / connectors ──
  loc.relPrefixes << QString::fromUtf8("через");
  loc.nextAdjectives << QString::fromUtf8("след") << QString::fromUtf8("следующий") << QString::fromUtf8("следующая")
                     << QString::fromUtf8("следующую") << QString::fromUtf8("следующее") << QString::fromUtf8("буд")
                     << QString::fromUtf8("будущий")
                     << QString::fromUtf8("будущую")
                     // "на следующей неделе", "в следующем месяце", "в следующем году"
                     << QString::fromUtf8("следующей") << QString::fromUtf8("следующем") << QString::fromUtf8("будущей")
                     << QString::fromUtf8("будущем");
  loc.thisAdjectives << QString::fromUtf8("эта") << QString::fromUtf8("этот") << QString::fromUtf8("этой") << QString::fromUtf8("эту")
                     << QString::fromUtf8("текущий") << QString::fromUtf8("текущая");
  loc.everyAdjectives << QString::fromUtf8("каждый") << QString::fromUtf8("каждая") << QString::fromUtf8("каждую")
                      << QString::fromUtf8("каждое") << QString::fromUtf8("по");
  loc.atWords << QString::fromUtf8("в") << QString::fromUtf8("во") << QString::fromUtf8("на");
  loc.fromWords << QString::fromUtf8("с") << QString::fromUtf8("со");
  loc.toWords << QString::fromUtf8("до") << QString::fromUtf8("по");
  loc.hourSuffixes << QString::fromUtf8("ч") << QString::fromUtf8("часов") << QString::fromUtf8("часа") << QString::fromUtf8("час");
  loc.suffixes << QString::fromUtf8("назад");

  loc.prefixes << QString::fromUtf8("через") << QString::fromUtf8("в") << QString::fromUtf8("во") << QString::fromUtf8("на")
               << QString::fromUtf8("след") << QString::fromUtf8("следующий") << QString::fromUtf8("каждый") << QString::fromUtf8("каждую")
               << QString::fromUtf8("каждое");

  fillSet(loc.hourUnits, {"час", "часа", "часов", "ч"});
  fillSet(loc.minuteUnits, {"минуту", "минуты", "минут", "мин"});
  loc.namedTimes.insert(QString::fromUtf8("полдень"), 12 * 60);
  loc.namedTimes.insert(QString::fromUtf8("полдня"), 12 * 60);
  // Parts of the day, at the hour a calendar would put them. Adverbs only:
  // the nouns ("вечер", "обед") are as often what a task is about.
  loc.namedTimes.insert(QString::fromUtf8("утром"), 9 * 60);
  loc.namedTimes.insert(QString::fromUtf8("днём"), 13 * 60);
  loc.namedTimes.insert(QString::fromUtf8("днем"), 13 * 60);
  loc.namedTimes.insert(QString::fromUtf8("вечером"), 19 * 60);
  loc.namedTimes.insert(QString::fromUtf8("полночь"), 0);
  loc.endWords << QString::fromUtf8("конец") << QString::fromUtf8("конца");
  loc.leadWords << QString::fromUtf8("в") << QString::fromUtf8("во") << QString::fromUtf8("на") << QString::fromUtf8("к")
                << QString::fromUtf8("до");

  loc.amSuffix.clear();
  loc.pmSuffix.clear();

  loc.timeRe = QRegularExpression(QStringLiteral("^(\\d{1,2})(?::(\\d{2}))?$"));
  loc.numericDateRe =
      QRegularExpression(QStringLiteral("^(\\d{4})-(\\d{1,2})-(\\d{1,2})$"
                                        "|^(\\d{1,2})\\.(\\d{1,2})(?:\\.(\\d{2,4}))?$"
                                        "|^(\\d{1,2})/(\\d{1,2})(?:/(\\d{2,4}))?$"));

  return loc;
}

}  // namespace

const ChronoLocale& russianLocale() {
  static const ChronoLocale loc = buildRussian();
  return loc;
}

}  // namespace heap::chrono
