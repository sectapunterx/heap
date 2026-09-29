// A small take on heap.'s quick-capture grammar (docs/TUTORIAL.md,
// "Quick-capture syntax"): everything optional and order-independent.
//   fix login race                      -> task in To do
//   ship v1 tomorrow                    -> task with a deadline
//   APP-231 urgent fix login by friday  -> the ticket key is the id, P1
//   pay invoice // net-30               -> text after // is the description
//   focus refactor parser 10:00         -> focus block on the calendar
//   standup every weekday 10:00         -> a repeating standup
//   call with @lena tomorrow 4pm        -> a one-off meeting with Lena
//   ping @andrey about the release      -> a reminder to message Andrey
// The app understands Russian as well; the demo keeps to English.

import type { Prio } from './model';

export type MeetingType = 'none' | 'standup' | 'oneone' | 'sync';

export interface Captured {
  kind: 'task' | 'focus' | 'meeting' | 'ping';
  title: string;
  desc?: string;
  /** Day offset from today; null = no date. */
  due: number | null;
  mentions: string[];
  start?: number;
  end?: number;
  meeting?: MeetingType;
  prio?: Prio;
  /** A tracker key named in the text; it becomes the task id. */
  ticket?: string;
  repeat?: string;
  /** Meeting words but no time: saved as a task, kept off the calendar. */
  untimedMeeting?: boolean;
}

const WEEKDAYS = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
const SHORT_DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const PARTS_OF_DAY: Record<string, number> = { morning: 540, noon: 720, afternoon: 900, evening: 1140, tonight: 1200, eod: 1080 };
const PRIORITY: Record<string, Prio> = { p0: 'P0', critical: 'P0', blocker: 'P0', '!!!': 'P0', p1: 'P1', urgent: 'P1', asap: 'P1', '!!': 'P1', p2: 'P2', p3: 'P3' };

const TICKET = /\b(bug|bugs|issue|issues|ticket|task|tasks|story|epic|feature|bugfix|hotfix|todo)\b/i;
const FOCUS = /\b(focus|deep work|heads[- ]down)\b/i;
const STANDUP = /\b(standup|stand-up|daily|scrum)\b/i;
const ONE_ON_ONE = /(^|\s)(1:1|1-1|1on1|one[- ]on[- ]one)(?=\s|$)/i;
const SYNC = /\b(sync|sync-up)\b/i;
const MEETING = /\b(meeting|meet|call|retro|demo|review|interview|grooming|planning|workshop|huddle|catch[- ]?up)\b/i;
const CONTACT = /\b(ping|ask|tell|remind|message|dm|follow[- ]up|check with)\b/i;

function meetingType(text: string): MeetingType | null {
  if (STANDUP.test(text)) return 'standup';
  if (ONE_ON_ONE.test(text)) return 'oneone';
  if (SYNC.test(text)) return 'sync';
  if (MEETING.test(text)) return 'none';
  return null;
}

function clock(h: string, m: string | undefined, mer: string | undefined): number {
  let hour = Number(h) % 24;
  if (mer?.toLowerCase() === 'pm' && hour < 12) hour += 12;
  if (mer?.toLowerCase() === 'am' && hour === 12) hour = 0;
  return hour * 60 + Number(m ?? 0);
}

