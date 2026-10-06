#!/bin/bash
# Builds everything the port ships that is not game data, inside build/Dockerfile (Ubuntu 20.04):
#   box64 (aarch64, dynarec on)           -> port/shogunshowdown/box64/box64
#   box64's x86_64 libgcc_s               -> port/shogunshowdown/box64/box64-x86_64-linux-gnu/
#   glespass libGL.so.1 (aarch64)         -> port/shogunshowdown/glespass/libGL.so.1
#   libsteam_api.so stand in (x86_64)     -> port/shogunshowdown/steamstub/libsteam_api.so
# Usage: build/build.sh [box64 git tag]
set -e
TAG="${1:-v0.4.4}"
R="$(cd "$(dirname "$0")/.." && pwd)"
P=port/shogunshowdown
docker build -q -t shogunshowdown-portmaster-build "$R/build" >/dev/null
mkdir -p "$R/build/src"
[ -d "$R/build/src/box64" ] || git clone -q --depth 1 --branch "$TAG" https://github.com/ptitSeb/box64.git "$R/build/src/box64"
docker run --rm -u "$(id -u):$(id -g)" -v "$R:/repo" shogunshowdown-portmaster-build bash -c '
  set -e
  cd /repo/build/src/box64 && mkdir -p build-aarch64 && cd build-aarch64
  cmake .. -DARM_DYNAREC=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc -DCMAKE_ASM_COMPILER=aarch64-linux-gnu-gcc \
    -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 >/dev/null
  make -j"$(nproc)" >/dev/null
  aarch64-linux-gnu-strip -o /repo/'"$P"'/box64/box64 box64
  cp /repo/build/src/box64/x64lib/libgcc_s.so.1 /repo/'"$P"'/box64/box64-x86_64-linux-gnu/
  cd /repo/glespass && bash build.sh >/dev/null && cp out/libGL.so.1 /repo/'"$P"'/glespass/
  gcc -shared -fPIC -O2 -o /repo/'"$P"'/steamstub/libsteam_api.so /repo/'"$P"'/steamstub/steamstub.c
  strip /repo/'"$P"'/steamstub/libsteam_api.so
'
ls -la "$R/$P/box64/box64" "$R/$P/glespass/libGL.so.1" "$R/$P/steamstub/libsteam_api.so"
