#!/bin/bash
# Device-like test on an x86_64 Linux PC: the game's own x86_64 player on an OpenGL ES 3.2 context
# (tests/pc/gles_force.so makes Mesa create GLES contexts, as crusty_glx does on the device), with
# the port's patched data, a rootful Xwayland at a handheld resolution and a scripted virtual
# gamepad (tests/vpad.py). The game runs in bwrap with only the virtual pad under /dev/input.
#
# Usage: tests/localtest.sh <WxH> "<vpad script>" [tag]
# Env:   GAME_DIR  a copy of the game with the port's setup applied (default: port/shogunshowdown/gamedata)
#        DISP      X display number for the test server (default 9)
#        FRESH=1   start from an empty home (no saves)
# Output: tests/out/<tag>/ with screenshots, player.log and rss.log; prints peak RSS.
# The game ignores input until its title intro has finished (about 45 s on a PC).
set -u
ulimit -c 0
T="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$T/.." && pwd)"
G="${GAME_DIR:-$R/port/shogunshowdown/gamedata}"
RES="${1:-640x480}"; SCRIPT="$2"; TAG="${3:-run}"; D=${DISP:-9}
[ -f "$T/pc/gles_force.so" ] || gcc -shared -fPIC -O2 -o "$T/pc/gles_force.so" "$T/pc/gles_force.c" -ldl
OUT="$T/out/$TAG"; mkdir -p "$OUT"; rm -f "$OUT"/*.png "$OUT"/rss.log
H="$T/out/home-$TAG"; [ "${FRESH:-0}" = 1 ] && rm -rf "$H"; mkdir -p "$H"
while [ -e "/tmp/.X$D-lock" ]; do sleep 0.5; done
Xwayland :$D -geometry "$RES" -decorate >/dev/null 2>&1 & XPID=$!
for i in $(seq 40); do DISPLAY=:$D xdpyinfo >/dev/null 2>&1 && break; sleep 0.5; done
before=$(ls /dev/input/)
SHOT_CMD="DISPLAY=:$D import -window root $OUT/{name}.png 2>/dev/null" python3 "$T/vpad.py" "wait 2; $SCRIPT" & VPID=$!
sleep 2
new=$(comm -13 <(echo "$before" | sort) <(ls /dev/input/ | sort))
binds=(); for n in $new; do binds+=(--dev-bind "/dev/input/$n" "/dev/input/$n"); done
# Unity's Input System only takes input while its window has focus
( sleep 20; W=$(DISPLAY=:$D xdotool search --name "Shogun" 2>/dev/null | head -1); [ -n "$W" ] && DISPLAY=:$D xdotool windowfocus "$W" ) &
cd "$G"
W=${RES%x*}; Hh=${RES#*x}
DISPLAY=:$D HOME="$H" XDG_CONFIG_HOME="$H/.config" LD_PRELOAD="$T/pc/gles_force.so" \
  bwrap --die-with-parent --dev-bind / / --tmpfs /dev/input "${binds[@]}" \
  ./ShogunShowdown.x86_64 -screen-width "$W" -screen-height "$Hh" -screen-fullscreen 1 -logFile "$OUT/player.log" \
  > "$OUT/game.out" 2>&1 & GPID=$!
( while kill -0 $GPID 2>/dev/null; do
    P=$(pgrep -P $GPID | head -1)
    [ -n "$P" ] && awk -v t="$SECONDS" '/VmRSS/{r=$2}/VmSwap/{s=$2}END{print t"s rss+swap="int((r+s)/1024)"MB"}' /proc/$P/status 2>/dev/null
    sleep 3; done > "$OUT/rss.log" ) &
wait $VPID
P=$(pgrep -P $GPID | head -1)
PEAK=$(awk '/VmHWM/{print int($2/1024)}' /proc/$P/status 2>/dev/null)
[ -n "$P" ] && kill $P 2>/dev/null; for i in $(seq 20); do kill -0 $GPID 2>/dev/null || break; sleep 0.5; done
kill -9 $GPID $P 2>/dev/null; wait $GPID 2>/dev/null; kill $XPID 2>/dev/null; wait $XPID 2>/dev/null
echo "peakRSS=${PEAK}MB files: $(ls "$OUT" | grep png | tr '\n' ' ')"
