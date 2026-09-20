;;; package-bootstrap.el --- Activate isolated test packages -*- lexical-binding: t; -*-

;;; Commentary:
;; `emacs -Q' disables normal package activation.  The rewrite intentionally
;; relies on Emacs' normal startup activation instead of calling
;; `package-initialize' itself, so isolated test processes must reproduce that
;; startup step before loading init.el.

;;; Code:
(require 'package)
(setq package-user-dir (expand-file-name "elpa" user-emacs-directory))
(package-initialize)

;;; package-bootstrap.el ends here
