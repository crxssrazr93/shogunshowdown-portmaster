#!/bin/bash
# TEST ONLY (render comparison, tests/compare in the Shogun Showdown port repo). Runs the port's own
# game path (box64, glespass, Westonpack, crusty_glx, 640x480) with the PortCapture helper; scenario,
# run tag and settings come from ports/shogcmp/run.cfg:
#   SCEN=fight TAG=dev_fight_1 [SHOGUN_ASPECT=fill] [SHOGUN_SHARP=1] [RES=640x480]
# The scenario's input script and frame list come from ports/shogcmp/scenarios.sh (a copy of
# tests/compare/scenarios.sh), so the device and the PC runs use the same ones.
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
if [ -d "/opt/system/Tools/PortMaster/" ]; then controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then controlfolder="$XDG_DATA_HOME/PortMaster"
else controlfolder="/roms/ports/PortMaster"; fi
source $controlfolder/control.txt
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls
GAMEDIR=/$directory/ports/shogcmp
DATADIR=$GAMEDIR/gamedata
cd "$GAMEDIR"
exec > >(tee "$GAMEDIR/log.txt") 2>&1
SCEN=fight; TAG=dev; SHOGUN_ASPECT=fill; SHOGUN_SHARP=1; RES=640x480
source "$GAMEDIR/run.cfg"
source "$GAMEDIR/scenarios.sh"
scenario "$SCEN" || { echo "unknown scenario $SCEN"; exit 1; }
OUT="$GAMEDIR/portcap/$TAG"; rm -rf "$OUT"; mkdir -p "$OUT/frames"
rm -rf "$GAMEDIR/home"; mkdir -p "$GAMEDIR/home"       # a fresh home: no saves, so the tutorial runs
echo "scenario $SCEN tag $TAG aspect $SHOGUN_ASPECT sharp $SHOGUN_SHARP res $RES"
echo "$INPUT" > "$OUT/input.txt"; echo "$FRAMES" > "$OUT/frames.txt"
# the installed port keeps libsteam_api.so replaced by its stub; make sure
PLUGINS="$DATADIR/ShogunShowdown_Data/Plugins"
cmp -s "$GAMEDIR/steamstub/libsteam_api.so" "$PLUGINS/libsteam_api.so" || cp "$GAMEDIR/steamstub/libsteam_api.so" "$PLUGINS/libsteam_api.so"
$ESUDO chmod a+x "$DATADIR/ShogunShowdown.x86_64" "$GAMEDIR/box64/box64"
weston_dir=/tmp/weston
$ESUDO mkdir -p "${weston_dir}"
weston_runtime="weston_pkg_0.2"
[[ "$PM_CAN_MOUNT" != "N" ]] && $ESUDO umount "${weston_dir}" 2>/dev/null
$ESUDO mount "$controlfolder/libs/${weston_runtime}.squashfs" "${weston_dir}"
REAL_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
pm_platform_helper "$GAMEDIR/box64/box64"
# real input devices are disabled inside the game by PortCapture (PORTCAP_ONLYPAD), so stick drift
# cannot change the run; no gptokeyb and no SDL controller mapping are needed
cd "$DATADIR"
W=${RES%x*}; H=${RES#*x}
$ESUDO env WRAPPED_LIBRARY_PATH="$GAMEDIR/glespass" GLESPASS_CTXFIX=1 \
  GLESPASS_VENDOR=Generic GLESPASS_RENDERER=GLES-device \
  PORTCAP_DIR="$OUT/frames" PORTCAP_FRAMES="$FRAMES" PORTCAP_SEED=1234 PORTCAP_STATE=1 PORTCAP_TRACE=0 PORTCAP_INPUT="$INPUT" \
  $weston_dir/westonwrap.sh headless noop kiosk crusty_glx \
  BOX64_LOG=1 BOX64_LD_LIBRARY_PATH="$GAMEDIR/box64/box64-x86_64-linux-gnu" \
  BOX64_DYNAREC_BLEEDING_EDGE=0 BOX64_DYNAREC_STRONGMEM=1 BOX64_DYNAREC_BIGBLOCK=2 \
  SHOGUN_ASPECT="$SHOGUN_ASPECT" SHOGUN_SHARP="$SHOGUN_SHARP" \
  XDG_RUNTIME_DIR="$REAL_XDG_RUNTIME_DIR" HOME="$GAMEDIR/home" XDG_CONFIG_HOME="$GAMEDIR/home/.config" \
  "$GAMEDIR/box64/box64" ./ShogunShowdown.x86_64 -screen-fullscreen 1 \
  -screen-width "$W" -screen-height "$H" -logFile "$OUT/player.log"
$ESUDO $weston_dir/westonwrap.sh cleanup
[[ "$PM_CAN_MOUNT" != "N" ]] && $ESUDO umount "${weston_dir}"
pm_finish
