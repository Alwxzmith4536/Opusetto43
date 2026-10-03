# Horror Cube (Roblox Studio)

A cursed black cube floats near your spawn. **Click it** and the whole world turns into a blood‑red nightmare for everyone in the server.

## Setup (2 minutes)

1. **ServerScriptService** → **+** → **Script** → paste `HorrorCube.server.lua`
2. **StarterPlayer → StarterPlayerScripts** → **+** → **LocalScript** → paste `HorrorClient.client.lua`
3. Press **Play** and click the cube.

You don't need to place a cube. The script creates one 22 studs in front of your SpawnLocation.
If you want to use your own part instead, name it `HorrorCube` and put it in Workspace.

## What happens when you click

**World (everyone sees it, done by the server script)**
- The sun sinks to midnight and thick red fog fills the sky. The stars go out and the moon grows bigger.
- A wave of blood spreads out from the cube and stains every part. Plastic turns to concrete, grass to mud and metal to rust.
- Terrain gets darker and the water turns to blood.
- Every light in the map turns red and flickers. New red lights and blood pools appear around the map.
- Color grading makes the colors look drained and tinted red, with bloom and a blurred distance.
- The cube itself catches red hellfire, trembles and beats like a heart.

**Each player (done by the client script)**
- Intro: the screen glitches, you hear a scream, the camera shakes, and the text *"YOU SHOULDN'T HAVE TOUCHED IT"* is typed out. Then the **Watcher jumpscare** hits.
- A heartbeat plays and gets faster the closer you are to the cube. A red vignette pulses with it.
- Ash and embers fall, a VHS tracking line rolls down the screen, the camera sways slowly, and sounds echo like in a cave.
- Random scares every 10–22 seconds:
  - The **Watcher** stands in the fog. It disappears when you look straight at it.
  - Red lightning and thunder.
  - A whisper right behind your back.
  - Words that flash on screen for a split second.
  - A blackout where something is standing in front of you.

## Settings

Each script starts with a `CONFIG` table. The most useful options:

| Setting | Script | What it does |
|---|---|---|
| `AllowRevert` | server | `true` = click the cube again to bring the normal world back (handy for testing) |
| `CubePosition` | server | `Vector3.new(x, y, z)` to place the cube yourself |
| `WaveSpeed`, `BloodColor`, `BloodStrength` | server | How fast the blood spreads and how red everything gets |
| `RedLights`, `BloodPools` | server | How many extra lights and puddles appear |
| `Jumpscare`, `ShadowFigure` | client | Turn the Watcher off if you want it less intense |
| `RandomEventMin/Max` | client | How often the random scares happen |
| `IntroText`, `Whispers` | client | Your own creepy messages |

**Protect something from the blood:** add the tag `HorrorIgnore` to a part or model (Properties → Tags).

## Sounds

The scripts work with **zero setup** by using built‑in Roblox sounds that are slowed down and distorted into rumbles, thumps and groans.
For a much scarier result, paste real horror audio IDs into `SOUND_IDS` at the top of the client script. You can find them in Creator Store → Audio by searching "horror drone", "heartbeat", "scream", "whisper" or "thunder":

```lua
local SOUND_IDS = {
	Drone = "rbxassetid://YOUR_ID",
	Heartbeat = "rbxassetid://YOUR_ID",
	...
}
```
