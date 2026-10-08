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
other. Every build is given as `<tool>:<rev>[=<label>][,<rev>...]`, where the
revisions are any mix of tags, branches and commits present in the tool's
subject repository; a bare revision is taken as a revision of `mata`, and the
optional `=<label>` is what the build is called in the result table, the tables
and the plots. The first build listed is the baseline the others are compared
against.

```shell
# three revisions of mata
just compare emp-programs/determinize.emp inputs/bench-regexps_union.input v1.32.32 devel 073777da

# one commit against its parent, under readable names
just compare emp-programs/words_of_lengths-10.emp inputs/bench-regexps_union.input 24a00cf0^=before 24a00cf0=after

# the C++ library against the Python bindings, two revisions each
just compare emp-programs/determinize.emp inputs/bench-regexps_union.input \
    mata:v1.32.32,devel pymata:v1.32.32,devel

# or, with more control: several benchmark families in one run
./scripts/compare_versions.sh --program emp-programs/determinize.emp \
    --input inputs/bench-regexps_union.input \
    --input inputs/bench-single-z3-noodler.input \
    --timeout 10 --jobs 8 --output-dir my-run \
    mata:devel pymata:devel
```

Each run gets its own directory `results/data/<run>/`, holding one `.csv` per
input file and, next to each, a `<csv>-report/` directory with the tables and
plots (see *Reporting* below).

`just tools` lists the known tools:

| tool | subject | what it runs |
| ---- | ------- | ------------ |
| `mata` | `subjects/mata` | the C++ interpreter linked against that revision's `libmata` |
| `pymata` | `subjects/mata` | `pyinterpret`'s `MataEngine` on that revision's Python bindings |

Each revision of a subject is checked out once into its own git worktree under
`build/versions/<subject>/<label>/src`, and each tool builds from there into its
own directory, producing `bin/<tool>-<label>`. Because `libmata` is a static
library and the Python bindings live in a per-revision virtualenv, every binary
carries its own revision and nothing is installed system-wide. The builds are
then registered as separate pycobench methods, so one run measures all of them
on identical inputs.

Binaries are reused across runs; pass `--force` to rebuild. A new tool is added
by listing it in `tool_subject()` and writing a matching `_build_<tool>`
function in `scripts/build_version.sh`.

`harnesses/pycobench` is itself an independent project (its own git
repository, `pyproject.toml`/`uv.lock`, and `flake.nix`) and can be built and
run on its own -- see `harnesses/pycobench/README.md`.

## What is measured: `.emp` programs

An experiment is a `.emp` program from `emp-programs/` run on every automaton
of an `inputs/*.input` file. The program is a sequence of statements, one per
line, with `#` starting a comment:

```
<var> = <op> <arg>...    # binds the result of the operation
<op> <arg>...            # discards it
load_automaton <var>     # binds the next automaton of the input line
```

An `<arg>` is either an automaton bound earlier or, for the operations that
take them, a literal the operation interprets itself. `words_of_lengths aut1 10`
for instance asks `mata::applications::strings::get_words_of_lengths()` for an
accepted word of length 10 -- the automaton is read as a one-tape transducer, so
it takes exactly one length, an n-tape NFT would take n of them.

Every operation prints the time it took under its own name
(`words_of_lengths: 0.00026`), so the result table has a column isolating the
measured operation from parsing and construction, next to the `runtime` column
holding the wall-clock time of the whole process. An operation that computes an
answer also prints `result: <answer>`, which the report cross-checks between the
compared builds.

A new operation is added by naming it in `STR_OP` in
`harnesses/automata-program-parser/src/cpp/interpreter/parser.h`, dispatching it
in `interpreter/interpreter.h`, and implementing it per tool (e.g. in
`interpreter_mata.cc`).

## Reporting

Every run ends with the tables and plots comparing the measured builds; they are
regenerated from a finished run with

```shell
just report results/data/<run>
just report results/data/<run> --metric words_of_lengths --timeout 10
```

For each metric (`runtime` by default, `--metric all` for every metric the
builds share) the report holds

* `summary-<metric>.{md,tex,csv}` -- per build: finished runs, timeouts,
  memouts, errors, and the mean/median/max/total of the metric, plus its PAR-2
  score when a `--timeout` is given,
* `pairwise-<metric>.{md,tex,csv}` -- per build against the baseline: instances
  only one of them finished, how often it is faster, and the
  median/geomean/min/max speed-up where both finished,
* `scatter-<metric>-<baseline>-vs-<build>.{pdf,png}` -- log-log scatter plot,
  with the runs that produced no measurement drawn on the border lines,
* `cactus-<metric>.{pdf,png}` -- instances finished within a time limit,
* `disagreements.csv` -- instances on which the builds reported different
  answers, when there are any.

The tool behind this is `harnesses/pycobench/src/pyco_plot.py`; it reads the
engines and metrics off the result table's header and knows nothing about
automata, so it reports any pycobench run.

