"""Synthesizes the soundtrack for Seek POV Final from timeline.json (written by render.cjs).

Pure standard library: python3 make_audio.py -> seek-pov-final-audio.wav
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
TURN, WAVE, DARK, LIFT, SPACE, WARP0, WARP1, BLAST, END = (TL[k] for k in ['TURN', 'WAVE', 'DARK', 'LIFT', 'SPACE', 'WARP0', 'WARP1', 'BLAST', 'END'])
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


# street drone -> silence -> a slow, lonely space pad -> silence after the blast -> a music-box goodbye
noise = lowpass([rnd.uniform(-1, 1) for _ in range(N)], 90)
PAD = [[110, 164.8, 220, 261.6], [98, 146.8, 196, 246.9], [87.3, 130.8, 174.6, 220], [98, 146.8, 196, 233.1]]
for i in range(N):
    t = i / SR
    if t < DARK:
        lvl = 0.1 + 0.25 * ss(TURN - 0.5, WAVE, t)
        buf[i] += (math.sin(TAU * 41.2 * t) * 0.5 + 0.6 * math.sin(TAU * 43.6 * t) + noise[i] * 3) * lvl
    if LIFT < t < BLAST + 0.1:
        g = ss(LIFT, SPACE + 2, t) * (1 - ss(BLAST - 0.2, BLAST, t))
        ch = PAD[int((t - LIFT) / 4.0) % 4]
        v = sum(math.sin(TAU * f * t + 0.6 * math.sin(TAU * 0.3 * t + j)) for j, f in enumerate(ch)) * 0.05
        v += math.sin(TAU * 55 * t) * 0.06
        if WARP0 < t < WARP1:
            v += noise[i] * 4 * math.sin(math.pi * (t - WARP0) / (WARP1 - WARP0)) * 0.08
        buf[i] += v * g

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
    if kind == 'sting':
        n = int(2.5 * SR); e = env(n, 0.003, 0.9); cl = [55.0, 58.3, 82.4, 116.5, 164.8]
        add(t, [e[k] * sum(((f * k / SR) % 1) * 2 - 1 for f in cl) / 5 for k in range(n)], 0.6)
    elif kind == 'wave':
        n = int((DARK - t + 0.3) * SR); sq = bandnoise(n, 40, 1500); sw = sweep(n, 200, 30, 0.6)
        add(t, [(sq[k] * 3 + sw[k] * 0.6) * (k / n) ** 0.5 for k in range(n)], 0.75)
    elif kind == 'lift':
        n = int(3.6 * SR); sq = bandnoise(n, 200, 4000); sw = sweep(n, 80, 600, 1.2)
        add(t, [(sq[k] * 2 + sw[k] * 0.4) * math.sin(math.pi * k / n) for k in range(n)], 0.5)
    elif kind == 'warp':
        n = int((WARP1 - t) * SR); sw = sweep(n, 120, 900, 0.7)
        add(t, [sw[k] * 0.3 * math.sin(math.pi * k / n) for k in range(n)], 0.4)
    elif kind == 'blast':
        n = int(3.0 * SR); sw = sweep(n, 200, 2400, 2.0)
        add(t - 3.0, [sw[k] * (k / n) ** 2 for k in range(n)], 0.35)
        n = int(5.0 * SR); e = env(n, 0.002, 1.4); sq = bandnoise(n, 25, 6000)
        add(t, [e[k] * (sq[k] * 3 + math.sin(TAU * (28 + 60 * math.exp(-k / SR * 2)) * k / SR) * 1.6) for k in range(n)], 1.0)

# music box over THE END
for j, f in enumerate([659.3, 587.3, 523.3, 493.9, 523.3, 587.3, 659.3, 784.0, 659.3]):
    n = int(1.8 * SR); e = env(n, 0.003, 0.6)
    add(END + 0.6 + j * 0.62, [e[k] * (math.sin(TAU * f * k / SR) + 0.3 * math.sin(TAU * f * 3 * k / SR)) for k in range(n)], 0.1)

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
with wave.open(os.path.join(HERE, 'seek-pov-final-audio.wav'), 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v)) * 32767)) for v in out))
print('wrote seek-pov-final-audio.wav', DUR, 's')
