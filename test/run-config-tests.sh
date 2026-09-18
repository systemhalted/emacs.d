#!/usr/bin/env bash
set -euo pipefail

test_root=$(mktemp -d)

trap 'rm -rf -- "$test_root"' EXIT

cp init.el systemhalted.org "$test_root"

cd "$test_root"

emacs --batch -Q --init-directory "$test_root" -l init.el --eval '(unless (bound-and-true-p vertico-mode) (error "Vertico was not enabled"))' --eval '(unless (equal (car (completion-all-completions "function describe" (quote ("describe-function" "find-file")) nil (length "function describe"))) "describe-function") (error "Orderless did not work as expected"))'
