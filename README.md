# automata-lib-bench: Pipeline for comparing finite automata libraries 

This repository contains data, tools, benchmarks and scripts for comparing various libraries for handling Nondeterministic Finite Automata (NFA) and other automata types.
This repository is meant to be used for running a set of benchmarks on a set of libraries.

The available tools are listed by `just tools`; each is built per revision from
its subject repository under `subjects/`, and takes as input automata in various
formats (each library tends to use different format).
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
just build         # syncs pycobench's Python env (binaries are built on demand)
just smoke-test    # the pinned mata against its parent, one instance per program kind
just suite suites/tacas-24.toml v1.32.32 devel   # the paper's experiments on two revisions
```

The legacy pipeline (`run_all.sh`, `jobs/*.yaml`, `just build-legacy`) is kept
as it was; everything below goes through `scripts/bench.py`.

## Experiments

An *experiment* runs **programs** on **inputs** for **builds**:

* a program is an `.emp` program, interpreted by every build, or a C++ program
  `cc-programs/<name>.cc`, compiled against every build (see *What is
  measured* below); several programs, or several *variants* of one (the same
  program with other arguments), are compared like builds are;
* an input is a list of instances, one per line, each column (a `.mata` file)
  becoming one argument of the program: an `inputs/*.input` file, or a list
  generated from a glob (see *Inputs*);
* a build is a tool at a revision, `[<tool>:]<rev>[=<label>][,<rev>...]`; a bare
  revision is one of `mata`. `pr/<N>` stands for GitHub pull request `N` and
  expands into `<label>-base` (the commit it branched off) and `<label>-head`
  (its tip), both fetched from the subject's remote.

Every (build, program, variant) is one pycobench *method*, named
`<tool>-<label>[.<program>][.<variant>]`, so all of them are measured on exactly
the same instances into one table. The first method is the baseline of the
report.

An experiment is given on the command line, or in a suite:

```shell
# one program, three revisions of mata
just compare emp-programs/determinize.emp inputs/bench-regexps_union.input v1.32.32 devel 073777da
# a pull request against the commit it branched off, three repetitions
just compare cc-programs/trim.cc inputs/bench-double-bool-comb-cox.input --repeat 3 pr/879
# the C++ library against the Python bindings, two revisions each
just compare emp-programs/determinize.emp inputs/bench-regexps_union.input mata:v1.32.32,devel pymata:v1.32.32,devel
# two variants of one program on one revision, on every .mata file of a directory
just compare cc-programs/minimize.cc 'benchmarks/nfa-bench/benchmarks/regexps/regexps_union/*.mata' \
    --variant brzozowski=--algorithm=brzozowski --variant hopcroft=--algorithm=hopcroft devel

# suites: all their experiments, some of them, or just what they would run
just suite suites/tacas-24.toml @tools
just suite suites/quick.toml --only trim,minimize --repeat 3 pr/879
just suite suites/quick.toml --list HEAD^ HEAD
```

`scripts/bench.py --help` lists the options: `--timeout`, `--jobs`, `--repeat`,
`--memout`, `--[no-]pin`, `--build-mode`, `--force` (rebuild), `--test-run`
(first instance only), `--no-report`, `--output-dir`.

### Suites

A suite (`suites/*.toml`) names experiments, the defaults they run with, and
sets of builds, and includes other suites:

```toml
include = [
  "trim.toml",                                             # all its experiments
  { path = "tacas-24.toml", only = ["armc-incl", "b-smt"] },
]

[defaults]                  # for this suite's experiments and the included ones
timeout = 30                # seconds per instance
jobs = 4                    # instances measured in parallel
repeat = 1                  # measurements per instance; the minimum is kept
memout = 8                  # GB per instance (default: none)
pin = true                  # one physical core per job
build_mode = "Release"      # or RelWithDebInfo, Debug
builds = ["v1.32.32=old", "devel=new"]

[builds]                    # named sets, used as "@tools" here or on the command line
tools = ["mata:devel", "pymata:devel", "vata:for-inclusion-testing"]

[experiment.inclusion]
description = "shown by --list"
program = "emp-programs/automata_inclusion.emp"
inputs = "inputs/bench-double-automata-inclusion.input"
builds = ["@tools"]         # this experiment's own
timeout = 120               # any default, for this experiment only

[experiment.inclusion-cox]
extends = "inclusion"       # everything of 'inclusion' but what it sets
inputs = "inputs/bench-double-bool-comb-cox.input"

[experiment.minimize]
program = "cc-programs/minimize.cc"
variants = { brzozowski = "--algorithm=brzozowski", hopcroft = "--algorithm=hopcroft" }
inputs = "inputs/bench-regexps_union.input"

[experiment.det-vs-det-min]
programs = ["emp-programs/determinize.emp", "emp-programs/determinize-minimize.emp"]
inputs = "inputs/bench-regexps_union.input"
```

A setting is taken from, last one winning: the built-in default, the
`[defaults]` of the suite defining the experiment, those of the suites including
that one (outermost last), the experiment's own keys, and the command line.
Builds on the command line replace the builds of every experiment. So a
reusable experiment leaves its builds to `[defaults]` (or to the command line),
and a suite composing it decides which builds it runs on. Unknown keys are
errors, and `--list` prints every experiment as resolved: its inputs, settings
and methods.

| suite | what for |
| ----- | -------- |
| `tacas-24.toml` | the experiments of the TACAS'24 paper; `@tools` compares the libraries |
| `quick.toml` | a cross-section of the others, for checking a change |
| `trim.toml` | `trim()` against copy + in-place trim |
| `minimize.toml` | variants and several programs on one revision |
| `smoke.toml` | `just smoke-test` and CI |

### Inputs

`inputs` is one entry or a list of them, each becoming one table of the run:

```toml
inputs = [
  "inputs/bench-regexps_union.input",                     # a list as it is
  "benchmarks/nfa-bench/benchmarks/regexps/**/*.mata",    # one instance per file
  # one instance per '<stem>-lhs.mata', the columns filled in with its stem
  { glob = "benchmarks/nfa-bench/benchmarks/automata_inclusion/*-lhs.mata",
    columns = ["{stem}-lhs.mata", "{stem}-rhs.mata"], name = "inclusion" },
  # one instance per pair of files
  { glob = "benchmarks/nfa-bench/benchmarks/email_filter/*.mata", combine = 2 },
]
```

The stem is the match without the literal end of the pattern. A column may
itself be a glob, which pycobench expands when it runs the instance, so one
instance can take a variable number of automata (`"{stem}-*.mata"`). Matches
missing a column are skipped and counted. Generated lists are written into the
run (`inputs/<name>.input`), so the run records exactly what it measured. When
an input's first column is an `.emp` program, every instance brings its own and
the experiment names no program.

### Runs

An ad hoc experiment runs into `results/data/<name>-<timestamp>/`, a suite into
`results/data/<suite>-<timestamp>/<experiment>/`. Each holds one `.csv` per
input and, next to each, a `<csv>-report/` directory with the tables and plots
(see *Reporting*). It also keeps what the run was made from: the generated
pycobench job config, copies of the programs, the generated input lists, and
`manifest.json`, which ties every method to the tool, revision and commit it was
built from and records the settings, the hashes of the programs, inputs and
suites, the revisions of this repository and its harnesses, and the machine
(CPU, governors, compiler).

## Tools and builds

A tool is one way of running programs, defined by its own file
`scripts/tools/<tool>.sh` (format in the header of `scripts/build_version.sh`):
the subject it is built from, the program kinds it runs, and a `build()`
function producing `bin/<tool>-<label>`, run as
`<binary> <program.emp> [options] <automaton>...`. Whatever the language of the
library, that wrapper is its whole interface to the rest of the pipeline, so a
Java or a .NET library is added exactly like a C++ one. `just tools` lists them:

| tool | subject | runs | what it is |
| ---- | ------- | ---- | ---------- |
| `mata` | `subjects/mata` | emp, cc | the C++ interpreter linked against that revision's `libmata` |
| `pymata` | `subjects/mata` | emp | `pyinterpret`'s `MataEngine` on that revision's Python bindings |
| `vata` | `subjects/libvata` | emp | the C++ interpreter on libvata (no determinization, minimization, concatenation) |
| `awali` | `tarball:` awali releases | emp | the C++ interpreter on awali's dynamic library |
| `brics` | `subjects/mata-comparison-brics` | emp | the Java interpreter on brics (no determinization, minimization) |
| `automatalib` | `subjects/mata-comparison-brics` | emp | the Java interpreter on AutomataLib (no minimization, concatenation) |
| `automata-net` | `subjects/automata-net` | emp | the .NET interpreter of Automata.NET (no determinization, minimization, concatenation) |
| `fado` | `pypi:fado` | emp | `pyinterpret`'s `FadoEngine` on that FAdo release |
| `automata-py` | `pypi:automata-lib` | emp | `pyinterpret`'s `AutomataLibEngine` on that automata-lib release |

An operation a library lacks makes the instance fail (ERR) instead of being
skipped. The Java and .NET interpreters read explicit alphabets only, so their
wrappers mintermize bitvector inputs first (`scripts/massage_arguments.py`,
cached under `build/minterm/`). The dev shell provides their toolchains (JDK,
Maven, .NET SDK, Boost for libvata); the wrappers embed the store paths, so keep
the shell rooted (e.g. with nix-direnv) to keep them from being collected.

A subject is a git repository (`subjects/<name>`, revisions are tags, branches
and commits), `pypi:<package>` (revisions are versions), or `tarball:<url>`
(revisions are versions put into the URL). Each revision of a git subject is
checked out once into its own worktree under
`build/versions/<subject>/<label>/src`, and every tool builds from there into
its own directory, so revisions and tools never clobber each other and nothing
is installed system-wide. The other libraries read their `.mata` inputs with
a pinned mata (`parsing_mata_rev` in `scripts/build_version.sh`), which is not
what they are compared on.

A build is reused while its label still resolves to the commit it was built
from and the harness (interpreters and timing code), the tool file and the build
mode are the same; a label that moved (`devel`, `HEAD`, a force-pushed pull
request) is rebuilt. `just clean [days]` removes the builds not rebuilt for
`days` days (default 30) together with their worktrees and binaries, and failed
builds regardless of age; `just clean 30 --dry-run` lists them.

`harnesses/pycobench` is itself an independent project (its own git
repository, `pyproject.toml`/`uv.lock`, and `flake.nix`) and can be built and
run on its own -- see `harnesses/pycobench/README.md`.

### Comparing an approach or algorithm

* Implement the new approach on a branch or pull request of mata and compare
  `pr/<N>` (or `<old>=before <new>=after`): base and head are built alike and
  measured on the same instances in the same run, interleaved.
* Operations the interpreter knows: an `.emp` program. Anything else, or a new
  API: a C++ program, built against both revisions -- it may use API only the
  new revision has behind its own variant, or be a different file per
  approach (`programs = [...]`).
* Two approaches within one revision (an algorithm parameter, a flag): variants.
* Time only the operation (`bench::measure`), not the parsing; check that the
  approaches agree (`result:` is cross-checked by the report; a C++ program
  can also fail when they disagree, like `trim.cc`).
* Operations under a millisecond: `bench::measure_repeated`, not `--repeat`.
* Use `--repeat 3` or more for the final numbers, keep the default pinning, and
  start with `--test-run` / `--list` to see that the right thing is measured.
* Put the experiment into a suite once it is worth rerunning: `quick.toml`-like
  compositions are then one command for every future change.

### Measurement noise

By default every pycobench worker is pinned to a physical core of its own,
never the core of CPU 0, so `--jobs` may not exceed the cores left; `--no-pin`
lets the workers float. `--repeat <n>` measures every instance `n` times and
keeps each cell's minimum (a cell that failed in any repeat stays failed); the
per-repeat tables are kept in `<csv>-repeats/`. `--memout <GB>` caps the
memory of every run, which is what fills the *memouts* column of the report.

## What is measured: programs

An experiment's program is run on every instance (line) of its inputs, each
column (a `.mata` automaton) becoming one argument, after the variant's
arguments. A program is either an `.emp` program, run by every tool's
interpreter, or a C++ program, built against the libmata of every compared
revision. Both print what they measure as `<name>: <value>` lines, each
becoming a column of the result table next to `runtime`, the wall-clock time of
the whole process. An operation that computes an answer also prints
`result: <answer>`, which the report cross-checks between the compared builds.

### `.emp` programs

For operations the interpreters already know, and for comparing libraries: a
program in `emp-programs/` is a sequence of statements, one per line, with `#`
starting a comment:

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

