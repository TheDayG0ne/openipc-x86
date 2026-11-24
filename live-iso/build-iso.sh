#!/bin/bash
# Run on an isolated Debian bookworm build VM, never on the source rootfs.
set -euo pipefail
umask 077
[ "$#" = 2 ] || { echo "Usage: sudo $0 ROOTFS_DIR OUTPUT.iso" >&2; exit 2; }
[ "$(id -u)" = 0 ] || exit 1
src=$(realpath -e -- "$1")
out=$(realpath -m -- "$2")
[ -d "$src/etc" ] && [ -f "$src/etc/shadow" ] && [ "$src" != / ] || { echo 'Invalid rootfs' >&2; exit 1; }
[ ! -e "$out" ] || { echo 'Output already exists' >&2; exit 1; }
case "$out/" in "$src/"*) echo 'Output inside rootfs' >&2; exit 1;; esac
here=$(cd -- "$(dirname -- "$0")" && pwd)
tmp=$(mktemp -d)
cleanup() { rm -rf -- "$tmp"; }
trap cleanup EXIT
mkdir -p "$tmp/root" "$tmp/iso/live" "$tmp/iso/boot/grub"
rsync -aHAX --numeric-ids --one-file-system "$src/" "$tmp/root/"
r="$tmp/root"
# A rootfs is trusted executable input, but credentials and machine identity must not be cloned.
for f in etc/passwd etc/shadow etc/group; do test -f "$r/$f" && test ! -L "$r/$f"; done
awk -F: 'BEGIN{OFS=FS} { $2="!"; print }' "$r/etc/shadow" > "$tmp/shadow"
install -m 600 "$tmp/shadow" "$r/etc/shadow"
rm -rf -- "$r/etc/openipc" "$r/var/lib/systemd/random-seed"
rm -f -- "$r/etc/ssh/ssh_host_"* "$r/etc/machine-id"
: > "$r/etc/machine-id"
mkdir -p "$r/etc/systemd/system" "$r/usr/local/sbin" "$r/etc/systemd/system/getty@tty1.service.d"
# Masks override both enablement and udev activation. Admin must configure before unmasking.
ln -sfn /dev/null "$r/etc/systemd/system/divinus-camera@.service"
for n in 1 2 3 4; do ln -sfn /dev/null "$r/etc/systemd/system/divinus-camera@$n.service"; done
install -m 755 "$here/install.sh" "$r/usr/local/sbin/openipc-install"
install -m 755 "$here/firstboot.sh" "$r/usr/local/sbin/openipc-firstboot"
install -m 644 "$here/firstboot.service" "$r/etc/systemd/system/openipc-firstboot.service"
mkdir -p "$r/etc/systemd/system/multi-user.target.wants"
ln -sfn ../openipc-firstboot.service "$r/etc/systemd/system/multi-user.target.wants/openipc-firstboot.service"
# Live boot enters only the installer; there is no generic password.
cat > "$r/etc/systemd/system/getty@tty1.service.d/openipc-live.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOF
cat > "$r/root/.bash_profile" <<'EOF'
if [ "$(tty)" = /dev/tty1 ] && grep -qw boot=live /proc/cmdline; then
  /usr/local/sbin/openipc-install
  poweroff
fi
EOF
# Network-facing services are not started in the live environment. This also persists
# after installation; enable only after inspecting and securing the configuration.
for unit in ssh.service ssh.socket systemd-networkd.service systemd-networkd.socket systemd-resolved.service; do ln -sfn /dev/null "$r/etc/systemd/system/$unit"; done
# The supplied rootfs must already have a live-boot-enabled initramfs and tools.
test -e "$r/usr/share/initramfs-tools/scripts/live" || { echo 'rootfs needs live-boot and a regenerated initramfs' >&2; exit 1; }
for cmd in rsync lsblk findmnt sgdisk mkfs.ext4 mkfs.fat grub-install blkid chpasswd; do
  find "$r/usr/bin" "$r/usr/sbin" "$r/bin" "$r/sbin" -maxdepth 1 -name "$cmd" -print -quit 2>/dev/null | grep -q . || { echo "rootfs missing $cmd" >&2; exit 1; }
done
kernel=$(find "$r/boot" -maxdepth 1 -type f -name 'vmlinuz-*' | sort -V | tail -n1)
[ -n "$kernel" ] || exit 1
version=${kernel##*/vmlinuz-}
test -s "$r/boot/initrd.img-$version"
cp "$kernel" "$tmp/iso/live/vmlinuz"
cp "$r/boot/initrd.img-$version" "$tmp/iso/live/initrd"
mksquashfs "$r" "$tmp/iso/live/filesystem.squashfs" -noappend -comp xz
cat > "$tmp/iso/boot/grub/grub.cfg" <<'EOF'
set timeout=5
menuentry 'OpenIPC Live / Install' {
    linux /live/vmlinuz boot=live components systemd.unit=multi-user.target
    initrd /live/initrd
}
EOF
grub-mkrescue -o "$tmp/output.iso" "$tmp/iso"
# Publish without overwriting an existing file.
( set -C; cat "$tmp/output.iso" > "$out" )
sha256sum "$out"
