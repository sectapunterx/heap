#pragma once

#include <QString>

#include <cstdint>

// Focus mode (APP-160): while it is on, notifications are held back — the
// same holding quiet hours do — and handed over only when the user asks, once
// it ends. A meeting or the standup still gets through unless the user said
// otherwise ("let meetings through", on by default). It never books a
// calendar block and never decides anything on its own.
namespace heap::safety {

enum class Delivery : std::uint8_t {
  Deliver,
  Hold,
};

// A meeting or the standup: something the user agreed to attend at a time.
inline bool isAppointment(const QString& kind) {
  return kind == QLatin1String("meeting") || kind == QLatin1String("standup");
}

// What happens to a notification of `kind` while focus mode is `immersed`.
// Quiet hours are judged separately, by the caller, exactly as before.
inline Delivery immersionDelivery(const QString& kind, bool immersed, bool passMeetings) {
  if(!immersed) {
    return Delivery::Deliver;
  }
  return isAppointment(kind) && passMeetings ? Delivery::Deliver : Delivery::Hold;
}

// Whole minutes in focus, for the indicator and the closing toast.
inline int immersionMinutes(qint64 seconds) {
  return seconds <= 0 ? 0 : static_cast<int>(seconds / 60);
}

}  // namespace heap::safety
