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
  "The rewrite currently promises Eglot for Java, Rust and Go."
  (should (systemhalted-test/hook-contains-p 'java-mode-hook #'eglot-ensure))
  (should (systemhalted-test/hook-contains-p 'rust-mode-hook #'eglot-ensure))
  (should (systemhalted-test/hook-contains-p 'go-ts-mode-hook #'eglot-ensure))
  (should (systemhalted-test/hook-contains-p 'go-mod-ts-mode-hook #'eglot-ensure)))

(ert-deftest systemhalted-test/go-save-hook-is-safe-without-gopls ()
  "Saving a Go buffer must not fail when gopls is not connected."
  (should (systemhalted-test/hook-contains-p
           'go-ts-mode-hook #'systemhalted/go-setup-format-on-save))
  (should (fboundp 'systemhalted/go-before-save))
  (with-temp-buffer
    (should-not (systemhalted/go-before-save))))

(ert-deftest systemhalted-test/rust-save-hook-is-installed-and-safe ()
  "Rust buffers format on save, and saving works without rust-analyzer."
  (with-temp-buffer
    (rust-mode)
    (should (memq #'systemhalted/rust-setup-format-on-save rust-mode-hook))
    (should (memq #'systemhalted/rust-before-save before-save-hook))
    (should-not (systemhalted/rust-before-save))))

(ert-deftest systemhalted-test/auto-save-visited-is-scoped ()
  "Idle saves in place are on, but only for Eglot-managed Rust and Go buffers."
  (should (bound-and-true-p auto-save-visited-mode))
  (should (eq auto-save-visited-predicate #'systemhalted/auto-save-visited-p))
  (with-temp-buffer
    (fundamental-mode)
    (should-not (systemhalted/auto-save-visited-p)))
  (with-temp-buffer
    (rust-mode)
    (should-not (systemhalted/auto-save-visited-p))))

(ert-deftest systemhalted-test/pdf-files-open-with-pdf-tools ()
  "PDF files and PDFs from EWW should open in pdf-view-mode."
  (should (eq (assoc-default "paper.pdf" auto-mode-alist #'string-match)
              'pdf-view-mode))
  (should (fboundp 'pdf-view-mode))
  (require 'mailcap)
  (should (member '((viewer . pdf-view-mode)
                    (type . "application/pdf")
                    (test . window-system))
                  mailcap-user-mime-data)))

(ert-deftest systemhalted-test/pdf-search-match-markup-needs-a-match ()
  "Marking up a search match without one should explain what to do.
The key binding is not checked here: loading `pdf-annot' starts the
epdfinfo server, which the isolated test setup does not build."
  (should (commandp #'systemhalted/pdf-annotate-search-match))
  (with-temp-buffer
    (should-error (systemhalted/pdf-annotate-search-match 'highlight)
                  :type 'user-error)))

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
