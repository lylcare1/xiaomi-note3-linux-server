#!/bin/sh
# cpu-bench-final.sh — strict benchmark, 3 runs each, average
LOG=/tmp/cpu-bench-final.txt
echo "=== Strict CPU Benchmark $(date) ===" > $LOG
echo "uname: $(uname -r), nproc: $(nproc)" >> $LOG

# bench NAME MASK PARALLEL DURATION RUNS
bench() {
    NAME=$1; MASK=$2; N=$3; DUR=$4; RUNS=$5
    total_mb=0
    for r in $(seq 1 $RUNS); do
        rm -f /tmp/b_*
        pids=""
        for i in $(seq 1 $N); do
            ( taskset $MASK timeout $DUR dd if=/dev/urandom of=/tmp/b_$i bs=1M 2>/dev/null ) &
            pids="$pids $!"
        done
        wait $pids 2>/dev/null
        run_bytes=0
        for i in $(seq 1 $N); do
            sz=$(stat -c %s /tmp/b_$i 2>/dev/null || echo 0)
            run_bytes=$((run_bytes + sz))
            rm -f /tmp/b_$i
        done
        run_mb=$((run_bytes / 1048576))
        total_mb=$((total_mb + run_mb))
    done
    avg=$((total_mb / RUNS))
    mbps=$((avg / DUR))
    printf "  %-30s avg=%4dMB (%d runs, %ds) = %3d MB/s\n" "$NAME" "$avg" "$RUNS" "$DUR" "$mbps"
    echo "$NAME: avg=${avg}MB rate=${mbps}MB/s" >> $LOG
}

echo "Warming up CSPRNG..."
dd if=/dev/urandom of=/dev/null bs=1M count=50 2>/dev/null

echo "=== Single-core (1 process, 5s x 3 runs) ==="
bench "single-little-cpu0"   0x01 1 5 3
bench "single-little-cpu3"   0x08 1 5 3
bench "single-big-cpu4"      0x10 1 5 3
bench "single-big-cpu7"      0x80 1 5 3

echo "=== Multi-core parallel (N processes, 8s x 3 runs) ==="
bench "little4-4p  (cpu0-3)" 0x0f 4 8 3
bench "big4-4p    (cpu4-7)"  0xf0 4 8 3
bench "all8-8p    (cpu0-7)"  0xff 8 8 3
bench "all8-4p    (cpu0-7, 4 proc)" 0xff 4 8 3

echo
cat $LOG
