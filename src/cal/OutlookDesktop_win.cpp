// The COM half of OutlookDesktop.h: asks the desktop Outlook for the default
// calendar's occurrences in a range. Plain IDispatch late binding, so the build
// needs no Outlook type library and no ActiveQt — only ole32/oleaut32, which
// every Windows has. Read-only: nothing here sets anything on an item.

#include "cal/OutlookDesktop.h"

#include <initializer_list>
#include <vector>

#include <objbase.h>
#include <oleauto.h>
#include <windows.h>

namespace heap::cal {

namespace {

// COM for this thread. Apartment-threaded, which is what Outlook's object
// model expects; balanced on scope exit.
struct ComScope {
  HRESULT hr;

  ComScope() : hr(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)) {
  }

  ~ComScope() {
    if(SUCCEEDED(hr)) {
      CoUninitialize();
    }
  }

  ComScope(const ComScope&) = delete;
  ComScope& operator=(const ComScope&) = delete;
};

struct Var {
  VARIANT v;

  Var() {
    VariantInit(&v);
  }

  ~Var() {
    VariantClear(&v);
  }

  Var(const Var&) = delete;
  Var& operator=(const Var&) = delete;
};

// An owned IDispatch*.
class Disp {
 public:
  Disp() = default;

  explicit Disp(IDispatch* p) : m_p(p) {
  }

  ~Disp() {
    reset();
  }

  Disp(const Disp&) = delete;
  Disp& operator=(const Disp&) = delete;

  Disp(Disp&& o) noexcept : m_p(o.m_p) {
    o.m_p = nullptr;
  }

  Disp& operator=(Disp&& o) noexcept {
    if(this != &o) {
      reset();
      m_p = o.m_p;
      o.m_p = nullptr;
    }
    return *this;
  }

  void reset() {
    if(m_p != nullptr) {
      m_p->Release();
      m_p = nullptr;
    }
  }

  [[nodiscard]] IDispatch* get() const {
    return m_p;
  }

  explicit operator bool() const {
    return m_p != nullptr;
  }

