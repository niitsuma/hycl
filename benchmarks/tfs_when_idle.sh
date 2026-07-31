#!/usr/bin/env bash
# Time the temporal-feature-selection arms once the machine is quiet.
#
# The idle test matches benchmarks/run_when_idle.sh, so the two sets of
# numbers are taken under the same conditions and belong in one table.
#
#   tfs_when_idle.sh OUTPUT_FILE SCM2CPP_LOADER.py [MAX_WAIT_HOURS]
set -u

OUT=${1:?usage: tfs_when_idle.sh OUTPUT_FILE SCM2CPP_LOADER.py [MAX_WAIT_HOURS]}
LOADER=${2:?the ctypes loader that scm2cpp -M generated}
MAX_WAIT=$(python3 -c "print(int(${3:-24} * 3600))")
THRESHOLD=4.0
NEEDED=3
INTERVAL=60

here=$(cd "$(dirname "$0")/.." && pwd)
PY=${PYTHON:-$HOME/venvs/hyclb/bin/python}

quiet=0; waited=0
while (( waited < MAX_WAIT )); do
    load=$(cut -d' ' -f1 /proc/loadavg)
    gpu=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
    gpu=${gpu:-0}
    if awk "BEGIN{exit !($load < $THRESHOLD && $gpu < 10)}"; then
        quiet=$((quiet + 1)); (( quiet >= NEEDED )) && break
    else
        quiet=0
    fi
    sleep $INTERVAL; waited=$((waited + INTERVAL))
done

watch_load() {
    local peak=0
    while :; do
        local l=$(cut -d' ' -f1 /proc/loadavg)
        awk "BEGIN{exit !($l > $peak)}" && peak=$l
        echo "$peak" > "$1"
        sleep 10
    done
}
PEAK=$(mktemp)
watch_load "$PEAK" & WATCHER=$!
trap 'kill $WATCHER 2>/dev/null; rm -f "$PEAK"' EXIT

{
    echo "# Temporal feature selection: hyclb against the C++ Scm2Cpp compiles to"
    echo "# date:      $(date -Is)"
    echo "# cpu:       $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')"
    echo "# cores:     $(nproc)"
    echo "# loadavg:   $(cut -d' ' -f1-3 /proc/loadavg)"
    echo "# loader:    $LOADER"
    if (( quiet >= NEEDED )); then
        echo "# condition: idle (load below $THRESHOLD and GPU below 10% for $NEEDED consecutive minutes)"
    else
        echo "# condition: NOT IDLE -- gave up after $((waited / 3600))h; these numbers are contended"
    fi
    echo
    HYCLB_SCM2CPP_PY="$LOADER" "$PY" -c "
from hyclb.api import cl_load, new_module
m = new_module('tfs'); cl_load('$here/examples/tfs_lasso.lisp', m)
m.timings(5)
m.compare(5)" 2>&1 | grep -vE '^hyclb;'
    echo
    peak=$(cat "$PEAK" 2>/dev/null || echo "?")
    echo "# loadavg at end:  $(cut -d' ' -f1-3 /proc/loadavg)"
    echo "# peak during run: $peak"
    if awk "BEGIN{exit !($peak > $THRESHOLD)}" 2>/dev/null; then
        echo "# WARNING: the load rose above $THRESHOLD while measuring."
        echo "# These numbers describe the background as much as the code."
    fi
} > "$OUT" 2>&1
