#!/usr/bin/env -S just --justfile

# Compiler to use. Options: "g++", "clang", ...
CXX := env("CXX", "g++")

# Number of cores for parallel compilation.
JOBS := env("JOBS", "6")

alias t := test
[default]
test *ARGS:
    just build "debug"
    just test-run "debug" {{ ARGS }}

    just build "release"
    just test-run "release" {{ ARGS }}

test-run BUILD_MODE="debug" *ARGS:
    ./build/{{ BUILD_MODE }}/{{ CXX }}/tests/tests {{ ARGS }}

alias b := build

[working-directory("./subjects/mata/")]
build-mata BUILD_MODE="release":
    make {{ BUILD_MODE }}
    sudo make install

build-harnesses:
    sh ./harnesses/automata-program-parser/build.sh

build BUILD_MODE="release": (build-mata BUILD_MODE) build-harnesses
    pwd

wip BUILD_DIR BUILD_MODE="debug" *ARGS:
    make {{ BUILD_MODE }} BUILD_DIR="build/{{ BUILD_DIR }}/{{ CXX }}"
    ./build/{{ BUILD_DIR }}/{{ CXX }}/tests/tests {{ ARGS }}

alias tp := test-python
[working-directory("bindings/python/")]
test-python:
    # source .venv/bin/activate.fish &&
    make -j {{ JOBS }} BUILD_DIR=build/bindings/python
    make -j {{ JOBS }} test
    ../../run_papermill_examples.sh
    # ; deactivate

alias vc := valgrind-callgrind
valgrind-callgrind +ARGS:
    valgrind --tool=callgrind {{ ARGS }}

alias c := clean
clean:
    make clean

alias r := release
release: (build "release")

alias rd := release-debuginfo
release-debuginfo: (build "release-debuginfo")

alias d := docs
docs:
    make docs BUILD_DIR="build/debug/{{ CXX }}"
    make -C docs/ html

# TODO: Implement.
ci:
    @! echo "Unimplemented"

alias h := help
help:
    just --list --justfile {{ justfile() }}

alias f := fmt
fmt:
    nix fmt
