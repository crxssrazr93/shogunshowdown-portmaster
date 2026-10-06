#!/bin/bash

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

# Knulli names the buttons for games by position, as SDL does: "a" is the bottom button, which
# is labelled B on these devices. Swap a/b and x/y so the buttons act as labelled, like in the
# system menus.
if [ "$CFW_NAME" = "knulli" ]; then
  swap_ab() { sed -E 's/,a:/,@:/g; s/,b:/,a:/g; s/,@:/,b:/g; s/,x:/,@:/g; s/,y:/,x:/g; s/,@:/,y:/g'; }
  export SDL_GAMECONTROLLERCONFIG="$(printf '%s\n' "$SDL_GAMECONTROLLERCONFIG" | swap_ab)"
  swap_ab < "$SDL_GAMECONTROLLERCONFIG_FILE" > /tmp/gamecontrollerdb_ab.txt &&
    export SDL_GAMECONTROLLERCONFIG_FILE=/tmp/gamecontrollerdb_ab.txt
fi

GAMEDIR=/$directory/ports/shogunshowdown
DATADIR=$GAMEDIR/gamedata
cd "$GAMEDIR"

> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

if [ ! -f "$DATADIR/ShogunShowdown.x86_64" ]; then
  pm_message "Game files missing. Copy the Linux Steam build of Shogun Showdown into ports/shogunshowdown/gamedata (see README)."
  sleep 5
  exit 1
fi
$ESUDO chmod a+x "$DATADIR/ShogunShowdown.x86_64" "$GAMEDIR/box64/box64"

# One time setup (again after a game update): patch six game files (OpenGL ES, side panels on
# narrow screens) and compress the large textures (see tools/patchscript). The stamp covers every file the setup changes.
PATCHED_FILES="globalgamemanagers.assets resources.assets sharedassets0.assets sharedassets2.assets
  Resources/unity_builtin_extra sharedassets1.assets resources.assets.resS sharedassets1.assets.resS
  sharedassets2.assets.resS Managed/Assembly-CSharp.dll"
patch_stamp() { (cd "$DATADIR/ShogunShowdown_Data" && stat -c '%s %Y' $PATCHED_FILES 2>/dev/null); }
if [ "$(cat .patch_stamp 2>/dev/null)" != "$(patch_stamp)" ]; then
  export GAMEDIR DATADIR DEVICE_ARCH controlfolder PATCHED_FILES
  chmod +x "$GAMEDIR/tools/patchscript"
  export PATCHER_FILE="$GAMEDIR/tools/patchscript"
  export PATCHER_GAME="Shogun Showdown"
  export PATCHER_TIME="about a minute"
  source "$controlfolder/utils/patcher.txt"
  # tools/patchscript writes the stamp only when every file checked out
  if [ "$(cat .patch_stamp 2>/dev/null)" != "$(patch_stamp)" ]; then
    pm_message "Preparing the game failed. This port needs the current Steam (Linux) build, see the README."
    sleep 8
    pm_finish
    exit 1
  fi
fi

# Steam is replaced by a minimal stand in (no ownership or DRM checks; see steamstub/readme.txt)
# The original is kept outside Plugins/, since Unity loads every library in that folder.
PLUGINS="$DATADIR/ShogunShowdown_Data/Plugins"
[ -f "$PLUGINS/libsteam_api.so.orig" ] && mv -f "$PLUGINS/libsteam_api.so.orig" "$DATADIR/libsteam_api.so.orig"
if ! cmp -s "$GAMEDIR/steamstub/libsteam_api.so" "$PLUGINS/libsteam_api.so"; then
  [ -f "$DATADIR/libsteam_api.so.orig" ] || mv "$PLUGINS/libsteam_api.so" "$DATADIR/libsteam_api.so.orig"
  cp "$GAMEDIR/steamstub/libsteam_api.so" "$PLUGINS/libsteam_api.so"
fi

weston_dir=/tmp/weston
$ESUDO mkdir -p "${weston_dir}"
weston_runtime="weston_pkg_0.2"
if [ ! -f "$controlfolder/libs/${weston_runtime}.squashfs" ]; then
  if [ ! -f "$controlfolder/harbourmaster" ]; then
    pm_message "This port requires the latest PortMaster to run, please go to https://portmaster.games/ for more info."
    sleep 5
    exit 1
  fi
  $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${weston_runtime}.squashfs"
fi
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
  $ESUDO umount "${weston_dir}"
fi
$ESUDO mount "$controlfolder/libs/${weston_runtime}.squashfs" "${weston_dir}"

