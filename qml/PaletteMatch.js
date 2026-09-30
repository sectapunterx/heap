.pragma library

// Matching for the command palette.
//
// It used to be a single left-to-right subsequence over label + sub, so
// "ingress kubernetes" found nothing when the title said "Kubernetes ingress",
// and one transposed letter ("kubrenetes") lost the hit entirely. Now the query
// is split into words; every word has to land somewhere in the text, in any
// order, and each is scored on how well it lands:
//
//   whole word            100
//   word prefix            80
//   substring              55
//   typo (edit distance)   40 / 25   one / two edits (Damerau: a swap is one)
//   subsequence            ≤ 20      scattered letters, the old behaviour
//
// score(query, text) returns the sum, or -1 when any query word misses. An
// empty query scores 0.

function _words(s) {
    return String(s || "").toLowerCase().split(/[^0-9a-zа-яё_+#.-]+/i).filter(function (w) { return w.length > 0; });
}

// Optimal string alignment distance (Damerau–Levenshtein without repeated
// edits of one substring), capped: returns cap + 1 once it is certain to
// exceed `cap`.
function distance(a, b, cap) {
    if (Math.abs(a.length - b.length) > cap) return cap + 1;
    var prev2 = null, prev = [], cur;
    for (var j = 0; j <= b.length; j++) prev.push(j);
    for (var i = 1; i <= a.length; i++) {
        cur = [i];
        var rowMin = i;
        for (var k = 1; k <= b.length; k++) {
            var cost = a.charAt(i - 1) === b.charAt(k - 1) ? 0 : 1;
            var v = Math.min(prev[k] + 1, cur[k - 1] + 1, prev[k - 1] + cost);
            if (prev2 && i > 1 && k > 1 && a.charAt(i - 1) === b.charAt(k - 2) && a.charAt(i - 2) === b.charAt(k - 1))
                v = Math.min(v, prev2[k - 2] + 1);
            cur.push(v);
            if (v < rowMin) rowMin = v;
        }
        if (rowMin > cap) return cap + 1;
        prev2 = prev;
        prev = cur;
    }
    return prev[b.length];
}

// Edits a word of this length may be off by and still count.
function _typoBudget(len) {
    return len >= 8 ? 2 : len >= 4 ? 1 : 0;
}

function _subsequence(q, s) {
    var i = 0, lastPos = -2, score = 0;
    for (var j = 0; j < s.length && i < q.length; j++) {
        if (q.charAt(i) === s.charAt(j)) {
            score += (lastPos + 1 === j ? 3 : 1);
            lastPos = j;
            i++;
        }
    }
    if (i < q.length) return -1;
    return Math.min(20, score);
}

// How well one query word lands in `text` (lower-cased) with `words` its words.
function _wordScore(qw, text, words) {
    var best = -1;
    for (var i = 0; i < words.length; i++) {
        var w = words[i];
        if (w === qw) return 100;
        if (w.indexOf(qw) === 0) best = Math.max(best, 80);
    }
    if (best >= 80) return best;
    if (text.indexOf(qw) >= 0) return 55;
    var budget = _typoBudget(qw.length);
    if (budget > 0) {
        for (var t = 0; t < words.length; t++) {
            var cand = words[t];
            // Compare against the word, and against its head when the word is
            // longer (a typo in a prefix: "kubrn" for "kubernetes").
            var d = distance(qw, cand, budget);
            if (cand.length > qw.length + budget)
                d = Math.min(d, distance(qw, cand.slice(0, qw.length), budget));
            if (d <= budget) best = Math.max(best, d === 1 ? 40 : 25);
        }
        if (best >= 0) return best;
    }
    if (qw.length >= 2) return _subsequence(qw, text);
    return -1;
}

function score(query, text) {
    var qws = _words(query);
    if (qws.length === 0) return 0;
    var lower = String(text || "").toLowerCase();
    var words = _words(lower);
    var total = 0;
    for (var i = 0; i < qws.length; i++) {
        var s = _wordScore(qws[i], lower, words);
        if (s < 0) return -1;
        total += s;
    }
    // Words in the order they were typed read as a phrase: a small bonus.
    if (qws.length > 1 && lower.indexOf(qws.join(" ")) >= 0) total += 15;
    // Earlier hits rank a little higher.
    var first = lower.indexOf(qws[0]);
    if (first > 0) total -= Math.min(10, first * 0.1);
    return Math.max(0, total);
}

// Does every query word appear in `body` (plain substring)? For the
// full-text tier, where typo tolerance would drown the results.
function bodyHit(query, body) {
    var qws = _words(query);
    if (qws.length === 0 || !body) return false;
    var lower = String(body).toLowerCase();
    for (var i = 0; i < qws.length; i++) if (lower.indexOf(qws[i]) < 0) return false;
    return true;
}
