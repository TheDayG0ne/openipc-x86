#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
LAUNCHER="$ROOT/buildroot/package/divinus-multi/S95divinus-multi"
TMP=$(mktemp -d)
cleanup() {
    # The pid directory is private to this test; never search for or kill
    # processes outside the launcher pidfiles owned by this temporary run.
    if [ -f "$TMP/etc/divinus-multi.conf" ]; then
        FAKE_OUT="$TMP" DAEMON="$TMP/bin/divinus" TEMPLATE="$TMP/etc/divinus.yaml" \
            BASE="$TMP/base" PIDS="$TMP/pids" RUNTIME="$TMP/runtime" CONF="$TMP/etc/divinus-multi.conf" \
            "$LAUNCHER" stop >/dev/null 2>&1 || true
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/etc" "$TMP/dev" "$TMP/base" "$TMP/pids" "$TMP/runtime"

cat > "$TMP/bin/divinus" <<'EOF'
#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# Keep each invocation alive so start/stop exercise the pidfiles.  Copy the
# config next to this executable, rather than using one central template.
cp "$script_dir/divinus.yaml" "${FAKE_OUT:?}/config-${UVC_DEVICE##*/}-$$"
printf '%s\n' "$UVC_DEVICE" >> "$FAKE_OUT/devices"
# Make the pidfile point directly at the long-lived process, so stop does not
# leave a child process behind.
exec sleep 1000
EOF
chmod +x "$TMP/bin/divinus"
cp "$ROOT/sources/divinus/divinus.yaml" "$TMP/etc/divinus.yaml"
cat > "$TMP/etc/divinus-multi.conf" <<EOF
MULTI_CAMERAS=2
MULTI_DEVICE_1=/dev/null
MULTI_DEVICE_2=$TMP/dev/missing
MULTI_WEB_PORT=80
MULTI_RTSP_PORT_CENTRAL=554
MULTI_RTSP_PORT_1=555
MULTI_RTSP_PORT_2=556
EOF

run_launcher() {
    FAKE_OUT="$TMP" DAEMON="$TMP/bin/divinus" TEMPLATE="$TMP/etc/divinus.yaml" \
        BASE="$TMP/base" PIDS="$TMP/pids" RUNTIME="$TMP/runtime" CONF="$TMP/etc/divinus-multi.conf" \
        "$LAUNCHER" "$1"
}

# /dev/null is an existing character device, so this test needs no mknod or
# device privileges.  Camera 2 is deliberately absent.
run_launcher start

[ -s "$TMP/pids/central.pid" ]
[ -s "$TMP/pids/camera-1.pid" ]
[ ! -e "$TMP/pids/camera-2.pid" ]
[ -s "$TMP/base/central/divinus.yaml" ]
[ -s "$TMP/base/camera-1/divinus.yaml" ]
[ -s "$TMP/runtime/cameras.manifest" ]
grep -q '^slot=1 rtsp_port=555$' "$TMP/runtime/cameras.manifest"
grep -q '^slot=2 rtsp_port=556$' "$TMP/runtime/cameras.manifest"

# Check the generated YAML in each worker directory.  In particular, camera 1
# must not receive the central web/RTSP settings or lose unrelated YAML keys.
grep -q '^system:$' "$TMP/base/central/divinus.yaml"
grep -q '^  web_port: 80$' "$TMP/base/central/divinus.yaml"
grep -q '^rtsp:$' "$TMP/base/central/divinus.yaml"
grep -q '^  enable: false$' "$TMP/base/central/divinus.yaml"
grep -q '^  port: 554$' "$TMP/base/central/divinus.yaml"
grep -q '^system:$' "$TMP/base/camera-1/divinus.yaml"
grep -q '^  web_port: 0$' "$TMP/base/camera-1/divinus.yaml"
grep -q '^rtsp:$' "$TMP/base/camera-1/divinus.yaml"
grep -q '^  enable: true$' "$TMP/base/camera-1/divinus.yaml"
grep -q '^  port: 555$' "$TMP/base/camera-1/divinus.yaml"
grep -q '^  udp_srcport: 5600$' "$TMP/base/camera-1/divinus.yaml"
! grep -q '^  web_port: 80$' "$TMP/base/camera-1/divinus.yaml"
! grep -q '^  port: 554$' "$TMP/base/camera-1/divinus.yaml"

# stop must use the same private paths as start and remove only this run's
# pidfiles.  cleanup repeats this safely if the test exits early.
run_launcher stop
[ ! -e "$TMP/pids/central.pid" ]
[ ! -e "$TMP/pids/camera-1.pid" ]
[ ! -e "$TMP/runtime/cameras.manifest" ]
printf '%s\n' 'multi-camera launcher policy tests: PASS'
