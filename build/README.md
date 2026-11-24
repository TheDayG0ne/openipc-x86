# Experimental x86 build

Run `./build/build.ps1` from the monorepo root on Windows with Git, PowerShell and Docker Desktop (Linux containers). This initializes the public pinned submodules and builds using the current checkout. See the [root README](../README.md) for prerequisites, source pins, output and limitations. The script mounts the checkout read-only, stages sources in the container, and fetches Buildroot 2024.02.10 at commit `4235e198768df7d2696f49f28b090c08fed79954`. Firmware's GENERAL external tree is staged and adapted for multiple external trees; upstream submodule files are not modified. No local source URLs or absolute host paths need configuring.

The current external configuration targets `bzImage` and `rootfs.ext4`; it does not produce a disk image. The separate image tool requires squashfs and a compatible early init, and is not invoked. Building does not establish bootability, hardware support, persistence or security. The script stages `overlay/overlay` for a future compatible Buildroot configuration, but the current configuration does not apply it.

Run `powershell -NoProfile -File ./build/tests/static.ps1` from the root for offline static checks. Full validation requires a clean clone, submodules, Docker and network. These checks do not replace a build or VM and hardware testing.
