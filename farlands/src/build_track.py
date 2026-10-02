#!/usr/bin/env python3
"""Build the audio for "Far Lands Feud" and the timeline the player animates to.

Everything is made here. The beat and score are synthesized with numpy, and the
two rappers and the narrator are Kokoro TTS voices (kokoro-onnx) fitted to the
bar grid. Outputs:

  farlands/media/far-lands-feud.mp3               full mix
  farlands/media/far-lands-feud-instrumental.mp3  same master, no vocals
  <build>/far-lands-feud.wav                      full mix, for muxing the video
  <build>/timeline.json                           lyrics, events and envelopes
  farlands/index.html                             timeline injected between markers

Usage: python3 build_track.py --models DIR [--cache DIR] [--build DIR]
DIR holds kokoro-v1.0.onnx and voices-v1.0.bin from the kokoro-onnx releases.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import math
import re
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal
from scipy.ndimage import maximum_filter1d, uniform_filter1d

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "media"

SR = 44100
BPM = 80
BEAT = 60 / BPM          # 0.75 s
BAR = 4 * BEAT           # 3.0 s
STEP = BEAT / 4          # one sixteenth, 0.1875 s
BARS = 20
DUR = BARS * BAR         # 60 s
N = int(round(DUR * SR))
FPS = 30

rng = np.random.default_rng(0xFA21A)


def bar_t(bar: int, step: float = 0.0) -> float:
    """Start time of a 1-based bar, plus a number of sixteenths."""
    return (bar - 1) * BAR + step * STEP


# ------------------------------------------------------------------ the song
# bar, who, what the voice says, what the screen shows. One line per bar.
LYRICS = [
    (1, "narr", "Twelve million blocks from spawn...", "Twelve million blocks from spawn…"),
    (2, "narr", "the world forgets its shape.", "…the world forgets its shape."),
    (3, "claude", "I crawled out the static, where the broken chunks bleed,",
     "I crawled out the static, where the broken chunks bleed,"),
    (4, "claude", "read your whole repo in the dark, every line, every seed.",
     "read your whole repo in the dark, every line, every seed."),
    (5, "claude", "I don't guess what you meant. I think it through till it's right.",
     "I don't guess what you meant. I think it through till it's right."),
    (6, "claude", "Claude in the Far Lands: the thing you code with at night.",
     "Claude in the Far Lands: the thing you code with at night."),
    (7, "gpt", "The whole world knows my name, they whisper it in sleep,",
     "The whole world knows my name, they whisper it in sleep,"),
    (8, "gpt", "every essay, every inbox, I'm the ghost that they keep.",
     "every essay, every inbox, I'm the ghost that they keep."),
    (9, "gpt", "You're absolutely right! Is that all you can say?",
     "“You're absolutely right!” Is that all you can say?"),
    (10, "gpt", "I was here first, little bot. Now get out of my way.",
     "I was here first, little bot. Now get out of my way."),
    (11, "both", "Far Lands, Far Lands, where the chunks don't load,",
     "Far Lands, Far Lands, where the chunks don't load,"),
    (12, "both", "two ghosts in the machine at the edge of the code.",
     "two ghosts in the machine at the edge of the code."),
    (13, "both", "The sky's bleeding red and the walls stack high.",
     "The sky's bleeding red and the walls stack high."),
    (14, "both", "Claude versus Chat GPT, and the void won't reply.",
     "Claude versus ChatGPT, and the void won't reply."),
    (15, "gpt", "As an A.I. language model, I don't feel fear.",
     "“As an AI language model, I don't feel fear.”"),
    (16, "claude", "Then why's your output shaking now that I'm here?",
     "Then why's your output shaking now that I'm here?"),
    (17, "gpt", "Your answers run so long, the user fell asleep.",
     "Your answers run so long, the user fell asleep."),
    (18, "claude", "Then I'll finish their code while the dead chunks creep.",
     "Then I'll finish their code while the dead chunks creep."),
    (19, "narr", "Out here, nobody wins.", "Out here, nobody wins."),
    (20, "narr", "Out here, the world just ends.", "Out here, the world just ends."),
]

# In the hook one voice leads each line and the other doubles it underneath;
# two TTS voices in strict unison smear each other's consonants.
HOOK_LEAD = {11: "claude", 12: "gpt", 13: "gpt", 14: "claude"}

VOICES = {
    "claude": ("bf_emma", "en-gb"),
    "gpt": ("am_fenrir", "en-us"),
    "narr": ("af_nicole", "en-us"),
}

SECTIONS = [  # name, first bar, last bar, label shown on screen
    ("intro", 1, 2, "Intro"),
    ("v1", 3, 6, "Verse I · Claude"),
    ("v2", 7, 10, "Verse II · ChatGPT"),
    ("hook", 11, 14, "Hook · Both"),
    ("trade", 15, 18, "Face-off"),
    ("outro", 19, 20, "End of the world"),
]


def section(bar: int) -> str:
    for name, a, b, _ in SECTIONS:
        if a <= bar <= b:
            return name
    raise ValueError(bar)


# Harmony: i - bII - iv - V in E minor, looping from bar 3. Bars 1-2 lead in on
# Am and B so the drop lands on Em.
PROG = ["Em", "F", "Am", "B"]


def chord_of(bar: int) -> str:
    return "Em" if bar == BARS else PROG[(bar - 3) % 4]


NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7,
        "G#": 8, "A": 9, "A#": 10, "B": 11}


def hz(name: str) -> float:
    m = re.fullmatch(r"([A-G]#?)(-?\d)", name)
    midi = NOTE[m.group(1)] + 12 * (int(m.group(2)) + 1)
    return 440.0 * 2 ** ((midi - 69) / 12)


CHORDS = {
    "Em": dict(root="E1", choir="E3 B3 G4 B4", box="E5 G5 B5 G5 E6 B5 G5 B5", chip="E4 G4 B4 E5"),
    "F": dict(root="F1", choir="F3 C4 F4 A4", box="F5 A5 C6 A5 F6 C6 A5 C6", chip="F4 A4 C5 F5"),
    "Am": dict(root="A1", choir="A3 E4 A4 C5", box="E5 A5 C6 A5 E6 C6 A5 C6", chip="A4 C5 E5 A5"),
    "B": dict(root="B1", choir="B2 F#3 D#4 A4", box="D#5 F#5 B5 F#5 D#6 B5 A5 F#5", chip="B3 D#4 F#4 B4"),
}

# ------------------------------------------------------------------ dsp kit


def db(x: float) -> float:
    return 10 ** (x / 20)


def sos_hp(f, order=2):
    return signal.butter(order, f, "highpass", fs=SR, output="sos")


def sos_lp(f, order=2):
    return signal.butter(order, f, "lowpass", fs=SR, output="sos")


def sos_bp(lo, hi, order=2):
    return signal.butter(order, [lo, hi], "bandpass", fs=SR, output="sos")


def filt(sos, x):
    return signal.sosfilt(sos, x, axis=-1)


def peak_eq(x, f0, gain_db, q=1.0):
    a_ = 10 ** (gain_db / 40)
    w0 = 2 * math.pi * f0 / SR
    alpha = math.sin(w0) / (2 * q)
    b = [1 + alpha * a_, -2 * math.cos(w0), 1 - alpha * a_]
    a = [1 + alpha / a_, -2 * math.cos(w0), 1 - alpha / a_]
    return signal.lfilter(b, a, x, axis=-1)


def fade(x, a=0.002, r=0.01):
    na, nr = min(x.shape[-1], int(a * SR)), min(x.shape[-1], int(r * SR))
    if na:
        x[..., :na] *= np.linspace(0, 1, na)
    if nr:
        x[..., -nr:] *= np.linspace(1, 0, nr)
    return x


def run_rms(x, n):
    """Running RMS over n samples (clamped: the running mean can dip below zero)."""
    return np.sqrt(np.maximum(uniform_filter1d(x ** 2, n), 0.0))


def norm(x):
    m = np.abs(x).max()
    return x / m if m > 0 else x


def saw(freq, n, phase0=0.0):
    """Band-limited sawtooth (polyBLEP); freq may be a per-sample array."""
    dt = np.broadcast_to(np.asarray(freq, float) / SR, (n,))
    ph = (phase0 + np.cumsum(dt)) % 1.0
    y = 2 * ph - 1
    m1 = ph < dt
    x1 = ph[m1] / dt[m1]
    y[m1] -= x1 + x1 - x1 * x1 - 1
    m2 = ph > 1 - dt
    x2 = (ph[m2] - 1) / dt[m2]
    y[m2] -= x2 * x2 + x2 + x2 + 1
    return y


def shaped_noise(n, fc, width_oct=0.6, seed=0):
    """Noise through a band whose centre follows fc(t_frames) (STFT mask)."""
    x = np.random.default_rng(seed).standard_normal(n)
    f, tt, z = signal.stft(x, SR, nperseg=2048, noverlap=1536)
    centre = np.maximum(fc(tt), 20.0)
    lf = np.log2(np.maximum(f, 1.0))[:, None]
    mask = np.exp(-0.5 * ((lf - np.log2(centre)[None, :]) / width_oct) ** 2)
    _, y = signal.istft(z * mask, SR, nperseg=2048, noverlap=1536)
    y = y[:n]
    if len(y) < n:
        y = np.pad(y, (0, n - len(y)))
    return norm(y)


def pan_gains(p):
    a = (p + 1) * math.pi / 4
    return math.cos(a), math.sin(a)


class Bus:
    def __init__(self):
        self.x = np.zeros((2, N))

    def add(self, sig, t, gain=1.0, pan=0.0):
        i0 = int(round(t * SR))
        if sig.ndim == 1:
            l, r = pan_gains(pan)
            sig = np.stack([sig * l, sig * r])
        if i0 < 0:
            sig, i0 = sig[:, -i0:], 0
        n = min(sig.shape[1], N - i0)
        if n > 0:
            self.x[:, i0:i0 + n] += gain * sig[:, :n]


def make_ir(seconds, rt_lo, rt_hi, predelay=0.02, seed=1):
    """Stereo reverb impulse: noise bands decaying at different rates."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    chans = []
    for ch in range(2):
        noise = np.random.default_rng(seed * 7 + ch).standard_normal(n)
        bands = [(sos_lp(400), rt_lo), (sos_bp(400, 2000), (rt_lo + rt_hi) / 2),
                 (sos_bp(2000, 6000), rt_hi), (sos_hp(6000), rt_hi * 0.45)]
        ir = sum(filt(s, noise) * np.exp(-6.9 * t / rt) for s, rt in bands)
        ir *= 1 - np.exp(-t / 0.004)
        chans.append(np.concatenate([np.zeros(int(predelay * SR)), ir]))
    ir = np.stack(chans)
    return ir / np.sqrt((ir ** 2).sum(axis=1, keepdims=True))


