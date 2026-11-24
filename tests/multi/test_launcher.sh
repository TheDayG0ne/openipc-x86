#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
LAUNCHER="$ROOT/buildroot/package/divinus-multi/S95divinus-multi"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/etc" "$TMP/dev" "$TMP/base" "$TMP/pids"

cat > "$TMP/bin/divinus" <<'EOF'
#!/bin/sh
printf '%s\n' "$UVC_DEVICE" >> "${FAKE_OUT:?}/devices"
cp "$(dirname "$0")/divinus.yaml" "$FAKE_OUT/config-${UVC_DEVICE##*/}"
exit 0
EOF
chmod +x "$TMP/bin/divinus"
cp "$ROOT/sources/divinus/divinus.yaml" "$TMP/etc/divinus.yaml"
cat > "$TMP/etc/divinus-multi.conf" <<EOF
MULTI_CAMERAS=2
MULTI_DEVICE_1=$TMP/dev/video1
MULTI_DEVICE_2=$TMP/dev/missing
MULTI_WEB_PORT=80
MULTI_RTSP_PORT_CENTRAL=554
MULTI_RTSP_PORT_1=555
MULTI_RTSP_PORT_2=556
EOF
# Only camera 1 is present; central must always start independently.
mknod "$TMP/dev/video1" c 81 1

FAKE_OUT="$TMP" FAKE_TEMPLATE="$TMP/base/central/divinus.yaml" DAEMON="$TMP/bin/divinus" TEMPLATE="$TMP/etc/divinus.yaml" \
    BASE="$TMP/base" PIDS="$TMP/pids" CONF="$TMP/etc/divinus-multi.conf" \
    "$LAUNCHER" start

[ -s "$TMP/pids/central.pid" ]
[ -s "$TMP/pids/camera-1.pid" ]
[ ! -e "$TMP/pids/camera-2.pid" ]
grep -q '^  web_port: 80$' "$TMP/config-null"
grep -q '^  port: 554$' "$TMP/config-null"
grep -q '^  web_port: 0$' "$TMP/config-video1"
grep -q '^  port: 555$' "$TMP/config-video1"
# The worker config must not accidentally rewrite unrelated YAML keys.
grep -q '^  udp_srcport: 5600$' "$TMP/config-video1"
"$LAUNCHER" stop
printf '%s\n' 'multi-camera launcher policy tests: PASS'
