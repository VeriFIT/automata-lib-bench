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

