"""Synthesizes the venue soundtrack for the rendered video.

    python3 soundtrack.py meta.json out.wav [seconds]

meta.json is window.__meta from the page: the same cue list the browser plays
live, so the room reacts at the same moments in the video. Everything is made
from noise and oscillators; there are no samples. Needs numpy.
"""
import json
import sys
import wave

import numpy as np

SR = 48000
meta = json.load(open(sys.argv[1]))
OUT = sys.argv[2]
DUR = float(sys.argv[3]) if len(sys.argv) > 3 else float(meta["DUR"])
N = int(DUR * SR) + SR
rng = np.random.default_rng(2026)
mix = np.zeros((2, N))


def band(x, lo, hi):
    """Brick-wall band-pass via FFT. Fine for noise shaping."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(X, len(x))


def env(n, a, r):
    """Attack/release envelope in seconds over n samples."""
    t = np.arange(n) / SR
    e = np.minimum(1, t / max(a, 1e-4))
    tail = (n / SR) - r
    e *= np.where(t > tail, np.exp(-(t - tail) / (r / 4)), 1)
    return e


def add(x, t0, pan=0.0, gain=1.0):
    i = int(t0 * SR)
    if i >= N:
        return
    x = x[: N - i]
    left, right = np.sqrt((1 - pan) / 2), np.sqrt((1 + pan) / 2)
    mix[0, i:i + len(x)] += x * left * gain
    mix[1, i:i + len(x)] += x * right * gain


def claps(dur, density):
    n = int(dur * SR)
    out = np.zeros((2, n))
    kernel_len = int(0.012 * SR)
    kt = np.arange(kernel_len) / SR
    for ch in range(2):
        imp = np.zeros(n)
        count = int(dur * density)
        pos = rng.integers(0, n, count)
        imp[pos] = rng.uniform(0.2, 1, count)
        kernel = rng.standard_normal(kernel_len) * np.exp(-kt / 0.0022)
        out[ch] = band(np.convolve(imp, kernel, mode="same"), 700, 6500)
    return out / (np.abs(out).max() + 1e-9)


def applause(t0, dur, level):
    total = dur + 1.6
    c = claps(total, 190 * level + 60) * env(int(total * SR), 0.35, 1.6)
    add(c[0], t0, -0.6, 0.30 * level)
    add(c[1], t0, 0.6, 0.30 * level)


def cheer(t0, dur, level):
    applause(t0, dur, level)
    total = dur + 1.4
    n = int(total * SR)
    swell = band(rng.standard_normal(n), 700, 2600) * env(n, 0.25, 1.4)
    add(swell / (np.abs(swell).max() + 1e-9), t0, 0, 0.12 * level)
    for _ in range(4):  # a few "woo"s from the crowd
        d = rng.uniform(0.5, 0.9)
        m = int(d * SR)
        t = np.arange(m) / SR
        f = rng.uniform(420, 620) * (1 + 0.5 * np.sin(np.pi * t / d)) * (1 + 0.02 * np.sin(2 * np.pi * 6 * t))
        v = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / d) ** 2
        add(v, t0 + rng.uniform(0, dur * 0.6), rng.uniform(-0.8, 0.8), 0.025 * level)


def laugh(t0, dur, level):
    total = dur + 0.8
    n = int(total * SR)
    t = np.arange(n) / SR
    for v in range(9):
        rate = rng.uniform(4.2, 6.2)
        ph = rng.uniform(0, 1)
        pulses = np.clip(np.sin(np.pi * ((t * rate + ph) % 1)), 0, 1) ** 3
        decay = np.exp(-t / (dur * rng.uniform(0.5, 0.9)))
        lo = rng.uniform(300, 700)
        voice = band(rng.standard_normal(n), lo, lo * 2.4) * pulses * decay * env(n, 0.05, 0.6)
        voice /= np.abs(voice).max() + 1e-9
        add(voice, t0 + rng.uniform(0, 0.3), rng.uniform(-0.9, 0.9), 0.07 * level)


def typing(t0, dur):
    k = 0.0
    while k < dur:
        m = int(0.018 * SR)
        click = band(rng.standard_normal(m), 1800, 7000) * np.exp(-np.arange(m) / SR / 0.003)
        add(click, t0 + k, rng.uniform(-0.3, 0.3), rng.uniform(0.03, 0.07))
        k += rng.uniform(0.05, 0.14)


def riser(t0, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = rng.standard_normal(n)
    out = np.zeros(n)
    steps = 24
    for s in range(steps):  # sweep the band upward in slices
        a, b = s * n // steps, (s + 1) * n // steps
        f = 200 * (30 ** (s / steps))
        out[a:b] = band(x, f, f * 1.8)[a:b]
    out /= np.abs(out).max() + 1e-9
    tone = np.sin(2 * np.pi * np.cumsum(80 * 4 ** (t / dur)) / SR)
    add((out * 0.6 + tone * 0.25) * (t / dur) ** 2, t0, 0, 0.4)


def boom(t0):
    n = int(2.2 * SR)
    t = np.arange(n) / SR
    f = 70 * (28 / 70) ** np.minimum(1, t / 1.4)
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.55)
    hit = band(rng.standard_normal(n), 30, 900) * np.exp(-t / 0.18)
    hit /= np.abs(hit).max() + 1e-9
    add(np.tanh(sub * 1.6) * 0.8 + hit * 0.35, t0, 0, 0.9)


def note(freq, dur, kind="tri", level=0.1):
    n = int(dur * SR)
    t = np.arange(n) / SR
    if kind == "saw":
        x = sum(np.sin(2 * np.pi * freq * k * t) / k for k in range(1, 9))
    else:
        x = sum(np.sin(2 * np.pi * freq * k * t) * ((-1) ** ((k - 1) // 2)) / k ** 2 for k in (1, 3, 5, 7))
    return x * np.exp(-t / (dur / 3)) * np.minimum(1, t / 0.01) * level


def kick(level):
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    f = 50 + 90 * np.exp(-t / 0.03)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.12) * level


def hat(level):
    n = int(0.05 * SR)
    return band(rng.standard_normal(n), 6000, 14000) * np.exp(-np.arange(n) / SR / 0.012) * level


midi = lambda m: 440 * 2 ** ((m - 69) / 12)


def music(t0, kind, dur):
    if kind == "slate":
        bpm, prog = 84, [[57, 60, 64, 67], [53, 57, 60, 64], [48, 52, 55, 59], [55, 59, 62, 64]]
        beat = 60 / bpm
        b = 0
        while b * beat < dur:
            t = t0 + b * beat
            fade = min(1, (dur - b * beat) / 1.5)
            if b % 4 == 0:
                for m in prog[(b // 4) % 4]:
                    add(note(midi(m), beat * 4, "tri", 0.05 * fade), t, rng.uniform(-0.4, 0.4))
            if b % 2 == 0:
                add(kick(0.35 * fade), t)
            add(hat(0.05 * fade), t + beat / 2, 0.3)
            b += 1
        n = int(dur * SR)  # vinyl crackle
        crackle = np.zeros(n)
        idx = rng.integers(0, n, int(dur * 25))
        crackle[idx] = rng.uniform(-1, 1, len(idx))
        add(band(crackle, 1500, 9000), t0, 0, 0.12)
    else:
        bpm, roots = 124, [45, 45, 41, 43]
        beat = 60 / bpm
        b = 0
        while b * beat < dur:
            t = t0 + b * beat
            fade = min(1, (dur - b * beat) / 2)
            root = roots[(b // 4) % 4]
            add(kick(0.5 * fade), t)
            add(hat(0.08 * fade), t + beat / 2, 0.25)
            add(note(midi(root), beat * 0.45, "saw", 0.06 * fade), t + beat / 2)
            if b % 4 == 0:
                for i in (0, 4, 7, 11):
                    add(note(midi(root + 24 + i), beat * 1.5, "saw", 0.018 * fade), t, rng.uniform(-0.5, 0.5))
            b += 1


# --- the room: crowd walla, room tone, PA hum -------------------------------
t = np.arange(N) / SR
bed_level = np.interp(t, [0, 11.5, 12.5, 20, 21.5, DUR], [0.10, 0.10, 0.045, 0.04, 0.018, 0.018])
walla = np.zeros(N)
for v in range(10):  # individual murmuring voices, each drifting in and out
    rate = rng.uniform(3.2, 5.5)
    syll = np.clip(np.sin(2 * np.pi * rate * t + rng.uniform(0, 6.28)), 0, 1) ** 2
    drift = 0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(0.03, 0.09) * t + rng.uniform(0, 6.28))
    lo = rng.uniform(250, 500)
    walla += band(rng.standard_normal(N), lo, lo * 4) * syll * drift
walla /= np.abs(walla).max() + 1e-9
mix[0] += walla * bed_level * 1.6
mix[1] += np.roll(walla, 911) * bed_level * 1.6
hum = (np.sin(2 * np.pi * 60 * t) * 0.6 + np.sin(2 * np.pi * 120 * t) * 0.3) * 0.004
mix += hum + band(rng.standard_normal(N), 2000, 12000) * 0.0025

# --- cues ---------------------------------------------------------------------
for c in meta["CUES"]:
    kind, t0 = c["type"], c["t"]
    if t0 > DUR:
        continue
    d, lvl = c.get("dur", 1), c.get("level", 1)
    if kind == "applause":
        applause(t0, d, lvl)
    elif kind == "cheer":
        cheer(t0, d, lvl)
    elif kind == "laugh":
        laugh(t0, d, lvl)
    elif kind == "typing":
        typing(t0, d)
    elif kind == "riser":
        riser(t0, d)
    elif kind == "boom":
        boom(t0)
    elif kind == "music":
        music(t0, c["kind"], d)

# --- room reverb on everything but the hum ------------------------------------
ir_len = int(1.3 * SR)
ir_t = np.arange(ir_len) / SR
for ch in range(2):
    ir = rng.standard_normal(ir_len) * np.exp(-ir_t / 0.32) * 0.02
    ir[0] = 1.0
    size = 1 << int(np.ceil(np.log2(N + ir_len)))
    mix[ch] = np.fft.irfft(np.fft.rfft(mix[ch], size) * np.fft.rfft(ir, size), size)[:N]

# --- the stream drops out (with a stutter) and comes back ------------------------
for c in meta["CUES"]:
    if c["type"] == "dropout":
        a, b = int(c["t"] * SR), int((c["t"] + c["dur"]) * SR)
        chunk = mix[:, a - 2400:a].copy()
        for k in range(3):
            mix[:, a + k * 2400:a + (k + 1) * 2400] = chunk * (0.8 - k * 0.25)
        mix[:, a + 7200:b] = 0
        ramp = np.minimum(1, np.arange(4800) / 4800)
        mix[:, b:b + 4800] *= ramp

mix = mix[:, : int(DUR * SR)]
mix = np.tanh(mix * 1.1)
mix /= np.abs(mix).max() / 0.89
pcm = (mix.T * 32767).astype("<i2")
with wave.open(OUT, "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print(f"soundtrack: {DUR:.1f}s -> {OUT}")
