#!/bin/bash

# The setup is wrt our paper: 6 parallel jobs with 60s timeout
BASEDIR=$(dirname "$0")
TIMEOUT=60
JOBS=6
OUTPUT_DIR=""
OUTPUT_DIR_NAME=""
METHODS=""
EXCLUDE=""
TEST_RUN=""
TEST_RUN_COUNT=1
SAY_YES="false"

# Each benchmark corresponds to naming in our paper; set to "true" to run concrete benchmark
# or use the CLI commands.
ALL="true"
ARMC_INCL="false"
B_SMT="false"
EMAIL_FILTER="false"
LIA_EXPLICIT="false"
LIA_SYMBOLIC="false"
REGEXPS_UNION_DETERMINIZE_MINIMIZE="false"
DETERMINIZE_MINIMIZE_AUTOMATALIB_ALL="false"
DETERMINIZE_AUTOMATALIB_ALL="false"
NOODLER_COMPL="false"
NOODLER_CONCAT="false"
NOODLER_INTER="false"
PARAM_INTER="false"
PARAM_UNION="false"
PARAM_DIFF="false"

usage() { {
        [ $# -gt 0 ] && echo "error: $1"
        echo "usage: ./run_all.sh [opt1, ..., optn]"
        echo "options:"
        echo "     --test-run               will conduct a test run (5s timeout, only 1 instance per benchmark)"
        echo "     --test-run-count         will conduct a test run (5s timeout, only <INT> instance per benchmark)"
        echo "  -t|--timeout                will set a timeout to <INT> seconds (default 60s)"
        echo "  -o|--output-dir             will store the results in 'results/data/<DIR>'"
        echo "  -m|--methods                will measure only selected tools"
        echo "  -e|--exclude                will not measure selected tools"
        echo "  -j|--jobs                   will run only number of jobs"
        echo "  -y|--no-interaction         will not interact with use in --test-run"
        echo "     --armc-incl              will run 'armc-incl' benchmark"
        echo "     --b-smt                  will run 'b-smt' benchmark"
        echo "     --email-filter           will run 'email-filter' benchmark"
        echo "     --lia-explicit           will run 'lia-explicit' benchmark"
        echo "     --lia-symbolic           will run 'lia-symbolic' benchmark"
        echo "     --noodler-compl          will run 'noodler-compl' benchmark"
        echo "     --noodler-concat         will run 'noodler-concat' benchmark"
        echo "     --noodler-inter          will run 'noodler-inter' benchmark"
        echo "     --param-inter            will run 'param-inter' benchmark"
        echo "     --param-union            will run 'param-union' benchmark"
        echo "     --param-diff             will run 'param-diff' benchmark"
        echo "     --regexps_union-determinize-minimize             will run 'param-diff' benchmark"
        echo "     --determinize-minimize-automatalib-all             "
        echo "     --determinize-automatalib-all             "
    } >&2
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0;;
        --test-run)
            TIMEOUT=5
            TEST_RUN="--test-run"
            shift 1;;
        --test-run-count)
            TIMEOUT=5
            TEST_RUN="--test-run --test-run-count $2"
            shift 2;;
        -y|--no-interaction)
            SAY_YES="true"
            shift 1;;
        -m|--methods)
            METHODS="-m $2"
            shift 2;;
        -o|--output-dir)
            OUTPUT_DIR="-s $2"
            OUTPUT_DIR_NAME="$2"
            shift 2;;
        -t|--timeout)
            TIMEOUT=$2
            shift 2;;
        -e|--exclude)
            EXCLUDE="-e $2"
            shift 2;;
        -j|--jobs)
            JOBS=$2
            shift 2;;
        --armc-incl)
            ARMC_INCL="true"
            ALL="false"
            shift 1;;
        --b-smt)
            B_SMT="true"
            ALL="false"
            shift 1;;
        --email-filter)
            EMAIL_FILTER="true"
            ALL="false"
            shift 1;;
        --regexps_union-determinize-minimize)
            REGEXPS_UNION_DETERMINIZE_MINIMIZE="true"
            ALL="false"
            shift 1;;
        --determinize-minimize-automatalib-all)
            DETERMINIZE_MINIMIZE_AUTOMATALIB_ALL="true"
            ALL="false"
            shift 1;;
        --determinize-automatalib-all)
            DETERMINIZE_AUTOMATALIB_ALL="true"
            ALL="false"
            shift 1;;
        --lia-explicit)
            LIA_EXPLICIT="true"
            ALL="false"
            shift 1;;
        --lia-symbolic)
            LIA_SYMBOLIC="true"
            ALL="false"
            shift 1;;
        --noodler-compl)
            NOODLER_COMPL="true"
            ALL="false"
            shift 1;;
        --noodler-concat)
            NOODLER_CONCAT="true"
            ALL="false"
            shift 1;;
        --noodler-inter)
            NOODLER_INTER="true"
            ALL="false"
            shift 1;;
        --param-inter)
            PARAM_INTER="true"
            ALL="false"
            shift 1;;
        --param-union)
            PARAM_UNION="true"
            ALL="false"
            shift 1;;
        --param-diff)
            PARAM_DIFF="true"
            ALL="false"
            shift 1;;
        *)
            echo "unknown parameter: $1"
	    shift 1;;
    esac
