#!/usr/bin/env bash

# Removes the builds of scripts/build_version.sh that were not rebuilt for a
# while: the revision's worktree and build trees under 'build/versions' and its
# binaries in 'bin'. A build's age is that of its newest BUILD_KEY stamp (one
# per tool, and per library the other tools parse with); a version without any
# is a failed build and goes regardless of age.
#
# Examples:
#   ./scripts/clean_versions.sh --dry-run           # what would go, 30 days
#   ./scripts/clean_versions.sh --older-than 0      # every build

set -euo pipefail

die() {
    echo "error: $*" >&2
    exit 1
}

usage() { {
        [ $# -gt 0 ] && echo "error: $1"
        echo "usage: ./scripts/clean_versions.sh [opts]"
        echo "options:"
        echo "  -o|--older-than <days>      remove builds whose newest binary is older [default=30]"
        echo "  -n|--dry-run                only list what would be removed"
    } >&2
}

days=30
dry_run=false
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0;;
        -o|--older-than)
            days="$2"
            shift 2;;
        -n|--dry-run)
            dry_run=true
            shift 1;;
        *)
            usage "unknown argument: $1"
            exit 1;;
    esac
done
[[ "$days" =~ ^[0-9]+$ ]] || die "--older-than needs a number of days, got '$days'"

rootdir=$(cd "$(dirname "$0")/.." && pwd)
cd "$rootdir"
[ -d build/versions ] || { echo "[!] nothing built"; exit 0; }

now=$(date +%s)
subjects=()
for version_dir in build/versions/*/*/; do
    [ -d "$version_dir" ] || continue
    version_dir="${version_dir%/}"
    slug=$(basename "$version_dir")
    subject=$(basename "$(dirname "$version_dir")")

    # Every directory beside the checkout is a tool built from it, or a
    # library built for the other tools.
    binaries=()
    newest=0
    for stamp in "$version_dir"/*/BUILD_KEY; do
        [ -e "$stamp" ] || continue
        binary="bin/$(basename "$(dirname "$stamp")")-$slug"
        [ ! -e "$binary" ] || binaries+=( "$binary" )
        mtime=$(stat -c %Y "$stamp")
        [ "$mtime" -le "$newest" ] || newest=$mtime
    done
    if [ "$newest" -gt 0 ] && [ $(( (now - newest) / 86400 )) -lt "$days" ]; then
        continue
    fi

    size=$(du -sh "$version_dir" | cut -f1)
    echo "[-] $subject/$slug ($size${binaries[*]:+, ${binaries[*]}})"
    [ "$dry_run" = false ] || continue
    if [ -e "$version_dir/src/.git" ] && [ -e "subjects/$subject/.git" ]; then
        git -C "subjects/$subject" worktree remove --force "$rootdir/$version_dir/src" 2>/dev/null || true
        [[ " ${subjects[*]} " == *" $subject "* ]] || subjects+=( "$subject" )
    fi
    rm -rf "$version_dir" "${binaries[@]}"
done

for subject in "${subjects[@]}"; do
    git -C "subjects/$subject" worktree prune
done