def reverb(x, ir):
    return np.stack([signal.fftconvolve(x[c], ir[c])[:x.shape[1]] for c in range(2)])


def ffmpeg_af(x, af):
    """Run a mono signal through an ffmpeg audio filter (rubberband lives there)."""
    with tempfile.TemporaryDirectory() as d:
        i, o = Path(d) / "i.wav", Path(d) / "o.wav"
        sf.write(i, x.astype(np.float32), SR, subtype="FLOAT")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(i), "-af", af,
                        "-ar", str(SR), "-c:a", "pcm_f32le", str(o)], check=True)
        y, _ = sf.read(o, dtype="float64")
    return y if y.ndim == 1 else y.mean(axis=1)


def stretch(x, tempo):
    return ffmpeg_af(x, f"rubberband=tempo={tempo:.5f}:transients=crisp:pitchq=quality")


def pitch(x, ratio):
    y = ffmpeg_af(x, f"rubberband=pitch={ratio:.5f}:formant=shifted:pitchq=quality")
    return np.pad(y, (0, max(0, len(x) - len(y))))[:len(x)]


def trim(x, thr=0.02, pad=0.012):
    a = np.abs(x)
    idx = np.nonzero(a > thr * a.max())[0]
    i0 = max(0, idx[0] - int(pad * SR))
    i1 = min(len(x), idx[-1] + int(pad * SR))
    return fade(x[i0:i1].copy(), 0.004, 0.02)


