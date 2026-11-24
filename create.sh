#!/bin/sh
# Create disk images only; never accept a disk device as a destination.
set -eu
export LC_ALL=C
[ "$#" -eq 3 ] || { echo "usage: $0 bzImage rootfs.squashfs output-directory" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || { echo 'run as root in a trusted Linux environment' >&2; exit 1; }
kernel=$(realpath -e -- "$1")
rootfs=$(realpath -e -- "$2")
out=$(realpath -e -- "$3")
[ -f "$kernel" ] && [ -f "$rootfs" ] && [ -d "$out" ] || { echo 'inputs must be regular files and output a directory' >&2; exit 1; }
[ "$(od -An -tx1 -N4 "$rootfs" | tr -d ' \n')" = 68737173 ] || { echo 'input is not a little-endian squashfs image' >&2; exit 1; }
[ ! -e "$out/openipc.raw" ] && [ ! -L "$out/openipc.raw" ] && [ ! -e "$out/openipc.vmdk" ] && [ ! -L "$out/openipc.vmdk" ] || { echo 'output already exists' >&2; exit 1; }
tmp=$(mktemp -d "$out/.disk-image-x86.XXXXXXXX")
loop=
boot_mounted=0
store_mounted=0
cleanup() {
    ok=1
    [ "$store_mounted" -eq 0 ] || umount "$tmp/store" || ok=0
    [ "$boot_mounted" -eq 0 ] || umount "$tmp/boot" || ok=0
    if [ "$ok" -eq 1 ] && [ -n "$loop" ]; then
        losetup -d "$loop" || ok=0
    fi
    if [ "$ok" -eq 1 ]; then
        rm -rf -- "$tmp"
    else
        echo "cleanup incomplete; inspect $tmp and $loop manually" >&2
    fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir "$tmp/boot" "$tmp/store"
# Unique MBR disk signature; reserve zero as an invalid ID.
sig=$(od -An -N4 -tx4 /dev/urandom | tr -d ' \n')
[ "$sig" != 00000000 ] || sig=00000001
root_bytes=$(stat -c %s "$rootfs")
# 1 MiB alignment; 128 MiB boot, rounded root, 512 MiB store.
root_mib=$(( (root_bytes + 1048575) / 1048576 ))
[ "$root_mib" -gt 0 ] || exit 1
root_start=129
store_start=$((root_start + root_mib))
total_mib=$((store_start + 512))
# MBR sector addressing is limited to 2 TiB.
[ "$total_mib" -lt 2097152 ] || { echo 'image too large for MBR' >&2; exit 1; }
truncate -s "${total_mib}M" "$tmp/disk.raw"
sfdisk "$tmp/disk.raw" <<EOF
label: dos
label-id: 0x$sig
unit: sectors

start=2048, size=262144, type=83, bootable
start=$((root_start * 2048)), size=$((root_mib * 2048)), type=83
start=$((store_start * 2048)), size=$((512 * 2048)), type=83
EOF
loop=$(losetup --find --show --partscan "$tmp/disk.raw")
# The loop belongs exclusively to the newly created file in our private directory.
for p in 1 2 3; do
    [ -b "${loop}p$p" ] || { echo "missing loop partition $p" >&2; exit 1; }
done
mkfs.ext4 -F -L OPENIPC_BOOT "${loop}p1"
mkfs.ext4 -F -L OPENIPC_STORE "${loop}p3"
dd if="$rootfs" of="${loop}p2" bs=4M conv=fsync status=none
mount -t ext4 "${loop}p1" "$tmp/boot"
boot_mounted=1
mount -t ext4 "${loop}p3" "$tmp/store"
store_mounted=1
printf '%s\n' overlay-x86-v1 > "$tmp/store/.overlay-x86-store"
cp -- "$kernel" "$tmp/boot/bzImage"
mkdir -p "$tmp/boot/grub"
cat > "$tmp/boot/grub/grub.cfg" <<EOF
set timeout=3
set default=0
menuentry 'OpenIPC x86 experimental' {
    linux /bzImage root=PARTUUID=$sig-02 rootfstype=squashfs ro overlay.x86=PARTUUID=$sig-03
}
EOF
grub-install --target=i386-pc --boot-directory="$tmp/boot" --modules='part_msdos ext2' --no-floppy "$loop"
sync
umount "$tmp/store"
store_mounted=0
umount "$tmp/boot"
boot_mounted=0
losetup -d "$loop"
loop=
qemu-img convert -f raw -O vmdk "$tmp/disk.raw" "$tmp/disk.vmdk"
# Hard links fail rather than overwrite, even if another process races us.
ln -- "$tmp/disk.raw" "$out/openipc.raw"
if ! ln -- "$tmp/disk.vmdk" "$out/openipc.vmdk"; then
    rm -- "$out/openipc.raw"
    exit 1
fi
printf 'Created %s/openipc.raw and openipc.vmdk (MBR ID %s)\n' "$out" "$sig"
