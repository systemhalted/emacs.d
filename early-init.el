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
;;
;; This file also enforces the Emacs 30+ floor, so an unsupported build
;; fails immediately instead of part-way through init.

;;; Code:

;; This configuration targets Emacs 30 and newer only, and stops here rather
;; than half-loading on an older build.  The floor is load-bearing, not
;; aspirational: the web stack hangs `lsp-deferred' off `js-base-mode', which
;; on Emacs 29 would also catch `js-json-mode' (reparented to `prog-mode' in
;; Emacs 30, bug#67463), and the tree-sitter major modes it relies on are not
;; present at all before 29.
(when (< emacs-major-version 30)
  (error "This configuration requires Emacs 30 or newer; this is %s"
         emacs-version))

(setq package-enable-at-startup nil)

;; Suppress UI chrome before the first frame is drawn.
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)
(setq frame-inhibit-implied-resize t)

;;; early-init.el ends here