done

run_benchmark() {
    # :param $1: path to configuration .yaml file
    # :param $2: path to inputs .input file
    # :param $3: number of parallel jobs
    "$BASEDIR/scripts/run_pyco.sh" $TEST_RUN $EXCLUDE $METHODS --config $1 --timeout "$TIMEOUT" --jobs $3 $OUTPUT_DIR $2
    if [ "$TEST_RUN" != "" ] && [ "$SAY_YES" == "false" ]; then
        read -p "Press <any> key to continue"
    fi
}

start_time=$SECONDS

if [ "$ALL" = "true" ]; then
    echo "[!] Running all benchmarks, this will take some time (could take over 14 hours, or even days)"
fi

if [ "$TEST_RUN" != "" ]; then
    echo "[!] Selected dry run: timeout set to $TIMEOUT; only one instance per benchmark will be run (unless specific benchmarks were selected)."
    echo "[!] Note, that there might be some timeouts in the output, which is expected. No errors should be present"
    echo "[!] At the end of each benchmark, we print: "
    echo "  (1) short summary with average times,"
    echo "  (2) short summary with timeouts."
    if [ "$SAY_YES" = "false" ]; then
        echo "[!] You will be prompted to press <any> key after each benchmark to inspect the results"
        echo "[!] Run './run_all.sh --test-run -y' to disable the prompts"
        read -p "Press <any> key to continue"
    fi
fi

if [ "$ARMC_INCL" = "true" ] || [ "$ALL" = "true" ]; then
    echo "============= Running 'armc-incl' benchmark =============="
    run_benchmark "$BASEDIR/jobs/tacas-24-automata-inclusion.yaml" "$BASEDIR/inputs/bench-double-automata-inclusion.input" $JOBS
fi

if [ "$B_SMT" = "true" ] || [ "$ALL" = "true" ]; then
    echo "============== Running 'b-smt' benchmark ================"
    run_benchmark "$BASEDIR/jobs/tacas-24-bool-comb-ere.yaml" "$BASEDIR/inputs/bench-variadic-bool-comb-ere.input" $JOBS
fi

if [ "$EMAIL_FILTER" = "true" ] || [ "$ALL" = "true" ]; then
    # Note: For email filter we run the results in sequence, since, there might be a minor issue
    # with our helper scripts that generate transformed .mata formulae.
    # The reason is that for each instance, we reuse the .mata files to generate .mata.minterm files,
    # in rare cases, the tools might wrongly rewrite the generated .mata.minterm file.
    echo "=========== Running 'email-filter' benchmark ============"
    run_benchmark "$BASEDIR/jobs/tacas-24-email-filter.yaml" "$BASEDIR/inputs/bench-quintuple-email-filter.input" 1
fi

if [ "$LIA_EXPLICIT" = "true" ] || [ "$ALL" = "true" ]; then
    echo "=========== Running 'lia-explicit' benchmark ============"
    run_benchmark "$BASEDIR/jobs/tacas-24-presburger-complement.yaml" "$BASEDIR/inputs/bench-single-presburger-explicit-complement.input" $JOBS
fi

if [ "$REGEXPS_UNION_DETERMINIZE_MINIMIZE" = "true" ] || [ "$ALL" = "true" ]; then
    echo "=========== Running 'regexps_union-determinize-minimize' benchmark ============"
    run_benchmark "$BASEDIR/jobs/determinize-minimize.yaml" "$BASEDIR/inputs/bench-regexps_union.input" $JOBS
fi

