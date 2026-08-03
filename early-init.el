;;; early-init.el --- Pre-init settings -*- lexical-binding: t; -*-

;;; Commentary:
;; Since Emacs 27, package activation happens before init.el unless it is
;; disabled here.  The literate config (systemhalted.org) calls
;; `package-initialize' explicitly, so switch the automatic pass off —
;; otherwise every package would be activated twice per startup.
;;
;; UI chrome is disabled here — before the first frame is drawn — so
;; Emacs never renders the menu bar, tool bar, or scroll bars only to
;; hide them a moment later.

;;; Code:

(setq package-enable-at-startup nil)

;; Suppress UI chrome before the first frame is drawn.
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)
(setq frame-inhibit-implied-resize t)

;;; early-init.el ends here
