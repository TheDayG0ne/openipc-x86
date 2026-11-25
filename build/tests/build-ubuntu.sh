#!/usr/bin/env bash
# Isolated contract tests; fake Git and Docker, no build is run.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/openipc-x86-test.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT
fakebin="$test_root/bin"
mkdir -p "$fakebin" "$test_root/tmp" "$test_root/caller/build"
: >"$test_root/caller/build/Dockerfile"
export TEST_ROOT="$test_root" SOURCE_ROOT="$root" TMPDIR="$test_root/tmp"
export GIT_LOG="$test_root/git.log" DOCKER_LOG="$test_root/docker.log"
cat >"$fakebin/git" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%q ' "$@" >>"$GIT_LOG"; printf '\n' >>"$GIT_LOG"
dir=""
if [[ "$1" == -C ]]; then dir="$2"; shift 2; fi
case "$1" in
  rev-parse)
    [[ "$dir" == "$TEST_ROOT/caller" && "${FAKE_CHECKOUT:-0}" == 1 ]] || exit 1
    printf '%s\n' "$TEST_ROOT/caller" ;;
  clone)
    target="${@: -1}"
    mkdir -p "$target/build"
    cp "$SOURCE_ROOT/build/build-ubuntu.sh" "$target/build/build-ubuntu.sh"
    chmod +x "$target/build/build-ubuntu.sh"
    : >"$target/build/Dockerfile"
    printf '%s\n' "$target" >"$TEST_ROOT/clone-path" ;;
  checkout)
    [[ "$dir" == "$(cat "$TEST_ROOT/clone-path")" && "$2" == --detach && "$3" != -* ]]
    printf '%s\n' "$3" >"$TEST_ROOT/ref" ;;
  submodule) [[ "$dir" == "$(cat "$TEST_ROOT/clone-path")" ]] ;;
  *) exit 1 ;;
esac
EOF
cat >"$fakebin/docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%q ' "$@" >>"$DOCKER_LOG"; printf '\n' >>"$DOCKER_LOG"
case "$1" in
  info) ;;
  build)
    [[ "${@: -1}" == "$EXPECTED_REPO/build" ]]
    [[ "${FAIL_STAGE:-}" != build ]] || exit 31
    : >"$TEST_ROOT/image" ;;
  run)
    [[ "$4" == --volume && "$5" == "$EXPECTED_REPO:/repo:ro" ]]
    : >"$TEST_ROOT/container"
    [[ "${FAIL_STAGE:-}" != run ]] || exit 32 ;;
  cp)
    [[ "$2" == *:/work/output/images/* && "$3" == /* ]]
    [[ "${FAIL_STAGE:-}" != cp ]] || exit 33
    : >"$3" ;;
  rm) rm -f "$TEST_ROOT/container" ;;
  container) [[ "$2" == inspect && -f "$TEST_ROOT/container" ]] ;;
  image) [[ "$2" == inspect && -f "$TEST_ROOT/image" ]] ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$fakebin/git" "$fakebin/docker"
export PATH="$fakebin:$PATH" INSTALL_DOCKER=0 OPENIPC_X86_REF=
: >"$GIT_LOG"; : >"$DOCKER_LOG"
cd "$test_root/caller"
# The clone path is generated dynamically; Docker checks it against Git's record.
# Resolve it in the fake Docker process for clone cases.
export EXPECTED_REPO=CLONE
# Expand the sentinel at invocation time in the fake.
sed -i '/case "\$1" in/i [[ "$EXPECTED_REPO" != CLONE ]] || EXPECTED_REPO="$(cat "$TEST_ROOT/clone-path")"' "$fakebin/docker"
FAKE_CHECKOUT=1 "$root/build/build-ubuntu.sh" --ref review/ref --output "$test_root/out" >"$test_root/stdout"
[[ "$(cat "$test_root/ref")" == review/ref ]]
[[ ! -e "$(cat "$test_root/clone-path")" ]]
for f in bzImage rootfs.ext4 rootfs.squashfs; do [[ -f "$test_root/out/$f" ]]; done
grep -F -- "$test_root/out" "$test_root/stdout" >/dev/null
: >"$GIT_LOG"
EXPECTED_REPO="$test_root/caller" FAKE_CHECKOUT=1 "$root/build/build-ubuntu.sh" --output "$test_root/existing-out" >/dev/null
! grep -q 'clone' "$GIT_LOG"
if FAKE_CHECKOUT=1 "$root/build/build-ubuntu.sh" --ref -bad > /dev/null 2>&1; then exit 1; fi
if FAIL_STAGE=run FAKE_CHECKOUT=1 "$root/build/build-ubuntu.sh" --ref error/ref --output "$test_root/error-out" >"$test_root/error" 2>&1; then exit 1; fi
[[ ! -e "$(cat "$test_root/clone-path")" ]]
grep -q 'container: openipc-x86-' "$test_root/error"
grep -q 'image: openipc-x86-builder:' "$test_root/error"
echo 'build-ubuntu contract tests: ok'
