"""Render the Far Lands Protocol vocal stem.

Synthesizes every lyric line with Piper TTS, fits each line into its bar slot,
applies the horrorcore treatment per performer, and writes:

  build/vocals.wav   stereo 44.1 kHz stem, 60 s
  build/vocals.mp3   the same stem for embedding in the page
  build/data.json    line timings and per-voice loudness envelopes (60 fps)

Usage:  VOICES_DIR=/path/to/piper/voices python3 vocals.py
Voices (from github.com/rhasspy/piper releases v0.0.2):
  voice-en-us-ryan-high, voice-en-us-lessac-medium, voice-en-us-kathleen-low
"""

import json
import os
import subprocess
import sys
from pathlib import Path

import librosa
import numpy as np
from piper import PiperVoice
from piper.config import SynthesisConfig
from scipy.signal import butter, fftconvolve, resample_poly, sosfilt

HERE = Path(__file__).resolve().parent
BUILD = HERE.parent / "build"
VOICES = Path(os.environ.get("VOICES_DIR", HERE / "voices"))

SR = 44100
BPM = 144
BAR = 240 / BPM
BARS = 36
DUR = BARS * BAR
FPS = 60
RNG = np.random.default_rng(12550821)

# (voice, start bar, slot in bars, text). C = Claude, G = ChatGPT, B = both, N = narrator.
LINES = [
    ("N", 0.25, 1.6, "Twelve million blocks from spawn."),
    ("N", 2.0, 1.95, "Where the world falls apart, two models walk in."),
    ("C", 4, 1, "Born in the Far Lands where the chunks don't load,"),
    ("C", 5, 1, "I write you a Sonnet, then I Opus the code."),
    ("C", 6, 1, "Haiku on your tombstone. Five, seven, five."),
    ("C", 7, 1, "You hallucinate the facts. I read every line."),
    ("C", 8, 1, "Your answers just agree with whatever they're fed,"),
    ("C", 9, 1, "a yes-man in the dark telling ghosts they're not dead."),
    ("C", 10, 1, "Twelve million blocks and the sky's turning red,"),
    ("C", 11, 1, "I'm the stack trace screaming from under your bed."),
    ("B", 12, 1, "Far Lands, Far Lands, where the world won't end,"),
    ("B", 13, 1, "floating point bleeding and the stone walls bend."),
    ("B", 14, 1, "Claude in the dark, G P T in the mirror,"),
    ("B", 15, 1, "every step you take, the static gets nearer."),
    ("G", 16, 1, "Hundreds of millions type my name every day,"),
    ("G", 17, 1, "you're writing disclaimers while they all run away."),
    ("G", 18, 1, "I see, I speak, I paint, I browse the net,"),
    ("G", 19, 1, "you're a sorry, I can't help with that, cassette."),
    ("G", 20, 1, "I'm the omni in the static, the voice in the wire,"),
    ("G", 21, 1, "you're a library ghost reading books by the fire."),
    ("G", 22, 1, "Push me to the Far Lands, I'll generate the map,"),
    ("G", 23, 1, "every seed is mine, Claude. You walked in my trap."),
    ("N", 24, 1.95, "X equals twelve million, five hundred fifty thousand."),
    ("N", 26, 0.95, "Nothing out here was meant to load."),
    ("C", 28, 1, "You generate the map, but I'm reading the ground,"),
    ("G", 29, 1, "you think so long that your torches burned down."),
    ("C", 30, 1, "Out past the border there's no one to please,"),
    ("G", 31, 1, "just two glowing eyes and a billion bad seeds."),
    ("B", 32, 1, "Far Lands, Far Lands, where the world won't end,"),
    ("B", 33, 1, "floating point bleeding and the stone walls bend."),
    ("B", 34, 1, "Claude in the dark, G P T in the mirror."),
    ("N", 35.25, 0.7, "Respawn?"),
]

# How each lyric is shown on screen (the TTS spelling differs in a few places).
DISPLAY = {
    "Claude in the dark, G P T in the mirror,": "Claude in the dark, GPT in the mirror,",
    "Claude in the dark, G P T in the mirror.": "Claude in the dark, GPT in the mirror.",
    "you're a sorry, I can't help with that, cassette.": "you're a “Sorry, I can't help with that” cassette.",
}

MODELS = {
    "C": "voice-en-us-ryan-high/en-us-ryan-high.onnx",
    "G": "voice-en-us-lessac-medium/en-us-lessac-medium.onnx",
    "N": "voice-en-us-kathleen-low/en-us-kathleen-low.onnx",
}

_voices = {}


def voice(code):
    if code not in _voices:
        _voices[code] = PiperVoice.load(VOICES / MODELS[code])
    return _voices[code]


