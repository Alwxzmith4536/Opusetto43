# ASHFALL — Green vs Blue vs Yellow (stickman saber duel)

`ashfall.mp4` — 70 s, 1920×1080, 30 fps. A three-way stickman lightsaber battle on a ruined, ash-covered planet.
Yellow wins against both opponents. Pale white sky over a dark ash plain (the "half white" background),
cinematic letterbox, slow-mo, hit-stop, impact frames, motion blur.

Everything is generated from code — no assets:

| file | what it does |
| --- | --- |
| `core.js` | stickman skeleton, two-bone IK, keyframe tracks, time-warp (slow-mo / hit-stop) |
| `poses.js` | pose library (guards, strikes, blocks, kicks, force push, flips…) |
| `sim.js` | blade-lock solver, facing, gait, scarf physics, camera, shake, event list |
| `story.js` | the choreography: every fighter move, camera shot, effect and title |
| `render.js` | canvas renderer: environment, fighters, sabers, sparks, ash, post |
| `audio.js` | synthesised score + sound effects driven by the same events |
| `render_frames.js`, `build.sh` | headless-Chromium frame renderer and the full pipeline |
| `still.js`, `posesheet.js` | dev tools for contact sheets |

Rebuild: `./build.sh` (needs node + playwright/chromium + ffmpeg).
