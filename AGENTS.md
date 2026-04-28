# Repository Guidelines

## Project Structure & Module Organization

This repository is a personal Emacs configuration. `init.el` is the entry point: it evaluates `systemhalted.org` with `org-babel-load-file`. Treat `systemhalted.org` as the primary configuration source; `systemhalted.el` is generated output and should not be edited by hand. `emacs-custom.el` stores Emacs Custom state. `snippets/` contains Yasnippet snippets. Package and runtime state such as `elpa/`, `eclipse.jdt.ls/`, `backups/`, `auto-save-list/`, `transient/`, `url/`, and `history` should usually be left untouched.

## Build, Test, and Development Commands

- `emacs --batch -Q -l org --eval '(org-babel-tangle-file "systemhalted.org")'`: regenerate tangled Emacs Lisp from the literate Org config.
- `emacs --batch -Q -l init.el --eval '(message "init loaded")'`: smoke-test that the configuration loads in batch mode.
- `emacs --debug-init`: start Emacs interactively with startup debugging enabled.
- `git status --short`: check for generated or runtime files before committing.

## Coding Style & Naming Conventions

Use Emacs Lisp conventions: two-space indentation, lowercase kebab-case symbols, and namespaced custom functions such as `systemhalted/config-reload`. Prefer `use-package` for package configuration because the main config already uses it extensively. Keep literate explanations near the relevant source block in `systemhalted.org`; keep comments in `.el` files brief and operational. Avoid committing machine-local state, caches, credentials, or package manager artifacts.

## Testing Guidelines

There is no formal test suite. For configuration changes, run the batch load command above and then start Emacs with `--debug-init`. For Org Babel edits, retangle `systemhalted.org` and inspect the generated diff if `systemhalted.el` is tracked in your branch. If adding reusable Lisp, consider adding small `ert-deftest` tests in a future `test/` directory and document the command here.

## Commit & Pull Request Guidelines

Recent commits use short imperative subjects, for example `Add support for Python` and `Update init.el`. Keep subjects concise and scoped. PRs should describe the affected Emacs area, list manual verification performed, link any relevant issue, and include screenshots only for visible UI/theme changes. Call out changes to credentials, language-server paths, or machine-specific paths explicitly.
