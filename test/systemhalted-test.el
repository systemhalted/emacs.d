;;; systemhalted-test.el --- Configuration regression tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)

(defvar systemhalted-test--original-home (getenv "HOME")
  "Real $HOME before the suite redirected it; see the test below.")

(defvar systemhalted-test--org-preloaded (featurep 'org)
  "Non-nil when init.el already loaded Org (a fresh retangle does).
Then Org's :config ran against the real $HOME before this file could
redirect it, and the hermeticity assertion below cannot apply.")

;; Loading org fires the config's deferred :config, which scaffolds the
;; Organicely tree under $HOME.  Point $HOME at a throwaway directory first
;; (init.el has already loaded from the real one) so running the suite never
;; writes into the user's notes tree.
(setenv "HOME" (make-temp-file "systemhalted-test-home-" t))

(require 'org)

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
                  (error "stale archive")
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
          (error "still broken"))
        'demo))
      (should (= calls 2))
      (should (= refreshes 1)))))

(ert-deftest systemhalted/config-asserts-recorded-use-package-errors ()
  (let ((systemhalted/use-package-errors '("broken package")))
    (should-error (systemhalted/config--assert-no-package-errors))))

(ert-deftest systemhalted/graphical-frame-fonts-are-hooked ()
  (should (memq #'systemhalted/apply-graphical-frame-fonts
                after-make-frame-functions)))

(ert-deftest systemhalted/graphical-frame-fonts-apply-defaults-and-fallbacks ()
  (let ((frame (selected-frame))
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
                   (lambda (&rest _args) (error "real cause"))
                   'demo))))
        (should (string-match-p "real cause" (cadr err)))))))

(ert-deftest systemhalted/test-run-does-not-touch-real-home ()
  (when systemhalted-test--org-preloaded
    (ert-skip "init.el retangled and loaded Org before $HOME was redirected"))
  (should-not
   (string-prefix-p (file-name-as-directory systemhalted-test--original-home)
                    org-directory)))

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

(ert-deftest systemhalted/org-buffers-default-links-to-eww ()
  (with-temp-buffer
    (org-mode)
    (should (local-variable-p 'browse-url-browser-function))
    (should (eq browse-url-browser-function #'eww-browse-url)))
  (should-not (eq (default-value 'browse-url-browser-function)
                  #'eww-browse-url)))

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

(ert-deftest systemhalted/undefined-replay-requeues-sequence-bound-now ()
  "A sequence that is bound in the current buffer gets replayed, not beeped."
  (with-temp-buffer
    (let ((map (make-sparse-keymap))
          (unread-command-events nil)
          orig-called)
      (define-key map (kbd "C-c C-c") #'ignore)
      (use-local-map map)
      (cl-letf (((symbol-function 'this-command-keys-vector)
                 (lambda () (vconcat (kbd "C-c C-c")))))
        (systemhalted/undefined-replay-bound-keys
         (lambda () (setq orig-called t))))
      (should-not orig-called)
      (should (equal unread-command-events
                     (listify-key-sequence (vconcat (kbd "C-c C-c"))))))))

(ert-deftest systemhalted/undefined-replay-leaves-unbound-sequence-alone ()
  "A sequence unbound here still falls through to `undefined'."
  (with-temp-buffer
    (fundamental-mode)
    (let ((unread-command-events nil)
          orig-called)
      (cl-letf (((symbol-function 'this-command-keys-vector)
                 (lambda () (vconcat (kbd "C-c C-c")))))
        (systemhalted/undefined-replay-bound-keys
         (lambda () (setq orig-called t))))
      (should orig-called)
      (should-not unread-command-events))))

(ert-deftest systemhalted/undefined-replay-advice-is-installed ()
  (should (advice-member-p #'systemhalted/undefined-replay-bound-keys
                           'undefined)))

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
