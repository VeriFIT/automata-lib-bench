// The NFTs a benchmark program on benchmarks/nfa-bench/benchmarks/nft is given, and what it reports about a result.
//
// One file holds all the operands of an operation, one '@NFT-explicit' section each. Symbols are read as the numbers
// they are written as (an IntAlphabet), '<eps>' as EPSILON.
#ifndef NFT_HH
#define NFT_HH

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <fstream>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <type_traits>
#include <vector>

#include <mata/alphabet.hh>
#include <mata/nfa/nfa.hh>
#include <mata/nft/builder.hh>
#include <mata/nft/nft.hh>
#include <mata/parser/parser.hh>

#include "utils/args.hh"
#include "utils/bench.hh"

namespace bench {

/// The end of a program that threw @p error: its message, and an exit status that makes the run an error rather than
/// the crash an uncaught exception would make it. Not 1, which pycobench counts as finished by default.
inline int fail(const std::exception& error) {
	std::cerr << "error: " << error.what() << '\n';
	return 2;
}

/// Times @p f like measure() when one call takes 10 ms or more, and like measure_repeated() when it takes less, as one
/// call of most NFT operations does and one measurement of it would be mostly noise. @p f must not modify its inputs.
/// Returns the result of the first call.
template <typename F> std::invoke_result_t<F&> measure_auto(std::string_view name, F&& f) {
	detail::check_name(name);
	const auto start{Clock::now()};
	std::invoke_result_t<F&> result = std::invoke(f);
	const Seconds once{Clock::now() - start};
	if (once >= std::chrono::milliseconds{10}) {
		detail::print_seconds(name, once);
	} else {
		keep(measure_repeated(name, f));
	}
	return result;
}

/// Loads every section of the one file of @p args as an NFT, and checks there are @p min to @p max of them.
/// Times 'mataparsing'.
inline std::vector<mata::nft::Nft> load_nfts(const Args& args, size_t min, size_t max = SIZE_MAX) {
	if (args.files.size() != 1) { throw std::invalid_argument("expected one file of NFTs"); }
	const std::string& file{args.files[0]};
	std::vector<mata::nft::Nft> nfts{measure("mataparsing", [&] {
		std::ifstream fs{file};
		if (!fs) { throw std::runtime_error("could not open file: " + file); }
		const mata::parser::Parsed parsed{mata::parser::parse_mf(fs, true)};
		mata::IntAlphabet alphabet{};
		std::vector<mata::nft::Nft> result{};
		for (const mata::parser::ParsedSection& section : parsed) {
			result.push_back(mata::nft::builder::construct(section, &alphabet));
		}
		return result;
	})};
	if (nfts.size() < min || nfts.size() > max) {
		throw std::runtime_error(
			file + ": " + std::to_string(nfts.size()) + " NFTs, expected " + std::to_string(min) +
			(max == min ? "" : " or more")
		);
	}
	return nfts;
}

/// The language of the identity NFT @p identity, the form of a literal or a language operand, as an NFA.
inline mata::nfa::Nfa language_of(const mata::nft::Nft& identity) {
	return mata::nft::project_to(identity, 0).to_nfa_move();
}

/// Reports the size of @p aut, and as 'result' whether its language is empty: every variant of a program computes a
/// result of the same emptiness, which the report cross-checks. Times 'emptiness_check'.
template <typename Automaton> void report_result(const Automaton& aut) {
	report("states", aut.num_of_states());
	report("transitions", aut.delta.num_of_transitions());
	report("result", measure_auto("emptiness_check", [&] { return aut.is_lang_empty(); }));
}

} // namespace bench

#endif
