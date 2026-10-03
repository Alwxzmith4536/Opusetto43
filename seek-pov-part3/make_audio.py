"""Synthesizes the soundtrack for Seek POV Part 3 from timeline.json (written by render.cjs).

Pure standard library: python3 make_audio.py -> seek-pov-part3-audio.wav
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
CHASE0, CHASE1, CHARGE, IMPACT = TL['CHASE0'], TL['CHASE1'], TL['CHARGE'], TL['IMPACT']


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


# Seek's drone, then DOORS-style chase music: pounding bass pulse + rising siren
noise = lowpass([rnd.uniform(-1, 1) for _ in range(N)], 90)
for i in range(N):
    t = i / SR
    if t > IMPACT + 0.05 and t < IMPACT + 1.5:
        continue
    lvl = 0.12 + 0.15 * ss(11, 12.5, t) - 0.07 * ss(50, 51, t) + 0.12 * ss(CHARGE, IMPACT, t)
    if t > IMPACT:
        lvl = 0.06 * ss(IMPACT + 1.5, IMPACT + 3, t) * (1 - ss(DUR - 1.5, DUR, t))
    v = (math.sin(TAU * 41.2 * t) + 0.7 * math.sin(TAU * 61.9 * t + 1.3) + 0.35 * math.sin(TAU * 82.6 * t)) * 0.5
    buf[i] += (v * (0.75 + 0.25 * math.sin(TAU * 0.13 * t)) + noise[i] * 3.0) * lvl
    if CHASE0 - 1 < t < CHASE1 + 0.8:
        g = ss(CHASE0 - 1, CHASE0, t) * (1 - ss(CHASE1, CHASE1 + 0.8, t))
        beat = (t * 2.6) % 1                     # ~156 bpm
        kick = math.exp(-beat * 18) * math.sin(TAU * (50 + 90 * math.exp(-beat * 30)) * beat / 2.6)
        off = (t * 2.6 + 0.5) % 1
        stab = math.exp(-off * 10) * ((((t * 110) % 1) * 2 - 1) * 0.5 + (((t * 164.8) % 1) * 2 - 1) * 0.35)
        siren = math.sin(TAU * (520 + 140 * math.sin(TAU * 0.5 * t)) * t) * 0.18 * ss(CHASE0, CHASE1, t)
        buf[i] += (kick * 0.55 + stab * 0.12 + siren * 0.25) * g
    if 10 < t < IMPACT and t < 17.5:
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
    if kind == 'burst':
        n = int(2.0 * SR); en, sq = env(n, 0.003, 0.6), bandnoise(n, 60, 2500); sw = sweep(n, 90, 30, 0.5)
        add(t, [en[k] * (sq[k] * 3 + sw[k]) for k in range(n)], 0.8)
        n = int(1.2 * SR); sw = sweep(n, 200, 1400, 2.0)
        add(t - 0.4, [sw[k] * (k / n) for k in range(n)], 0.15)
    elif kind == 'grab':
        n = int(1.4 * SR); en, sq = env(n, 0.005, 0.5), bandnoise(n, 150, 1800); sw = sweep(n, 260, 60, 0.4)
        add(t - 0.05, [en[k] * (sq[k] * 2.5 + 0.6 * sw[k]) for k in range(n)], 0.5)
    elif kind == 'stop':
        n = int(0.5 * SR); en = env(n, 0.002, 0.1)
        add(t, [en[k] * math.sin(TAU * (45 + 50 * en[k]) * k / SR) for k in range(n)], 0.5)
    elif kind == 'impact':
        n = int(3.0 * SR); e = env(n, 0.003, 0.9); cl = [55.0, 58.3, 82.4, 116.5, 164.8]
        add(t, [e[k] * (sum(((f * k / SR) % 1) * 2 - 1 for f in cl) / 5 + rnd.uniform(-1, 1) * 0.5 * math.exp(-k / SR * 4)) for k in range(n)], 0.9)

# the runners' footsteps: quick slaps on the tile
tt = 17.0
while tt < CHASE1:
    n = int(0.05 * SR); add(tt, [rnd.uniform(-1, 1) * math.exp(-k / (0.008 * SR)) for k in range(n)], 0.12)
    tt += 0.17 + rnd.random() * 0.06

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
        if ln['who'] == 'N' and 20 < ln['s'] < 48:
            f *= 1 + 0.08 * math.sin(t * 40)
        n = int(0.065 * SR); e = env(n, 0.004, 0.025)
        add(t, [e[k] * (0.6 * math.sin(TAU * f * k / SR) + 0.4 * (1 if (f * k / SR) % 1 < 0.35 else -1)) for k in range(n)], 0.075)

# Nagatoro sobbing while carried
for t in [16.2, 21.5, 22.6, 27.5, 30.0, 33.8, 37.0, 42.2, 46.5, 48.0]:
    n = int(0.2 * SR); en = env(n, 0.01, 0.06); sw = sweep(n, 720, 560)
    add(t, [en[k] * sw[k] for k in range(n)], 0.1)

peak = max(abs(v) for v in buf) or 1
out = [math.tanh(v / peak * 1.6) * 0.89 for v in buf]
for k in range(SR):
    out[-1 - k] *= k / SR
with wave.open(os.path.join(HERE, 'seek-pov-part3-audio.wav'), 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v)) * 32767)) for v in out))
print('wrote seek-pov-part3-audio.wav', DUR, 's')
