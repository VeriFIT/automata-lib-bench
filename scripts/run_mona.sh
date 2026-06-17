#!/bin/bash
binary=$1
shift
program=$1
shift
automata="$@"

BASEDIR=$(dirname "$0")

$binary $program $(python3 $BASEDIR/to_mona_mata.py $automata)
