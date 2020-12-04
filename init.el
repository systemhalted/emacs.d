;;; init.el --- -*- lexical-binding: t -*-,.

;; Customizations
(add-to-list 'load-path "~/.emacs.d/customizations")
;; -Customizations
;;(load "setup-proxy.el")

(add-to-list 'load-path "~/.emacs.d/vendor")
(load "setup-vm.el")

;; OrgBabel
(org-babel-load-file "~/.emacs.d/systemhalted.org")
;; -OrgBabel

(provide 'init);;;init.el ends here

