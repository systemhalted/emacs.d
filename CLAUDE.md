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

## Org is Organicely, an Org-based second brain — notes only, no tasks

Org holds **no task management**. The rule: anything with a "done" state goes in Apple Reminders, anything with a date goes in Apple Calendar, everything else goes in org. There is no agenda, no TODO keywords (`org-todo-keywords` is nil), no task lifecycle.

`~/organicely/` is a directory tree — **one file per note** — in numbered areas (sorted by prefix): `00-inbox/` (unfiled captures, swept weekly), `10-work/` (flat), `20-personal/`, `30-learning/`, `40-writing/`, `60-ideas/` (each with section subdirectories), `50-journal/` (`daily/` one file per day + `old/`), `99-archive/` (flat). Areas are listed in `systemhalted/org-area-dirs`, their seeded sections in `systemhalted/org-area-sections`; `systemhalted/ensure-org-files` creates the directories when Org first loads. Sections are just directories — new ones appear on demand at capture/refile. A note is a single `.org` file with a `#+TITLE:`/`#+DATE:` header; filenames are kebab-case slugs of the title (`systemhalted/org-slug`, collisions resolved by `systemhalted/org-unique-file`).

Enforcement is **soft by design**: `systemhalted/org-warn-done-state` warns (never blocks) on save when a file under `~/organicely/` contains TODO/IN-PROGRESS/DONE headings or `SCHEDULED:`/`DEADLINE:` lines. Do not reintroduce hard guards, agenda config, or task keywords.

Capture (`C-c c`) has two templates: `c` Note — `systemhalted/org-capture-file` prompts for a destination (`Inbox` or any `area/section`, new ones created if typed) and a title, then creates a fresh note file; `s` Source note — `systemhalted/org-notes-target` groups notes in `00-inbox/sources.org` under a heading keyed by the source's `:SOURCE_ID:`. The journal deliberately has **no capture template**: journaling goes through `C-c J` (`systemhalted/journal`) — opens (creating if needed) today's `50-journal/daily/YYYY-MM-DD.org`, titled e.g. `5th June 2026, Friday`, alone in the frame with book view on. Refiling is not `org-refile`: in Org buffers `C-c C-w` is rebound to `systemhalted/refile-note`, which moves the current note's file — and its `<note>-attachments/` directory — into a chosen `area/section`.

The old `todo.org`/`backlog.org`/`notes.org` are legacy user data: the config must never reference, require, or delete them.

## Keybinding collision to remember

`C-c p` is the Projectile command prefix (the conventional default) — `C-c p *` belongs to Projectile. Custom bindings take capitals (`C-c B`) or other letters; check for collisions before binding anything new.

Other notable bindings established in the config: `C-c r` reload, `C-c e` visit config, `C-c c` capture, `C-c l` store-link, `C-c n` `systemhalted/notes-search` (consult-ripgrep over `~/organicely/`), `C-c J` `systemhalted/journal` (opens today's `50-journal/daily/YYYY-MM-DD.org` in book view), `C-c j` enable Jupyter (Org-mode only, opt-in), `C-c b` consult-buffer, `C-c B` `systemhalted/book-view-toggle` (book-style reading view: olivetti margins + mixed-pitch body), `C-c w` `wordwise-mode` (Kindle-style inline vocabulary hints with difficulty 1–5, from the locally-maintained `wordwise.el` package), `C-c s` consult-ripgrep, `C-c E` `systemhalted/emergency-ui-reset` (shed expensive UI features; deliberately not `C-c !`, which Org and Flycheck shadow), `C-c t` / `C-c T` cycle/select theme, `C-c m` Ghostel terminal, `C-x g` magit-status, `C-h T` `systemhalted/tutorial` (open a tutorial subtree of `systemhalted.org` in a read-only indirect buffer, quit with `q`; registry is `systemhalted/tutorials`). `C-c a` and `C-c P` are deliberately unbound (they were the agenda and promote-to-todo keys in the retired task workflow).

## Programming stack

Language intelligence is centralized on `lsp-mode` + `lsp-ui`. Older language-specific stacks (Elpy, Tide, company-*) were removed deliberately — do not reintroduce them. The current division of labor:

- `lsp-mode` — protocol, completion provider is `:capf`.
- `corfu` — in-buffer completion UI (not company).
- `flycheck` — diagnostics in `prog-mode`.
- `yasnippet` + `yasnippet-snippets` — snippets.
- `lsp-java` — JDT LS, installed under `eclipse.jdt.ls/server/` (gitignored).
- `lsp-pyright` — Python; requires the `pyright` binary on PATH.
- `rustic` + `lsp-mode`'s built-in `rust-analyzer` client — Rust; requires the `rust-analyzer` binary on PATH (clippy diagnostics, rustfmt-on-save). `rustic` is the one deliberate cargo-integrated mode (its own lsp auto-setup is disabled via `rustic-lsp-client nil`; the buffer attaches through `lsp-mode`'s shared hook like every other language).

