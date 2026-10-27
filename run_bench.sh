#!/bin/bash
# Runs the pre-registered Nat.repr benchmark (PLAN.md) on the benchmark host.
# Usage: run_bench.sh <build-subdir> <out-dir> <cpu> [blocks]
# Example: run_bench.sh release ~/lean4-repr/logs/2026-10-27/nat-repr/gmp 60 30
sub=$1; out=$2; cpu=$3; blocks=${4:-30}
root=$HOME/lean4-repr
wt=$root/wt-bench
bin=$wt/build/$sub/stage1/bin
mkdir --parents "$out" || exit 1
in_container() {
  docker run --rm --user "$(id --user):$(id --group)" --volume "$root:$root" --workdir "$out" \
    --cpuset-cpus "$cpu" --env MAXK="${MAXK:-10000000}" --env MAXLIST="${MAXLIST:-100000}" lean4-repr-build "$@"
}

# Compile the benchmark with the toolchain under test.
cp "$root/NatReprBench.lean" "$out/" || exit 1
in_container bash -c "
  $bin/lean NatReprBench.lean -c NatReprBench.c &&
  $bin/leanc -O3 NatReprBench.c -o NatReprBench" || exit 1

# Record the environment.
{
  echo "date: $(date --iso-8601=seconds)"
  echo "command: MAXK=${MAXK:-} MAXLIST=${MAXLIST:-} $0 $*"
  echo "cpu: $cpu (L3 shared with $(cat /sys/devices/system/cpu/cpu$cpu/cache/index3/shared_cpu_list))"
  echo "worktree commit: $(git -C "$wt" rev-parse HEAD)"
  echo "uname: $(uname -a)"
  in_container bash -c "$bin/lean --version; clang --version | head -1; dpkg-query --show libgmp-dev"
  sha256sum "$out/NatReprBench" "$bin/../lib/lean/libleanshared.so" "$bin/../lib/lean/libleanrt.a" 2>/dev/null
  in_container ldd "$out/NatReprBench"
  lscpu | grep --extended-regexp "Model name|MHz"
  cat /sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor
} > "$out/environment.txt" 2>&1

ccd=$(cat /sys/devices/system/cpu/cpu$cpu/cache/index3/shared_cpu_list)
load() {
  echo "== $1 $(date +%T) $(cut --delimiter=' ' --fields=1-3 /proc/loadavg)"
  ps -eo psr,pcpu,user,comm --sort=-pcpu | awk -v r="$ccd" '
    BEGIN { n = split(r, parts, ","); for (i = 1; i <= n; i++) { split(parts[i], ab, "-"); lo[i] = ab[1]; hi[i] = ab[2] } }
    NR > 1 { for (i = 1; i <= n; i++) if ($1 >= lo[i] && $1 <= hi[i] && $2 > 5) print }'
}

# Pilot: sets the repetition table; its timings are discarded.
if [ ! -s "$out/table.txt" ]; then
  in_container ./NatReprBench pilot > "$out/table.txt" || exit 1
fi

echo "block,order,k,variant,reps,ns" > "$out/data.csv"
for b in $(seq 1 "$blocks"); do
  load "before block $b" >> "$out/load.log"
  in_container ./NatReprBench block "$b" table.txt >> "$out/data.csv" || { echo "block $b failed"; exit 1; }
  load "after block $b" >> "$out/load.log"
done
echo "done $(date +%T)" >> "$out/load.log"
