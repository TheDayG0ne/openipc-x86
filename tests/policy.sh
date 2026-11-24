#!/bin/sh
set -eu
. "${1:-./overlay/usr/libexec/overlay-x86}"
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
# Only temporary directories; no mount, device, filesystem or reset commands.
if ovl_prepare "$t"; then fail 'unprovisioned accepted'; fi
printf '%s\n' overlay-x86-v1 > "$t/.overlay-x86-store"
ovl_prepare "$t" || fail 'valid store rejected'
touch "$t/upper/settings" "$t/.reset"
ovl_prepare "$t" || fail 'reset failed'
[ ! -e "$t/upper/settings" ] && [ ! -e "$t/.reset" ] || fail 'reset incomplete'
rm -rf "$t/upper"
ln -s / "$t/upper"
if ovl_prepare "$t"; then fail 'symlink upper accepted'; fi
rm "$t/upper"
mkdir "$t/upper"
rm -f "$t/.overlay-x86-store"
ln -s /dev/null "$t/.overlay-x86-store"
if ovl_prepare "$t"; then fail 'symlink marker accepted'; fi
rm "$t/.overlay-x86-store"
printf '%s\n' wrong > "$t/.overlay-x86-store"
if ovl_prepare "$t"; then fail 'wrong marker accepted'; fi
echo 'policy tests passed'
