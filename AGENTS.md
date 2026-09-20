# Repository Guidelines

## Project Structure & Module Organization

This repository is a personal Emacs configuration. `early-init.el` owns pre-init package activation and frame settings. `init.el` loads `systemhalted.el` when current and otherwise tangles and loads `systemhalted.org`. Treat `systemhalted.org` as the primary configuration source; `systemhalted.el` is generated output and should not be edited by hand. `var/custom.el` stores Emacs Custom state. `snippets/` contains Yasnippet snippets. Package and runtime state such as `elpa/`, `eclipse.jdt.ls/`, `backups/`, `auto-save-list/`, `transient/`, `url/`, and `history` should usually be left untouched.

## Build, Test, and Development Commands

- `emacs --batch -Q -l org --eval '(org-babel-tangle-file "systemhalted.org")'`: regenerate tangled Emacs Lisp from the literate Org config.
- `bash test/run-config-tests.sh smoke ert installer tangle compile`: strict load, ERT, installer, deterministic tangling, and compiler diagnostics in an isolated copy.
- `bash test/run-config-tests.sh daemon interactive`: isolated terminal client handoff and `--debug-init` startup checks (Linux/util-linux).
- `emacs --debug-init`: start Emacs interactively with startup debugging enabled.
- `git status --short`: check for generated or runtime files before committing.

## Coding Style & Naming Conventions

Use Emacs Lisp conventions: two-space indentation, lowercase kebab-case symbols, and namespaced custom functions with the `systemhalted/` prefix (e.g., `systemhalted/config-reload`, `systemhalted/notes-search`; internals use `systemhalted/<feature>--<name>`). Do not introduce a second namespace.

Use `use-package` for every package. Archive packages use explicit `:ensure t` (or an explicit package name such as `:ensure auctex`); built-ins, package-bundled extensions, and local-checkout branches use `:ensure nil`. A `:vc` declaration is itself an explicit installer and is not paired with `:ensure`. There is no `use-package-always-ensure`—implicit installs are deliberately disabled.

Keep literate explanations near the relevant source block in `systemhalted.org`; keep comments in `.el` files brief and operational. Avoid committing machine-local state, caches, credentials, or package manager artifacts.

## Org Workflow Guardrails

Org is **Organicely**, a notes-only second brain — no task management. The rule: anything with a "done" state goes in Apple Reminders, anything with a date goes in Apple Calendar, everything else goes in org. There is no agenda, no TODO keywords (`org-todo-keywords` is nil), no task lifecycle.

`~/organicely/` is a directory tree, one file per note, in numbered areas (`00-inbox/`, `10-work/`, `20-personal/`, `30-learning/`, `40-writing/`, `50-journal/`, `60-ideas/`, `99-archive/`); areas and section subdirectories are listed in `systemhalted/org-area-dirs` / `systemhalted/org-area-sections` and created by `systemhalted/ensure-org-files` when Org first loads. Capture (`C-c c`) creates a note file directly (`c` Note) or a source-grouped entry in `00-inbox/sources.org` (`s`); in Org buffers `C-c C-w` is rebound to `systemhalted/refile-note`, which moves the note's file (plus its `-attachments/` directory) into a chosen `area/section`. Journaling is `C-c J` (`systemhalted/journal`), one file per day under `50-journal/daily/`.

Enforcement is **soft by design**: `systemhalted/org-warn-done-state` warns (never blocks) on save when a file under `~/organicely/` contains task-shaped headings or `SCHEDULED:`/`DEADLINE:` lines. Do not reintroduce hard guards, agenda config, task keywords, or a promotion command. The old `todo.org`/`backlog.org`/`notes.org` are legacy user data: never reference, require, or delete them.

## Keybinding Conventions

