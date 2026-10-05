#!/usr/bin/env bash

# Benchmarks several tools and/or several of their revisions against each other.
#
# Every (tool, revision) pair is built into its own binary (see
# scripts/build_version.sh) and registered as a separate pycobench "method", so
# a single run measures all of them on exactly the same inputs. The resulting
# .csv has one group of columns per pair and the run ends with pycobench's
# comparison table (averages, medians, timeouts).
#
# Pairs are given as '<tool>:<rev>[,<rev>...]'; a bare revision list is taken as
# revisions of 'mata'. Revisions are any mix of tags, branches and commits that
# exist in the tool's subject repository.
#
# Examples:
#   # three revisions of mata
#   ./scripts/compare_versions.sh v1.32.32 devel 073777da
#   # the C++ library against the Python bindings, two revisions each
#   ./scripts/compare_versions.sh mata:v1.32.32,devel pymata:v1.32.32,devel

set -euo pipefail

die() {
    echo "error: $*" >&2
    exit 1
}

usage() { {
        [ $# -gt 0 ] && echo "error: $1"
        echo "usage: ./scripts/compare_versions.sh [opts] <spec> [spec...]"
        echo "  <spec>                      '<tool>:<rev>[,<rev>...]', or a bare <rev> of mata"
        echo "options:"
        echo "  -p|--program <prog.emp>     program to run [default=emp-programs/determinize-minimize.emp]"
        echo "  -i|--input <bench.input>    inputs to run on [default=inputs/bench-regexps_union.input]"
        echo "  -t|--timeout <int>          timeout per benchmark in seconds [default=60]"
        echo "  -j|--jobs <int>             number of parallel jobs [default=6]"
        echo "  -o|--output-dir <dir>       store results in 'results/data/<dir>'"
        echo "  -f|--force                  rebuild the binaries even if they exist"
        echo "  -d|--test-run               only run the first input (quick pipeline check)"
        echo "  -l|--list-tools             list the known tools and their subjects"
    } >&2
}

program="emp-programs/determinize-minimize.emp"
input="inputs/bench-regexps_union.input"
timeout=60
jobs=6
output_dir=""
force=""
testrun=""
specs=()

rootdir=$(cd "$(dirname "$0")/.." && pwd)

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0;;
        -l|--list-tools)
            exec "$rootdir/scripts/build_version.sh" --list-tools;;
        -p|--program)
            program="$2"
            shift 2;;
        -i|--input)
            input="$2"
            shift 2;;
        -t|--timeout)
            timeout="$2"
            shift 2;;
        -j|--jobs)
            jobs="$2"
            shift 2;;
        -o|--output-dir)
            output_dir="$2"
            shift 2;;
        -f|--force)
            force="--force"
            shift 1;;
        -d|--test-run)
            testrun="--test-run"
            shift 1;;
        -*)
            usage "unknown option: $1"
            exit 1;;
        *)
            specs+=( "$1" )
            shift 1;;
    esac
done

[ ${#specs[@]} -ge 1 ] || { usage "need at least one '<tool>:<rev>,...' spec"; exit 1; }
cd "$rootdir"

# Expand the specs into parallel (tool, revision) arrays.
tools=()
revs=()
for spec in "${specs[@]}"; do
    if [[ "$spec" == *:* ]]; then
        spec_tool="${spec%%:*}"
        spec_revs="${spec#*:}"
    else
        spec_tool="mata"
        spec_revs="$spec"
    fi
    [ -n "$spec_revs" ] || die "spec '$spec' lists no revision"
    subject=$(./scripts/build_version.sh --list-tools | awk -v t="$spec_tool" '$1 == t { print $2 }')
    [ -n "$subject" ] || die "unknown tool '$spec_tool' (see --list-tools)"
    IFS=',' read -r -a spec_rev_list <<< "$spec_revs"
    for rev in "${spec_rev_list[@]}"; do
        # Fail before building anything, so typos do not surface minutes later.
        git -C "$subject" rev-parse --verify --quiet "$rev^{commit}" >/dev/null 2>&1 ||
            die "$spec_tool: revision '$rev' not found in $subject (try 'git -C $subject fetch --all --tags')"
        tools+=( "$spec_tool" )
        revs+=( "$rev" )
    done
done

[ ${#tools[@]} -ge 2 ] || die "need at least two (tool, revision) pairs to compare"

# run_pyco.sh resolves the config and the inputs relative to the repository root
program=$(realpath --relative-to="$rootdir" "$program") || die "no such program: $program"
input=$(realpath --relative-to="$rootdir" "$input") || die "no such input file: $input"
[ -f "$program" ] || die "no such program: $program"
[ -f "$input" ] || die "no such input file: $input"

methods=()
for i in "${!tools[@]}"; do
    ./scripts/build_version.sh ${force:+"$force"} "${tools[$i]}" "${revs[$i]}"
    methods+=( "${tools[$i]}-${revs[$i]//\//-}" )
done

# Inputs are ';'-delimited; every column becomes one argument of the program.
params=$(( $(head -1 < "$input" | tr -cd ';' | wc -c) + 1 ))
args=""
for i in $(seq 1 "$params"); do
    args+=" \$$i"
done

config_dir="jobs/generated"
config="$config_dir/compare-$(basename "${program%.*}").yaml"
mkdir -p "$config_dir"
{
    echo "# Generated by scripts/compare_versions.sh -- regenerate, do not edit."
    echo "# program: $program"
    echo "# inputs:  $input"
    for method in "${methods[@]}"; do
        echo
        echo "$method:"
        echo "  cmd: ./bin/$method ./$program$args"
    done
} > "$config"

echo "[!] Comparing ${#methods[@]} builds: ${methods[*]}"
echo "[!] Job config: $config"

exec bash ./scripts/run_pyco.sh $testrun --config "$config" --timeout "$timeout" --jobs "$jobs" \
    ${output_dir:+-s "$output_dir"} "$input"
