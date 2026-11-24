# OpenIPC x86-64: experimental Buildroot port

This is a separate Buildroot external tree; neither firmware nor Divinus is modified. It uses the same upstream Buildroot 2024.02.10 as firmware, a staged copy of firmware's GENERAL package definitions and `rootfs_script.sh`, and an unmodified local Divinus source checkout via `DIVINUS_OVERRIDE_SRCDIR`. The staged `external.mk` is adapted for multiple external trees; text line endings are normalized. Build with Linux/Docker; native Windows filesystems and CRLF conversions are unsuitable for Buildroot. Inputs are mounted read-only. Buildroot copies Divinus into its build directory before cleaning/building it.

On a Linux host with this repository at `$PWD` and the two source checkouts alongside it under `../sources`:

```sh
docker build -t openipc-x86-builder .
docker run --rm -v "$PWD:/work" -v "$PWD/../sources:/sources:ro" -v "$PWD/../overlay-x86:/overlay-source:ro" -e JOBS=4 openipc-x86-builder sh /work/build.sh
```

Output: `output/images/bzImage`, `output/images/rootfs.squashfs` and `output/images/rootfs.ext4` (no bootloader or disk partition image). The original `overlay-x86` early init is staged from the read-only checkout; consult its README for the required squashfs boot arguments, persistent ext4 provisioning and limitations. The squashfs is the root required by disk-image-x86; the ext4 image is not a pre-provisioned overlay store. Set up a bootloader and `root=` yourself; do not flash to a production disk. The local Divinus must contain the UVC FFmpeg changes; upstream firmware's default HEAD package does not enable them. Set source revisions explicitly for reproducible builds. x264 enables GPL code. Defaults are experimental, no authentication guarantee: isolate from untrusted networks.

The firmware post-build hook stamps os-release and prunes files and modules; its SoC-specific late overlays run only when their config symbols are enabled. We deliberately do not apply the whole firmware overlay: it assumes embedded SoC detection, flash layout, claim shell and hardware scripts. This is not yet a complete OpenIPC user experience, installer, or secure production image. The staged early init requires a separately provisioned persistent overlay store and boot arguments; it has not been validated by a boot test here. UVC hardware and RTSP need device testing.
