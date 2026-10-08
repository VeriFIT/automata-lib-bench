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
# exist in the tool's subject repository, and '<rev>=<label>' names the build
# something shorter than a commit hash in the tables and plots.
#
# 'pr/<N>' stands for GitHub pull request N and expands to the two builds it is
# about: the commit it is based on and its tip, labelled '<label>-base' and
# '<label>-head'. Both are fetched from the subject's remote.
#
# The run ends in its own directory under 'results/data', holding the .csv, the
# summary and pairwise tables, and the scatter and cactus plots.
#
# Examples:
#   # three revisions of mata
#   ./scripts/compare_versions.sh v1.32.32 devel 073777da
#   # one commit against its parent, under readable names
#   ./scripts/compare_versions.sh 24a00cf0=after 24a00cf0^=before
#   # a pull request against what it branched off
#   ./scripts/compare_versions.sh pr/885=antichain
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
        echo "  <spec>                      '<tool>:<rev>[=<label>][,...]', or a bare <rev> of mata"
        echo "                              <rev> may be 'pr/<N>': the base and the tip of pull request N"
        echo "options:"
        echo "  -p|--program <prog.emp>     program to run [default=emp-programs/determinize-minimize.emp]"
        echo "  -i|--input <bench.input>    inputs to run on; repeatable, one .csv per file"
        echo "                              [default=inputs/bench-regexps_union.input]"
        echo "  -t|--timeout <int>          timeout per benchmark in seconds [default=60]"
        echo "  -j|--jobs <int>             number of parallel jobs [default=6]"
        echo "  -o|--output-dir <dir>       store the run in 'results/data/<dir>'"
        echo "                              [default=<program>-<timestamp>]"
        echo "  -f|--force                  rebuild the binaries even if they exist"
        echo "  -d|--test-run               only run the first input (quick pipeline check)"
        echo "  -R|--no-report              skip the plots and tables"
        echo "  -l|--list-tools             list the known tools and their subjects"
    } >&2
}

program="emp-programs/determinize-minimize.emp"
inputs=()
timeout=60
jobs=6
output_dir=""
force=""
testrun=""
report=true
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
            inputs+=( "$2" )
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
        -R|--no-report)
            report=false
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

# Resolves 'pr/<N>' of a GitHub pull request into the commits it compares. Both
# are fetched into the subject, because the head lives in a 'pull/<N>/head' ref
# that a plain clone does not have and the base may be newer than the last fetch.
pr_commits() {
    local subject=$1 number=$2 remote base head
    command -v gh >/dev/null || die "resolving 'pr/$number' needs the 'gh' CLI"
    remote=$(git -C "$subject" remote | grep -x origin || git -C "$subject" remote | head -1)
    [ -n "$remote" ] || die "$subject has no remote to resolve 'pr/$number' against"
    local slug
    slug=$(git -C "$subject" remote get-url "$remote" |
        sed -E 's#^(git@[^:]+:|https?://[^/]+/)##; s#\.git$##')
    read -r base head < <(
        gh api "repos/$slug/pulls/$number" --jq '"\(.base.sha) \(.head.sha)"'
    ) || die "could not read pull request $number of $slug"
    git -C "$subject" fetch --quiet "$remote" "+refs/pull/$number/head:refs/remotes/$remote/pr/$number" ||
        die "could not fetch pull request $number of $slug"
    git -C "$subject" fetch --quiet "$remote" "$base" 2>/dev/null || true
    echo "$base $head"
}

