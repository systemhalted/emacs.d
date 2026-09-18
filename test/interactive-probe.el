;;; interactive-probe.el --- Isolated startup check -*- lexical-binding: t; -*-

(defun systemhalted/test--interactive-check ()
  "Verify the startup screen after Emacs has entered its command loop."
  (condition-case err
      (progn
        (systemhalted/config--assert-no-package-errors)
        (unless (derived-mode-p 'dashboard-mode)
          (error "Startup selected %S instead of Dashboard" major-mode))
        (when (bound-and-true-p yas-minor-mode)
          (error "Dashboard has snippets enabled"))
        (when (featurep 'org)
          (error "Cached startup unnecessarily loaded Org"))
        (with-temp-file (getenv "SYSTEMHALTED_TEST_RESULT")
          (insert "debug-init passed\n"))
        (setq confirm-kill-emacs nil)
        (kill-emacs 0))
    (error
     (message "Interactive startup failed: %s" (error-message-string err))
     (setq confirm-kill-emacs nil)
     (kill-emacs 1))))

(add-hook 'emacs-startup-hook
          (lambda ()
            (run-with-timer 1 nil #'systemhalted/test--interactive-check)))
