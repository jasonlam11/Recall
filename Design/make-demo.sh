#!/bin/bash
# Converts a screen recording into README-ready demo.gif.
#
#   ./Design/make-demo.sh ~/Desktop/recording.mov
#
# Two-pass palette generation, because a single-pass GIF of a mostly-cream UI
# bands badly. 12fps and 900px wide keeps a ~40s clip well under GitHub's 10MB
# inline limit while staying legible.
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 <recording.mov>"; exit 1; }
IN="$1"
cd "$(dirname "$0")/.."
OUT="demo.gif"
PALETTE=$(mktemp -d)/palette.png

FPS=12
WIDTH=900

ffmpeg -loglevel error -i "$IN" \
  -vf "fps=$FPS,scale=$WIDTH:-1:flags=lanczos,palettegen=stats_mode=diff" -y "$PALETTE"

ffmpeg -loglevel error -i "$IN" -i "$PALETTE" \
  -lavfi "fps=$FPS,scale=$WIDTH:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3" \
  -y "$OUT"

SIZE=$(du -m "$OUT" | cut -f1)
echo "wrote $OUT (${SIZE}MB, ${WIDTH}px, ${FPS}fps)"
if [ "$SIZE" -gt 9 ]; then
  echo "warning: over 9MB — GitHub may not render it inline."
  echo "  trim the clip, or rerun with FPS=10 / WIDTH=800 in this script."
fi
