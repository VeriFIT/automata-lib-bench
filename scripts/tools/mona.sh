# mona: the harness' C++ interpreter on MONA's DFA library, whose automata have
# a shared multi-terminal BDD per state. MONA has DFAs only: an NFA is
# determinized when it is loaded, by projecting out choice variables as MONA
# quantifies (see interpreter_mona.cc). Reads '@NFA-bits' inputs only, with the
# harness' own reader. A revision is a tag or a commit of
# https://github.com/cs-au-dk/MONA, e.g. 1.4-18.
#
# Only MONA's libraries (Mem, BDD, DFA) are built, with MONA's own optimisation
# flags (-O3) whatever the build mode; its configure needs flex and bison all
# the same. The binary links them statically.

subject="tarball:https://github.com/cs-au-dk/MONA/archive/{rev}.tar.gz"
runs="emp"

build() {
    local prefix="$outdir/prefix" harness_build="$outdir/harness-build" dir

    # In the source tree: DFA's makefile finds BDD's headers there only. The
    # tarball is unpacked afresh for every build.
    rm -rf "$prefix"
    (cd "$worktree" && ./configure --prefix="$prefix" --disable-shared >/dev/null)
    for dir in Mem BDD DFA; do
        make -C "$worktree/$dir" --jobs="$jobs" install >/dev/null
    done

    echo "======== Building the C++ interpreter ========"
    cmake -B "$harness_build" -S "$harness" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH="$prefix" \
        -DMATA_INTERPRETERS:BOOL=OFF \
        -DMONA_INTERPRETER:BOOL=ON
    cmake --build "$harness_build" --parallel "$jobs" --target mona-emp-interpreter
    cp "$harness_build/src/cpp/mona-emp-interpreter" "$binary"
}
