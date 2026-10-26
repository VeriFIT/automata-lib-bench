// The simulation-based reduction nfa::reduce() of every input NFA.
//
// usage: reduce <aut.mata>...
//
// Reports the summed size of the results, and both numbers as 'result', which the report cross-checks between the
// builds: the forward simulation is unique, so builds that quotient and prune alike give the same sizes.
#include <cstddef>
#include <string>

#include <mata/nfa/nfa.hh>

#include "nft.hh" // measure_auto(), fail()
#include "utils/args.hh"
#include "utils/bench.hh"
#include "utils/mata_load.hh"

using mata::nfa::Nfa;

int main(int argc, char** argv) try {
	bench::Args args{argc, argv};
	args.done();

	size_t states{0};
	size_t transitions{0};
	for (const Nfa& aut : bench::load_nfas(args.files)) {
		const Nfa reduced{bench::measure_auto("reduce", [&] { return mata::nfa::reduce(aut); }, false)};
		states += reduced.num_of_states();
		transitions += reduced.delta.num_of_transitions();
	}
	bench::report("states", states);
	bench::report("transitions", transitions);
	bench::report("result", std::to_string(states) + "/" + std::to_string(transitions));
} catch (const std::exception& error) { return bench::fail(error); }