# Expand the specs into parallel (tool, revision, label) arrays.
tools=()
revs=()
labels=()
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
    entries=()
    for entry in "${spec_rev_list[@]}"; do
        # Without '<rev>=<label>' the revision names itself: the tag, branch,
        # commit or pull request as it was written on the command line.
        rev="${entry%%=*}"
        label="${entry#*=}"
        if [ "$label" = "$entry" ]; then label="$rev"; fi
        # 'pr/<N>' is the one revision that stands for two: what the pull request
        # changes and what it is measured against.
        if [[ "$rev" =~ ^pr/([0-9]+)$ ]]; then
            [ "$label" != "$rev" ] || label="pr${BASH_REMATCH[1]}"
            read -r pr_base pr_head < <(pr_commits "$subject" "${BASH_REMATCH[1]}")
            entries+=( "$pr_base=$label-base" "$pr_head=$label-head" )
        else
            entries+=( "$rev=$label" )
        fi
    done
    for entry in "${entries[@]}"; do
        rev="${entry%%=*}"
        label="${entry#*=}"
        [ -n "$rev" ] || die "spec '$spec' lists an empty revision"
        # Fail before building anything, so typos do not surface minutes later.
        git -C "$subject" rev-parse --verify --quiet "$rev^{commit}" >/dev/null 2>&1 ||
            die "$spec_tool: revision '$rev' not found in $subject (try 'git -C $subject fetch --all --tags')"
        tools+=( "$spec_tool" )
        revs+=( "$rev" )
        # The label ends up in column names, file names and plot legends, so
        # everything a revision may contain ('/', '^', '~', ':') is folded away.
        labels+=( "$(printf '%s' "$label" | tr -cs 'A-Za-z0-9._-' '-' | sed -E 's/-+$//')" )
    done
done

[ ${#tools[@]} -ge 2 ] || die "need at least two (tool, revision) pairs to compare"

# run_pyco.sh resolves the config and the inputs relative to the repository root
program=$(realpath --relative-to="$rootdir" "$program") || die "no such program: $program"
[ -f "$program" ] || die "no such program: $program"

[ ${#inputs[@]} -gt 0 ] || inputs=( "inputs/bench-regexps_union.input" )
for i in "${!inputs[@]}"; do
    inputs[$i]=$(realpath --relative-to="$rootdir" "${inputs[$i]}") || die "no such input file: ${inputs[$i]}"
    [ -f "${inputs[$i]}" ] || die "no such input file: ${inputs[$i]}"
done
# Every input must feed the program the same number of automata.
params=$(head -1 < "${inputs[0]}" | tr -cd ';' | wc -c)
for input in "${inputs[@]}"; do
    [ "$(head -1 < "$input" | tr -cd ';' | wc -c)" = "$params" ] ||
        die "$input does not have the same number of columns as ${inputs[0]}"
done

methods=()
for i in "${!tools[@]}"; do
    ./scripts/build_version.sh ${force:+"$force"} "${tools[$i]}" "${revs[$i]}" "${labels[$i]}"
    methods+=( "${tools[$i]}-${labels[$i]}" )
done

# Inputs are ';'-delimited; every column becomes one argument of the program.
args=""
for i in $(seq 1 $((params + 1))); do
    args+=" \$$i"
done

config_dir="jobs/generated"
config="$config_dir/compare-$(basename "${program%.*}").yaml"
mkdir -p "$config_dir"
{
    echo "# Generated by scripts/compare_versions.sh -- regenerate, do not edit."
    echo "# program: $program"
    echo "# inputs:  ${inputs[*]}"
    for method in "${methods[@]}"; do
        echo
        echo "$method:"
        echo "  cmd: ./bin/$method ./$program$args"
    done
} > "$config"

# One directory per run keeps the .csv together with the report generated from it.
program_name=$(basename "${program%.*}")
: "${output_dir:=$program_name-$(date +%Y-%m-%d-%H-%M-%S)}"

echo "[!] Comparing ${#methods[@]} builds: ${methods[*]}"
echo "[!] Job config: $config"
echo "[!] Results:    results/data/$output_dir"

bash ./scripts/run_pyco.sh $testrun --config "$config" --timeout "$timeout" --jobs "$jobs" \
    -s "$output_dir" "${inputs[@]}"

[ "$report" = true ] || exit 0
exec bash ./scripts/report.sh --timeout "$timeout" --baseline "${methods[0]}" \
    --title "$program_name" "results/data/$output_dir"
