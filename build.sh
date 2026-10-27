#!/bin/bash
# Build one Lean worktree inside the declared container.
# Usage: build.sh <worktree> <build-subdir> [extra cmake options...]
# Example: build.sh wt-bench release-gmp
wt=$1; sub=$2; shift 2
root=$HOME/lean4-repr
mkdir --parents "$root/ccache" "$root/logs"
log=$root/logs/build-$wt-$sub.log
exec docker run --rm --name "lean4-repr-$wt-$sub" \
  --user "$(id --user):$(id --group)" \
  --volume "$root:$root" --workdir "$root/$wt" \
  --env CCACHE_DIR="$root/ccache" --env HOME="$root" \
  lean4-repr-build bash -c "
    cmake -S . -B build/$sub -G 'Unix Makefiles' -DSTRIP_BINARIES=OFF \
      -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ $* &&
    nice make -C build/$sub -j48
  " > "$log" 2>&1
