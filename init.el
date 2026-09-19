;; -*- lexical-binding: t; -*-

(defvar systemhalted/config-directory
  (file-name-directory (or load-file-name buffer-file-name)))
(defvar systemhalted/config-file
  (expand-file-name "systemhalted.org" systemhalted/config-directory))

(org-babel-load-file systemhalted/config-file)
