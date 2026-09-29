// Copy for the five feature pages. Every claim here is checked against the
// README and docs/ — keep it that way when editing.
export type WidgetKind = 'plan' | 'week' | 'notes' | 'connect' | 'flow';
export type ShotName =
  | 'board-kanban'
  | 'board-timeline'
  | 'board-week'
  | 'board-month'
  | 'calendar-focus'
  | 'board-notes'
  | 'board-docs'
  | 'settings-integrations'
  | 'hotkeys-tweaks'
  | 'welcome';

export interface FeatureSection {
  eyebrow: string;
  title: string;
  body: string;
  points?: string[];
  shot?: ShotName;
  shotAlt?: string;
  /** Short mono lines shown instead of a screenshot. */
  snippet?: string[];
}

export interface FeatureArea {
  slug: string;
  num: string;
  label: string;
  title: string;
  lead: string;
  /** One line for cards and the home-page tour. */
  summary: string;
  widget: WidgetKind;
  widgetHint: string;
  sections: FeatureSection[];
  keys: Array<{ keys: string[]; label: string }>;
}

export const FEATURE_AREAS: FeatureArea[] = [
  {
    slug: 'plan',
    num: '01',
    label: 'Plan',
    title: 'Plan — a board that keeps up with you.',
    lead: 'Kanban columns, a deadline timeline and an archive — quick enough to use between two compiles, and entirely yours to rearrange.',
    summary: 'Kanban columns you drag between, priority chips, recurring tasks, a timeline by deadline and an archive.',
    widget: 'plan',
    widgetHint: 'Drag cards between columns. Filter by priority, change the sort.',
    sections: [
      {
        eyebrow: 'Board',
        title: 'The order is yours.',
        body: 'Drop a card exactly where it belongs, or let a column sort itself by priority, due date, recency or title. Every change can be undone — heap. keeps a real undo and redo stack.',
        points: ['Priority chips P0–P3 and filters', 'Markdown descriptions with a tickable checklist', 'Branch and PR decoration from your working copy', 'A scheduled-time pill on cards with a time slot'],
        shot: 'board-kanban',
        shotAlt: 'heap. board with five columns, priority chips and a pinned day calendar',
      },
      {
        eyebrow: 'Timeline',
        title: 'Every task, by when it’s due.',
        body: 'The same tasks, bucketed into overdue, today, this week and later. The view for Monday morning: what is burning, what can wait.',
        shot: 'board-timeline',
        shotAlt: 'heap. timeline grouping tasks by deadline',
      },
      {
        eyebrow: 'Automation & archive',
        title: 'It tidies up after you.',
        body: 'Recurring tasks come back on schedule. A 60-second tick moves finished cards to the archive, warns about stuck ones and fires deadline and standup reminders — all of it respecting your quiet hours.',
        points: ['Restore or delete from the archive', 'Reminders that stay quiet when you ask them to'],
        snippet: ['automation · every 60 s', '  archive  done > 7d        → 2 cards', '  warn     stuck in Review → APP-103', '  remind   standup 10:00    → quiet hours off'],
      },
    ],
    keys: [
      { keys: ['J', 'K'], label: 'Next / previous card' },
      { keys: ['H', 'L'], label: 'Previous / next column' },
      { keys: ['⇧', 'H J K L'], label: 'Move the card' },
      { keys: ['Space', '↵'], label: 'Select · open the card' },
    ],
  },
  {
    slug: 'time',
    num: '02',
    label: 'Time',
    title: 'Time — your week, next to your work.',
    lead: 'Week, month and a whole-day calendar in the same window as your tasks, so the plan and the calendar stop disagreeing.',
    summary: 'Week and month views, a day calendar with drag-to-create, focus blocks, repeating events, .ics in and out.',
    widget: 'week',
    widgetHint: 'Drag an event to move it, pull its bottom edge to resize, drag on an empty slot to create one.',
    sections: [
      {
        eyebrow: 'Week',
        title: 'Seven days, one glance.',
        body: 'Drag and resize events, see overlapping ones side by side, and keep a rail of the tasks that still need a slot.',
        shot: 'board-week',
        shotAlt: 'heap. week view with events side by side',
      },
      {
        eyebrow: 'Day',
        title: 'Book time for the work itself.',
        body: 'A midnight-to-midnight day calendar with a live now-line. Drag to create, resize, or drop a task onto it to book a focus block for it.',
        shot: 'calendar-focus',
        shotAlt: 'heap. day calendar with a focus block',
      },
      {
        eyebrow: 'Repeating & .ics',
        title: 'The calendar things you expect.',
        body: 'Repeating events daily, weekly, fortnightly, monthly or yearly — edit one occurrence, this-and-following, or the whole series.',
        points: ['All-day, multi-day and past-midnight events', 'Meeting reminders', '.ics import and export', 'Month view for the long run'],
        shot: 'board-month',
        shotAlt: 'heap. month view',
      },
    ],
    keys: [
      { keys: ['T'], label: 'Go to today' },
      { keys: ['←', '→'], label: 'Previous / next period' },
      { keys: ['G'], label: 'Go to a date' },
      { keys: ['Ctrl', '3'], label: 'Open the week' },
    ],
  },
  {
    slug: 'know',
    num: '03',
    label: 'Know',
    title: 'Know — notes that link to the work.',
    lead: 'Markdown notes and long-form docs next to the board, linked to your tasks and the people you work with.',
    summary: 'Markdown notes with folders and a daily note, [[wiki-links]] and backlinks, docs, snippets and contacts.',
    widget: 'notes',
    widgetHint: 'Edit on the left and watch it render. Click a [[link]] — or a missing one to create it.',
    sections: [
      {
        eyebrow: 'Notes',
        title: 'Write where you work.',
        body: 'Many notes per profile, with folders, pinning and a daily note. A Markdown editor with headings, task lists, tables, highlighted code, callouts and footnotes — and a live rendered view.',
        points: ['@people and #ticket autocomplete', 'Import and export as a folder of .md files — Obsidian-compatible'],
        shot: 'board-notes',
        shotAlt: 'heap. notes: Markdown editor and rendered view',
      },
      {
        eyebrow: 'Links',
        title: 'Notes that know each other.',
        body: '[[Wiki-links]] cross from one note to another, every note shows what links to it, and a link to a note that doesn’t exist yet offers to create it.',
        snippet: ['Design lives in [[Rate limiter design]].', 'Open question in [[Retry budget]]   ← not written yet', '', 'Linked from: Standup notes · 2026-07-07'],
      },
      {
        eyebrow: 'Docs',
        title: 'The reference you keep reaching for.',
        body: 'A tree of long-form Markdown pages, plus a catalog of your own sections and fields, snippets with syntax highlighting and contact cards.',
        shot: 'board-docs',
        shotAlt: 'heap. docs with sections, snippets and contacts',
      },
    ],
    keys: [
      { keys: ['Ctrl', '7'], label: 'Open notes' },
      { keys: ['Ctrl', '6'], label: 'Open docs' },
      { keys: ['Ctrl', '⇧', 'N'], label: 'Quick-capture a note' },
      { keys: ['Ctrl', 'K'], label: 'Search every note' },
    ],
  },
  {
    slug: 'connect',
    num: '04',
    label: 'Connect',
    title: 'Connect — issues come to you.',
    lead: 'Your team keeps its tracker. heap. brings your part of it onto your board and sends status changes back.',
    summary: 'GitHub, GitLab, Jira, Trello and eight more trackers, mirrored as cards. Mattermost for your contacts.',
    widget: 'connect',
    widgetHint: 'Pick a tracker and connect it. Then move a card and watch what goes back.',
    sections: [
      {
        eyebrow: 'Trackers',
        title: 'Twelve trackers, one board.',
        body: 'GitHub, GitLab, Jira, Trello, Gitea, Forgejo, Redmine, Todoist, Asana, ClickUp, Sentry and Bitbucket. Sign in through the browser or paste a token; GitHub also takes a device code.',
        points: ['GitHub, GitLab and Jira pull what’s assigned to you — no setup', 'Map a tracker’s statuses onto your columns', 'Optional timed auto-sync', 'Walks every page of a pull and waits out rate limits'],
        shot: 'settings-integrations',
        shotAlt: 'heap. settings: tracker integrations',
      },
      {
        eyebrow: 'Write-back',
        title: 'Move a card, update the issue.',
        body: 'For GitHub, GitLab, Gitea and Forgejo, moving a card writes its state back: drop it in Done and the issue closes, pull it out again and it reopens. In “my issues” mode each issue is written back to the repository it came from.',
        snippet: ['APP-108  Review → Done', '  ↳ acme/web#108  open → closed'],
      },
      {
        eyebrow: 'Credentials & people',
        title: 'Tokens stay in the keychain.',
        body: 'Access tokens live in the OS keychain, never in state.json. Mattermost brings in the people you talk to as contacts and @handles — it never posts anything.',
      },
    ],
    keys: [],
  },
  {
    slug: 'flow',
    num: '05',
    label: 'Flow',
    title: 'Flow — small things that save the day.',
    lead: 'A palette over everything, capture from anywhere, and a board that follows your git branch.',
    summary: 'Ctrl+K over everything, one-line quick capture from any app that books meetings and focus blocks, a git-aware board and profiles.',
    widget: 'flow',
    widgetHint: 'Type into quick capture — try a meeting with a time — search with the palette, or run a git command.',
    sections: [
      {
        eyebrow: 'Command palette',
        title: 'Ctrl+K, then anything.',
        body: 'Full-text search across tasks, notes, docs and snippets, plus every command. The header search is a query box too: status:, priority:, deadline:, tag: and mention: clauses mix with plain words.',
        snippet: ['priority:P0,P1 deadline:<friday', 'status:blocked mention:@ada', 'deadline:none tag:infra'],
      },
      {
        eyebrow: 'Quick capture',
        title: 'From any app, without opening heap.',
        body: 'Ctrl+Shift+Space brings up one line over whatever you are working in — the main window stays minimized, in the tray or behind your editor. Type, press Enter, and a notification tells you exactly what was made and where it went. Ctrl+Shift+N does the same for a note.',
        points: ['A live preview of what was understood, before you commit', 'Esc puts it away; a half-written note waits for you', 'Click the notification to open the task'],
        snippet: ['Meeting added to the calendar', '“Call with @lena”', 'Tomorrow, Thu 1 Oct, 16:00–16:30', 'Note: pricing', 'Also a task in “To do”'],
      },
      {
        eyebrow: 'Capture grammar',
        title: 'It reads the way you write.',
        body: 'Everything is optional and in any order, in English or Russian. Days, times and ranges, parts of the day and repeats become the schedule; a tracker key becomes the task’s id; “p1” or “urgent” sets the priority; @mentions stay linked to people and text after // becomes the note.',
        points: ['tomorrow · by friday · in 2 days · every weekday', '4pm · 16:00–16:45 · tomorrow morning · tonight', 'завтра утром · к пятнице · по будням', 'p0–p3 · !! · urgent · срочно'],
        snippet: ['ship v1 tomorrow morning         → due tomorrow, 09:00', 'APP-231 urgent fix login by fri  → APP-231 · P1 · due Friday', 'pay invoice // net-30            → note: net-30', 'созвон завтра в 16:00-16:45      → a meeting, tomorrow'],
      },
      {
        eyebrow: 'Meetings, focus, to-dos',
        title: 'It knows where each line belongs.',
        body: 'The words decide. A standup, a 1:1 or a team sync is booked as that kind of event; a call, a retro, a demo or an interview is a one-off meeting — on the calendar with its attendees and a linked task when you give a time, a plain task when you don’t. “focus” plus a time books a focus block, “bug” or “task” keeps a line off the calendar, and “ping @someone” lands in the people you still have to message.',
        snippet: ['standup every weekday 10:00    → Standup, repeats on weekdays', '1:1 with @anna thursday 12:00  → 1:1 · With: @anna', 'focus write the RFC 9:00       → Focus block scheduled', 'ping @andrey about the release → Reminder to message @andrey'],
      },
      {
        eyebrow: 'Git-aware',
        title: 'It follows your branch.',
        body: 'heap. watches your working copy. The active branch is matched to a task by id, the card is decorated with the branch, and a focused-repo banner shows branch and PR state.',
        snippet: ['$ git switch -c APP-112-flaky-sync-test', '  ⎇ matched APP-112 · focused repo acme-web'],
      },
      {
        eyebrow: 'Profiles & first run',
        title: 'A workspace per project.',
        body: 'Profiles are feature-scoped workspaces with JSON import and export. A short, skippable first-run guide shows you around — replay it whenever you like.',
        shot: 'welcome',
        shotAlt: 'heap. interactive welcome guide',
      },
    ],
    keys: [
      { keys: ['Ctrl', 'K'], label: 'Command palette' },
      { keys: ['Ctrl', '⇧', 'Space'], label: 'Quick-capture a task' },
      { keys: ['Ctrl', 'F'], label: 'Query the header search' },
      { keys: ['Ctrl', '/'], label: 'Hotkeys panel — rebind anything' },
    ],
  },
];

export function areaBySlug(slug: string): FeatureArea | undefined {
  return FEATURE_AREAS.find((a) => a.slug === slug);
}

/** "Plan — a board that keeps up with you." → "A board that keeps up with you." */
export function tagline(area: FeatureArea): string {
  const t = area.title.split('— ')[1] ?? area.title;
  return t.charAt(0).toUpperCase() + t.slice(1);
}