if [ "$DETERMINIZE_MINIMIZE_AUTOMATALIB_ALL" = "true" ] || [ "$ALL" = "true" ]; then
    echo "=========== Running 'determinize-minimize-all' benchmark ============"
    run_benchmark "$BASEDIR/jobs/determinize-minimize.yaml" "$BASEDIR/inputs/bench-automatalib-all.input" $JOBS
fi

if [ "$DETERMINIZE_AUTOMATALIB_ALL" = "true" ] || [ "$ALL" = "true" ]; then
    echo "=========== Running 'determinize-all' benchmark ============"
    run_benchmark "$BASEDIR/jobs/determinize.yaml" "$BASEDIR/inputs/bench-automatalib-all.input" $JOBS
fi

if [ "$LIA_SYMBOLIC" = "true" ] || [ "$ALL" = "true" ]; then
    echo "============== Running 'b-smt' benchmark ================"
    echo "=========== Running 'lia-symbolic' benchmark ============"
    run_benchmark "$BASEDIR/jobs/tacas-24-presburger-complement.yaml" "$BASEDIR/inputs/bench-single-presburger-complement.input" $JOBS
fi

if [ "$NOODLER_COMPL" = "true" ] || [ "$ALL" = "true" ]; then
    echo "========== Running 'noodler-compl' benchmark ============"
    run_benchmark "$BASEDIR/jobs/tacas-24-z3-noodler.yaml" "$BASEDIR/inputs/bench-single-z3-noodler.input" $JOBS
    run_benchmark "$BASEDIR/jobs/tacas-24-z3-noodler.yaml" "$BASEDIR/inputs/bench-single-z3-noodler-big.input" $JOBS
fi

if [ "$NOODLER_CONCAT" = "true" ] || [ "$ALL" = "true" ]; then
    echo "========== Running 'noodler-concat' benchmark ==========="
    run_benchmark "$BASEDIR/jobs/tacas-24-z3-noodler-concat.yaml" "$BASEDIR/inputs/bench-single-z3-noodler.input" $JOBS
fi

if [ "$NOODLER_INTER" = "true" ] || [ "$ALL" = "true" ]; then
    echo "========== Running 'noodler-inter' benchmark ============"
    run_benchmark "$BASEDIR/jobs/tacas-24-bool-comb-intersect.yaml" "$BASEDIR/inputs/bench-variadic-z3-noodler-intersect.input" $JOBS
fi

if [ "$PARAM_INTER" = "true" ] || [ "$ALL" = "true" ]; then
    echo "=========== Running 'param-inter' benchmark ============="
    run_benchmark "$BASEDIR/jobs/tacas-24-bool-comb-cox-inter.yaml" "$BASEDIR/inputs/bench-double-bool-comb-cox.input" $JOBS
    run_benchmark "$BASEDIR/jobs/tacas-24-bool-comb-intersect.yaml" "$BASEDIR/inputs/bench-variadic-bool-comb-intersect.input" $JOBS
fi

if [ "$PARAM_UNION" = "true" ] || [ "$ALL" = "true" ]; then
    echo "=========== Running 'param-union' benchmark ============="
    run_benchmark "$BASEDIR/jobs/tacas-24-bool-comb-cox-union.yaml" "$BASEDIR/inputs/bench-double-bool-comb-cox.input" $JOBS
    run_benchmark "$BASEDIR/jobs/tacas-24-bool-comb-intersect-union.yaml" "$BASEDIR/inputs/bench-variadic-bool-comb-intersect.input" $JOBS
fi

if [ "$PARAM_DIFF" = "true" ] || [ "$ALL" = "true" ]; then
    echo "============ Running 'param-diff' benchmark ============="
    # Note: we advise, not to run this benchmark. We did not run it for our experimental evaluation
    # The reason is that the compared tools timeouts most of the time on these instances.
    # The results are henced not interesting at all.
    run_benchmark "$BASEDIR/jobs/tacas-24-bool-comb-cox-diff.yaml" "$BASEDIR/inputs/bench-double-bool-comb-cox.input" $JOBS
fi

secs=$((SECONDS - start_time))
formated_elapsed=$(printf "%dd:%dh:%dm:%ds\n" $((secs/86400)) $((secs%86400/3600)) $((secs%3600/60)) $((secs%60)))
eval "echo [!] All benchmarks done in $formated_elapsed"
if [ -n "$OUTPUT_DIR_NAME" ]; then
    echo "[!] All results stored in '$OUTPUT_DIR_NAME'"
fi
