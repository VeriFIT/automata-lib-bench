#!/bin/bash
#

die() {
    echo "error: $*" >&2
    exit 1
}

echo "================ Building 'automata.net' ================="
../tools/Automata/build.sh
if [ $? -ne 0 ]; then
  die "could not build automata.net library"
fi

echo "=========== Building 'brics', 'automatalib'  ============="
# Note, for some reason, brics/automatalib to be in the correct folder
pushd ../tools/brics
./build.sh
if [ $? -ne 0 ]; then
  die "could not build brics or automatalib library"
fi
popd

echo "=========== Building 'mata', 'vata', 'awali' ============="
../harnesses/nfa-program-parser/build.sh
if [ $? -ne 0 ]; then
  die "could not build mata, vata or awali library"
fi

echo "======= Building 'pymata', 'fado', 'automata.py' ========="
../harnesses/nfa-program-parser/build-python.sh
if [ $? -ne 0 ]; then
  die "could not build pymata, fado or automata.py library"
fi
