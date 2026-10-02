#!/bin/bash

# Helper script that runs experiments and generates .csv files.
#
# The results are stored in results/data directory.
#
# The result of the script is in form of `;` delimited .csv file for set of outputs of benchmarks.

usage() { {
        [ $# -gt 0 ] && echo "error: $1"
        echo "usage: ./run_experiments.sh [opt1, ..., optn] [bench1, ..., benchm]"
        echo "options:"
        echo "  -c|--config <conf.yaml>     configuration file in yaml format [default=jobs/bench-cade-23.yaml]"
        echo "  -t|--timeout <int>         timeout for each benchmark in seconds [default=60s]"
        echo "  -m|--methods                will measure only selected tools"
        echo "  -e|--exclude                will exclude selected tools"
        echo "  -j|--jobs                   number of parallel jobs"
        echo "  -s|--suffix                 adds suffix to the target file"
        echo "  -v|--verbose                adds verbosity to pycobench"
        echo "  -d|--test-run               will run only single benchmark from each input"
        echo "  -c|--test-run-count         will run only <INT> benchmark from each input (used for test-run)"
    } >&2
}

die() {
    echo "error: $*" >&2
    exit 1
}

# Be default we run the experiments on 6 CPUs (any more, in our experience, leads to some unexpected
# behaviour), it deletes temporary files, runs no warmups, and measures once with timeout 60s.
# In our experience, 60s timeout is enough.
timeout=60
benchmarks=()
jobs=6
methods=
exclude=
suffix=""
basedir=$(realpath $(dirname "$0"))
rootdir=$(realpath "$basedir/..")
pycobench_dir="$rootdir/harnesses/pycobench"
pyco_python="$pycobench_dir/.venv/bin/python3"
[ -x "$pyco_python" ] || die "pycobench's Python environment not found at $pyco_python. Run 'just setup-python' first."
config=
verbose=""
testrun=false
testrun_count=1
GR='\033[0;32m'
RD='\033[0;31m'
NC='\033[0m' # No Color

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
            jobs=$2
            shift 2;;
        -v|--verbose)
            verbose="-v"
            shift 1;;
        -m|--methods)
            methods="-m $2"
            shift 2;;
        -e|--exclude)
            exclude="-e $2"
            shift 2;;
        -d|--test-run)
            testrun=true
            shift 1;;
        -c|--test-run-count)
            testrun_count=$2
            shift 2;;
        *)
            benchmarks+=( $1 )
            shift 1;;
    esac
done

# $1: filename, $2: extension
# Adds extension $2 to the $filename, unless it already contains it
escape_extension () {
  if [[ "$1" == *.$2 ]];
  then
    echo "$1"
  else
    echo "$1.$2"
  fi
}

# $1: filename, $2: directory
# Adds $2 directory before the filename, unless it already contains it
prepend_directory() {
  if [[ "$1" == $2/* ]];
  then
    echo "$1"
  else
    echo "$2/$1"
  fi
}

# Check that dependencies for running pycobench were installed

tmp_output=$(mktemp)
env -u PYTHONPATH "$pyco_python" "$pycobench_dir/src/pycobench.py" >& "$tmp_output"
# if grep -q ModuleNotFoundError "$tmp_output"; then
  # die "error: your system is missing python modules for running pycobench. Did you run 'install requirements.sh'?"
# fi
rm "$tmp_output"

# Prepares configuration
config=$(escape_extension "$config" "yaml")
result_dir=$rootdir/results/data
if [ -n "$suffix" ]; then
  result_dir="$result_dir/$suffix"
fi
mkdir -p "$result_dir"

[ ${#benchmarks[@]} -gt 0 ] 2>/dev/null || die "error: you must specify some *.input file with benchmarks"

start_time=$SECONDS
for benchmark in ${benchmarks[@]}
do
    # Script takes .input files with list of benchmarks
    benchmark_file=$(escape_extension "$benchmark" "input")
    # The result contains information about date, timeout, number of jobs and measured subset of tools (if specified)
    # Run the script with -s|--suffix to append other information to your benchmarks
    benchmark_name=$(basename "$benchmark")
    job_name=$(basename "$config")
    result_file=$result_dir/${job_name%.*}-${benchmark_name%.*}-$(date +%Y-%m-%d-%H-%M-%S)-timeout-$timeout-jobs-$jobs$methods
    result_file=$(echo -e "${result_file// /-}")
    echo "[!] Result file: $result_file"

    # Perform actual runs
    intermediate=()
    echo "[!] Performing benchmarks"
    sub_result_file="$result_file.log"
    intermediate+=( $sub_result_file )
    if [ "$testrun" = true ]; then

      cat "$rootdir/$benchmark_file" | head -$testrun_count | env -u PYTHONPATH "$pyco_python" "$pycobench_dir/src/pycobench.py" $exclude $methods $verbose -j "$jobs" -c "$config" -t "$timeout" -o "$sub_result_file"
    else
      env -u PYTHONPATH "$pyco_python" "$pycobench_dir/src/pycobench.py" $exclude $methods $verbose -j "$jobs" -c "$rootdir/$config" -t "$timeout" -o "$sub_result_file" < "$benchmark_file"
    fi

    number_of_params=$(($(head -1 < "$benchmark_file"  | tr -cd ';' | wc -c) + 1))

    echo "[$benchmark] Benchmark measured"
    echo "Result file: $result_file.csv"
    echo "Interm file: ${intermediate[@]}"
    "$rootdir"/harnesses/pycobench/src/process_pyco.sh -o "$result_file.csv" -p $number_of_params ${intermediate[@]}
    echo "[$benchmark] Benchmark processed"

    if [ "$testrun" = true ]; then
      errors=$(grep "error" ${intermediate[@]} | wc -l)
      if [ $errors = "0" ]; then
        echo -e "${GR}[✓] $job_name ready for full benchmarking!${NC}"
      else
        echo -e "${RD}[✗] $job_name contains $errors errors.${NC}"
      fi
    fi
done

env -u PYTHONPATH "$pyco_python" "$pycobench_dir/src/compare_profiles.py" "$result_file.csv"

secs=$((SECONDS - start_time))
formatted_elapsed=$(printf "%dd:%dh:%dm:%ds\n" $((secs/86400)) $((secs%86400/3600)) $((secs%3600/60)) $((secs%60)))
eval "echo [!] Benchmarking done in $formatted_elapsed"
