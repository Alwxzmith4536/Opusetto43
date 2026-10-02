#!/usr/bin/env bash
# Rebuilds ashfall.mp4 from source: renders every frame in headless Chromium (4 workers),
# synthesises the soundtrack, and muxes them with ffmpeg.
# Needs: node (with playwright + chromium), ffmpeg.  Usage: ./build.sh [workdir]
set -euo pipefail
cd "$(dirname "$0")"
WORK="${1:-/tmp/ashfall-build}"; mkdir -p "$WORK/frames"; rm -f "$WORK"/frames/*.jpg
NF=$(node -e "global.window=undefined;for(const f of ['core.js','poses.js','sim.js','story.js'])require('./'+f);console.log(Math.floor(SIM.warp.s2o(SIM.total)*30))")
echo "frames: $NF"
Q=$(( (NF + 3) / 4 ))
for k in 0 1 2 3; do
  a=$(( k * Q )); b=$(( (k + 1) * Q )); [ $b -gt $NF ] && b=$NF
  node render_frames.js "$WORK/frames" $a $b 1.5 0.94 > "$WORK/render_$k.log" 2>&1 &
done
wait
node audio.js "$WORK/ashfall.wav"
ffmpeg -hide_banner -loglevel error -y -framerate 30 -i "$WORK/frames/f%05d.jpg" -i "$WORK/ashfall.wav" \
  -vf "format=yuv420p" \
  -af "acompressor=threshold=-21dB:ratio=3:attack=8:release=160:makeup=3,loudnorm=I=-15:TP=-1.5:LRA=12" \
  -c:v libx264 -preset slow -crf 22 -profile:v high -pix_fmt yuv420p -c:a aac -b:a 192k -ar 44100 -shortest -movflags +faststart ashfall.mp4
echo "wrote $(pwd)/ashfall.mp4"
