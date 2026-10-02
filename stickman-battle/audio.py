"""Procedural soundtrack: score + saber hums + effects synced to the picture."""
import math
import random
import wave
import numpy as np

SR = 44100


# ------------------------------------------------------------------ helpers
def env_ad(n, a, d, power=2.0):
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(a, 1e-4)) * np.exp(-t / max(d, 1e-4)) ** 1.0
    return e.astype(np.float32)


def noise(n, rng):
    return rng.standard_normal(n).astype(np.float32)


def fft_filter(x, lo=None, hi=None, order=2):
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    g = np.ones_like(f)
    if lo is not None:
        g *= 1.0 / (1.0 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    if hi is not None:
        g *= 1.0 / (1.0 + (f / hi) ** (2 * order))
    return np.fft.irfft(X * g, n).astype(np.float32)


def sweep_noise(n, fa, fb, rng, q=1.2, bands=14):
    """noise whose spectral centre glides fa -> fb across n samples"""
    out = np.zeros(n, np.float32)
    t = np.linspace(0, 1, n, dtype=np.float32)
    base = noise(n, rng)
    for i in range(bands):
        u = i / (bands - 1)
        fc = fa * (fb / fa) ** u
        band = fft_filter(base, lo=fc / (1 + 0.6 / q), hi=fc * (1 + 0.6 / q), order=2)
        w = np.exp(-((t - u) ** 2) / (2 * (0.55 / bands * 1.6) ** 2))
        out += band * w
    return out


def add(buf_l, buf_r, sig, t0, pan=0.0, gain=1.0):
    i0 = int(t0 * SR)
    if i0 >= len(buf_l) or i0 + len(sig) <= 0:
        return
    s0 = max(0, -i0)
    i0 = max(0, i0)
    seg = sig[s0:]
    n = min(len(seg), len(buf_l) - i0)
    gl = gain * math.cos((pan + 1) * math.pi / 4)
    gr = gain * math.sin((pan + 1) * math.pi / 4)
    buf_l[i0:i0 + n] += seg[:n] * gl
    buf_r[i0:i0 + n] += seg[:n] * gr


# ------------------------------------------------------------------ instruments
def taiko(amp=1.0, f0=110.0, rng=None):
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    f = 46.0 + (f0 - 46.0) * np.exp(-t / 0.06)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t / 0.22)
    body += 0.35 * np.sin(2 * ph) * np.exp(-t / 0.1)
    r = rng or np.random.default_rng(1)
    skin = fft_filter(noise(n, r), lo=120, hi=900) * np.exp(-t / 0.035) * 0.8
    return ((body + skin) * amp).astype(np.float32)


def saw_add(f, n, nh=14, bright=2200.0, detune=0.0, vib=0.0, phase0=0.0):
    t = np.arange(n) / SR
    out = np.zeros(n, np.float32)
    ff = f * (1 + detune)
    vibr = 1 + vib * np.sin(2 * np.pi * 5.2 * t)
    ph0 = 2 * np.pi * np.cumsum(ff * vibr) / SR + phase0
    for h in range(1, nh + 1):
        fh = ff * h
        if fh > 9000:
            break
        g = (1.0 / h) / (1.0 + (fh / bright) ** 2)
        out += (g * np.sin(h * ph0)).astype(np.float32)
    return out


def pad(freqs, dur, amp=0.2, bright=1500.0, attack=0.6, release=0.8, vib=0.002):
    n = int((dur + release) * SR)
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / attack) * np.minimum(1.0, np.maximum(0.0, (dur + release - t) / release))
    sig = np.zeros(n, np.float32)
    for f in freqs:
        for d, ph in ((-0.0035, 0.0), (0.0, 1.3), (0.004, 2.1)):
            sig += saw_add(f, n, nh=10, bright=bright, detune=d, vib=vib, phase0=ph)
    return (sig * e * amp / max(1, len(freqs)) / 2.2).astype(np.float32)


