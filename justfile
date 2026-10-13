#!/usr/bin/env -S just --justfile

# Compiler to use. Options: "g++", "clang", ...
CXX := env("CXX", "g++")

# Number of cores for parallel compilation.
JOBS := env("JOBS", "6")

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

# The legacy pipeline (`run_all.sh`, `jobs/*.yaml`), kept as it was;
# `scripts/bench.py` builds every library through `scripts/build_version.sh`.

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

alias r := release
release: (build-legacy "release")

alias rd := release-debuginfo
release-debuginfo: (build-legacy "release-debuginfo")

# Legacy: cleans mata's build tree (`make clean`); `clean` removes the per-revision builds.
clean-legacy:
    make clean

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