Every operation prints its time under its own name (`words_of_lengths: 0.00026`).
A new operation is added by naming it in `STR_OP` in
`harnesses/automata-program-parser/src/cpp/interpreter/parser.h`, dispatching it
in `interpreter/interpreter.h`, and implementing it per tool (e.g. in
`interpreter_mata.cc`).

### C++ programs

For anything else -- a new algorithm, a variant chosen by a parameter, an API
the interpreter does not expose, an operation of microseconds: a file
`cc-programs/<name>.cc` is a complete program, built per revision on demand
(by tools running `cc`: `mata`). It loads its arguments and measures with the
harness' `utils/mata_load.hh` and `utils/bench.hh`, which the interpreter uses
as well:

```cpp
#include <mata/nfa/nfa.hh>

#include "utils/bench.hh"
#include "utils/mata_load.hh"

int main(int argc, char **argv) {
  // Times 'mataparsing' (and 'mataminterm' for bitvector alphabets).
  const std::vector<mata::nfa::Nfa> auts{bench::load_nfas(argc, argv)};
  const mata::nfa::Nfa det{bench::measure("determinize", [&] {
    return mata::nfa::determinize(auts[0]);
  })};
  bench::report("states", det.num_of_states());
}
```

- `bench::measure(name, f)` runs `f` once, prints its time and returns its
  result. For operations of a millisecond or more; repeating them is
  `--repeat`'s job, in fresh processes.
- `bench::measure_repeated(name, f)` prints the median over batches of at least
  10 ms of the time per call, for operations too short to time once. `f` must
  not modify its inputs: copy them inside `f`.
- `bench::report(name, value)` prints anything that is not a time.
- `bench::Args` (`utils/args.hh`) reads the variant's leading
  `--<key>=<value>` options before the automata, and fails on options the
  program does not ask for, so a misspelt variant does not silently run the
  default.

Times are seconds of a monotonic wall clock, as in pyinterpret. A name may be
printed several times per run, and the column holds the sum. Names are
`[A-Za-z0-9_.-]+`, as they become columns and file names of the report.
`cc-programs/trim.cc` (out-of-place `trim()` against copy + in-place `trim()`,
on the inputs and on their product) and `cc-programs/minimize.cc` (an algorithm
per variant) are complete examples.

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

