"""Synthesizes the soundtrack for Seek POV Part 6 from timeline.json (written by render.cjs).

Pure standard library: python3 make_audio.py -> seek-pov-part6-audio.wav
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
POWER, BARRAGE0, BARRAGE1, HITMEGA, END = TL['POWER'], TL['BARRAGE0'], TL['BARRAGE1'], TL['HITMEGA'], TL['END']
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


# lounge tune until the bananas fly, then chiptune battle music
noise = lowpass([rnd.uniform(-1, 1) for _ in range(N)], 90)
CHORDS = [[220.0, 261.6, 329.6, 392.0], [174.6, 220.0, 261.6, 329.6], [196.0, 246.9, 293.7, 349.2], [164.8, 207.7, 246.9, 329.6]]
BASS = [110.0, 87.3, 98.0, 82.4]
ARP = [440, 523.3, 659.3, 880, 392, 493.9, 587.3, 784]
for i in range(N):
    t = i / SR
    m = 1 - ss(19.0, 20.0, t)
    if m > 0:
        bar_ = int(t / 2.4) % 4; ph = t % 2.4
        v = sum(math.sin(TAU * f * t) * (0.7 + 0.3 * math.sin(TAU * 4.5 * t)) for f in CHORDS[bar_]) * 0.12 * math.exp(-ph * 1.1)
        v += math.sin(TAU * BASS[bar_] * (1.0 if int(t / 0.6) % 2 == 0 else 1.5) * t) * 0.35 * math.exp(-((t / 0.6) % 1) * 3)
        buf[i] += v * m * 0.45
    g = ss(21.8, 22.4, t) * (1 - ss(HITMEGA, HITMEGA + 0.1, t)) * (0.6 if t < POWER else 1.0)
    if g > 0:
        step = (t * 8) % 1; n_ = int(t * 8)
        f = ARP[n_ % 8] * (1.5 if t > POWER + 3 and (n_ // 8) % 2 else 1)
        v = (1 if (f * t) % 1 < 0.25 else -1) * 0.08 * math.exp(-step * 3)
        beat = (t * 2.5) % 1
        v += math.exp(-beat * 16) * math.sin(TAU * (50 + 100 * math.exp(-beat * 30)) * beat / 2.5) * 0.5
        v += (1 if (55 * (1 if int(t * 2.5) % 4 < 2 else 1.33) * t) % 1 < 0.5 else -1) * 0.07
        buf[i] += v * g
    if t > HITMEGA + 0.5:
        buf[i] += (math.sin(TAU * 41.2 * t) * 0.5 + noise[i] * 3) * 0.05 * (1 - ss(DUR - 1.5, DUR, t))

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
    if kind == 'chime':
        for j, f in enumerate([1318.5, 1046.5]):
            n = int(1.4 * SR); e = env(n, 0.002, 0.4)
            add(t + j * 0.18, [e[k] * (math.sin(TAU * f * k / SR) + 0.4 * math.sin(TAU * f * 2.7 * k / SR)) for k in range(n)], 0.12)
        n = int(0.9 * SR); sq = bandnoise(n, 200, 1500); add(t, [sq[k] * 1.5 * math.sin(math.pi * k / n) for k in range(n)], 0.2)
    elif kind == 'shake':
        tt = t
        while tt < t + 6.4:
            n = int(0.07 * SR); sq = bandnoise(n, 2000, 8000)
            add(tt, [sq[k] * 3 * math.exp(-k / (0.02 * SR)) for k in range(n)], 0.18)
            tt += 0.14
    elif kind == 'pour':
        n = int(1.3 * SR); sq = bandnoise(n, 800, 3500)
        add(t, [sq[k] * 2 * math.sin(math.pi * k / n) for k in range(n)], 0.25)
    elif kind == 'tap':
        n = int(5.4 * SR); sq = bandnoise(n, 500, 4500)
        add(t, [sq[k] * 2 * min(1, k / (0.2 * SR)) * min(1, (n - k) / (0.2 * SR)) for k in range(n)], 0.25)
    elif kind == 'slide':
        n = int(2.2 * SR); sq = bandnoise(n, 150, 1200)
        add(t, [sq[k] * 2.5 * (1 - k / n) for k in range(n)], 0.3)
    elif kind == 'glug':
        tt = t
        while tt < DRINK1:
            n = int(0.22 * SR); e = env(n, 0.01, 0.06); sw = sweep(n, 160, 80)
            add(tt, [e[k] * sw[k] for k in range(n)], 0.4)
            tt += 0.36
    elif kind == 'clunk':
        n = int(0.3 * SR); e = env(n, 0.001, 0.05)
        add(t, [e[k] * (math.sin(TAU * 180 * k / SR) + rnd.uniform(-1, 1) * 0.4) for k in range(n)], 0.5)
    elif kind == 'power':
        n = int(3.0 * SR); sw = sweep(n, 120, 1600, 1.6); e = env(n, 0.01, 1.2)
        add(t, [e[k] * (sw[k] * 0.6 + rnd.uniform(-1, 1) * 0.2) for k in range(n)], 0.5)
        for j in range(12):
            m = int(0.3 * SR); f = 1200 + j * 180; add(t + 0.6 + j * 0.15, [math.sin(TAU * f * k / SR) * math.exp(-k / (0.08 * SR)) for k in range(m)], 0.08)
    elif kind == 'megawind':
        n = int(1.0 * SR); sw = sweep(n, 80, 400, 1.5); add(t, [sw[k] * (k / n) for k in range(n)], 0.4)
    elif kind == 'mega':
        n = int(2.5 * SR); e = env(n, 0.002, 0.5); sq = bandnoise(n, 50, 3000)
        add(t, [e[k] * (sq[k] * 3 + math.sin(TAU * (40 + 80 * math.exp(-k / SR * 5)) * k / SR) * 1.5) for k in range(n)], 0.95)
        n = int(1.0 * SR); sw = sweep(n, 600, 200); e = env(n, 0.01, 0.3)
        add(t + 1.1, [e[k] * sw[k] * (0.5 + 0.5 * math.sin(TAU * 12 * k / SR)) for k in range(n)], 0.25)   # boing
    elif kind == 'thud':
        n = int(0.4 * SR); en = env(n, 0.002, 0.08)
        add(t, [en[k] * math.sin(TAU * (50 + 60 * en[k]) * k / SR) for k in range(n)], 0.6)
    elif kind == 'burp':
        n = int(1.1 * SR); e = env(n, 0.03, 0.5); sq = bandnoise(n, 60, 700)
        add(t, [e[k] * ((((70 + 15 * math.sin(k / SR * 30)) * k / SR) % 1) * 2 - 1 + sq[k] * 2) for k in range(n)], 0.8)


# every banana: a whoosh, and a splat when it lands on Seek's eye
for b_ in TL['THROWS']:
    n = int(0.35 * SR); sq = bandnoise(n, 600, 4000)
    add(b_['t'], [sq[k] * 2 * math.sin(math.pi * k / n) for k in range(n)], 0.12)
    if b_['hit']:
        n = int(0.4 * SR); e = env(n, 0.002, 0.08); sq = bandnoise(n, 150, 2500)
        add(b_['t'] + 0.5, [e[k] * (sq[k] * 3 + math.sin(TAU * 120 * k / SR)) for k in range(n)], 0.45)

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
with wave.open(os.path.join(HERE, 'seek-pov-part6-audio.wav'), 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v)) * 32767)) for v in out))
print('wrote seek-pov-part6-audio.wav', DUR, 's')
