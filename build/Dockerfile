# Build environment: Ubuntu 20.04 (glibc 2.31, so binaries run on every PortMaster CFW)
# with the aarch64 cross compiler for box64 and the native compiler for the Steam stub.
FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git build-essential python3 \
      gcc-aarch64-linux-gnu g++-aarch64-linux-gnu binutils-aarch64-linux-gnu \
 && rm -rf /var/lib/apt/lists/*
# Ubuntu 20.04 ships CMake 3.16; box64 needs 3.19 or newer.
RUN curl -sL https://github.com/Kitware/CMake/releases/download/v3.30.5/cmake-3.30.5-linux-x86_64.tar.gz \
    | tar xz -C /opt && ln -s /opt/cmake-3.30.5-linux-x86_64/bin/* /usr/local/bin/
WORKDIR /src