`C-c p` is free (Projectile's old prefix, now explicitly unbound); project commands are on Emacs' own `C-x p`. Custom bindings take capitals (`C-c B`, `C-c J`, `C-c E`) or other letters; check for major/minor-mode collisions before binding anything new (Org and Flycheck both claim keys under `C-c`). `C-c a` and `C-c P` are deliberately unbound (retired agenda/promote keys).

Notable bindings: `C-c r` reload, `C-c e` visit config, `C-c c` capture, `C-c J` journal, `C-c n` notes search, `C-c l` LSP prefix (and `org-store-link` globally), `C-c j` enable Jupyter (Org only), `C-c b` consult-buffer, `C-c B` book view, `C-c w` wordwise, `C-c s` consult-ripgrep, `C-c E` emergency UI reset, `C-c m` Ghostel terminal, `C-x g` magit-status, `C-h T` tutorials.

## Programming & Completion Stack

Language intelligence is centralized on `lsp-mode` + `lsp-ui`. Do not reintroduce older stacks (Elpy, Tide, company-*).

- `lsp-mode` — protocol, completion provider is capf (`:none` setting avoids company auto-enable).
- `corfu` — in-buffer completion UI (not company).
- `flycheck` — diagnostics in `prog-mode`.
- `yasnippet` + `yasnippet-snippets` — snippets.
- `lsp-java` — JDT LS, installed under `eclipse.jdt.ls/server/`.
- `lsp-pyright` — Python; requires `pyright` binary on PATH.
- `lua-mode` + `lsp-mode`'s built-in `lua-language-server` client — Lua; formatting stays on `lsp-format-buffer`, REPL/Org Babel share the detected Lua interpreter, and `luacheck` on PATH adds Flycheck linting.
  - `dap-mode` + `dap-java` — debugging via Debug Adapter Protocol.

Web editing is split by file type: `web-mode` for `.html`/`.tsx`, `rjsx-mode` for `.jsx`/`.js`, `typescript-mode` for `.ts`, built-in `css-mode` for CSS. Do not collapse onto a single mode.

Minibuffer completion: `vertico` + `orderless` + `marginalia` + `consult` + `corfu`. Do not replace with Ivy/Helm/company.

## Testing Guidelines

Focused regressions live in `test/systemhalted-test.el`. Run them through `bash test/run-config-tests.sh ert`, which isolates HOME before init can load Org. The test suite rejects direct unisolated invocation. `bash test/link-home-test.sh` runs standalone isolated installer cases. Configuration changes require the strict isolated load, relevant ERT tests, and terminal startup/client checks; perform GUI and macOS host checks manually where available. Generated Lisp is ignored; compare fresh tangles rather than committing it. Standalone package internals such as Wordwise are tested in their own repositories, not here.

## Architecture and Ownership

Keep one literate file organized by subsystem; preserve tutorial heading text for `C-h T`. Environment import precedes personal-checkout selection, SDKMAN precedes shared LSP integration, and Projects precedes Dashboard. Omarchy hosts set `systemhalted/omarchy-owned-ui` and repoint `user-emacs-directory` in their external shim; do not edit desktop configuration as part of a repository refactor.

Projects use the built-in `project.el` (`C-x p`); Projectile was removed. Discovery is manual (`systemhalted/discover-projects`), registering projects one level under `~/Work`; it does not call `project-remember-projects-under`, whose non-recursive pass means different things on Emacs 29 and 30. Startup reads only `project-list-file`. Snippets activate in programming and Org buffers. Git editor libraries load eagerly in regular and daemon sessions. Emacs handles Git editor input without custom key replay; retain the With-Editor delayed-hint buffer guard. Keep advice and timers safe across reloads. Shell imports are direct, with no environment cache. Package-install failures are reported without automatic retries; stale archive metadata is refreshed manually. The recorder for those failures is `test/package-error-check.el`, loaded ahead of `init.el` by the checks that assert on them — keep it out of the config.

## Commit & Pull Request Guidelines

Recent commits use short imperative subjects, for example `Add support for Python` and `Update init.el`. Keep subjects concise and scoped. PRs should describe the affected Emacs area, list manual verification performed, link any relevant issue, and include screenshots only for visible UI/theme changes. Call out changes to credentials, language-server paths, or machine-specific paths explicitly.
