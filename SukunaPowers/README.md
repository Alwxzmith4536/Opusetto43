# Sukuna Powers (Roblox, R15)

Click the floating **red cube** (Sukuna's finger). It plays a cinematic transformation and gives you Ryomen Sukuna's techniques from *Jujutsu Kaisen*. Each technique has its own R15 animation, VFX, sounds and a camera cut-scene for the caster.

## Open it in Roblox Studio

1. Download **`build/SukunaPowers.rbxlx`**.
2. Double-click it, or use **Roblox Studio → File → Open from File…**
3. Press **Play** (F5). Walk through the torii gate to the red cube and click it.

Three R15 "Cursed Spirit" training dummies spawn behind the cube so you can test the moves. They respawn after they die.

## Controls

| Input | Technique |
|---|---|
| Left click | **Combo** (拳): jab → hook → uppercut → roundhouse kick |
| `Z` | **Dismantle** (解): three flying crescent slashes that scar the ground |
| `X` | **Cleave** (捌): dash in, then rapid cuts whose damage scales with the target's max health |
| `C` | **Fuga** (開): a flame forms in the palm, Sukuna draws a fire bow and the arrow explodes |
| `V` | **Domain Expansion: Malevolent Shrine** (伏魔御厨子): hand sign, the shrine rises, the sky turns red and sure-hit slashes fill the area |
| `G` | **World Cutting Slash** (世界を断つ斬撃): a chant, then a slash that splits space |

Gamepad: R2 / X / Y / B / D-pad Up / D-pad Down. On mobile, tap the buttons on the HUD bar.

## What's inside

- **R15 animation engine (`PoseAnimator`)**: keyframed poses applied to the R15 `Motor6D` joints with easing, blending, crouch solving (knees and hips bend while the feet stay planted, using each avatar's real leg lengths) and a cursed-energy tremble. The player's normal R15 idle and walk animations keep running underneath, so moves blend in and out smoothly. You don't need to upload any animations. Every client animates every character, so all players see the moves.
- **Cinematics**: scripted camera shots, letterbox bars, kanji title cards, chant captions, impact frames, colour grading, screen flashes and camera shake.
- **Transformation**: the cube's energy arcs into you, you clutch your head and struggle, then a cursed-energy shockwave cracks the ground. Sukuna's markings appear: the cheek lines, a second pair of eyes, glowing red eyes, forehead marks, black arm bands and chest lines. You also get a red-black aura, 300 HP and more speed.
- **VFX**: curved beam crescents, razor cut lines, ground scars, craters, flying rock debris, shockwave rings and spheres, lightning, fire, smoke, blood mist, afterimages and highlights.
- **Malevolent Shrine**: about 370 parts built in code. It has a stone base, red lacquer pillars, a glowing fanged maw, two tiers of temple roofs, horns, lanterns, a nameplate, and skulls and bones on a pool of blood.
- **Server-authoritative**: the server checks every request and handles cooldowns, hitboxes, damage, stuns, knockback and kill credit (`creator` tag). Clients only handle visuals.

## Customising

Everything is in `ReplicatedStorage.SukunaShared.Config`:

- damage, ranges, cooldowns and key bindings (`Config.Abilities`)
- the move timeline shared by server and client (`Config.Timing`)
- `DamagePlayers` (PvP on or off), `Cinematics`, `FaceMarkings`, `BodyMarkings`, `KeepPowersOnRespawn`, and the dummy settings
- `Config.Sounds`: these default to sounds built into the Roblox client (`rbxasset://`). Swap in your own `rbxassetid://…` sounds for stronger audio.
- `Config.CustomAnimations`: if you upload your own R15 animations, paste their IDs here and they replace the procedural animation for that move.

## Project layout (Rojo)

```
SukunaPowers/
├─ default.project.json          Rojo project (map, lighting, scripts)
├─ build/SukunaPowers.rbxlx      ready-to-open Studio place
└─ src/
   ├─ server/SukunaServer.server.luau     ServerScriptService
   ├─ client/SukunaClient.client.luau     StarterPlayerScripts
   └─ shared/                              ReplicatedStorage.SukunaShared
      ├─ Config.luau        balance / timing / sounds
      ├─ PoseAnimator.luau  R15 procedural animation engine
      ├─ Moves.luau         keyframed poses for every technique
      ├─ Effects.luau       client presentation of each technique
      ├─ VFX.luau           effect builders
      ├─ Cinematics.luau    camera cut-scenes, titles, shake, grading
      ├─ Shrine.luau        Malevolent Shrine builder
      └─ Sounds.luau        sound helper
```

To rebuild the place after editing the scripts, run `rojo build default.project.json -o build/SukunaPowers.rbxlx`. You can also use `rojo serve` to live-sync into Studio.

## Notes

- The place is set to **R15** avatars. If you copy the scripts into another game, set *Game Settings → Avatar → R15*.
- To move the scripts into an existing place, copy `SukunaShared` into ReplicatedStorage, `SukunaServer` into ServerScriptService and `SukunaClient` into StarterPlayerScripts, then add a part named `SukunaCube` to Workspace.
