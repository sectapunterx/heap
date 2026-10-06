#!/usr/bin/env python3
"""Generates heap's sound palette into design/sounds/: done, undo and refuse
(APP-177) and the three meeting chimes (APP-178).

Low and muffled, like knocking on wood through cloth: each sound is one or two
"thuds" — a sine and a quieter octave below it, with a slight pitch drop in the
first 30 ms like a soft knock — under a steep (4th-order) low-pass, with a soft
linear attack and an exponential decay to silence. Everything sits in A:

    done    two thuds going up    A3 (220 Hz) → D4 (293.66 Hz)
    undo    the same going down   D4 → A3
    refuse  one low, short thud   A2 (110 Hz)

Each of those is under 150 ms. A meeting is the exception — it must not be
missed — so it gets a short melody, under a second, in the same muffled timbre:
a soft mallet (the note, a faint 4th partial that dies first, an octave below)
under the same kind of low-pass. As the meeting comes closer:

    meet-chords   two chords, A+E then C#+A        (15 min before by default)
    meet-rise     A, C#, E, A: four notes up        (10 min)
    meet-call     E, A, B, E: down and back, "hey"  (5 min)

Every file starts and ends on exact zero, so nothing clicks. All six share one
gain (the loudest peak lands on PEAK_DBFS), so their relative levels are as
designed; the app scales them by the volume setting.
16-bit PCM, mono, 44.1 kHz, deterministic: re-running the script writes the
same bytes.

    python tools/gen_sounds.py            # writes the committed files
    python tools/gen_sounds.py out_dir    # somewhere else
"""

import math
import struct
import sys
import wave
from pathlib import Path

RATE = 44100
PEAK_DBFS = -3.0
# A raised-cosine fade over the last few ms puts the tail on exact zero; the
# exponential decay is already near -80 dB there, so it changes nothing audible.
TAIL_FADE_S = 0.004

A2, A3, B3, CS4, D4, E4, A4 = 110.0, 220.0, 246.94, 277.18, 293.66, 329.63, 440.0

# (start s, frequency Hz, length s, relative peak, low-pass Hz, attack s)
SOUNDS = {
    "done": [
        (0.000, A3, 0.085, 1.00, 700.0, 0.008),
        (0.058, D4, 0.088, 0.90, 800.0, 0.008),
    ],
    "undo": [
        (0.000, D4, 0.085, 0.80, 800.0, 0.008),
        (0.058, A3, 0.088, 0.80, 700.0, 0.008),
    ],
    "refuse": [
        (0.000, A2, 0.140, 0.90, 450.0, 0.006),
    ],
}


def lowpass(samples, cutoff):
    """4th-order Butterworth low-pass: two RBJ biquads in cascade."""
    out = samples
    for q in (0.5412, 1.3066):
        w0 = 2 * math.pi * cutoff / RATE
        alpha = math.sin(w0) / (2 * q)
        cw = math.cos(w0)
        a0 = 1 + alpha
        b0 = (1 - cw) / 2 / a0
        b1 = (1 - cw) / a0
        b2 = b0
        a1 = -2 * cw / a0
        a2 = (1 - alpha) / a0
        x1 = x2 = y1 = y2 = 0.0
        filtered = []
        for x in out:
            y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1, y2, y1 = x1, x, y1, y
            filtered.append(y)
        out = filtered
    return out


def thud(freq, length, peak, cutoff, attack):
    n = int(round(RATE * length))
    tone = []
    phases = [0.0, 0.0]
    # The tone and a quieter octave below it: body without brightness.
    partials = [(freq, 1.0), (freq / 2, 0.55)]
    for i in range(n):
        t = i / RATE
        # A 4 % drop to pitch over the first 30 ms, exponential like the prototype.
        drop = 1.04 ** max(0.0, 1.0 - t / 0.030)
        s = 0.0
        for k, (f, a) in enumerate(partials):
            phases[k] += 2 * math.pi * f * drop / RATE
            s += a * math.sin(phases[k])
        tone.append(s)
    tone = lowpass(tone, cutoff)
    out = []
    floor = 1e-4
    for i, s in enumerate(tone):
        t = i / RATE
        if t < attack:
            env = peak * t / attack
        else:
            env = peak * (floor / peak) ** ((t - attack) / (length - attack))
        remaining = length - t
        if remaining < TAIL_FADE_S:
            env *= 0.5 - 0.5 * math.cos(math.pi * max(0.0, remaining) / TAIL_FADE_S)
        out.append(s * env)
    return out


