import sys
import os
import libmata.parser as ps
import libmata.alphabets as alph


MINTERM_EXT=".minterm"
MATA_EXT=".mata"


def peak_type(automaton: str):
    with open(automaton, 'r') as automaton_handle:
        line = automaton_handle.readline()
        return line


def should_regenerate(automata):
    for aut in automata:
        if not os.path.exists(aut):
            return True
    return False


def massage_automata(automata_sources: list[str]) -> list[str]:
    automata_type = peak_type(automata_sources[0]).strip()
    if '@NFA-bits' in automata_type:
        targets = []
        for aut_src in automata_sources:
            aut_tgt = os.path.splitext(aut_src)[0] + MATA_EXT + MINTERM_EXT
            targets.append(aut_tgt)
        alphabet = alph.OnTheFlyAlphabet()
        parsed_automata = ps.from_mata(automata_sources, alphabet)
        for aut, tgt in zip(parsed_automata, targets):
            initial = " ".join(f"q{i}" for i in aut.initial_states)
            final = " ".join(f"q{i}" for i in aut.final_states)
            transitions = "\n".join(
                f"q{t.source} {t.symbol} q{t.target}" for t in aut.iterate()
            )

            with open(tgt, 'w') as tgt_handle:
                tgt_handle.write(f"@NFA-explicit\n")
                tgt_handle.write(f"%Initial {initial}\n")
                tgt_handle.write(f"%Final {final}\n")
                tgt_handle.write(transitions)
                tgt_handle.write('\n')

        return targets
    else:
        return automata_sources


if __name__ == "__main__":
    if len(sys.argv) < 1:
        print("usage: massage_arguments.py [aut1, ... autn]")
        sys.exit(1)
    massaged_automata = massage_automata(sys.argv[1:])
    print(" ".join(massaged_automata))
