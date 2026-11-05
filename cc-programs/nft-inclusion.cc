// Inclusion or equivalence of NFTs: each NFT of a file against its simulation reduction, which accepts the same
// relation and so makes the check explore everything, or against the next NFT of the file.
//
// usage: nft-inclusion --operation=included|equivalent [--against=reduce|next]
//                      [--jump=repeat-symbol|append-dont-cares] <nfts.mata>
//   --operation  is_included(nft, other) or are_equivalent(nft, other), by the antichain algorithm
//   --against    reduce: other is nft::reduce() of the NFT, built outside the timing; next: the NFTs are paired up in
//                file order, which needs an even number of NFTs of equal levels [reduce]
//   --jump       the mata::nft::JumpMode both NFTs are read with [repeat-symbol]
#include <cstddef>
#include <stdexcept>
#include <string>
#include <vector>

#include <mata/nft/nft.hh>

#include "nft.hh"
#include "utils/args.hh"
#include "utils/bench.hh"

using mata::nft::JumpMode;
using mata::nft::Nft;

int main(int argc, char** argv) try {
	bench::Args args{argc, argv};
	const std::string operation{args.option("operation", "")};
	const std::string against{args.option("against", "reduce")};
	const std::string jump{args.option("jump", "repeat-symbol")};
	args.done();
	if (operation != "included" && operation != "equivalent") {
		throw std::invalid_argument("--operation=included|equivalent is required, not '" + operation + "'");
	}
	if (against != "reduce" && against != "next") {
		throw std::invalid_argument("--against=reduce|next, not '" + against + "'");
	}
	if (jump != "repeat-symbol" && jump != "append-dont-cares") {
		throw std::invalid_argument("--jump=repeat-symbol|append-dont-cares, not '" + jump + "'");
	}
	const JumpMode jump_mode{jump == "repeat-symbol" ? JumpMode::RepeatSymbol : JumpMode::AppendDontCares};

	const std::vector<Nft> nfts{bench::load_nfts(args, against == "next" ? 2 : 1)};
	if (against == "next" && nfts.size() % 2 != 0) {
		throw std::invalid_argument("--against=next needs an even number of NFTs");
	}
	std::vector<std::pair<const Nft*, Nft>> pairs{};
	for (std::size_t i{0}; i < nfts.size(); i += (against == "next" ? 2 : 1)) {
		pairs.emplace_back(&nfts[i], against == "next" ? nfts[i + 1] : mata::nft::reduce(nfts[i]));
	}
	// One time and one answer per file, whether every pair holds, as the report cross-checks one result per run.
	const bool holds{bench::measure_auto(operation, [&] {
		bool all{true};
		for (const auto& [nft, other] : pairs) {
			all = (operation == "included" ? mata::nft::is_included(*nft, other, nullptr, jump_mode)
										   : mata::nft::are_equivalent(*nft, other, jump_mode)) &&
				  all;
		}
		return all;
	})};
	bench::report("result", holds);
} catch (const std::exception& error) { return bench::fail(error); }