def brass(f, dur, amp=0.25, bright=1800.0):
    n = int((dur + 0.3) * SR)
    t = np.arange(n) / SR
    a = np.minimum(1.0, t / 0.04)
    d = np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.08))
    sw = 1 + 0.6 * np.exp(-t / 0.2)
    sig = (saw_add(f, n, nh=16, bright=bright) + 0.7 * saw_add(f * 1.004, n, nh=16, bright=bright))
    return (sig * a * d * sw * amp * 0.5).astype(np.float32)


def bass(f, dur, amp=0.4):
    n = int((dur + 0.15) * SR)
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / 0.01) * np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.06)) * (0.55 + 0.45 * np.exp(-t / 0.25))
    sig = saw_add(f, n, nh=10, bright=500.0) + 0.6 * np.sin(2 * np.pi * f * t)
    return (sig * e * amp * 0.6).astype(np.float32)


def pluck(f, dur=0.25, amp=0.15):
    n = int(dur * SR)
    t = np.arange(n) / SR
    e = np.exp(-t / 0.09)
    sig = np.sin(2 * np.pi * f * t) + 0.5 * np.sin(4 * np.pi * f * t) * np.exp(-t / 0.05) + 0.25 * np.sin(6 * np.pi * f * t)
    return (sig * e * amp).astype(np.float32)


def choir(freqs, dur, amp=0.2):
    """vowel-ish pad: harmonic stack shaped by 'ah' formants"""
    n = int((dur + 1.2) * SR)
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / 0.9) * np.minimum(1.0, np.maximum(0.0, (dur + 1.2 - t) / 1.2))
    sig = np.zeros(n, np.float32)
    for f in freqs:
        for d in (-0.004, 0.0, 0.005):
            ff = f * (1 + d)
            vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t + d * 900)
            ph = 2 * np.pi * np.cumsum(ff * vib) / SR
            for h in range(1, 22):
                fh = ff * h
                if fh > 4000:
                    break
                g = (np.exp(-((fh - 780) / 260) ** 2) + 0.6 * np.exp(-((fh - 1220) / 300) ** 2)
                     + 0.25 * np.exp(-((fh - 2600) / 500) ** 2) + 0.25 / h)
                sig += (g / h ** 0.35 * np.sin(h * ph)).astype(np.float32)
    return (sig * e * amp / max(1, len(freqs)) / 3.0).astype(np.float32)


# ------------------------------------------------------------------ effects
def fx_clash(p, rng):
    n = int((0.35 + 0.35 * min(p, 2.0)) * SR)
    t = np.arange(n) / SR
    base = rng.uniform(0.85, 1.25)
    sig = np.zeros(n, np.float32)
    for k, (r, d) in enumerate(((1.0, 0.28), (1.51, 0.2), (2.76, 0.16), (4.07, 0.1), (5.4, 0.07))):
        f = 640.0 * base * r
        sig += (np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * np.exp(-t / (d * (0.7 + 0.5 * p)))
                / (1 + 0.5 * k)).astype(np.float32)
    zap = fft_filter(noise(n, rng), lo=1500, hi=9000) * np.exp(-t / 0.05)
    thump = np.sin(2 * np.pi * (140 - 70 * np.minimum(1, t / 0.15)) * t) * np.exp(-t / 0.08)
    crackle = fft_filter(noise(n, rng), lo=3000, hi=12000) * np.exp(-t / 0.14) * (rng.random(n) > 0.82)
    out = 0.5 * sig + 0.7 * zap + 0.6 * thump * min(1.5, p) + 0.5 * crackle
    return (out * min(1.4, 0.5 + 0.45 * p)).astype(np.float32)


def fx_hit(p, rng):
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    f = 55 + 120 * np.exp(-t / 0.05)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t / 0.25)
    sn = fft_filter(noise(n, rng), lo=200, hi=3500) * np.exp(-t / 0.09)
    return ((0.9 * body + 0.7 * sn) * min(1.5, 0.6 + 0.5 * p)).astype(np.float32)


