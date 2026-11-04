// Composition of the NFTs of a file in the order they are written, T1 ∘ T2 ∘ ... ∘ Tn: the output level of each
// synchronized with the input level of the next.
//
// usage: nft-compose [--order=left|right] [--between=none|trim|reduce] [--mode=auto|general]
//                    [--jump=repeat-symbol|no-jump] [--sync=<lhs level>,<rhs level>] [--project-out=yes|no]
//                    [--trim=no|yes] <nfts.mata>
//   --order        ((T1 ∘ T2) ∘ T3) ∘ ... or T1 ∘ (T2 ∘ (T3 ∘ ...)); the same for two NFTs
//   --between      done to every intermediate result, not to the final one: nothing, trim(), or the simulation-based
//                  nft::reduce(); reducing a whole result is measured by nft-transform --operation=reduce
//   --mode         mata::nft::CompositionMode::Auto, which picks the fast algorithm when it applies, or ::General
//   --jump         the mata::nft::JumpMode; Auto takes the fast algorithm only with no-jump, as z3-noodler does
//   --sync         the level of the left and of the right NFT synchronized [1,0]
//   --project-out  whether the synchronized level is removed from the result [yes]
//   --trim         every composition trimmed, timed as part of it, as z3-noodler's compose(...).trim(): by
//                  CompositionNormalization::Trim where mata has it, by Nft::trim() after the composition before
#include <charconv>
#include <stdexcept>
#include <string>
#include <vector>

#include <mata/nft/nft.hh>

#include "nft.hh"
#include "utils/args.hh"
#include "utils/bench.hh"

using mata::nft::Nft;

/// Whether mata has CompositionNormalization::Trim, whose composition returns its result trimmed.
template <typename Normalization>
concept HasTrimNormalization = requires { Normalization::Trim; };

/// compose() trimmed, by Normalization::Trim when mata has it.
template <typename Normalization = mata::nft::CompositionNormalization>
Nft compose_trimmed(
	const Nft& lhs,
	const Nft& rhs,
	const mata::nft::Level lhs_level,
	const mata::nft::Level rhs_level,
	const bool project_out,
	const mata::nft::JumpMode jump,
	const mata::nft::CompositionMode mode
) {
	if constexpr (HasTrimNormalization<Normalization>) {
		return mata::nft::compose(lhs, rhs, lhs_level, rhs_level, project_out, jump, mode, Normalization::Trim);
	} else {
		Nft result{mata::nft::compose(lhs, rhs, lhs_level, rhs_level, project_out, jump, mode)};
		result.trim();
		return result;
	}
}

/// The level written as @p text, the whole of it.
mata::nft::Level parse_level(const std::string_view text) {
	mata::nft::Level level{};
	const auto [end, error]{std::from_chars(text.data(), text.data() + text.size(), level)};
	if (error != std::errc{} || end != text.data() + text.size()) {
		throw std::invalid_argument("not a level: '" + std::string{text} + "'");
	}
	return level;
}

int main(int argc, char** argv) try {
	bench::Args args{argc, argv};
	const std::string order{args.option("order", "left")};
	const std::string between{args.option("between", "none")};
	const std::string mode_name{args.option("mode", "auto")};
	const std::string jump_name{args.option("jump", "repeat-symbol")};
	const std::string sync{args.option("sync", "1,0")};
	const std::string project_out{args.option("project-out", "yes")};
	const std::string trim{args.option("trim", "no")};
	args.done();
	if (order != "left" && order != "right") { throw std::invalid_argument("unknown --order=" + order); }
	if (between != "none" && between != "trim" && between != "reduce") {
		throw std::invalid_argument("unknown --between=" + between);
	}
	if (mode_name != "auto" && mode_name != "general") { throw std::invalid_argument("unknown --mode=" + mode_name); }
	if (jump_name != "repeat-symbol" && jump_name != "no-jump") {
		throw std::invalid_argument("unknown --jump=" + jump_name);
	}
	if (project_out != "yes" && project_out != "no") {
		throw std::invalid_argument("unknown --project-out=" + project_out);
	}
	if (trim != "no" && trim != "yes") { throw std::invalid_argument("unknown --trim=" + trim); }
	const size_t comma{sync.find(',')};
	if (comma == std::string::npos) { throw std::invalid_argument("--sync=<lhs level>,<rhs level>, not " + sync); }
	const mata::nft::Level lhs_level{parse_level(std::string_view{sync}.substr(0, comma))};
	const mata::nft::Level rhs_level{parse_level(std::string_view{sync}.substr(comma + 1))};
	const mata::nft::CompositionMode mode{
		mode_name == "auto" ? mata::nft::CompositionMode::Auto : mata::nft::CompositionMode::General
	};
	const mata::nft::JumpMode jump{
		jump_name == "no-jump" ? mata::nft::JumpMode::NoJump : mata::nft::JumpMode::RepeatSymbol
	};

	const std::vector<Nft> nfts{bench::load_nfts(args, 2)};
	const auto compose = [&](const Nft& lhs, const Nft& rhs) {
		return bench::measure_auto("composition", [&] {
			if (trim == "yes") {
				return compose_trimmed(lhs, rhs, lhs_level, rhs_level, project_out == "yes", jump, mode);
			}
			return mata::nft::compose(lhs, rhs, lhs_level, rhs_level, project_out == "yes", jump, mode);
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
