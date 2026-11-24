#!/bin/sh
set -eu
# The OpenIPC hook removes libstdc++ for non-vendor configs. Do not apply
# camera-specific overlay and flash scripts on a writable PC filesystem.
# Kernel /dev/video nodes are created by devtmpfs; no SoC vendor loader.
exit 0