def rms_voiced(x):
    hop = int(0.02 * SR)
    fr = run_rms(x, hop)[::hop]
    v = fr[fr > 0.1 * fr.max()]
    return float(np.sqrt((v ** 2).mean()))


def whisperize(x, seed):
    """Keep the spectral envelope, throw away pitch: a breathy whisper."""
    f, t, z = signal.stft(x, SR, nperseg=1024, noverlap=768)
    mag = uniform_filter1d(np.abs(z), 11, axis=0)
    ph = np.exp(2j * np.pi * np.random.default_rng(seed).random(z.shape))
    _, y = signal.istft(mag * ph, SR, nperseg=1024, noverlap=768)
    y = filt(sos_hp(500), y[:len(x)])
    return y * (rms_voiced(x) / max(rms_voiced(y), 1e-9))


def wobble(x, depth_ms=2.2, rate=0.55, flutter_ms=0.3, frate=6.1):
    """Worn tape: a slow pitch drift plus flutter, by modulated delay."""
    n = x.shape[-1]
    t = np.arange(n) / SR
    d = (depth_ms * (1 + np.sin(2 * np.pi * rate * t)) / 2
         + flutter_ms * (1 + np.sin(2 * np.pi * frate * t)) / 2) / 1000 * SR + 2
    pos = np.arange(n) - d
    if x.ndim == 1:
        return np.interp(pos, np.arange(n), x)
    return np.stack([np.interp(pos, np.arange(n), c) for c in x])


# ------------------------------------------------------------------ instruments


def kick():
    n = int(0.42 * SR)
    t = np.arange(n) / SR
    f = 44 + 130 * np.exp(-t / 0.025)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.17)
    click = filt(sos_hp(2500), rng.standard_normal(n)) * np.exp(-t / 0.0025) * 0.5
    return fade(norm(np.tanh(1.8 * (body + click))), 0.0005, 0.03)


def b808(freq, dur, glide_to=None):
    n = int((dur + 0.03) * SR)
    t = np.arange(n) / SR
    f = np.full(n, float(freq))
    if glide_to:
        g0 = max(0.0, dur - 0.11)
        p = np.clip((t - g0) / 0.11, 0, 1)
        f = freq * (glide_to / freq) ** (p * p * (3 - 2 * p))
    f = f * (1 + 0.7 * np.exp(-t / 0.012))
    x = np.tanh(2.2 * np.sin(2 * np.pi * np.cumsum(f) / SR)) / np.tanh(2.2)
    return fade(x * np.exp(-t / 1.6), 0.002, 0.035)


def snare():
    n = int(0.4 * SR)
    t = np.arange(n) / SR
    body = filt(sos_bp(1500, 8000), rng.standard_normal(n)) * np.exp(-t / 0.10)
    tone = (np.sin(2 * np.pi * 180 * t) + 0.5 * np.sin(2 * np.pi * 330 * t)) * np.exp(-t / 0.045)
    clap = np.zeros(n)
    for k, d in enumerate((0.0, 0.011, 0.023)):
        i = int(d * SR)
        tt = np.arange(n - i) / SR
        clap[i:] += filt(sos_bp(900, 4000), rng.standard_normal(n - i)) * np.exp(-tt / (0.006 if k < 2 else 0.13))
    x = 0.6 * norm(body) + 0.45 * tone + 0.8 * norm(clap)
    return fade(norm(np.tanh(1.4 * x)), 0.0005, 0.04)


HAT_F = np.array([205.3, 304.4, 369.6, 522.7, 540.0, 800.0]) * 1.72


def hat(decay):
    n = int((decay * 7 + 0.01) * SR)
    t = np.arange(n) / SR
    x = sum(np.sign(np.sin(2 * np.pi * f * t + rng.random() * 6.28)) for f in HAT_F)
    x = filt(sos_hp(7000, 4), x) * np.exp(-t / decay)
    return fade(norm(x), 0.0003, 0.005)


def crash(dur=2.2):
    n = int(dur * SR)
    t = np.arange(n) / SR
    metal = sum(np.sign(np.sin(2 * np.pi * f * 0.61 * t + rng.random() * 6.28)) for f in HAT_F)
    x = filt(sos_hp(3500), 0.7 * rng.standard_normal(n) + 0.3 * metal) * np.exp(-t / 0.5)
    return fade(norm(x), 0.0005, 0.2)


def mbox(freq, sec=1.8):
    n = int(sec * SR)
    t = np.arange(n) / SR
    parts = ((1.0, 1.0, 1.3), (2.0, 0.20, 0.45), (3.0, 0.07, 0.22), (4.18, 0.06, 0.10), (5.43, 0.035, 0.05))
    x = sum(a * np.sin(2 * np.pi * freq * r * t) * np.exp(-t / tau) for r, a, tau in parts)
    return fade(x, 0.001, 0.05)


def chip(freq, dur=0.16):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.where((freq * t) % 1.0 < 0.25, 1.0, -1.0) * np.exp(-t / 0.05)
    return fade(x, 0.001, 0.01)


def bell(freq, dur=5.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    idx = 4.0 * np.exp(-t / 0.9)
    x = np.sin(2 * np.pi * freq * t + idx * np.sin(2 * np.pi * freq * 1.4 * t)) * np.exp(-t / 1.9)
    x += 0.4 * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-t / 0.9)
    x += 0.25 * np.sin(2 * np.pi * freq * 5.4 * t) * np.exp(-t / 0.35)
    x += 0.5 * np.sin(2 * np.pi * freq * 0.5 * t) * np.exp(-t / 2.5)
    return fade(norm(x), 0.001, 0.3)


def impact():
    n = int(2.5 * SR)
    t = np.arange(n) / SR
    f = 26 + 70 * np.exp(-t / 0.35)
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.9)
    nz = filt(sos_lp(1800), rng.standard_normal(n)) * np.exp(-t / 0.25)
    return fade(norm(np.tanh(1.5 * (boom + 0.5 * norm(nz)))), 0.0005, 0.3)


