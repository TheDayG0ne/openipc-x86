# OpenIPC x86-64: experimental Buildroot port

The supported build pipeline is documented in [build/README.md](../build/README.md); run `./build/build.ps1` from the monorepo root. The former standalone `buildroot/build.sh` workflow is retired to avoid divergent source staging and configurations.

The external tree uses the staged firmware GENERAL definitions, the local Divinus source and the `divinus-webui` package. The latter installs the WebUI's unminified `www` tree at `/usr/share/divinus-webui`. It does not configure a web server or reverse proxy; serving it requires independent Divinus support. CGI execution, dependencies, authentication and functionality are not validated.

The output includes a kernel, squashfs and ext4 root filesystem, not a bootloader or disk image. The early init requires a separately provisioned persistent overlay store and boot arguments; see [overlay/README.md](../overlay/README.md) and [image/README.md](../image/README.md). Boot, hardware, RTSP and security require independent testing. Do not flash physical disks; isolate experiments from untrusted networks. x264 enables GPL code.
