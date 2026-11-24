#!/bin/bash
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" = 0 ] && [ -t 0 ] || { echo 'Requires an interactive root console.' >&2; exit 1; }
grep -qw boot=live /proc/cmdline || { echo 'Installer only runs from live media.' >&2; exit 1; }
medium=$(findmnt -n -o SOURCE --target /run/live/medium || true)
medium=${medium%%\[*}
[ -b "$medium" ] || { echo 'Cannot identify live medium; refusing installation.' >&2; exit 1; }
medium=$(readlink -f "$medium")
lsblk -d -o NAME,PATH,SIZE,MODEL,SERIAL,TRAN,RM,RO,TYPE
printf 'Target whole disk (absolute /dev path), or blank to abort: '
read -r input
[ -n "$input" ] || exit 1
case "$input" in /dev/*) ;; *) exit 1;; esac
disk=$(readlink -e -- "$input")
[ -b "$disk" ] && [ "$(lsblk -dn -o TYPE "$disk")" = disk ] || { echo 'Not a whole disk.' >&2; exit 1; }
[ "$(lsblk -dn -o RO "$disk")" = 0 ] && [ "$(lsblk -dn -o RM "$disk")" = 0 ] || { echo 'Read-only or removable disk.' >&2; exit 1; }
check_disk() {
  # Reject the medium, any mounted descendants, swap, device-mapper holders and
  # unusual stacked layouts. Recheck immediately before destructive operations.
  local node name
  while read -r node; do
    node=$(readlink -f "$node")
    [ "$node" != "$medium" ] || return 1
    findmnt -rn -S "$node" | grep -q . && return 1
    awk 'NR>1 {print $1}' /proc/swaps | grep -Fxq "$node" && return 1
    name=${node##*/}
    [ -d "/sys/class/block/$name/holders" ] || return 1
    [ -z "$(ls -A "/sys/class/block/$name/holders")" ] || return 1
  done < <(lsblk -nrpo NAME "$disk")
  # Live media must have a uniquely identifiable physical ancestor.
  local parent
  parent=$(lsblk -s -nrpo NAME,TYPE "$medium" | awk '$2=="disk" {print $1}')
  [ -n "$parent" ] && [ "$(printf '%s\n' "$parent" | wc -l)" -eq 1 ] || return 1
  [ "$(readlink -f "$parent")" != "$disk" ]
}
check_disk || { echo 'Disk or live medium is in use or ambiguous; refusing.' >&2; exit 1; }
size=$(blockdev --getsize64 "$disk")
[ "$size" -ge 8589934592 ] || { echo 'Disk must be at least 8 GiB.' >&2; exit 1; }
printf 'ALL DATA on %s (%s bytes) will be destroyed. Type exactly ERASE %s: ' "$disk" "$size" "$disk"
read -r answer
[ "$answer" = "ERASE $disk" ] || exit 1
check_disk || { echo 'Disk state changed; refusing.' >&2; exit 1; }
sgdisk --zap-all "$disk"
sgdisk -n 1:1MiB:+2MiB -t 1:ef02 -n 2:0:+512MiB -t 2:ef00 -n 3:0:0 -t 3:8300 "$disk"
partprobe "$disk"
udevadm settle
part() { lsblk -nrpo PATH,PARTN "$disk" | awk -v n="$1" '$2==n {print $1}'; }
esp=$(part 2); root=$(part 3)
[ -b "$esp" ] && [ -b "$root" ] && [ "$esp" != "$root" ] || { echo 'Partition discovery failed.' >&2; exit 1; }
mkfs.fat -F 32 "$esp"
mkfs.ext4 -F "$root"
target=$(mktemp -d /mnt/openipc-install.XXXXXX)
cleanup() { set +e; umount -R "$target"; rmdir "$target"; }
trap cleanup EXIT
mount "$root" "$target"
mkdir -p "$target/boot/efi"
mount "$esp" "$target/boot/efi"
# Copy the immutable lower layer, not the running overlay and its transient state.
source_dir=/run/live/rootfs/filesystem.squashfs
mountpoint -q "$source_dir" || { echo 'Live lower layer not found; refusing copy.' >&2; exit 1; }
rsync -aHAX --numeric-ids --one-file-system "$source_dir/" "$target/"
rm -f "$target/etc/systemd/system/getty@tty1.service.d/openipc-live.conf" "$target/root/.bash_profile"
uuid=$(blkid -s UUID -o value "$root"); efiuuid=$(blkid -s UUID -o value "$esp")
[ -n "$uuid" ] && [ -n "$efiuuid" ] || exit 1
printf 'UUID=%s / ext4 errors=remount-ro 0 1\nUUID=%s /boot/efi vfat umask=0077 0 2\n' "$uuid" "$efiuuid" > "$target/etc/fstab"
mount --bind /dev "$target/dev"
mount -t proc proc "$target/proc"
mount --bind /sys "$target/sys"
chroot "$target" grub-install --target=i386-pc --recheck "$disk"
chroot "$target" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=OpenIPC --removable --no-nvram
kernel=$(find "$target/boot" -maxdepth 1 -type f -name 'vmlinuz-*' | sort -V | tail -n1)
version=${kernel##*/vmlinuz-}
test -s "$target/boot/initrd.img-$version"
mkdir -p "$target/boot/grub"
cat > "$target/boot/grub/grub.cfg" <<EOF
set timeout=3
menuentry 'OpenIPC' {
 search --no-floppy --fs-uuid --set=root $uuid
 linux /boot/vmlinuz-$version root=UUID=$uuid ro
 initrd /boot/initrd.img-$version
}
EOF
chroot "$target" grub-script-check /boot/grub/grub.cfg
sync
echo 'Installation complete. Remove the live medium and reboot. Configure a unique root password at first boot.'
