;;; init.el --- Personal Emacs entry point -*- lexical-binding: t; -*-
;;; Commentary:

;;; Code:
(let ((config-el (expand-file-name "systemhalted.el" user-emacs-directory))
      (config-org (expand-file-name "systemhalted.org" user-emacs-directory)))
  ;; Load the prebuilt tangle only while it is current: a git pull
  ;; updates systemhalted.org without retangling, and loading the stale
  ;; .el would silently run the pre-pull configuration.
  (if (and (file-exists-p config-el)
           (not (file-newer-than-file-p config-org config-el)))
      (load config-el nil 'nomessage)
    (org-babel-load-file config-org)))
(put 'downcase-region 'disabled nil)
(provide 'init)
;;; init.el ends here
