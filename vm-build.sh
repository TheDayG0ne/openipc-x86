#!/bin/bash
set -euxo pipefail
OUT=/out
INPUT=/input
TMP=$(mktemp -d "$OUT/.openipc-vm.XXXXXX")
ROOT="$TMP/rootfs"
RAW="$TMP/openipc-x86.raw"
MOUNT="$TMP/mnt"
LOOP=''
cleanup() {
  set +e
  mountpoint -q "$MOUNT/sys" && umount -l "$MOUNT/sys"
  mountpoint -q "$MOUNT/proc" && umount -l "$MOUNT/proc"
  mountpoint -q "$MOUNT/dev" && umount -l "$MOUNT/dev"
  mountpoint -q "$MOUNT" && umount -l "$MOUNT"
  [ -z "$LOOP" ] || losetup -d "$LOOP"
  rm -rf -- "$TMP"
}
trap cleanup EXIT
mkdir -p "$ROOT" "$MOUNT"
test -s "$INPUT/divinus"
test -s /src/divinus.yaml
debootstrap --arch=amd64 --no-merged-usr --variant=minbase bookworm "$ROOT" http://deb.debian.org/debian
cp -L /etc/resolv.conf "$ROOT/etc/resolv.conf"
chroot "$ROOT" bash -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends systemd-sysv linux-image-amd64 grub-pc-bin grub-common iproute2 kmod v4l-utils libavcodec59 libavformat59 libavutil57 libswscale6 libswresample4 ca-certificates && apt-get clean && rm -rf /var/lib/apt/lists/*'
install -D -m755 "$INPUT/divinus" "$ROOT/usr/local/bin/divinus"
install -D -m644 /src/divinus.yaml "$ROOT/usr/share/openipc/divinus.yaml"
python3 - "$ROOT/usr/share/openipc/divinus.yaml" "$ROOT/etc/openipc" <<'PY'
from pathlib import Path
import secrets, sys
source, dest = map(Path, sys.argv[1:])
base = source.read_text()
password = secrets.token_urlsafe(24)
dest.mkdir(parents=True, exist_ok=True)
for n in range(1, 5):
    text = base
    text = text.replace('  web_port: 80', f'  web_port: {8080 + n}')
    text = text.replace('  web_enable_auth: false', '  web_enable_auth: true')
    text = text.replace('  web_auth_skiplocal: true', '  web_auth_skiplocal: false')
    text = text.replace('  web_auth_pass: 12345', f'  web_auth_pass: {password}')
    text = text.replace('onvif:\n  enable: false', 'onvif:\n  enable: true')
    text = text.replace('  enable_auth: false', '  enable_auth: true')
    text = text.replace('  auth_pass: 12345', f'  auth_pass: {password}')
    text = text.replace('  port: 554', f'  port: {554 + n - 1}')
    (dest / f'camera{n}.yaml').write_text(text)
(dest / 'README').write_text('Generated test credentials are present in camera*.yaml; change them before production use.\n')
PY
for n in 1 2 3 4; do
  mkdir -p "$ROOT/etc/openipc/camera$n"
  cp "$ROOT/etc/openipc/camera$n.yaml" "$ROOT/etc/openipc/camera$n/divinus.yaml"
  printf 'UVC_DEVICE=/dev/video%s\n' "$((n - 1))" > "$ROOT/etc/openipc/camera$n/environment"
done
cat > "$ROOT/etc/systemd/system/divinus-camera@.service" <<'UNIT'
[Unit]
Description=OpenIPC Divinus camera %i (non-production test image)
After=network-online.target systemd-udev-settle.service
Wants=network-online.target
[Service]
Type=simple
WorkingDirectory=/etc/openipc/camera%i
EnvironmentFile=/etc/openipc/camera%i/environment
ExecStart=/usr/local/bin/divinus
Restart=on-failure
RestartSec=2
[Install]
WantedBy=multi-user.target
UNIT
mkdir -p "$ROOT/etc/systemd/network"
cat > "$ROOT/etc/systemd/network/20-wired.network" <<'NET'
[Match]
Name=en* eth*
[Network]
DHCP=yes
NET
cat > "$ROOT/etc/fstab" <<'FSTAB'
/dev/sda1 / ext4 errors=remount-ro 0 1
FSTAB
printf 'openipc-x86\n' > "$ROOT/etc/hostname"
cat > "$ROOT/etc/default/grub" <<'GRUB'
GRUB_TIMEOUT=1
GRUB_CMDLINE_LINUX_DEFAULT="console=ttyS0,115200n8 systemd.unit=multi-user.target"
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL="serial console"
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
GRUB
chroot "$ROOT" useradd --system --create-home --shell /usr/sbin/nologin openipc || true
chroot "$ROOT" passwd --lock root
chroot "$ROOT" systemctl enable systemd-networkd.service divinus-camera@1.service divinus-camera@2.service divinus-camera@3.service divinus-camera@4.service
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
