#!/bin/bash
set -euo pipefail
OUT=/out
INPUT=/input
WORK=/work
TMP=$(mktemp -d "$WORK/.openipc-vm.XXXXXX")
ROOT="$TMP/rootfs"
RAW="$TMP/openipc-x86.raw"
MOUNT="$TMP/mnt"
LOOP=''
PART=''
PART_NODE_CREATED=''
cleanup() {
  set +e
  mountpoint -q "$MOUNT/sys" && umount -l "$MOUNT/sys"
  mountpoint -q "$MOUNT/proc" && umount -l "$MOUNT/proc"
  mountpoint -q "$MOUNT/dev" && umount -l "$MOUNT/dev"
  mountpoint -q "$MOUNT" && umount -l "$MOUNT"
  [ -z "$LOOP" ] || losetup -d "$LOOP"
  [ -z "$PART_NODE_CREATED" ] || rm -f -- "$PART_NODE_CREATED"
  rm -rf -- "$TMP"
}
trap cleanup EXIT
mkdir -p "$ROOT" "$MOUNT"
test -s "$INPUT/divinus"
test -s /src/divinus.yaml
debootstrap --arch=amd64 --variant=minbase bookworm "$ROOT" http://deb.debian.org/debian
cp -L /etc/resolv.conf "$ROOT/etc/resolv.conf"
chroot "$ROOT" bash -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends systemd-sysv systemd-resolved linux-image-amd64 grub-pc grub-pc-bin grub-common iproute2 kmod v4l-utils libavcodec59 libavformat59 libavutil57 libswscale6 libswresample4 ca-certificates && apt-get clean && rm -rf /var/lib/apt/lists/*'
install -D -m755 "$INPUT/divinus" "$ROOT/usr/lib/openipc/divinus.bin"
install -D -m755 /usr/local/share/openipc/setup-gate "$ROOT/usr/lib/openipc/setup-gate"
install -D -m755 /usr/local/share/openipc/firstboot "$ROOT/usr/lib/openipc/firstboot"
install -d -m755 "$ROOT/usr/share/openipc/eula"
cp /eula/eula.*.txt "$ROOT/usr/share/openipc/eula/"
test -s "$ROOT/usr/share/openipc/eula/eula.en.txt"
cat > "$ROOT/usr/local/bin/divinus" <<'WRAPPER'
#!/bin/sh
/usr/lib/openipc/setup-gate || { echo 'OpenIPC setup required on tty1' >&2; exit 1; }
exec /usr/lib/openipc/divinus.bin "$@"
WRAPPER
chmod 755 "$ROOT/usr/local/bin/divinus"
install -D -m644 /src/divinus.yaml "$ROOT/usr/share/openipc/divinus.yaml"
python3 - "$ROOT/usr/share/openipc/divinus.yaml" "$ROOT/etc/openipc" /secrets/credentials.txt <<'PY'
from pathlib import Path
import secrets, sys
source, dest, export = map(Path, sys.argv[1:])
base = source.read_text()
credentials = []
dest.mkdir(parents=True, exist_ok=True)
for n in range(1, 5):
    passwords = {key: secrets.token_urlsafe(24) for key in ("web", "onvif", "rtsp")}
    credentials.append(f"camera{n}: " + ", ".join(f"{k} admin: {v}" for k, v in passwords.items()))
    text = base.replace('  web_port: 80', f'  web_port: {8080+n}')
    text = text.replace('  web_enable_auth: false', '  web_enable_auth: true')
    text = text.replace('  web_auth_skiplocal: true', '  web_auth_skiplocal: false')
    text = text.replace('  web_auth_pass: 12345', f'  web_auth_pass: {passwords["web"]}')
    text = text.replace('onvif:\n  enable: false', 'onvif:\n  enable: true')
    text = text.replace('  port: 554', f'  port: {553+n}')
    for section in ('onvif', 'rtsp'):
        start = text.index(section + ':\n')
        end = text.find('\n\n', start)
        if end < 0: end = len(text)
        part = text[start:end]
        assert '  auth_pass: 12345' in part
        text = text[:start] + part.replace('  auth_pass: 12345', f'  auth_pass: {passwords[section]}', 1) + text[end:]
    text = text.replace('onvif:\n  enable: true\n  enable_auth: false', 'onvif:\n  enable: true\n  enable_auth: true')
    text = text.replace('rtsp:\n  enable: true\n  enable_auth: false', 'rtsp:\n  enable: true\n  enable_auth: true')
    assert '  web_auth_pass: 12345' not in text
    (dest/f'camera{n}.yaml').write_text(text)
export.write_text('\n'.join(credentials) + '\n')
export.chmod(0o600)
(dest/'README').write_text('Generated test credentials are in camera*.yaml; change them before production use.\n')
PY
chmod 700 "$ROOT/etc/openipc"
chmod 600 "$ROOT/etc/openipc/"*.yaml
chroot "$ROOT" passwd -l root
cat > "$ROOT/etc/systemd/system/openipc-firstboot.service" <<'UNIT'
[Unit]
Description=OpenIPC local first boot setup
After=systemd-user-sessions.service
Before=serial-getty@ttyS0.service
[Service]
Type=oneshot
ExecStart=/usr/lib/openipc/firstboot
StandardInput=tty-force
StandardOutput=tty
TTYPath=/dev/ttyS0
Restart=on-failure
RestartSec=3
[Install]
WantedBy=multi-user.target
UNIT
chroot "$ROOT" systemctl enable openipc-firstboot.service
mkdir -p "$ROOT/etc/systemd/system/serial-getty@ttyS0.service.d"
printf '[Unit]\nAfter=openipc-firstboot.service\n' > "$ROOT/etc/systemd/system/serial-getty@ttyS0.service.d/openipc.conf"
for n in 1 2 3 4; do
  mkdir -p "$ROOT/etc/openipc/camera$n"
  cp "$ROOT/etc/openipc/camera$n.yaml" "$ROOT/etc/openipc/camera$n/divinus.yaml"
  chmod 600 "$ROOT/etc/openipc/camera$n/divinus.yaml"
  mkdir -p "$ROOT/etc/systemd/system/divinus-camera@$n.service.d" "$ROOT/etc/udev/rules.d"
  printf '[Unit]\nBindsTo=dev-video%s.device\nAfter=dev-video%s.device\n' "$((n-1))" "$((n-1))" > "$ROOT/etc/systemd/system/divinus-camera@$n.service.d/device.conf"
  printf 'SUBSYSTEM=="video4linux", KERNEL=="video%s", TAG+="systemd", ENV{SYSTEMD_WANTS}+="divinus-camera@%s.service"\n' "$((n-1))" "$n" >> "$ROOT/etc/udev/rules.d/80-openipc-cameras.rules"
  printf 'UVC_DEVICE=/dev/video%s\n' "$((n-1))" > "$ROOT/etc/openipc/camera$n/environment"
done
cat > "$ROOT/etc/systemd/system/divinus-camera@.service" <<'UNIT'
[Unit]
Description=OpenIPC Divinus camera %i (non-production test image)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=3
[Service]
Type=simple
WorkingDirectory=/etc/openipc/camera%i
EnvironmentFile=/etc/openipc/camera%i/environment
ExecStartPre=/usr/lib/openipc/setup-gate
ExecStart=/usr/local/bin/divinus
Restart=on-failure
RestartSec=10
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
ln -sf /run/systemd/resolve/stub-resolv.conf "$ROOT/etc/resolv.conf"
cat > "$ROOT/etc/fstab" <<'FSTAB'
LABEL=openipc-root / ext4 errors=remount-ro 0 1
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
chroot "$ROOT" systemctl enable systemd-networkd.service systemd-resolved.service
truncate -s 4G "$RAW"
parted -s "$RAW" mklabel msdos mkpart primary ext4 1MiB 100%
LOOP=$(losetup --find --show --partscan "$RAW")
PART="${LOOP}p1"
PART_SYS="/sys/class/block/${PART##*/}"
if [ ! -r "$PART_SYS/dev" ]; then
  echo "Partition device not exposed by kernel: $PART" >&2
  exit 1