# (start s, frequency Hz, length s) per mallet note, and the melody's peak.
CHIMES = {
    "meet-chords": ([(0.00, A3, 0.65), (0.00, E4, 0.65), (0.26, CS4, 0.70), (0.26, A4, 0.70)], 0.50),
    "meet-rise": ([(0.00, A3, 0.32), (0.14, CS4, 0.32), (0.28, E4, 0.32), (0.42, A4, 0.55)], 0.70),
    "meet-call": ([(0.00, E4, 0.28), (0.16, A3, 0.28), (0.32, B3, 0.28), (0.48, E4, 0.50)], 0.70),
}
MALLET_LOWPASS = 1100.0
MALLET_ATTACK = 0.012


def decay(peak, t, start, length):
    """Exponential from `peak` at `start` down to 1e-4 at `length`."""
    floor = 1e-4
    return peak * (floor / peak) ** (max(0.0, t - start) / (length - start))


def mallet(freq, length, peak):
    n = int(round(RATE * length))
    # (frequency multiple, level, how long it rings): the 4th partial dies first.
    partials = [(1.0, 1.0, length), (4.0, 0.12, length * 0.35), (0.5, 0.35, length)]
    tone = []
    for i in range(n):
        t = i / RATE
        s = 0.0
        for mul, level, ring in partials:
            if t < ring:
                s += decay(level, t, 0.0, ring) * math.sin(2 * math.pi * freq * mul * t)
        tone.append(s)
    tone = lowpass(tone, MALLET_LOWPASS)
    out = []
    for i, s in enumerate(tone):
        t = i / RATE
        env = peak * t / MALLET_ATTACK if t < MALLET_ATTACK else decay(peak, t, MALLET_ATTACK, length)
        remaining = length - t
        if remaining < TAIL_FADE_S:
            env *= 0.5 - 0.5 * math.cos(math.pi * max(0.0, remaining) / TAIL_FADE_S)
        out.append(s * env)
    return out


def render_chime(notes, peak):
    end = max(start + length for start, _, length in notes)
    buf = [0.0] * int(round(RATE * end))
    for start, freq, length in notes:
        offset = int(round(RATE * start))
        for i, v in enumerate(mallet(freq, length, peak)):
            if offset + i < len(buf):
                buf[offset + i] += v
    return buf


def render(spec):
    end = max(start + length for start, _, length, _, _, _ in spec)
    buf = [0.0] * int(round(RATE * end))
    for start, freq, length, peak, cutoff, attack in spec:
        offset = int(round(RATE * start))
        for i, v in enumerate(thud(freq, length, peak, cutoff, attack)):
            if offset + i < len(buf):
                buf[offset + i] += v
    return buf


def main():
    root = Path(__file__).resolve().parent.parent
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "design" / "sounds"
    out_dir.mkdir(parents=True, exist_ok=True)
    rendered = {name: render(spec) for name, spec in SOUNDS.items()}
    rendered.update({name: render_chime(notes, peak) for name, (notes, peak) in CHIMES.items()})
    peak = max(abs(v) for buf in rendered.values() for v in buf) or 1.0
    gain = (10 ** (PEAK_DBFS / 20)) / peak
    for name, buf in rendered.items():
        samples = [max(-32767, min(32767, int(round(v * gain * 32767)))) for v in buf]
        out = out_dir / f"{name}.wav"
        with wave.open(str(out), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(struct.pack("<%dh" % len(samples), *samples))
        print(f"{out}: {out.stat().st_size} bytes, {len(samples)} samples, {len(samples) / RATE * 1000:.0f} ms")


if __name__ == "__main__":
    main()
