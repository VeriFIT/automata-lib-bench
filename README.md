# automata-lib-bench: Pipeline for comparing finite automata libraries 

This repository contains data, tools, benchmarks and scripts for comparing various libraries for handling Nondeterministic Finite Automata (NFA) and other automata types.
This repository is meant to be used for running a set of benchmarks on a set of libraries.

The available tools are listed in `jobs/*.yaml` (each file corresponds to a~group of similar experiments); each tool is
installed in the `tools` directory, and takes as input automata in various formats (each library tends to use different
format).
The pipeline uses `pycobench` (a python benchmarknig package) to measure the time of each library and output a report in
`csv` (delimited by `;`) which lists individual measurements, results and some other metrics (e.g., time of
mintermization or optionally time of some preprocessing) for each library.
For each library, a set of source code files delegating necessary operations for particular experiments is present.

Note, that some tools/libraries are run either as a wrapper script (to simplify
the usage in benchmarking or fine-tuning the measurement) or specific binary
program that either takes an input automaton (and processes it) or might take
an input program that specifies sequence of automata operation (and executes
them in order; e.g., load automaton `A`; load automaton `B`; create
intersection of `A` and `B`).

## Setup

This repo uses git submodules; clone (or fix up an existing clone) with:

```shell
git clone --recurse-submodules <url>
# or, in an existing clone:
git submodule update --init --recursive
```

Everything is driven through [`just`](https://github.com/casey/just) recipes
(`just --list`), so the same commands work whether or not you use Nix:

* **With Nix**: `nix develop` (or let direnv do it via `.envrc`) gives you a
  shell with the C++ toolchain, `just` and `uv` already on `PATH`. The same
  operations are also exposed directly as `nix run .#<name>` (e.g.
  `nix run .#build`, `nix run .#smoke-test`) -- these just run the matching
  `just` recipe inside the flake's own devShell.
* **Without Nix** (Linux or macOS): run `just bootstrap` once to install the
  system dependencies (a C++20 compiler, cmake, and `uv`), then proceed as below.

Either way:

```shell
just build        # builds mata + the interpreters, and syncs pycobench's Python env
just smoke-test    # quick sanity check that the pipeline works end to end
./run_all.sh --help
```

## Comparing tools and versions

One run can measure several tools and several of their revisions against each
other. Every build is given as `<tool>:<rev>[,<rev>...]`, where the revisions
are any mix of tags, branches and commits present in the tool's subject
repository; a bare revision is taken as a revision of `mata`.

```shell
# three revisions of mata
just compare emp-programs/determinize.emp inputs/bench-regexps_union.input v1.32.32 devel 073777da

# the C++ library against the Python bindings, two revisions each
just compare emp-programs/determinize.emp inputs/bench-regexps_union.input \
    mata:v1.32.32,devel pymata:v1.32.32,devel

# or, with more control
./scripts/compare_versions.sh --program emp-programs/determinize.emp \
    --input inputs/bench-regexps_union.input --timeout 10 --output-dir my-run \
    mata:devel pymata:devel
```

`just tools` lists the known tools:

| tool | subject | what it runs |
| ---- | ------- | ------------ |
| `mata` | `subjects/mata` | the C++ interpreter linked against that revision's `libmata` |
| `pymata` | `subjects/mata` | `pyinterpret`'s `MataEngine` on that revision's Python bindings |

Each revision of a subject is checked out once into its own git worktree under
`build/versions/<subject>/<rev>/src`, and each tool builds from there into its
own directory, producing `bin/<tool>-<rev>`. Because `libmata` is a static
library and the Python bindings live in a per-revision virtualenv, every binary
carries its own revision and nothing is installed system-wide. The builds are
then registered as separate pycobench methods, so one run measures all of them
on identical inputs and the final table compares them column by column.

Binaries are reused across runs; pass `--force` to rebuild. A new tool is added
by listing it in `tool_subject()` and writing a matching `_build_<tool>`
function in `scripts/build_version.sh`.

`harnesses/pycobench` is itself an independent project (its own git
repository, `pyproject.toml`/`uv.lock`, and `flake.nix`) and can be built and
run on its own -- see `harnesses/pycobench/README.md`.

