# Converting large `Nat`s to decimal in Lean 4: benchmark

This benchmark backs a comparison posted on [leanprover/lean4#5771](https://github.com/leanprover/lean4/issues/5771).  It times three ways for `Nat.reprFast`, the runtime implementation of `Nat.repr`, to convert numbers that do not fit in a `USize`:

- `list`: the code on master, `String.ofList (Nat.toDigits 10 n)`, which is quadratic in the number of digits.
- `dc`: divide and conquer in Lean, with a proof that `Nat.reprFast n = Nat.repr n`: branch [`nat-repr-dc`](https://github.com/matthiasgoergens/lean4/tree/nat-repr-dc).
- `ext`: a runtime function that calls GMP's `mpz_get_str` (Lean's own `mpn_to_string` in builds without GMP).  This is my reconstruction, from its description on the issue, of the approach proposed there; the patch is [`patches/gmp`](patches/gmp).

All three are called from one binary, built from the `nat-repr-dc` branch plus [`patches/bench`](patches/bench), which adds the runtime function and public entry points for the benchmark.

## Results

The design, hypotheses and analysis were written down before the data existed: [`PLAN.md`](PLAN.md), including the deviations and why.  Raw data and analyses are in [`data/`](data):

- [`data/gmp-final`](data/gmp-final): the final code, Lean built with GMP, 30 blocks.  The numbers on the issue come from here.
- [`data/gmp`](data/gmp): the same design on an earlier commit of the branch (which differs only for numbers below 10³⁶), including `list` at 100,000 digits.
- [`data/nogmp`](data/nogmp): built with `-DUSE_GMP=OFF`, stopped after 8 blocks.

Each block is a fresh process that measures every (size, variant) cell once, in random order.  The input at each size is one random number, the same in every block.  `data.csv` has one row per measurement: time per call is `ns / reps`.  `environment.txt` records the commit, compiler, GMP version and checksums of the binaries.

## Reproducing

Paths in the scripts assume a working directory `~/lean4-repr` that holds this repository's scripts and a worktree `wt-bench`:

```sh
repo=$PWD   # a clone of this repository
git clone https://github.com/matthiasgoergens/lean4 --branch nat-repr-dc ~/lean4-repr/wt-bench
git -C ~/lean4-repr/wt-bench am "$repo"/patches/bench/*.patch
cp "$repo"/{Dockerfile,build.sh,run_bench.sh,NatReprBench.lean} ~/lean4-repr/
cd ~/lean4-repr
docker build --tag lean4-repr-build .
./build.sh wt-bench release                     # add -DUSE_GMP=OFF and another build directory for the non-GMP run
MAXLIST=10000 ./run_bench.sh release ~/lean4-repr/out 11 30   # build directory, output directory, CPU, blocks
"$repo"/analyse.py ~/lean4-repr/out/data.csv    # needs uv
```
