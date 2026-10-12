#!/bin/bash
# Builds the three game copies the comparison runs (see README.md), from the untouched Steam Linux
# build, following build/make_patches.sh and port/shogunshowdown/tools/patchscript:
#   cmp-ref   everything the port does EXCEPT setup/gles_shaders2021.py and the ASTC step: the game's
#             original OpenGLCore shader programs, audio, UI and PortSharp patches as shipped
#   cmp-port  everything except the ASTC step: what the xdelta patches give (the six patched files are
#             checked against the MD5s in patchscript). Isolates the shader conversion.
#   cmp-astc  cmp-port plus the setup's step 7 (tools/astc_textures.py with an x86_64 astcenc)
# Then, identically in all three, the test only PortCapture helper (PortCapture.cs). Nothing under
# port/, setup/ or build/ is touched.
#
# Usage: tests/compare/make_copies.sh [workspace]     (default ~/Games/steam-ports/shogunshowdown; needs
#        linux/ShogunShowdown_Data there: the untouched Steam build)
# Env:   PYTHON   python with UnityPy, lz4 (setup/requirements.txt); default: the steam-ports venv-unity
#                 or tests/compare/.venv (created on first use)
#        ASTCENC  x86_64 astcenc (default ~/Games/steam-ports/tools/astcenc/bin/astcenc-avx2)
set -e
C="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$C/../.." && pwd)"
WS="$(cd "${1:-$HOME/Games/steam-ports/shogunshowdown}" && pwd)"
SRC="$WS/linux"
[ -d "$SRC/ShogunShowdown_Data" ] || { echo "need $SRC/ShogunShowdown_Data (the untouched Steam Linux build)"; exit 1; }
ASTCENC="${ASTCENC:-$HOME/Games/steam-ports/tools/astcenc/bin/astcenc-avx2}"
if [ -z "$PYTHON" ]; then
  PYTHON="$HOME/Games/steam-ports/tools/venv-unity/bin/python"
  if ! "$PYTHON" -c 'import UnityPy, lz4' 2>/dev/null; then
    PYTHON="$C/.venv/bin/python"
    if ! "$PYTHON" -c 'import UnityPy, lz4' 2>/dev/null; then
      python3 -m venv "$C/.venv" && "$C/.venv/bin/pip" install -q -r "$R/setup/requirements.txt" || exit 1
    fi
  fi
fi
CECIL="${CECIL:-$(ls -d /usr/lib/mono/gac/Mono.Cecil/0.11*/ | tail -1)Mono.Cecil.dll}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
PS="$R/port/shogunshowdown/tools/patchscript"
FILES=(globalgamemanagers.assets resources.assets sharedassets0.assets sharedassets2.assets Resources/unity_builtin_extra
  Managed/Assembly-CSharp.dll)

echo "== the source is the supported Steam build"
for f in "${FILES[@]}"; do
  want=$(grep -E "^(FILES=\")?$f [0-9a-f]{32} [0-9a-f]{32}" "$PS" | head -1 | cut -d' ' -f2)
  got=$(md5sum < "$SRC/ShogunShowdown_Data/$f" | cut -c1-32)
  [ "$want" = "$got" ] || { echo "  DIFF $f (want $want, got $got)"; exit 1; }
done
echo "  ok"

echo "== Cecil patchers"
mkdir -p "$W/uip" && cp "$CECIL" "$W/uip/"
mcs -r:"$CECIL" -out:"$W/uip/ui_aspect_patch.exe" "$R/setup/ui_aspect_patch.cs"
mcs -r:"$CECIL" -out:"$W/uip/sharp_inject.exe" "$R/setup/sharp_inject.cs"

