# Glossary of the interface (APP-215)

One thing, one word, in each language. New strings use these terms;
`tests/qml/tst_Glossary.qml` fails when a banned synonym comes back into a
live string (strings of views leaving with heap 2 — welcome tour, side rail,
Tweaks — are not checked).

| Term (en) | Термин (ru) | What it is | Not |
|---|---|---|---|
| Today | Сегодня | The day screen: input line, day plan, what is due | dashboard, home |
| Tasks | Задачи | The section with the board, list and calendar | tickets, cards (in UI copy) |
| Task | Задача | One item, local or from a tracker | ticket, card, issue |
| Task document | Задача-документ | A task opened as a full page | task editor, details |
| Knowledge | Знания | Notes, pinned references, pages and snippets in one section | Docs + Notes |
| Pinned | Закреплено | References (RFC, API links with a tag) on top of Knowledge | Reference, Справочник |
| My views | Мои виды | Saved task queries in the sidebar | saved filters |
| Save as view | Сохранить как вид | Saving the current query | Save view, Сохранить вид |
| Column stage | Этап колонки | What a column means: todo / in progress / done… | status category |
| Command line | Командная строка | Ctrl K: find anything, run any command | palette, палитра |
| Style: Quiet / Bold / Custom | Стиль: Тихий / Насыщенный / Свой | The look of heap 2 | theme preset |
| Appearance (Settings) | Внешний вид (Настройки) | Where Tweaks went | Tweaks, Твики |
| Only yours | Только у вас | Data that never leaves this computer | private, local-only |
| Profile | Профиль | A set of tasks with its own trackers and statuses | project, workspace |

## Tone

- Russian: addressing the person as «вы», lower case after the first word in
  buttons and headings, quotes «», no trailing period in buttons and
  one-line hints; a period after full sentences.
- English: sentence case, curly quotes “”, same punctuation rules.
- ru and en say the same thing; neither adds a promise the other lacks.
- An error says what happened and what to do next.

## Open discrepancies

- `taskmenu.localOnly`: en "only here" vs ru «только у вас» — different
  meaning (place vs owner); needs an owner decision.
- Weekly "recap" (en) vs «сводка» (ru) — kept as is, recap is the en word.
