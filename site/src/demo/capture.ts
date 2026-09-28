// A small take on heap.'s quick-capture grammar (docs/TUTORIAL.md,
// "Quick-capture syntax"): everything optional and order-independent.
//   fix login race                    -> task in To do
//   ship v1 tomorrow                  -> task with a deadline
//   pay invoice // net-30             -> text after // is the description
//   review PR @andrey @lena           -> mentions kept
//   focus refactor parser 10:00       -> focus block on today's calendar
//   standup 10:00 / sync 15:00-15:30  -> meeting on today's calendar

export interface Captured {
  kind: 'task' | 'focus' | 'meeting';
  title: string;
  desc?: string;
  due: number | null;
  mentions: string[];
  start?: number;
  end?: number;
}

const WEEKDAYS = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
const MEETING = /^(standup|meeting|sync|call|1:1|review|retro|demo)\b/i;

/** `todayIndex`: 0 = Monday … 6 = Sunday. */
export function parseCapture(input: string, todayIndex: number): Captured | null {
  let text = input.trim();
  if (!text) return null;

  let desc: string | undefined;
  const slash = text.indexOf('//');
  if (slash >= 0) {
    desc = text.slice(slash + 2).trim() || undefined;
    text = text.slice(0, slash).trim();
  }

  const mentions = [...text.matchAll(/@([\w.-]+)/g)].map((m) => m[1]);

  let start: number | undefined;
  let end: number | undefined;
  const time = text.match(/\b([01]?\d|2[0-3]):([0-5]\d)(?:\s*-\s*([01]?\d|2[0-3]):([0-5]\d))?\b/);
  if (time) {
    start = Number(time[1]) * 60 + Number(time[2]);
    if (time[3]) end = Number(time[3]) * 60 + Number(time[4]);
    text = (text.slice(0, time.index) + text.slice(time.index! + time[0].length)).trim();
  }

  let due: number | null = null;
  const words = text.split(/\s+/);
  const kept: string[] = [];
  for (const w of words) {
    const lw = w.toLowerCase();
    if (lw === 'today') due = 0;
    else if (lw === 'tomorrow') due = 1;
    else if (WEEKDAYS.includes(lw)) {
      const target = WEEKDAYS.indexOf(lw);
      due = (target - todayIndex + 7) % 7 || 7;
    } else kept.push(w);
  }
  text = kept.join(' ').trim();

  let kind: Captured['kind'] = 'task';
  if (start !== undefined) {
    if (/^focus\b/i.test(text)) {
      kind = 'focus';
      text = text.replace(/^focus\b\s*/i, '');
    } else if (MEETING.test(text)) {
      kind = 'meeting';
    }
  }
  if (kind !== 'task') {
    end ??= start! + (kind === 'focus' ? 90 : 30);
    due = null;
  }

  const title = text.replace(/\s+/g, ' ').trim();
  if (!title) return null;
  return { kind, title: title.charAt(0).toUpperCase() + title.slice(1), desc, due, mentions, start, end };
}