# build <dest> <with shaders: 1|0>   (the steps of build/make_patches.sh on a runnable game folder)
build() {
  local dest="$1" shaders="$2" PD="$1/ShogunShowdown_Data"
  echo "== $(basename "$dest") (shader conversion: $shaders)"
  rm -rf "$dest"; mkdir -p "$dest"
  cp -r "$SRC/ShogunShowdown_Data" "$PD"
  cp "$SRC/ShogunShowdown.x86_64" "$SRC/UnityPlayer.so" "$dest/"
  "$PYTHON" "$R/setup/audio_loadtype.py" "$PD"
  [ "$shaders" = 1 ] && "$PYTHON" "$R/setup/gles_shaders2021.py" "$PD"
  mono "$W/uip/ui_aspect_patch.exe" "$SRC/ShogunShowdown_Data/Managed" "$PD/Managed/Assembly-CSharp.dll" \
    "$R/port/shogunshowdown/patch/PortSharp.dll"
  cp "$R/port/shogunshowdown/patch/PortSharp.dll" "$PD/Managed/"
  mono "$W/uip/sharp_inject.exe" "$PD/Managed/Assembly-CSharp.dll" "$PD/Managed/PortSharp.dll" "$W/uip/Assembly-CSharp.dll"
  mv -f "$W/uip/Assembly-CSharp.dll" "$PD/Managed/Assembly-CSharp.dll"
  # the launcher: Steam stub in place of libsteam_api.so (the original is kept next to the game)
  mv "$PD/Plugins/libsteam_api.so" "$dest/libsteam_api.so.orig"
  cp "$R/port/shogunshowdown/steamstub/libsteam_api.so" "$PD/Plugins/libsteam_api.so"
  chmod +x "$dest/ShogunShowdown.x86_64"
}
build "$WS/cmp-ref" 0
build "$WS/cmp-port" 1

echo "== integrity: cmp-port must match the MD5s patchscript expects after the xdelta patches"
bad=0
for f in "${FILES[@]}"; do
  want=$(grep -E "^(FILES=\")?$f [0-9a-f]{32} [0-9a-f]{32}" "$PS" | head -1 | cut -d' ' -f3 | tr -d '"')
  got=$(md5sum < "$WS/cmp-port/ShogunShowdown_Data/$f" | cut -c1-32)
  [ "$want" = "$got" ] && echo "  ok   $f" || { echo "  DIFF $f (want $want, got $got)"; bad=1; }
done
[ $bad = 0 ] || { echo "cmp-port does not match the shipped patch results"; exit 1; }

echo "== cmp-astc: cmp-port plus setup step 7 (astc_textures.py, $(basename "$ASTCENC"))"
[ -x "$ASTCENC" ] || { echo "no astcenc at $ASTCENC"; exit 1; }
rm -rf "$WS/cmp-astc"; cp -r "$WS/cmp-port" "$WS/cmp-astc"
"$PYTHON" "$R/port/shogunshowdown/tools/astc_textures.py" "$WS/cmp-astc/ShogunShowdown_Data" "$ASTCENC" \
  "$R/port/shogunshowdown/tools/astc_manifest.json" "$W/astc"

echo "== PortCapture (test helper), identically in all three copies"
"$C/install_capture.sh" "$WS"

echo "== files that differ between the copies"
for pair in "cmp-ref cmp-port" "cmp-port cmp-astc"; do
  set -- $pair
  (cd "$WS/$1" && find . -type f | sort) > "$W/l1"; (cd "$WS/$2" && find . -type f | sort) > "$W/l2"
  # the ASTC step only adds its markers (<file>.astc_done)
  if ! diff "$W/l1" "$W/l2" | grep -E '^[<>]' | grep -v -E '\.astc_done$' | cmp -s - /dev/null; then
    echo "file lists of $1 and $2 differ:"; diff "$W/l1" "$W/l2"; exit 1; fi
  grep -v '\.astc_done$' "$W/l2" > "$W/l2f"; mv "$W/l2f" "$W/l2"
  diff=$(cd "$WS/$1" && while read -r f; do cmp -s "$f" "$WS/$2/$f" || echo "$f"; done < "$W/l1")
  echo "  $1 vs $2:"; echo "$diff" | sed 's/^/    /'
  if [ "$1" = cmp-ref ]; then
    allowed='^\./ShogunShowdown_Data/(globalgamemanagers.assets|resources.assets|sharedassets0.assets|sharedassets2.assets|Resources/unity_builtin_extra)$'
  else
    allowed='^\./ShogunShowdown_Data/(sharedassets[0-9]+.assets(.resS|.astc_done)?|resources.assets(.resS|.astc_done)?)$'
  fi
  if echo "$diff" | grep -v -E "$allowed" | grep -q .; then echo "UNEXPECTED difference above"; exit 1; fi
done
echo "done: $WS/cmp-ref, cmp-port and cmp-astc"
