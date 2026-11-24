#!/bin/sh
set -eu

# Build in the container's Linux filesystem, not on the read-only checkout.
for path in /repo/buildroot/configs/openipc_x86_64_defconfig /repo/sources/firmware/general/external.mk /repo/sources/divinus/src/Makefile; do
    [ -f "$path" ] || { echo "Missing $path; initialize submodules first" >&2; exit 1; }
done
git init -q /work/buildroot
git -C /work/buildroot remote add origin https://github.com/buildroot/buildroot.git
git -C /work/buildroot fetch --depth 1 origin 4235e198768df7d2696f49f28b090c08fed79954
git -C /work/buildroot checkout -q --detach FETCH_HEAD
[ "$(git -C /work/buildroot rev-parse HEAD)" = 4235e198768df7d2696f49f28b090c08fed79954 ] || exit 1
mkdir -p /work/output/firmware-general /work/buildroot-x86 /work/divinus
rsync -a --exclude=.git /repo/sources/firmware/general/ /work/output/firmware-general/
rsync -a --exclude=.git /repo/buildroot/ /work/buildroot-x86/
# The external defconfig applies this overlay after its board overlay.
mkdir -p /work/buildroot-x86/overlay-x86
rsync -a /repo/overlay/overlay/ /work/buildroot-x86/overlay-x86/
find /work/buildroot-x86/overlay-x86 -type f ! -name '.keep' -exec sed -i 's/\r$//' {} +
chmod +x /work/buildroot-x86/overlay-x86/init /work/buildroot-x86/overlay-x86/usr/sbin/firstboot /work/buildroot-x86/overlay-x86/usr/libexec/overlay-x86
rsync -a --exclude=.git /repo/sources/divinus/ /work/divinus/
find /work/output/firmware-general /work/buildroot-x86 -type f \( -name '*.in' -o -name 'Config.in' -o -name '*.mk' -o -name '*.sh' -o -name '*.list' -o -name '*.awk' -o -name 'external.desc' \) -exec sed -i 's/\r$//' {} +
sed -i 's/$(BR2_EXTERNAL)/$(BR2_EXTERNAL_GENERAL_PATH)/g' /work/output/firmware-general/external.mk
chmod +x /work/output/firmware-general/scripts/rootfs_script.sh
printf '%s\n' 'DIVINUS_OVERRIDE_SRCDIR = /work/divinus' > /work/output/local.mk
make -C /work/buildroot O=/work/output BR2_EXTERNAL=/work/output/firmware-general:/work/buildroot-x86 openipc_x86_64_defconfig
make -C /work/buildroot O=/work/output BR2_EXTERNAL=/work/output/firmware-general:/work/buildroot-x86 -j"${JOBS:-2}" all
