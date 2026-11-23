FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc make pkg-config libssl-dev libasound2-dev libv4l-dev \
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev \
    git ca-certificates file python3 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
