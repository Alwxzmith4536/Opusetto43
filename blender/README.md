# Saitama vs Cosmic Garou: 5-minute Blender fight animation

A fan-made, fully procedural 3D fight animation. It runs 5:00 (7200 frames at 24 fps), is set in an endless white void, and ends with Saitama winning by **speedblitz**.

| File | What it is |
|---|---|
| `saitama_vs_cosmic_garou.blend` | Ready-to-open Blender scene with everything already animated |
| `saitama_vs_cosmic_garou.py` | The generator script that builds the whole scene from scratch |
| `web/` | Browser player: the same scene in real-time 3D (three.js), with a phone 9:16 mode |
| `export_web.py` | Re-exports the .blend into `web/scene.json` + `web/scene.bin.txt` |
| `trailer.html` | 44-second 2D vertical trailer |

## Open it

1. Download `saitama_vs_cosmic_garou.blend` and open it in **Blender 4.2 or newer** (tested on 4.2 LTS and 5.0).
2. Press **Space** to play in the viewport. For faster playback, switch the viewport to Solid shading.
3. To make the movie, use **Render → Render Animation** (Ctrl+F12). It writes an H.264 MP4 to `render/` next to the .blend, at 1920×1080 and 24 fps.

Keep the render engine on **EEVEE**. The cel shading uses *Shader to RGB*, which only works in EEVEE.
Rendering speed tips: lower *Render Properties → Sampling → Render* samples (32 by default), or turn off
*Freestyle* (the black ink outlines), or render at 50% resolution.

## Watch it in the browser (3D)

`web/index.html` loads the exported scene and plays all 5 minutes in real-time WebGL. It uses the same meshes, rig, keyframes (Bezier handles included), camera cuts and effects as the .blend. Serve the `web/` folder over http(s), for example with `python3 -m http.server` inside `web/`. After changing the .blend, re-export with:

```
blender --background saitama_vs_cosmic_garou.blend --python export_web.py
```

## Rebuild or tweak it

```
blender --background --python saitama_vs_cosmic_garou.py
```

Or open the script in Blender's **Scripting** tab and press **Run Script**. It clears the current scene first.
Everything lives in plain Python: the poses (`POSES`), character designs (`build_saitama`, `build_garou`),
effects (`FX`) and the fight itself (`choreograph`). Change a number, rerun, and you get a new cut in about 10 seconds.

## Timeline

| Time | Scene |
|---|---|
| 0:00 | Standoff in the white void. Garou's cosmic halo ignites while Saitama picks his nose |
| 0:16 | Round 1: Garou's Water Stream martial-arts flurry. Saitama dodges everything, blocks with one hand, then ends the round with a slap that sends Garou flying 20 m |
| 1:10 | Cosmic barrage: Garou fires ~30 energy orbs from the sky while Saitama strolls forward slapping them away. He punches the giant orb into orbit |
| 1:50 | Sky battle: mid-air shockwave clashes that finish with a fist-to-fist collision |
| 2:30 | Portal assault: Garou warps around Saitama, gets his fist caught and is thrown into the ground |
| 3:05 | Gamma Ray Burst fired from orbit. Saitama scratches his head in the smoke |
| 3:35 | Desperation flurry. Saitama doesn't flinch, then his eyebrows go **serious** |
| 3:55 | **SPEEDBLITZ**: 18 ground hits, an uppercut and a 16-hit aerial juggle, with afterimages everywhere, then the hammer blow into a 9 m crater |
| 4:25 | Aftermath: Garou's halo shatters and his cosmic glow fades. Saitama walks away, fade to white |

## What's inside the scene

- **Rigged characters.** Each fighter has a 17-bone armature, so you can grab any bone and re-pose it. Saitama's cape is a deforming mesh driven by 3 cape bones, with flutter baked from his speed.
- **Cosmic Garou.** His body uses a procedural nebula and star-field shader. He also has a spinning halo, orbiting star particles, glowing eyes and white spiked hair. His glow strength is animated through the `Glow` node in the `G_Cosmic` material.
- **Effects.** Shockwave rings, impact bursts, energy orbs, the Gamma Ray beam, portals, smoke, flying rocks, craters and cracks, speed lines, camera shake, and anime black "impact frames".
- **Camera.** One animated camera with many shot cuts. It is parented as `CamRig → CamShake → Camera` and aims at `CamTarget`.
- **Look.** A white background, two-tone cel shading and Freestyle ink outlines.

Fan work. *One-Punch Man* and its characters belong to ONE and Yusuke Murata.
