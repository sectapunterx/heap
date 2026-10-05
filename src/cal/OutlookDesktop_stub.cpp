// Outside Windows there is no desktop Outlook to ask (see OutlookDesktop.h).

#include "cal/OutlookDesktop.h"

namespace heap::cal {

bool outlookDesktopAvailable() {
  return false;
}

OutlookRead readOutlookCalendar(const QDateTime& /*from*/, const QDateTime& /*to*/) {
  OutlookRead out;
  out.error = QStringLiteral("Outlook on this computer is read on Windows only");
  return out;
}

}  // namespace heap::cal
