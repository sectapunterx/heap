# Design decisions (0.8.1)

Questions the sheets leave open, decided against the sheets (ui-ux-pro-max:
progressive disclosure, content priority, state preservation). One entry each.

## Knowledge

- **DG-070 · Where the rest of the Docs catalogue goes.** The list shows
  Закреплено / Заметки / Сниппеты only. A reference stands in Закреплено when it
  is pinned (`pinned: true` in the docs blob; the starter catalogue pins RFC
  9110, RFC 6749 and OpenAPI). Unpinned references and contacts appear only
  while searching the list ("Ссылки", "Контакты" groups) and in Ctrl K, which
  opens the list searched for the hit. Right-click a reference to pin or unpin
  it. Why: progressive disclosure keeps the sheet's list at rest, and nothing
  of the catalogue is lost or unreachable. A collapsed group was rejected: it
  is UI the sheet does not show.
- **DG-070 · Docs pages.** Pages of the former catalogue are listed flat under
  "Страницы" (only when a profile has any) and open in the same document area,
  drawn and edited like a note, with "Страница · изменена …" above. The page
  tree, new pages and moving pages are gone with DocsView; rename and delete
  stay on the row's right-click menu. Notes replace new pages.
- **DG-071 · What left the toolbar.** Attach (Ctrl+Shift+A in the editor), the
  list toggle (Ctrl+Alt+L, Ctrl K "notes.toggleList"), the whole source
  (Ctrl+Shift+M) stay on their keys. The links column shows itself when the
  view is wider than 1000 px; there is no toggle.
- **DG-072 · Column order and content.** Bold: Задачи в заметке, Ссылаются
  сюда, Внешние ссылки; quiet: Ссылаются сюда first (as Q-Knowledge). An empty
  group is not drawn. "Ссылки из заметки" (outgoing) is not in the sheets and
  left the column; the links stay visible in the note itself. An external
  link's title (`[RFC 6585](url "429 Too Many Requests")`) reads after its
  label.
- **DG-073 · Note order.** Newest first by creation time. The sheet's order is
  not alphabetical; ordering by last edit would make the note being typed in
  jump to the top of the list (state preservation), creation order does not.
