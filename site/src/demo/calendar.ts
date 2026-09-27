import type { CalEvent } from './model';

export const SNAP = 15;

export function snap(min: number, step = SNAP): number {
  return Math.round(min / step) * step;
}

export function clamp(v: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, v));
}

/** 0 = Monday … 6 = Sunday. */
export function weekdayIndex(d: Date): number {
  return (d.getDay() + 6) % 7;
}

export function weekDates(today: Date): Date[] {
  const monday = new Date(today);
  monday.setHours(0, 0, 0, 0);
  monday.setDate(monday.getDate() - weekdayIndex(today));
  return Array.from({ length: 7 }, (_, i) => {
    const d = new Date(monday);
    d.setDate(monday.getDate() + i);
    return d;
  });
}

export interface Placed {
  event: CalEvent;
  lane: number;
  lanes: number;
}

/** Lay overlapping events side by side, the way heap.'s week view does. */
export function layoutDay(events: CalEvent[]): Placed[] {
  const sorted = [...events].sort((a, b) => a.start - b.start || b.end - a.end);
  const out: Placed[] = [];
  let cluster: Placed[] = [];
  let clusterEnd = -1;
  const flush = () => {
    const lanes = cluster.reduce((m, p) => Math.max(m, p.lane + 1), 1);
    for (const p of cluster) p.lanes = lanes;
    out.push(...cluster);
    cluster = [];
  };
  for (const ev of sorted) {
    if (cluster.length && ev.start >= clusterEnd) flush();
    const taken = new Set(cluster.filter((p) => p.event.end > ev.start).map((p) => p.lane));
    let lane = 0;
    while (taken.has(lane)) lane++;
    cluster.push({ event: ev, lane, lanes: 1 });
    clusterEnd = Math.max(clusterEnd, ev.end);
  }
  flush();
  return out;
}

/** First gap of `dur` minutes on `day` between `from` and `until`, or null. */
export function findFreeSlot(events: CalEvent[], day: number, from: number, dur: number, until = 18 * 60): number | null {
  const busy = events.filter((e) => e.day === day).sort((a, b) => a.start - b.start);
  let t = snap(Math.max(from, 9 * 60) + SNAP / 2 - 1);
  for (const e of busy) {
    if (e.end <= t) continue;
    if (e.start - t >= dur) break;
    t = Math.max(t, e.end);
  }
  return t + dur <= until ? t : null;
}
