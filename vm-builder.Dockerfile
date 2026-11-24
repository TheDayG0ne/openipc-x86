FROM debian:bookworm
RUN apt-get update && apt-get install -y --no-install-recommends debootstrap qemu-utils parted e2fsprogs grub-pc-bin grub-common linux-image-amd64 ca-certificates python3 && rm -rf /var/lib/apt/lists/*
COPY openipc-setup-gate.sh /usr/local/share/openipc/setup-gate
COPY openipc-firstboot.sh /usr/local/share/openipc/firstboot
COPY vm-build.sh /usr/local/bin/vm-build.sh
RUN chmod 0755 /usr/local/bin/vm-build.sh
ENTRYPOINT ["/usr/local/bin/vm-build.sh"]
