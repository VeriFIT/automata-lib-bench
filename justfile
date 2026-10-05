#!/usr/bin/env -S just --justfile

# Compiler to use. Options: "g++", "clang", ...
CXX := env("CXX", "g++")

# Number of cores for parallel compilation.
JOBS := env("JOBS", "6")

alias b := build
alias h := help
alias f := fmt

[working-directory("./subjects/mata/")]
build-mata BUILD_MODE="release":
    make {{ BUILD_MODE }}
    sudo make install

build-harnesses:
    sh ./harnesses/automata-program-parser/build.sh

[working-directory("./harnesses/pycobench/")]
setup-python:
    uv sync

# Builds the mata library + interpreters, and syncs pycobench's Python environment.
# This is everything needed before running the benchmarks (see `run_all.sh`/`just smoke-test`).
build BUILD_MODE="release": (build-mata BUILD_MODE) build-harnesses setup-python

alias setup := build

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

# Runs a quick, low-timeout pass of the regexps_union determinize-minimize benchmark
# to sanity-check that the pipeline (mata binary + pycobench + Python env) works end to end.
smoke-test:
    ./run_all.sh --test-run -y --regexps_union-determinize-minimize

alias c := clean
clean:
    make clean

alias r := release
release: (build "release")

alias rd := release-debuginfo
release-debuginfo: (build "release-debuginfo")

help:
    just --list --justfile {{ justfile() }}

fmt:
    nix fmt
