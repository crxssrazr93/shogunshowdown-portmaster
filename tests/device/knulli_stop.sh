#!/bin/bash
# Stop the running port on the Knulli test device: ES emukill, then the game process (TERM, then
# KILL), then wait for its launcher to exit. Usage: knulli_stop.sh <game process pattern> <launcher pattern>
# Patterns use the [x] bracket trick so pgrep does not match this shell (see memory pkill-self-match).
# Both patterns are required: an empty pattern makes pgrep -f match every process, and the loop
# below then kills the whole system, sshd included (this happened twice; the device needed a reboot).
if [ -z "$1" ] || [ -z "$2" ] || [ ${#1} -lt 4 ] || [ ${#2} -lt 4 ]; then
  echo "usage: knulli_stop.sh <game process pattern> <launcher pattern> (both required, 4+ chars)" >&2
  exit 2
fi
exec "$(dirname "$0")/knulli.sh" "
curl -s -X POST localhost:1234/emukill >/dev/null
for sig in TERM TERM KILL; do
  P=\$(pgrep -f '$1'); [ -z \"\$P\" ] && break
  kill -\$sig \$P; sleep 3
done
for i in \$(seq 30); do pgrep -f '$2' >/dev/null || break; sleep 1; done
pgrep -fa '$1|$2' | cut -c1-80 || true"
