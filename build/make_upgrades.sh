#!/bin/bash
# Makes the upgrade patches for installs prepared by an older release: for every patched version of a
# game file that an earlier commit shipped, patch/<file>.<old patched MD5>.xdelta turns it into the
# current one (tools/patchscript applies it in place of the patch from the original). Run after
# build/make_patches.sh, with the same untouched copy of the Steam Linux build. Needs docker.
# Usage: build/make_upgrades.sh <folder holding ShogunShowdown_Data>
set -e
R="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$(cd "$1" && pwd)/ShogunShowdown_Data"
P="$R/port/shogunshowdown/patch"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
find "$P" -name '*.[0-9a-f]*[0-9a-f].xdelta' -delete  # earlier upgrade patches (names end in an MD5)
FILES=(globalgamemanagers.assets resources.assets sharedassets0.assets sharedassets2.assets Resources/unity_builtin_extra
  Managed/Assembly-CSharp.dll)
for f in "${FILES[@]}"; do
  b=$(basename "$f")
  mkdir -p "$W/$b"
  cp "$SRC/$f" "$W/$b/orig"
  cp "$P/$b.xdelta" "$W/$b/current.xd"
  # every earlier version of this file's patch (committed ones; the working copy is the current one)
  for c in $(git -C "$R" log --format=%h -- "port/shogunshowdown/patch/$b.xdelta"); do
    git -C "$R" show "$c:port/shogunshowdown/patch/$b.xdelta" > "$W/$b/$c.xd"
    cmp -s "$W/$b/$c.xd" "$W/$b/current.xd" && rm "$W/$b/$c.xd"
  done
done
docker run --rm -v "$W:/w" -v "$P:/out" ubuntu:20.04 bash -c '
  apt-get update -qq >/dev/null && apt-get install -y -qq xdelta3 >/dev/null 2>&1
  for d in /w/*/; do
    b=$(basename "$d")
    xdelta3 -d -f -s "$d/orig" "$d/current.xd" "$d/current"
    for x in "$d"/*.xd; do
      [ "$(basename "$x")" = current.xd ] && continue
      xdelta3 -d -f -s "$d/orig" "$x" "$d/old"
      s=$(md5sum < "$d/old" | cut -c1-32)
      cmp -s "$d/old" "$d/current" && continue
      xdelta3 -9 -e -f -s "$d/old" "$d/current" "/out/$b.$s.xdelta"
      echo "$b: upgrade from $s"
    done
  done
  chown -R '"$(id -u):$(id -g)"' /out'
