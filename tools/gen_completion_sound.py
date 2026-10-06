#!/usr/bin/env python3
"""Generates design/sounds/complete.wav, the opt-in completion sound (APP-167).

A soft "tick": two sine partials (E6 and B6, a fifth apart) that decay
exponentially over ~120 ms, peaking at -18 dBFS so it never startles. A 3 ms
fade-in keeps the attack from clicking and a 12 ms fade-out lands the tail on
silence. 16-bit PCM, mono, 44.1 kHz, deterministic: re-running the script
writes the same bytes.

    python tools/gen_completion_sound.py            # writes the committed file
    python tools/gen_completion_sound.py out.wav    # somewhere else
"""

import math
import struct
import sys
import wave
from pathlib import Path

RATE = 44100
DURATION_S = 0.120
PEAK_DBFS = -18.0
FADE_IN_S = 0.003
FADE_OUT_S = 0.012

# (frequency Hz, relative amplitude, decay time constant in seconds)
PARTIALS = [
    (1318.51, 1.00, 0.030),  # E6, the body of the tick
    (1975.53, 0.45, 0.018),  # B6, a brighter, shorter overtone
]


def render():
    n = int(RATE * DURATION_S)
    raw = []
    for i in range(n):
        t = i / RATE
        s = sum(a * math.exp(-t / tau) * math.sin(2 * math.pi * f * t) for f, a, tau in PARTIALS)
        if t < FADE_IN_S:
            s *= t / FADE_IN_S
        remaining = DURATION_S - t
        if remaining < FADE_OUT_S:
            s *= max(0.0, remaining / FADE_OUT_S)
        raw.append(s)
    peak = max(abs(v) for v in raw) or 1.0
    gain = (10 ** (PEAK_DBFS / 20)) / peak
    return [int(round(v * gain * 32767)) for v in raw]


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "design" / "sounds" / "complete.wav"
    out.parent.mkdir(parents=True, exist_ok=True)
    samples = render()
    with wave.open(str(out), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(struct.pack("<%dh" % len(samples), *samples))
    print(f"{out}: {out.stat().st_size} bytes, {len(samples)} samples")


if __name__ == "__main__":
    main()
