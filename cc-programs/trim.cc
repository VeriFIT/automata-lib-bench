// Out-of-place mata::nfa::trim() against copying the NFA and trimming the copy
// in place, on every input automaton and on the untrimmed product of the first
// two, where most states are useless.
//
// usage: trim <aut.mata>...
#include <iostream>
#include <vector>

#include <mata/nfa/nfa.hh>

#include "utils/bench.hh"
#include "utils/mata_load.hh"

using mata::nfa::Nfa;

int main(int argc, char** argv) {
	std::vector<Nfa> work{bench::load_nfas(argc, argv)};
	if (work.size() >= 2) {
		Nfa product{mata::nfa::intersection(work[0], work[1])};
		product.alphabet = work[0].alphabet;
		work.push_back(std::move(product));
	}

	for (const Nfa& aut : work) {
		const Nfa trimmed{bench::measure_repeated("trim", [&] { return mata::nfa::trim(aut); })};
		const Nfa copy_trimmed{bench::measure_repeated("copy_trim", [&] {
			Nfa copy{aut};
			copy.trim();
			return copy;
		})};
		if (trimmed.num_of_states() != copy_trimmed.num_of_states() ||
			trimmed.delta.num_of_transitions() != copy_trimmed.delta.num_of_transitions()) {
			std::cerr << "error: trim() and copy + trim() disagree\n";
			return 1;
		}
		bench::report("useful_states", trimmed.num_of_states());
	}
}
