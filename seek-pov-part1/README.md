# Seek POV — Part 1: A Basic Day

Fan-made indie-horror anime short. Nagatoro and Senpai have an ordinary after-school
moment in class 2-A, all of it seen first-person through the eye of **Seek** from the
Roblox horror game *DOORS*: ink dripping over the lens, eyes blooming on the walls, a
heavy wet walk down the hallway, and a lunge at the end.

- `seek-pov-part1.mp4` — the finished 72 s video (1280×720, 24 fps, with sound)
- `index.html` — the scene. Open it in a browser to watch it render live (Three.js)
- `render.cjs` — renders `index.html` frame by frame in headless Chromium and encodes the MP4
- `make_audio.py` — synthesizes the soundtrack from `timeline.json` (standard library only)

Look: low-poly, flat-shaded characters rendered at 640×360 and upscaled with hard
pixels, sunset key light with shadows, fog, sunbeams and dust for the PS3-era feel.

## Rebuild

```sh
npm i three@0.170.0                                   # local copy for offline rendering
NODE_PATH=$(npm root -g):./node_modules node render.cjs --stills 0   # writes timeline.json
python3 make_audio.py                                 # -> seek-pov-part1-audio.wav
ffmpeg -i seek-pov-part1-audio.wav -c:a aac -b:a 128k seek-pov-part1-audio.m4a
NODE_PATH=$(npm root -g):./node_modules node render.cjs --audio seek-pov-part1-audio.wav
```

Nagatoro (*Don't Toy with Me, Miss Nagatoro*) and Seek (*DOORS*) belong to their
creators; this is a non-commercial fan work with all models, textures and sound made
from scratch.
