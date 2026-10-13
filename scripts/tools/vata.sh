# vata: the harness' C++ interpreter on libvata's explicit tree automata (an NFA
# is a tree automaton over unary symbols), reading '.mata' inputs with the
# pinned libmata.
#
# Builds need Boost < 1.89 (libvata's CMake requires its compiled 'system'
# component even though the library itself uses only headers), found through
# $BOOST_ROOT, which the dev shell sets; the binary links libvata and libmata
# statically.

subject=subjects/libvata
runs="emp"

build() {
    local build="$outdir/vata-build" prefix="$outdir/prefix"
    local harness_build="$outdir/harness-build" mata_prefix

    # libvata asks for CMake 2.8, which CMake >= 4 refuses without a policy floor;
    # GCC >= 14 rejects a never-instantiated bad template body in
    # src/util/shared_list.hh unless -Wtemplate-body is off.
    cmake -B "$build" -S "$worktree" \
        -DCMAKE_BUILD_TYPE="$build_mode" \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_PREFIX_PATH="${BOOST_ROOT:-}" \
        -DCMAKE_CXX_FLAGS=-Wno-template-body \
        -DBUILD_TESTING:BOOL=OFF
    cmake --build "$build" --parallel "$jobs" --target libvata
    # libvata has no install rules: lay its headers and archive out as a prefix
    # for the harness' find_path()/find_library().
    rm -rf "$prefix"
    mkdir -p "$prefix/include" "$prefix/lib"
    cp -r "$worktree/include/vata" "$prefix/include/"
    cp "$build/src/libvata.a" "$prefix/lib/"

    mata_prefix=$(libmata_prefix)

    echo "======== Building the C++ interpreter ========"
    cmake -B "$harness_build" -S "$harness" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH="$prefix;$mata_prefix${BOOST_ROOT:+;$BOOST_ROOT}" \
        -DVATA_INTERPRETER:BOOL=ON
    cmake --build "$harness_build" --parallel "$jobs" --target vata-emp-interpreter
    cp "$harness_build/src/cpp/vata-emp-interpreter" "$binary"
}
