#!/bin/bash
set -euxo pipefail
OUT=/out
ROOT="$OUT/rootfs"
RAW="$OUT/openipc-x86.raw"
MOUNT="$OUT/mnt"
LOOP=''
cleanup() {
  set +e
  mountpoint -q "$MOUNT/sys" && umount -l "$MOUNT/sys"
  mountpoint -q "$MOUNT/proc" && umount -l "$MOUNT/proc"
  mountpoint -q "$MOUNT/dev" && umount -l "$MOUNT/dev"
  mountpoint -q "$MOUNT" && umount -l "$MOUNT"
  [ -z "$LOOP" ] || losetup -d "$LOOP"
}
trap cleanup EXIT
mkdir -p "$ROOT" "$MOUNT"
if [ -e "$ROOT/etc/os-release" ]; then
  find "$ROOT" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
fi
debootstrap --arch=amd64 --variant=minbase bookworm "$ROOT" http://deb.debian.org/debian
chroot "$ROOT" bash -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends systemd-sysv linux-image-amd64 grub-pc-bin grub-common iproute2 kmod v4l-utils && apt-get clean && rm -rf /var/lib/apt/lists/*'
install -D -m755 /src/divinus "$ROOT/usr/local/bin/divinus"
install -D -m644 /src/divinus.yaml "$ROOT/usr/share/openipc/divinus.yaml"
python3 - "$ROOT/usr/share/openipc/divinus.yaml" "$ROOT/etc/openipc" <<'PY'
from pathlib import Path
import secrets, sys
source, dest = map(Path, sys.argv[1:])
base = source.read_text()
password = secrets.token_urlsafe(18)
dest.mkdir(parents=True, exist_ok=True)
for n in range(1, 5):
    text = base
    text = text.replace('  web_port: 80', f'  web_port: {8080 + n}')
    text = text.replace('onvif:\n  enable: false', 'onvif:\n  enable: true')
    text = text.replace('  port: 554', f'  port: {554 + n - 1}')
    text = text.replace('  auth_pass: 12345', f'  auth_pass: {password}')
    (dest / f'camera{n}.yaml').write_text(text)
(dest / 'README').write_text('Passwords are generated at image build time. Change them before production use.\n')
PY
for n in 1 2 3 4; do
  mkdir -p "$ROOT/etc/openipc/camera$n"
  cp "$ROOT/etc/openipc/camera$n.yaml" "$ROOT/etc/openipc/camera$n/divinus.yaml"
done
cat > "$ROOT/etc/systemd/system/divinus-camera@.service" <<'UNIT'
[Unit]
Description=OpenIPC Divinus camera %i
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
WorkingDirectory=/etc/openipc/camera%i
EnvironmentFile=-/etc/openipc/camera%i/environment
ExecStart=/usr/local/bin/divinus
Restart=on-failure
RestartSec=2
[Install]
WantedBy=multi-user.target
UNIT
for n in 1 2 3 4; do
  printf 'UVC_DEVICE=/dev/video%s\n' "$((n - 1))" > "$ROOT/etc/openipc/camera$n/environment"
done
cat > "$ROOT/etc/fstab" <<'FSTAB'
/dev/sda1 / ext4 errors=remount-ro 0 1
FSTAB
printf 'openipc-x86\n' > "$ROOT/etc/hostname"
chroot "$ROOT" systemctl enable divinus-camera@1.service divinus-camera@2.service divinus-camera@3.service divinus-camera@4.service
truncate -s 4G "$RAW"
parted -s "$RAW" mklabel msdos mkpart primary ext4 1MiB 100%
LOOP=$(losetup --find --show --partscan "$RAW")
mkfs.ext4 "${LOOP}p1"
mount "${LOOP}p1" "$MOUNT"
cp -a "$ROOT"/. "$MOUNT"/
mount --bind /dev "$MOUNT/dev"
mount -t proc proc "$MOUNT/proc"
mount --bind /sys "$MOUNT/sys"
chroot "$MOUNT" grub-install --target=i386-pc --recheck "$LOOP"
chroot "$MOUNT" update-grub
umount -l "$MOUNT/sys" "$MOUNT/proc" "$MOUNT/dev" "$MOUNT"
losetup -d "$LOOP"; LOOP=''
qemu-img convert -p -f raw -O vmdk "$RAW" "$OUT/openipc-x86.vmdk"
qemu-img info "$OUT/openipc-x86.vmdk"
sha256sum "$OUT/openipc-x86.vmdk" > "$OUT/openipc-x86.vmdk.sha256"
rm -f "$RAW"
