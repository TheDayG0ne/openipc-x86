#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
LAUNCHER="$ROOT/buildroot/package/divinus-multi/S95divinus-multi"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/etc" "$TMP/dev" "$TMP/base" "$TMP/pids"

cat > "$TMP/bin/divinus" <<'EOF'
#!/bin/sh
printf '%s\n' "$UVC_DEVICE" > "${FAKE_OUT:?}/device"
cat "${FAKE_TEMPLATE:?}" > "$FAKE_OUT/config"
exit 0
EOF
chmod +x "$TMP/bin/divinus"
cp "$ROOT/sources/divinus/divinus.yaml" "$TMP/etc/divinus.yaml"
cat > "$TMP/etc/divinus-multi.conf" <<EOF
MULTI_CAMERAS=3
MULTI_DEVICE_1=$TMP/dev/missing
MULTI_DEVICE_2=$TMP/dev/also-missing
MULTI_DEVICE_3=$TMP/dev/never-started
MULTI_WEB_PORT_1=80
MULTI_WEB_PORT_2=81
MULTI_WEB_PORT_3=82
MULTI_RTSP_PORT_1=554
MULTI_RTSP_PORT_2=555
MULTI_RTSP_PORT_3=556
EOF

FAKE_OUT="$TMP" FAKE_TEMPLATE="$TMP/base/1/divinus.yaml" DAEMON="$TMP/bin/divinus" TEMPLATE="$TMP/etc/divinus.yaml" \
BASE="$TMP/base" PIDS="$TMP/pids" CONF="$TMP/etc/divinus-multi.conf" \
    "$LAUNCHER" start

[ -s "$TMP/pids/1.pid" ]
[ "$(cat "$TMP/device")" = /dev/null ]
grep -q '^  web_port: 80$' "$TMP/config"
grep -q '^  port: 554$' "$TMP/config"
grep -q '^  web_port: 81$' "$TMP/config" && exit 1 || :
# The unrelated YAML keys must remain unchanged.
grep -q '^  udp_srcport: 5600$' "$TMP/config"
[ ! -e "$TMP/pids/2.pid" ]
[ ! -e "$TMP/pids/3.pid" ]
printf '%s\n' 'multi-camera launcher tests: PASS'
