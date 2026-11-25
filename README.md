# OpenIPC x86 (experimental monorepo)

This repository combines the experimental x86 Buildroot external tree, overlay, disk-image tooling, tests and public upstream source submodules. It is not a production firmware release. **The build targets a kernel (`bzImage`), squashfs and ext4 root filesystems.** The disk-image tool can consume the squashfs, but is not automatically run: it requires privileged loop devices and mounts in an isolated Linux VM. Boot, persistence, UVC, RTSP and security are not validated. Do not flash physical disks; isolate experiments from untrusted networks. x264 includes GPL code.

## Build

### Ubuntu Server 24.04 (one command)

Use a dedicated, patched Ubuntu Server 24.04 build host or isolated VM. From any directory, run the public helper below; it clones this repository from Git, initializes the pinned public submodules, and uses the existing Docker Buildroot pipeline:

```bash
curl -fsSL https://raw.githubusercontent.com/TheDayG0ne/openipc-x86/master/build/build-ubuntu.sh -o build-ubuntu.sh
chmod 0755 build-ubuntu.sh
./build-ubuntu.sh
```

The helper **does not install Docker by default**. If Docker is not already installed, review the script and explicitly opt in to the Ubuntu package installation with `INSTALL_DOCKER=1 ./build-ubuntu.sh`. This uses `sudo apt-get` and enables the Docker service; use a separate build VM, keep packages updated, and remember that Docker access (including membership in the `docker` group) is effectively root-equivalent. Do not run the build on a workstation containing secrets or production mounts. The script never embeds IP addresses, credentials, tokens, or private URLs. Use `--ref` to select a reviewed Git ref, `--jobs N` to limit parallelism, and `--output DIR` to place artifacts outside the checkout.

The builder mounts the checkout read-only and retains the uniquely tagged builder image. On success it prints an artifacts directory containing `bzImage`, `rootfs.ext4`, and `rootfs.squashfs`; it does not create an ISO, raw disk image, VMDK, or flash media. On failure any created container and tagged image are retained for diagnosis; the helper reports which it can find. The disposable clone is removed on success or failure. Inspect with `docker logs <container>` and remove only the exact tagged resources after review; no Docker-wide prune is performed. Treat artifacts as untrusted build output, verify hashes/signatures in your release process, and transfer them only through an authenticated, access-controlled channel. Do not boot or flash them on production hardware. Disk-image creation requires a separate isolated Linux VM with deliberately reviewed privileged loop/mount access; see [image/README.md](image/README.md).

Static verification, without Docker or a build, is available from a checkout:

```bash
bash -n build/build-ubuntu.sh build/buildroot-entrypoint.sh build/tests/build-ubuntu.sh
bash build/tests/build-ubuntu.sh
powershell.exe -NoProfile -File ./build/tests/static.ps1  # if PowerShell is installed
```

When invoked outside a checkout, the helper creates a temporary disposable clone, selects
`--ref` (or `master`), and initializes its recursive submodules there. If invoked from a
checkout, it uses that checkout without changing branches, refs, or submodules. Supplying
`--ref` always uses a separate temporary clone, so a reviewed or locally modified checkout
cannot be silently overwritten. A temporary clone runs its own selected script and is removed
on exit. Its default output is a uniquely named directory beside the checkout; `--output`
must name a new directory outside every checkout (an existing directory is rejected). All
artifacts are copied to a unique staging directory and published by rename only after every
`docker cp` succeeds, so failures cannot mix old and new outputs. Refs beginning with `-`
are rejected. The contract test uses fake Git and Docker commands and does not run a build.

The Ubuntu helper is a convenience wrapper around `build/build.ps1`'s Docker pipeline; it does not alter component sources. For reproducibility, review the selected commit and submodule gitlinks before building. Network access is needed for the clone, submodules, Docker base image, and Buildroot downloads.

On Windows install Git, PowerShell and Docker Desktop using Linux containers. From a fresh clone run:

```powershell
./build/build.ps1
```

The script initializes the pinned submodules recursively and runs the existing Buildroot build in an isolated Docker container. Git for Windows must support long paths; use a short checkout path and, if needed, enable Windows long-path support. Network access and substantial free disk space are required. Optionally set `$env:JOBS = '4'` before running. On success, files are copied to a new `build/artifacts-<id>/` directory. The container is removed; its uniquely tagged builder image remains. On failure the container, if created, remains for diagnosis (`docker logs <name>`); remove it and its image manually when appropriate. No Docker-wide pruning is performed. The checkout is mounted read-only and copied into the container; tracked and uncommitted working-tree changes are inputs, so use a clean checkout for reproducibility. Docker Desktop must be allowed to share the checkout drive.

## Sources

| Submodule | Public URL | Commit |
| --- | --- | --- |
| `sources/divinus` | https://github.com/TheDayG0ne/divinus.git | `943b7d5396955ede00aa85c03f2723bf6df4a183` |
| `sources/firmware` | https://github.com/OpenIPC/firmware.git | `9e6a05287f4fc17d914e621bcf824e89dbcb8b0c` |
| `sources/divinus-webui` | https://github.com/TheDayG0ne/divinus-webui.git | `c07b4b2326ecf8cb46b679f0a2af8553ee24b148` |

The build uses Divinus, firmware and Divinus WebUI. The WebUI's unminified `www` tree is installed in `/usr/share/divinus-webui`; no reverse proxy or WebUI server configuration is added. Serving it requires independent Divinus support; CGI execution, backend dependencies, authentication and functionality are not established by copying these files. See the [WebUI README](sources/divinus-webui/README.md) for its limitations. Submodule contents and configuration remain upstream. Buildroot itself is fetched using annotated tag object `4235e198768df7d2696f49f28b090c08fed79954` (2024.02.10), which resolves to commit `c9620ac37e658d177821be85b4c9484e71e19710`. The Debian base image, apt packages and other Buildroot downloads are not all pinned, so this is not a guarantee of bit-identical results. Review source licenses and independently verify upstreams.

`buildroot/`, `overlay/`, `image/` and `tests/` retain their own documentation; some describe separate experimental workflows, not the result of the command above. See [build/README.md](build/README.md) for checks and details.
