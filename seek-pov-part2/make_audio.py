"""Synthesizes the soundtrack for Seek POV Part 2 from timeline.json (written by render.cjs).

Pure standard library: python3 make_audio.py -> seek-pov-part2-audio.wav
"""
import json, math, os, random, struct, wave

HERE = os.path.dirname(os.path.abspath(__file__))
TL = json.load(open(os.path.join(HERE, 'timeline.json')))
SR = 22050
DUR = TL['DUR']
N = int(DUR * SR)
buf = [0.0] * N
rnd = random.Random(48)
TAU = 2 * math.pi
CUT, SHUT = TL['CUT'], TL['SHUT']


def ss(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def add(start, samples, gain=1.0):
    i0 = int(start * SR)
    for k, v in enumerate(samples):
        if 0 <= i0 + k < N:
            buf[i0 + k] += v * gain


def env(n, a, d):
    na = max(1, int(a * SR))
    return [min(1.0, k / na) * math.exp(-max(0, k - na) / (d * SR)) for k in range(n)]


def lowpass(xs, cutoff):
    a = 1 - math.exp(-TAU * cutoff / SR)
    y, out = 0.0, []
    for x in xs:
        y += a * (x - y)
        out.append(y)
    return out


def bandnoise(n, lo, hi):
    w = [rnd.uniform(-1, 1) for _ in range(n)]
    a = lowpass(w, hi)
    b = lowpass(a, lo)
    return [x - y for x, y in zip(a, b)]


def sweep(n, f0, f1, shape=1.0):
    ph, out = 0.0, []
    for k in range(n):
        u = k / n
        ph += TAU * (f0 + (f1 - f0) * u ** shape) / SR
        out.append(math.sin(ph))
    return out


# Seek's drone: tense while carrying, gone after the flash, a thin hum from the drain
noise = lowpass([rnd.uniform(-1, 1) for _ in range(N)], 90)
for i in range(N):
    t = i / SR
    lvl = 0.12 + 0.12 * ss(4, 6, t) - 0.1 * ss(44, 46, t) + 0.15 * ss(53, 55.4, t)
    if 55.6 < t < CUT:
        lvl = 0.05
    if t >= CUT:
        lvl = 0.06 * (1 - ss(SHUT + 0.5, SHUT + 1.5, t)) + 0.05 * ss(SHUT + 1, SHUT + 2.5, t) * (1 - ss(DUR - 1.5, DUR, t))
    v = (math.sin(TAU * 41.2 * t) + 0.7 * math.sin(TAU * 61.9 * t + 1.3) + 0.35 * math.sin(TAU * 82.6 * t)) * 0.5
    buf[i] += (v * (0.75 + 0.25 * math.sin(TAU * 0.13 * t)) + noise[i] * 3.0) * lvl
    # restroom fluorescent hum
    if 24 < t < SHUT:
        buf[i] += (((t * 120) % 1) * 2 - 1) * 0.012

# Seek's wet footsteps
for st in TL['STEPS']:
    n = int(0.28 * SR)
    e1, e2, sq = env(n, 0.004, 0.07), env(n, 0.002, 0.035), bandnoise(n, 200, 1400)
    add(st, [e1[k] * math.sin(TAU * (55 + 40 * e1[k]) * k / SR) + e2[k] * sq[k] * 2.5 for k in range(n)], 0.3)

# eyes blooming
for e in TL['EYES']:
    if e['t'] > 0:
        n = int(0.5 * SR)
        en, sq, sw = env(n, 0.02, 0.12), bandnoise(n, 300, 2500), sweep(n, 420, 70, 0.3)
        add(e['t'] - 0.1, [en[k] * (sq[k] * 2 * (0.5 + 0.5 * sw[k]) + 0.3 * sw[k]) for k in range(n)], 0.22)

# flicker buzz
for a, b in TL['FLICKER']:
    t = a
    while t < b:
        if rnd.random() < 0.45:
            add(t, [((1 if (k * 120 / SR) % 1 < 0.5 else -1) * 0.5 + rnd.uniform(-1, 1) * 0.5) for k in range(int(0.05 * SR))], 0.05)
        t += 0.05

# one-shot effects
for fx in TL['SFX']:
    t, kind = fx['t'], fx['k']
    if kind == 'grab':
        n = int(0.6 * SR); en, sq = env(n, 0.005, 0.15), bandnoise(n, 150, 1800); sw = sweep(n, 260, 60, 0.4)
        add(t - 0.05, [en[k] * (sq[k] * 2.5 + 0.6 * sw[k]) for k in range(n)], 0.5)
    elif kind == 'whoosh':
        n = int(0.9 * SR); sq = bandnoise(n, 400, 3000)
        add(t, [sq[k] * math.sin(math.pi * k / n) ** 2 * 3 for k in range(n)], 0.5)
    elif kind == 'splash':
        n = int(1.4 * SR); en, sq = env(n, 0.003, 0.35), bandnoise(n, 500, 6000)
        add(t, [en[k] * sq[k] * 3 + (env(n, 0.002, 0.05)[k] * math.sin(TAU * 90 * k / SR) if k < 3000 else 0) for k in range(n)], 0.6)
        for j in range(14):   # droplets
            m = int(0.06 * SR); f = 900 + rnd.random() * 1500
            add(t + 0.25 + rnd.random() * 1.2, [math.sin(TAU * f * (1 + 0.6 * k / m) * k / SR) * math.exp(-k / (0.015 * SR)) for k in range(m)], 0.12)
    elif kind == 'thud':
        n = int(0.4 * SR); en = env(n, 0.002, 0.08)
        add(t, [en[k] * math.sin(TAU * (50 + 60 * en[k]) * k / SR) for k in range(n)], 0.7)
    elif kind == 'bang':
        n = int(1.2 * SR); en, sq = env(n, 0.001, 0.12), bandnoise(n, 80, 2500)
        add(t, [en[k] * (sq[k] * 3 + math.sin(TAU * 70 * k / SR)) for k in range(n)], 0.75)
    elif kind == 'flash':
        n = int(0.08 * SR); add(t - 0.12, [rnd.uniform(-1, 1) * math.exp(-k / (0.004 * SR)) for k in range(n)], 0.5)   # shutter click
        n = int(0.9 * SR); sw = sweep(n, 1800, 3800, 0.5); en = env(n, 0.005, 0.25)
        add(t, [en[k] * sw[k] for k in range(n)], 0.2)
    elif kind == 'bonk':
        n = int(0.7 * SR); en = env(n, 0.001, 0.12); sq = bandnoise(n, 300, 4000)
        add(t, [en[k] * (math.sin(TAU * 180 * k / SR) * 0.8 + math.sin(TAU * 410 * k / SR) * 0.4 + sq[k] * 1.5) for k in range(n)], 0.75)
    elif kind == 'slurp':
        n = int(2.8 * SR); sq = bandnoise(n, 100, 1200); sw = sweep(n, 300, 40, 0.7)
        add(t, [sq[k] * 2.5 * (0.5 + 0.5 * sw[k]) * math.sin(math.pi * k / n) + 0.4 * sw[k] * math.sin(math.pi * k / n) for k in range(n)], 0.55)
    elif kind == 'drip':
        tt = t + 0.3
        while tt < SHUT:
            m = int(0.08 * SR); f = 700 + rnd.random() * 500
            add(tt, [math.sin(TAU * f * (1 + 0.8 * k / m) * k / SR) * math.exp(-k / (0.02 * SR)) for k in range(m)], 0.1)
            tt += 0.9 + rnd.random() * 1.1

# voices: syllable blips per character (Senpai's wobble while crying)
BASE = {'N': 600, 'S': 290, 'G': 520, 'K': 700}
for ln in TL['LINES']:
    cps = TL['CPS']
    for ci, ch in enumerate(ln['text']):
        if ch in ' .,!?~—-*♪' or ci % 2:
            continue
        t = ln['s'] + ci / cps
        if t > ln['e'] - 0.15:
            break
        f = BASE[ln['who']] * (1 + rnd.uniform(-0.12, 0.14))
        if ln['who'] == 'S' and 35 < ln['s'] < 40:
            f *= 1 + 0.08 * math.sin(t * 40)
        n = int(0.065 * SR); e = env(n, 0.004, 0.025)
        add(t, [e[k] * (0.6 * math.sin(TAU * f * k / SR) + 0.4 * (1 if (f * k / SR) % 1 < 0.35 else -1)) for k in range(n)], 0.075)

# sobbing hiccups under Senpai's breakdown
for t in [35.0, 36.3, 37.1, 38.6, 40.2, 41.5, 42.4]:
    n = int(0.18 * SR); en = env(n, 0.01, 0.05); sw = sweep(n, 380, 300)
    add(t, [en[k] * sw[k] for k in range(n)], 0.12)

# a soft music-box sting as the eye shuts
for j, f in enumerate([659.3, 587.3, 523.3, 493.9]):
    n = int(1.6 * SR); e = env(n, 0.003, 0.5)
    add(SHUT + 0.4 + j * 0.45, [e[k] * (math.sin(TAU * f * k / SR) + 0.3 * math.sin(TAU * f * 3 * k / SR)) for k in range(n)], 0.08)

peak = max(abs(v) for v in buf) or 1
out = [math.tanh(v / peak * 1.6) * 0.89 for v in buf]
for k in range(SR):
    out[-1 - k] *= k / SR
with wave.open(os.path.join(HERE, 'seek-pov-part2-audio.wav'), 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v)) * 32767)) for v in out))
print('wrote seek-pov-part2-audio.wav', DUR, 's')
