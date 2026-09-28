// Screenshots live once, in the repository's docs/assets/img/screens (the
// README uses them too); astro:assets resizes and re-encodes them at build.
import type { ImageMetadata } from 'astro';
import boardKanban from '../../../docs/assets/img/screens/board-kanban.png';
import boardTimeline from '../../../docs/assets/img/screens/board-timeline.png';
import boardWeek from '../../../docs/assets/img/screens/board-week.png';
import boardMonth from '../../../docs/assets/img/screens/board-month.png';
import calendarFocus from '../../../docs/assets/img/screens/calendar-focus.png';
import boardNotes from '../../../docs/assets/img/screens/board-notes.png';
import boardDocs from '../../../docs/assets/img/screens/board-docs.png';
import settingsIntegrations from '../../../docs/assets/img/screens/settings-integrations.png';
import hotkeysTweaks from '../../../docs/assets/img/screens/hotkeys-tweaks.png';
import welcome from '../../../docs/assets/img/screens/welcome.png';
import type { ShotName } from '../data/features';

export const SHOTS: Record<ShotName, ImageMetadata> = {
  'board-kanban': boardKanban,
  'board-timeline': boardTimeline,
  'board-week': boardWeek,
  'board-month': boardMonth,
  'calendar-focus': calendarFocus,
  'board-notes': boardNotes,
  'board-docs': boardDocs,
  'settings-integrations': settingsIntegrations,
  'hotkeys-tweaks': hotkeysTweaks,
  welcome,
};
