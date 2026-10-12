#!/bin/bash
# The whole comparison (see README.md). For each scenario (idle, shoot): RUNS (default 3) runs of
# cmp-ref and of cmp-port, a determinism check of the first two of each, the first ref run against the
# first port run, all runs against each other (best pair per frame), then the shader log scan, with
# everything also written to tests/compare/out/summary.txt. About a minute per run. Needs
# make_copies.sh to have run.
# Usage: tests/compare/run_all.sh [scenario ...]      (default: shoot idle)
C="$(cd "$(dirname "$0")" && pwd)"
SCENS=("$@"); [ ${#SCENS[@]} = 0 ] && SCENS=(shoot idle)
mkdir -p "$C/out"; : > "$C/out/summary.txt"
for s in "${SCENS[@]}"; do
  find "$C/runs" -maxdepth 1 -type d \( -name "ref_${s}_*" -o -name "port_${s}_*" \) -exec rm -rf {} + 2>/dev/null
  for f in ref port; do for r in $(seq 1 ${RUNS:-3}); do "$C/run_capture.sh" $f $s ${f}_${s}_$r || echo "run ${f}_${s}_$r did not finish"; done; done
  {
    echo "##### scenario $s: determinism, cmp-ref twice"
    "$C/compare.py" ref_${s}_1 ref_${s}_2 --name det_ref_$s --strict
    echo; echo "##### scenario $s: determinism, cmp-port twice"
    "$C/compare.py" port_${s}_1 port_${s}_2 --name det_port_$s --strict
    echo; echo "##### scenario $s: first cmp-ref run (A) against first cmp-port run (B)"
    "$C/compare.py" ref_${s}_1 port_${s}_1 --name ref_vs_port_$s
    echo; echo "##### scenario $s: all runs, best ref/port pair per frame"
    "$C/compare_runs.py" $s
    echo
  } 2>&1 | tee -a "$C/out/summary.txt"
done
{ echo "##### shader log scan"; "$C/log_scan.py" $(cd "$C/runs" && ls | grep -E "^(ref|port)_"); } 2>&1 | tee -a "$C/out/summary.txt"
