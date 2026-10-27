# Pre-registered plan: converting large `Nat`s to decimal

Written 2026-10-27, before any confirmatory data exists.  The timings so far (prototype runs of the same day) were exploratory smoke tests and are not part of this analysis.

## Question

Upstream Lean's `Nat.reprFast` converts numbers of `USize.size` and above with `String.ofList (toDigits 10 n)`.  Two replacements are on branches:

- **DC**: divide and conquer in Lean, proven equal to `Nat.repr` (branch `matthias/nat-repr-dc`).
- **EXT**: a runtime function `lean_string_of_nat`, which calls GMP's `mpz_get_str` in GMP builds (branch `matthias/nat-repr-gmp`).

The question is how much time each takes per conversion, as a function of the number of decimal digits, compared with the current code (**LIST**) and with each other.  The main setting is a GMP build, which is what every official release is.  A build with `USE_GMP=OFF` is a secondary setting.

## Variants (cells)

All variants are called from one benchmark binary, built from branch `matthias/nat-repr-bench`.  That branch exposes the three functions as `Nat.benchReprList`, `Nat.benchReprDC` and `Nat.benchReprExtern`, so the comparison is within one binary and one runtime.

- `list`: `Nat.benchReprList` (the current code path for big numbers)
- `dc`: `Nat.benchReprDC`
- `ext`: `Nat.benchReprExtern`
- `dc2`: `Nat.benchReprDC` again, under a second label: the negative control

## Sizes

Decimal digit counts k ∈ {20, 30, 100, 1000, 10⁴, 10⁵, 10⁶, 10⁷}.  At each k the input is a uniformly random k-digit number with a nonzero leading digit, drawn from a fixed-seed generator (seed = k) and identical in every block.  `list` runs only for k ≤ 10⁵, because it takes about 27 s per call at 2·10⁵ digits on a laptop and would grow to hours at 10⁶.

## Experimental unit, blocks, randomisation

A block is one fresh process.  Within a block, every (k, variant) cell is measured once, with the order of all cells shuffled by a generator seeded with the block number.  A measurement times `r(k, variant)` back-to-back calls with `IO.monoNanosNow`.  The observation is the time per call, `total / r`.  The repetition counts `r` are set from a pilot block, which is discarded, so that each measurement takes at least about 20 ms, or a single call where one call takes longer than that.  The table of `r` is recorded with the data.

There are B = 30 blocks.  There is no early stopping.

Before timing, every block checks that all variants produce the same string at every k, using one call each outside the timed region.  A mismatch aborts the run.

## Environment

The host is a shared machine (AMD Threadripper PRO 9985WX, 64 cores, 8 CCDs, 2 threads per core, governor `performance`).  It is shared, and other people's builds run on it.  Mitigations:

- The process is pinned with `taskset` to one core whose SMT sibling is left idle.  The core is on the CCD with the lowest load when the run starts, avoiding CPUs 20 and 50, which another benchmark was using.
- The load average and the top processes on that CCD are logged before and after each block.
- Randomised blocks spread slow drifts in load evenly over the cells.  The analysis is paired within blocks.

Recorded with the run: the commit of every worktree, SHA-256 of the benchmark binary and of `libleanshared`/`libleanrt`, the compiler versions, `uname -a`, and the exact commands.  Raw output goes to `logs/<date>/nat-repr/`.

## Hypotheses and primary analysis

For each k and each pair of variants (A, B), the paired effect is the geometric mean over blocks of `t_A / t_B`, with a 95 % interval from a t-interval on the per-block log ratios.

- **H1 (no regression on small big numbers).**  At k = 20 and k = 30, `dc / list` ≤ 1.10, meaning the upper end of the 95 % interval is below 1.10.  These are the most common big numbers, such as `UInt64` values above 2⁶³.  A margin of 10 % is the largest slowdown I would accept for them without further work.
- **H2 (speed-up).**  For k ≥ 1000, `list / dc` > 10 with the lower end of the interval above 10, and `list / dc` increases with k.
- **H3 (GMP is faster still).**  For k ≥ 10⁴, `dc / ext` > 1 (interval excludes 1).  I expect it between 1.5 and 10.  The value that matters for the upstream choice: if `dc / ext` ≤ 2 at every k, DC is competitive with GMP.  If it exceeds 5 anywhere above 10⁴ digits, the GMP route has a clear performance case.
- **Negative control.**  `dc / dc2` has a 95 % interval within [0.95, 1.05] at every k.  If not, the harness has an order or position bias, and the other comparisons are reported as unreliable.
- **Positive control.**  `list` grows roughly quadratically: the per-call time ratio between k = 10⁵ and k = 10⁴ is above 30.

Secondary, same design and hypotheses but labelled secondary: the same binary built with `-DUSE_GMP=OFF`, where `ext` uses Lean's own `mpn_to_string` and Lean's own schoolbook division.

Everything else, such as special inputs like 10ᵏ or 2ᵏ, scaling exponents, end-to-end timings of the compiler emitting C for a file with a big literal, and other leaf sizes, is exploratory and will be labelled so.

## Deviation, recorded before the secondary run (2026-10-27, after the primary run)

The secondary run (`USE_GMP=OFF`) stops at k = 10⁶.  Without GMP, multiplication and division are schoolbook, so a single `dc` or `ext` call at 10⁷ digits would take on the order of a minute, and 30 blocks would take hours.  Everything else is as above.  The primary run is unaffected.

## Deviations after the secondary run started (2026-10-27)

- The secondary run was stopped after 8 complete blocks (block 9 dropped), because I did not want to spend long on quadratic cases: one `ext` call at 10⁶ digits takes about three minutes without GMP.  Its analysis uses those 8 blocks and is indicative, not confirmatory.
- The code under test changed after the primary run, following review (numbers below 10³⁶ no longer compute any power; comments; no change to the algorithm).  The primary design is therefore repeated on the final code, as a replication, with one change: `list` runs only up to k = 10⁴, so that the run takes minutes.  H2 is then judged on k ∈ {1000, 10⁴}, and the positive control on the `list` ratio between k = 10⁴ and k = 1000 (above 30 for quadratic growth with some overhead, i.e. a ratio of at least 30 for a tenfold size increase).

## Correction (2026-10-27)

The motivation given for H1 names `UInt64` values above 2⁶³.  On 64-bit platforms those are below `USize.size` and never reach the new code; H1 is about numbers from 2⁶⁴ (on 32-bit platforms, from 2³²) upwards, which the sizes k = 20 and 30 cover.
