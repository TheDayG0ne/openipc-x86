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
if [ "${DIVINUS_TEST_IGNORE_TERM:-0}" = 1 ]; then
    trap "" TERM
fi
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
# These must not switch lifecycle state or the lock after sourcing config.
PIDS=$TMP/other-pids
RUNTIME=$TMP/other-runtime
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
[ ! -e "$TMP/other-pids" ]
[ ! -e "$TMP/other-runtime" ]
# Missing config must not prevent stopping an existing run, but start/restart
# must fail rather than silently doing nothing.
run_launcher start
mv "$TMP/etc/divinus-multi.conf" "$TMP/etc/saved.conf"
run_launcher stop
[ ! -e "$TMP/pids/central.pid" ]
if run_launcher start; then echo 'missing config accepted' >&2; exit 1; fi
if run_launcher restart; then echo 'missing config accepted for restart' >&2; exit 1; fi
mv "$TMP/etc/saved.conf" "$TMP/etc/divinus-multi.conf"

# A live foreign PID with a stale start time must never receive a signal.
sleep 1000 &
foreign=$!
foreign_stat=$(cat "/proc/$foreign/stat"); foreign_stat=${foreign_stat##*) }; set -- $foreign_stat; shift 19
printf '%s %s central\n' "$foreign" "$1" > "$TMP/pids/central.pid"
run_launcher stop
kill -0 "$foreign"
kill "$foreign"
wait "$foreign" 2>/dev/null || true

# Refuse a second start, rather than claiming workers were reconciled.
run_launcher start
if run_launcher start; then echo 'second start unexpectedly succeeded' >&2; exit 1; fi
run_launcher stop

# Decimal normalization applies to both collision detection and output.
sed 's/MULTI_RTSP_PORT_1=555/MULTI_RTSP_PORT_1=00554/' "$TMP/etc/divinus-multi.conf" > "$TMP/etc/bad"
mv "$TMP/etc/bad" "$TMP/etc/divinus-multi.conf"
if run_launcher start; then echo 'duplicate port accepted' >&2; exit 1; fi
sed 's/MULTI_RTSP_PORT_1=00554/MULTI_RTSP_PORT_1=00555/' "$TMP/etc/divinus-multi.conf" > "$TMP/etc/good"
mv "$TMP/etc/good" "$TMP/etc/divinus-multi.conf"
run_launcher start
grep -q '^slot=1 rtsp_port=555$' "$TMP/runtime/cameras.manifest"
run_launcher stop

# A worker setup failure rolls back a previously started central process.
rm -rf "$TMP/base/camera-1"
ln -s "$TMP/dev" "$TMP/base/camera-1"
if run_launcher start; then echo 'rollback test unexpectedly succeeded' >&2; exit 1; fi
[ ! -e "$TMP/pids/central.pid" ]
[ ! -e "$TMP/runtime/cameras.manifest" ]
rm "$TMP/base/camera-1"

# A launcher-owned TERM-ignoring process forces a timeout. restart must not start a new run.
DIVINUS_TEST_IGNORE_TERM=1 run_launcher start
stubborn=$(cut -d' ' -f1 "$TMP/pids/central.pid")
sleep 1
if STOP_TIMEOUT=1 run_launcher restart; then kill -KILL "$stubborn"; echo 'restart unexpectedly succeeded' >&2; exit 1; fi
[ -f "$TMP/pids/central.pid" ]
kill -0 "$stubborn"
kill -KILL "$stubborn"
wait "$stubborn" 2>/dev/null || true
rm -f "$TMP/pids/central.pid" "$TMP/pids/camera-1.pid" "$TMP/runtime/cameras.manifest"
printf '%s\n' 'multi-camera launcher policy tests: PASS'
