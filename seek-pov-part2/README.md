# Seek POV — Part 2: Don’t Look Back

Part 2 of the fan-made indie-horror anime short. Seek grabs Nagatoro and Senpai, drags them
down the hallway to the restroom and dumps Nagatoro in a toilet. Senpai breaks down crying, until
Gamo-chan and Sakura burst in with a phone flash and a mop. All seen first-person through the eye
of **Seek** from the Roblox horror game *DOORS*, ending down in the floor drain.

- `seek-pov-part2.mp4` — the finished 77 s video (1280×720, 24 fps, with sound)
- `index.html` — the scene. Open it in a browser to watch it render live (Three.js)
- `render.cjs` — renders `index.html` frame by frame in headless Chromium and encodes the MP4
- `make_audio.py` — synthesizes the soundtrack from `timeline.json` (standard library only)

Look: low-poly, flat-shaded characters rendered at 640×360 and upscaled with hard
pixels, sunset key light with shadows, fog, sunbeams and dust for the PS3-era feel.

## Rebuild

```sh
npm i three@0.170.0                                   # local copy for offline rendering
NODE_PATH=$(npm root -g):./node_modules node render.cjs --stills 0   # writes timeline.json
python3 make_audio.py                                 # -> seek-pov-part2-audio.wav
ffmpeg -i seek-pov-part2-audio.wav -c:a aac -b:a 128k seek-pov-part2-audio.m4a
NODE_PATH=$(npm root -g):./node_modules node render.cjs --audio seek-pov-part2-audio.wav
```

Nagatoro (*Don't Toy with Me, Miss Nagatoro*) and Seek (*DOORS*) belong to their
creators; this is a non-commercial fan work with all models, textures and sound made
from scratch.
