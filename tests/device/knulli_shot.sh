#!/bin/bash
# Screenshot of the Knulli device's screen: knulli_shot.sh <out.png>
# fbgrab shows only white for GL output; the raw /dev/fb0 dump (BGRA, 640 wide, several pages)
# holds the displayed frame in its first page (/sys/class/graphics/fb0/pan selects the page).
set -e
OUT="$1"; T=$(mktemp -d)
"$(dirname "$0")/knulli.sh" 'cat /sys/class/graphics/fb0/virtual_size /sys/class/graphics/fb0/pan; dd if=/dev/fb0 of=/tmp/fb.raw bs=1M 2>/dev/null' > "$T/info"
sshpass -f "$HOME/.ssh/knulli.pass" scp -q root@${KNULLI_HOST:?set KNULLI_HOST to the device address}:/tmp/fb.raw "$T/fb.raw"
W=$(head -1 "$T/info" | cut -d, -f1); PANY=$(sed -n 2p "$T/info" | cut -d, -f2)
H=$(( $(stat -c %s "$T/fb.raw") / (W * 4) )); VH=$(head -1 "$T/info" | cut -d, -f2)
magick -size ${W}x${H} -depth 8 bgra:"$T/fb.raw" -alpha off -crop ${W}x$((VH / 2))+0+${PANY} +repage "$OUT"
rm -rf "$T"