def fx_push(rng):
    n = int(1.0 * SR)
    t = np.arange(n) / SR
    sw = sweep_noise(n, 180, 3200, rng) * np.minimum(1, t / 0.12) * np.exp(-t / 0.4)
    f = 70 - 38 * np.minimum(1, t / 0.7)
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.45)
    return (sw * 1.3 + boom * 0.9).astype(np.float32)


def fx_thud(p, rng):
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    s = fft_filter(noise(n, rng), hi=500) * np.exp(-t / 0.09)
    b = np.sin(2 * np.pi * 62 * t) * np.exp(-t / 0.12)
    return ((s * 1.2 + b) * min(1.3, 0.4 + 0.5 * p)).astype(np.float32)


def fx_ignite(rng):
    n = int(0.55 * SR)
    t = np.arange(n) / SR
    f = 120 + 900 * np.minimum(1, t / 0.28) ** 2
    sw = saw_add(110.0, n, nh=6) * 0.0
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = (np.sin(ph) + 0.4 * np.sin(2 * ph)) * np.minimum(1, t / 0.05) * np.exp(-np.maximum(0, t - 0.25) / 0.12)
    snap = fft_filter(noise(n, rng), lo=1200, hi=8000) * np.exp(-t / 0.05)
    air = sweep_noise(n, 300, 5000, rng) * np.exp(-t / 0.3)
    return (0.5 * tone + 0.8 * snap + 0.5 * air).astype(np.float32)


def fx_riser(dur, rng):
    n = int(dur * SR)
    t = np.arange(n) / SR
    u = t / dur
    sw = sweep_noise(n, 200, 7000, rng) * (u ** 1.6)
    f = 90 * (2 ** (3 * u))
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * u ** 1.5 * 0.4
    return (sw * 1.0 + tone).astype(np.float32)


def fx_burst(rng):
    n = int(3.2 * SR)
    t = np.arange(n) / SR
    f = 38 + 60 * np.exp(-t / 0.15)
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 1.1)
    crash = fft_filter(noise(n, rng), lo=250, hi=9000) * np.exp(-t / 0.6)
    shim = np.zeros(n, np.float32)
    for r in (1.0, 1.48, 2.0, 2.99, 4.1):
        shim += np.sin(2 * np.pi * 520 * r * t) * np.exp(-t / 1.0) * 0.12
    return (1.6 * sub + 0.9 * crash + shim).astype(np.float32)


def fx_dissolve(rng):
    n = int(2.2 * SR)
    t = np.arange(n) / SR
    air = fft_filter(noise(n, rng), lo=2500, hi=11000) * np.exp(-t / 0.8) * 0.5
    sig = air
    for i in range(34):
        t0 = rng.uniform(0, 1.5)
        f = rng.uniform(1800, 6500)
        k = int(0.18 * SR)
        i0 = int(t0 * SR)
        tt = np.arange(k) / SR
        blip = np.sin(2 * np.pi * f * tt) * np.exp(-tt / 0.04) * 0.25 * (1 - t0 / 1.8)
        sig[i0:i0 + k] += blip[:n - i0]
    low = np.sin(2 * np.pi * 70 * t) * np.exp(-t / 0.5) * 0.4
    return (sig + low).astype(np.float32)


def fx_throw(rng):
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    b = fft_filter(noise(n, rng), lo=400, hi=1800) * (0.5 + 0.5 * np.sin(2 * np.pi * 26 * t))
    return (b * np.sin(np.pi * np.minimum(1, t / 0.9)) * 1.2).astype(np.float32)


def fx_whoosh(strength, rng, dur=0.4):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = sweep_noise(n, 500, 3500, rng) * np.sin(np.pi * np.minimum(1, t / dur)) ** 1.5
    return (s * strength).astype(np.float32)


