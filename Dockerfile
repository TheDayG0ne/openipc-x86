FROM debian:bookworm
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends build-essential bc bzip2 ca-certificates cpio file git gzip libncurses-dev libssl-dev libelf-dev patch perl python3 rsync unzip wget xz-utils && rm -rf /var/lib/apt/lists/*
WORKDIR /work
