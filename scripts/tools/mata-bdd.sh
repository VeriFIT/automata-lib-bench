# mata-bdd: the harness' C++ interpreter on mata's NFTs used as automata with
# BDDs on their transitions (one NFT level per variable of the bitvector),
# linked against libmata of the revision. Reads '@NFA-bits' inputs only, with
# the harness' own reader: it must not mintermize.

subject=subjects/mata
runs="emp"

build() {
    local build="$outdir/mata-build" prefix="$outdir/prefix"
    local harness_build="$outdir/harness-build"

    cmake -B "$build" -S "$worktree" \
        -DCMAKE_BUILD_TYPE="$build_mode" \
        -DCMAKE_INSTALL_PREFIX="$prefix" \
        -DBUILD_TESTING:BOOL=OFF \
        -DMATA_BUILD_EXAMPLES:BOOL=OFF
    cmake --build "$build" --parallel "$jobs" --target libmata
    cmake --install "$build" >/dev/null

    echo "======== Building the C++ interpreter ========"
    cmake -B "$harness_build" -S "$harness" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH="$prefix"
    cmake --build "$harness_build" --parallel "$jobs" --target mata-bdd-emp-interpreter
    cp "$harness_build/src/cpp/mata-bdd-emp-interpreter" "$binary"
}
