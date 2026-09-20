;;; package-error-check.el --- Record use-package failures -*- lexical-binding: t; -*-

;; Load this BEFORE init.el.  `use-package' reports install and load failures
;; through `display-warning' with type `use-package' and level :error — not
;; through `use-package-error', which is a defsubst (inlined into byte-compiled
;; callers) and only guards malformed declarations at expansion time.  Recording
;; the warnings is the hook that actually sees a package fail.

(defvar systemhalted/use-package-errors nil
  "Errors reported by `use-package' during the current config load.")

(defun systemhalted/use-package--record-warning (type message &optional level &rest _)
  "Record use-package MESSAGE reported at :error LEVEL for batch verification.
TYPE and LEVEL are as in `display-warning'."
  (when (and (eq type 'use-package) (eq level :error))
    (push (format "%s" message) systemhalted/use-package-errors)))

(advice-add 'display-warning :before #'systemhalted/use-package--record-warning)

(defun systemhalted/config--assert-no-package-errors ()
  "Signal an error when `use-package' reported failures during this load."
  (when systemhalted/use-package-errors
    (error "use-package failures: %s"
           (mapconcat #'identity
                      (nreverse systemhalted/use-package-errors)
                      " | "))))

(provide 'package-error-check)
;;; package-error-check.el ends here
