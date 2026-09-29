import { describe, expect, it } from 'vitest';
import { captureNotice, parseCapture } from '../../src/demo/capture';
import { renderNote, wikiTargets } from '../../src/demo/markdown';
import { runCommand } from '../../src/demo/terminal';
import { reducer } from '../../src/demo/store';
import { seedState } from '../../src/demo/seed';
import { tasksIn } from '../../src/demo/model';
import { findFreeSlot, layoutDay, weekDates, weekdayIndex } from '../../src/demo/calendar';

const WED = 2;

describe('parseCapture', () => {
  it('makes a plain task', () => {
    expect(parseCapture('fix login race', WED)).toEqual({ kind: 'task', title: 'Fix login race', due: null, mentions: [], desc: undefined, start: undefined, end: undefined });
  });

  it('understands deadlines, descriptions and mentions', () => {
    expect(parseCapture('ship v1 tomorrow', WED)).toMatchObject({ kind: 'task', title: 'Ship v1', due: 1 });
    expect(parseCapture('pay invoice // net-30, portal is slow', WED)).toMatchObject({ title: 'Pay invoice', desc: 'net-30, portal is slow' });
    expect(parseCapture('review PR @andrey @lena', WED)).toMatchObject({ mentions: ['andrey', 'lena'] });
    expect(parseCapture('release notes friday', WED)).toMatchObject({ due: 2 });
    expect(parseCapture('retro wednesday', WED)).toMatchObject({ due: 7 });
  });

  it('books focus blocks and meetings when a time is given', () => {
    expect(parseCapture('focus refactor parser 10:00', WED)).toMatchObject({ kind: 'focus', title: 'Refactor parser', start: 600, end: 690 });
    expect(parseCapture('standup 10:00', WED)).toMatchObject({ kind: 'meeting', title: 'Standup', start: 600, end: 630 });
    expect(parseCapture('sync 15:00-15:30', WED)).toMatchObject({ kind: 'meeting', start: 900, end: 930 });
  });

  it('reads priorities, ticket keys, parts of the day and repeats', () => {
    expect(parseCapture('APP-231 urgent fix login by friday', WED)).toMatchObject({ kind: 'task', title: 'Fix login', ticket: 'APP-231', prio: 'P1', due: 2 });
    expect(parseCapture('ship v1 tomorrow morning', WED)).toMatchObject({ title: 'Ship v1', due: 1, start: 540 });
    expect(parseCapture('standup every weekday 10:00', WED)).toMatchObject({ kind: 'meeting', meeting: 'standup', repeat: 'weekdays' });
    expect(parseCapture('call with @lena tomorrow 4pm', WED)).toMatchObject({ kind: 'meeting', meeting: 'none', due: 1, start: 960, end: 990 });
    // "1:1" is a meeting, not the time 01:01.
    expect(parseCapture('1:1 with @anna thursday 12:00', WED)).toMatchObject({ kind: 'meeting', meeting: 'oneone', start: 720, due: 1 });
  });

  it('keeps untimed meetings and bugs off the calendar, and routes pings', () => {
    expect(parseCapture('meeting with the designer', WED)).toMatchObject({ kind: 'task', untimedMeeting: true });
    expect(parseCapture('bug in sync 15:00', WED)).toMatchObject({ kind: 'task' });
    expect(parseCapture('ping @andrey about the release', WED)).toMatchObject({ kind: 'ping', mentions: ['andrey'] });
  });

  it('writes the confirmation the app shows', () => {
    expect(captureNotice(parseCapture('call with @lena tomorrow 4pm // pricing', WED)!, WED)).toEqual({
      headline: 'Meeting added to the calendar',
      lines: ['“Call with @lena”', 'Tomorrow, 16:00–16:30', 'With: @lena', 'Note: pricing', 'Also a task in “To do”'],
    });
    expect(captureNotice(parseCapture('APP-231 urgent fix login by friday', WED)!, WED)).toEqual({
      headline: 'Task added to “To do”',
      lines: ['“Fix login”', 'Due: in 2 days', 'Priority: P1', 'Ticket: APP-231'],
    });
  });

  it('rejects empty input', () => {
    expect(parseCapture('   ', WED)).toBeNull();
    expect(parseCapture('tomorrow', WED)).toBeNull();
  });
});

describe('renderNote', () => {
  it('renders wiki links, mentions and task ids', () => {
    const html = renderNote('See [[Rate limiter design]] and [[Nope]] for @Oleg about #APP-101 and #BAD-9', ['Rate limiter design'], ['APP-101']);
    expect(html).toContain('class="md-wiki" data-note="Rate limiter design"');
    expect(html).toContain('md-wiki--missing');
    expect(html).toContain('<span class="md-mention">@Oleg</span>');
    expect(html).toContain('data-task="APP-101"');
    expect(html).toContain('md-ticket--unknown');
  });

  it('escapes raw HTML and keeps task lists', () => {
    const html = renderNote('<script>alert(1)</script>\n\n- [x] done\n- [ ] todo', [], []);
    expect(html).not.toContain('<script>');
    expect(html).toContain('checked');
    expect(html.match(/type="checkbox"/g)).toHaveLength(2);
  });

  it('does not treat e-mail addresses as mentions', () => {
    expect(renderNote('mail me at a@b.c', [], [])).not.toContain('md-mention');
  });

  it('lists wiki targets', () => {
    expect(wikiTargets('[[A]] then [[ B ]]')).toEqual(['A', 'B']);
  });
});

