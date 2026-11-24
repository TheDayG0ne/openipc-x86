#!/bin/sh
set -eu

# Build in the container's Linux filesystem, not on the read-only checkout.
for path in /repo/buildroot/configs/openipc_x86_64_defconfig /repo/sources/firmware/general/external.mk /repo/sources/divinus/src/Makefile /repo/sources/divinus-webui/www/index.html /repo/sources/divinus-webui/LICENSE; do
    [ -f "$path" ] || { echo "Missing $path; initialize submodules first" >&2; exit 1; }
done
git init -q /work/buildroot
git -C /work/buildroot remote add origin https://github.com/buildroot/buildroot.git
git -C /work/buildroot fetch --depth 1 origin 4235e198768df7d2696f49f28b090c08fed79954
git -C /work/buildroot checkout -q --detach FETCH_HEAD
# The pinned object is an annotated tag; checkout dereferences it to this commit.
[ "$(git -C /work/buildroot rev-parse HEAD)" = c9620ac37e658d177821be85b4c9484e71e19710 ] || { echo 'Unexpected Buildroot commit' >&2; exit 1; }
mkdir -p /work/output/firmware-general /work/buildroot-x86 /work/divinus
rsync -a --exclude=.git /repo/sources/firmware/general/ /work/output/firmware-general/
rsync -a --exclude=.git /repo/buildroot/ /work/buildroot-x86/
# The external defconfig applies this overlay after its board overlay.
mkdir -p /work/buildroot-x86/overlay-x86
rsync -a /repo/overlay/overlay/ /work/buildroot-x86/overlay-x86/
find /work/buildroot-x86/overlay-x86 -type f ! -name '.keep' -exec sed -i 's/\r$//' {} +
chmod +x /work/buildroot-x86/overlay-x86/init /work/buildroot-x86/overlay-x86/usr/sbin/firstboot /work/buildroot-x86/overlay-x86/usr/libexec/overlay-x86
rsync -a --exclude=.git /repo/sources/divinus/ /work/divinus/
mkdir -p /work/divinus-webui
rsync -a --exclude=.git /repo/sources/divinus-webui/ /work/divinus-webui/
find /work/output/firmware-general /work/buildroot-x86 -type f \( -name '*.in' -o -name 'Config.in' -o -name '*.mk' -o -name '*.sh' -o -name '*.list' -o -name '*.awk' -o -name 'external.desc' \) -exec sed -i 's/\r$//' {} +
sed -i 's/$(BR2_EXTERNAL)/$(BR2_EXTERNAL_GENERAL_PATH)/g' /work/output/firmware-general/external.mk
chmod +x /work/output/firmware-general/scripts/rootfs_script.sh
printf '%s\n' 'DIVINUS_OVERRIDE_SRCDIR = /work/divinus' > /work/output/local.mk
make -C /work/buildroot O=/work/output BR2_EXTERNAL=/work/output/firmware-general:/work/buildroot-x86 openipc_x86_64_defconfig
make -C /work/buildroot O=/work/output BR2_EXTERNAL=/work/output/firmware-general:/work/buildroot-x86 -j"${JOBS:-2}" all
# Fail the pipeline if post-build processing removed or changed representative assets.
for asset in index.html a/divinus.js a/divinus.css; do
    cmp "/work/divinus-webui/www/$asset" "/work/output/target/usr/share/divinus-webui/$asset"
done
