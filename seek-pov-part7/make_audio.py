"""Synthesizes the soundtrack for Seek POV Part 7 from timeline.json (written by render.cjs).

Pure standard library: python3 make_audio.py -> seek-pov-part7-audio.wav
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
SSJ0, SSJ1, BEAM0, BEAM1, BOOM, END = TL['SSJ0'], TL['SSJ1'], TL['BEAM0'], TL['BEAM1'], TL['BOOM'], TL['END']
INSIDE = -5


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


# street drone, then an epic chiptune battle theme from the power-up until the K.O.
noise = lowpass([rnd.uniform(-1, 1) for _ in range(N)], 90)
ARP = [220, 261.6, 329.6, 440, 196, 246.9, 293.7, 392]
for i in range(N):
    t = i / SR
    d = (1 - ss(SSJ0, SSJ0 + 1, t)) + ss(BOOM + 2, BOOM + 4, t) * (1 - ss(DUR - 1.5, DUR, t))
    buf[i] += (math.sin(TAU * 41.2 * t) * 0.5 + noise[i] * 3) * 0.08 * d
    g = ss(SSJ1, SSJ1 + 0.5, t) * (1 - ss(BOOM, BOOM + 0.1, t)) * (0.5 if BEAM0 - 4 < t < BEAM1 else 1)
    if g > 0:
        n_ = int(t * 8); step = (t * 8) % 1
        f = ARP[n_ % 8] * (2 if (n_ // 16) % 2 else 1)
        v = (1 if (f * t) % 1 < 0.5 else -1) * 0.07 * math.exp(-step * 2.5)
        beat = (t * 2.7) % 1
        v += math.exp(-beat * 16) * math.sin(TAU * (50 + 100 * math.exp(-beat * 30)) * beat / 2.7) * 0.55
        v += (1 if (55 * [1, 1, 0.89, 1.19][int(t / 1.48) % 4] * t) % 1 < 0.5 else -1) * 0.08
        if int(t * 5.4) % 2 == 1: v += rnd.uniform(-1, 1) * 0.08 * math.exp(-((t * 5.4) % 1) * 12)
        buf[i] += v * g
    # Super Seek aura hum
    sj = ss(SSJ0, SSJ1, t) * (1 - ss(54, 57, t) * 0.6)
    if sj > 0:
        buf[i] += (math.sin(TAU * 110 * t + 3 * math.sin(TAU * 6 * t)) * 0.06 + rnd.uniform(-1, 1) * 0.02) * sj

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
    if kind == 'rise':
        n = int(1.2 * SR); sq = bandnoise(n, 100, 900); add(t, [sq[k] * 2 * math.sin(math.pi * k / n) for k in range(n)], 0.3)
    elif kind == 'ssj':
        n = int(3.2 * SR); sw = sweep(n, 60, 900, 1.4); e = env(n, 0.05, 2.0); sq = bandnoise(n, 100, 5000)
        add(t, [e[k] * (sw[k] * 0.5 + sq[k] * 2.5 * (k / n)) for k in range(n)], 0.7)
        n = int(2.0 * SR); e = env(n, 0.002, 0.6); sq = bandnoise(n, 40, 6000)
        add(t + 1.55, [e[k] * (sq[k] * 3 + math.sin(TAU * 45 * k / SR)) for k in range(n)], 0.9)
    elif kind == 'chime':
        for j, f in enumerate([1318.5, 1046.5]):
            n = int(1.4 * SR); e = env(n, 0.002, 0.4)
            add(t + j * 0.18, [e[k] * (math.sin(TAU * f * k / SR) + 0.4 * math.sin(TAU * f * 2.7 * k / SR)) for k in range(n)], 0.1)
    elif kind == 'dash':
        n = int(0.6 * SR); sq = bandnoise(n, 400, 5000); add(t, [sq[k] * 3 * (k / n) for k in range(n)], 0.5)
    elif kind == 'hit':
        n = int(1.0 * SR); e = env(n, 0.001, 0.15); sq = bandnoise(n, 60, 4000)
        add(t, [e[k] * (sq[k] * 3 + math.sin(TAU * (60 + 100 * math.exp(-k / SR * 20)) * k / SR) * 1.5) for k in range(n)], 0.9)
    elif kind == 'charge':
        n = int((BEAM0 - t) * SR); sw = sweep(n, 100, 1200, 1.5)
        add(t, [(sw[k] * 0.5 + rnd.uniform(-1, 1) * 0.3) * (k / n) for k in range(n)], 0.45)
    elif kind == 'beam':
        n = int((BEAM1 - t + 0.2) * SR); sq = bandnoise(n, 80, 6000)
        add(t, [(sq[k] * 3 + math.sin(TAU * 90 * k / SR + 4 * math.sin(TAU * 13 * k / SR)) * 0.8) * min(1, k / (0.05 * SR)) for k in range(n)], 0.75)
    elif kind == 'boom':
        n = int(4.0 * SR); e = env(n, 0.002, 1.0); sq = bandnoise(n, 30, 4000)
        add(t, [e[k] * (sq[k] * 3 + math.sin(TAU * (30 + 70 * math.exp(-k / SR * 3)) * k / SR) * 1.6) for k in range(n)], 1.0)

# bananas sizzling away in the aura
for b_ in TL['THROWS']:
    n = int(0.2 * SR); sq = bandnoise(n, 2000, 9000)
    add(b_['t'] + 0.36, [sq[k] * 3 * math.exp(-k / (0.05 * SR)) for k in range(n)], 0.15)

# voices: syllable blips per character (Senpai's wobble while crying)
BASE = {'N': 600, 'S': 290, 'G': 520, 'K': 700, 'F': 470, 'E': 90, 'P': 220}
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
with wave.open(os.path.join(HERE, 'seek-pov-part7-audio.wav'), 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v)) * 32767)) for v in out))
print('wrote seek-pov-part7-audio.wav', DUR, 's')
