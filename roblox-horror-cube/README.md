# Horror Cube (Roblox Studio)

A white cube. Click it and the whole world turns into horrorcore / redcore.

## Install

1. Open Roblox Studio and start from the **Baseplate** template (any place works).
2. **ServerScriptService** → `+` → **Script** → name it `HorrorCube` → paste `HorrorCube.server.lua`.
3. **StarterPlayer → StarterPlayerScripts** → `+` → **LocalScript** → name it `HorrorClient` → paste `HorrorClient.client.lua`.
4. Press **Play** (F5), walk up to the cube and click it.

`HorrorCube` works on its own; `HorrorClient` adds camera shake, blood rain, vignette, heartbeat and scare text.

## What happens on click

1. Blackout: the lights die and the cube convulses, lit only by red flashes.
2. Slam: crimson sky, fog, bloom and a red colour-grade fade in.
3. The corruption spreads outward from the cube: parts bleed to rotten red, lights turn red and flicker, and terrain and water turn to blood.
4. The cube becomes a levitating, throbbing, bleeding heart with a watching eye above it.
5. Client side: blood rain (stops indoors), embers, a heartbeat-pulsing vignette, glitching scare text and a jumpscare every minute or so.

## Customise

Everything lives in the `CONFIG` table at the top of each script.

- **Audio**: the defaults are a built-in Roblox sound pitched down. Put your own Creator Store IDs (`rbxassetid://...`) in `Sounds` (server) and `HeartbeatSoundId` / `JumpscareSoundId` (client).
- **Jumpscare image**: set `JumpscareImageId` in the client script.
- **Protect something**: give any part or model the attribute `HorrorIgnore = true` and it won't be recoloured.
- **Cube location, size, timings, walk speed**: top of `HorrorCube.server.lua`.