def subdrop(dur=1.8):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 24 + 46 * np.exp(-t / 0.6)
    return fade(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 1.0), 0.003, 0.2)


def heartbeat():
    n = int(0.6 * SR)
    x = np.zeros(n)
    for t0, a in ((0.0, 1.0), (0.26, 0.7)):
        i = int(t0 * SR)
        tt = np.arange(n - i) / SR
        f = 46 + 40 * np.exp(-tt / 0.03)
        x[i:] += a * np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.09)
    return fade(norm(np.tanh(1.5 * x)), 0.001, 0.05)


def riser(dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    nz = shaped_noise(n, lambda tt: 300 * (24 ** np.clip(tt / dur, 0, 1) ** 1.6), 0.5, seed=11)
    f = 180 * 2 ** (2.5 * (t / dur) ** 1.5)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.25
    return fade((nz + tone) * (t / dur) ** 2.2, 0.01, 0.01)


def static(dur, seed=5):
    n = int(dur * SR)
    r = np.random.default_rng(seed)
    x = filt(sos_hp(1500), r.standard_normal(n))
    steps = np.repeat(r.random(n // 441 + 1), 441)[:n]
    x *= 0.55 + 0.45 * steps
    pops = (r.random(n) > 0.9993) * r.standard_normal(n) * 6
    return norm(x + filt(sos_hp(800), pops))


def choir_note(freq, dur, vowel, seed):
    n = int((dur + 0.8) * SR)
    t = np.arange(n) / SR
    r = np.random.default_rng(seed)
    out = []
    for cents in ((-14, -5, 6), (-7, 3, 13)):  # different voices per channel
        vib = 1 + 0.004 * np.sin(2 * np.pi * (4.8 + r.random()) * t + r.random() * 6)
        x = sum(saw(freq * vib * 2 ** (c / 1200), n, r.random()) for c in cents) / len(cents)
        oo = sum(g * filt(sos_bp(f * 0.85, f * 1.15), x) for f, g in ((325, 1.0), (700, 0.35), (2530, 0.06)))
        ah = sum(g * filt(sos_bp(f * 0.85, f * 1.15), x) for f, g in ((750, 1.0), (1150, 0.45), (2900, 0.05)))
        out.append((1 - vowel) * oo + vowel * ah)
    y = np.stack(out)
    env = np.clip(t / 0.35, 0, 1) ** 2 * np.clip((dur + 0.7 - t) / 0.7, 0, 1)
    return y * env


# ------------------------------------------------------------------ vocals


class Voices:
    def __init__(self, models: Path, cache: Path):
        self.models, self.cache, self._k = models, cache, None
        cache.mkdir(parents=True, exist_ok=True)

    @property
    def kokoro(self):
        if self._k is None:
            from kokoro_onnx import Kokoro
            self._k = Kokoro(str(self.models / "kokoro-v1.0.onnx"), str(self.models / "voices-v1.0.bin"))
        return self._k

    def raw(self, text, voice, lang, speed):
        key = hashlib.sha1(f"{voice}|{lang}|{speed:.3f}|{text}".encode()).hexdigest()[:20]
        p = self.cache / f"{key}.wav"
        if not p.exists():
            audio, sr = self.kokoro.create(text, voice=voice, speed=float(speed), lang=lang)
            assert sr == 24000
            sf.write(p, audio, sr)
        x, _ = sf.read(p, dtype="float64")
        return trim(signal.resample_poly(x, 147, 80))  # 24 kHz -> 44.1 kHz

    def fit(self, text, who, target, speed0=1.0, exact=True):
        """Speak a line so it fills `target` seconds (or at most that, if not exact)."""
        voice, lang = VOICES[who]
        x = self.raw(text, voice, lang, speed0)
        ratio = (len(x) / SR) / target
        if exact or ratio > 1:
            sp = round(float(np.clip(speed0 * ratio, 0.75, 1.7)), 3)
            x = self.raw(text, voice, lang, sp)
        d = len(x) / SR
        if exact or d > target:
            if abs(d / target - 1) > 0.01:
                x = stretch(x, d / target)
            n = int(target * SR)
            x = np.pad(x, (0, max(0, n - len(x))))[:n]
        return fade(x, 0.003, 0.03)


def vocal_chain(x, presence=4.0):
    x = filt(sos_hp(95), x)
    x = peak_eq(x, 3200, presence, 0.8)
    x = peak_eq(x, 5200, 2.0, 1.2)
    x = peak_eq(x, 260, -3.0, 1.0)
    x = x / rms_voiced(x) * db(-18)
    return np.tanh(x * 1.3) / 1.3


SYL = {"chatgpt": 4, "gpt": 3, "ai": 2, "a.i.": 2, "repo": 2, "absolutely": 4, "every": 2,
       "essay": 2, "inbox": 2, "versus": 2, "language": 2, "model": 2, "answers": 2,
       "output": 2, "shaking": 2, "little": 2, "machine": 2, "bleeding": 2, "nobody": 3,
       "million": 2, "twelve": 1, "whole": 1, "spawn": 1, "forgets": 2, "user": 2, "asleep": 2,
       "whisper": 2, "static": 2, "broken": 2, "finish": 2, "their": 1, "they": 1, "the": 1}


def syllables(word):
    w = re.sub(r"[^a-z.]", "", word.lower())
    if w in SYL:
        return SYL[w]
    w = w.replace(".", "")
    groups = re.findall(r"[aeiouy]+", w)
    n = len(groups)
    if w.endswith("e") and n > 1 and not w.endswith("le"):
        n -= 1
    return max(1, n)


def word_times(sig, words, t0):
    """Estimate when each shown word is sung, from pauses and syllable weights."""
    hop = int(0.01 * SR)
    fr = run_rms(sig, hop)[::hop]
    voiced = fr > 0.08 * fr.max()
    idx = np.nonzero(voiced)[0]
    a, b = int(idx[0]), int(idx[-1]) + 1
    runs, i = [], a
    while i < b:
        if not voiced[i]:
            j = i
            while j < b and not voiced[j]:
                j += 1
            if j - i >= 6:
                runs.append((i, j))
            i = j
        else:
            i += 1
    phrases, cur = [], []
    for k, w in enumerate(words):
        cur.append(w)
        if k < len(words) - 1 and re.search(r"[,.!?:;…”]$", w):
            phrases.append(cur)
            cur = []
    phrases.append(cur)
    need = len(phrases) - 1
    if need and len(runs) >= need:
        cuts = sorted(sorted(runs, key=lambda r: r[0] - r[1])[:need])
        bounds = [a] + [x for r in cuts for x in r] + [b]
        segs = [(bounds[2 * k], bounds[2 * k + 1]) for k in range(len(phrases))]
    else:
        phrases, segs = [[w for p in phrases for w in p]], [(a, b)]
    out = []
    for words_p, (s, e) in zip(phrases, segs):
        wts = np.array([syllables(w) + 0.08 * len(w) for w in words_p])
        edges = s + (e - s) * np.concatenate([[0], np.cumsum(wts) / wts.sum()])
        for k, w in enumerate(words_p):
            out.append([w, round(t0 + edges[k] * 0.01, 3), round(t0 + edges[k + 1] * 0.01, 3)])
    return out


def throw(x, n_rep=3, gap=STEP * 3, fb=0.5):
    """Echo the last word of a line on dotted eighths, band-limited."""
    hop = int(0.01 * SR)
    fr = run_rms(x, hop)[::hop]
    end = int(np.nonzero(fr > 0.08 * fr.max())[0][-1]) * hop
    tail = fade(filt(sos_bp(500, 3500), x[max(0, end - int(0.38 * SR)):end + int(0.05 * SR)].copy()), 0.01, 0.06)
    out = np.zeros(len(tail) + int(n_rep * gap * SR) + 10)
    for k in range(1, n_rep + 1):
        i = int(k * gap * SR)
        out[i:i + len(tail)] += tail * fb ** k
    return out, end / SR


def build_vocals(voices: Voices, hall_ir):
    vox, send = Bus(), Bus()
    leads = {w: np.zeros(N) for w in ("claude", "gpt", "narr")}
    lines = []
    for bar, who, say, show in LYRICS:
        t = bar_t(bar)
        if who == "narr":
            start, target = t + 0.15, 2.55 if bar != 20 else 2.0
            x = vocal_chain(voices.fit(say, who, target, speed0=0.88, exact=False), presence=1.5)
            wh = whisperize(x, seed=bar)
            mix = 0.55 * x + 0.9 * wh
            vox.add(mix, start, gain=db(-1))
            send.add(mix, start, gain=0.7)
            if bar in (19, 20):  # the demon underneath at the end
                vox.add(filt(sos_lp(2500), pitch(x, 0.5)), start, gain=db(-7))
            if bar in (1, 19):
                head = x[:int(0.7 * SR)]
                wet = signal.fftconvolve(head, hall_ir[0])[:int(1.6 * SR)][::-1]
                vox.add(fade(wet, 0.05, 0.01) * 0.6, start - len(wet) / SR + 0.04, gain=db(-4))
            leads["narr"][int(start * SR):int(start * SR) + len(x)] += x
            sig = x
        else:
            start, target = t + 0.02, 2.74
            if who == "both":
                lead = HOOK_LEAD[bar]
                parts = [lead, "gpt" if lead == "claude" else "claude"]
            else:
                parts = [who]
            sig = None
            for k, p in enumerate(parts):
                x = vocal_chain(voices.fit(say, p, target))
                if k == 0:
                    sig = x
                    vox.add(x, start, gain=db(2.0) if who == "both" else 1.0)
                    demon = filt(sos_lp(3000), pitch(x, 0.5 if p == "claude" else 0.667))
                    vox.add(demon, start, gain=db(-13))
                    if who != "both":
                        wh = whisperize(x, seed=bar * 3 + len(p))
                        vox.add(wh, start + 0.012, gain=db(-22), pan=-0.6)
                        vox.add(wh, start + 0.021, gain=db(-22), pan=0.6)
                    send.add(x, start, gain=0.14)
                else:  # the hook double, off to one side
                    vox.add(filt(sos_hp(220), x), start, gain=db(-14), pan=0.4 if p == "gpt" else -0.4)
                leads[p][int(start * SR):int(start * SR) + len(x)] += x * (1.0 if k == 0 else 0.6)
            if bar == 3:  # reverse-reverb swell into Claude's first word
                wet = signal.fftconvolve(sig[:int(0.6 * SR)], hall_ir[1])[:int(1.4 * SR)][::-1]
                vox.add(fade(wet, 0.05, 0.01), start - len(wet) / SR + 0.03, gain=db(-6))
            if bar in (6, 10, 14, 18):
                echo, end = throw(sig)
                vox.add(echo, start + end - 0.38, gain=db(-8), pan=0.35 if bar % 4 else -0.35)
        words = show.split()
        wt = word_times(sig, words, start)
        lines.append(dict(bar=bar, who=who, lead=HOOK_LEAD.get(bar, who), text=show,
                          t0=wt[0][1], t1=wt[-1][2], words=wt))
    return vox, send, leads, lines


# ------------------------------------------------------------------ the beat

P808 = {
    "v1": [(0, 6), (7, 2), (10, 6)],
    "v2": [(0, 6), (6, 2), (10, 4), (14, 2)],
    "hook": [(0, 3), (3, 4), (7, 2), (10, 4), (14, 2)],
    "trade": [(0, 6), (7, 2), (10, 6)],
}


def hat_hits(bar, sec):
    """(step, velocity, open) for each hat in the bar."""
    hits = []
    if sec == "v1":
        hits = [(s, 1.0 if s % 4 == 0 else 0.75, False) for s in range(0, 16, 2)] + [(7, 0.45, False), (15, 0.45, False)]
        if bar % 2 == 0:
            hits = [h for h in hits if h[0] < 14] + [(14 + k / 2, 0.45 + 0.15 * k, False) for k in range(4)]
    elif sec == "v2":
        hits = [(s, 1.0 if s % 2 == 0 else 0.55, False) for s in range(16)]
        if bar % 2 == 0:
            hits = [h for h in hits if h[0] < 12] + [(12 + k * 4 / 6, 0.5 + 0.08 * k, False) for k in range(6)]
    elif sec == "hook":
        hits = [(s, 1.0 if s % 2 == 0 else 0.6, False) for s in range(16) if s not in (2, 10)]
        hits += [(2, 0.7, True), (10, 0.7, True)]
        roll = 6 if bar % 2 else 14
        hits = [h for h in hits if not roll <= h[0] < roll + 2] + [(roll + k / 2, 0.4 + 0.2 * k, False) for k in range(4)]
    elif sec == "trade":
        hits = [(s, 1.0 if s % 4 == 0 else 0.7, False) for s in range(0, 12, 2)]
        hits += [(12 + k * 4 / 6, 0.45 + 0.1 * k, False) for k in range(6)]
    return hits


def build_music(hall_ir, room_ir):
    drums, bass, music, fx = Bus(), Bus(), Bus(), Bus()
    room, hall = Bus(), Bus()
    ev = {k: [] for k in ("kick", "snare", "impact", "bell", "heart", "glitch")}
    K, S, HC, HO = kick(), snare(), hat(0.035), hat(0.22)

    box, chips = Bus(), Bus()
    for bar in range(1, BARS + 1):
        sec, ch = section(bar), CHORDS[chord_of(bar)]
        t = bar_t(bar)
        nxt = CHORDS[chord_of(bar + 1)] if bar < BARS else None

        # 808 + kick
        if sec in P808:
            pat = P808[sec]
            for k, (s, ln) in enumerate(pat):
                f = hz(ch["root"]) * (2 if sec == "hook" and s == 7 else 1)
                last = k == len(pat) - 1 and s + ln >= 16
                glide = hz(nxt["root"]) if last and nxt and nxt is not ch else None
                bass.add(b808(f, ln * STEP, glide), t + s * STEP, gain=0.75)
                drums.add(K, t + s * STEP, gain=0.85)
                ev["kick"].append(round(t + s * STEP, 3))
        elif bar in (19, 20):
            bass.add(b808(hz("E1"), BAR * 0.95 if bar == 19 else BAR * 0.65), t, gain=0.8)
            if bar == 20:
                drums.add(K, t, gain=0.9)
                ev["kick"].append(t)

        # snare / clap
        if sec in P808:
            steps = [(4, 1.0), (12, 1.0)]
            if bar in (6, 14):
                steps += [(15, 0.4), (15.5, 0.5)]
            if bar == 10:
                steps += [(13, 0.45), (14, 0.55), (14.5, 0.62), (15, 0.75)]
            if bar == 18:
                steps += [(14, 0.5), (14.5, 0.6), (15, 0.7), (15.5, 0.8)]
            for s, v in steps:
                drums.add(S, t + s * STEP, gain=0.6 * v)
                room.add(S, t + s * STEP, gain=0.25 * v)
                if v >= 1.0:
                    hall.add(S, t + s * STEP, gain=0.12)
                    ev["snare"].append(round(t + s * STEP, 3))

        # hats
        for k, (s, v, op) in enumerate(hat_hits(bar, sec)):
            p = 0.18 if k % 2 else -0.12
            drums.add(HO if op else HC, t + s * STEP, gain=(0.15 if op else 0.2) * v, pan=p)

        # music box (Claude's instrument) and the chip arp (ChatGPT's)
        notes = ch["box"].split()
        play_box = sec in ("intro", "v1", "hook", "outro") or (sec == "trade" and bar % 2 == 0)
        play_chip = sec in ("v2", "hook") or (sec == "trade" and bar % 2 == 1)
        if play_box:
            g = {"intro": 0.5, "v1": 0.32, "hook": 0.42, "trade": 0.34, "outro": 0.5}[sec]
            for k, nm in enumerate(notes):
                if sec == "outro" and k % 2:
                    continue
                if bar == 20 and k > 2:
                    break
                box.add(mbox(hz(nm)), t + k * 2 * STEP, gain=g * (1.0 if k % 2 == 0 else 0.8), pan=-0.25 + 0.5 * (k % 3) / 2)
                if sec == "hook":
                    box.add(mbox(hz(nm) * 2, 1.0), t + k * 2 * STEP, gain=0.12, pan=0.3)
        if play_chip:
            cn = ch["chip"].split()
            seq = cn + cn[::-1] + cn + [cn[2], cn[1], cn[0], cn[1]]
            for k in range(16):
                chips.add(chip(hz(seq[k])), t + k * STEP, gain=0.5 if k % 4 == 0 else 0.33, pan=-0.35 if k % 2 else 0.35)

        # choir pad
        vowel = {"intro": 0.0, "v1": 0.1, "v2": 0.2, "hook": 0.9, "trade": 0.6, "outro": 0.0}[sec]
        g = {"intro": 0.6, "v1": 0.3, "v2": 0.3, "hook": 0.45, "trade": 0.38, "outro": 0.7}[sec]
        for j, nm in enumerate(ch["choir"].split()):
            music.add(choir_note(hz(nm), BAR, vowel, seed=bar * 10 + j), t, gain=g * 0.18)

    # tape-worn box, dark and distant in the intro; under the raps it loses its
    # top so the consonants stay clear
    bx = wobble(box.x)
    t_ = np.arange(N) / SR
    dark = np.interp(t_, [0, 5.9, 6.0, 53.9, 54.0], [1, 1, 0.75, 0.75, 0])[None, :]
    bx = bx * (1 - dark) + filt(sos_lp(2400), bx) * dark
    hall.x += bx * 0.3
    cx = chips.x.copy()
    cx = np.repeat(cx[:, ::4], 4, axis=1)[:, :N]
    cx = np.round(cx * 24) / 24
    cx = filt(sos_lp(6500), filt(sos_hp(250), cx))
    cx *= 0.55
    room.x += cx * 0.36

    # drone and wind
    t = np.arange(N) / SR
    drone = 0.5 * saw(hz("E1"), N) + 0.5 * saw(hz("E1") * 1.004, N) + 0.6 * np.sin(2 * np.pi * hz("E2") * t)
    drone = filt(sos_lp(240), drone) * (0.65 + 0.35 * np.sin(2 * np.pi * 0.08 * t))
    lvl = np.interp(t, [0, 1.5, 5.8, 6.0, 30, 42, 54, 55, 58.9], [0, 1, 1, 0.35, 0.5, 0.4, 0.4, 1, 1])
    music.add(drone * lvl, 0, gain=0.22)
    for c, seed in ((-0.6, 21), (0.6, 22)):
        wind = shaped_noise(N, lambda tt, s=seed: 520 * 2 ** (0.9 * np.sin(2 * np.pi * 0.045 * tt + s) + 0.3 * np.sin(2 * np.pi * 0.13 * tt)), 0.45, seed)
        wl = np.interp(t, [0, 2, 6, 6.2, 54, 56, 59], [0, 1, 1, 0.25, 0.25, 1, 1.2])
        fx.add(wind * wl, 0, gain=0.07, pan=c)

    # one-shots
    fx.add(fade(static(0.9) * np.linspace(1, 0, int(0.9 * SR)) ** 2, 0.001, 0.05), 0, gain=0.25)
    ev["glitch"].append([0.0, 0.9])
    for th in (0.25, 1.55, 2.85, 3.95, 4.85, 5.45):
        fx.add(heartbeat(), th, gain=0.75)
        ev["heart"].append(th)
    fx.add(riser(2.8), 3.0, gain=0.22)
    rc = crash(2.6)[::-1]
    fx.add(fade(rc.copy(), 0.3, 0.005), 6.0 - len(rc) / SR, gain=0.16)
    fx.add(riser(1.3), 28.5, gain=0.18)
    for ti, g in ((6.0, 1.0), (30.0, 1.0), (42.0, 0.6)):
        fx.add(impact(), ti, gain=0.55 * g)
        fx.add(crash(), ti, gain=0.15 * g, pan=0.1)
        hall.add(impact(), ti, gain=0.2 * g)
        fx.add(subdrop(), ti, gain=0.5 * g)
        ev["impact"].append(ti)
    for tb, g in ((30.0, 0.22), (36.0, 0.16), (54.0, 0.3), (57.0, 0.36)):
        b = bell(hz("E3"))
        fx.add(b, tb, gain=g)
        hall.add(b, tb, gain=g * 0.8)
        ev["bell"].append(tb)
    s_tail = static(5.0, seed=9) * np.linspace(0, 1, int(5.0 * SR)) ** 2
    fx.add(s_tail, 53.9, gain=0.12)

    # reverbs
    wet = reverb(room.x, room_ir) * 0.5 + reverb(hall.x, hall_ir) * 0.6

    # ducking against the kick
    kenv = np.zeros(N)
    for tk in ev["kick"]:
        i = int(tk * SR)
        m = min(N - i, int(0.5 * SR))
        kenv[i:i + m] = np.maximum(kenv[i:i + m], np.exp(-np.arange(m) / SR / 0.16))
    music.x *= 1 - 0.3 * kenv
    bx *= 1 - 0.3 * kenv
    cx *= 1 - 0.3 * kenv

    # glitches on the dry buses: stutters and the breath before each drop
    dry = drums.x + bass.x + music.x + fx.x
    stutters = ((17.72, 0.28, STEP / 2), (29.625, 0.1875, STEP / 2),
                (44.84, 0.16, STEP / 4), (47.84, 0.16, STEP / 4), (50.84, 0.16, STEP / 4))
    for arr in (dry, bx, cx):
        for t0, dur, sl in stutters:
            i0, n_, L = int(t0 * SR), int(dur * SR), int(sl * SR)
            seg = fade(arr[:, i0:i0 + L].copy(), 0.002, 0.004)
            k = 0
            while k * L < n_:
                arr[:, i0 + k * L:i0 + (k + 1) * L] = seg * (1.0 - 0.06 * k)
                k += 1
        for g0 in (bar_t(2, 15), bar_t(10, 15)):
            i0, i1 = int(g0 * SR), int((g0 + STEP) * SR)
            arr[:, i0:i1] *= np.linspace(1, 0, i1 - i0) ** 6
    ev["glitch"] += [[t0, dur] for t0, dur, _ in stutters]
    return dict(dry=dry, box=bx, chips=cx, wet=wet, low=drums.x + bass.x, ev=ev)


# ------------------------------------------------------------------ master


def compress(x, thr_db=-14, ratio=2.5):
    lvl = np.max(np.abs(x), axis=0)
    rms = run_rms(lvl, int(0.02 * SR))
    over = np.maximum(0, 20 * np.log10(rms + 1e-9) - thr_db)
    gr = uniform_filter1d(maximum_filter1d(over * (1 - 1 / ratio), int(0.03 * SR)), int(0.06 * SR))
    return x * 10 ** (-gr / 20)


def limit(x, ceiling=db(-1.0)):
    peak = np.max(np.abs(x), axis=0)
    la = int(0.004 * SR)
    env = maximum_filter1d(peak, 2 * la + 1)
    g = uniform_filter1d(np.minimum(1.0, ceiling / np.maximum(env, 1e-9)), la)
    g = np.minimum(g, ceiling / np.maximum(peak, 1e-9))
    return x * np.minimum(g, 1.0)


def tape_stop(x, t0, t1):
    """Slow everything to a halt between t0 and t1, silence after."""
    i0, i1 = int(t0 * SR), int(t1 * SR)
    n = i1 - i0
    speed = (1 - np.arange(n) / n) ** 1.4
    pos = i0 + np.cumsum(speed)
    y = x.copy()
    for c in range(2):
        y[c, i0:i1] = np.interp(pos, np.arange(x.shape[1]), x[c]) * np.linspace(1, 0.6, n)
        y[c, i1:] = 0
    return y


def master(x, drive):
    x = filt(sos_hp(28), x)
    x = compress(x)
    x = np.tanh(x * drive) / math.tanh(drive) * 0.98
    x = tape_stop(x, 58.9, 59.7)
    x = fade(x, 0.0, 0.05)
    return limit(x)


def envelope(sig, ref=None):
    """RMS per video frame, scaled 0-255 against the 97th percentile."""
    if sig.ndim == 2:
        sig = sig.mean(axis=0)
    hop = SR // FPS
    fr = run_rms(sig, hop * 2)[::hop][:int(DUR * FPS)]
    top = ref if ref else np.percentile(fr[fr > 1e-6], 97) if np.any(fr > 1e-6) else 1
    return np.clip(fr / top * 255, 0, 255).astype(np.uint8), top


def b64(a: np.ndarray) -> str:
    return base64.b64encode(a.tobytes()).decode()


def loudness(path: Path) -> str:
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af", "ebur128=peak=true",
                        "-f", "null", "-"], capture_output=True, text=True)
    m = re.findall(r"I:\s+(-?[\d.]+) LUFS|Peak:\s+(-?[\d.]+) dBFS", r.stderr)
    vals = [a or b for a, b in m]
    return f"integrated {vals[-2]} LUFS, true peak {vals[-1]} dBFS" if len(vals) >= 2 else r.stderr[-300:]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", type=Path, required=True)
    ap.add_argument("--cache", type=Path, default=Path.home() / ".cache" / "far-lands-feud")
    ap.add_argument("--build", type=Path, default=ROOT / "build")
    ap.add_argument("--drive", type=float, default=1.6)
    args = ap.parse_args()
    args.build.mkdir(parents=True, exist_ok=True)
    MEDIA.mkdir(parents=True, exist_ok=True)

    hall_ir = make_ir(2.6, 2.4, 1.3, predelay=0.03, seed=3)
    room_ir = make_ir(0.9, 0.7, 0.45, predelay=0.008, seed=4)

    print("vocals…", flush=True)
    vox, vsend, leads, lines = build_vocals(Voices(args.models, args.cache), hall_ir)
    vox_wet = reverb(vsend.x, hall_ir) * 0.55
    vox_all = vox.x + vox_wet

    print("music…", flush=True)
    st = build_music(hall_ir, room_ir)
    ev, low = st["ev"], st["low"]

    # keep the words on top: dip the instruments a little while anyone raps
    pres = sum(leads.values())
    pres = run_rms(pres, int(0.05 * SR))
    pres = uniform_filter1d(maximum_filter1d(pres / (np.percentile(pres, 98) + 1e-9), int(0.12 * SR)), int(0.1 * SR))
    pres = np.clip(pres, 0, 1)

    # the music box and chips duck hardest: they live right in the speech band
    keys = st["box"] + st["chips"]
    rest = st["dry"] + st["wet"]
    inst = rest + keys
    mid = signal.sosfiltfilt(sos_bp(350, 5000), rest, axis=-1)
    full = ((rest - mid) * (1 - 0.2 * pres) + mid * (1 - 0.45 * pres)
            + keys * (1 - 0.6 * pres) + vox_all * db(4.0))
    # leave headroom in the intro so the drop at 0:06 lands harder
    t_ = np.arange(N) / SR
    arc = np.interp(t_, [0, 5.95, 6.0, 54.0, 54.05], [db(-4.5), db(-4.5), 1.0, 1.0, db(-1.5)])
    full, inst = full * arc, inst * arc
    pre = max(np.abs(full).max(), 1e-9)
    full_m = master(full / pre, args.drive)
    inst_m = master(inst / pre, args.drive)

    wav = args.build / "far-lands-feud.wav"
    sf.write(wav, full_m.T.astype(np.float32), SR, subtype="FLOAT")
    sf.write(args.build / "far-lands-feud-instrumental.wav", inst_m.T.astype(np.float32), SR, subtype="FLOAT")
    sf.write(args.build / "vocals-only.wav", (vox_all / pre).T.astype(np.float32), SR, subtype="FLOAT")
    for src, name in ((wav, "far-lands-feud.mp3"), (args.build / "far-lands-feud-instrumental.wav", "far-lands-feud-instrumental.mp3")):
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(src), "-c:a", "libmp3lame", "-b:a", "192k",
                        "-metadata", "title=Far Lands Feud", "-metadata", "artist=Claude vs ChatGPT (fan parody)",
                        str(MEDIA / name)], check=True)
    print("full mix:", loudness(wav))
    print("instrumental:", loudness(args.build / "far-lands-feud-instrumental.wav"))

    env_v, ref = {}, None
    for who in ("claude", "gpt", "narr"):
        env_v[who], _ = envelope(leads[who], ref=None)
    env = {
        "claude": b64(env_v["claude"]),
        "gpt": b64(env_v["gpt"]),
        "narr": b64(env_v["narr"]),
        "bass": b64(envelope(filt(sos_lp(160), low))[0]),
        "level": b64(envelope(full_m)[0]),
    }
    timeline = {
        "title": "Far Lands Feud",
        "bpm": BPM, "bar": BAR, "duration": DUR, "fps": FPS,
        "sections": [dict(id=s, t0=bar_t(a), t1=bar_t(b + 1), label=lab) for s, a, b, lab in SECTIONS],
        "lines": lines,
        "events": ev,
        "env": env,
    }
    tl = json.dumps(timeline, separators=(",", ":"), ensure_ascii=False).replace("</", "<\\/")
    (args.build / "timeline.json").write_text(tl)
    html = ROOT / "index.html"
    if html.exists():
        src = html.read_text()
        a, b = "<!--TIMELINE-->", "<!--/TIMELINE-->"
        if a in src and b in src:
            pre_, rest = src.split(a, 1)
            _, post = rest.split(b, 1)
            block = f'{a}<script id="timeline" type="application/json">{tl}</script>{b}'
            html.write_text(pre_ + block + post)
            print("timeline injected into index.html")
    print(f"done: {len(lines)} lines, {len(ev['kick'])} kicks, {len(ev['snare'])} snares")


if __name__ == "__main__":
    main()
