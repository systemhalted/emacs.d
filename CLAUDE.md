# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository

Personal Emacs configuration. The repo *is* `~/.emacs.d`, so changes here directly affect the user's running Emacs.

This config runs on macOS, Fedora, and Ubuntu — all three are first-class targets. Guard platform-specific code with `(eq system-type 'darwin)` (or equivalent), and when documenting external-tool installation, cover MacPorts and Homebrew for macOS plus `dnf` (Fedora) and `apt` (Ubuntu/Debian). Don't introduce paths like `/Library/...` without a Linux counterpart.

## Source of truth: edit the Org file, not the `.el`

`init.el` is a 3-line shim that calls `(org-babel-load-file "~/.emacs.d/systemhalted.org")`. All real configuration lives in `systemhalted.org` as literate Emacs Lisp blocks. `systemhalted.el` is **generated output** (gitignored) — never edit it by hand; edits will be overwritten on the next reload/tangle.

When making config changes:
- Edit `systemhalted.org`.
- Keep the literate prose near each `#+begin_src emacs-lisp` block; the prose explains *why* and is part of the contract.
- Inside Emacs, `C-c r` (`systemhalted/config-reload`) saves and re-tangles+loads the file. `C-c e` jumps to it.

Useful batch commands:
- `emacs --batch -Q -l org --eval '(org-babel-tangle-file "systemhalted.org")'` — regenerate `systemhalted.el`.
- `emacs --batch -Q -l init.el --eval '(message "init loaded")'` — smoke-test that the config loads.
- `emacs --debug-init` — interactive startup with the debugger enabled.

There is no formal test suite.

## Naming and style

All custom functions are namespaced `systemhalted/...` (e.g. `systemhalted/promote-to-todo`, `systemhalted/config-reload`). Follow this when adding new functions; do not introduce a second namespace.

Use `use-package` for every package, with explicit `:ensure t` for external packages and `:ensure nil` for built-ins. There is no `use-package-always-ensure` — implicit installs are deliberately disabled.

## Org workflow has hard guardrails — read before touching

The Org setup enforces a three-file model and will *signal errors* if you violate it:

- `~/org/todo.org` — execution. The **only** file in `org-agenda-files`. Allowed states: `TODO → IN-PROGRESS → DONE`.
- `~/org/backlog.org` — passive intake. A `before-save-hook` rejects any TODO/IN-PROGRESS/DONE heading or `SCHEDULED:`/`DEADLINE:` line.
- `~/org/notes.org` — durable thinking. `org-todo-keywords` is set to nil locally; a save hook rejects task headings.

Promotion from backlog → todo is intentionally manual via `C-c P` (`systemhalted/promote-to-todo`). An `org-after-todo-state-change-hook` reverts and errors on any TODO state change outside `todo.org`. `systemhalted/assert-agenda-scope` runs at startup and errors if anything else creeps into `org-agenda-files`.

If you add Org features, preserve these invariants. In particular: do not widen `org-agenda-files`, do not add task keywords to `backlog.org`/`notes.org`, and do not add capture templates that route tasks anywhere except `todo.org`'s `* Tasks` heading.

## Keybinding collision to remember

`C-c p` is the Projectile command prefix (the conventional default). `systemhalted/promote-to-todo` was moved to **`C-c P`** (capital P) because day-to-day project work happens far more often than backlog promotion. Keep this convention if you bind anything new — `C-c p *` belongs to Projectile, `C-c P` is reserved for promote-to-todo.

Other notable bindings established in the config: `C-c r` reload, `C-c e` visit config, `C-c c` capture, `C-c a` agenda, `C-c l` store-link, `C-c j` enable Jupyter (Org-mode only, opt-in), `C-c b` consult-buffer, `C-c B` `systemhalted/book-view-toggle` (book-style reading view: olivetti margins + mixed-pitch body), `C-c s` consult-ripgrep, `C-x g` magit-status, `C-h T` `systemhalted/tutorial` (open a tutorial subtree of `systemhalted.org` in a read-only indirect buffer; registry is `systemhalted/tutorials`).

## Programming stack

Language intelligence is centralized on `lsp-mode` + `lsp-ui`. Older language-specific stacks (Elpy, Tide, company-*) were removed deliberately — do not reintroduce them. The current division of labor:

- `lsp-mode` — protocol, completion provider is `:capf`.
- `corfu` — in-buffer completion UI (not company).
- `flycheck` — diagnostics in `prog-mode`.
- `yasnippet` + `yasnippet-snippets` — snippets.
- `lsp-java` — JDT LS, installed under `eclipse.jdt.ls/server/` (gitignored).
- `lsp-pyright` — Python; requires the `pyright` binary on PATH.

Web editing is split by file type and is intentional: `web-mode` for `.html`/`.tsx`, `rjsx-mode` for `.jsx`/`.js`, `typescript-mode` for `.ts`, built-in `css-mode` for CSS. Do not collapse these onto a single mode.

## Completion stack

The minibuffer/in-buffer completion is the small-package stack: `vertico` + `orderless` + `marginalia` + `consult` + `corfu`. Do not replace any one of these with a larger framework (Ivy/Helm/company) — the configuration assumes the responsibilities are split.


## Tutorials

All tutorials are managed through indirect-org buffer. `systemhalted/tutorials` maintains the list of tutorials available within the org file and `systemhalted/tutorial` renders the tutorial as a separate buffer. The heading of the tutorial must match the one in the `systemhalted/tutorials`. The tutorial is mapped to `C-h T`.

## What not to commit

`.gitignore` already excludes `systemhalted.el`, `elpa/`, `eclipse.jdt.ls/`, `backups/`, `auto-save-list/`, `transient/`, `url/`, `history`, `recentf`, `places`, `projectile.cache`, `.lsp-session-v1`, `.dap-breakpoints`, `tramp`, etc. Run `git status --short` before committing — runtime state regenerates and should never appear in a diff.