 private:
  IDispatch* m_p = nullptr;
};

QString hrText(HRESULT hr) {
  return QStringLiteral("0x%1").arg(static_cast<quint32>(hr), 8, 16, QLatin1Char('0'));
}

// obj.name(args…) or obj.name, by flags. Args are given first to last.
HRESULT invoke(IDispatch* obj, const wchar_t* name, WORD flags, VARIANT* result, std::initializer_list<const VARIANT*> args = {}) {
  if(obj == nullptr) {
    return E_POINTER;
  }
  DISPID id = 0;
  auto* n = const_cast<LPOLESTR>(name);
  HRESULT hr = obj->GetIDsOfNames(IID_NULL, &n, 1, LOCALE_USER_DEFAULT, &id);
  if(FAILED(hr)) {
    return hr;
  }
  // DISPPARAMS wants the arguments last to first.
  std::vector<VARIANT> rev;
  rev.reserve(args.size());
  for(auto it = std::rbegin(args); it != std::rend(args); ++it) {
    rev.push_back(**it);
  }
  DISPPARAMS params{};
  params.cArgs = static_cast<UINT>(rev.size());
  params.rgvarg = rev.empty() ? nullptr : rev.data();
  DISPID named = DISPID_PROPERTYPUT;
  if((flags & DISPATCH_PROPERTYPUT) != 0) {
    params.cNamedArgs = 1;
    params.rgdispidNamedArgs = &named;
  }
  return obj->Invoke(id, IID_NULL, LOCALE_USER_DEFAULT, flags, &params, result, nullptr, nullptr);
}

Disp getObject(IDispatch* obj, const wchar_t* name, WORD flags = DISPATCH_PROPERTYGET, std::initializer_list<const VARIANT*> args = {}) {
  Var r;
  if(FAILED(invoke(obj, name, flags, &r.v, args)) || r.v.vt != VT_DISPATCH || r.v.pdispVal == nullptr) {
    return {};
  }
  IDispatch* p = r.v.pdispVal;
  p->AddRef();
  return Disp(p);
}

QString getString(IDispatch* obj, const wchar_t* name) {
  Var r;
  if(FAILED(invoke(obj, name, DISPATCH_PROPERTYGET, &r.v)) || FAILED(VariantChangeType(&r.v, &r.v, 0, VT_BSTR)) || r.v.bstrVal == nullptr) {
    return {};
  }
  return QString::fromWCharArray(r.v.bstrVal, static_cast<qsizetype>(SysStringLen(r.v.bstrVal)));
}

bool getBool(IDispatch* obj, const wchar_t* name) {
  Var r;
  if(FAILED(invoke(obj, name, DISPATCH_PROPERTYGET, &r.v)) || FAILED(VariantChangeType(&r.v, &r.v, 0, VT_BOOL))) {
    return false;
  }
  return r.v.boolVal != VARIANT_FALSE;
}

int getInt(IDispatch* obj, const wchar_t* name) {
  Var r;
  if(FAILED(invoke(obj, name, DISPATCH_PROPERTYGET, &r.v)) || FAILED(VariantChangeType(&r.v, &r.v, 0, VT_I4))) {
    return -1;
  }
  return static_cast<int>(r.v.lVal);
}

// Outlook's DATE is local wall-clock time.
QDateTime getDate(IDispatch* obj, const wchar_t* name) {
  Var r;
  if(FAILED(invoke(obj, name, DISPATCH_PROPERTYGET, &r.v)) || FAILED(VariantChangeType(&r.v, &r.v, 0, VT_DATE))) {
    return {};
  }
  SYSTEMTIME st{};
  if(VariantTimeToSystemTime(r.v.date, &st) == 0) {
    return {};
  }
  return QDateTime(QDate(st.wYear, st.wMonth, st.wDay), QTime(st.wHour, st.wMinute, st.wSecond));
}

// Items.Restrict compares dates written the way the user's locale writes
// them — the documented form; an ISO string matches nothing on most locales.
QString restrictDate(const QDateTime& dt) {
  SYSTEMTIME st{};
  st.wYear = static_cast<WORD>(dt.date().year());
  st.wMonth = static_cast<WORD>(dt.date().month());
  st.wDay = static_cast<WORD>(dt.date().day());
  st.wHour = static_cast<WORD>(dt.time().hour());
  st.wMinute = static_cast<WORD>(dt.time().minute());
  wchar_t date[80] = {};
  wchar_t time[80] = {};
  GetDateFormatEx(LOCALE_NAME_USER_DEFAULT, DATE_SHORTDATE, &st, nullptr, date, 80, nullptr);
  GetTimeFormatEx(LOCALE_NAME_USER_DEFAULT, TIME_NOSECONDS, &st, nullptr, time, 80);
  return QString::fromWCharArray(date) + QLatin1Char(' ') + QString::fromWCharArray(time);
}

struct Bstr {
  VARIANT v;

  explicit Bstr(const QString& s) {
    VariantInit(&v);
    v.vt = VT_BSTR;
    v.bstrVal = SysAllocString(reinterpret_cast<const wchar_t*>(s.utf16()));
  }

  ~Bstr() {
    VariantClear(&v);
  }

  Bstr(const Bstr&) = delete;
  Bstr& operator=(const Bstr&) = delete;
};

VARIANT intVar(int i) {
  VARIANT v;
  VariantInit(&v);
  v.vt = VT_I4;
  v.lVal = i;
  return v;
}

VARIANT boolVar(bool b) {
  VARIANT v;
  VariantInit(&v);
  v.vt = VT_BOOL;
  v.boolVal = b ? VARIANT_TRUE : VARIANT_FALSE;
  return v;
}

constexpr int kOlFolderCalendar = 9;
constexpr int kOlMeetingCanceled = 5;
constexpr int kOlMeetingReceivedAndCanceled = 7;
// A runaway range (a daily series with no end) stops here rather than
// enumerating for minutes.
constexpr int kMaxItems = 5000;

}  // namespace

