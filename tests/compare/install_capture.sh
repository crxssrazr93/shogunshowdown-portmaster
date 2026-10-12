#!/bin/bash
# Compiles PortCapture.cs against the game's own class libraries and injects it (capture_inject.cs,
# Mono.Cecil) into the Managed folder of cmp-ref, cmp-port and cmp-astc, identically. Run by
# make_copies.sh; run it alone after changing PortCapture.cs (the unpatched assemblies are kept as
# Managed/*.dll.nocap and are always the input).
# Usage: tests/compare/install_capture.sh [workspace]
set -e
C="$(cd "$(dirname "$0")" && pwd)"
WS="$(cd "${1:-$HOME/Games/steam-ports/shogunshowdown}" && pwd)"
CECIL="${CECIL:-$(ls -d /usr/lib/mono/gac/Mono.Cecil/0.11*/ | tail -1)Mono.Cecil.dll}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
M="$WS/cmp-port/ShogunShowdown_Data/Managed"
# the game's mscorlib, not the host's: it lacks newer overloads
mcs -target:library -noconfig -nostdlib -r:"$M/mscorlib.dll" -r:"$M/System.dll" -r:"$M/System.Core.dll" -r:"$M/netstandard.dll" \
    -r:"$M/UnityEngine.CoreModule.dll" -r:"$M/UnityEngine.ParticleSystemModule.dll" \
    -r:"$M/UnityEngine.ImageConversionModule.dll" -r:"$M/Unity.InputSystem.dll" -r:"$M/UnityEngine.JSONSerializeModule.dll" \
    -r:"$M/UnityEngine.Physics2DModule.dll" -r:"$M/UnityEngine.InputLegacyModule.dll" -out:"$W/PortCapture.dll" "$C/PortCapture.cs"
cp "$CECIL" "$W/"; mcs -r:"$CECIL" -out:"$W/capture_inject.exe" "$C/capture_inject.cs"
for d in cmp-ref cmp-port cmp-astc; do
  [ -d "$WS/$d" ] || continue
  PD="$WS/$d/ShogunShowdown_Data"
  cp "$W/PortCapture.dll" "$PD/Managed/"
  mono "$W/capture_inject.exe" "$PD/Managed" "$PD/Managed/PortCapture.dll"
done
echo "PortCapture installed in the cmp-* copies"
