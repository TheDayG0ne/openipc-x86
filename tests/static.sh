#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh -n create.sh
# Reject invalid input before creating any output or invoking block tools.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
printf kernel > "$tmp/kernel"
printf invalid > "$tmp/root"
mkdir "$tmp/out"
if sh ./create.sh "$tmp/kernel" "$tmp/root" "$tmp/out" 2>/dev/null; then
    echo 'invalid squashfs was accepted' >&2
    exit 1
fi
[ -z "$(ls -A "$tmp/out")" ]
echo 'syntax and invalid-input rejection OK'
