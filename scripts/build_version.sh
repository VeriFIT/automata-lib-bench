#!/usr/bin/env bash

# Builds the emp interpreter against one specific revision of a tool.
#
# Every revision gets its own git worktree, build tree and install prefix under
# 'build/versions/<subject>/<slug>/', so several revisions coexist without
# clobbering each other. When the subject library is static, the resulting
# binary contains that revision in full -- nothing is installed system-wide
# and the binaries can be benchmarked against each other side by side.
#
# This script auto-detects the build method:
# - If <subject-repo> is 'subjects/mata', uses mata's build system
# - Can be extended for other subjects (VATA, Awali, etc.) by adding more cases
#
# Result: bin/emp-interpreter-<subject>-<slug>

set -euo pipefail

die() {
    echo "error: $*" >&2
    exit 1
}

usage() { {
        [ $# -gt 0 ] && echo "error: $1"
        echo "usage: ./scripts/build_version.sh [opts] <subject-repo> <rev> [slug]"
        echo "  <subject-repo>              path to subject repo (e.g., subjects/mata)"
        echo "  <rev>                       any revision (tag, branch, commit)"
        echo "  [slug]                      name slug for the binary; defaults to <rev>"
        echo "options:"
        echo "  -f|--force                  rebuild even if the binary already exists"
        echo "  -b|--build-mode <mode>      Release (default), RelWithDebInfo, Debug"
    } >&2
}

# Build libmata (and install headers + config files for the harness to discover).
_build_mata() {
    local worktree=$1 build=$2 prefix=$3 build_mode=$4 jobs=$5

    # Only the library is needed; examples and tests would cost build time.
    cmake -B "$build" -S "$worktree" \
        -DCMAKE_BUILD_TYPE="$build_mode" \
        -DCMAKE_INSTALL_PREFIX="$prefix" \
        -DBUILD_TESTING:BOOL=OFF \
        -DMATA_BUILD_EXAMPLES:BOOL=OFF
    cmake --build "$build" --parallel "$jobs" --target libmata
    # Install merges mata's and 3rd-party headers into one include directory,
    # which is what the harness' find_path() expects.
    cmake --install "$build" >/dev/null
}

# === Main ===

force=false
build_mode="Release"
args=()
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0;;
        -f|--force)
            force=true
            shift 1;;
        -b|--build-mode)
            build_mode="$2"
            shift 2;;
        -*)
            usage "unknown option: $1"
            exit 1;;
        *)
            args+=( "$1" )
            shift 1;;
    esac
done

[ ${#args[@]} -ge 2 ] || { usage "missing subject or revision"; exit 1; }
subject_repo="${args[0]}"
rev="${args[1]}"
slug="${args[2]:-$rev}"
# '/' would turn branch names like 'origin/devel' into directories
slug="${slug//\//-}"

rootdir=$(cd "$(dirname "$0")/.." && pwd)
subject_name=$(basename "$subject_repo")
subject_abs=$(realpath "$rootdir/$subject_repo" 2>/dev/null) ||
    die "subject repo not found: $subject_repo"

harness_src="$rootdir/harnesses/automata-program-parser"
version_dir="$rootdir/build/versions/$subject_name/$slug"
worktree="$version_dir/src"
subject_build="$version_dir/build"
prefix="$version_dir/prefix"
jobs="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

[ -e "$subject_abs/.git" ] || die "$subject_repo: not a git repository"
[ -e "$harness_src/CMakeLists.txt" ] || die "harness not initialised; run 'git submodule update --init --recursive'"

commit=$(git -C "$subject_abs" rev-parse --verify --quiet "$rev^{commit}") ||
    die "$subject_repo: unknown revision '$rev'"

binary_name="emp-interpreter-$subject_name-$slug"
binary="$rootdir/bin/$binary_name"

if [ -x "$binary" ] && [ "$force" = false ]; then
    echo "[!] $subject_name/$slug: already built ($binary); use --force to rebuild"
    exit 0
fi

echo "========== Building $subject_name '$slug' ($commit) ==========="
mkdir -p "$version_dir" "$rootdir/bin"

# Check out the revision into a worktree.
if [ -e "$worktree/.git" ]; then
    git -C "$worktree" checkout --detach --force "$commit"
else
    git -C "$subject_abs" worktree prune
    git -C "$subject_abs" worktree add --detach "$worktree" "$commit"
fi

# Subject-specific build. This can be extended for VATA, Awali, etc.
if [ "$subject_name" = "mata" ]; then
    _build_mata "$worktree" "$subject_build" "$prefix" "$build_mode" "$jobs"
else
    die "unsupported subject: $subject_name (only 'mata' is implemented)"
fi

# Build the harness (interpreter) against this version of the subject.
echo "======== Building harness for $subject_name '$slug' ========"
harness_build="$version_dir/harness-build"
cmake -B "$harness_build" -S "$harness_src" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$prefix"
cmake --build "$harness_build" --parallel "$jobs" --target mata-emp-interpreter

cp "$harness_build/src/cpp/mata-emp-interpreter" "$binary"
echo "$commit" > "$version_dir/COMMIT"
echo "[done] $binary ($(git -C "$worktree" describe --tags --always))"
