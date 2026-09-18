;;; systemhalted-test.el --- Configuration regression tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)

(unless (getenv "SYSTEMHALTED_TEST_ISOLATED")
  (error "Run ERT through bash test/run-config-tests.sh ert (isolates HOME before init)"))

(require 'org)
(require 'eww)

(ert-deftest systemhalted/package-install-refreshes-and-retries-once ()
  (let ((calls 0)
        (refreshes 0)
        (systemhalted/package-install--refreshing nil)
        (descriptor
         (package-desc-create :name 'demo
                              :version '(1 0)
                              :summary "demo"
                              :reqs nil
                              :kind 'tar
                              :archive "melpa"))
        seen)
    (cl-letf (((symbol-function 'package-refresh-contents)
               (lambda () (setq refreshes (1+ refreshes)))))
      (should
       (eq 'installed
           (systemhalted/package-install--with-refresh
            (lambda (package &rest _args)
              (setq calls (1+ calls)
                    seen package)
              (if (= calls 1)
                  (signal 'file-error '("https://melpa.org/packages/demo-1.0.tar" "Not Found"))
                'installed))
            descriptor)))
      (should (= calls 2))
      (should (= refreshes 1))
      (should (eq seen 'demo)))))

(ert-deftest systemhalted/package-install-propagates-second-failure ()
  (let ((calls 0)
        (refreshes 0)
        (systemhalted/package-install--refreshing nil))
    (cl-letf (((symbol-function 'package-refresh-contents)
               (lambda () (setq refreshes (1+ refreshes)))))
      (should-error
       (systemhalted/package-install--with-refresh
        (lambda (&rest _args)
          (setq calls (1+ calls))
          (if (= calls 1)
              (signal 'file-error '("https://melpa.org/packages/demo-1.0.tar" "Not Found"))
            (error "still broken")))
        'demo))
      (should (= calls 2))
      (should (= refreshes 1)))))

(ert-deftest systemhalted/package-install-does-not-retry-unrelated-errors ()
  (dolist (failure '((error "signature verification failed")
                     (error "invalid dependency")
                     (file-error "/local/demo.el" "Permission denied")
                     (file-error "https://melpa.org/packages/demo-1.0.tar" "No Data")
                     (file-error "https://melpa.org/packages/demo-1.0.tar" "Forbidden")
                     (file-error "https://melpa.org/packages/archive-contents" "Not Found")
                     (file-error "https://other.example/demo-1.0.tar" "Not Found")))
    (let ((calls 0) (refreshes 0))
      (cl-letf (((symbol-function 'package-refresh-contents)
                 (lambda () (setq refreshes (1+ refreshes)))))
        (should (equal failure
                       (should-error
                        (systemhalted/package-install--with-refresh
                         (lambda (&rest _args)
                           (setq calls (1+ calls))
                           (signal (car failure) (cdr failure)))
                         'demo))))
        (should (= calls 1))
        (should (= refreshes 0))))))

(ert-deftest systemhalted/package-install-preserves-arguments-and-recursion-guard ()
  (let ((calls 0) seen)
    (cl-letf (((symbol-function 'package-refresh-contents) #'ignore))
      (systemhalted/package-install--with-refresh
       (lambda (_package &rest args)
         (setq calls (1+ calls) seen args)
         (when (= calls 1)
           (signal 'file-error '("https://melpa.org/packages/demo-1.0.el" "Gone"))))
       'demo t 'interactive)
      (should (= calls 2))
      (should (equal seen '(t interactive))))
    (let ((systemhalted/package-install--refreshing t))
      (cl-letf (((symbol-function 'package-refresh-contents)
                 (lambda () (ert-fail "Nested retry refreshed archives"))))
        (should-error
         (systemhalted/package-install--with-refresh
          (lambda (&rest _args)
            (signal 'file-error '("https://melpa.org/packages/demo-1.0.el" "Gone")))
          'demo))))))

(ert-deftest systemhalted/env-import-scopes-prompt-override-and-keeps-imports ()
  (require 'exec-path-from-shell)
  (let ((process-environment (copy-sequence process-environment))
        (exec-path-from-shell-variables '("PATH" "JAVA_HOME"))
        (exec-path exec-path))
    (setenv "POWERLEVEL9K_INSTANT_PROMPT" "original")
    (cl-letf (((symbol-function 'exec-path-from-shell-initialize)
               (lambda ()
                 (should (equal (getenv "POWERLEVEL9K_INSTANT_PROMPT") "quiet"))
                 (setenv "PATH" "/imported/bin")
                 (setenv "JAVA_HOME" "/imported/jdk")
                 (setq exec-path '("/imported/bin")))))
      (systemhalted/env-import--initialize))
    (should (equal (getenv "POWERLEVEL9K_INSTANT_PROMPT") "original"))
    (should (equal (getenv "PATH") "/imported/bin"))
    (should (equal (getenv "JAVA_HOME") "/imported/jdk"))
    (should (equal exec-path '("/imported/bin")))
    (cl-letf (((symbol-function 'exec-path-from-shell-initialize)
               (lambda () (error "shell failure"))))
      (should-error (systemhalted/env-import--initialize)))
    (should (equal (getenv "POWERLEVEL9K_INSTANT_PROMPT") "original"))))

(ert-deftest systemhalted/dashboard-owns-startup-display ()
  (should (eq initial-major-mode 'lisp-interaction-mode))
  (should (eq initial-buffer-choice #'dashboard-open))
  (should (file-directory-p (expand-file-name "backups" user-emacs-directory)))
  (should (file-directory-p (expand-file-name "auto-save-list" user-emacs-directory))))

(ert-deftest systemhalted/config-asserts-recorded-use-package-errors ()
  (let ((systemhalted/use-package-errors '("broken package")))
    (should-error (systemhalted/config--assert-no-package-errors))))

(ert-deftest systemhalted/graphical-frame-fonts-are-hooked ()
  (should (memq #'systemhalted/apply-graphical-frame-fonts
                after-make-frame-functions)))

(ert-deftest systemhalted/graphical-frame-fonts-apply-defaults-and-fallbacks ()
  (let ((frame (selected-frame))
        (systemhalted/omarchy-owned-ui nil)
        face-calls
        fontset-calls)
    (cl-letf (((symbol-function 'display-graphic-p)
               (lambda (&optional arg)
                 (eq (or arg frame) frame)))
              ((symbol-function 'find-font)
               (lambda (_spec) t))
              ((symbol-function 'set-face-attribute)
               (lambda (&rest args)
                 (push args face-calls)))
              ((symbol-function 'set-fontset-font)
               (lambda (&rest args)
                 (push args fontset-calls))))
      (systemhalted/apply-graphical-frame-fonts frame))
    (should (member `(default ,frame :font "Fira Code" :height 150)
                    face-calls))
    (should (member `(variable-pitch ,frame :font "Cantarell" :height 150)
                    face-calls))
    (should
     (equal
      (nreverse fontset-calls)
      '((t (#xe000 . #xf8ff) "FiraCode Nerd Font Mono" nil prepend)
        (nil (#xe000 . #xf8ff) "FiraCode Nerd Font Mono" nil prepend)
        (t (#xf0000 . #xfffff) "FiraCode Nerd Font Mono" nil prepend)
        (nil (#xf0000 . #xfffff) "FiraCode Nerd Font Mono" nil prepend))))))

(ert-deftest systemhalted/graphical-frame-fonts-skip-terminal-frames ()
  (let (face-calls fontset-calls)
    (cl-letf (((symbol-function 'display-graphic-p)
               (lambda (&optional _frame) nil))
              ((symbol-function 'set-face-attribute)
               (lambda (&rest args)
                 (push args face-calls)))
              ((symbol-function 'set-fontset-font)
               (lambda (&rest args)
                 (push args fontset-calls))))
      (systemhalted/apply-graphical-frame-fonts (selected-frame)))
    (should-not face-calls)
    (should-not fontset-calls)))

(ert-deftest systemhalted/dashboard-projects-normalize-root-adds-trailing-slash ()
  (should
   (equal "/tmp/example-project/"
          (systemhalted/dashboard-projects--normalize-root
           "/tmp/example-project"))))

(ert-deftest systemhalted/dashboard-projects-prefers-most-specific-root ()
  (should
   (equal "/tmp/work/app/"
          (systemhalted/dashboard-projects--project-for-file
           "/tmp/work/app/src/main.el"
           '(("/tmp/work/app/" . "/tmp/work/app/")
             ("/tmp/work/" . "/tmp/work/"))))))

(ert-deftest systemhalted/dashboard-projects-sort-by-activity-prioritizes-open-then-recentf ()
  (let ((recentf-list '("/tmp/work/eventing/src/main.el"
                        "/tmp/work/notes/index.org"
                        "/tmp/work/shell/README.md")))
    (cl-letf (((symbol-function 'projectile-open-projects)
               (lambda ()
                 '("/tmp/work/emacs.d/" "/tmp/work/shell/"))))
      (should
       (equal '("/tmp/work/emacs.d/"
                "/tmp/work/shell/"
                "/tmp/work/eventing/"
                "/tmp/work/notes/"
                "/tmp/work/misc/")
              (systemhalted/dashboard-projects--sort-by-activity
               '("/tmp/work/shell"
                 "/tmp/work/misc"
                 "/tmp/work/eventing"
                 "/tmp/work/notes"
                 "/tmp/work/emacs.d")))))))

(ert-deftest systemhalted/dashboard-projects-loader-only-sorts-projectile-backend ()
  (cl-letf (((symbol-function 'systemhalted/dashboard-projects--sort-by-activity)
             (lambda (_projects) '("sorted"))))
    (let ((dashboard-projects-backend 'projectile))
      (should
       (equal '("sorted")
              (systemhalted/dashboard-projects--load-projects-by-activity
               (lambda () '("original"))))))
    (let ((dashboard-projects-backend 'project-el))
      (should
       (equal '("original")
              (systemhalted/dashboard-projects--load-projects-by-activity
               (lambda () '("original"))))))))

(ert-deftest systemhalted/use-package-error-warnings-are-recorded ()
  (let ((systemhalted/use-package-errors nil))
    (display-warning 'use-package "Failed to install demo: no match" :error)
    (display-warning 'use-package "minor grumble" :warning)
    (display-warning 'emacs "unrelated" :error)
    (should (equal systemhalted/use-package-errors
                   '("Failed to install demo: no match")))))

(ert-deftest systemhalted/package-install-keeps-original-error-when-refresh-fails ()
  (let ((systemhalted/package-install--refreshing nil))
    (cl-letf (((symbol-function 'package-refresh-contents)
               (lambda () (error "network down"))))
      (let ((err (should-error
                  (systemhalted/package-install--with-refresh
                   (lambda (&rest _args)
                     (signal 'file-error '("https://melpa.org/packages/demo-1.0.tar" "Not Found")))
                   'demo))))
        (should (equal err '(file-error "https://melpa.org/packages/demo-1.0.tar" "Not Found")))))))

(ert-deftest systemhalted/test-run-is-isolated-before-init ()
  (should (getenv "SYSTEMHALTED_TEST_ISOLATED"))
  (should (string-prefix-p (file-name-as-directory (getenv "HOME"))
                          org-directory))
  (should (file-in-directory-p custom-file user-emacs-directory)))

(ert-deftest systemhalted/org-destination-validation ()
  (dolist (valid '("00-inbox" "20-personal/home" "30-learning/new section"))
    (should (equal valid (systemhalted/org--validate-destination valid))))
  ;; A directory-style trailing slash is normalized away, not rejected.
  (should (equal "20-personal/home"
                 (systemhalted/org--validate-destination "20-personal/home/")))
  (should (equal "00-inbox"
                 (systemhalted/org--validate-destination "00-inbox/")))
  (dolist (invalid '("" "/tmp" "../outside" "00-inbox/.."
                     "00-inbox/.hidden" "00-inbox/a/b"
                     "unknown/section" "20-personal/foo-attachments"
                     "20-personal/foo(Attachments)"))
    (should-error (systemhalted/org--validate-destination invalid)
                  :type 'user-error)))

(ert-deftest systemhalted/org-unique-file-respects-attachment-collisions ()
  (let ((dir (make-temp-file "organicely-unique-" t)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "note-attachments" dir))
          (should
           (string-suffix-p
            "note-2.org"
            (systemhalted/org-unique-file dir "note"))))
      (delete-directory dir t))))

(ert-deftest systemhalted/refile-rolls-back-when-attachments-fail ()
  (let* ((root (make-temp-file "organicely-refile-" t))
         (org-directory (file-name-as-directory root))
         (source-dir (expand-file-name "00-inbox" root))
         (target-dir (expand-file-name "20-personal/home" root))
         (source (expand-file-name "note.org" source-dir))
         (source-attachments
          (expand-file-name "note-attachments" source-dir))
         (target (expand-file-name "note.org" target-dir))
         (original-rename (symbol-function 'rename-file))
         buffer
         (rename-count 0))
    (unwind-protect
        (progn
          (make-directory source-attachments t)
          (make-directory target-dir t)
          (with-temp-file source
            (insert "#+TITLE: Note\n"))
          (setq buffer (find-file-noselect source))
          (with-current-buffer buffer
            (cl-letf (((symbol-function 'completing-read)
                       (lambda (&rest _args) "20-personal/home"))
                      ((symbol-function 'rename-file)
                       (lambda (&rest args)
                         (setq rename-count (1+ rename-count))
                         (if (= rename-count 2)
                             (error "attachment move failed")
                           (apply original-rename args)))))
              (should-error (systemhalted/refile-note)))
            (should (equal buffer-file-name source)))
          (should (file-exists-p source))
          (should (file-directory-p source-attachments))
          (should-not (file-exists-p target)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest systemhalted/project-discovery-survives-symlink-cycles ()
  (let* ((root (make-temp-file "project-discovery-" t))
         (child (expand-file-name "child" root))
         (loop (expand-file-name "loop" root))
         (checks 0))
    (unwind-protect
        (progn
          (make-directory child)
          (make-symbolic-link root loop)
          (cl-letf (((symbol-function 'projectile-project-p)
                     (lambda (_dir)
                       (setq checks (1+ checks))
                       nil)))
            (systemhalted/discover-projects root))
          (should (< checks 5)))
      (delete-directory root t))))

(ert-deftest systemhalted/project-discovery-traverses-symlinked-parents ()
  (let* ((root (make-temp-file "project-discovery-" t))
         (outside (make-temp-file "project-outside-" t))
         (repo (expand-file-name "repo" outside))
         registered)
    (unwind-protect
        (progn
          (make-directory repo)
          (make-symbolic-link outside (expand-file-name "shared" root))
          (cl-letf (((symbol-function 'projectile-project-p)
                     (lambda (dir)
                       (string= (file-name-nondirectory
                                 (directory-file-name dir))
                                "repo")))
                    ((symbol-function 'projectile-project-root)
                     (lambda (dir) dir))
                    ((symbol-function 'projectile-add-known-project)
                     (lambda (dir) (push dir registered))))
            (systemhalted/discover-projects root))
          (should (= (length registered) 1)))
      (delete-directory outside t)
      (delete-directory root t))))

(ert-deftest systemhalted/project-discovery-tolerates-unreadable-directories ()
  (let ((root (make-temp-file "project-unreadable-" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'directory-files)
                   (lambda (&rest _args)
                     (signal 'file-error '("permission denied"))))
                  ((symbol-function 'message) #'ignore))
          (should-not (systemhalted/discover-projects root)))
      (delete-directory root t))))

(ert-deftest systemhalted/org-buffers-default-links-to-eww-with-pdf-dispatch ()
  (with-temp-buffer
    (org-mode)
    (should (local-variable-p 'browse-url-browser-function))
    (should (eq browse-url-browser-function #'systemhalted/org-browse-url)))
  (should-not (eq (default-value 'browse-url-browser-function)
                  #'systemhalted/org-browse-url)))

(ert-deftest systemhalted/org-file-links-to-pdf-open-in-emacs ()
  (should (eq (cdr (assoc "\\.pdf\\'" org-file-apps)) 'emacs)))

(ert-deftest systemhalted/org-browse-url-sends-pdfs-to-pdf-opener ()
  (let (opened eww)
    (cl-letf (((symbol-function 'systemhalted/pdf-open-url)
               (lambda (url &optional _new-window)
                 (setq opened url)))
              ((symbol-function 'eww-browse-url)
               (lambda (&rest args)
                 (setq eww args))))
      (systemhalted/org-browse-url "https://example.com/paper.PDF?download=1")
      (should (equal opened "https://example.com/paper.PDF?download=1"))
      (should-not eww))))

(ert-deftest systemhalted/org-browse-url-keeps-html-links-in-eww ()
  (let (opened eww)
    (cl-letf (((symbol-function 'systemhalted/pdf-open-url)
               (lambda (&rest args)
                 (setq opened args)))
              ((symbol-function 'eww-browse-url)
               (lambda (&rest args)
                 (setq eww args))))
      (systemhalted/org-browse-url "https://example.com/page" t)
      (should (equal eww '("https://example.com/page" t)))
      (should-not opened))))

(ert-deftest systemhalted/pdf-open-url-downloads-to-temp-file ()
  (let (copied-url copied-path displayed)
    (cl-letf (((symbol-function 'url-copy-file)
               (lambda (url path ok-if-already-exists)
                 (setq copied-url url
                       copied-path path)
                 (should ok-if-already-exists)
                 (with-temp-file path
                   (insert "%PDF-1.4\n"))))
              ((symbol-function 'systemhalted/pdf--visit-temporary-file)
               (lambda (path &optional new-window)
                 (setq displayed (list path new-window))
                 path)))
      (unwind-protect
          (progn
            (systemhalted/pdf-open-url "https://example.com/paper.pdf" t)
            (should (equal copied-url "https://example.com/paper.pdf"))
            (should (stringp copied-path))
            (should (string-match-p "\\.pdf\\'" copied-path))
            (should (equal displayed (list copied-path t))))
        (when (and (stringp copied-path)
                   (file-exists-p copied-path))
          (delete-file copied-path))))))

(ert-deftest systemhalted/pdf-delete-temp-file-removes-backed-file ()
  (let ((file (make-temp-file "systemhalted-pdf-test-" nil ".pdf")))
    (unwind-protect
        (with-temp-buffer
          (setq-local systemhalted/pdf-temp-file file)
          (systemhalted/pdf--delete-temp-file)
          (should-not (file-exists-p file)))
      (when (file-exists-p file)
        (delete-file file)))))

(ert-deftest systemhalted/eww-display-pdf-writes-response-body-to-temp-file ()
  (let (written-file)
    (unwind-protect
        (with-temp-buffer
          (set-buffer-multibyte nil)
          (insert "HTTP/1.1 200 OK\n\n%PDF-1.4\nhello\n")
          (goto-char (point-min))
          (search-forward "%PDF")
          (goto-char (match-beginning 0))
          (let ((eww-data '(:url "https://example.com/paper.pdf")))
            (cl-letf (((symbol-function 'systemhalted/pdf--visit-temporary-file)
                       (lambda (path &optional _new-window)
                         (setq written-file path)
                         path)))
              (systemhalted/eww-display-pdf)))
          (should (stringp written-file))
          (should (file-exists-p written-file))
          (with-temp-buffer
            (set-buffer-multibyte nil)
            (insert-file-contents-literally written-file)
            (should (equal (buffer-string) "%PDF-1.4\nhello\n"))))
      (when (and (stringp written-file)
                 (file-exists-p written-file))
        (delete-file written-file)))))

(ert-deftest systemhalted/org-open-in-system-browser-uses-secondary ()
  (let (opened)
    (with-temp-buffer
      (org-mode)
      (insert "[[https://example.com/page]]")
      (goto-char 3)
      (let ((browse-url-secondary-browser-function
             (lambda (url &rest _args) (setq opened url))))
        (systemhalted/org-open-in-system-browser)))
    (should (equal opened "https://example.com/page"))))

(ert-deftest systemhalted/lombok-selects-newest-main-jar-semantically ()
  (let ((jars '("/cache/1.18.9/lombok-1.18.9.jar"
                "/cache/1.18.42/lombok-1.18.42-sources.jar"
                "/cache/1.18.42/lombok-1.18.42.jar"
                "/cache/1.18.50/lombok-1.18.50-javadoc.jar"
                "/cache/edge-SNAPSHOT/lombok-edge-SNAPSHOT.jar")))
    (cl-letf (((symbol-function 'file-expand-wildcards)
               (lambda (&rest _args) jars)))
      (should
       (equal "/cache/1.18.42/lombok-1.18.42.jar"
              (systemhalted/lombok-jar-path))))))

(ert-deftest systemhalted/lombok-falls-back-to-non-numeric-version-dirs ()
  (let ((jars '("/cache/edge-SNAPSHOT/lombok-edge-SNAPSHOT.jar")))
    (cl-letf (((symbol-function 'file-expand-wildcards)
               (lambda (&rest _args) jars)))
      (should
       (equal "/cache/edge-SNAPSHOT/lombok-edge-SNAPSHOT.jar"
              (systemhalted/lombok-jar-path))))))

(ert-deftest systemhalted/git-editor-recovery-preserves-pending-input ()
  (dolist (key '("C-c C-c" "C-c C-k"))
    (with-temp-buffer
      (let* ((keys (kbd key))
             (command (if (equal key "C-c C-c")
                          'with-editor-finish 'with-editor-cancel))
             (map (make-sparse-keymap))
             (unread-command-events '(?x (t . ?y)))
             orig-called)
        (setq-local git-commit-mode t
                    with-editor-mode t
                    server-buffer-clients '(client))
        (define-key map keys command)
        (use-local-map map)
        (cl-letf (((symbol-function 'this-command-keys-vector) (lambda () keys)))
          (systemhalted/undefined-replay-bound-keys
           (lambda () (setq orig-called t))))
        (should-not orig-called)
        (should (equal unread-command-events
                       (append (listify-key-sequence keys) '(?x (t . ?y)))))))))

(ert-deftest systemhalted/git-editor-recovery-ignores-other-contexts ()
  (dolist (excluded '(ordinary-buffer no-client no-editor wrong-binding
                     undefined-binding other-key))
    (with-temp-buffer
      (let* ((keys (kbd (if (eq excluded 'other-key) "C-c z" "C-c C-c")))
             (map (make-sparse-keymap))
             (unread-command-events '(?x))
             orig-called)
        (setq-local git-commit-mode (not (eq excluded 'ordinary-buffer))
                    with-editor-mode (not (eq excluded 'no-editor))
                    server-buffer-clients (unless (eq excluded 'no-client) '(client)))
        (define-key map keys (pcase excluded
                               ('wrong-binding #'ignore)
                               ('undefined-binding #'undefined)
                               (_ #'with-editor-finish)))
        (use-local-map map)
        (cl-letf (((symbol-function 'this-command-keys-vector) (lambda () keys)))
          (systemhalted/undefined-replay-bound-keys
           (lambda () (setq orig-called t))))
        (should orig-called)
        (should (equal unread-command-events '(?x)))))))

(ert-deftest systemhalted/git-editor-recovery-does-not-loop ()
  (with-temp-buffer
    (let ((keys (kbd "C-c C-c"))
          (map (make-sparse-keymap))
          (unread-command-events nil)
          (calls 0))
      (setq-local git-commit-mode t with-editor-mode t server-buffer-clients '(client))
      (define-key map keys #'with-editor-finish)
      (use-local-map map)
      (cl-letf (((symbol-function 'this-command-keys-vector) (lambda () keys)))
        (dotimes (_ 2)
          (systemhalted/undefined-replay-bound-keys
           (lambda () (setq calls (1+ calls))))))
      (should (= calls 1))
      (should (equal unread-command-events (listify-key-sequence keys)))
      (let ((this-command 'with-editor-finish))
        (systemhalted/git-editor--clear-replay))
      (should-not systemhalted/git-editor--replayed-keys))))

(ert-deftest systemhalted/snippets-are-scoped-to-code-and-org ()
  (should-not (bound-and-true-p yas-global-mode))
  (with-temp-buffer
    (emacs-lisp-mode)
    (should (bound-and-true-p yas-minor-mode)))
  (with-temp-buffer
    (org-mode)
    (should (bound-and-true-p yas-minor-mode)))
  (with-temp-buffer
    (dashboard-mode)
    (should-not (bound-and-true-p yas-minor-mode))))

(ert-deftest systemhalted/with-editor-usage-message-skips-killed-buffer ()
  "The guarded usage message must not select a buffer killed meanwhile."
  (let (timer-fn)
    (cl-letf (((symbol-function 'run-with-timer)
               (lambda (_secs _repeat fn &rest _args) (setq timer-fn fn))))
      (with-temp-buffer
        (setq-local with-editor-usage-message "hint")
        (systemhalted/with-editor-usage-message--guarded)))
    ;; The temp buffer is dead by now; firing the timer must be a no-op.
    (should (functionp timer-fn))
    (funcall timer-fn)))

(provide 'systemhalted-test)
;;; systemhalted-test.el ends here
