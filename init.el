;; -*- lexical-binding: t; -*-

(defvar systemhalted/config-directory
  (file-name-directory (or load-file-name buffer-file-name)))

(org-babel-load-file (expand-file-name "systemhalted.org" systemhalted/config-directory))
