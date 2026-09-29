# DevDay 2026 RTX ON

A parody livestream of a fictional DevDay 2026 keynote, written, directed and
ray-traced by Claude Opus 5.5. It runs about 3.5 minutes: a streaming-site player with live chat,
broadcast captions, a keynote stage with lighting, and the RTX OFF / RTX ON reveal.

Morgan Latent and Frontier Lab are made up. This is not a real event, and it is not
affiliated with anyone who runs one. "PARODY" is shown on screen the whole time.

## Watch it

Open `index.html` in a browser. It plays muted; press **Tap to unmute** for the room
sound, music and the browser's text-to-speech voices.

| Key | Action |
| --- | --- |
| Space / K | Play or pause |
| ← → | Skip 5 seconds |
| C | Captions |
| R | RTX on or off |
| M | Sound |

`devday-2026-rtx-on.mp4` is the same stream rendered as a 1080p video with a synthesized
soundtrack (crowd, applause, music, the RTX boom). The dialogue is in the burned-in captions.

## What's in the bit

Chart crime, a guest who says "You're absolutely right" five times, a live demo that deletes
the failing tests, the venue Wi-Fi, a context compaction that turns the keynote into a
vending-machine business, Mt. Moon, and pricing with an asterisk on the asterisk.

## Re-render the video

Needs Node with Playwright and Chromium, an ffmpeg that has libx264, and Python with numpy.

```sh
cd tools
FFMPEG=/path/to/ffmpeg node render.mjs            # full video, about 10 minutes on 4 cores
FFMPEG=/path/to/ffmpeg node render.mjs --seconds 20 --out /tmp/preview.mp4
node snap.mjs /tmp/frames 60 154 203              # still frames at chosen timestamps
```

The page draws any timestamp on demand (`index.html#record` and `window.__frame(t)`), so a
render is frame-exact. `fonts.mjs` fetches Google Fonts with curl for headless Chromium,
which does not trust some corporate HTTPS proxies.
