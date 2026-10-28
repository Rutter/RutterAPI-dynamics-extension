#!/bin/sh
# Both suites on both companies. Companies run in parallel; the two suites share a batch, so
# they run one after the other. Logs go to $1 (default: current directory).
out=$(realpath "${1:-.}")
cd "$(dirname "$0")"
for c in usa uae; do
    (python3 update_parity.py $c > "$out/update_$c.log" 2>&1
     python3 parity.py $c > "$out/create_$c.log" 2>&1) &
done
wait
tail -qn 1 "$out"/update_*.log "$out"/create_*.log
! grep -q ": FAIL$" "$out"/update_*.log "$out"/create_*.log
