#!/usr/bin/env bash

# Builds one tool at one revision into a self-contained benchmark binary.
#
# A "tool" is one way of running benchmark programs, defined by its own file
# 'scripts/tools/<tool>.sh' (see "Tool files" below). It names the subject it is
# built from: a git repository whose revisions are built, 'pypi:<package>' whose
# versions are installed, or 'tarball:<url>' whose '{rev}' is replaced by the
# version to download. Several tools can share a subject: both 'mata' and
# 'pymata' are built from 'subjects/mata'.
#
# Each revision of a git subject is checked out once into its own git worktree
# under 'build/versions/<subject>/<slug>/src' and every tool builds from there
# into its own directory, so revisions and tools never clobber each other.
#
# Result: bin/<tool>-<slug>, run as '<binary> <program.emp> [options] <automaton>...'.
# With '--program cc-programs/<name>.cc' also
# 'build/versions/<subject>/<slug>/<tool>/programs/<name>', that C++ benchmark
# program linked against the revision's libmata.
#
# === Tool files ===
#
# 'scripts/tools/<tool>.sh' is sourced and sets:
#   subject=<git repository below the root | pypi:<package> | tarball:<url with {rev}>>
#   runs="<program kinds the tool runs: emp, cc>"
#   build() { ...; }   builds $binary
# build() sees: $worktree (the checkout of the revision, or the unpacked
# tarball; empty for pypi), $outdir (kept between builds of this tool and
# slug), $binary, $rev, $commit (the version for pypi and tarball subjects),
# $build_mode, $jobs, $rootdir,
# $harness (the interpreters' repository), and the helpers die(),
# libmata_prefix() and libmata_python(). A tool that runs 'cc' installs libmata
# into $outdir/prefix.

set -euo pipefail
# The dev shell exports the site-packages of its python3.14; leaked into the
# python3.13 venvs' builds it mixes the two (wheel tag 'cp313-cp314').
unset PYTHONPATH

die() {
    echo "error: $*" >&2
    exit 1
}

