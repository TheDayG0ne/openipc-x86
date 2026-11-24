# OpenIPC x86 (experimental monorepo)

This repository combines the experimental x86 Buildroot external tree, overlay, disk-image tooling, tests and public upstream source submodules. It is not a production firmware release. **The current build targets a kernel (`bzImage`) and an ext4 root filesystem (`rootfs.ext4`), not a bootable disk image.** The image tool requires a compatible squashfs root and early init; it is not integrated with the current build. Boot, persistence, UVC, RTSP and security are not validated. Do not flash physical disks; isolate experiments from untrusted networks. x264 includes GPL code.

## Build

On Windows install Git, PowerShell and Docker Desktop using Linux containers. From a fresh clone run:

```powershell
./build/build.ps1
```

The script initializes the pinned submodules recursively and runs the existing Buildroot build in an isolated Docker container. Network access and substantial free disk space are required. Optionally set `$env:JOBS = '4'` before running. On success, files are copied to a new `build/artifacts-<id>/` directory. The container is removed; its uniquely tagged builder image remains. On failure the container, if created, remains for diagnosis (`docker logs <name>`); remove it and its image manually when appropriate. No Docker-wide pruning is performed. The checkout is mounted read-only and copied into the container; tracked and uncommitted working-tree changes are inputs, so use a clean checkout for reproducibility. Docker Desktop must be allowed to share the checkout drive.

## Sources

| Submodule | Public URL | Commit |
| --- | --- | --- |
| `sources/divinus` | https://github.com/TheDayG0ne/divinus.git | `980b1831bf832c1c435eceac2229130bc044f44a` |
| `sources/firmware` | https://github.com/OpenIPC/firmware.git | `9e6a05287f4fc17d914e621bcf824e89dbcb8b0c` |
| `sources/majestic-webui` | https://github.com/OpenIPC/majestic-webui.git | `2c15ce5532986272092eb7c4f8e945b71a7681ca` |

The build uses Divinus and firmware; majestic-webui is provided as source, not integrated into this build. Submodule contents and configuration remain upstream. Buildroot itself is fetched at `4235e198768df7d2696f49f28b090c08fed79954` (2024.02.10). The Debian base image, apt packages and other Buildroot downloads are not all pinned, so this is not a guarantee of bit-identical results. Review source licenses and independently verify upstreams.

`buildroot/`, `overlay/`, `image/` and `tests/` retain their own documentation; some describe separate experimental workflows, not the result of the command above. See [build/README.md](build/README.md) for checks and details.
