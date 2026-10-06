#!/bin/bash
# Regenerates the game file changes the port ships, from an untouched copy of the Steam Linux build:
#   port/shogunshowdown/patch/*.xdelta           (setup/audio_loadtype.py + setup/gles_shaders2021.py)
#   port/shogunshowdown/tools/astc_manifest.json (setup/astc_manifest.py)
#   the MD5s in port/shogunshowdown/tools/patchscript
# Needs python3 with UnityPy and lz4 (setup/requirements.txt) and docker (xdelta3 from Ubuntu 20.04).
# Usage: build/make_patches.sh <folder holding ShogunShowdown_Data>
set -e
R="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$(cd "$1" && pwd)/ShogunShowdown_Data"
PY="${PYTHON:-python3}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
FILES=(globalgamemanagers.assets resources.assets sharedassets0.assets sharedassets2.assets Resources/unity_builtin_extra)

cp -r "$SRC" "$W/patched"
"$PY" "$R/setup/audio_loadtype.py" "$W/patched"
"$PY" "$R/setup/gles_shaders2021.py" "$W/patched"
mkdir -p "$W/orig/Resources"
for f in "${FILES[@]}"; do cp "$SRC/$f" "$W/orig/$f"; done

docker run --rm -v "$W:/w" -v "$R/port/shogunshowdown/patch:/out" ubuntu:20.04 bash -c "
  apt-get update -qq >/dev/null && apt-get install -y -qq xdelta3 >/dev/null 2>&1
  for f in ${FILES[*]}; do xdelta3 -9 -e -f -s /w/orig/\$f /w/patched/\$f /out/\$(basename \$f).xdelta; done
  chown -R $(id -u):$(id -g) /out"

S="$R/port/shogunshowdown/tools/patchscript"
for f in "${FILES[@]}"; do
  orig=$(md5sum < "$SRC/$f" | cut -c1-32)
  new=$(md5sum < "$W/patched/$f" | cut -c1-32)
  sed -i "s|$f [0-9a-f]\{32\} [0-9a-f]\{32\}|$f $orig $new|" "$S"
done
"$PY" "$R/setup/astc_manifest.py" "$W/patched" "$SRC" > "$R/port/shogunshowdown/tools/astc_manifest.json"
grep -A5 '^FILES=' "$S"
ls -la "$R/port/shogunshowdown/patch"
