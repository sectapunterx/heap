#pragma once

#include <QDateTime>
#include <QJsonObject>
#include <QJsonValue>
#include <QString>

// Pure helpers for reading one tracker's JSON issue (HEAP-117). They are here
// rather than in RestIssueProvider so the bespoke parsers (GitHub, GitLab,
// Jira, Trello) can share them without dragging in QNetworkAccessManager — each
// of those has its own narrow test target that links the parser alone.
namespace heap::integrations {

// Resolve a FieldMap path. Segments are dot-separated; a segment that is all
// digits indexes an array ("assignees.0.login"); "a|b" takes the first
// alternative that resolves to a non-empty leaf. A missing key, a wrong shape
// or an out-of-range index all yield an undefined value rather than throwing.
QJsonValue valueAtPath(const QJsonObject& obj, const QString& path);

// valueAtPath stringified: strings pass through, integral numbers lose the
// ".0", bools become "true"/"false", objects/arrays/null become empty.
QString fieldStr(const QJsonObject& obj, const QString& path);

// Read a tracker timestamp in any of the shapes the providers use: ISO-8601
// (with or without milliseconds, and with Jira's colon-less "+0000" offset), a
// bare "2026-09-20" date, or epoch milliseconds as a number or a string. The
// result is local time. `hasTime` (optional) answers whether the value carried
// a clock at all — a bare date lands at local midnight with false, so it
// compares equal to a deadline the user typed by hand.
QDateTime parseTrackerTimestamp(const QJsonValue& v, bool* hasTime = nullptr);

// "d73a4a" and "#d73a4a" both become "#d73a4a". Anything that is not a 3/6/8
// digit hex colour becomes empty, so a colour name never reaches a QML colour
// property as-is.
QString normalizeHexColor(const QString& raw);

// A project/repo identifier is spliced into URL paths and task ids, so it is
// accepted only as plain path segments ("owner/name", "PROJ"). A traversal
// segment ("." or "..") or anything else becomes empty.
QString sanitizeProject(const QString& raw);

// Collect one key out of an array of objects into "a, b" — the git forges list
// several assignees and heap shows one line.
QString joinObjectField(const QJsonValue& array, const QString& key);

}  // namespace heap::integrations