usage() { {
        [ $# -gt 0 ] && echo "error: $1"
        echo "usage: ./scripts/build_version.sh [opts] <tool> <rev> [slug]"
        echo "  <tool>                      tool to build (see --list-tools)"
        echo "  <rev>                       revision of the tool's subject (tag, branch, commit; version for pypi)"
        echo "  [slug]                      name of the built binary; defaults to <rev>"
        echo "options:"
        echo "  -l|--list-tools             list the known tools, their subjects and program kinds"
        echo "  -f|--force                  rebuild even if the binary already exists"
        echo "  -b|--build-mode <mode>      Release (default), RelWithDebInfo, Debug"
        echo "  -p|--program <prog.cc>      also build this C++ program of cc-programs/ (tools running 'cc')"
        echo "     --libmata-prefix <rev>   build libmata alone at <rev> of subjects/mata, print its prefix"
        echo "     --libmata-python <rev>   build mata's bindings alone at <rev>, print the venv's python"
    } >&2
}

rootdir=$(cd "$(dirname "$0")/.." && pwd)
tools_dir="$rootdir/scripts/tools"
harness="$rootdir/harnesses/automata-program-parser"
jobs="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

known_tools() {
    local file
    for file in "$tools_dir"/*.sh; do basename "$file" .sh; done
}

# Sources the tool file into the current shell, resetting what it defines.
load_tool() {
    local file="$tools_dir/$1.sh"
    [ -f "$file" ] || die "unknown tool '$1' (known: $(known_tools | paste -sd' '))"
    subject="" runs=""
    unset -f build
    # shellcheck source=/dev/null
    . "$file"
    [ -n "$subject" ] && [ -n "$runs" ] && declare -F build >/dev/null ||
        die "$file must set 'subject' and 'runs' and define build()"
}

# The mata revision other tools read their '.mata' inputs with: they link its
# libmata (C++) or install its bindings (Python) only to parse and mintermize,
# so it is pinned rather than compared.
parsing_mata_rev=v1.32.45-dev.57

# Checks revision <rev> of subjects/mata out for the helpers below, into
# 'build/versions/mata/lib-<rev>', and prints that directory and the commit.
_parsing_mata_checkout() {
    local rev=$1 dir="$rootdir/build/versions/mata/lib-${1//\//-}" commit
    commit=$(git -C "$rootdir/subjects/mata" rev-parse --verify --quiet "$rev^{commit}") ||
        die "subjects/mata: unknown revision '$rev'"
    if [ ! -e "$dir/src/.git" ]; then
        git -C "$rootdir/subjects/mata" worktree prune
        git -C "$rootdir/subjects/mata" worktree add --detach "$dir/src" "$commit" >&2
    elif [ "$(git -C "$dir/src" rev-parse HEAD)" != "$commit" ]; then
        git -C "$dir/src" checkout --detach --force "$commit" >&2
    fi
    echo "$dir $commit"
}

# Prints the install prefix of libmata (Release) at revision [rev] of
# subjects/mata (default: $parsing_mata_rev), building it first. Keyed on the
# commit alone: the harness is not part of it.
libmata_prefix() {
    local dir commit
    read -r dir commit < <(_parsing_mata_checkout "${1:-$parsing_mata_rev}")
    [ -n "$commit" ] || exit 1
    local lib="$dir/libmata"
    if [ "$(cat "$lib/BUILD_KEY" 2>/dev/null)" != "$commit" ]; then
        rm -f "$lib/BUILD_KEY"
        {
            cmake -B "$lib/build" -S "$dir/src" -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_INSTALL_PREFIX="$lib/prefix" -DBUILD_TESTING:BOOL=OFF -DMATA_BUILD_EXAMPLES:BOOL=OFF
            cmake --build "$lib/build" --parallel "$jobs" --target libmata
            cmake --install "$lib/build"
        } >&2
        echo "$commit" > "$lib/BUILD_KEY"
    fi
    echo "$lib/prefix"
}

# Prints the Python interpreter of a venv holding only mata's bindings at
# revision [rev] (default: $parsing_mata_rev), building it first. Keyed on the
# commit alone. A tool needing more packages keeps its own venv and points it
# here with a .pth file rather than installing into this one.
libmata_python() {
    local dir commit
    read -r dir commit < <(_parsing_mata_checkout "${1:-$parsing_mata_rev}")
    [ -n "$commit" ] || exit 1
    local venv="$dir/python/venv"
    if [ "$(cat "$dir/python/BUILD_KEY" 2>/dev/null)" != "$commit" ]; then
        command -v uv >/dev/null || die "uv not found; enter the dev shell or run 'just bootstrap'"
        rm -rf "$dir/python"
        {
            uv venv "$venv" --python "$(command -v python3)"
            VIRTUAL_ENV="$venv" uv pip install "$dir/src/bindings/python"
        } >&2
        echo "$commit" > "$dir/python/BUILD_KEY"
    fi
    echo "$venv/bin/python"
}

# C++ benchmark program linked against the revision's libmata. CMake rebuilds
# it only when the program, the harness headers or libmata changed.
build_program() {
    local name
    [[ " $runs " == *" cc "* ]] || die "tool '$tool' does not run C++ programs (runs: $runs)"
    [ "$(cd "$(dirname "$program")" && pwd)" = "$rootdir/cc-programs" ] ||
        die "C++ programs live in cc-programs/, not in $(dirname "$program")"
    name=$(basename "$program" .cc)
    cmake -B "$outdir/programs" -S "$rootdir/cc-programs" \
        -DCMAKE_BUILD_TYPE="$build_mode" -DCMAKE_PREFIX_PATH="$outdir/prefix" >/dev/null
    cmake --build "$outdir/programs" --parallel "$jobs" --target "$name"
    echo "[done] $outdir/programs/$name"
}

# === Main ===

force=false
build_mode="Release"
program=""
args=()
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0;;
        -l|--list-tools)
            for t in $(known_tools); do
                load_tool "$t"
                printf '%-14s %-32s %s\n' "$t" "$subject" "$runs"
            done
            exit 0;;
        -f|--force)
            force=true
            shift 1;;
        -b|--build-mode)
            build_mode="$2"
            shift 2;;
        --libmata-prefix)
            libmata_prefix "$2"
            exit 0;;
        --libmata-python)
            libmata_python "$2"
            exit 0;;
        -p|--program)
            [ -f "$2" ] || die "no such program: $2"
            program="$2"
            shift 2;;
        -*)
            usage "unknown option: $1"
            exit 1;;
        *)
            args+=( "$1" )
            shift 1;;
    esac
done

[ ${#args[@]} -ge 2 ] || { usage "missing tool or revision"; exit 1; }
tool="${args[0]}"
rev="${args[1]}"
slug="${args[2]:-$rev}"
# '/' would turn branch names such as 'origin/devel' into directories
slug="${slug//\//-}"

load_tool "$tool"

if [[ "$subject" == pypi:* ]]; then
    subject_name="${subject#pypi:}"
    worktree=""
    commit="$rev"
elif [[ "$subject" == tarball:* ]]; then
    subject_name="$tool"
    tarball_url="${subject#tarball:}"
    tarball_url="${tarball_url//\{rev\}/$rev}"
    worktree="$rootdir/build/versions/$subject_name/$slug/src"
    commit="$rev"
else
    subject_name=$(basename "$subject")
    subject_abs="$rootdir/$subject"
    [ -e "$subject_abs/.git" ] || die "$subject not initialised; run 'git submodule update --init --recursive'"
    worktree="$rootdir/build/versions/$subject_name/$slug/src"
    commit=$(git -C "$subject_abs" rev-parse --verify --quiet "$rev^{commit}") ||
        die "$subject: unknown revision '$rev'"
fi
outdir="$rootdir/build/versions/$subject_name/$slug/$tool"
binary="$rootdir/bin/$tool-$slug"

# The cache is keyed on the commit, not the label: labels such as 'devel',
# 'HEAD' or a pull request's head move, and a stale binary would be measured
# under the new name. The harness (interpreters and timing code) and the tool
# file are part of every build, so their states are part of the key, as is the
# build mode. The stamp is per tool, as tools share the checkout.
harness_state=$(git -C "$harness" rev-parse HEAD)
git -C "$harness" diff --quiet HEAD ||
    harness_state+="+$(git -C "$harness" diff HEAD | sha256sum | cut -c1-12)"
tool_state=$(sha256sum < "$tools_dir/$tool.sh" | cut -c1-12)
key="$commit $build_mode harness:$harness_state tool:$tool_state"
stamp="$outdir/BUILD_KEY"
if [ -x "$binary" ] && [ "$force" = false ] && [ "$(cat "$stamp" 2>/dev/null)" = "$key" ]; then
    echo "[!] $tool/$slug: already built at $commit ($binary); use --force to rebuild"
    [ -z "$program" ] || build_program
    exit 0
fi

echo "========== Building $tool '$slug' ($commit) =========="
mkdir -p "$outdir" "$rootdir/bin"
# A failed build must not leave the previous revision's binary behind.
rm -f "$stamp" "$binary"

# One checkout per revision, shared by every tool built from this subject.
if [ -z "$worktree" ]; then
    :
elif [ -n "${tarball_url:-}" ]; then
    rm -rf "$worktree"
    mkdir -p "$worktree"
    curl --fail --silent --show-error --location "$tarball_url" |
        tar --extract --gzip --strip-components=1 --directory "$worktree" ||
        die "could not download and unpack $tarball_url"
elif [ -e "$worktree/.git" ]; then
    git -C "$worktree" checkout --detach --force "$commit"
else
    git -C "$subject_abs" worktree prune
    git -C "$subject_abs" worktree add --detach "$worktree" "$commit"
fi

build

echo "$key" > "$stamp"
echo "[done] $binary ($commit)"
[ -z "$program" ] || build_program
