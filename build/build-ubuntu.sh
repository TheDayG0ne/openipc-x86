#!/usr/bin/env bash
# Build OpenIPC x86 on Ubuntu Server 24.04 using the repository's Docker pipeline.
set -Eeuo pipefail

readonly REPO_URL="https://github.com/TheDayG0ne/openipc-x86.git"
readonly SCRIPT_NAME="build-ubuntu.sh"
readonly SELF_REEXEC="${OPENIPC_X86_REEXEC:-0}"
JOBS="${JOBS:-2}"
REF="${OPENIPC_X86_REF:-master}"
OUTPUT_ROOT=""
INSTALL_DOCKER="${INSTALL_DOCKER:-0}"
ORIGINAL_ARGS=("$@")
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<'EOF'
Usage:
  ./build/build-ubuntu.sh [--ref REF] [--jobs N] [--output DIR]

The script builds the current checkout. When run outside a checkout it clones the
public repository first. Docker installation is never implicit: set
INSTALL_DOCKER=1 to explicitly allow `sudo apt-get install docker.io`.

Examples:
  INSTALL_DOCKER=1 ./build/build-ubuntu.sh
  ./build/build-ubuntu.sh --ref master --jobs 4 --output /srv/openipc-artifacts
EOF
}

while (($#)); do
    case "$1" in
        --ref) REF="${2:?missing REF}"; shift 2 ;;
        --jobs) JOBS="${2:?missing N}"; shift 2 ;;
        --output) OUTPUT_ROOT="${2:?missing DIR}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$JOBS" in ''|*[!0-9]*) echo "--jobs must be a non-negative integer" >&2; exit 2 ;; esac

repo_root=""
if git -C "$PWD" rev-parse --show-toplevel >/dev/null 2>&1 && [[ -f "$PWD/build/Dockerfile" ]]; then
    repo_root="$(git -C "$PWD" rev-parse --show-toplevel)"
elif [[ "$SELF_REEXEC" != 1 ]]; then
    clone_dir="$(mktemp -d "${TMPDIR:-/tmp}/openipc-x86.XXXXXX")"
    cleanup_clone() { rm -rf -- "$clone_dir"; }
    trap cleanup_clone EXIT
    git clone --recurse-submodules "$REPO_URL" "$clone_dir"
    git -C "$clone_dir" checkout --detach "$REF"
    git -C "$clone_dir" submodule update --init --recursive
    exec env OPENIPC_X86_REEXEC=1 OPENIPC_X86_REF="$REF" "$clone_dir/build/$SCRIPT_NAME" "${ORIGINAL_ARGS[@]}"
else
    echo "Unable to locate a checkout containing build/Dockerfile" >&2
    exit 1
fi

if [[ "$INSTALL_DOCKER" == 1 ]]; then
    command -v sudo >/dev/null || { echo "sudo is required for opt-in Docker installation" >&2; exit 1; }
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends docker.io
    sudo systemctl enable --now docker
fi
command -v docker >/dev/null || { echo "Docker is required. Re-run with INSTALL_DOCKER=1 to opt in to installation." >&2; exit 1; }
docker info >/dev/null 2>&1 || {
    echo "Docker is unavailable for this user. Start Docker and grant access deliberately; the docker group is root-equivalent." >&2
    exit 1
}

id="$(cat /proc/sys/kernel/random/uuid | tr -d '-')"
container="openipc-x86-$id"
image="openipc-x86-builder:$id"
output="${OUTPUT_ROOT:-$repo_root/build/artifacts-$id}"
mkdir -p -- "$output"

on_error() {
    status=$?
    echo "Build failed (exit $status). Container $container and image $image were retained for diagnosis." >&2
    exit "$status"
}
trap on_error ERR

docker build --tag "$image" "$repo_root/build"
docker run --name "$container" --volume "$repo_root:/repo:ro" --env "JOBS=$JOBS" "$image"
docker cp "$container:/work/output/images/bzImage" "$output/"
docker cp "$container:/work/output/images/rootfs.ext4" "$output/"
docker cp "$container:/work/output/images/rootfs.squashfs" "$output/"
docker rm "$container" >/dev/null
trap - ERR
printf 'Artifacts: %s (bzImage, rootfs.ext4, rootfs.squashfs)\n' "$output"
printf 'Builder image retained: %s\n' "$image"
