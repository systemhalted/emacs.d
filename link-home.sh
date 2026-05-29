#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
target="${HOME}/.emacs.d"

if [[ -L "$target" || -d "$target" ]]; then
  rm -rf -- "$target"
elif [[ -e "$target" ]]; then
  printf 'Error: %s exists and is not a directory or symlink.\n' "$target" >&2
  exit 1
fi

ln -s -- "$source_dir" "$target"
printf '%s -> %s\n' "$target" "$source_dir"