bool outlookDesktopAvailable() {
  const ComScope com;
  CLSID clsid{};
  return SUCCEEDED(CLSIDFromProgID(L"Outlook.Application", &clsid));
}

OutlookRead readOutlookCalendar(const QDateTime& from, const QDateTime& to) {
  OutlookRead out;
  const ComScope com;
  if(FAILED(com.hr) && com.hr != RPC_E_CHANGED_MODE) {
    out.error = QStringLiteral("COM ") + hrText(com.hr);
    return out;
  }
  CLSID clsid{};
  if(FAILED(CLSIDFromProgID(L"Outlook.Application", &clsid))) {
    out.error = QStringLiteral("Outlook is not installed");
    return out;
  }
  IDispatch* raw = nullptr;
  // A running Outlook is the one this returns; otherwise it starts one in
  // the background, which exits again once released.
  const HRESULT hr = CoCreateInstance(clsid, nullptr, CLSCTX_LOCAL_SERVER, IID_IDispatch, reinterpret_cast<void**>(&raw));
  if(FAILED(hr) || raw == nullptr) {
    out.error = QStringLiteral("Outlook did not answer (%1)").arg(hrText(hr));
    return out;
  }
  const Disp app(raw);

  const Bstr mapi(QStringLiteral("MAPI"));
  const Disp ns = getObject(app.get(), L"GetNamespace", DISPATCH_METHOD, {&mapi.v});
  const VARIANT calendarKind = intVar(kOlFolderCalendar);
  const Disp folder = getObject(ns.get(), L"GetDefaultFolder", DISPATCH_METHOD, {&calendarKind});
  const Disp items = getObject(folder.get(), L"Items");
  if(!items) {
    out.error = QStringLiteral("Outlook has no calendar to read");
    return out;
  }
  // Sort first, then expand series: the order Outlook documents, without
  // which IncludeRecurrences returns the masters only.
  const Bstr byStart(QStringLiteral("[Start]"));
  invoke(items.get(), L"Sort", DISPATCH_METHOD, nullptr, {&byStart.v});
  const VARIANT yes = boolVar(true);
  invoke(items.get(), L"IncludeRecurrences", DISPATCH_PROPERTYPUT, nullptr, {&yes});

  const Bstr filter(QStringLiteral("[Start] < '%1' AND [End] > '%2'").arg(restrictDate(to), restrictDate(from)));
  const Disp found = getObject(items.get(), L"Restrict", DISPATCH_METHOD, {&filter.v});
  if(!found) {
    out.error = QStringLiteral("Outlook refused the date filter");
    return out;
  }

  Disp item = getObject(found.get(), L"GetFirst", DISPATCH_METHOD);
  while(item && out.items.size() < kMaxItems) {
    const int status = getInt(item.get(), L"MeetingStatus");
    if(status != kOlMeetingCanceled && status != kOlMeetingReceivedAndCanceled) {
      OutlookItem it;
      it.subject = getString(item.get(), L"Subject");
      it.start = getDate(item.get(), L"Start");
      it.end = getDate(item.get(), L"End");
      it.allDay = getBool(item.get(), L"AllDayEvent");
      it.location = getString(item.get(), L"Location");
      it.body = getString(item.get(), L"Body");
      QString gid = getString(item.get(), L"GlobalAppointmentID");
      if(gid.isEmpty()) {
        gid = getString(item.get(), L"EntryID");
      }
      if(!gid.isEmpty() && it.start.isValid()) {
        it.key = gid.right(40) + QLatin1Char('-') + it.start.toString(QStringLiteral("yyyyMMddHHmm"));
        out.items.append(it);
      }
    }
    item = getObject(found.get(), L"GetNext", DISPATCH_METHOD);
  }
  out.ok = true;
  return out;
}

}  // namespace heap::cal
