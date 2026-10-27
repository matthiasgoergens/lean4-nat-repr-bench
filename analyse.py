#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["scipy>=1.13"]
# ///
"""Primary analysis of the Nat.repr benchmark, as pre-registered in PLAN.md."""

import argparse
import csv
import math
import statistics
from collections import defaultdict
from pathlib import Path

from scipy import stats


def load(path: Path) -> dict[tuple[int, str], dict[int, float]]:
    """(k, variant) -> {block: nanoseconds per call}."""
    cells: dict[tuple[int, str], dict[int, float]] = defaultdict(dict)
    with path.open() as f:
        for row in csv.DictReader(f):
            cells[(int(row["k"]), row["variant"])][int(row["block"])] = int(row["ns"]) / int(row["reps"])
    return cells


def paired(cells, k: int, a: str, b: str) -> tuple[float, float, float, int] | None:
    """Geometric mean of t_a / t_b over blocks, with a 95 % t-interval."""
    if (k, a) not in cells or (k, b) not in cells:
        return None
    blocks = sorted(set(cells[(k, a)]) & set(cells[(k, b)]))
    logs = [math.log(cells[(k, a)][i] / cells[(k, b)][i]) for i in blocks]
    n = len(logs)
    mean = statistics.fmean(logs)
    half = stats.t.ppf(0.975, n - 1) * statistics.stdev(logs) / math.sqrt(n)
    return math.exp(mean), math.exp(mean - half), math.exp(mean + half), n


def fmt_time(ns: float) -> str:
    for unit, scale in (("s", 1e9), ("ms", 1e6), ("µs", 1e3)):
        if ns >= scale:
            return f"{ns / scale:.3g} {unit}"
    return f"{ns:.3g} ns"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path, help="data.csv from run_bench.sh")
    args = parser.parse_args()
    cells = load(args.data)
    sizes = sorted({k for k, _ in cells})

    print("## Time per call: median over blocks [min, max]\n")
    print("| k | " + " | ".join(("list", "dc", "ext", "dc2")) + " |")
    print("|---|---|---|---|---|")
    for k in sizes:
        row = []
        for v in ("list", "dc", "ext", "dc2"):
            xs = sorted(cells.get((k, v), {}).values())
            row.append(f"{fmt_time(statistics.median(xs))} [{fmt_time(xs[0])}, {fmt_time(xs[-1])}]" if xs else "")
        print(f"| {k} | " + " | ".join(row) + " |")

    print("\n## Paired ratios: geometric mean [95 % interval]\n")
    print("| k | dc/list | dc/ext | dc/dc2 |")
    print("|---|---|---|---|")
    results = {}
    for k in sizes:
        row = []
        for a, b in (("dc", "list"), ("dc", "ext"), ("dc", "dc2")):
            r = paired(cells, k, a, b)
            results[(k, a, b)] = r
            row.append(f"{r[0]:.3g} [{r[1]:.3g}, {r[2]:.3g}]" if r else "")
        print(f"| {k} | " + " | ".join(row) + " |")

    print("\n## Pre-registered hypotheses\n")
    h1 = all(results[(k, "dc", "list")][2] < 1.10 for k in (20, 30))
    print(f"H1 (dc/list upper bound < 1.10 at k = 20, 30): {'holds' if h1 else 'fails'}")
    big = [k for k in sizes if k >= 1000 and results.get((k, "dc", "list"))]
    speedups = [1 / results[(k, "dc", "list")][0] for k in big]
    h2 = all(1 / results[(k, "dc", "list")][2] > 10 for k in big) and speedups == sorted(speedups)
    print(f"H2 (list/dc lower bound > 10 for k >= 1000, increasing in k): {'holds' if h2 else 'fails'}"
          f"  (list/dc = {', '.join(f'{s:.3g}' for s in speedups)})")
    h3 = all(results[(k, "dc", "ext")][1] > 1 for k in sizes if k >= 10**4)
    print(f"H3 (dc/ext lower bound > 1 for k >= 10^4): {'holds' if h3 else 'fails'}")
    worst = max(results[(k, "dc", "ext")][0] for k in sizes if k >= 10**4)
    print(f"   largest dc/ext above 10^4 digits: {worst:.3g}"
          f" ({'competitive (<= 2)' if worst <= 2 else 'clear case for GMP (> 5)' if worst > 5 else 'in between'})")
    neg = all(0.95 <= results[(k, "dc", "dc2")][1] and results[(k, "dc", "dc2")][2] <= 1.05 for k in sizes)
    print(f"Negative control (dc/dc2 interval within [0.95, 1.05] at every k): {'holds' if neg else 'FAILS'}")
    lists = sorted(k for k, v in cells if v == "list")
    lo, hi = lists[-2], lists[-1]
    ratio = statistics.median(cells[(hi, "list")].values()) / statistics.median(cells[(lo, "list")].values())
    print(f"Positive control (list time ratio {hi} / {lo} > 30): {'holds' if ratio > 30 else 'FAILS'}"
          f" (ratio {ratio:.3g})")

if __name__ == "__main__":
    main()
