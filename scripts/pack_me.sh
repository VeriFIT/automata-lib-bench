#!/bin/bash

BASEDIR=$(realpath $(dirname "$0"))
PROJECTDIR=$(realpath "$BASEDIR/../..")

TARNAME=tacas24-artifact

git-archive-all $TARNAME.tar

gzip -9 $TARNAME.tar
