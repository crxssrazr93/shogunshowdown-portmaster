#!/bin/bash
# The whole comparison (see README.md). For each scenario (default: fight): RUNS (default 2) runs of
# cmp-ref, cmp-port and cmp-astc, two games at a time (displays 9 and 10), then a determinism check of
# each build against itself (first two runs, strict), ref against port, port against astc and ref
# against astc (first runs, and the best pair over all runs), then the shader log scan; everything is
# also written to tests/compare/out/summary_<scenario>.txt. Needs make_copies.sh to have run.
# Usage: tests/compare/run_all.sh [scenario ...]
# Env:   RUNS=2, SKIP_EXISTING=1 (keep finished runs), RES=640x480 (suffixes the scenario: fight_720x720)
C="$(cd "$(dirname "$0")" && pwd)"
SCENS=("$@"); [ ${#SCENS[@]} = 0 ] && SCENS=(fight)
RES="${RES:-640x480}"
mkdir -p "$C/out"
for s in "${SCENS[@]}"; do
  tag="$s"; [ "$RES" != 640x480 ] && tag="${s}_$RES"
  jobs_=(); for r in $(seq 1 ${RUNS:-2}); do for f in ref port astc; do
    if [ "${SKIP_EXISTING:-0}" = 1 ] && grep -q "PortCapture: done" "$C/runs/${f}_${tag}_$r/player.log" 2>/dev/null; then continue; fi
    jobs_+=("$f $r"); done; done
  i=0
  while [ $i -lt ${#jobs_[@]} ]; do
    pids=()
    for k in 0 1; do
      [ $((i + k)) -lt ${#jobs_[@]} ] || continue
      set -- ${jobs_[$((i + k))]}; f=$1; r=$2; name=${f}_${tag}_$r
      DISP=$((9 + k)) "$C/run_capture.sh" $f $s $name $RES & pids+=($!)
    done
    for p in "${pids[@]}"; do wait $p || echo "a run did not finish"; done
    i=$((i + 2))
  done
  {
    for f in ref port astc; do
      [ -d "$C/runs/${f}_${tag}_2" ] || continue          # RUNS=1: no determinism check
      echo "##### $tag: determinism, cmp-$f twice (strict)"
      "$C/compare.py" ${f}_${tag}_1 ${f}_${tag}_2 --name det_${f}_$tag --strict; echo
    done
    for pair in "ref port" "port astc" "ref astc"; do
      set -- $pair
      echo "##### $tag: first $1 run (A) against first $2 run (B)"
      "$C/compare.py" ${1}_${tag}_1 ${2}_${tag}_1 --name ${1}_vs_${2}_$tag; echo
      [ -d "$C/runs/${1}_${tag}_2" ] && {
        echo "##### $tag: all runs, best $1/$2 pair per frame"
        "$C/compare_runs.py" $tag $1 $2; echo; }
    done
    echo "##### shader log scan"
    "$C/log_scan.py" $(cd "$C/runs" && ls | grep -E "^(ref|port|astc)_${tag}_")
  } 2>&1 | tee "$C/out/summary_$tag.txt"
done
