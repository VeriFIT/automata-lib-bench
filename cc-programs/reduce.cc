// The simulation-based or residual reduction nfa::reduce() of every input NFA.
//
// usage: reduce [--algorithm=simulation|residual-after|residual-with] <aut.mata>...
//
// Reports the summed size of the results, and both numbers as 'result', which the report cross-checks between the
// builds of one variant. Exact language equivalence is timed separately as 'equivalence', and a mismatch is an error.
#include <cstddef>
#include <stdexcept>
#include <string>

#include <mata/nfa/nfa.hh>

#include "nft.hh" // measure_auto(), fail()
#include "utils/args.hh"
#include "utils/bench.hh"
#include "utils/mata_load.hh"

using mata::nfa::Nfa;

int main(int argc, char** argv) try {
	bench::Args args{argc, argv};
	const std::string algorithm{args.option("algorithm", "simulation")};
	args.done();
	if (algorithm != "simulation" && algorithm != "residual-after" && algorithm != "residual-with") {
		throw std::invalid_argument("unknown --algorithm=" + algorithm);
	}

	size_t states{0};
	size_t transitions{0};
	for (const Nfa& aut : bench::load_nfas(args.files)) {
		const Nfa reduced{bench::measure_auto(
			"reduce",
			[&] {
				if (algorithm == "simulation") { return mata::nfa::reduce(aut); }
				return mata::nfa::reduce(
					aut, nullptr,
					{{"algorithm", "residual"},
					 {"type", algorithm == "residual-after" ? "after" : "with"},
					 {"direction", "forward"}}
				);
			},
			false
		)};
		if (!bench::measure_auto("equivalence", [&] { return mata::nfa::are_equivalent(aut, reduced); }, false)) {
			throw std::runtime_error("reduced automaton is not language-equivalent to its input");
		}
		states += reduced.num_of_states();
		transitions += reduced.delta.num_of_transitions();
	}
	bench::report("states", states);
	bench::report("transitions", transitions);
	bench::report("result", std::to_string(states) + "/" + std::to_string(transitions));
} catch (const std::exception& error) { return bench::fail(error); }
