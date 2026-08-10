#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
target="${HOME}/.emacs.d"

if [[ -d "$target" ]]; then
  target_dir="$(cd -- "$target" && pwd -P)"
  if [[ "$target_dir" == "$source_dir" ]]; then
    printf '%s already resolves to %s\n' "$target" "$source_dir"
    exit 0
  fi
fi

if [[ -e "$target" || -L "$target" ]]; then
  printf 'Error: %s already exists; refusing to replace it.\n' "$target" >&2
  printf 'Move it aside explicitly, then run this script again.\n' >&2
  exit 1
fi

ln -s -- "$source_dir" "$target"
printf '%s -> %s\n' "$target" "$source_dir"
