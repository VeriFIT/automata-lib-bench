"""Prints the paths of the given automata as tools without bitvector support read them.

Bitvector (@NFA-bits) automata are mintermized together into explicit copies,
cached in 'build/minterm/<key>/' where <key> hashes the inputs' contents, the
bindings' version and this script; other automata are printed unchanged.

usage: python massage_arguments.py <aut1> ... <autn>
"""

import hashlib
import importlib.metadata
import os
import shutil
import sys
import tempfile

import libmata.alphabets as alph
import libmata.parser as ps

CACHE_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build", "minterm")


def peak_type(automaton: str):
    with open(automaton, "r") as automaton_handle:
        return automaton_handle.readline()


def cache_key(automata_sources: list[str]) -> str:
    """Hash of everything the mintermized copies depend on.

    The automata are mintermized together, so each copy depends on all inputs and their order.
    """
    digest = hashlib.sha256()
    try:
        bindings = importlib.metadata.version("libmata")
    except importlib.metadata.PackageNotFoundError:
        bindings = "unknown"
    with open(__file__, "rb") as handle:
        script = handle.read()
    for part in (bindings.encode(), script):
        digest.update(len(part).to_bytes(8, "little") + part)
    for aut_src in automata_sources:
        with open(aut_src, "rb") as handle:
            content = handle.read()
        digest.update(len(content).to_bytes(8, "little") + content)
    return digest.hexdigest()[:32]


def write_mintermized(automata_sources: list[str], target_dir: str, names: list[str]):
    alphabet = alph.OnTheFlyAlphabet()
    parsed_automata = ps.from_mata(automata_sources, alphabet)
    for aut, name in zip(parsed_automata, names):
        initial = " ".join(f"q{i}" for i in aut.initial_states)
        final = " ".join(f"q{i}" for i in aut.final_states)
        transitions = "\n".join(f"q{t.source} {t.symbol} q{t.target}" for t in aut.iterate())
        with open(os.path.join(target_dir, name), "w") as tgt_handle:
            tgt_handle.write("@NFA-explicit\n")
            tgt_handle.write(f"%Initial {initial}\n")
            tgt_handle.write(f"%Final {final}\n")
            tgt_handle.write(transitions)
            tgt_handle.write("\n")


def massage_automata(automata_sources: list[str]) -> list[str]:
    if "@NFA-bits" not in peak_type(automata_sources[0]):
        return automata_sources

    target_dir = os.path.join(CACHE_DIR, cache_key(automata_sources))
    # The index keeps an automaton passed twice from sharing one copy.
    names = [f"{i}-{os.path.basename(aut_src)}" for i, aut_src in enumerate(automata_sources)]
    targets = [os.path.join(target_dir, name) for name in names]
    if not os.path.isdir(target_dir):
        os.makedirs(CACHE_DIR, exist_ok=True)
        # Built aside and renamed into place, so that parallel jobs see either all copies or none.
        tmp_dir = tempfile.mkdtemp(dir=CACHE_DIR, prefix=".tmp-")
        try:
            write_mintermized(automata_sources, tmp_dir, names)
            os.rename(tmp_dir, target_dir)
        except OSError:
            if not os.path.isdir(target_dir):
                raise
            # Another job renamed its identical copies into place first.
        finally:
            shutil.rmtree(tmp_dir, ignore_errors=True)
    return targets


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: massage_arguments.py <aut1> ... <autn>", file=sys.stderr)
        sys.exit(1)
    print(" ".join(massage_automata(sys.argv[1:])))