# The Unity player has an older SDL built in, which numbers a pad's buttons differently from the
# SDL that PortMaster's mapping (SDL_GAMECONTROLLERCONFIG) was written for: key codes from
# BTN_JOYSTICK (0x120) up first, then every lower code. Current SDL numbers them all in ascending
# order, so on pads that also report low codes (the H700 pads report 1, 114 and 115) every button
# index is off. This renumbers a mapping line for the old order, from the pad's key capabilities.
legacy_sdl_mapping() {
  local mapping="$1" name="${1#*,}" dev="" ev wbits=64 n i b w code
  name="${name%%,*}"
  for ev in /sys/class/input/event*/device; do
    [ "$(cat "$ev/name" 2>/dev/null)" = "$name" ] && { dev="$ev"; break; }
  done
  [ -n "$dev" ] || { echo "$mapping"; return; }
  case "$(uname -m)" in aarch64|x86_64) ;; *) wbits=32 ;; esac
  local words=($(cat "$dev/capabilities/key")) codes=()
  n=${#words[@]}
  for ((i = 0; i < n; i++)); do
    w=$((16#${words[n-1-i]}))
    for ((b = 0; b < wbits; b++)); do
      (( (w >> b) & 1 )) && codes+=($((i * wbits + b)))
    done
  done
  local -A old_idx=()
  local o=0 cur=0 out="" f
  for code in "${codes[@]}"; do (( code >= 0x120 )) && old_idx[$code]=$((o++)); done
  for code in "${codes[@]}"; do (( code < 0x120 )) && old_idx[$code]=$((o++)); done
  local -A cur_to_old=()
  for code in "${codes[@]}"; do
    cur_to_old[$cur]=${old_idx[$code]}
    cur=$((cur + 1))
  done
  IFS=, read -ra fields <<< "$mapping"
  for f in "${fields[@]}"; do
    if [[ "$f" =~ ^([^:]+):b([0-9]+)$ ]] && [ -n "${cur_to_old[${BASH_REMATCH[2]}]}" ]; then
      f="${BASH_REMATCH[1]}:b${cur_to_old[${BASH_REMATCH[2]}]}"
    fi
    out+="$f,"
  done
  echo "$out"
}
unity_mapping=""
while IFS= read -r line; do
  [ -n "$line" ] && unity_mapping+="$(legacy_sdl_mapping "$line")"$'\n'
done <<< "$SDL_GAMECONTROLLERCONFIG"

mkdir -p "$GAMEDIR/conf"
if [ "$CFW_NAME" = "muOS" ] && [ -n "$GPTOKEYB2" ]; then
  $GPTOKEYB2 "ShogunShowdown.x86_64" -c "$GAMEDIR/shogunshowdown.gptk" &
else
  $GPTOKEYB "ShogunShowdown.x86_64" -c "$GAMEDIR/shogunshowdown.gptk" &
fi
# Only the game gets the renumbered mapping: gptokeyb is a current SDL program. (westonwrap evals
# its arguments, so a value with spaces cannot be passed to it as VAR=value.)
export SDL_GAMECONTROLLERCONFIG="$unity_mapping"

# westonwrap replaces XDG_RUNTIME_DIR; pass the real one on so the game's audio reaches PipeWire.
REAL_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
pm_platform_helper "$GAMEDIR/box64/box64"
cd "$DATADIR"
# crusty_glx gives the Unity player an OpenGL ES 3 context through GLX; glespass is the libGL.so.1
# that box64's GL wrapper loads, passing the player's GL calls straight to the GLES driver.
# Unity renders on its own thread; GLESPASS_CTXFIX moves the EGL context to that thread when the
# player hands the GLX context over (crusty alone keeps it on the main thread).
# box64 runs libgcc_s.so.1 only as an x86_64 library (it has no native wrapper for it), so the
# port carries that one, as other box64 ports do.
# GLESPASS_VENDOR / GLESPASS_RENDERER hide the GPU name from the player: for a tile based GPU
# (Mali) Unity clears a camera target where this game's last camera draws over the previous
# cameras' output, which leaves only the UI on screen.
$ESUDO env WRAPPED_LIBRARY_PATH="$GAMEDIR/glespass" GLESPASS_CTXFIX=1 \
  GLESPASS_VENDOR=Generic GLESPASS_RENDERER=GLES-device \
  BOX64_LD_LIBRARY_PATH="$GAMEDIR/box64/box64-x86_64-linux-gnu" \
  $weston_dir/westonwrap.sh headless noop kiosk crusty_glx \
  XDG_RUNTIME_DIR="$REAL_XDG_RUNTIME_DIR" HOME="$GAMEDIR/conf" XDG_CONFIG_HOME="$GAMEDIR/conf" \
  "$GAMEDIR/box64/box64" ./ShogunShowdown.x86_64 -screen-fullscreen 1 \
  -screen-width "$DISPLAY_WIDTH" -screen-height "$DISPLAY_HEIGHT" -logFile "$GAMEDIR/player.log"

$ESUDO $weston_dir/westonwrap.sh cleanup
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
  $ESUDO umount "${weston_dir}"
fi
pm_finish
