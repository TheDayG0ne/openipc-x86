#!/bin/sh
set -eu
cd /work
BR_VERSION=2024.02.10
if [ ! -f "buildroot-$BR_VERSION/Makefile" ]; then
    wget -O "/tmp/buildroot-$BR_VERSION.tar.gz" "https://github.com/buildroot/buildroot/archive/$BR_VERSION.tar.gz"
    tar -xf "/tmp/buildroot-$BR_VERSION.tar.gz"
fi
# GENERAL's external.mk assumes a single external tree in BR2_EXTERNAL. Stage
# its files and adapt that reference for a multi-external build; do not edit the
# checkout. This staging also normalizes Windows checkouts' CRLF shell/Kconfig.
# Stage the original external early-init overlay without changing its checkout.
mkdir -p overlay-x86
rsync -a --delete /overlay-source/overlay/ overlay-x86/
find overlay-x86 -type f ! -name '.keep' -exec sed -i 's/\r$//' {} +
chmod +x overlay-x86/init overlay-x86/usr/sbin/firstboot
mkdir -p output/firmware-general
rsync -a --delete /sources/firmware/general/ output/firmware-general/
find output/firmware-general -type f \( -name '*.in' -o -name 'Config.in' -o -name '*.mk' -o -name '*.sh' -o -name '*.list' -o -name '*.awk' -o -name 'external.desc' \) -exec sed -i 's/\r$//' {} +
sed -i 's/$(BR2_EXTERNAL)/$(BR2_EXTERNAL_GENERAL_PATH)/g' output/firmware-general/external.mk
chmod +x output/firmware-general/scripts/rootfs_script.sh
printf '%s\n' 'DIVINUS_OVERRIDE_SRCDIR = /sources/divinus' > output/local.mk
make -C "buildroot-$BR_VERSION" O=/work/output BR2_EXTERNAL=/work/output/firmware-general:/work openipc_x86_64_defconfig
make -C "buildroot-$BR_VERSION" O=/work/output BR2_EXTERNAL=/work/output/firmware-general:/work -j"${JOBS:-2}" all
