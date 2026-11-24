#!/bin/sh
# Run only in an isolated privileged Linux VM/container with loop support.
set -eu
. "${1:-./overlay/usr/libexec/overlay-x86}"
t=$(mktemp -d)
l1= l2=
cleanup() {
    [ -z "$l2" ] || losetup -d "$l2"
    [ -z "$l1" ] || losetup -d "$l1"
    rm -rf "$t"
}
trap cleanup EXIT
truncate -s 16M "$t/disk"
printf '\170\126\064\022' | dd of="$t/disk" bs=1 seek=440 conv=notrunc status=none
printf '\000\000\002\000\203\377\377\377\000\010\000\000\000\100\000\000' | dd of="$t/disk" bs=1 seek=446 conv=notrunc status=none
printf '\125\252' | dd of="$t/disk" bs=1 seek=510 conv=notrunc status=none
l1=$(losetup --find --show --partscan "$t/disk")
[ -b "${l1}p1" ] || { echo 'loop partition device unavailable; devtmpfs with partition nodes required' >&2; exit 1; }
[ "$(ovl_resolve_partuuid 12345678-01)" = "${l1}p1" ]
if ovl_resolve_partuuid 12345678-02; then exit 1; fi
cp "$t/disk" "$t/clone"
l2=$(losetup --find --show --partscan "$t/clone")
[ -b "${l2}p1" ]
if ovl_resolve_partuuid 12345678-01; then echo 'duplicate accepted' >&2; exit 1; fi
echo 'virtual PARTUUID tests passed'
