#!/usr/bin/env bash
# Run rewrite checks in an isolated HOME and Emacs init directory.
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/emacs-rewrite-test.XXXXXX")"
test_config="${test_root}/config"
test_home="${test_root}/home"

cleanup() {
  local status=$?
  if [[ -d "${test_config}/elpa" ]]; then
    mkdir -p -- "${repo_dir}/.cache/test-packages"
    cp -Rf -- "${test_config}/elpa/." "${repo_dir}/.cache/test-packages/" || status=1
  fi
  rm -rf -- "$test_root"
  exit "$status"
}
trap cleanup EXIT

mkdir -p -- "$test_config" "$test_home"
cp -- "${repo_dir}/init.el" "${repo_dir}/systemhalted.org" "$test_config/"
mkdir -p -- "${test_config}/test"
cp -- "${repo_dir}/test/systemhalted-test.el" \
      "${repo_dir}/test/package-bootstrap.el" \
      "${test_config}/test/"

package_seed="${SYSTEMHALTED_TEST_PACKAGES:-${repo_dir}/.cache/test-packages}"
if [[ -d "$package_seed" ]]; then
  cp -R -- "$package_seed" "${test_config}/elpa"
fi

export HOME="$test_home"
export XDG_CONFIG_HOME="${test_home}/.config"
export XDG_CACHE_HOME="${test_home}/.cache"
export XDG_RUNTIME_DIR="${test_home}/runtime"
mkdir -m 700 -- "$XDG_RUNTIME_DIR"

cd -- "$test_config"

if [[ $# -eq 0 ]]; then
  set -- smoke ert tangle compile
fi

for check in "$@"; do
  case "$check" in
    smoke)
      emacs --batch -Q --init-directory "$test_config" \
        -l test/package-bootstrap.el \
        -l init.el \
        --eval '(message "rewrite config loaded")'
      ;;
    ert)
      emacs --batch -Q --init-directory "$test_config" \
        -l test/package-bootstrap.el \
        -l init.el \
        -l test/systemhalted-test.el \
        -f ert-run-tests-batch-and-exit
      ;;
    tangle)
      emacs --batch -Q -l org \
        --eval '(org-babel-tangle-file "systemhalted.org")'
      cp -- systemhalted.el "${test_root}/first-tangle.el"
      emacs --batch -Q -l org \
        --eval '(org-babel-tangle-file "systemhalted.org")'
      cmp -- systemhalted.el "${test_root}/first-tangle.el"
      ;;
    compile)
      emacs --batch -Q --init-directory "$test_config" \
        -l test/package-bootstrap.el \
        -l init.el \
        --eval '(unless (byte-compile-file "systemhalted.el") (error "Compilation failed"))'
      ;;
    *)
      printf 'Unknown check: %s\n' "$check" >&2
      exit 2
      ;;
  esac
done
