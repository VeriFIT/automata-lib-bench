// Projection of an NFT onto one of its levels, and the reduction of the language this gives.
//
// usage: nft-project --keep=0|1 [--then=none|reduce|minimize] <nft.mata>
//   --keep  project_to(T, level): 0 gives the domain (the inputs), 1 the range (the outputs)
//   --then  done to the NFA of that language: nothing, the simulation-based nfa::reduce(), or nfa::minimize()
#include <stdexcept>
#include <string>
#include <vector>

#include <mata/nfa/nfa.hh>
#include <mata/nft/nft.hh>

#include "nft.hh"
#include "utils/args.hh"
#include "utils/bench.hh"

using mata::nfa::Nfa;

int main(int argc, char** argv) try {
	bench::Args args{argc, argv};
	const std::string keep{args.option("keep", "")};
	const std::string then{args.option("then", "none")};
	args.done();
	if (keep != "0" && keep != "1") { throw std::invalid_argument("--keep=0|1 is required, not '" + keep + "'"); }
	if (then != "none" && then != "reduce" && then != "minimize") {
		throw std::invalid_argument("unknown --then=" + then);
	}

	const mata::nft::Nft nft{bench::load_nfts(args, 1, 1)[0]};
	Nfa language{bench::measure_auto("projection", [&] {
		return mata::nft::project_to(nft, static_cast<mata::nft::Level>(std::stoul(keep))).to_nfa_move();
	})};
	if (then == "reduce") {
		language = bench::measure_auto("reduce", [&] { return mata::nfa::reduce(language); });
	} else if (then == "minimize") {
		language = bench::measure_auto("minimize", [&] { return mata::nfa::minimize(language); });
	}
	bench::report_result(language);
} catch (const std::exception& error) { return bench::fail(error); }
