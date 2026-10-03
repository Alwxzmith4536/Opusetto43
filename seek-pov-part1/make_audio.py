"""Synthesizes the soundtrack for Seek POV Part 1 from timeline.json (written by render.cjs).

Pure standard library, so it runs anywhere: python3 make_audio.py -> seek-pov-part1-audio.wav
"""
import json, math, os, random, struct, wave

HERE = os.path.dirname(os.path.abspath(__file__))
TL = json.load(open(os.path.join(HERE, 'timeline.json')))
SR = 22050
DUR = TL['DUR']
N = int(DUR * SR)
buf = [0.0] * N
rnd = random.Random(47)
TAU = 2 * math.pi


def ss(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def add(start, samples, gain=1.0):
    i0 = int(start * SR)
    for k, v in enumerate(samples):
        i = i0 + k
        if 0 <= i < N:
            buf[i] += v * gain


def env_ad(n, a, d):
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


def light(t):
    for a, b in TL['FLICKER']:
        if a < t < b and (math.sin(t * 131.0) * 43758.5) % 1 < 0.45:
            return 0.0
    return 1.0


LUNGE, BLACK = TL['LUNGE'], TL['BLACK']

# --- Seek's presence: a low, breathing drone that thickens toward the end ---
noise = lowpass([rnd.uniform(-1, 1) for _ in range(N)], 90)
for i in range(N):
    t = i / SR
    if t > BLACK + 0.05 and t < 63:
        continue
    lvl = 0.10 + 0.08 * ss(3, 8, t) + 0.12 * ss(46, 49, t) + 0.25 * ss(55, LUNGE, t)
    if t > 63:
        lvl = 0.10 * ss(63, 64.5, t) * (1 - ss(70, 72, t))
    lfo = 0.75 + 0.25 * math.sin(TAU * 0.11 * t)
    v = (math.sin(TAU * 41.2 * t) + 0.7 * math.sin(TAU * 61.9 * t + 1.3) + 0.35 * math.sin(TAU * 82.6 * t)) * 0.5
    buf[i] += (v * lfo + noise[i] * 3.0) * lvl

# --- fluorescent hum (hallway louder), dies with the flicker ---
for i in range(0, N):
    t = i / SR
    if t >= LUNGE:
        break
    g = 0.025 if t < 18 else 0.012
    ph = (t * 120) % 1
    buf[i] += (ph * 2 - 1) * g * light(t) * ss(2, 4, t)

# --- cicadas through the classroom windows; they stop dead when the lights go ---
cic = bandnoise(int(30 * SR), 3500, 6500)
for k, v in enumerate(cic):
    t = 16.5 + k / SR
    am = 0.5 + 0.5 * math.sin(TAU * 38 * t) * (0.6 + 0.4 * math.sin(TAU * 0.4 * t))
    g = 0.09 * ss(16.5, 19.5, t) * (1 - ss(46.95, 47.05, t))
    buf[int(t * SR)] += v * am * g * 3

# --- Westminster school chime, distant ---
def bell(f, dur=2.2):
    n = int(dur * SR)
    e = env_ad(n, 0.005, 0.9)
    return [e[k] * (math.sin(TAU * f * k / SR) + 0.5 * math.sin(TAU * f * 2.76 * k / SR) + 0.25 * math.sin(TAU * f * 5.4 * k / SR)) for k in range(n)]
for j, f in enumerate([329.6, 261.6, 293.7, 196.0, 196.0, 293.7, 329.6, 261.6]):
    add(16.8 + j * 0.62 + (0.5 if j >= 4 else 0), bell(f), 0.055)

# --- Seek's footsteps: heavy, wet ---
for st in TL['STEPS']:
    n = int(0.28 * SR)
    e1, e2 = env_ad(n, 0.004, 0.07), env_ad(n, 0.002, 0.035)
    sq = bandnoise(n, 200, 1400)
    s = [e1[k] * math.sin(TAU * (55 + 40 * e1[k]) * k / SR) + e2[k] * sq[k] * 2.5 for k in range(n)]
    add(st, s, 0.32)

# --- eyes opening: a wet squelch with a falling pitch ---
for e in TL['EYES']:
    for when in [e['t']] + ([e['hide'][1]] if e['hide'] else []):
        n = int(0.5 * SR)
        en = env_ad(n, 0.02, 0.12)
        sq = bandnoise(n, 300, 2500)
        ph, s = 0.0, []
        for k in range(n):
            f = 420 * math.exp(-k / SR * 6) + 70
            ph += TAU * f / SR
            s.append(en[k] * (sq[k] * 2 * (0.5 + 0.5 * math.sin(ph)) + 0.3 * math.sin(ph)))
        add(when - 0.1, s, 0.22 if when < 40 else 0.3)
# all the classroom eyes snapping shut at once, the moment she looks
add(min(e['hide'][0] for e in TL['EYES'] if e['hide']), [v * e for v, e in zip(bandnoise(int(0.25 * SR), 150, 900), env_ad(int(0.25 * SR), 0.003, 0.05))], 0.6)

# --- flicker buzz ---
for a, b in TL['FLICKER']:
    t = a
    while t < b:
        on = (math.sin(t * 131.0) * 43758.5) % 1 < 0.45
        if on:
            n = int(0.05 * SR)
            s = [(1 if (k * 120 / SR) % 1 < 0.5 else -1) * 0.5 + rnd.uniform(-1, 1) * 0.5 for k in range(n)]
            add(t, s, 0.07)
        t += 0.05

# --- voices: little syllable blips, game-dialogue style ---
for ln in TL['LINES']:
    base = 600 if ln['who'] == 'N' else 290
    cps = TL['CPS']
    for ci, ch in enumerate(ln['text']):
        if ch in ' .,!?~—-' or ci % 2:
            continue
        t = ln['s'] + ci / cps
        if t > ln['e'] - 0.15:
            break
        f = base * (1 + rnd.uniform(-0.12, 0.14)) * (0.9 if ln['s'] > 47 else 1)
        n = int(0.065 * SR)
        e = env_ad(n, 0.004, 0.025)
        s = [e[k] * (0.6 * math.sin(TAU * f * k / SR) + 0.4 * (1 if (f * k / SR) % 1 < 0.35 else -1)) for k in range(n)]
        add(t, s, 0.075)

# --- heartbeat (Seek's? hers?) speeding up ---
t = 54.5
while t < BLACK:
    bpm = 70 + 90 * ss(54.5, BLACK, t)
    for off, g in ((0, 1.0), (0.16, 0.7)):
        n = int(0.22 * SR)
        e = env_ad(n, 0.003, 0.06)
        add(t + off, [e[k] * math.sin(TAU * (48 + 30 * e[k]) * k / SR) for k in range(n)], 0.45 * g * ss(54.5, 56, t))
    t += 60 / bpm

# --- the lunge: rising screech, then the sting ---
n = int((BLACK - LUNGE) * SR)
ph, s = 0.0, []
for k in range(n):
    u = k / n
    f = 300 + 1500 * u * u
    ph += TAU * f / SR
    s.append((math.sin(ph) + 0.6 * math.sin(ph * 1.51) + rnd.uniform(-1, 1) * 0.6) * u)
add(LUNGE, s, 0.25)
n = int(3.2 * SR)
e = env_ad(n, 0.003, 0.9)
cl = [55.0, 58.3, 82.4, 116.5, 164.8]
s = []
for k in range(n):
    tt = k / SR
    v = sum(((f * tt) % 1) * 2 - 1 for f in cl) / len(cl)
    s.append(e[k] * (v + rnd.uniform(-1, 1) * 0.5 * math.exp(-tt * 4)))
add(BLACK - 0.02, s, 0.9)

# --- master: soft clip, normalize, fade, write ---
peak = max(abs(v) for v in buf) or 1
out = [math.tanh(v / peak * 1.6) * 0.89 for v in buf]
fade = int(1.0 * SR)
for k in range(fade):
    out[-1 - k] *= k / fade
with wave.open(os.path.join(HERE, 'seek-pov-part1-audio.wav'), 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v)) * 32767)) for v in out))
print('wrote seek-pov-part1-audio.wav', DUR, 's')
