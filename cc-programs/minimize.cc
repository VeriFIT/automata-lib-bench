// Minimization of every input NFA by one algorithm, chosen per variant:
// Brzozowski's on the NFA, or Hopcroft's on its trimmed determinization.
//
// usage: minimize [--algorithm=brzozowski|hopcroft] <aut.mata>...
#include <stdexcept>
#include <string>

#include <mata/nfa/algorithms.hh>
#include <mata/nfa/nfa.hh>

#include "utils/args.hh"
#include "utils/bench.hh"
#include "utils/mata_load.hh"

using mata::nfa::Nfa;

int main(int argc, char **argv) {
  bench::Args args{argc, argv};
  const std::string algorithm{args.option("algorithm", "brzozowski")};
  args.done();
  if (algorithm != "brzozowski" && algorithm != "hopcroft") {
    throw std::invalid_argument("unknown --algorithm=" + algorithm);
  }

  for (const Nfa &aut : bench::load_nfas(args.files)) {
    const Nfa minimal{bench::measure("minimize", [&] {
      if (algorithm == "hopcroft") {
        return mata::nfa::algorithms::minimize_hopcroft(
            mata::nfa::determinize(aut).trim());
      }
      return mata::nfa::minimize(aut, {{"algorithm", "brzozowski"}});
    })};
    bench::report("states", minimal.num_of_states());
  }
}
