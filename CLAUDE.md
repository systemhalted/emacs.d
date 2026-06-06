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

All custom functions are namespaced `systemhalted/...` (e.g. `systemhalted/notes-search`, `systemhalted/config-reload`). Follow this when adding new functions; do not introduce a second namespace.

Use `use-package` for every package, with explicit `:ensure t` for external packages and `:ensure nil` for built-ins. There is no `use-package-always-ensure` — implicit installs are deliberately disabled.

## Org is a second brain — notes only, no tasks

Org holds **no task management**. The rule: anything with a "done" state goes in Apple Reminders, anything with a date goes in Apple Calendar, everything else goes in org. There is no agenda, no TODO keywords (`org-todo-keywords` is nil), no task lifecycle.

`~/org/` is one file per numbered category (sorted by prefix): `00-inbox.org` (unfiled captures, swept weekly), `10-work.org`, `20-personal.org`, `30-learning.org` (`* Books/Articles/Videos/Courses`), `40-writing.org` (`* Ideas/Drafts/Articles/Poetry/Stories/Books/Published`), `50-journal.org` (datetree), `60-ideas.org`, `99-archive.org`. The file list is `systemhalted/org-category-files`; seed headings are in `systemhalted/org-file-structure`. Missing files are created at startup (`systemhalted/ensure-org-files`); empty ones are seeded on open.

Enforcement is **soft by design**: `systemhalted/org-warn-done-state` warns (never blocks) on save when a file under `~/org/` contains TODO/IN-PROGRESS/DONE headings or `SCHEDULED:`/`DEADLINE:` lines. Do not reintroduce hard guards, agenda config, or task keywords.

Capture (`C-c c`) routes by category: `i` inbox, `w` work, `p` personal, `l` learning sub-menu (`a/b/v/c`), `r` writing idea, `d` idea, `j` journal datetree, `s` source-aware note (`systemhalted/org-notes-target` — groups notes in the inbox by the source heading's `:SOURCE_ID:`). Refile targets (`C-c C-w`) are all category files except inbox/journal, completed as `file/heading` paths.

The old `todo.org`/`backlog.org`/`notes.org` are legacy user data: the config must never reference, require, or delete them.

## Keybinding collision to remember

`C-c p` is the Projectile command prefix (the conventional default) — `C-c p *` belongs to Projectile. Custom bindings take capitals (`C-c B`) or other letters; check for collisions before binding anything new.

Other notable bindings established in the config: `C-c r` reload, `C-c e` visit config, `C-c c` capture, `C-c l` store-link, `C-c n` `systemhalted/notes-search` (consult-ripgrep over `~/org/`), `C-c j` enable Jupyter (Org-mode only, opt-in), `C-c b` consult-buffer, `C-c B` `systemhalted/book-view-toggle` (book-style reading view: olivetti margins + mixed-pitch body), `C-c s` consult-ripgrep, `C-x g` magit-status, `C-h T` `systemhalted/tutorial` (open a tutorial subtree of `systemhalted.org` in a read-only indirect buffer; registry is `systemhalted/tutorials`). `C-c a` and `C-c P` are deliberately unbound (they were the agenda and promote-to-todo keys in the retired task workflow).

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
