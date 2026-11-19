// Concatenate the two NFTs of a file, with an epsilon connector between every final state of the left NFT and every
// initial state of the right NFT. Reports the operand cardinalities to identify workloads with multiple connectors.
//
// usage: nft-concatenate --use-epsilon=yes|no <pair.mata>
//   use-epsilon=yes   keep the connector transitions
//   use-epsilon=no    remove epsilon transitions after concatenating
#include <stdexcept>
#include <string>
#include <vector>

#include <mata/nft/algorithms.hh>
#include <mata/nft/nft.hh>

#include "nft.hh"
#include "utils/args.hh"
#include "utils/bench.hh"

using mata::nft::Nft;

int main(int argc, char** argv) try {
	bench::Args args{argc, argv};
	const std::string use_epsilon{args.option("use-epsilon", "yes")};
	args.done();
	if (use_epsilon != "yes" && use_epsilon != "no") {
		throw std::invalid_argument{"--use-epsilon=yes|no is required, not '" + use_epsilon + "'"};
	}

	const std::vector<Nft> nfts{bench::load_nfts(args, 2, 2)};
	bench::report("lhs_finals", nfts[0].final.size());
	bench::report("rhs_initials", nfts[1].initial.size());
	bench::report("num_levels", nfts[0].levels.num_of_levels);
	const Nft result{bench::measure_auto("concatenation", [&] {
		return mata::nft::algorithms::concatenate_eps(nfts[0], nfts[1], mata::nft::EPSILON, use_epsilon == "yes");
	})};
	bench::report_result(result);
} catch (const std::exception& error) { return bench::fail(error); }
