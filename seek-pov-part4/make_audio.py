"""Synthesizes the soundtrack for Seek POV Part 4 from timeline.json (written by render.cjs).

Pure standard library: python3 make_audio.py -> seek-pov-part4-audio.wav
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
HIDE, NOISE, END, FALL0, LAND = TL['HIDE'], TL['NOISE'], TL['END'], TL['FALL0'], TL['LAND']


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


# Seek's drone in the hall; in the garden: night wind, crickets, and a held breath
noise = lowpass([rnd.uniform(-1, 1) for _ in range(N)], 90)
wind = lowpass([rnd.uniform(-1, 1) for _ in range(N)], 400)
for i in range(N):
    t = i / SR
    lvl = 0.16 + 0.1 * ss(12, 15, t)
    if t > FALL0:
        lvl = 0.07 + 0.08 * ss(36, 40, t) * (1 - ss(NOISE, NOISE + 2, t))
    if t > END:
        lvl = 0.05 * ss(END + 1, END + 2.5, t) * (1 - ss(DUR - 1.5, DUR, t))
    v = (math.sin(TAU * 41.2 * t) + 0.7 * math.sin(TAU * 61.9 * t + 1.3) + 0.35 * math.sin(TAU * 82.6 * t)) * 0.5
    buf[i] += (v * (0.75 + 0.25 * math.sin(TAU * 0.13 * t)) + noise[i] * 3.0) * lvl
    if FALL0 < t < END:
        buf[i] += wind[i] * 1.6 * (0.5 + 0.5 * math.sin(TAU * 0.07 * t)) * (2.5 if t < LAND else 1)
        if t > LAND + 2 and not (36.5 < t < NOISE + 1):   # crickets go silent while Seek stands over them
            c = math.sin(TAU * 4200 * t) * (1 if (t * 18) % 1 < 0.4 else 0) * (1 if (t * 0.9) % 1 < 0.6 else 0)
            buf[i] += c * 0.025
    if t < FALL0:
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
for a, b in TL.get('FLICKER', []):
    t = a
    while t < b:
        if rnd.random() < 0.45:
            add(t, [((1 if (k * 120 / SR) % 1 < 0.5 else -1) * 0.5 + rnd.uniform(-1, 1) * 0.5) for k in range(int(0.05 * SR))], 0.05)
        t += 0.05

# one-shot effects
for fx in TL['SFX']:
    t, kind = fx['t'], fx['k']
    if kind == 'tackle':
        n = int(0.6 * SR); en, sq = env(n, 0.002, 0.12), bandnoise(n, 80, 2000)
        add(t, [en[k] * (sq[k] * 2.5 + math.sin(TAU * 60 * k / SR)) for k in range(n)], 0.7)
    elif kind == 'thud':
        n = int(0.4 * SR); en = env(n, 0.002, 0.08)
        add(t, [en[k] * math.sin(TAU * (50 + 60 * en[k]) * k / SR) for k in range(n)], 0.6)
    elif kind == 'windup':
        n = int(1.8 * SR); sw = sweep(n, 60, 240, 1.5); sq = bandnoise(n, 100, 900)
        add(t, [(sw[k] * 0.5 + sq[k] * 2) * (k / n) ** 2 for k in range(n)], 0.4)
    elif kind == 'punch':
        n = int(3.5 * SR); e = env(n, 0.002, 0.7); sq = bandnoise(n, 40, 5000)
        add(t, [e[k] * (sq[k] * 3 + math.sin(TAU * (35 + 80 * math.exp(-k / SR * 6)) * k / SR) * 1.5) for k in range(n)], 1.0)
        for j in range(30):   # floor chunks cracking
            m = int(0.05 * SR); add(t + 0.1 + rnd.random() * 1.5, [rnd.uniform(-1, 1) * math.exp(-k / (0.01 * SR)) for k in range(m)], 0.25)
    elif kind == 'wind':
        n = int((LAND - FALL0) * SR); sq = bandnoise(n, 200, 3000)
        add(t, [sq[k] * 3 * (k / n) for k in range(n)], 0.5)
    elif kind == 'land':
        for j in range(18):
            m = int(0.12 * SR); en = env(m, 0.002, 0.03); sq = bandnoise(m, 100, 3000)
            add(t + rnd.random() * 0.8, [en[k] * sq[k] * 3 for k in range(m)], 0.35)
    elif kind == 'pot':
        n = int(0.9 * SR); en = env(n, 0.001, 0.15); sq = bandnoise(n, 600, 6000)
        add(t, [en[k] * (sq[k] * 3 + math.sin(TAU * 900 * k / SR) * 0.4) for k in range(n)], 0.5)

# heartbeat while Seek stands over the grass
t = 36.0
while t < NOISE + 0.5:
    for off, g in ((0, 1.0), (0.16, 0.7)):
        n = int(0.22 * SR); e = env(n, 0.003, 0.06)
        add(t + off, [e[k] * math.sin(TAU * (48 + 30 * e[k]) * k / SR) for k in range(n)], 0.45 * g)
    t += 60 / (80 + 40 * ss(36, NOISE, t))

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
        if False:
            f *= 1 + 0.08 * math.sin(t * 40)
        n = int(0.065 * SR); e = env(n, 0.004, 0.025)
        if 'whisper' in ln['text']:
            add(t, [e[k] * rnd.uniform(-1, 1) for k in range(n)], 0.05)
        else:
            add(t, [e[k] * (0.6 * math.sin(TAU * f * k / SR) + 0.4 * (1 if (f * k / SR) % 1 < 0.35 else -1)) for k in range(n)], 0.075)

peak = max(abs(v) for v in buf) or 1
out = [math.tanh(v / peak * 1.6) * 0.89 for v in buf]
for k in range(SR):
    out[-1 - k] *= k / SR
with wave.open(os.path.join(HERE, 'seek-pov-part4-audio.wav'), 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v)) * 32767)) for v in out))
print('wrote seek-pov-part4-audio.wav', DUR, 's')
