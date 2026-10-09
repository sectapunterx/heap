# Design decisions (0.8.1)

Questions the sheets leave open, decided against the sheets (ui-ux-pro-max
guidance in brackets). One entry per decision, with its DG id.

## Settings (DG-090…103)

- **DG-090 — settings the sheets do not show.** Rows a user may have set
  (scale, contrast, own cursor colour, own themes, close to tray, start at
  login; showing weekends, grid snap, focus blocks, standup time; default
  priority, blocked highlight, branch before review; desktop notifications and
  a test, deadline lead, snooze lengths, standup reminder, digests, volume,
  chime minutes; end-of-day, waiting, seen-before, standup draft; shortcut
  hints, reset all keys; auto backup and its interval, restoring a backup copy,
  JSON import, unused attachments, reset settings, wipe; storage path, engine,
  logs) are folded under a quiet "Ещё настройки" line at the end of their
  section. At rest every section shows exactly the sheet's rows; nothing a user
  configured is lost or unreachable, and a settings search opens the fold so a
  hit can still be revealed. [progressive-disclosure; consistency — a fold in
  place beats a command-only path, which hides a setting from the page it
  belongs to.]
- **DG-101 — Профиль removed.** `settings.profile` (name, handle, role, team,
  avatar colour) is read by nothing outside the section; the stored values stay
  in the JSON untouched. The old `settings:profile` deep link opens the top.
- **DG-091 — sections.** The X sheets' eleven plus Помощь, in their order;
  "Слежение за Git" is the block heading, "Git" the nav name; no version footer
  or debug toggle in the nav (the version is under О программе).
- **DG-090 — layout of a row.** One rule for the whole page: label and hint on
  the left, options right-aligned (H2-Settings / Q-Settings, X-Set-Columns,
  X-Set-StyleKeys). The three-column composites (CalNotif, GitLangAbout) set
  options under the label only for want of width. [consistency, visual-hierarchy.]
- **DG-090 — which style is "quiet" here.** The settings page follows the
  chip-fill switch (`Style.chipFill`), the same switch as the rest of the quiet
  look: off = no fills, lowercase options, outline pill on the picked one.
- **DG-093 — sign-in state cards.** The three cards under the list ("Не
  подключено / Ждём подтверждения / Подключено как") illustrate the states; the
  app shows the picked tracker's actual state in its detail (header line, the
  device code while waiting, "Выйти" when connected) instead of three static
  cards. [state-clarity; no decorative duplicates of live state.]
- **DG-093 — "Как часто".** The cadence is one setting for all trackers
  (`integrations.autoSyncMinutes`); every tracker's detail shows it and says so
  in the hint, instead of inventing a per-tracker schedule. "Синхронизировать"
  sits beside it, so the old manual sync is not lost.
- **DG-093 — rows without a function behind them are omitted**: "Спрашивать
  перед отправкой" (writes already confirm on a remote conflict; asking before
  every write needs a new flow) — follow-up ticket. "Тикеты вне фильтра" shows
  the real behaviour: kept as "только здесь", with "в архив" offered when there
  are any. [disabled-states: no controls that look usable but do nothing.]
- **DG-093 — MR/PR switches** (pull reviews, roles, may move) stay inside the
  tracker detail under the sheet's rows; the connection fields fold behind
  "Поля подключения".
- **DG-095 — Сроки.** The scheduler reminds a set number of hours before the
  deadline, not at 9:00; the option says the real lead ("за 24 ч") instead of
  promising a morning reminder. Morning mode is a follow-up.
- **DG-096 — Удалённые задачи (30 дней / навсегда)** is omitted: deletion is
  final today (Undo only), so there is nothing to keep; it needs a trash store
  (schema change). Снимки каждый день / каждый час, Хранить 7/14/30 and Снимок
  перед импортом и обновлением are wired (`data.historyEvery`,
  `data.historyDays`, `data.snapshotBeforeImport`). A stored 90 days stays and
  shows as a fourth option.
- **DG-099 — Git.** "Связывать ветку с задачей" switches branch→task matching
  off (`git.linkBranches`); "Строка «работаю над …»" hides the branch line over
  the view (`git.workingOnLine`); auto-move, auto focus block and "whose move"
  went to the fold.
- **DG-100 — Формат даты** is the clock format (как в системе / 24 ч / 12 ч,
  `calendar.timeFormat`, "system" = the locale's). "Разбор дат в вводе" states
  what the parser does (ru + en) and offers no other choice.
- **DG-102 — Помощь.** Three rows. "С чего начать" opens the existing guide
  (HelpContent) in a reader over the page — the guide had no note in Knowledge
  to point at, and the welcome tour's "Learn more" still lands in it.
- **DG-103 — О программе.** "Канал stable/beta" is omitted (the updater reads
  only stable releases); the channel is in the section line ("lowkey 0.8.1 ·
  stable"). "Проверить сейчас" stays on the Обновления row: with "только
  вручную" it is the only way to check. "Что нового" and "Лицензии" open the
  release notes and THIRD_PARTY_NOTICES on GitHub. Данные: export offers JSON
  (profile) or Markdown (notes), as the sheet's hint says.
- **DG-097 — Клавиши.** One row per action name (the catalogue keeps a few
  actions twice); a key is rebound in place; a conflict opens its box under the
  row, not at the end of a long list; the read-only rail panel stays.
- **DG-003 — glyphs.** `qml/Icon.qml` is not on heap2/0.8.1 yet: the drag
  handle and the column menu are drawn dots, the stage is StatusRing;
  dropdown chevrons come from the shared AppComboBox. Swap in Icon when it
  lands.
