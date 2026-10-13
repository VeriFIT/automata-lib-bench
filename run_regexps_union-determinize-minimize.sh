#!/bin/bash
#
rm -rf ./results/data/regexps_union-determinize-minimize || true
./run_all.sh --jobs 8 --timeout 60 --regexps_union-determinize-minimize --output-dir regexps_union-determinize-minimize
