#!/bin/bash
# Frame rate A/B on the Knulli test device (RG35XX H). Needs the port installed with the game set
# up and a saved run in progress (the script continues it). Deploys a launcher variant with extra
# environment variables and player arguments, then measures presented fps on the title screen and
# in the run's fight, and prints the busiest threads.
# Usage: tests/device/perf_run.sh "<VAR=value ...>" "<player arguments>"
#   e.g. tests/device/perf_run.sh "BOX64_DYNAREC_BIGBLOCK=3" ""
# Put the plain launcher back afterwards: scp "port/Shogun Showdown.sh" to the device.
set -u
D="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$D/../.." && pwd)"
HOST=root@${KNULLI_HOST:?set KNULLI_HOST to the device address}
ENVX="$1"; ARGS="${2:-}"
L=$(mktemp)
sed "s|GLESPASS_CTXFIX=1 |GLESPASS_CTXFIX=1 $ENVX |; s| -logFile | $ARGS -logFile |" "$R/port/Shogun Showdown.sh" > "$L"
"$D/knulli_stop.sh" '^[.]/ShogunShowdown' '[S]hogun Showdown.sh' >/dev/null
sshpass -f ~/.ssh/knulli.pass scp -q "$L" "$HOST:/userdata/roms/ports/Shogun Showdown.sh"; rm -f "$L"
sshpass -f ~/.ssh/knulli.pass scp -q "$D/devpad.py" "$D/fbfps.py" "$HOST:/tmp/"
"$D/knulli.sh" 'curl -s -X POST -d "/userdata/roms/ports/Shogun Showdown.sh" localhost:1234/launch; sleep 90
echo "title $(python3 /tmp/fbfps.py 5)"
python3 /tmp/devpad.py "hold A 0.3; wait 4; hold B 0.3; wait 45" >/dev/null
P=$(pgrep -f "^./ShogunShowdown.x86_64") || { echo "game exited"; exit 1; }
echo "fight $(python3 /tmp/fbfps.py 10)"
for t in /proc/$P/task/*; do echo "$(awk "{print \$14+\$15}" $t/stat) $(cat $t/comm)"; done | sort -rn | head -4'
