#!/bin/bash
set -x -e
ALL_FILES="source/ramjet/*.d source/ramjet/internal/*.d -Isource"
#DFLAGS="-g -debug -odobj -unittest"

mkdir -p obj
dmd $ALL_FILES -g -debug -inline -of./bin/ramjet -odobj -unittest
