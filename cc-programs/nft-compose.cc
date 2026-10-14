// Composition of the NFTs of a file in the order they are written, T1 ∘ T2 ∘ ... ∘ Tn: the output level (1) of each
// synchronized with the input level (0) of the next.
//
// usage: nft-compose [--order=left|right] [--between=none|trim|reduce] [--mode=auto|general] <nfts.mata>
//   --order    ((T1 ∘ T2) ∘ T3) ∘ ... or T1 ∘ (T2 ∘ (T3 ∘ ...)); the same for two NFTs
//   --between  done to every intermediate result, not to the final one: nothing, trim(), or the simulation-based
//              nft::reduce(); reducing a whole result is measured by nft-transform --operation=reduce
//   --mode     mata::nft::CompositionMode::Auto, which picks the fast algorithm when it applies, or ::General
#include <stdexcept>
#include <string>
#include <vector>

#include <mata/nft/nft.hh>

#include "nft.hh"
#include "utils/args.hh"
#include "utils/bench.hh"

using mata::nft::Nft;

int main(int argc, char** argv) try {
	bench::Args args{argc, argv};
	const std::string order{args.option("order", "left")};
	const std::string between{args.option("between", "none")};
	const std::string mode_name{args.option("mode", "auto")};
	args.done();
	if (order != "left" && order != "right") { throw std::invalid_argument("unknown --order=" + order); }
	if (between != "none" && between != "trim" && between != "reduce") {
		throw std::invalid_argument("unknown --between=" + between);
	}
	if (mode_name != "auto" && mode_name != "general") { throw std::invalid_argument("unknown --mode=" + mode_name); }
	const mata::nft::CompositionMode mode{
		mode_name == "auto" ? mata::nft::CompositionMode::Auto : mata::nft::CompositionMode::General
	};

	const std::vector<Nft> nfts{bench::load_nfts(args, 2)};
	const auto compose = [&](const Nft& lhs, const Nft& rhs) {
		return bench::measure_auto("composition", [&] {
			return mata::nft::compose(lhs, rhs, 1, 0, true, mata::nft::JumpMode::RepeatSymbol, mode);
		});
	};
	// In place, since compositions grow the NFTs to 10^5 states.
	const auto shrink = [&](Nft& intermediate) {
		if (between == "trim") {
			intermediate = bench::measure_auto("trim", [&] {
				Nft trimmed{intermediate};
				trimmed.trim();
				return trimmed;
			});
		} else if (between == "reduce") {
			intermediate = bench::measure_auto("reduce", [&] { return mata::nft::reduce(intermediate); });
		}
	};

	const size_t last{nfts.size() - 1};
	Nft result{};
	if (order == "left") {
		result = compose(nfts[0], nfts[1]);
		for (size_t i{2}; i <= last; ++i) {
			shrink(result);
			result = compose(result, nfts[i]);
		}
	} else {
		result = compose(nfts[last - 1], nfts[last]);
		for (size_t i{last - 1}; i-- > 0;) {
			shrink(result);
			result = compose(nfts[i], result);
		}
	}
	bench::report_result(result);
} catch (const std::exception& error) { return bench::fail(error); }
