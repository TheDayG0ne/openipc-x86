#!/bin/sh
set -eu
: "${DIVINUS:=/input/divinus}"
OUT=${OUT:-/tmp/divinus-test}
mkdir -p "$OUT"
gcc -shared -fPIC -O2 -Wall -Wextra -o "$OUT/fake-v4l2.so" /test/fake-v4l2.c -ldl
cp /test/divinus.yaml "$OUT/divinus.yaml"
cd "$OUT"
export UVC_DEVICE=/tmp/divinus-fake-video
LD_PRELOAD="$OUT/fake-v4l2.so" "$DIVINUS" >divinus.log 2>&1 &
pid=$!
cleanup() { kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
sleep 5
kill -0 "$pid" || { cat divinus.log; exit 1; }
grep -q 'fixture: STREAMON' divinus.log || { cat divinus.log; exit 1; }
timeout 35 ffmpeg -hide_banner -loglevel warning -rtsp_transport tcp -i rtsp://127.0.0.1:18554/ -t 3 -an -c:v rawvideo -pix_fmt gray -f framemd5 frames.md5 >ffmpeg.log 2>&1 || { cat ffmpeg.log; cat divinus.log; exit 1; }
python3 - <<'PY'
from pathlib import Path
lines = [line for line in Path('frames.md5').read_text().splitlines() if line and not line.startswith('#')]
hashes = [line.split(',')[-1].strip() for line in lines]
assert len(hashes) >= 10, f'only {len(hashes)} decoded frames'
assert len(set(hashes)) >= 3, 'frames do not change'
print(f'PASS: decoded {len(hashes)} RTSP frames, {len(set(hashes))} unique')
PY
