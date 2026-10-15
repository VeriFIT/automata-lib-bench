// One operation on every NFT of a file. None changes whether the relation is empty, which every NFT reports.
//
// usage: nft-transform --operation=invert|trim|reduce|determinize <nfts.mata>
//   invert       invert_levels(): the inverse relation
//   trim         trim(): only the states on a path from an initial to a final state
//   reduce       the simulation-based nft::reduce()
//   determinize  nft::determinize()
#include <set>
#include <stdexcept>
#include <string>

#include <mata/nft/nft.hh>

#include "nft.hh"
#include "utils/args.hh"
#include "utils/bench.hh"

using mata::nft::Nft;

int main(int argc, char** argv) try {
	bench::Args args{argc, argv};
	const std::string operation{args.option("operation", "")};
	args.done();
	if (!std::set<std::string>{"invert", "trim", "reduce", "determinize"}.contains(operation)) {
		throw std::invalid_argument("--operation=invert|trim|reduce|determinize is required, not '" + operation + "'");
	}

	for (const Nft& nft : bench::load_nfts(args, 1)) {
		const Nft result{bench::measure_auto(operation, [&] {
			if (operation == "invert") { return mata::nft::invert_levels(nft); }
			if (operation == "trim") {
				Nft trimmed{nft};
				trimmed.trim();
				return trimmed;
			}
			if (operation == "reduce") { return mata::nft::reduce(nft); }
			return mata::nft::determinize(nft);
		})};
		bench::report_result(result);
	}
} catch (const std::exception& error) { return bench::fail(error); }
