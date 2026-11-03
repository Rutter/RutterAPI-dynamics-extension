#!/bin/sh
# All suites on both companies. Companies run in parallel; the suites share a batch, so
# they run one after the other. Logs go to $1 (default: current directory).
mkdir -p "${1:-.}"
out=$(realpath "${1:-.}")
cd "$(dirname "$0")"
rm -f "$out/failed"
for c in usa uae; do
    # A crashed suite prints no result line, so its exit code is what marks the run failed.
    (python3 update_parity.py $c > "$out/update_$c.log" 2>&1 || touch "$out/failed"
     python3 parity.py $c > "$out/create_$c.log" 2>&1 || touch "$out/failed"
     python3 replace_checks.py $c > "$out/replace_$c.log" 2>&1 || touch "$out/failed") &
done
wait
tail -qn 1 "$out"/update_*.log "$out"/create_*.log "$out"/replace_*.log
[ ! -e "$out/failed" ]
