import sys
import os
import re
import sympy
from sympy.logic.boolalg import to_dnf


MONA_EXT =".mona"
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


def break_transitions(trans):
    if trans in ('\\true', ):
        return [trans]
    expr = sympy.sympify(trans.replace('!', '~'))
    dnf_expr = to_dnf(expr)
    as_str = str(dnf_expr).replace('~', '!')
    return as_str.split(' | ')

def key_sorter(item):
    pos = re.sub("[^0-9]", "", item)
    try:
        return int(pos)
    except ValueError:
        return -1


def to_mona_mata(automata_sources: list[str]) -> list[str]:
    automata_type = peak_type(automata_sources[0]).strip()
    if '@NFA-bits' in automata_type:
        targets = []
        for aut_src in automata_sources:
            aut_tgt = os.path.splitext(aut_src)[0] + MATA_EXT + MONA_EXT
            targets.append(aut_tgt)
        if should_regenerate(targets):
            for aut, tgt_file in zip(automata_sources, targets):
                lines = []
                transitions = []
                with open(aut, 'r') as input_handle:
                    input_lines = input_handle.readlines()
                for input_line in input_lines:
                    if input_line.startswith('%') or input_line.startswith('@'):
                        lines.append(input_line)
                    else:
                        src, *trans, tgt = input_line.split(' ')
                        broken = break_transitions(" ".join(trans))
                        for trans in broken:
                            sorted_trans = ' & '.join(sorted(trans.split(' & '), key=key_sorter))
                            sorted_trans = sorted_trans.replace('(', '').replace(')', '')
                            transitions.append((src, "(" + sorted_trans + ")", tgt))
                transitions = sorted(transitions, key=lambda x: x[0])
                lines.extend([f'{s} {t} {tt}' for (s, t, tt) in transitions])

                with open(tgt_file, 'w') as tgt_handle:
                    tgt_handle.write("".join(lines))

        return targets
    else:
        return automata_sources


if __name__ == "__main__":
    if len(sys.argv) < 1:
        print("usage: to_mona_mata.py [aut1, ... autn]")
        sys.exit(1)
    mona_automata = to_mona_mata(sys.argv[1:])
    print(" ".join(mona_automata))
