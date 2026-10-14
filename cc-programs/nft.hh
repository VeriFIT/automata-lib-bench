// The NFTs a benchmark program on benchmarks/nfa-bench/benchmarks/nft is given, and what it reports about a result.
//
// One file holds all the operands of an operation, one '@NFT-explicit' section each. Symbols are read as the numbers
// they are written as (an IntAlphabet), '<eps>' as EPSILON.
//
// Every step of the operation a program computes is timed as itself and as 'operation', which pycobench sums over the
// run: the time of the whole operation, whatever steps a variant takes, for the report to compare the variants on.
#ifndef NFT_HH
#define NFT_HH

#include <algorithm>
#include <array>
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

/// Times @p f, a step of the operation, as @p name and, unless @p step_of_operation is false, as 'operation'. A call of
/// 10 ms or more is timed once; a shorter one, as one call of most NFT operations is, as the median over 5 batches of
/// at least 10 ms of the time per call, as measure_repeated() does. @p f must not modify its inputs. Returns the result
/// of the first call.
template <typename F>
std::invoke_result_t<F&> measure_auto(std::string_view name, F&& f, const bool step_of_operation = true) {
	constexpr Clock::duration min_batch{std::chrono::milliseconds{10}};
	constexpr std::size_t max_calls{std::size_t{1} << 24};
	detail::check_name(name);
	const auto start{Clock::now()};
	std::invoke_result_t<F&> result = std::invoke(f);
	Seconds time{Clock::now() - start};
	if (time < min_batch) {
		const auto batch = [&f](std::size_t calls) {
			const auto batch_start{Clock::now()};
			for (std::size_t i{0}; i < calls; ++i) { keep(std::invoke(f)); }
			return Clock::now() - batch_start;
		};
		std::size_t calls{1};
		while (calls < max_calls && batch(calls) < min_batch) { calls *= 2; }
		std::array<Seconds, 5> per_call{};
		for (Seconds& call : per_call) { call = Seconds{batch(calls)} / static_cast<double>(calls); }
		std::ranges::nth_element(per_call, per_call.begin() + per_call.size() / 2);
		time = per_call[per_call.size() / 2];
	}
	detail::print_seconds(name, time);
	if (step_of_operation) { detail::print_seconds("operation", time); }
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
/// result of the same emptiness, which the report cross-checks. Times 'emptiness_check', which is not part of the
/// operation.
template <typename Automaton> void report_result(const Automaton& aut) {
	report("states", aut.num_of_states());
	report("transitions", aut.delta.num_of_transitions());
	report("result", measure_auto("emptiness_check", [&] { return aut.is_lang_empty(); }, false));
}

} // namespace bench

#endif
