# Repository Guidelines

## Project Structure & Module Organization

This repository is a personal Emacs configuration. `init.el` is the entry point: it evaluates `systemhalted.org` with `org-babel-load-file`. Treat `systemhalted.org` as the primary configuration source; `systemhalted.el` is generated output and should not be edited by hand. `var/custom.el` stores Emacs Custom state. `snippets/` contains Yasnippet snippets. Package and runtime state such as `elpa/`, `eclipse.jdt.ls/`, `backups/`, `auto-save-list/`, `transient/`, `url/`, and `history` should usually be left untouched.

## Build, Test, and Development Commands

- `emacs --batch -Q -l org --eval '(org-babel-tangle-file "systemhalted.org")'`: regenerate tangled Emacs Lisp from the literate Org config.
- `emacs --batch -Q -l init.el --eval '(message "init loaded")'`: smoke-test that the configuration loads in batch mode.
- `emacs --debug-init`: start Emacs interactively with startup debugging enabled.
- `git status --short`: check for generated or runtime files before committing.

## Coding Style & Naming Conventions

Use Emacs Lisp conventions: two-space indentation, lowercase kebab-case symbols, and namespaced custom functions with the `systemhalted/` prefix (e.g., `systemhalted/config-reload`, `systemhalted/promote-to-todo`). Do not introduce a second namespace.

Use `use-package` for every package with explicit `:ensure t` for external packages and `:ensure nil` for built-ins. There is no `use-package-always-ensure`—implicit installs are deliberately disabled.

Keep literate explanations near the relevant source block in `systemhalted.org`; keep comments in `.el` files brief and operational. Avoid committing machine-local state, caches, credentials, or package manager artifacts.

## Org Workflow Guardrails

The Org setup enforces a three-file model and will signal errors if violated:

- `~/org/todo.org` — execution. The **only** file in `org-agenda-files`. Allowed states: `TODO → IN-PROGRESS → DONE`.
- `~/org/backlog.org` — passive intake. A `before-save-hook` rejects any TODO/IN-PROGRESS/DONE heading or `SCHEDULED:`/`DEADLINE:` line.
- `~/org/notes.org` — durable thinking. `org-todo-keywords` is set to nil locally; a save hook rejects task headings.

Promotion from backlog → todo is intentionally manual via `C-c p` (`systemhalted/promote-to-todo`). Do not widen `org-agenda-files`, add task keywords to `backlog.org`/`notes.org`, or add capture templates that route tasks anywhere except `todo.org`.

## Keybinding Conventions

`C-c p` is bound to `systemhalted/promote-to-todo` (Org workflow). Projectile's prefix was moved to `C-c P` (capital P). Keep this convention when binding anything new.

Notable bindings: `C-c r` reload, `C-c e` visit config, `C-c c` capture, `C-c a` agenda, `C-c l` LSP prefix, `C-c j` enable Jupyter, `C-c b` consult-buffer, `C-c s` consult-ripgrep, `C-x g` magit-status.

## Programming & Completion Stack

Language intelligence is centralized on `lsp-mode` + `lsp-ui`. Do not reintroduce older stacks (Elpy, Tide, company-*).

- `lsp-mode` — protocol, completion provider is capf (`:none` setting avoids company auto-enable).
- `corfu` — in-buffer completion UI (not company).
- `flycheck` — diagnostics in `prog-mode`.
- `yasnippet` + `yasnippet-snippets` — snippets.
- `lsp-java` — JDT LS, installed under `eclipse.jdt.ls/server/`.
- `lsp-pyright` — Python; requires `pyright` binary on PATH.
- `dap-mode` + `dap-java` — debugging via Debug Adapter Protocol.

Web editing is split by file type: `web-mode` for `.html`/`.tsx`, `rjsx-mode` for `.jsx`/`.js`, `typescript-mode` for `.ts`, built-in `css-mode` for CSS. Do not collapse onto a single mode.

Minibuffer completion: `vertico` + `orderless` + `marginalia` + `consult` + `corfu`. Do not replace with Ivy/Helm/company.

## Testing Guidelines

There is no formal test suite. For configuration changes, run the batch load command above and then start Emacs with `--debug-init`. For Org Babel edits, retangle `systemhalted.org` and inspect the generated diff if `systemhalted.el` is tracked in your branch. If adding reusable Lisp, consider adding small `ert-deftest` tests in a future `test/` directory and document the command here.

## Commit & Pull Request Guidelines

Recent commits use short imperative subjects, for example `Add support for Python` and `Update init.el`. Keep subjects concise and scoped. PRs should describe the affected Emacs area, list manual verification performed, link any relevant issue, and include screenshots only for visible UI/theme changes. Call out changes to credentials, language-server paths, or machine-specific paths explicitly.
