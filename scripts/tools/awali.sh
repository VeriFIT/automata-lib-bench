# awali: the harness' C++ interpreter on awali's dynamic layer (libawalidyn),
# reading '.mata' inputs with the pinned libmata. Awali publishes release
# tarballs only; a revision is the version, e.g. 2.3.0-230512.
#
# libawalidyn runs every algorithm from a "module" per automaton context, which
# it compiles from the installed sources on first use and caches. The modules
# the interpreter uses on Boolean automata over chars are compiled here, so no
# benchmark run times a compilation.

subject="tarball:http://files.vaucanson-project.org/tarballs/awali-all-v{rev}.tgz"
runs="emp"

build() {
    local build="$outdir/awali-build" prefix="$outdir/prefix"
    local harness_build="$outdir/harness-build" mata_prefix

    # The module paths are baked into libawalidyn: compile modules into the
    # prefix (not ~/.awali/modules) and work in $outdir/tmp (not /tmp/awali).
    # Awali's CMake also reads HOME for its scratch module directory, whose
    # contents it installs: point it into $outdir too. Its cmake_minimum_required
    # predates 3.5, which CMake >= 4 refuses without a policy floor. GCC >= 14
    # rejects never-instantiated bad template bodies in awali/dyn/options/option.hh
    # unless -Wtemplate-body is off; awali bakes its CMAKE_CXX_FLAGS into the
    # module compilations too.
    rm -rf "$build" "$prefix" "${outdir:?}/tmp" "${outdir:?}/home"
    HOME="$outdir/home" cmake -B "$build" -S "$worktree" \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_CXX_FLAGS=-Wno-template-body \
        -DCMAKE_BUILD_TYPE="$build_mode" \
        -DCMAKE_INSTALL_PREFIX="$prefix" \
        -DFORCE_INSTALL_IN_PREFIX=TRUE \
        -DCOMPILE_MODULE_IN_INSTALL_DIR=TRUE \
        -DAWALI_TMP_DIR="$outdir/tmp" \
        -DCORA=FALSE \
        -DPY=FALSE
    cmake --build "$build" --parallel "$jobs" --target awalidyn
    cmake --install "$build" >/dev/null
    # Modules of the operations in interpreter_awali.cc ("trim", "is_empty" ->
    # accessible; "complement", "complete" -> determinize; "sum",
    # "concatenate" -> product; "minimal_automaton" -> quotient).
    cmake --build "$build" --parallel "$jobs" --target \
        lal_char_b-automaton lal_char_b-context lal_char_b-factories \
        lal_char_b-accessible lal_char_b-determinize lal_char_b-standard \
        lal_char_b-quotient lal_char_b_lal_char_b-product

    mata_prefix=$(libmata_prefix)

    echo "======== Building the C++ interpreter ========"
    cmake -B "$harness_build" -S "$harness" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS=-Wno-template-body \
        -DCMAKE_PREFIX_PATH="$prefix;$mata_prefix" \
        -DAWALI_INTERPRETER:BOOL=ON
    cmake --build "$harness_build" --parallel "$jobs" --target awali-emp-interpreter
    # Linked against $prefix/lib/libawalidyn.so by its absolute RPATH.
    cp "$harness_build/src/cpp/awali-emp-interpreter" "$binary"
}
