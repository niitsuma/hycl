#!/usr/bin/env bash
# Wait for the machine to go quiet, then run a benchmark.
#
# The CPU arms of the LASSO benchmark are single-threaded and the GPU arms queue
# behind whatever else is resident, so anything else running inflates them.  This
# waits for a sustained low load average AND a quiet GPU before measuring, and
# records the conditions alongside the numbers.
#
#   benchmarks/run_when_idle.sh OUTPUT_FILE [THRESHOLD] [MAX_WAIT_HOURS]
set -u

OUT=${1:?usage: run_when_idle.sh OUTPUT_FILE [THRESHOLD] [MAX_WAIT_HOURS]}
THRESHOLD=${2:-4.0}
MAX_WAIT=$(python3 -c "print(int(${3:-24} * 3600))")
NEEDED=3          # consecutive quiet samples, one minute apart
INTERVAL=60

here=$(cd "$(dirname "$0")/.." && pwd)
PY=${PYTHON:-$HOME/venvs/hyclb/bin/python}

quiet=0
waited=0
while (( waited < MAX_WAIT )); do
    load=$(cut -d' ' -f1 /proc/loadavg)
    gpu=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
    gpu=${gpu:-0}
    if awk "BEGIN{exit !($load < $THRESHOLD && $gpu < 10)}"; then
        quiet=$((quiet + 1))
        (( quiet >= NEEDED )) && break
    else
        quiet=0
    fi
    sleep $INTERVAL
    waited=$((waited + INTERVAL))
done

{
    echo "# LASSO benchmark"
    echo "# date:      $(date -Is)"
    echo "# host:      $(uname -srm)"
    echo "# cpu:       $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')"
    echo "# gpu:       $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
    echo "# loadavg:   $(cut -d' ' -f1-3 /proc/loadavg)"
    if (( quiet >= NEEDED )); then
        echo "# condition: idle (load below $THRESHOLD and GPU below 10% for $NEEDED consecutive minutes)"
    else
        echo "# condition: NOT IDLE -- gave up waiting after $((waited / 3600))h; these numbers are contended"
    fi
    echo
    "$PY" "$here/benchmarks/lasso.py" --reps 5 2>&1 | grep -vE '^hyclb;|Warning|warn'
    echo
    echo "# --- CUDA: the sweep loop moved onto the device --------------------"
    echo "# gpu busy at start: $(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader 2>/dev/null | head -1)"
    "$PY" "$here/benchmarks/lasso_cuda.py" 2>&1 | grep -vE '^hyclb;|Warning|warn'
} > "$OUT" 2>&1
