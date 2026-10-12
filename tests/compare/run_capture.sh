#!/bin/bash
# One deterministic capture run (see README.md), following tests/localtest.sh: the game's x86_64
# player under an offscreen Xvfb (no window on the desktop) at 640x480 by default, with a virtual
# gamepad inside bwrap (no real input devices). PortCapture.cs (in all copies) fixes the simulation
# step and the random seeds, feeds the scripted input and writes the frames; the run ends when it
# logs "PortCapture: done".
#
# Usage: tests/compare/run_capture.sh <ref|port|astc> <scenario> <tag> [WxH]
#   ref   cmp-ref   desktop GL (Mesa), the game's original shaders
#   port  cmp-port  a forced GLES 3.2 context (tests/pc/gles_force.so, as crusty_glx gives on the device),
#                   the port's converted shaders
#   astc  cmp-astc  as port, with the textures converted to ASTC 4x4 as the device's setup does
#   scenario        a name from scenarios.sh (default list: fight)
# Env:   WS      workspace holding the cmp-* copies (default ~/Games/steam-ports/shogunshowdown)
#        DISP    X display number (default 9)
#        SEED    PORTCAP_SEED (default 1234)
#        TRACE   1 = per frame trace file (frames/trace.txt)
#        ACTIONS 1 = log the game's input actions and bindings (PORTCAP_ACTIONS)
#        ASPECT, SHARP   SHOGUN_ASPECT (fill|fit) and SHOGUN_SHARP (1|0), default fill and 1 (the port's)
#        FRAMES, INPUT   override the scenario's frame list or input script
#        (the player runs under setarch -R: no address space randomisation, so Mono's address based
#         object hashes, and every Dictionary/HashSet order built on them, repeat from run to run)
# Output: tests/compare/runs/<tag>/frames/*.png (+ .txt state), player.log, game.out
set -u
ulimit -c 0
C="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$C/../.." && pwd)"; T="$R/tests"
FLAVOR="$1"; SCEN="$2"; TAG="$3"; RES="${4:-640x480}"; D=${DISP:-9}
WS="${WS:-$HOME/Games/steam-ports/shogunshowdown}"
case "$FLAVOR" in
  ref)  G="$WS/cmp-ref";  PRE=;;
  port) G="$WS/cmp-port"; PRE="$T/pc/gles_force.so";;
  orig) G="$WS/cmp-orig"; PRE=;;
  astc) G="$WS/cmp-astc"; PRE="$T/pc/gles_force.so";;
  *) echo "ref, port or astc"; exit 2;;
esac
source "$C/scenarios.sh"
scenario "$SCEN" || { echo "unknown scenario $SCEN"; exit 2; }
FRAMES="${FRAMES_OVERRIDE:-$FRAMES}"; INPUT="${INPUT_OVERRIDE:-$INPUT}"
[ -f "$T/pc/gles_force.so" ] || gcc -shared -fPIC -O2 -o "$T/pc/gles_force.so" "$T/pc/gles_force.c" -ldl
OUT="$C/runs/$TAG"; rm -rf "$OUT"; mkdir -p "$OUT/frames"
H="$OUT/home"; mkdir -p "$H"                                   # always a fresh home: no saves
# a lock left by a killed Xvfb is stale when its process is gone
if [ -e "/tmp/.X$D-lock" ] && ! kill -0 "$(tr -d ' ' < /tmp/.X$D-lock)" 2>/dev/null; then rm -f "/tmp/.X$D-lock" "/tmp/.X11-unix/X$D"; fi
while [ -e "/tmp/.X$D-lock" ]; do sleep 0.5; done
unset WAYLAND_DISPLAY; export SDL_VIDEODRIVER=x11 XDG_RUNTIME_DIR=/tmp/xdg-offscreen; mkdir -p -m 700 /tmp/xdg-offscreen
# FMOD crashes enumerating the host's ALSA plugins; one null device is all the game needs
export ALSA_CONFIG_PATH="$C/alsa_null.conf"
Xvfb :$D -screen 0 "$RES"x24 -nolisten tcp >/dev/null 2>&1 & XPID=$!
for i in $(seq 40); do DISPLAY=:$D xdpyinfo >/dev/null 2>&1 && break; sleep 0.5; done
DISPLAY=:$D xdpyinfo >/dev/null 2>&1 || { echo "offscreen X server :$D did not start"; kill -9 $XPID 2>/dev/null; exit 1; }
( sleep 10; while true; do
    W=$(DISPLAY=:$D xdotool search --name "Shogun" 2>/dev/null | head -1)
    [ -n "$W" ] && DISPLAY=:$D xdotool windowfocus "$W" 2>/dev/null; sleep 2; done ) & FPID=$!
cd "$G"
W=${RES%x*}; Hh=${RES#*x}
echo "$INPUT" > "$OUT/input.txt"; echo "$FRAMES" > "$OUT/frames.txt"
PORTCAP_DIR="$OUT/frames" PORTCAP_FRAMES="$FRAMES" PORTCAP_SEED="${SEED:-1234}" PORTCAP_STATE=1 PORTCAP_TRACE="${TRACE:-0}" \
PORTCAP_ACTIONS="${ACTIONS:-0}" PORTCAP_NORESEED="${NORESEED:-0}" PORTCAP_NOPARTICLES="${NOPARTICLES:-0}" PORTCAP_INPUT="$INPUT" SHOGUN_ASPECT="${ASPECT:-fill}" SHOGUN_SHARP="${SHARP:-1}" \
DISPLAY=:$D HOME="$H" XDG_CONFIG_HOME="$H/.config" LD_PRELOAD="$PRE" \
  bwrap --die-with-parent --dev-bind / / --tmpfs /dev/input \
  setarch "$(uname -m)" -R ./ShogunShowdown.x86_64 -screen-width "$W" -screen-height "$Hh" -screen-fullscreen 1 -logFile "$OUT/player.log" \
  > "$OUT/game.out" 2>&1 & GPID=$!
status=timeout
for i in $(seq ${MAXWAIT:-600}); do
  grep -q "PortCapture: done" "$OUT/player.log" 2>/dev/null && { status=done; break; }
  kill -0 $GPID 2>/dev/null || { status=exited; break; }
  sleep 1
done
P=$(pgrep -P $GPID | head -1)
kill -9 $FPID $P $GPID 2>/dev/null; wait $FPID $GPID 2>/dev/null
kill -9 $XPID 2>/dev/null; wait $XPID 2>/dev/null; rm -f "/tmp/.X$D-lock" "/tmp/.X11-unix/X$D"
echo "$TAG: $status, $(ls "$OUT/frames" | grep -c png) frames"
[ "$status" = done ]