Web editing is split by file type and is intentional: `web-mode` for `.html`/`.tsx`, `rjsx-mode` for `.jsx`/`.js`, `typescript-mode` for `.ts`, built-in `css-mode` for CSS. Do not collapse these onto a single mode.

## Completion stack

The minibuffer/in-buffer completion is the small-package stack: `vertico` + `orderless` + `marginalia` + `consult` + `corfu`. Do not replace any one of these with a larger framework (Ivy/Helm/company) — the configuration assumes the responsibilities are split.


## Tutorials

All tutorials are managed through indirect-org buffer. `systemhalted/tutorials` maintains the list of tutorials available within the org file and `systemhalted/tutorial` renders the tutorial as a separate buffer. The heading of the tutorial must match the one in the `systemhalted/tutorials`. The tutorial is mapped to `C-h T`. The buffer is read-only and quits with `q` (bound via a composed keymap so Org's `TAB` and `RET` still work).

**`C-h T` is for hand-written tutorials only — do not extend it to package documentation.** Emacs already dispatches that: `C-h R` (`info-display-manual`) completes over every Info manual, built-in *and* package, since `package.el` writes a `dir` file into each package directory and registers it on `Info-directory-list`; `C-h P` (`describe-package`) covers a package's own description; `C-h i` browses the Info directory; `M-x info-apropos` searches all manual indices. A version of this dispatcher that merged in ELPA `.info` files and READMEs was added and then reverted — it found a fraction of what `C-h R` offers, missed every built-in manual, and kept only one manual per package (dropping AUCTeX's `preview-latex`).

## Locally-maintained packages (`sdkman.el`, `trustrail.el`, `wordwise.el`)

Packages maintained in this account are loaded with a hybrid pattern, not a hardcoded path. An environment variable names a local checkout when one exists (`SDKMAN_EL_DIR`, `TRUSTRAIL_EL_DIR`, `WORDWISE_EL_DIR`); that directory goes on `load-path` so edits take effect on the next `C-c r`. When the variable is unset or points nowhere real, `use-package`'s `:vc` keyword has `package-vc` install from GitHub with `:rev :newest`.

`wordwise.el` (Kindle-style vocabulary hints, `C-c w`) was extracted from this config; its section in `systemhalted.org` keeps the savehist registration of `wordwise-cache` (eager, so sessions that never load the package don't drop the cache from `history`) plus a one-time migration from the old `systemhalted/wordwise-cache` name. Wordwise config bugs are usually package bugs — fix them in the wordwise.el repo, not here.

Follow this pattern for any further self-maintained package, and add its variable to `exec-path-from-shell-variables` — GUI Emacs does not inherit the shell environment, so without that import it would never see the local checkout. Never commit a `:load-path` pointing at a developer-specific absolute path; one committed config has to work on macOS, Fedora and Ubuntu.

## What not to commit

`.gitignore` already excludes `systemhalted.el`, `elpa/`, `eclipse.jdt.ls/`, `backups/`, `auto-save-list/`, `transient/`, `url/`, `history`, `recentf`, `places`, `projectile.cache`, `.lsp-session-v1`, `.dap-breakpoints`, `tramp`, etc. Run `git status --short` before committing — runtime state regenerates and should never appear in a diff.
