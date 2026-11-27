#!/bin/sh
# Run an OpenIPC x86 VM with a real L2 bridge. This intentionally does not use
# QEMU user-mode NAT and does not add host port forwards: the guest must obtain
# its address from the physical LAN's DHCP server.
set -eu

[ "$#" -eq 4 ] || {
    echo "usage: $0 BRIDGE bzImage rootfs.squashfs overlay.ext4" >&2
    exit 2
}

bridge=$1
kernel=$(realpath -e -- "$2")
rootfs=$(realpath -e -- "$3")
overlay=$(realpath -e -- "$4")

case "$bridge" in
    ''|*[!A-Za-z0-9_.-]*) echo 'invalid bridge name' >&2; exit 2;;
esac
[ -f "$kernel" ] && [ -f "$rootfs" ] && [ -f "$overlay" ] || {
    echo 'kernel, squashfs and overlay must be regular files' >&2
    exit 1
}

command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo 'qemu-system-x86_64 is required' >&2
    exit 1
}
ip link show "$bridge" >/dev/null 2>&1 || {
    echo "bridge does not exist: $bridge" >&2
    exit 1
}

exec qemu-system-x86_64 \
    -machine accel=kvm:tcg \
    -m 1024 \
    -smp 2 \
    -nographic \
    -no-reboot \
    -kernel "$kernel" \
    -drive "file=$rootfs,format=raw,if=virtio,readonly=on" \
    -drive "file=$overlay,format=raw,if=virtio" \
    -netdev "bridge,id=lan0,br=$bridge" \
    -device e1000,netdev=lan0 \
    -append 'console=ttyS0 root=/dev/vda rootfstype=squashfs ro init=/init rootwait overlay.x86=/dev/vdb'
