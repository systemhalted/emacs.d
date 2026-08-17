#!/usr/bin/env bash
# A fresh daemon started by Git's editor command (`emacs --daemon &&
# emacsclient -t FILE`) gets the file handed over immediately after init —
# before the daemon has been idle for even a moment, so an idle-timer
# preload of git-rebase cannot have fired yet.  The daemon must therefore
# load the editor machinery eagerly during init.
#
# The probe below runs via --eval, i.e. during command-line processing,
# when the daemon has had zero idle time — the same state an immediate
# emacsclient connection observes.  (Probing over emacsclient instead
# would prove nothing: its own startup latency hands the daemon the idle
# second the timer needs.)
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/daemon-editor-test.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# Hermetic $HOME: the Organicely scaffold and anything else keyed off $HOME
# lands in a throwaway directory; .emacs.d links back to the repo so init.el
# and the installed elpa/ packages resolve as usual.
test_home="${test_root}/home"
mkdir -p -- "$test_home"
ln -s -- "$repo_dir" "${test_home}/.emacs.d"

result="${test_root}/result"
todo="${test_root}/git-rebase-todo"
printf 'pick 0000000 placeholder\n' >"$todo"

# Feature checks come first in the list, before find-file-noselect gets a
# chance to autoload anything.  kill-emacs-hook is cleared so the probe
# daemon never rewrites savehist/recentf state shared with real sessions.
probe="(progn
  (setq kill-emacs-hook nil)
  (with-temp-file \"$result\"
    (insert (format \"%S\" (list
      (featurep 'git-rebase)
      (featurep 'git-commit)
      (featurep 'with-editor)
      (and (memq 'git-commit-setup-check-buffer find-file-hook) t)
      (with-current-buffer (find-file-noselect \"$todo\")
        (key-binding (kbd \"C-c C-c\")))))))
  (kill-emacs 0))"

HOME="$test_home" timeout 300 emacs --fg-daemon="daemon-editor-test-$$" -Q \
  -l "${repo_dir}/init.el" --eval "$probe" \
  >"${test_root}/daemon.log" 2>&1 || {
  cat "${test_root}/daemon.log" >&2
  fail "daemon did not start and run the probe cleanly"
}

[[ -f "$result" ]] || fail "probe wrote no result"
got="$(cat "$result")"
want="(t t t t with-editor-finish)"
[[ "$got" == "$want" ]] ||
  fail "editor machinery not resident at daemon init end: got $got, want $want"

# --- Second race: keys typed during the emacsclient handoff -----------------
# The daemon's command loop latches the pre-handoff buffer's keymaps inside
# read-key-sequence, so a C-c C-c typed before `server-switch-buffer' runs
# resolves against the wrong maps and hits `undefined'.  The config replays
# such a sequence (systemhalted/undefined-replay-bound-keys); without the
# replay, the keypress is swallowed and the client below never exits.
# Needs util-linux script(1) for a pty; skipped elsewhere (ERT covers the
# advice logic itself).
if script --version 2>/dev/null | grep -q util-linux; then
  sock="daemon-editor-test-$$"
  daemon_up=""
  cleanup_daemon() {
    [[ -n "$daemon_up" ]] &&
      emacsclient -s "$sock" -e '(progn (setq kill-emacs-hook nil) (kill-emacs))' \
        >/dev/null 2>&1 || true
  }
  trap 'cleanup_daemon; rm -rf -- "$test_root"' EXIT

  HOME="$test_home" timeout 120 emacs --daemon="$sock" -Q \
    -l "${repo_dir}/init.el" >"${test_root}/daemon2.log" 2>&1 ||
    fail "handoff daemon did not start"
  daemon_up=1
  # Widen the handoff window deterministically, like a loaded cold start.
  HOME="$test_home" emacsclient -s "$sock" -e \
    "(advice-add 'server-visit-files :before (lambda (&rest _) (sleep-for 1.2)))" \
    >/dev/null || fail "could not instrument handoff daemon"

  # One C-c C-c, sent while the daemon is still inside the handoff.  With
  # the replay advice the edit finishes and emacsclient exits promptly.
  if ! { sleep 0.8; printf '\x03\x03'; sleep 8; } | \
    TERM=xterm-256color HOME="$test_home" timeout 30 \
      script -qefc "emacsclient -s $sock -t $todo" "${test_root}/handoff.ts" \
      >/dev/null 2>&1; then
    fail "keypress during handoff was swallowed; client never finished"
  fi
fi

printf 'daemon-editor tests passed\n'