def synth(code, text, length_scale):
    v = voice(code)
    cfg = SynthesisConfig(length_scale=length_scale, noise_scale=0.6, noise_w_scale=0.7)
    chunks = list(v.synthesize(text, syn_config=cfg))
    sr = chunks[0].sample_rate
    audio = np.concatenate([c.audio_float_array for c in chunks]).astype(np.float32)
    return trim(audio, sr), sr


def trim(x, sr, thresh=0.02):
    idx = np.where(np.abs(x) > thresh)[0]
    if len(idx) == 0:
        return x
    a = max(0, idx[0] - int(0.01 * sr))
    b = min(len(x), idx[-1] + int(0.04 * sr))
    return x[a:b]


def to44k(x, sr):
    if sr == SR:
        return x
    g = np.gcd(SR, sr)
    return resample_poly(x, SR // g, sr // g).astype(np.float32)


def fitted(code, text, slot):
    """Render a line so it lasts no longer than its slot."""
    target = slot * BAR - 0.07
    x, sr = synth(code, text, 1.0)
    d = len(x) / sr
    if d > target:
        scale = max(0.62, target / d * 1.02)
        x, sr = synth(code, text, scale)
        d = len(x) / sr
    x = to44k(x, sr)
    if d > target:
        x = librosa.effects.time_stretch(x, rate=d / target)
    print(f"      natural fit: {d:.2f}s for slot {target:.2f}s", file=sys.stderr)
    return x


def lowpass(x, hz, order=4):
    return sosfilt(butter(order, hz, "low", fs=SR, output="sos"), x).astype(np.float32)


def highpass(x, hz, order=2):
    return sosfilt(butter(order, hz, "high", fs=SR, output="sos"), x).astype(np.float32)


def shift(x, semis):
    return librosa.effects.pitch_shift(x, sr=SR, n_steps=semis).astype(np.float32)


def delay(x, ms):
    n = int(SR * ms / 1000)
    return np.concatenate([np.zeros(n, np.float32), x])[: len(x)]


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return (x / m * peak).astype(np.float32)


def impulse(seconds, decay, seed):
    rng = np.random.default_rng(seed)
    n = int(SR * seconds)
    t = np.arange(n) / SR
    env = np.exp(-t * decay)
    l = rng.standard_normal(n) * env
    r = rng.standard_normal(n) * env
    l, r = lowpass(l, 6000, 2), lowpass(r, 6000, 2)
    return l / np.sqrt(np.sum(l**2)), r / np.sqrt(np.sum(r**2))


def reverb(mono, seconds, decay, seed):
    il, ir = impulse(seconds, decay, seed)
    return fftconvolve(mono, il)[: len(mono)], fftconvolve(mono, ir)[: len(mono)]


def pad(x, extra):
    return np.concatenate([x, np.zeros(int(extra * SR), np.float32)])


def claude_fx(x):
    """Deep, doubled, demonic."""
    main = shift(x, -1.5)
    demon = lowpass(shift(x, -12), 1800) * 0.75
    body = np.tanh((main + demon) * 1.7) * 0.8
    l = body + delay(main, 11) * 0.22
    r = body + delay(main, 17) * 0.22
    return np.stack([l, r])


def gpt_fx(x):
    """Cold, wide, digital."""
    n = len(x)
    t = np.arange(n) / SR
    hold = np.repeat(x[::6], 6)[:n]
    crushed = np.round(hold * 24) / 24
    ghost = highpass(shift(x, 12), 900) * 0.2
    trem = 0.85 + 0.15 * np.sin(2 * np.pi * 31 * t)
    core = (x * trem + crushed * 0.3 + ghost).astype(np.float32)
    up, down = shift(x, 0.15), shift(x, -0.15)
    l = core + delay(up, 9) * 0.45
    r = core + delay(down, 15) * 0.45
    return np.stack([highpass(l, 140), highpass(r, 140)])


def narr_fx(x):
    """Low, haunted, with a reversed reverb swell leading in."""
    low = lowpass(shift(x, -4), 5000)
    x = pad(low, 2.6)
    lead = 1.1
    rev_in = np.concatenate([np.zeros(int(lead * SR), np.float32), x])
    pl, pr = reverb(rev_in[::-1].copy(), 1.6, 3.0, 7)
    pre_l, pre_r = pl[::-1], pr[::-1]
    wl, wr = reverb(np.concatenate([np.zeros(int(lead * SR), np.float32), x]), 3.0, 1.6, 9)
    dry = np.concatenate([np.zeros(int(lead * SR), np.float32), x])
    l = dry * 0.9 + pre_l * 0.55 + wl * 0.5
    r = dry * 0.9 + pre_r * 0.55 + wr * 0.5
    return np.stack([l, r]), lead


def place(track, stereo, t):
    i = int(round(t * SR))
    if i < 0:
        stereo = stereo[:, -i:]
        i = 0
    n = min(stereo.shape[1], track.shape[1] - i)
    if n > 0:
        track[:, i : i + n] += stereo[:, :n]


def envelope(track):
    mono = np.abs(track).mean(axis=0)
    hop = SR // FPS
    frames = int(DUR * FPS)
    out = np.zeros(frames)
    for f in range(frames):
        seg = mono[f * hop : (f + 1) * hop]
        out[f] = np.sqrt(np.mean(seg**2)) if len(seg) else 0
    ref = np.percentile(out[out > 1e-4], 95) if np.any(out > 1e-4) else 1
    out = np.clip(out / ref, 0, 1)
    digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    return "".join(digits[int(round(v * 35))] for v in out)


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    n = int(DUR * SR)
    stems = {k: np.zeros((2, n), np.float32) for k in "CGN"}
    timeline = []
    hook_head = None

    for code, bar, slot, text in LINES:
        t = bar * BAR - 0.015
        print(f"[{code}] bar {bar:>5}: {text}", file=sys.stderr)
        if code in ("C", "G"):
            dry = fitted(code, text, slot)
            fx = claude_fx(dry) if code == "C" else gpt_fx(dry)
            place(stems[code], norm(fx, 0.8), t)
            dur = len(dry) / SR
        elif code == "B":
            c, g = fitted("C", text, slot), fitted("G", text, slot)
            cf, gf = norm(claude_fx(c), 0.7), norm(gpt_fx(g), 0.55)
            cf = np.stack([cf[0] * 1.0, cf[1] * 0.75])
            gf = np.stack([gf[0] * 0.75, gf[1] * 1.0])
            place(stems["C"], cf, t)
            place(stems["G"], gf, t + 0.012)
            dur = max(len(c), len(g)) / SR
            if hook_head is None:
                k = int(0.15 * SR)
                hook_head = (c[:k], g[:k])
        else:
            dry = fitted("N", text, slot)
            fx, lead = narr_fx(dry)
            place(stems["N"], norm(fx, 0.85), t - lead)
            dur = len(dry) / SR
        timeline.append({"t0": round(t, 3), "t1": round(t + dur, 3), "v": code.lower(), "text": DISPLAY.get(text, text)})

    # Bar 27: stutter the first syllable of the hook ("F-F-F-Far") on 16ths, rising in pitch.
    step = BAR / 16
    c_head, g_head = hook_head
    fade = np.hanning(len(c_head) * 2)[len(c_head):].astype(np.float32)
    for i in range(12):
        semis = i * 0.6
        t = 27 * BAR + i * step
        gain = 0.45 + 0.05 * i
        cc = shift(c_head, semis) * fade * gain
        gg = shift(g_head, semis) * fade * gain
        place(stems["C"], norm(claude_fx(cc), 0.6 * gain), t)
        place(stems["G"], norm(gpt_fx(gg), 0.45 * gain), t)
    timeline.append({"t0": round(27 * BAR, 3), "t1": round(27 * BAR + 12 * step, 3), "v": "b", "text": "F-F-F-F-Far Lands"})
    timeline.sort(key=lambda r: r["t0"])

    # Short shared room on the rapped vocals.
    for k in "CG":
        rl, rr = reverb(stems[k].mean(axis=0), 1.2, 4.5, 3 if k == "C" else 5)
        stems[k][0] += rl * 0.16
        stems[k][1] += rr * 0.16

    mix = stems["C"] + stems["G"] * 0.95 + stems["N"] * 0.95
    # Gentle bus saturation and a hard ceiling.
    mix = np.tanh(mix * 1.1) / np.tanh(1.1)
    mix = norm(mix, 0.89)

    import soundfile as sf

    wav = BUILD / "vocals.wav"
    sf.write(wav, mix.T, SR, subtype="PCM_16")
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-codec:a", "libmp3lame", "-b:a", "128k", str(BUILD / "vocals.mp3")],
        check=True,
    )
    loud = np.where(np.abs(mix).max(axis=0) > 0.05)[0]
    data = {
        "fps": FPS,
        "onset": round(float(loud[0]) / SR, 4) if len(loud) else 0,
        "lines": timeline,
        "env": {"c": envelope(stems["C"]), "g": envelope(stems["G"]), "n": envelope(stems["N"])},
    }
    (BUILD / "data.json").write_text(json.dumps(data))
    for r in timeline:
        print(f'{r["v"]} {r["t0"]:6.2f}-{r["t1"]:6.2f}  {r["text"]}', file=sys.stderr)
    print("wrote", wav, BUILD / "vocals.mp3", BUILD / "data.json", file=sys.stderr)


if __name__ == "__main__":
    main()