fi
IFS=: read -r major minor < "$PART_SYS/dev"
if [ ! -e "$PART" ]; then
  mknod "$PART" b "$major" "$minor"
  PART_NODE_CREATED=$PART
fi
[ -b "$PART" ] && [ "$(stat -c '%t:%T' "$PART")" = "$(printf '%x:%x' "$major" "$minor")" ] || { echo "Unexpected partition device: $PART" >&2; exit 1; }
[ "$(cat "$PART_SYS/start")" = 2048 ] || { echo 'Unexpected partition start' >&2; exit 1; }
[ "$(cat "$PART_SYS/size")" = 8386560 ] || { echo 'Unexpected partition size' >&2; exit 1; }
mkfs.ext4 -F -L openipc-root -O ^64bit,^metadata_csum "$PART"
mount "$PART" "$MOUNT"
cp -a "$ROOT"/. "$MOUNT"/
mount --bind /dev "$MOUNT/dev"
mount -t proc proc "$MOUNT/proc"
mount --bind /sys "$MOUNT/sys"
mkdir -p "$MOUNT/boot/grub"
printf '(hd0) %s\n' "$LOOP" > "$MOUNT/boot/grub/device.map"
chroot "$MOUNT" grub-install --target=i386-pc --boot-directory=/boot --recheck "$LOOP"
kernel=$(basename "$(find "$MOUNT/boot" -maxdepth 1 -name 'vmlinuz-*' -type f | sort -V | tail -n1)")
version=${kernel#vmlinuz-}
test -n "$version" && test -s "$MOUNT/boot/initrd.img-$version"
uuid=$(blkid -s UUID -o value "$PART")
test -n "$uuid"
cat > "$MOUNT/boot/grub/grub.cfg" <<GRUBCFG
set timeout=1
serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
terminal_input serial console
terminal_output serial console
menuentry 'OpenIPC x86' {
    search --no-floppy --fs-uuid --set=root $uuid
    linux /boot/$kernel root=UUID=$uuid ro console=ttyS0,115200n8 systemd.unit=multi-user.target
    initrd /boot/initrd.img-$version
}
GRUBCFG
chroot "$MOUNT" grub-script-check /boot/grub/grub.cfg
sync
umount "$MOUNT/sys" "$MOUNT/proc" "$MOUNT/dev" "$MOUNT"
losetup -d "$LOOP"
LOOP=''
[ -z "$PART_NODE_CREATED" ] || rm -f -- "$PART_NODE_CREATED"
PART_NODE_CREATED=''
qemu-img convert -p -f raw -O vmdk "$RAW" "$TMP/openipc-x86.vmdk"
qemu-img info "$TMP/openipc-x86.vmdk"
( set -C; cat "$TMP/openipc-x86.vmdk" > "$OUT/openipc-x86.vmdk" )
( set -C; cat "$RAW" > "$OUT/openipc-x86.img" )
( set -C; sha256sum "$OUT/openipc-x86.vmdk" > "$OUT/openipc-x86.vmdk.sha256" )
( set -C; sha256sum "$OUT/openipc-x86.img" > "$OUT/openipc-x86.img.sha256" )
