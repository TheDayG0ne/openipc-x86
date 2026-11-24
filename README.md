# OpenIPC x86 (experimental monorepo)

This repository combines the experimental x86 Buildroot external tree, overlay, disk-image tooling, tests and public upstream source submodules. It is not a production firmware release. **The build targets a kernel (`bzImage`), squashfs and ext4 root filesystems.** The disk-image tool can consume the squashfs, but is not automatically run: it requires privileged loop devices and mounts in an isolated Linux VM. Boot, persistence, UVC, RTSP and security are not validated. Do not flash physical disks; isolate experiments from untrusted networks. x264 includes GPL code.

## Build

On Windows install Git, PowerShell and Docker Desktop using Linux containers. From a fresh clone run:

```powershell
./build/build.ps1
```

The script initializes the pinned submodules recursively and runs the existing Buildroot build in an isolated Docker container. Git for Windows must support long paths; use a short checkout path and, if needed, enable Windows long-path support. Network access and substantial free disk space are required. Optionally set `$env:JOBS = '4'` before running. On success, files are copied to a new `build/artifacts-<id>/` directory. The container is removed; its uniquely tagged builder image remains. On failure the container, if created, remains for diagnosis (`docker logs <name>`); remove it and its image manually when appropriate. No Docker-wide pruning is performed. The checkout is mounted read-only and copied into the container; tracked and uncommitted working-tree changes are inputs, so use a clean checkout for reproducibility. Docker Desktop must be allowed to share the checkout drive.

## Sources

| Submodule | Public URL | Commit |
| --- | --- | --- |
| `sources/divinus` | https://github.com/TheDayG0ne/divinus.git | `980b1831bf832c1c435eceac2229130bc044f44a` |
| `sources/firmware` | https://github.com/OpenIPC/firmware.git | `9e6a05287f4fc17d914e621bcf824e89dbcb8b0c` |
| `sources/divinus-webui` | https://github.com/TheDayG0ne/divinus-webui.git | `a9efa2a5b6304b5a7539b4616dfa0d6cf4be42e6` |

The build uses Divinus, firmware and Divinus WebUI. The WebUI's unminified `www` tree is installed in `/usr/share/divinus-webui`; no reverse proxy or WebUI server configuration is added. Serving it requires independent Divinus support; CGI execution, backend dependencies, authentication and functionality are not established by copying these files. See the [WebUI README](sources/divinus-webui/README.md) for its limitations. Submodule contents and configuration remain upstream. Buildroot itself is fetched at `4235e198768df7d2696f49f28b090c08fed79954` (2024.02.10). The Debian base image, apt packages and other Buildroot downloads are not all pinned, so this is not a guarantee of bit-identical results. Review source licenses and independently verify upstreams.

`buildroot/`, `overlay/`, `image/` and `tests/` retain their own documentation; some describe separate experimental workflows, not the result of the command above. See [build/README.md](build/README.md) for checks and details.
