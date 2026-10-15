# mata: the harness' C++ interpreter linked against libmata of the revision.
#
# libmata is a static library that also absorbs its 3rd-party objects, so the
# binary contains that revision in full and nothing is installed system-wide.

subject=subjects/mata
runs="emp cc"

build() {
    local build="$outdir/mata-build" prefix="$outdir/prefix"
    local harness_build="$outdir/harness-build"

    # Only the library is needed; examples and tests would just cost build time.
    cmake -B "$build" -S "$worktree" \
        -DCMAKE_BUILD_TYPE="$build_mode" \
        -DCMAKE_INSTALL_PREFIX="$prefix" \
        -DBUILD_TESTING:BOOL=OFF \
        -DMATA_BUILD_EXAMPLES:BOOL=OFF
    cmake --build "$build" --parallel "$jobs" --target libmata
    # Installing merges mata's and its 3rd-party headers into a single include
    # directory, which is what the harness' find_path() expects.
    cmake --install "$build" >/dev/null

    echo "======== Building the C++ interpreter ========"
    # CMAKE_PREFIX_PATH makes the harness' find_library()/find_path() resolve to
    # this revision rather than a system-wide or another revision's libmata.
    cmake -B "$harness_build" -S "$harness" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH="$prefix"
    cmake --build "$harness_build" --parallel "$jobs" --target mata-emp-interpreter
    cp "$harness_build/src/cpp/mata-emp-interpreter" "$binary"
}
