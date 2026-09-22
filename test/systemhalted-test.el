;;; systemhalted-test.el --- Regression tests for the rewrite -*- lexical-binding: t; -*-

(require 'ert)

(defun systemhalted-test/hook-contains-p (hook function)
  "Return non-nil when HOOK contains FUNCTION."
  (and (boundp hook)
       (memq function (symbol-value hook))))

(ert-deftest systemhalted-test/completion-stack-is-active ()
  "The configured completion UIs should actually be enabled after startup."
  (should (bound-and-true-p vertico-mode))
  (should (bound-and-true-p marginalia-mode))
  (should (bound-and-true-p global-corfu-mode))
  (should (bound-and-true-p which-key-mode)))

(ert-deftest systemhalted-test/orderless-matches-out-of-order-components ()
  "Orderless should provide the matching semantics the config documents."
  (let ((matches
         (completion-all-completions
          "function describe"
          '("describe-function" "find-file")
          nil
          (length "function describe"))))
    (should (member "describe-function" matches))))

(ert-deftest systemhalted-test/project-and-dashboard-are-wired-together ()
  "Dashboard should read its projects from the built-in project library."
  (require 'project)
  (should (bound-and-true-p project-mode-line))
  (should (fboundp 'systemhalted/project-refresh-known-projects))
  (should (eq (lookup-key project-prefix-map (kbd "R"))
              #'systemhalted/project-refresh-known-projects))
  (should (eq dashboard-projects-backend 'project-el))
  (should (equal dashboard-items
                 '((recents . 5)
                   (projects . 5)
                   (bookmarks . 5)))))

(ert-deftest systemhalted-test/yasnippet-is-scoped-not-global ()
  "Snippets should be enabled in programming buffers but not special buffers."
  (require 'yasnippet)
  (with-temp-buffer
    (emacs-lisp-mode)
    (should (bound-and-true-p yas-minor-mode)))
  (with-temp-buffer
    (fundamental-mode)
    (should-not (bound-and-true-p yas-minor-mode)))
  (with-temp-buffer
    (dashboard-mode)
    (should-not (bound-and-true-p yas-minor-mode))))

(ert-deftest systemhalted-test/visual-wrapping-is-scoped-to-prose ()
  "Visual wrapping should follow text-oriented modes without hard filling."
  (should (systemhalted-test/hook-contains-p 'text-mode-hook #'visual-line-mode))
  (with-temp-buffer
    (fundamental-mode)
    (should-not (bound-and-true-p visual-line-mode))
    (should-not (bound-and-true-p auto-fill-function)))
  (with-temp-buffer
    (emacs-lisp-mode)
    (should-not (bound-and-true-p visual-line-mode))
    (should-not (bound-and-true-p auto-fill-function)))
  (with-temp-buffer
    (org-mode)
    (should (bound-and-true-p visual-line-mode))
    (should-not (bound-and-true-p auto-fill-function)))
  (with-temp-buffer
    (markdown-mode)
    (should (bound-and-true-p visual-line-mode))
    (should-not (bound-and-true-p auto-fill-function))))

(ert-deftest systemhalted-test/eglot-hooks-cover-current-languages ()
  "The rewrite currently promises Eglot for Java and Rust."
  (should (systemhalted-test/hook-contains-p 'java-mode-hook #'eglot-ensure))
  (should (systemhalted-test/hook-contains-p 'rust-mode-hook #'eglot-ensure)))

(ert-deftest systemhalted-test/config-commands-remain-bound ()
  "The literate config should remain directly reloadable and visitable."
  (should (fboundp 'systemhalted/config-reload))
  (should (fboundp 'systemhalted/config-visit))
  (should (eq (key-binding (kbd "C-c r")) #'systemhalted/config-reload))
  (should (eq (key-binding (kbd "C-c e")) #'systemhalted/config-visit)))

(ert-deftest systemhalted-test/emacs-lisp-blocks-declare-tangle-intent ()
  "Every Emacs Lisp source block must explicitly say whether it tangles.
This prevents a visually configured package from silently disappearing from
systemhalted.el because the block omitted its :tangle header argument."
  (with-temp-buffer
    (insert-file-contents systemhalted/config-file)
    (goto-char (point-min))
    (while (re-search-forward "^#\\+begin_src[ \t]+emacs-lisp\\(.*\\)$" nil t)
      (let ((arguments (match-string 1)))
        (should
         (string-match-p
          "[ \t]+:tangle[ \t]+\\(?:yes\\|no\\)\\(?:[ \t]\\|$\\)"
          arguments))))))

(ert-deftest systemhalted-test/generated-config-contains-core-packages ()
  "A tangle should contain the package forms that define the rewrite's core."
  (let ((generated
         (expand-file-name "systemhalted.el" systemhalted/config-directory)))
    (should (file-exists-p generated))
    (with-temp-buffer
      (insert-file-contents generated)
      (dolist (form '("(use-package vertico"
                      "(use-package marginalia"
                      "(use-package orderless"
                      "(use-package corfu"
                      "(use-package eglot"
                      "(use-package project"
                      "(use-package yasnippet"
                      "(use-package dashboard"
                      "(use-package ghostel"
                      "(use-package magit"
                      "(use-package wordwise"
                      "(use-package consult"))
        (goto-char (point-min))
        (should (search-forward form nil t))))))

(provide 'systemhalted-test)
;;; systemhalted-test.el ends here
