#!/bin/bash
set -euxo pipefail
OUT=/out
ROOT=$OUT/rootfs
DISK=$OUT/openipc-x86.vmdk
rm -rf "$ROOT" "$OUT"/work
mkdir -p "$ROOT" "$OUT/work"
debootstrap --arch=amd64 --variant=minbase bookworm "$ROOT" http://deb.debian.org/debian
install -D -m755 /src/divinus "$ROOT/usr/local/bin/divinus"
install -D -m644 /src/divinus.yaml "$ROOT/etc/divinus.yaml"
sed -i 's/^  enable: false$/  enable: true/' "$ROOT/etc/divinus.yaml"
cat > "$ROOT/etc/systemd/system/divinus.service" <<'UNIT'
[Unit]
Description=OpenIPC Divinus streamer
After=network-online.target
Wants=network-online.target
[Service]
ExecStart=/usr/local/bin/divinus /etc/divinus.yaml
Restart=on-failure
RestartSec=2
[Install]
WantedBy=multi-user.target
UNIT
cat > "$ROOT/etc/fstab" <<'FSTAB'
/dev/sda1 / ext4 errors=remount-ro 0 1
FSTAB
chroot "$ROOT" systemctl enable divinus.service || true
chroot "$ROOT" bash -c 'echo openipc-x86 > /etc/hostname; apt-get update; apt-get install -y --no-install-recommends systemd-sysv iproute2 kmod v4l-utils; apt-get clean'
truncate -s 4G "$DISK"
parted -s "$DISK" mklabel msdos mkpart primary ext4 1MiB 100%
LOOP=$(losetup --find --show --partscan "$DISK")
mkfs.ext4 "${LOOP}p1"
mount "${LOOP}p1" "$OUT/work"
cp -a "$ROOT"/. "$OUT/work"/
mount --bind /dev "$OUT/work/dev"; mount --bind /proc "$OUT/work/proc"; mount --bind /sys "$OUT/work/sys"
chroot "$OUT/work" grub-install --target=i386-pc --recheck "$LOOP"
chroot "$OUT/work" update-grub
umount "$OUT/work/sys" "$OUT/work/proc" "$OUT/work/dev"; umount "$OUT/work"; losetup -d "$LOOP"
qemu-img convert -f raw -O vmdk "$DISK" "$OUT/openipc-x86.vmdk"
rm -f "$DISK"
sha256sum "$OUT/openipc-x86.vmdk" > "$OUT/openipc-x86.vmdk.sha256"
