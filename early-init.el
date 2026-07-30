;;; early-init.el --- Pre-init settings -*- lexical-binding: t; -*-

;;; Commentary:
;; Since Emacs 27, package activation happens before init.el unless it is
;; disabled here.  The literate config (systemhalted.org) calls
;; `package-initialize' explicitly, so switch the automatic pass off —
;; otherwise every package would be activated twice per startup.

;;; Code:

(setq package-enable-at-startup nil)

;;; early-init.el ends here
