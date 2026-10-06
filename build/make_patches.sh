#!/bin/bash
# Regenerates the game file changes the port ships, from an untouched copy of the Steam Linux build:
#   port/shogunshowdown/patch/*.xdelta           (setup/audio_loadtype.py, setup/gles_shaders2021.py,
#                                                 setup/ui_aspect_patch.cs)
#   port/shogunshowdown/tools/astc_manifest.json (setup/astc_manifest.py)
#   the MD5s in port/shogunshowdown/tools/patchscript
# Needs python3 with UnityPy and lz4 (setup/requirements.txt), mono with mcs and Mono.Cecil 0.11, and
# docker (xdelta3 from Ubuntu 20.04).
# Usage: build/make_patches.sh <folder holding ShogunShowdown_Data>
set -e
R="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$(cd "$1" && pwd)/ShogunShowdown_Data"
PY="${PYTHON:-python3}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
FILES=(globalgamemanagers.assets resources.assets sharedassets0.assets sharedassets2.assets Resources/unity_builtin_extra
  Managed/Assembly-CSharp.dll)

cp -r "$SRC" "$W/patched"
"$PY" "$R/setup/audio_loadtype.py" "$W/patched"
"$PY" "$R/setup/gles_shaders2021.py" "$W/patched"
CECIL="${CECIL:-$(ls -d /usr/lib/mono/gac/Mono.Cecil/0.11*/ | tail -1)Mono.Cecil.dll}"
mkdir -p "$W/uip" && cp "$CECIL" "$W/uip/"
mcs -r:"$CECIL" -out:"$W/uip/ui_aspect_patch.exe" "$R/setup/ui_aspect_patch.cs"
mono "$W/uip/ui_aspect_patch.exe" "$SRC/Managed" "$W/patched/Managed/Assembly-CSharp.dll"
mkdir -p "$W/orig/Resources" "$W/orig/Managed"
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
