#!/bin/bash
# Zips port/ into shogunshowdown.zip, the layout PortMaster installs into ports/. Like PortMaster's
# tools/build_release.py, the metadata (port.json, gameinfo.xml, images) goes into the port folder
# and README.md becomes shogunshowdown.md.
set -e
R="$(cd "$(dirname "$0")/.." && pwd)"
for f in box64/box64 glespass/libGL.so.1 box64/box64-x86_64-linux-gnu/libgcc_s.so.1; do
  [ -f "$R/port/shogunshowdown/$f" ] || { echo "missing $f: run build/build.sh first"; exit 1; }
done
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cd "$R/port"
# Release zips carry the "# PORTMASTER:" line that PortMaster's own build adds; without it
# harbourmaster inserts it into the launcher on its first runtime download, even while it runs.
{ head -n 1 "Shogun Showdown.sh"; echo "# PORTMASTER: shogunshowdown.zip, Shogun Showdown.sh"; tail -n +2 "Shogun Showdown.sh"; } > "$stage/Shogun Showdown.sh"
chmod 755 "$stage/Shogun Showdown.sh"
cp -r shogunshowdown "$stage/"
rm -rf "$stage"/shogunshowdown/{conf,astc,log.txt,log.prev.txt,setup_log.txt,setup_log.prev.txt,player.log,.patch_stamp}
find "$stage/shogunshowdown/gamedata" -mindepth 1 ! -name 'Put Linux game files here' -exec rm -rf {} +
find "$stage" -name __pycache__ -prune -exec rm -rf {} +  # Python caches from local test runs
cp port.json gameinfo.xml screenshot.png cover.png "$stage/shogunshowdown/"
cp README.md "$stage/shogunshowdown/shogunshowdown.md"
rm -f "$R/shogunshowdown.zip"
(cd "$stage" && zip -9 -r -q -X "$R/shogunshowdown.zip" .)
ls -la "$R/shogunshowdown.zip"
