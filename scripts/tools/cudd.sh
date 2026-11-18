# cudd: the harness' C++ interpreter on symbolic NFAs whose transitions are
# labelled by BDDs of CUDD (the textbook algorithms over the guards: product,
# subset construction splitting the guards, antichain inclusion). Reads
# '@NFA-bits' inputs only, with the harness' own reader. A revision is a CUDD
# release, e.g. 3.0.0, from the GitHub mirror of the releases.
#
# CUDD is built with its own optimisation flags (-O3) whatever the build mode;
# the binary links libcudd statically.

subject="tarball:https://github.com/ivmai/cudd/archive/refs/tags/cudd-{rev}.tar.gz"
runs="emp"

build() {
    local build="$outdir/cudd-build" prefix="$outdir/prefix"
    local harness_build="$outdir/harness-build"

    rm -rf "$build" "$prefix"
    mkdir -p "$build"
    (cd "$build" && "$worktree/configure" --prefix="$prefix" --disable-shared >/dev/null)
    make -C "$build" --jobs="$jobs" >/dev/null
    make -C "$build" install >/dev/null

    echo "======== Building the C++ interpreter ========"
    cmake -B "$harness_build" -S "$harness" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH="$prefix" \
        -DMATA_INTERPRETERS:BOOL=OFF \
        -DCUDD_INTERPRETER:BOOL=ON
    cmake --build "$harness_build" --parallel "$jobs" --target cudd-emp-interpreter
    cp "$harness_build/src/cpp/cudd-emp-interpreter" "$binary"
}
