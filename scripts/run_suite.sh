#!/usr/bin/env bash

# Runs every experiment of a suite (suites/*.suite) through
# scripts/compare_versions.sh, each into its own directory of one run:
# 'results/data/<suite>-<timestamp>/<experiment>'.
#
# Everything after the suite is passed on to compare_versions.sh: the builds to
# compare and options such as --timeout, --jobs or --repeat.
#
# Examples:
#   ./scripts/run_suite.sh suites/tacas-24.suite v1.32.32 devel
#   ./scripts/run_suite.sh --only armc-incl,b-smt suites/tacas-24.suite --repeat 3 devel=new v1.32.32=old

set -euo pipefail

die() {
    echo "error: $*" >&2
    exit 1
}

usage() { {
        [ $# -gt 0 ] && echo "error: $1"
        echo "usage: ./scripts/run_suite.sh [--only <a,b>] [--list] <suite> [compare_versions args...]"
        echo "options:"
        echo "  --only <a,b>                run only these experiments of the suite"
        echo "  --list                      list the experiments of the suite and exit"
    } >&2
}

only=""
list=false
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0;;
        --only)
            only=",$2,"
            shift 2;;
        --list)
            list=true
            shift 1;;
        *)
            break;;
    esac
done

[ $# -ge 1 ] || { usage "missing suite"; exit 1; }
suite=$1
shift
[ -f "$suite" ] || die "no such suite: $suite"

rootdir=$(cd "$(dirname "$0")/.." && pwd)
suite=$(realpath "$suite")
cd "$rootdir"

names=()
lines=()
while read -r name program input opts; do
    case "$name" in ''|'#'*) continue ;; esac
    [ -n "$input" ] || die "$suite: experiment '$name' lacks a program or an input"
    names+=( "$name" )
    lines+=( "$name $program $input $opts" )
done < "$suite"

if [ "$list" = true ]; then
    printf '%s\n' "${names[@]}"
    exit 0
fi

if [ -n "$only" ]; then
    IFS=',' read -r -a wanted <<< "${only#,}"
    for name in "${wanted[@]}"; do
        [[ " ${names[*]} " == *" $name "* ]] || die "$suite has no experiment '$name'"
    done
fi

run_dir="$(basename "${suite%.*}")-$(date +%Y-%m-%d-%H-%M-%S)"
echo "[!] Suite run: results/data/$run_dir"
for line in "${lines[@]}"; do
    read -r name program input opts <<< "$line"
    [ -z "$only" ] || [[ "$only" == *",$name,"* ]] || continue
    read -r -a entry_opts <<< "$opts"
    program_opts=()
    [ "$program" = "-" ] || program_opts=( --program "$program" )
    echo "========== $name =========="
    ./scripts/compare_versions.sh "${program_opts[@]}" --input "$input" \
        --output-dir "$run_dir/$name" "$@" "${entry_opts[@]}"
done
