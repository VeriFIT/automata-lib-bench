// Application of an NFT T to a language L: the image of L under T (forward), or its preimage (backward). The file
// holds L, as an identity NFT, and T: [L, T] forward, [T, L] backward.
//
// usage: nft-apply --direction=forward|backward [--via=apply|compose|word|invert] [--jump=repeat-symbol|no-jump]
//                  <nfts.mata>
//   apply    T.apply(L as an NFA) on level 0 (forward) or 1 (backward)
//   compose  compose(L, T) (forward) or compose(T, L) (backward), then the level of L projected out
//   word     T.apply(the word of L); L must be a literal or empty, whose image is empty
//   invert   invert_levels(T).apply(L as an NFA) on level 0; backward only
//   --jump   the mata::nft::JumpMode of every operation; z3-noodler applies with no-jump, which takes the fast
//            composition
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

#include <mata/nfa/nfa.hh>
#include <mata/nft/nft.hh>

#include "nft.hh"
#include "utils/args.hh"
#include "utils/bench.hh"

using mata::nfa::Nfa;
using mata::nft::Nft;

int main(int argc, char** argv) try {
	bench::Args args{argc, argv};
	const std::string direction{args.option("direction", "")};
	const std::string via{args.option("via", "apply")};
	const std::string jump_name{args.option("jump", "repeat-symbol")};
	args.done();
	if (direction != "forward" && direction != "backward") {
		throw std::invalid_argument("--direction=forward|backward is required, not '" + direction + "'");
	}
	const bool forward{direction == "forward"};
	if (via != "apply" && via != "compose" && via != "word" && via != "invert") {
		throw std::invalid_argument("unknown --via=" + via);
	}
	if (via == "invert" && forward) { throw std::invalid_argument("--via=invert is for --direction=backward"); }
	if (jump_name != "repeat-symbol" && jump_name != "no-jump") {
		throw std::invalid_argument("unknown --jump=" + jump_name);
	}
	const mata::nft::JumpMode jump{
		jump_name == "no-jump" ? mata::nft::JumpMode::NoJump : mata::nft::JumpMode::RepeatSymbol
	};

	const std::vector<Nft> nfts{bench::load_nfts(args, 2, 2)};
	const Nft& language{forward ? nfts[0] : nfts[1]};
	const Nft& transducer{forward ? nfts[1] : nfts[0]};
	// The level of T that L is applied on.
	const mata::nft::Level level{forward ? 0U : 1U};

	Nft image{};
	if (via == "compose") {
		image = bench::measure_auto("apply", [&] {
			return forward ? mata::nft::project_out(mata::nft::compose(language, transducer, 1, 0, true, jump), 0)
						   : mata::nft::project_out(mata::nft::compose(transducer, language, 1, 0, true, jump), 1);
		});
	} else if (via == "word") {
		const std::optional<mata::Word> word{bench::measure_auto("to_nfa", [&] {
			// A literal may be written with epsilon transitions, which get_word() skips.
			Nfa nfa{mata::nfa::remove_epsilon(bench::language_of(language))};
			const auto some{nfa.get_word()};
			if (some && nfa.trim().delta.num_of_transitions() != some->size()) {
				throw std::invalid_argument("--via=word: the language is not one word");
			}
			return some;
		})};
		if (word) {
			image = bench::measure_auto("apply", [&] { return transducer.apply(*word, level, true, jump); });
		}
	} else {
		const Nfa nfa{bench::measure_auto("to_nfa", [&] { return bench::language_of(language); })};
		image = bench::measure_auto("apply", [&] {
			return via == "invert" ? mata::nft::invert_levels(transducer).apply(nfa, 0, true, jump)
								   : transducer.apply(nfa, level, true, jump);
		});
	}
	bench::report_result(image);
} catch (const std::exception& error) { return bench::fail(error); }
