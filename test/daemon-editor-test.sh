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
if [[ "${SYSTEMHALTED_TEST_ISOLATED:-}" != 1 ]]; then
  exec bash "${repo_dir}/test/run-config-tests.sh" daemon
fi
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
git init -q "${test_root}/repo"
commit_message="${test_root}/repo/.git/COMMIT_EDITMSG"
printf 'Placeholder commit\n' >"$commit_message"

# Feature checks come first in the list, before find-file-noselect gets a
# chance to autoload anything.  kill-emacs-hook is cleared so the probe
# daemon never rewrites savehist/recentf state shared with real sessions.
probe="(progn
  (systemhalted/config--assert-no-package-errors)
  (unless (featurep 'exec-path-from-shell)
    (error \"Daemon startup did not load the shell environment importer\"))
  (setq kill-emacs-hook nil)
  (with-temp-file \"$result\"
    (insert (format \"%S\" (list
      (featurep 'git-rebase)
      (featurep 'git-commit)
      (featurep 'with-editor)
      (and (memq 'git-commit-setup-check-buffer find-file-hook) t)
      (with-current-buffer (find-file-noselect \"$todo\")
        (key-binding (kbd \"C-c C-c\")))
      (with-current-buffer (find-file-noselect \"$commit_message\")
        (list (and git-commit-mode with-editor-mode)
              (key-binding (kbd \"C-c C-c\"))))))))
  (kill-emacs 0))"

HOME="$test_home" timeout 300 emacs --fg-daemon="daemon-editor-test-$$" -Q \
  -l "${repo_dir}/init.el" --eval "$probe" \
  >"${test_root}/daemon.log" 2>&1 || {
  cat "${test_root}/daemon.log" >&2
  fail "daemon did not start and run the probe cleanly"
}

[[ -f "$result" ]] || fail "probe wrote no result"
got="$(cat "$result")"
want="(t t t t with-editor-finish (t with-editor-finish))"
[[ "$got" == "$want" ]] ||
  fail "editor machinery not resident at daemon init end: got $got, want $want"

# Send finish/abort while a client frame is transitioning to its Git buffer.
# Vary keypress timing around a delayed server visit to catch swallowed input.
# Needs util-linux script(1) for a pty; skipped elsewhere.
if script --version 2>/dev/null | rg -q util-linux; then
  sock="daemon-editor-test-$$"
  daemon_up=""
  cleanup_daemon() {
    [[ -n "$daemon_up" ]] &&
      emacsclient -s "$sock" -e '(progn (setq kill-emacs-hook nil) (kill-emacs))' \
        >/dev/null 2>&1 || true
  }
  trap 'cleanup_daemon; rm -rf -- "$test_root"' EXIT

  HOME="$test_home" timeout 120 emacs --daemon="$sock" -Q \
    -l "${repo_dir}/init.el" \
    --eval '(systemhalted/config--assert-no-package-errors)' \
    >"${test_root}/daemon2.log" 2>&1 ||
    fail "handoff daemon did not start"
  daemon_up=1
  # Widen the handoff window deterministically, like a loaded cold start.
  HOME="$test_home" emacsclient -s "$sock" -e \
    "(advice-add 'server-visit-files :before (lambda (&rest _) (sleep-for 1.2)))" \
    >/dev/null || fail "could not instrument handoff daemon"

  run_handoff() {
    local action="$1" file="$2" label="$3" delay="$4" status=0 expected=0 client_command
    printf -v client_command '%q ' emacsclient -s "$sock" -t "$file"
    client_command="stty rows 30 cols 100; exec ${client_command}"
    # Abort should return an error to Git; finish should return success.
    [[ "$action" == abort ]] && expected=1
    { sleep "$delay"
      if [[ "$action" == abort ]]; then printf '\x03\x0b'; else printf '\x03\x03'; fi
      sleep 4
    } | TERM=xterm-256color HOME="$test_home" timeout 30 \
      script -qefc "$client_command" "${test_root}/${label}.ts" \
      >/dev/null 2>&1 || status=$?
    if [[ "$status" != "$expected" ]]; then
      cat -- "${test_root}/${label}.ts" >&2
      emacsclient -s "$sock" -e \
        '(list (buffer-name) major-mode (bound-and-true-p git-commit-mode) (bound-and-true-p with-editor-mode) (key-binding (kbd "C-c C-c")) (with-current-buffer "*Messages*" (buffer-string)))' \
        >&2 || true
      fail "$label: handoff key did not complete the edit (status $status)"
    fi
    if [[ "$action" == abort ]]; then
      rg -q 'Canceled by user' "${test_root}/${label}.ts" ||
        fail "$label: client failed without the expected cancellation"
    fi
  }
  for delay in 0.2 0.8 1.6; do
    run_handoff finish "$todo" "rebase-finish-${delay}" "$delay"
    run_handoff abort "$todo" "rebase-abort-${delay}" "$delay"
    run_handoff finish "$commit_message" "commit-finish-${delay}" "$delay"
    run_handoff abort "$commit_message" "commit-abort-${delay}" "$delay"
  done
else
  printf 'SKIP: terminal handoff tests require util-linux script(1)\n'
fi

printf 'daemon-editor tests passed\n'
