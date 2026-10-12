#!/usr/bin/env bash

# Runs one pycobench job config on .input files and turns each run into a
# ';'-delimited .csv under 'results/data[/<suffix>]'.
#
# Called by scripts/compare_versions.sh, which generates the job config.

set -euo pipefail

usage() { {
        [ $# -gt 0 ] && echo "error: $1"
        echo "usage: ./scripts/run_pyco.sh [opts] <bench.input> [bench.input...]"
        echo "options:"
        echo "  -c|--config <conf.yaml>     pycobench job config (required)"
        echo "  -t|--timeout <int>          timeout per benchmark in seconds [default=60]"
        echo "  -m|--methods <a;b>          measure only these methods"
        echo "  -e|--exclude <a;b>          do not measure these methods"
        echo "  -j|--jobs <int>             number of parallel jobs [default=6]"
        echo "  -s|--suffix <dir>           store the results in 'results/data/<dir>'"
        echo "  -v|--verbose                verbose pycobench"
        echo "  -d|--test-run               run only the first benchmark of each input"
        echo "  -n|--test-run-count <int>   run only the first <int> benchmarks (with --test-run)"
    } >&2
}

die() {
    echo "error: $*" >&2
    exit 1
}

timeout=60
jobs=6
benchmarks=()
pyco_opts=()
suffix=""
config=""
testrun=false
testrun_count=1
GR='\033[0;32m'
RD='\033[0;31m'
NC='\033[0m'

rootdir=$(cd "$(dirname "$0")/.." && pwd)
pycobench_dir="$rootdir/harnesses/pycobench"
pyco_python="$pycobench_dir/.venv/bin/python3"
[ -x "$pyco_python" ] || die "pycobench's Python environment not found at $pyco_python. Run 'just setup-python' first."

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0;;
        -s|--suffix)
            suffix="$2"
            shift 2;;
        -t|--timeout)
            timeout="$2"
            shift 2;;
        -c|--config)
            config="$2"
            shift 2;;
        -j|--jobs)
            jobs="$2"
            shift 2;;
        -v|--verbose)
            pyco_opts+=( -v )
            shift 1;;
        -m|--methods)
            pyco_opts+=( -m "$2" )
            shift 2;;
        -e|--exclude)
            pyco_opts+=( -e "$2" )
            shift 2;;
        -d|--test-run)
            testrun=true
            shift 1;;
        -n|--test-run-count)
            testrun_count="$2"
            shift 2;;
        -*)
            usage "unknown option: $1"
            exit 1;;
        *)
            benchmarks+=( "$1" )
            shift 1;;
    esac
done

[ -n "$config" ] || { usage "missing --config"; exit 1; }
[ ${#benchmarks[@]} -gt 0 ] || { usage "you must specify some *.input file with benchmarks"; exit 1; }

# Job configs and inputs name binaries and automata relative to the root.
cd "$rootdir"
[[ "$config" == *.yaml ]] || config="$config.yaml"
[ -f "$config" ] || die "no such job config: $config"

result_dir="results/data${suffix:+/$suffix}"
mkdir -p "$result_dir"

pyco() {
    env -u PYTHONPATH "$pyco_python" "$@"
}

start_time=$SECONDS
for benchmark in "${benchmarks[@]}"; do
    [[ "$benchmark" == *.input ]] || benchmark="$benchmark.input"
    [ -f "$benchmark" ] || die "no such input: $benchmark"
    benchmark_name=$(basename "${benchmark%.*}")
    job_name=$(basename "${config%.*}")
    result_file="$result_dir/$job_name-$benchmark_name-$(date +%Y-%m-%d-%H-%M-%S)-timeout-$timeout-jobs-$jobs"
    log="$result_file.log"
    echo "[!] Result file: $result_file.csv"

    if [ "$testrun" = true ]; then
        head -n "$testrun_count" "$benchmark" |
            pyco "$pycobench_dir/src/pycobench.py" "${pyco_opts[@]}" -j "$jobs" -c "$config" -t "$timeout" -o "$log"
    else
        pyco "$pycobench_dir/src/pycobench.py" "${pyco_opts[@]}" -j "$jobs" -c "$config" -t "$timeout" -o "$log" < "$benchmark"
    fi
    echo "[$benchmark] Benchmark measured"

    number_of_params=$(( $(head -1 < "$benchmark" | tr -cd ';' | wc -c) + 1 ))
    PYCOBENCH_PYTHON="$pyco_python" "$pycobench_dir/src/process_pyco.sh" -o "$result_file.csv" -p "$number_of_params" "$log"
    echo "[$benchmark] Benchmark processed"

    if [ "$testrun" = true ]; then
        errors=$(grep -c "error" "$log" || true)
        if [ "$errors" = 0 ]; then
            echo -e "${GR}[✓] $job_name ready for full benchmarking!${NC}"
        else
            echo -e "${RD}[✗] $job_name contains $errors errors.${NC}"
        fi
    fi

    pyco "$pycobench_dir/src/compare_profiles.py" "$result_file.csv"
done

secs=$((SECONDS - start_time))
printf "[!] Benchmarking done in %dd:%dh:%dm:%ds\n" $((secs/86400)) $((secs%86400/3600)) $((secs%3600/60)) $((secs%60))