def fx_final(rng):
    n = int(2.5 * SR)
    t = np.arange(n) / SR
    shing = sweep_noise(int(0.5 * SR), 9000, 2500, rng) * 1.2
    sig = np.zeros(n, np.float32)
    sig[:len(shing)] += shing * np.exp(-np.arange(len(shing)) / SR / 0.2)
    f = 42 + 80 * np.exp(-t / 0.1)
    sig += 1.6 * np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.9)
    for r in (1.0, 1.5, 2.0, 3.0):
        sig += 0.15 * np.sin(2 * np.pi * 440 * r * t) * np.exp(-t / 1.4)
    return sig.astype(np.float32)


# ------------------------------------------------------------------ main synth
def synth(S, out_path):
    from story import wind  # noqa
    D = S.warp.duration + 2.5
    N = int(D * SR)
    L = np.zeros(N, np.float32)
    R = np.zeros(N, np.float32)
    mL = np.zeros(N, np.float32)
    mR = np.zeros(N, np.float32)
    rng = np.random.default_rng(42)
    T = S.warp.to_out
    cam = S.cam

    def pan_of(x, t):
        c = cam.at(t)
        return max(-0.8, min(0.8, (x - c['cx']) * c['zoom'] / 960.0))

    # ---------- wind bed
    wl = fft_filter(noise(N, rng), lo=150, hi=1400)
    tt = np.arange(N) / SR
    gust = 0.55 + 0.45 * np.sin(2 * np.pi * tt / 9.0 + 1.0) ** 2
    gust2 = 0.6 + 0.4 * np.sin(2 * np.pi * tt / 3.7)
    wl = wl * gust * gust2 * 0.10
    wr = np.roll(wl, 2200)
    L += wl
    R += wr

    # ---------- sfx from the script
    for (ts, kind, kw) in S.sfx_list:
        to = T(ts)
        x = kw.get('x')
        p = kw.get('power', 1.0)
        if kind == 'clash':
            a = kw.get('at')
            pan = 0.0
            sig = fx_clash(p, rng)
            add(L, R, sig, to, pan, 0.9)
        elif kind == 'hit':
            add(L, R, fx_hit(p, rng), to, pan_of(x, ts) if x is not None else 0.0, 1.0)
        elif kind == 'push':
            add(L, R, fx_push(rng), to - 0.05, pan_of(x, ts) if x is not None else 0.0, 1.0)
        elif kind == 'thud':
            add(L, R, fx_thud(p, rng), to, pan_of(x, ts) if x is not None else 0.0, 0.8)
        elif kind == 'ignite':
            add(L, R, fx_ignite(rng), to, 0.0, 0.9)
        elif kind == 'riser':
            add(L, R, fx_riser(kw['dur'], rng), to, 0.0, 0.8)
        elif kind == 'burst':
            add(L, R, fx_burst(rng), to, 0.0, 1.2)
        elif kind == 'dissolve':
            add(L, R, fx_dissolve(rng), to, 0.0, 0.9)
        elif kind == 'throw' or kind == 'pull':
            sig = fx_throw(rng)
            if kind == 'pull':
                sig = sig[::-1].copy()
            add(L, R, sig, to, 0.0, 0.8)
        elif kind == 'whoosh2':
            add(L, R, fx_whoosh(1.1, rng, 0.7), to, 0.0, 0.9)
        elif kind == 'final':
            add(L, R, fx_final(rng), to, 0.0, 1.3)
        elif kind == 'tick':
            n = int(0.1 * SR)
            tq = np.arange(n) / SR
            add(L, R, (np.sin(2 * np.pi * 2300 * tq) * np.exp(-tq / 0.012) * 0.6).astype(np.float32), to, -0.1, 0.8)
        elif kind == 'victory':
            add(L, R, fx_burst(rng) * 0.6, to, 0.0, 0.9)

    # ---------- saber hums & swooshes from motion
    names = list(S.fighters.keys())
    step = 0.01
    nctl = int(D / step)
    base = {'blue': 118.0, 'green': 103.0, 'yellow': 131.0}
    for name in names:
        f = S.fighters[name]
        amp_c = np.zeros(nctl, np.float32)
        spd_c = np.zeros(nctl, np.float32)
        prev = None
        peaks = []
        from draw import saber_geom
        for i in range(nctl):
            o = i * step
            s = S.warp.to_script(o)
            if s > S.warp.arr[1][-1]:
                break
            dead = f.dead_t is not None and s >= f.dead_t
            hb, ht, tip, lit, st = saber_geom(f, s)
            on = (lit > 0.5) and not dead
            amp_c[i] = 1.0 if on else 0.0
            if prev is not None:
                dx = math.hypot(tip[0] - prev[0], tip[1] - prev[1])
                spd_c[i] = dx / step
            prev = tip
        spd_c = np.clip(spd_c, 0, 6000)
        # smooth
        k = np.ones(5) / 5
        spd_s = np.convolve(spd_c, k, mode='same')
        amp_s = np.convolve(amp_c, np.ones(9) / 9, mode='same')
        tgrid = np.arange(nctl) * step
        # control curves at audio rate
        ta = np.arange(N) / SR
        spd_a = np.interp(ta, tgrid, spd_s / 3500.0).astype(np.float32)
        amp_a = np.interp(ta, tgrid, amp_s).astype(np.float32)
        fq = base[name] * (1 + 0.45 * np.clip(spd_a, 0, 1.5))
        ph = 2 * np.pi * np.cumsum(fq) / SR
        hum = (np.sin(ph) + 0.55 * np.sin(2 * ph + 0.4) + 0.3 * np.sin(3 * ph + 1.1)
               + 0.18 * np.sin(5.02 * ph)).astype(np.float32)
        hum *= (0.045 + 0.10 * np.clip(spd_a, 0, 1.6)) * amp_a
        pn = {'blue': -0.25, 'green': 0.25, 'yellow': 0.0}[name]
        gl = math.cos((pn + 1) * math.pi / 4)
        gr = math.sin((pn + 1) * math.pi / 4)
        L += hum * gl
        R += hum * gr
        # swooshes at speed peaks
        last = -1.0
        for i in range(2, nctl - 2):
            v = spd_s[i]
            if v > 2300 and v >= spd_s[i - 1] and v > spd_s[i + 1] and amp_c[i] > 0.5:
                to = i * step
                if to - last > 0.11:
                    st_ = min(1.4, v / 3500.0)
                    add(L, R, fx_whoosh(0.5 * st_, rng, 0.28 + 0.1 * st_), to - 0.12, pn, 0.9)
                    last = to

    # ---------- the score
    def tm(ts):
        return T(ts)

    def hit(buf_l, buf_r, t, amp=1.0, f0=110.0):
        add(buf_l, buf_r, taiko(amp, f0, rng), t, 0.0, 1.0)

    D_ = {'D1': 36.71, 'D2': 73.42, 'A2': 110.0, 'D3': 146.83, 'F2': 87.31, 'Bb1': 58.27, 'C2': 65.41,
          'G1': 49.0, 'A1': 55.0, 'F3': 174.61, 'A3': 220.0, 'D4': 293.66, 'F4': 349.23, 'A4': 440.0,
          'E3': 164.81, 'G3': 196.0, 'Bb3': 233.08, 'C4': 261.63, 'C3': 130.81, 'E4': 329.63,
          'Fs3': 185.0, 'Fs4': 369.99, 'D5': 587.33, 'Fs2': 92.5, 'B3': 246.94, 'G2': 98.0}

    # act 0: atmosphere and ignitions
    t_go = tm(7.8)
    mus_l, mus_r = mL, mR
    add(mus_l, mus_r, pad([D_['D2'], D_['A2'], D_['D3']], tm(7.7) - 0.3, 0.16, bright=700, attack=2.5, release=1.0), 0.2, 0.0, 1.0)
    for ts, ch in ((3.0, [D_['D3'], D_['A3'], D_['D4']]), (4.35, [D_['D3'], D_['F3'], D_['A3']]),
                   (5.6, [D_['D3'], D_['A3'], D_['F4']])):
        add(mus_l, mus_r, pad(ch, 1.4, 0.12, bright=1100, attack=0.5, release=1.0), tm(ts), 0.0, 1.0)
        hit(mus_l, mus_r, tm(ts + 0.2), 0.45, 80.0)
    # heartbeat build to the pebble
    t = tm(6.4)
    k = 0
    while t < tm(7.75):
        hit(mus_l, mus_r, t, 0.3 + 0.35 * (t - tm(6.4)) / (tm(7.75) - tm(6.4)), 70.0)
        t += 0.62 - 0.12 * (t - tm(6.4)) / (tm(7.75) - tm(6.4))
    add(mus_l, mus_r, fx_riser(max(0.5, tm(7.78) - tm(6.8)), rng) * 0.5, tm(6.8), 0.0, 0.7)

    # fight A  8 -> 24  (D minor, 126 bpm)
    prog = [[D_['D3'], D_['F3'], D_['A3']], [D_['Bb3'] / 2, D_['D3'], D_['F3']],
            [D_['F3'], D_['A3'], D_['C4']], [D_['C3'], D_['E3'], D_['G3']]]
    roots = [D_['D2'], D_['Bb1'] * 1.0, D_['F2'], D_['C2']]
    beat = 60.0 / 126.0
    t0 = tm(7.85)
    t1 = tm(23.85)
    nb = int((t1 - t0) / beat)
    for b in range(nb):
        t = t0 + b * beat
        bar = b // 4
        ch = prog[bar % 4]
        rt = roots[bar % 4]
        # taiko pattern
        pat = [1.0, 0.0, 0.55, 0.0, 0.8, 0.0, 0.5, 0.5]
        for e in range(2):
            pv = pat[(b % 4) * 2 + e]
            if pv > 0:
                hit(mus_l, mus_r, t + e * beat / 2, 0.55 * pv, 100.0)
        if b % 4 == 0:
            add(mus_l, mus_r, pad(ch + [ch[0] * 2], beat * 4, 0.20, bright=1500, attack=0.35, release=0.4), t, 0.0, 1.0)
        # bass eighths
        for e in range(2):
            add(mus_l, mus_r, bass(rt * (1.0 if (b + e) % 4 else 2.0), beat * 0.45, 0.42), t + e * beat / 2, 0.0, 1.0)
        # stabs on bar starts every second bar
        if b % 8 == 0:
            for fq in (ch[0] * 2, ch[1] * 2, ch[2] * 2):
                add(mus_l, mus_r, brass(fq, 0.5, 0.22), t, -0.1, 1.0)
    # build 22.2 -> 23.9
    tb0 = tm(22.4)
    tb1 = tm(23.9)
    t = tb0
    gap = 0.42
    while t < tb1 - 0.05:
        hit(mus_l, mus_r, t, 0.55 + 0.6 * (t - tb0) / (tb1 - tb0), 100.0)
        gap = max(0.07, gap * 0.9)
        t += gap
    add(mus_l, mus_r, pad([D_['D3'], D_['A3'], D_['D4'], D_['F4']], tb1 - tb0, 0.3, bright=2500, attack=1.2, release=0.3), tb0, 0.0, 1.0)

    # burst + hero shot choir 24 -> 26.6
    tB = tm(23.92)
    hit(mus_l, mus_r, tB, 2.2, 90.0)
    add(mus_l, mus_r, choir([D_['D3'], D_['A3'], D_['D4'], D_['F4'], D_['A4']], 3.2, 0.5), tB + 0.05, 0.0, 1.0)
    add(mus_l, mus_r, pad([D_['D2'], D_['A2']], 3.0, 0.3, bright=500, attack=0.1, release=1.0), tB, 0.0, 1.0)

    # fight B  26.6 -> 34.3 (faster, 140 bpm)
    prog2 = [[D_['D3'], D_['F3'], D_['A3']], [D_['D3'], D_['F3'], D_['Bb3']],
             [D_['E3'], D_['G3'], D_['Bb3']], [D_['D3'], D_['A3'], D_['C4']]]
    roots2 = [D_['D2'], D_['D2'], D_['E3'] / 2, D_['A1']]
    beat = 60.0 / 140.0
    t0 = tm(26.7)
    t1 = tm(31.45)
    nb = int((t1 - t0) / beat)
    for b in range(nb):
        t = t0 + b * beat
        bar = b // 4
        ch = prog2[bar % 4]
        rt = roots2[bar % 4]
        hit(mus_l, mus_r, t, 0.7, 105.0)
        hit(mus_l, mus_r, t + beat * 0.5, 0.45, 100.0)
        if b % 2 == 1:
            hit(mus_l, mus_r, t + beat * 0.75, 0.5, 130.0)
        for e in range(2):
            add(mus_l, mus_r, bass(rt, beat * 0.4, 0.45), t + e * beat / 2, 0.0, 1.0)
        if b % 4 == 0:
            add(mus_l, mus_r, pad(ch + [ch[0] * 2], beat * 4, 0.22, bright=1800, attack=0.2, release=0.3), t, 0.0, 1.0)
            for fq in ch:
                add(mus_l, mus_r, brass(fq * 2, 0.45, 0.2), t, 0.1, 1.0)
        # 16th arpeggio in the upper register
        arp = [D_['D4'], D_['F4'], D_['A4'], D_['F4']]
        for s16 in range(4):
            add(mus_l, mus_r, pluck(arp[s16] * (1.0 if bar % 2 == 0 else 0.89), 0.2, 0.09), t + s16 * beat / 4, 0.3 * (1 if s16 % 2 else -1), 1.0)
    # suspense drop for the saber trick 31.5 -> 33.6
    ts_ = tm(31.5)
    add(mus_l, mus_r, pad([D_['D2'], D_['A2'], D_['F3']], tm(33.6) - ts_, 0.22, bright=700, attack=0.3, release=0.8), ts_, 0.0, 1.0)
    t = ts_
    while t < tm(33.6):
        hit(mus_l, mus_r, t, 0.5, 70.0)
        t += 0.75
    add(mus_l, mus_r, fx_riser(tm(34.5) - tm(33.0), rng) * 0.4, tm(33.0), 0.0, 0.7)

    # duel 34.6 -> 49.2  (150 bpm)
    prog3 = [[D_['D3'], D_['F3'], D_['A3']], [D_['Bb3'] / 2, D_['D3'], D_['F3']],
             [D_['G3'], D_['Bb3'], D_['D4']], [D_['A3'], D_['C4'] * 1.0, D_['E4']]]
    roots3 = [D_['D2'], D_['Bb1'], D_['G1'], D_['A1']]
    beat = 60.0 / 150.0
    t0 = tm(35.68)
    t1 = tm(49.15)
    nb = int((t1 - t0) / beat)
    add(mus_l, mus_r, pad([D_['D2'], D_['A2'], D_['D3']], t0 - tm(34.6), 0.2, bright=800, attack=1.2, release=0.3), tm(34.6), 0.0, 1.0)
    for b in range(nb):
        t = t0 + b * beat
        bar = b // 4
        ch = prog3[bar % 4]
        rt = roots3[bar % 4]
        hit(mus_l, mus_r, t, 0.85, 105.0)
        hit(mus_l, mus_r, t + beat * 0.5, 0.5, 100.0)
        if b % 4 in (1, 3):
            hit(mus_l, mus_r, t + beat * 0.25, 0.35, 140.0)
            hit(mus_l, mus_r, t + beat * 0.75, 0.5, 130.0)
        for e in range(2):
            add(mus_l, mus_r, bass(rt, beat * 0.4, 0.5), t + e * beat / 2, 0.0, 1.0)
        if b % 4 == 0:
            add(mus_l, mus_r, pad(ch + [ch[0] * 2, ch[1] * 2], beat * 4, 0.27, bright=2200, attack=0.15, release=0.3), t, 0.0, 1.0)
            for fq in ch:
                add(mus_l, mus_r, brass(fq * 2, 0.55, 0.26), t, 0.0, 1.0)
        arp = [ch[0] * 2, ch[1] * 2, ch[2] * 2, ch[1] * 2]
        for s16 in range(4):
            add(mus_l, mus_r, pluck(arp[s16], 0.18, 0.1), t + s16 * beat / 4, 0.35 * (1 if s16 % 2 else -1), 1.0)
    # the final-cut hush: cut at 49.3 and let the hit ring
    # resolution
    tF = tm(49.5)
    add(mus_l, mus_r, pad([D_['D2'], D_['A2']], tm(55.5) - tF, 0.2, bright=500, attack=2.0, release=1.0), tF, 0.0, 1.0)
    add(mus_l, mus_r, choir([D_['D3'], D_['A3'], D_['Fs3']], tm(55.5) - tm(52.0), 0.28), tm(52.0), 0.0, 1.0)
    # victory chord (D major)
    tV = tm(55.6)
    hit(mus_l, mus_r, tV, 1.8, 90.0)
    add(mus_l, mus_r, choir([D_['D3'], D_['A3'], D_['Fs4'], D_['D4'], D_['A4']], 4.5, 0.5), tV, 0.0, 1.0)
    for fq in (D_['D3'], D_['A3'], D_['D4'], D_['Fs4']):
        add(mus_l, mus_r, brass(fq, 2.2, 0.3), tV, 0.0, 1.0)
    add(mus_l, mus_r, pad([D_['D2'], D_['A2'], D_['D3'], D_['Fs3'], D_['A3']], 5.0, 0.4, bright=1800, attack=0.3, release=1.5), tV, 0.0, 1.0)

    # duck the score during the big hit-stops: simple sidechain from sfx 'final' & 'burst'
    duck = np.ones(N, np.float32)
    ta = np.arange(N) / SR
    for (ts, kind, kw) in S.sfx_list:
        if kind in ('final',):
            o = T(ts)
            i0 = int(o * SR)
            i1 = min(N, i0 + int(1.8 * SR))
            seg = np.arange(i1 - i0) / SR
            duck[i0:i1] *= 1 - 0.95 * np.exp(-seg / 1.2)
    # score gain
    mL *= duck * 0.55
    mR *= duck * 0.55
    # re-introduce score after the cut
    L += mL
    R += mR

    # ---------- master
    fade_in = np.minimum(1.0, ta / 0.8)
    L *= fade_in
    R *= fade_in
    fo0 = S.warp.duration - 1.6
    fade_out = np.clip((S.warp.duration + 0.2 - ta) / 1.8, 0, 1)
    L *= fade_out
    R *= fade_out
    peak = max(np.abs(L).max(), np.abs(R).max(), 1e-6)
    L = np.tanh(L / peak * 1.8) / np.tanh(1.8)
    R = np.tanh(R / peak * 1.8) / np.tanh(1.8)
    out = np.stack([L, R], axis=1) * 0.89
    pcm = (np.clip(out, -1, 1) * 32767).astype(np.int16)
    with wave.open(out_path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return D


if __name__ == '__main__':
    import sys
    import os
    os.environ.setdefault('QUICK', '0.25')
    import story
    S = story.build()
    synth(S, sys.argv[1])
