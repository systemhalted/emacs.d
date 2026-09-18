#!/usr/bin/env bash
set -euo pipefail

test_root=$(mktemp -d)

trap 'rm -rf -- "$test_root"' EXIT

cp init.el systemhalted.org "$test_root"

cd "$test_root"

emacs --batch -Q --init-directory "$test_root" -l init.el --eval '(unless (bound-and-true-p vertico-mode) (error "Vertico was not enabled"))'
