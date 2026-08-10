#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
installer="${repo_dir}/link-home.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/link-home-test.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

home_new="${test_root}/new"
mkdir -p -- "$home_new"
HOME="$home_new" bash "$installer"
[[ -L "${home_new}/.emacs.d" ]] || fail "missing target was not linked"
[[ "$(cd -- "${home_new}/.emacs.d" && pwd -P)" == "$repo_dir" ]] ||
  fail "new link points at the wrong repository"
HOME="$home_new" bash "$installer"

home_dir="${test_root}/existing-dir"
mkdir -p -- "${home_dir}/.emacs.d"
printf 'keep\n' >"${home_dir}/.emacs.d/sentinel"
if HOME="$home_dir" bash "$installer"; then
  fail "existing directory was accepted"
fi
[[ -f "${home_dir}/.emacs.d/sentinel" ]] ||
  fail "existing directory contents were changed"

home_file="${test_root}/existing-file"
mkdir -p -- "$home_file"
printf 'keep\n' >"${home_file}/.emacs.d"
if HOME="$home_file" bash "$installer"; then
  fail "existing file was accepted"
fi
[[ -f "${home_file}/.emacs.d" ]] || fail "existing file was changed"

home_link="${test_root}/wrong-link"
wrong_target="${test_root}/wrong-target"
mkdir -p -- "$home_link" "$wrong_target"
ln -s -- "$wrong_target" "${home_link}/.emacs.d"
if HOME="$home_link" bash "$installer"; then
  fail "wrong symlink was accepted"
fi
[[ -L "${home_link}/.emacs.d" ]] || fail "wrong symlink was changed"

home_dangling="${test_root}/dangling-link"
mkdir -p -- "$home_dangling"
ln -s -- "${test_root}/missing" "${home_dangling}/.emacs.d"
if HOME="$home_dangling" bash "$installer"; then
  fail "dangling symlink was accepted"
fi
[[ -L "${home_dangling}/.emacs.d" ]] || fail "dangling symlink was changed"

home_direct="${test_root}/direct"
mkdir -p -- "${home_direct}/.emacs.d"
cp -- "$installer" "${home_direct}/.emacs.d/link-home.sh"
HOME="$home_direct" bash "${home_direct}/.emacs.d/link-home.sh"
[[ -f "${home_direct}/.emacs.d/link-home.sh" ]] ||
  fail "direct clone was changed"

printf 'link-home tests passed\n'
