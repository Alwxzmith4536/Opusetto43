#!/usr/bin/env python3
"""Check that the lyrics survive the mix: transcribe every bar with Whisper and score it.

Usage: python3 check_vocals.py --whisper DIR mix.wav [more.wav ...]
DIR holds sherpa-onnx's Whisper export (base.en-encoder.int8.onnx, base.en-decoder.int8.onnx,
base.en-tokens.txt), from the sherpa-onnx asr-models release.
"""
import argparse
import re
from pathlib import Path

import numpy as np
import sherpa_onnx
import soundfile as sf
from scipy import signal

from build_track import LYRICS, bar_t


def words(s):
    s = s.lower().replace("chatgpt", "chat gpt").replace("a.i.", "ai")
    return re.sub(r"[^a-z0-9' ]", " ", s).split()


def wer(ref, hyp):
    r, h = words(ref), words(hyp)
    d = np.zeros((len(r) + 1, len(h) + 1), int)
    d[:, 0], d[0, :] = range(len(r) + 1), range(len(h) + 1)
    for i in range(1, len(r) + 1):
        for j in range(1, len(h) + 1):
            d[i, j] = min(d[i - 1, j] + 1, d[i, j - 1] + 1, d[i - 1, j - 1] + (r[i - 1] != h[j - 1]))
    return d[-1, -1] / max(1, len(r))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--whisper", type=Path, required=True)
    ap.add_argument("wavs", nargs="+", type=Path)
    args = ap.parse_args()
    m = args.whisper / "base.en-"
    rec = sherpa_onnx.OfflineRecognizer.from_whisper(
        encoder=f"{m}encoder.int8.onnx", decoder=f"{m}decoder.int8.onnx", tokens=f"{m}tokens.txt",
        language="en", task="transcribe", num_threads=4)
    for path in args.wavs:
        x, sr = sf.read(path)
        x = x.mean(axis=1) if x.ndim == 2 else x
        x16 = signal.resample_poly(x, 16000, sr).astype(np.float32)
        scores = []
        print(f"== {path.name}")
        for bar, who, say, _ in LYRICS:
            a, b = int(bar_t(bar) * 16000), int((bar_t(bar) + 3.0) * 16000)
            seg = x16[a:b] / (np.abs(x16[a:b]).max() + 1e-9) * 0.9
            s = rec.create_stream()
            s.accept_waveform(16000, seg)
            rec.decode_stream(s)
            hyp = s.result.text.strip()
            scores.append(wer(say, hyp))
            print(f"{bar:2d} {who:6s} WER {scores[-1]:4.2f} | {hyp}")
        print(f"mean WER {np.mean(scores):.2f}")


if __name__ == "__main__":
    main()
