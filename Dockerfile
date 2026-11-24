FROM openipc-x86-divinus:local
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ffmpeg curl && rm -rf /var/lib/apt/lists/*
WORKDIR /test
ENTRYPOINT ["/bin/sh", "/test/run.sh"]
