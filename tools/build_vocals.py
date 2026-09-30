"""Render the Token Arena vocals with Kokoro TTS and embed them in rap-battle.html.

The page plays these clips through Web Audio, so vocals work in browsers and
app views that have no speech-synthesis voices.

Setup (once):
    pip install kokoro-onnx soundfile imageio-ffmpeg
    B=https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0
    curl -L -o kokoro.onnx $B/kokoro-v1.0.int8.onnx
    curl -L -o voices.bin  $B/voices-v1.0.bin

Run:
    python3 tools/build_vocals.py --model kokoro.onnx --voices voices.bin
"""
import argparse, base64, json, os, re, subprocess, tempfile

import imageio_ffmpeg
import numpy as np
import soundfile as sf
from kokoro_onnx import Kokoro

HTML = os.path.join(os.path.dirname(__file__), '..', 'rap-battle.html')
VOICE = {'claude': ('af_heart', 1.12), 'gpt': ('af_bella', 1.15), 'host': ('am_michael', 1.05)}
WIN_LINES = {
    'claude': 'The crowd has spoken! Claude takes the belt!',
    'gpt': 'The crowd has spoken! GPT takes the belt!',
}
START, END = '<script id="vocals" type="application/json">', '</script>'


def spoken(text):
    # TTS reads the typographic apostrophe fine, but normalise it anyway
    return text.replace('’', "'")


def trim(audio, sr, thresh=0.01, pad=0.04):
    idx = np.where(np.abs(audio) > thresh)[0]
    if not len(idx):
        return audio
    a, b = max(0, idx[0] - int(pad * sr)), min(len(audio), idx[-1] + int(pad * sr))
    return audio[a:b]


def to_mp3(audio, sr):
    with tempfile.TemporaryDirectory() as d:
        wav, mp3 = os.path.join(d, 'a.wav'), os.path.join(d, 'a.mp3')
        sf.write(wav, audio, sr)
        subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-loglevel', 'error', '-y', '-i', wav,
                        '-ac', '1', '-ar', '24000', '-b:a', '48k', mp3], check=True)
        return open(mp3, 'rb').read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--model', default='kokoro.onnx')
    ap.add_argument('--voices', default='voices.bin')
    args = ap.parse_args()

    html = open(HTML, encoding='utf-8').read()
    lines = re.findall(r"who: '(\w+)'[^\n]*?text: '([^']*)'", html)
    k = Kokoro(args.model, args.voices)

    def render(who, text):
        voice, speed = VOICE[who]
        audio, sr = k.create(spoken(text), voice=voice, speed=speed, lang='en-us')
        audio = trim(audio, sr)
        return to_mp3(audio, sr), len(audio) / sr

    clips, total = [], 0.0
    for who, text in lines:
        data, dur = render(who, text)
        total += dur
        clips.append(base64.b64encode(data).decode())
        print(f'{dur:5.2f}s  {who:6}  {text}')
    win = {w: base64.b64encode(render('host', t)[0]).decode() for w, t in WIN_LINES.items()}
    print(f'{len(clips)} clips, {total:.1f}s of vocals')

    payload = json.dumps({'voices': {w: v[0] for w, v in VOICE.items()}, 'clips': clips, 'win': win})
    block = START + payload + END
    if START in html:
        a = html.index(START)
        b = html.index(END, a) + len(END)
        html = html[:a] + block + html[b:]
    else:
        html = html.rstrip() + '\n' + block + '\n'
    open(HTML, 'w', encoding='utf-8').write(html)


if __name__ == '__main__':
    main()
