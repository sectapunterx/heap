#include "integrations/JiraProvider.h"

#include <gtest/gtest.h>

using heap::integrations::ExternalTask;
using heap::integrations::jiraAdfToPlainText;
using heap::integrations::parseJiraIssues;

TEST(JiraParse, ParsesSearchResponse) {
  const QByteArray json = R"({
    "issues": [
      {
        "key": "LTE-2398",
        "fields": {
          "summary": "Handover fails on X2",
          "description": {
            "type": "doc",
            "content": [
              { "type": "paragraph", "content": [ { "type": "text", "text": "First line." } ] },
              { "type": "paragraph", "content": [ { "type": "text", "text": "Second line." } ] }
            ]
          },
          "status": { "name": "In Progress" },
          "priority": { "name": "High" },
          "labels": ["radio", "urgent"],
          "updated": "2026-07-02T12:34:56.000+0000"
        }
      }
    ]
  })";

  const QVector<ExternalTask> tasks = parseJiraIssues(json, "https://acme.atlassian.net/");
  ASSERT_EQ(tasks.size(), 1);

  const ExternalTask& t = tasks.first();
  EXPECT_EQ(t.providerId, QString("jira"));
  EXPECT_EQ(t.externalId, QString("LTE-2398"));
  // Trailing slash on baseUrl is trimmed before building the browse URL.
  EXPECT_EQ(t.url, QString("https://acme.atlassian.net/browse/LTE-2398"));
  EXPECT_EQ(t.title, QString("Handover fails on X2"));
  EXPECT_EQ(t.status, QString("In Progress"));
  EXPECT_EQ(t.priority, QString("High"));
  ASSERT_EQ(t.labels.size(), 2);
  EXPECT_EQ(t.labels[0], QString("radio"));
  // ADF flattened to plain text, paragraphs preserved on separate lines.
  EXPECT_TRUE(t.body.contains("First line."));
  EXPECT_TRUE(t.body.contains("Second line."));
}

TEST(JiraParse, PlainStringDescriptionAndEmpty) {
  // Some responses (or older APIs) carry a plain-string description.
  const QByteArray json = R"({
    "issues": [
      { "key": "AB-1", "fields": { "summary": "s", "description": "just text", "status": { "name": "Done" } } }
    ]
  })";
  const QVector<ExternalTask> tasks = parseJiraIssues(json, "https://x.atlassian.net");
  ASSERT_EQ(tasks.size(), 1);
  EXPECT_EQ(tasks[0].body, QString("just text"));
  EXPECT_EQ(tasks[0].status, QString("Done"));

  EXPECT_TRUE(parseJiraIssues(QByteArray(), "https://x").isEmpty());
  EXPECT_TRUE(parseJiraIssues("[]", "https://x").isEmpty());  // array, not the search object
  EXPECT_TRUE(parseJiraIssues("garbage", "https://x").isEmpty());
}

TEST(JiraAdf, FlattensNestedContent) {
  const QByteArray adf = R"({
    "type": "doc",
    "content": [
      { "type": "paragraph", "content": [ { "type": "text", "text": "Hello " }, { "type": "text", "text": "world" } ] }
    ]
  })";
  const QString text = jiraAdfToPlainText(adf);
  EXPECT_TRUE(text.contains("Hello world"));
}
