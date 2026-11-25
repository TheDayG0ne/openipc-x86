#!/usr/bin/env bash
# Isolated contract tests for build/build-ubuntu.sh. No Docker build is run.
set -Eeuo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/openipc-x86-test.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT
fakebin="$test_root/bin"
mkdir -p "$fakebin"
cat >"$fakebin/git" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'git %q\n' "$*" >>"$GIT_LOG"
if [[ "$1" == -C ]]; then
  dir=$2; shift 2
else
  dir=""
fi
case "${1:-}" in
  rev-parse)
    [[ "${FAKE_CHECKOUT:-0}" == 1 ]] || exit 1
    printf '%s\n' "$FAKE_ROOT"
    ;;
  clone)
    target="${@: -1}"
    mkdir -p "$target/build"
    : >"$target/build/Dockerfile"
    ;;
  checkout|submodule) ;;
  *) echo "unexpected git operation" >&2; exit 1 ;;
esac
EOF
cat >"$fakebin/docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'docker %q\n' "$*" >>"$DOCKER_LOG"
case "$1" in
  info|build|run|rm) exit 0 ;;
  cp) mkdir -p "${@: -1}"; : >"${@: -1}/$(basename "${2:-artifact}")" ;;
  *) echo "unexpected docker operation" >&2; exit 1 ;;
esac
EOF
chmod 0755 "$fakebin/git" "$fakebin/docker"

run() {
  env PATH="$fakebin:$PATH" GIT_LOG="$GIT_LOG" DOCKER_LOG="$DOCKER_LOG" \
    INSTALL_DOCKER=0 OPENIPC_X86_REF= "$root/build/build-ubuntu.sh" "$@" >/dev/null
}

GIT_LOG="$test_root/git.log" DOCKER_LOG="$test_root/docker.log"; : >"$GIT_LOG"; : >"$DOCKER_LOG"
# Outside a checkout: clone without checkout, then select the requested ref and init submodules.
run --ref review/ref
 grep -q 'git clone --no-checkout' "$GIT_LOG"
grep -q 'checkout --detach review/ref' "$GIT_LOG"
grep -q 'submodule update --init --recursive' "$GIT_LOG"

# Inside a checkout: use it as-is; a --ref request must not silently mutate it.
existing="$test_root/existing"
mkdir -p "$existing/build"
: >"$existing/build/Dockerfile"
: >"$GIT_LOG"; : >"$DOCKER_LOG"
env PATH="$fakebin:$PATH" GIT_LOG="$GIT_LOG" DOCKER_LOG="$DOCKER_LOG" FAKE_CHECKOUT=1 FAKE_ROOT="$existing" \
  INSTALL_DOCKER=0 "$root/build/build-ubuntu.sh" >/dev/null
grep -q 'rev-parse' "$GIT_LOG"
! grep -qE 'clone|checkout|submodule' "$GIT_LOG"

env PATH="$fakebin:$PATH" GIT_LOG="$GIT_LOG" DOCKER_LOG="$DOCKER_LOG" FAKE_CHECKOUT=1 FAKE_ROOT="$existing" \
  INSTALL_DOCKER=0 "$root/build/build-ubuntu.sh" --ref other/ref >/dev/null
 grep -q 'git clone --no-checkout' "$GIT_LOG"

echo 'build-ubuntu contract tests: ok'
