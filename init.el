;;; init.el --- Personal Emacs entry point -*- lexical-binding: t; -*-
;;; Commentary:

;;; Code:
(let ((config-el (expand-file-name "systemhalted.el" user-emacs-directory))
      (config-org (expand-file-name "systemhalted.org" user-emacs-directory)))
  (if (file-exists-p config-el)
      (load config-el nil 'nomessage)
    (org-babel-load-file config-org)))
(put 'downcase-region 'disabled nil)
(provide 'init)
;;; init.el ends here