/** `todayIndex`: 0 = Monday … 6 = Sunday. */
export function parseCapture(input: string, todayIndex: number): Captured | null {
  let text = input.trim();
  if (!text) return null;
  const raw = text;

  let desc: string | undefined;
  const slash = text.indexOf('//');
  if (slash >= 0) {
    desc = text.slice(slash + 2).trim() || undefined;
    text = text.slice(0, slash).trim();
  }

  const mentions = [...text.matchAll(/@([\w.-]+)/g)].map((m) => m[1]);

  let ticket: string | undefined;
  const key = text.match(/(?:^|\s)([A-Z][A-Z0-9]{1,9}-\d{1,6})(?=\s|$)/);
  if (key) {
    ticket = key[1];
    text = text.replace(key[1], '');
  }

  // A time, a range, or "4pm". Minutes take two digits: "1:1" is a meeting.
  let start: number | undefined;
  let end: number | undefined;
  const time = text.match(/(?:^|\s)(?:at\s+)?([01]?\d|2[0-3])(?::([0-5]\d))?\s*(am|pm)?(?:\s*-\s*([01]?\d|2[0-3])(?::([0-5]\d))?\s*(am|pm)?)?(?=\s|$)/i);
  if (time && (time[2] || time[3])) {
    start = clock(time[1], time[2], time[3] ?? time[6]);
    if (time[4]) end = clock(time[4], time[5], time[6]);
    text = (text.slice(0, time.index) + ' ' + text.slice(time.index! + time[0].length)).trim();
  }

  let due: number | null = null;
  let repeat: string | undefined;
  let prio: Prio | undefined;
  const words = text.split(/\s+/);
  const kept: string[] = [];
  for (let i = 0; i < words.length; i++) {
    const lw = words[i].toLowerCase();
    const next = words[i + 1]?.toLowerCase();
    if (lw === 'every' && next && (next === 'weekday' || next === 'weekdays' || next === 'day' || WEEKDAYS.includes(next))) {
      if (next === 'weekday' || next === 'weekdays') repeat = 'weekdays';
      else if (next === 'day') repeat = 'daily';
      else repeat = `every ${SHORT_DAYS[WEEKDAYS.indexOf(next)]}`;
      due = next === 'weekday' || next === 'weekdays' || next === 'day' ? 0 : (WEEKDAYS.indexOf(next) - todayIndex + 7) % 7;
      i++;
    } else if (lw === 'today') due = 0;
    else if (lw === 'tomorrow') due = 1;
    else if (WEEKDAYS.includes(lw)) due = (WEEKDAYS.indexOf(lw) - todayIndex + 7) % 7 || 7;
    else if (start === undefined && lw in PARTS_OF_DAY) start = PARTS_OF_DAY[lw];
    else if (!prio && lw in PRIORITY) prio = PRIORITY[lw];
    else if ((lw === 'by' || lw === 'on' || lw === 'at') && next && (WEEKDAYS.includes(next) || next === 'today' || next === 'tomorrow' || next in PARTS_OF_DAY)) continue;
    else kept.push(words[i]);
  }
  text = kept.join(' ').replace(/\s+/g, ' ').trim();

  let kind: Captured['kind'] = 'task';
  let meeting: MeetingType | undefined;
  let untimedMeeting: boolean | undefined;
  if (TICKET.test(raw)) {
    // "fix", "bug", "task": a to-do, never a calendar entry.
  } else if (mentions.length && CONTACT.test(text)) {
    kind = 'ping';
  } else if (FOCUS.test(text) && start !== undefined) {
    kind = 'focus';
    text = text.replace(/^focus\b\s*/i, '');
  } else {
    const type = meetingType(text);
    if (type && start !== undefined) {
      kind = 'meeting';
      meeting = type;
    } else if (type) untimedMeeting = true;
  }
  if (kind === 'focus' || kind === 'meeting') {
    end ??= start! + (kind === 'focus' ? 90 : 30);
    due ??= 0;
  }

  const title = text.replace(/\s+/g, ' ').trim();
  if (!title) return null;
  return {
    kind,
    title: title.charAt(0).toUpperCase() + title.slice(1),
    desc,
    due,
    mentions,
    start,
    end,
    meeting,
    prio,
    ticket,
    repeat,
    untimedMeeting,
  };
}

export function fmtClock(min: number): string {
  return `${String(Math.floor(min / 60)).padStart(2, '0')}:${String(min % 60).padStart(2, '0')}`;
}

function dayName(due: number, todayIndex: number): string {
  if (due === 0) return 'today';
  if (due === 1) return 'tomorrow';
  if (due === 2) return 'in 2 days';
  return WEEKDAYS[(todayIndex + due) % 7].replace(/^./, (c) => c.toUpperCase());
}

const MEETING_HEADLINE: Record<MeetingType, string> = {
  none: 'Meeting added to the calendar',
  standup: 'Standup added to the calendar',
  oneone: '1:1 added to the calendar',
  sync: 'Team sync added to the calendar',
};

/**
 * The confirmation heap. shows after a capture, in the app's own words: what
 * was made and where, the title in quotes, then only the things that were set.
 */
export function captureNotice(item: Captured, todayIndex: number): { headline: string; lines: string[] } {
  const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
  if (item.kind === 'ping') {
    return { headline: `Reminder to message ${item.mentions.map((m) => '@' + m).join(', ')}`, lines: [`“${item.title}”`] };
  }
  const lines = [`“${item.title}”`];
  let headline: string;
  if (item.kind === 'meeting') {
    headline = MEETING_HEADLINE[item.meeting ?? 'none'];
    lines.push(`${cap(dayName(item.due ?? 0, todayIndex))}, ${fmtClock(item.start!)}–${fmtClock(item.end!)}`);
    if (item.mentions.length) lines.push(`With: ${item.mentions.map((m) => '@' + m).join(', ')}`);
  } else if (item.kind === 'focus') {
    headline = 'Focus block scheduled';
    lines.push(`${cap(dayName(item.due ?? 0, todayIndex))}, ${fmtClock(item.start!)}`);
  } else {
    headline = 'Task added to “To do”';
    if (item.due !== null) lines.push(`Due: ${dayName(item.due, todayIndex)}${item.start !== undefined ? ', ' + fmtClock(item.start) : ''}`);
    if (item.untimedMeeting) lines.push('No time given, so it is not on the calendar');
  }
  if (item.repeat) lines.push(`Repeats: ${item.repeat}`);
  if (item.prio) lines.push(`Priority: ${item.prio}`);
  if (item.ticket) lines.push(`Ticket: ${item.ticket}`);
  if (item.desc) lines.push(`Note: ${item.desc}`);
  if (item.kind === 'meeting') lines.push('Also a task in “To do”');
  return { headline, lines };
}
