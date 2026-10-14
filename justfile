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

# Installs what the pipeline needs without Nix, on Debian/Ubuntu or macOS: GCC >= 14
# (recent mata), cmake, git, Python >= 3.13 with headers (recent mata bindings), a
# `time` command and uv, and on Debian/Ubuntu also the toolchains of the other
# libraries (Boost for vata, a JDK and maven for brics and automatalib, the .NET 8
# SDK for automata-net where apt has it). Debian 13 has new enough packages;
# Ubuntu 24.04's GCC, Python and just are too old. Elsewhere, install these
# manually (uv: https://docs.astral.sh/uv/getting-started/installation/).
bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    case "$(uname -s)" in
      Linux)
        if ! command -v apt-get >/dev/null; then
          echo "error: no apt-get found; install GCC >= 14, cmake, git, python3 (>= 3.13) with headers and 'time' manually" >&2
          exit 1
        fi
        sudo apt-get update
        sudo apt-get install -y build-essential cmake curl git python3 python3-dev time \
          libboost-dev libboost-filesystem-dev libboost-system-dev libboost-test-dev \
          openjdk-21-jdk-headless maven
        if [ -n "$(apt-cache policy dotnet-sdk-8.0 | grep 'Candidate: [0-9]')" ]; then
          sudo apt-get install -y dotnet-sdk-8.0
        else
          echo "note: apt has no dotnet-sdk-8.0; automata-net needs it: https://learn.microsoft.com/dotnet/core/install/linux" >&2
        fi
        ;;
      Darwin)
        if ! command -v brew >/dev/null; then
          echo "error: Homebrew not found; install it from https://brew.sh first" >&2
          exit 1
        fi
        brew install cmake python
        echo "note: vata, brics, automatalib and automata-net need Boost < 1.89, a JDK with maven and the .NET 8 SDK; install them yourself" >&2
        ;;
      *)
        echo "error: unsupported OS $(uname -s); install GCC >= 14, cmake, git, python3 (>= 3.13) with headers and 'time' manually" >&2
        exit 1
        ;;
    esac
    if ! command -v uv >/dev/null; then
      curl -LsSf https://astral.sh/uv/install.sh | sh
    fi

# Compares the pinned mata against its parent on one quick instance per
# program kind (suites/smoke.toml), as an end-to-end check of build,
# measurement and reporting.
smoke-test:
    ./scripts/bench.py suites/smoke.toml --test-run --output-dir smoke-test

# Builds one tool at one revision (tag, branch, commit or version) into bin/<tool>-<rev>.
build-version REV TOOL="mata":
    ./scripts/build_version.sh {{ TOOL }} {{ REV }}

# Lists the tools that can be benchmarked, the subject each is built from and the programs it runs.
tools:
    ./scripts/build_version.sh --list-tools

# Runs PROGRAM (an .emp program or cc-programs/<name>.cc) on INPUT (an .input
# file or a glob of .mata files) for every build, and writes the tables and
# plots comparing them. Builds are '[<tool>:]<rev>[=<label>][,...]' or
# 'pr/<N>'; the first is the baseline. Options of scripts/bench.py go among
# them (--repeat 3, --variant <name>=<args>, --list, ...).
# Example: just compare emp-programs/words_of_lengths-10.emp inputs/bench-regexps_union.input 24a00cf0^=before 24a00cf0=after
# Example: just compare cc-programs/trim.cc inputs/bench-double-bool-comb-cox.input pr/879
compare PROGRAM INPUT +ARGS:
    ./scripts/bench.py --program {{ PROGRAM }} --input '{{ INPUT }}' {{ ARGS }}

# Runs the experiments of a suite (suites/*.toml). Builds and options given
# here override the suite's; --list shows what would run.
# Example: just suite suites/tacas-24.toml --repeat 3 v1.32.32 devel
# Example: just suite suites/quick.toml --only trim,minimize pr/879
suite SUITE *ARGS:
    ./scripts/bench.py {{ SUITE }} {{ ARGS }}

# Regenerates the tables and plots of a finished run (a results/data/<dir>, or a single .csv).
# Example: just report results/data/words_of_lengths-10-2026-10-08-14-00-00 --metric words_of_lengths
report RUN *OPTS:
    ./scripts/report.sh {{ OPTS }} {{ RUN }}

# Removes the builds (worktree, build trees, binaries) not rebuilt for DAYS days.
alias c := clean
clean DAYS="30" *OPTS:
    ./scripts/clean_versions.sh --older-than {{ DAYS }} {{ OPTS }}

help:
    just --list --justfile {{ justfile() }}

fmt:
    nix fmt