describe('runCommand', () => {
  const tasks = seedState().tasks;

  it('matches a branch to a task by id', () => {
    const res = runCommand('git switch -c APP-112-flaky-sync-test', null, tasks);
    expect(res.branch).toBe('APP-112-flaky-sync-test');
    expect(res.lines.join('\n')).toContain('matched APP-112');
  });

  it('handles checkout -b, unknown ids and other commands', () => {
    expect(runCommand('git checkout -b app-108-race', null, tasks).lines.join()).toContain('matched APP-108');
    expect(runCommand('git switch -c APP-999-nope', null, tasks).lines.join()).toContain('no task APP-999');
    expect(runCommand('git status', 'main', tasks).lines[0]).toBe('On branch main');
    expect(runCommand('clear', null, tasks).clear).toBe(true);
    expect(runCommand('rm -rf /', null, tasks).lines[0]).toContain('command not found');
  });
});

describe('reducer', () => {
  it('moves a card before another and renumbers the column', () => {
    const s = reducer(seedState(), { type: 'move', id: 'APP-101', col: 'todo', before: 'APP-112' });
    expect(tasksIn(s.tasks, 'todo').map((t) => t.id)).toEqual(['APP-108', 'APP-101', 'APP-112', 'APP-110']);
    expect(s.done.moved).toBe(true);
  });

  it('shifts and advances between columns', () => {
    let s = reducer(seedState(), { type: 'shift', id: 'APP-108', dir: 1 });
    expect(s.tasks.find((t) => t.id === 'APP-108')!.col).toBe('prog');
    s = reducer(s, { type: 'advance', id: 'APP-099' });
    expect(s.tasks.find((t) => t.id === 'APP-099')!.col).toBe('backlog');
  });

  it('decorates the matched task when the terminal switches branch', () => {
    const s = reducer(seedState(), { type: 'term', input: 'git switch -c APP-112-flaky-sync-test' });
    expect(s.focusedBranch).toBe('APP-112-flaky-sync-test');
    expect(s.tasks.find((t) => t.id === 'APP-112')!.branch).toBe('APP-112-flaky-sync-test');
    expect(s.done.git).toBe(true);
  });

  it('captures tasks into To do and blocks into the calendar', () => {
    let s = reducer(seedState(), { type: 'capture', item: parseCapture('ship v1 tomorrow', WED)!, todayIndex: WED });
    expect(tasksIn(s.tasks, 'todo')[0].title).toBe('Ship v1');
    s = reducer(s, { type: 'capture', item: parseCapture('focus parser 16:00', WED)!, todayIndex: WED });
    expect(s.events.at(-1)).toMatchObject({ kind: 'focus', day: WED, start: 960, end: 1050 });
    s = reducer(s, { type: 'capture', item: parseCapture('APP-231 fix login p1', WED)!, todayIndex: WED });
    expect(tasksIn(s.tasks, 'todo')[0]).toMatchObject({ id: 'APP-231', prio: 'P1' });
    s = reducer(s, { type: 'capture', item: parseCapture('call with @lena tomorrow 4pm', WED)!, todayIndex: WED });
    expect(s.events.at(-1)).toMatchObject({ kind: 'meeting', day: WED + 1, start: 960 });
    expect(s.tasks.find((t) => t.id === s.events.at(-1)!.taskId)?.title).toBe('Call with @lena');
  });

  it('opens an existing note by title or creates the missing one', () => {
    let s = reducer(seedState(), { type: 'openNoteByTitle', title: 'rate limiter design' });
    expect(s.activeNoteId).toBe('rate-limiter');
    s = reducer(s, { type: 'openNoteByTitle', title: 'Retry budget' });
    expect(s.notes.at(-1)!.title).toBe('Retry budget');
    expect(s.activeNoteId).toBe(s.notes.at(-1)!.id);
  });

  it('renames a note from its first heading', () => {
    const s = reducer(seedState(), { type: 'note', id: 'daily', body: '## Wednesday\n\ntext' });
    expect(s.notes.find((n) => n.id === 'daily')!.title).toBe('Wednesday');
  });
});

describe('calendar helpers', () => {
  it('starts weeks on Monday', () => {
    const d = weekDates(new Date(2026, 8, 27)); // a Sunday
    expect(d[0].getDay()).toBe(1);
    expect(d[6].getDate()).toBe(27);
    expect(weekdayIndex(new Date(2026, 8, 27))).toBe(6);
  });

  it('lays overlapping events side by side', () => {
    const ev = (id: string, start: number, end: number) => ({ id, title: id, day: 0, start, end, kind: 'meeting' as const });
    const placed = layoutDay([ev('a', 600, 660), ev('b', 630, 700), ev('c', 720, 750)]);
    const by = Object.fromEntries(placed.map((p) => [p.event.id, p]));
    expect([by.a.lane, by.b.lane, by.a.lanes]).toEqual([0, 1, 2]);
    expect(by.c.lanes).toBe(1);
  });

  it('finds the first free slot after the busy ones', () => {
    const busy = [
      { id: 'x', title: 'x', day: 1, start: 540, end: 600, kind: 'meeting' as const },
      { id: 'y', title: 'y', day: 1, start: 630, end: 720, kind: 'meeting' as const },
    ];
    expect(findFreeSlot(busy, 1, 0, 90)).toBe(720);
    expect(findFreeSlot(busy, 1, 0, 30)).toBe(600);
    expect(findFreeSlot(busy, 1, 17 * 60, 90)).toBeNull();
  });
});
