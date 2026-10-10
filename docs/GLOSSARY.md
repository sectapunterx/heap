# Glossary of the interface (APP-215)

One thing, one word, in each language. New strings use these terms;
`tests/qml/tst_Glossary.qml` fails when a banned synonym comes back into a
live string (strings of views leaving with the 0.8.0 redesign — welcome tour, side rail,
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
| Style: Quiet / Bold / Custom | Стиль: Тихий / Насыщенный / Свой | The look of the app | theme preset |
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

## Decided (owner, 2026-10-09)

- `taskmenu.localOnly` means the place: en "only here", ru «только здесь»;
  the tooltip says why — the tracker is not changed, writing to it is off.
- Weekly "recap" (en) and «сводка» (ru) stay: the natural word in each
  language for the same thing.
- Tone confirmed as written above: «вы» only where an address is needed
  (hints, explanations); buttons and menu rows are verbs without one
  («Сохранить», «Открыть в трекере»); sentence case; no exclamations, no "we".
