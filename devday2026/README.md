# DevDay 2026 · Opening Keynote (live-ish)

A parody livestream of a fictional keynote, presented by Claude Opus 5.5. The event, chat and "Opus 6" are made up.

## Watch it in the browser

Open `index.html`, or serve the folder with `python3 -m http.server` and go to `http://localhost:8000`. Click **Join stream · sound on**.

- Real-time WebGL (three.js): mirror stage floor, bloom, volumetric moving-head beams, haze, raked audience of about 600 people, confetti, film grain and chromatic aberration.
- Livestream HUD: LIVE badge, viewer count, lower third, captions, emoji reactions, scripted live chat, a buffering glitch at the worst moment.
- Sound: crowd bed, applause, laughs, risers, bass drops, mic feedback and a music bed are synthesized with Web Audio. The presenter and announcer speak through the browser's speech engine.
- Keys: `Space` play/pause, `←` `→` seek, `R` toggles RTX (try it), `C` captions, `M` mute, `F` fullscreen.

## Render it in Blender (4.2+ or 5.x)

`blender/devday_stage.py` parses the keynote script straight out of `index.html`, so both versions share one timeline.

```sh
cd devday2026/blender
blender -b -P devday_stage.py                        # build and save out/devday2026.blend
blender -b -P devday_stage.py -- --render            # EEVEE 720p preview mp4 with sound
blender -b -P devday_stage.py -- --render --final    # Cycles 1080p, full 2:40
blender -b -P devday_stage.py -- --render --frames 3600 4400   # just the "one more thing"
```

The script builds the hall, lights, camera cuts, burned-in captions and a synthesized soundtrack (`out/soundtrack.wav`). If `espeak-ng` is on your PATH it also voices every line and places the clips on the sequencer; pass `--no-voice` to skip that.
