#!/usr/bin/env -S just --justfile

alias b := build
alias h := help
alias f := fmt

# Syncs pycobench's Python environment. The benchmarked binaries are built on
# demand, one per (tool, revision), by `just compare` and `just suite`.
[working-directory("./harnesses/pycobench/")]
setup-python:
    uv sync

alias setup := build
build: setup-python

# The legacy pipeline (`run_all.sh`, `jobs/*.yaml`) runs the other libraries
# until `scripts/build_version.sh` builds them.

# Legacy: builds mata and installs it system-wide.
[working-directory("./subjects/mata/")]
build-mata BUILD_MODE="release":
    make {{ BUILD_MODE }}
    sudo make install

# Legacy: builds the .emp interpreters into `bin/`.
build-harnesses:
    sh ./harnesses/automata-program-parser/build.sh

# Legacy: everything `run_all.sh` needs.
build-legacy BUILD_MODE="release": (build-mata BUILD_MODE) build-harnesses setup-python

# Installs system-level build dependencies (compiler, cmake, uv) on Debian/Ubuntu or macOS.
# On any other system, install these manually: a C++20 compiler, cmake, make, and uv
# (https://docs.astral.sh/uv/getting-started/installation/).
bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    case "$(uname -s)" in
      Linux)
        if command -v apt-get >/dev/null; then
          sudo apt-get update
          sudo apt-get install -y build-essential cmake curl
        else
          echo "error: no apt-get found; install a C++20 compiler, cmake and make manually" >&2
          exit 1
        fi
        ;;
      Darwin)
        if ! command -v brew >/dev/null; then
          echo "error: Homebrew not found; install it from https://brew.sh first" >&2
          exit 1
        fi
        brew install cmake
        ;;
      *)
        echo "error: unsupported OS $(uname -s); install a C++20 compiler, cmake and make manually" >&2
        exit 1
        ;;
    esac
    if ! command -v uv >/dev/null; then
      curl -LsSf https://astral.sh/uv/install.sh | sh
    fi

# Compares the pinned mata against its parent on one quick instance, as an
# end-to-end check of build, measurement and reporting.
smoke-test:
    ./scripts/compare_versions.sh --test-run --timeout 10 --jobs 1 \
        --program emp-programs/automata_inclusion.emp --input inputs/bench-double-bool-comb-cox.input \
        --output-dir smoke-test HEAD^=smoke-parent HEAD=smoke-head

# Builds one tool at one revision (tag, branch or commit) into bin/<tool>-<rev>.
build-version REV TOOL="mata":
    ./scripts/build_version.sh {{ TOOL }} {{ REV }}

# Lists the tools that can be benchmarked and the subject repo each is built from.
tools:
    ./scripts/build_version.sh --list-tools

# Benchmarks several tools and/or revisions against each other on the same inputs,
# and writes the tables and plots comparing them next to the measurements.
# Specs are '<tool>:<rev>[=<label>],...' or a bare <rev> of mata; the first one is the baseline.
# Example: just compare emp-programs/words_of_lengths-10.emp inputs/bench-regexps_union.input 24a00cf0^=before 24a00cf0=after
compare PROGRAM INPUT +SPECS:
    ./scripts/compare_versions.sh --program {{ PROGRAM }} --input {{ INPUT }} {{ SPECS }}

# Runs every experiment of a suite on the given builds (and compare_versions options).
# Example: just suite suites/tacas-24.suite --repeat 3 v1.32.32 devel
suite SUITE +ARGS:
    ./scripts/run_suite.sh {{ SUITE }} {{ ARGS }}

# Regenerates the tables and plots of a finished run (a results/data/<dir>, or a single .csv).
# Example: just report results/data/words_of_lengths-10-2026-10-08-14-00-00 --metric words_of_lengths
report RUN *OPTS:
    ./scripts/report.sh {{ OPTS }} {{ RUN }}

help:
    just --list --justfile {{ justfile() }}

fmt:
    nix fmt
