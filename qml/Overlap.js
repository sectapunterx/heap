.pragma library

// Side-by-side layout for events that share a time window.
//
// Two meetings at 10:00 used to be drawn exactly on top of each other in the
// week grid — the second one hid the first, and only the top one could be
// clicked. The day grid had solved this; the week grid had never been taught.
// Rather than a second copy of the algorithm, both now call this.
//
// Given [{ id, start, end }, …] it returns { id: { col, cols } }: which column
// an event sits in, and how many columns its overlap cluster spans, so the
// caller can size it to 1/cols of the day's width.

// Events that overlap each other form a cluster. Every member of a cluster
// gets the cluster's column count, so their widths match and they tile the
// day exactly — sizing each one by its own neighbours would leave gaps.
function _flush(cluster, map) {
    const colEnds = [];   // the last end-time occupying each column
    for (let k = 0; k < cluster.length; k++) {
        const e = cluster[k];
        let placed = false;
        for (let c = 0; c < colEnds.length; c++) {
            if (e.start >= colEnds[c] - 1e-9) {   // that column is free again
                colEnds[c] = e.end;
                e._col = c;
                placed = true;
                break;
            }
        }
        if (!placed) { e._col = colEnds.length; colEnds.push(e.end); }
    }
    const total = Math.max(1, colEnds.length);
    for (let k = 0; k < cluster.length; k++)
        map[cluster[k].id] = { col: cluster[k]._col, cols: total };
}

// `events` is [{ id, start, end }, …] for ONE day. Events from different days
// never overlap, so the caller groups first.
function compute(events) {
    const evs = events.slice();
    // By start, then end. The sweep below depends on it.
    evs.sort(function (a, b) { return (a.start - b.start) || (a.end - b.end); });

    const map = {};
    let cluster = [];
    let clusterEnd = -1;
    for (let i = 0; i < evs.length; i++) {
        const e = evs[i];
        if (cluster.length === 0) { cluster = [e]; clusterEnd = e.end; continue; }
        if (e.start < clusterEnd - 1e-9) {        // overlaps the running cluster
            cluster.push(e);
            clusterEnd = Math.max(clusterEnd, e.end);
        } else {
            _flush(cluster, map);
            cluster = [e];
            clusterEnd = e.end;
        }
    }
    if (cluster.length > 0) _flush(cluster, map);
    return map;
}

// Same, for a week: `days` is [[{id,start,end}, …], …], one list per day.
// Returns one flat map, because ids are unique across the week.
function computeByDay(days) {
    const map = {};
    for (let i = 0; i < days.length; i++) {
        const dayMap = compute(days[i]);
        for (const id in dayMap) map[id] = dayMap[id];
    }
    return map;
}

// Where a slot from compute() goes across `avail` pixels: { x, w }.
//
// Tiled 1/cols each while a lane is at least `minW` wide. Past that a fourth
// meeting in a 130px day left lanes ~30px wide, titles cut to two letters or
// to the time alone (VISU-15). Then the lanes cascade instead: each keeps
// `minW` (never more than the whole width) and steps right by an equal share
// of what is left, the later column drawn over the earlier one. Clusters are
// sorted by start, so an earlier event's top — where its title is — still
// shows above the one that covers its right side.
// The narrowest a lane gets before the lanes cascade (`minW` overrides).
const MIN_LANE_W = 64;

function lane(col, cols, avail, minW) {
    if (minW === undefined) minW = MIN_LANE_W;
    const n = Math.max(1, cols);
    const tile = avail / n;
    if (n === 1 || tile >= minW) return { x: col * tile, w: tile };
    const w = Math.min(avail, minW);
    const stepX = (avail - w) / (n - 1);
    return { x: col * stepX, w: w };
}
