#!/usr/bin/env bash
# Build OpenIPC x86 on Ubuntu Server 24.04 using the repository's Docker pipeline.
set -Eeuo pipefail

readonly REPO_URL="https://github.com/TheDayG0ne/openipc-x86.git"
readonly SCRIPT_NAME="build-ubuntu.sh"
readonly ARTIFACTS=(bzImage rootfs.ext4 rootfs.squashfs)
JOBS="${JOBS:-2}"
REF="${OPENIPC_X86_REF:-master}"
REF_REQUESTED=0
[[ -n "${OPENIPC_X86_REF:-}" ]] && REF_REQUESTED=1
OUTPUT_ROOT=""
INSTALL_DOCKER="${INSTALL_DOCKER:-0}"
SELF_REEXEC="${OPENIPC_X86_REEXEC:-0}"
CALLER_DIR="$PWD"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
clone_dir=""
repo_root=""
container=""
image=""
container_created=0
image_created=0
clone_created=0
output=""
output_parent=""
staging=""

usage() {
    cat <<'EOF'
Usage:
  ./build/build-ubuntu.sh [--ref REF] [--jobs N] [--output DIR]

The helper builds an exact checkout. Outside a checkout it creates a disposable
clone, selects REF, and runs the script from that clone. Output must be a new
directory outside every checkout. Docker installation is never implicit: set
INSTALL_DOCKER=1 to explicitly allow apt installation.
EOF
}

