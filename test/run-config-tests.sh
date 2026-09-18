#!/usr/bin/env bash
# Run configuration checks without sharing the user's home or package state.
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/emacs-config-test.XXXXXX")"
test_config="${test_root}/config"
test_home="${test_root}/home"
cleanup() {
  local test_status=$?
  # Cache only the isolated package copy, never the user's elpa directory.
  if [[ -d "${test_config}/elpa" ]]; then
    mkdir -p -- "${repo_dir}/.cache/test-packages"
    cp -Rf -- "${test_config}/elpa/." "${repo_dir}/.cache/test-packages/" || test_status=1
  fi
  rm -rf -- "$test_root"
  exit "$test_status"
}
trap cleanup EXIT
mkdir -p -- "$test_config" "$test_home"
cp -- "${repo_dir}/init.el" "${repo_dir}/early-init.el" \
  "${repo_dir}/systemhalted.org" "${repo_dir}/link-home.sh" "$test_config"
cp -R -- "${repo_dir}/test" "${test_config}/test"
package_seed="${SYSTEMHALTED_TEST_PACKAGES:-${repo_dir}/.cache/test-packages}"
if [[ ! -d "$package_seed" ]]; then
  package_seed="${repo_dir}/elpa"
fi
if [[ -d "$package_seed" ]]; then
  cp -R -- "$package_seed" "${test_config}/elpa"
fi
ln -s -- "$test_config" "${test_home}/.emacs.d"
export HOME="$test_home"
export XDG_CONFIG_HOME="${test_home}/.config"
export XDG_CACHE_HOME="${test_home}/.cache"
export SYSTEMHALTED_TEST_ISOLATED=1
unset SDKMAN_EL_DIR TRUSTRAIL_EL_DIR WORDWISE_EL_DIR
cd -- "$test_config"

checks=("${@:-smoke}")
for check in "${checks[@]}"; do
  case "$check" in
    smoke)
      emacs --batch -Q -l early-init.el -l init.el \
        --eval '(systemhalted/config--assert-no-package-errors)' \
        --eval '(message "init loaded")'
      ;;
    ert)
      emacs --batch -Q -l early-init.el -l init.el \
        --eval '(systemhalted/config--assert-no-package-errors)' \
        -l test/systemhalted-test.el -f ert-run-tests-batch-and-exit
      ;;
    daemon) bash test/daemon-editor-test.sh ;;
    installer) bash test/link-home-test.sh ;;
    tangle)
      emacs --batch -Q -l org \
        --eval '(org-babel-tangle-file "systemhalted.org")'
      cp -- systemhalted.el "${test_root}/first-tangle.el"
      emacs --batch -Q -l org \
        --eval '(org-babel-tangle-file "systemhalted.org")'
      cmp -- systemhalted.el "${test_root}/first-tangle.el"
      ;;
    compile)
      emacs --batch -Q -l early-init.el -l init.el \
        --eval '(systemhalted/config--assert-no-package-errors)' \
        --eval '(unless (byte-compile-file "systemhalted.el") (error "Compilation failed"))'
      ;;
    *) printf 'Unknown check: %s\n' "$check" >&2; exit 2 ;;
  esac
done
