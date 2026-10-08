#!/usr/bin/env bash

# Turns measurements into the plots and tables an experiment is reported with.
#
# Takes either a result .csv written by scripts/run_pyco.sh, or a directory
# below 'results/data' (then every .csv in it is reported, newest first). The
# report lands next to the .csv in '<csv-without-extension>-report': summary and
# pairwise tables as .csv/.md/.tex, a cactus plot, and one scatter plot per
# measured build against the baseline.
#
# scripts/compare_versions.sh calls this at the end of every run; call it
# directly to re-report an old run, or to report a different metric.
#
# Examples:
#   ./scripts/report.sh results/data/words_of_lengths-10-2026-10-08-14-00-00
#   ./scripts/report.sh --metric words_of_lengths --timeout 60 run.csv

set -euo pipefail

die() {
    echo "error: $*" >&2
    exit 1
}

usage() { {
        [ $# -gt 0 ] && echo "error: $1"
        echo "usage: ./scripts/report.sh [opts] <run.csv|results/data/<dir>>"
        echo "options:"
        echo "  -m|--metric <name>          metric to report; repeatable, 'all' for every shared"
        echo "                              one [default=runtime]"
        echo "  -t|--timeout <int>          timeout of the run; draws the limit, scores PAR-2"
        echo "  -b|--baseline <method>      method the others are compared against"
        echo "                              [default=the first one in the table]"
        echo "  -e|--methods <a,b,...>      only report these methods, in this order"
        echo "  -o|--output-dir <dir>       write the report here instead of next to the .csv"
        echo "  -F|--formats <a,b>          figure formats [default=pdf,png]"
        echo "  --title <text>              title of the figures"
    } >&2
}

rootdir=$(cd "$(dirname "$0")/.." && pwd)
pycobench_dir="$rootdir/harnesses/pycobench"
pyco_python="$pycobench_dir/.venv/bin/python3"

args=()
plot_args=()
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0;;
        -m|--metric)
            plot_args+=( --metric "$2" )
            shift 2;;
        -t|--timeout)
            plot_args+=( --timeout "$2" )
            shift 2;;
        -b|--baseline)
            plot_args+=( --baseline "$2" )
            shift 2;;
        -e|--methods)
            plot_args+=( --engines "$2" )
            shift 2;;
        -o|--output-dir)
            plot_args+=( --output-dir "$2" )
            shift 2;;
        -F|--formats)
            plot_args+=( --formats "$2" )
            shift 2;;
        --title)
            plot_args+=( --title "$2" )
            shift 2;;
        -*)
            usage "unknown option: $1"
            exit 1;;
        *)
            args+=( "$1" )
            shift 1;;
    esac
done

[ ${#args[@]} -eq 1 ] || { usage "need exactly one result .csv or directory"; exit 1; }
[ -x "$pyco_python" ] || die "pycobench's Python environment not found at $pyco_python. Run 'just setup-python' first."

target="${args[0]}"
csvs=()
if [ -d "$target" ]; then
    while IFS= read -r csv; do csvs+=( "$csv" ); done < <(find "$target" -maxdepth 1 -name '*.csv' | sort -r)
    [ ${#csvs[@]} -gt 0 ] || die "no .csv in $target"
else
    [ -f "$target" ] || die "no such result file: $target"
    csvs=( "$target" )
fi

for csv in "${csvs[@]}"; do
    echo "[!] Reporting $csv"
    env -u PYTHONPATH "$pyco_python" "$pycobench_dir/src/pyco_plot.py" "${plot_args[@]}" "$csv"
done