while (($#)); do
    case "$1" in
        --ref)
            (($# >= 2)) || { echo "--ref requires REF" >&2; exit 2; }
            REF="$2"; REF_REQUESTED=1; shift 2 ;;
        --jobs)
            (($# >= 2)) || { echo "--jobs requires N" >&2; exit 2; }
            JOBS="$2"; shift 2 ;;
        --output)
            (($# >= 2)) || { echo "--output requires DIR" >&2; exit 2; }
            OUTPUT_ROOT="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$JOBS" in ''|*[!0-9]*) echo "--jobs must be a non-negative integer" >&2; exit 2 ;; esac
[[ -n "$REF" && "$REF" != -* ]] || { echo "REF must be non-empty and must not begin with '-'" >&2; exit 2; }

absolute_output() {
    local requested="$1" parent name
    [[ -n "$requested" ]] || return 1
    if [[ "$requested" == */ ]]; then requested="${requested%/}"; fi
    [[ -n "$requested" ]] || requested="/"
    parent="$(dirname -- "$requested")"
    name="$(basename -- "$requested")"
    mkdir -p -- "$parent"
    parent="$(cd -- "$parent" && pwd -P)"
    [[ "$name" != . && "$name" != .. && -n "$name" ]] || return 1
    printf '%s\n' "$parent/$name"
}

cleanup_clone() {
    if [[ "$clone_created" == 1 && -n "$clone_dir" && -d "$clone_dir" ]]; then
        rm -rf -- "$clone_dir"
    fi
}

cleanup_staging() {
    # The exact path is safer than a wildcard; -L also handles a replaced
    # staging entry without following a symlink.
    if [[ -n "$staging" && ( -e "$staging" || -L "$staging" ) ]]; then
        rm -rf -- "$staging"
    fi
}

# A requested ref is never resolved from the caller's checkout. Resolve the
# checkout first, then derive all build paths from that exact checkout/script.
if [[ "$SELF_REEXEC" != 1 ]]; then
    if git -C "$CALLER_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
        candidate_root="$(git -C "$CALLER_DIR" rev-parse --show-toplevel)"
        [[ -f "$candidate_root/build/Dockerfile" ]] && repo_root="$(cd -- "$candidate_root" && pwd -P)"
    fi
    if [[ "$REF_REQUESTED" == 1 || -z "$repo_root" ]]; then
        clone_dir="$(mktemp -d "${TMPDIR:-/tmp}/openipc-x86.XXXXXX")"
        clone_created=1
        trap 'status=$?; cleanup_clone; exit "$status"' EXIT
        git clone --no-checkout -- "$REPO_URL" "$clone_dir"
        git -C "$clone_dir" checkout --detach "$REF"
        git -C "$clone_dir" submodule update --init --recursive
        repo_root="$clone_dir"
    fi
else
    # This process is run by the parent after it has selected the clone. Its
    # script location, not the caller's PWD, is the authoritative checkout.
    repo_root="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
fi

if [[ -n "$OUTPUT_ROOT" ]]; then
    requested_output="$OUTPUT_ROOT"
else
    requested_output="$(dirname -- "$repo_root")/openipc-x86-artifacts-$(cat /proc/sys/kernel/random/uuid | tr -d '-')"
fi
output="$(absolute_output "$requested_output")" || { echo "Invalid output directory" >&2; exit 2; }

[[ "$output" != *:* ]] || { echo "Output path must not contain ':' (Docker copy syntax)" >&2; exit 2; }
[[ "$repo_root" != *:* && "$repo_root" != *,* ]] || { echo "Checkout path must not contain ':' or ',' (Docker mount syntax)" >&2; exit 2; }

if [[ "$clone_created" == 1 ]]; then
    clone_real="$(cd -- "$clone_dir" && pwd -P)"
    [[ "$output" != "$clone_real"/* && "$output" != "$clone_real" ]] || {
        echo "Output directory must be outside the temporary clone: $output" >&2; exit 2;
    }
fi

if [[ "$clone_created" == 1 ]]; then
    trap 'status=$?; cleanup_clone; exit "$status"' EXIT
    forwarded=(--jobs "$JOBS" --output "$output")
    set +e
    OPENIPC_X86_REEXEC=1 OPENIPC_X86_REF= "$repo_root/build/$SCRIPT_NAME" "${forwarded[@]}"
    status=$?
    set -e
    exit "$status"
fi

if [[ "$INSTALL_DOCKER" == 1 ]]; then
    command -v sudo >/dev/null || { echo "sudo is required for opt-in Docker installation" >&2; exit 1; }
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends docker.io
    sudo systemctl enable --now docker
fi
command -v docker >/dev/null || { echo "Docker is required. Re-run with INSTALL_DOCKER=1 to opt in to installation." >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required for Linux no-replace publication" >&2; exit 1; }
[[ "$(uname -s)" == Linux ]] || { echo "atomic no-replace publication requires Linux" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker is unavailable for this user. Start Docker deliberately; docker access is root-equivalent." >&2; exit 1; }

id="$(cat /proc/sys/kernel/random/uuid | tr -d '-')"
container="openipc-x86-$id"
image="openipc-x86-builder:$id"
output_parent="$(dirname -- "$output")"
[[ ! -e "$output" && ! -L "$output" ]] || { echo "Output already exists: $output" >&2; exit 2; }
[[ "$output" != "$repo_root"/* && "$output" != "$repo_root" ]] || { echo "Output must be outside the checkout" >&2; exit 2; }
if git -C "$output_parent" rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "Output must be outside any checkout: $output" >&2; exit 2
fi
staging="$(mktemp -d "$output_parent/.openipc-x86-staging.XXXXXX")"
trap 'status=$?; cleanup_staging; exit "$status"' EXIT

on_error() {
    status=$?
    echo "Build failed (exit $status). Resources retained for diagnosis:" >&2
    if docker container inspect "$container" >/dev/null 2>&1; then echo "  container: $container" >&2; else echo "  container: not found (or Docker unavailable)" >&2; fi
    if docker image inspect "$image" >/dev/null 2>&1; then echo "  image: $image" >&2; else echo "  image: not found (or Docker unavailable)" >&2; fi
    echo "  output: $output" >&2
    exit "$status"
}
trap on_error ERR

docker build --tag "$image" "$repo_root/build"
image_created=1
docker run --name "$container" --volume "$repo_root:/repo:ro" --env "JOBS=$JOBS" "$image"
container_created=1
for artifact in "${ARTIFACTS[@]}"; do
    docker cp "$container:/work/output/images/$artifact" "$staging/$artifact"
    [[ -f "$staging/$artifact" ]] || { echo "Docker cp did not create expected artifact: $staging/$artifact" >&2; exit 1; }
done
python3 "$SCRIPT_DIR/publish-noreplace.py" "$staging" "$output"
[[ ! -e "$staging" && ! -L "$staging" ]] || { echo "Atomic publication did not consume staging: $staging" >&2; exit 1; }
staging=""
docker rm "$container" >/dev/null
container_created=0
trap - ERR
printf 'Artifacts: %s (%s)\n' "$output" "${ARTIFACTS[*]}"
printf 'Builder image retained: %s\n' "$image"
