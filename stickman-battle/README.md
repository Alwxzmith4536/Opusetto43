# Ash Planet Saber Battle

A procedurally animated stickman lightsaber duel: **green vs blue vs yellow**, a 1-vs-1-vs-1 on a ruined,
ash-covered planet, with a half-white / half-ash backdrop. No on-screen text. Yellow wins.

The video is drawn entirely in code (vector stickmen with Cairo, effects and post-processing with NumPy/Pillow,
a synthesized score and sound effects) and encoded with ffmpeg.

## Files

| file | purpose |
| --- | --- |
| `ash-planet-saber-battle.mp4` | the finished video (1920x1080, 60 fps, stereo audio) |
| `rig.py` | stickman skeleton, pose library, keyframe tracks |
| `scene.py` | fighters, camera, slow-motion time warp, events |
| `story.py` | the choreography (every beat of the fight) |
| `draw.py` | backdrop, stickmen, sabers, effects, bloom/grain/vignette post |
| `audio.py` | procedural score, saber hum, clashes, force pushes |
| `render.py` | frame renderer and ffmpeg pipe |
| `preview.py`, `sheet.py`, `smoke.py` | dev tools (pose sheet, contact sheet, crash smoke test) |

## Re-render

```bash
pip install numpy pillow pycairo
QUICK=1 python3 render.py video silent.mp4        # full 1080p, 60 fps (about 25 min on 4 cores)
python3 audio.py score.wav                        # soundtrack
ffmpeg -i silent.mp4 -i score.wav -c:v copy -c:a aac -b:a 192k -shortest ash-planet-saber-battle.mp4
```

`QUICK=0.5` renders at half resolution for fast previews, and `python3 sheet.py out.png 8.9 9.2 ...` makes a
contact sheet of stills at the given script times.
