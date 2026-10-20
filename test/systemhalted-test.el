;;; systemhalted-test.el --- Regression tests for the rewrite -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)

(defun systemhalted-test/hook-contains-p (hook function)
  "Return non-nil when HOOK contains FUNCTION."
  (and (boundp hook)
       (memq function (symbol-value hook))))

(ert-deftest systemhalted-test/completion-stack-is-active ()
  "The configured completion UIs should actually be enabled after startup."
  (should (bound-and-true-p vertico-mode))
  (should (bound-and-true-p marginalia-mode))
  (should (bound-and-true-p global-corfu-mode))
  (should (bound-and-true-p which-key-mode)))

(ert-deftest systemhalted-test/orderless-matches-out-of-order-components ()
  "Orderless should provide the matching semantics the config documents."
  (let ((matches
         (completion-all-completions
          "function describe"
          '("describe-function" "find-file")
          nil
          (length "function describe"))))
    (should (member "describe-function" matches))))

(ert-deftest systemhalted-test/project-and-dashboard-are-wired-together ()
  "Dashboard should read its projects from the built-in project library."
  (require 'project)
  (should (bound-and-true-p project-mode-line))
  (should (fboundp 'systemhalted/project-refresh-known-projects))
  (should (eq (lookup-key project-prefix-map (kbd "R"))
              #'systemhalted/project-refresh-known-projects))
  (should (eq dashboard-projects-backend 'project-el))
  (should (equal dashboard-items
                 '((recents . 5)
                   (projects . 5)
                   (bookmarks . 5)))))

(ert-deftest systemhalted-test/yasnippet-is-scoped-not-global ()
  "Snippets should be enabled in programming buffers but not special buffers."
  (require 'yasnippet)
  (with-temp-buffer
    (emacs-lisp-mode)
    (should (bound-and-true-p yas-minor-mode)))
  (with-temp-buffer
    (fundamental-mode)
    (should-not (bound-and-true-p yas-minor-mode)))
  (with-temp-buffer
    (dashboard-mode)
    (should-not (bound-and-true-p yas-minor-mode))))

(ert-deftest systemhalted-test/visual-wrapping-is-scoped-to-prose ()
  "Visual wrapping should follow text-oriented modes without hard filling."
  (should (systemhalted-test/hook-contains-p 'text-mode-hook #'visual-line-mode))
  (with-temp-buffer
    (fundamental-mode)
    (should-not (bound-and-true-p visual-line-mode))
    (should-not (bound-and-true-p auto-fill-function)))
  (with-temp-buffer
    (emacs-lisp-mode)
    (should-not (bound-and-true-p visual-line-mode))
    (should-not (bound-and-true-p auto-fill-function)))
  (with-temp-buffer
    (org-mode)
    (should (bound-and-true-p visual-line-mode))
    (should-not (bound-and-true-p auto-fill-function)))
  (with-temp-buffer
    (markdown-mode)
    (should (bound-and-true-p visual-line-mode))
    (should-not (bound-and-true-p auto-fill-function))))

(ert-deftest systemhalted-test/eglot-hooks-cover-current-languages ()
  "The rewrite currently promises Eglot for Java, Rust and Go."
  (should (systemhalted-test/hook-contains-p 'java-mode-hook #'eglot-ensure))
  (should (systemhalted-test/hook-contains-p 'rust-mode-hook #'eglot-ensure))
  (should (systemhalted-test/hook-contains-p 'go-ts-mode-hook #'eglot-ensure))
  (should (systemhalted-test/hook-contains-p 'go-mod-ts-mode-hook #'eglot-ensure)))

(ert-deftest systemhalted-test/go-save-hook-is-safe-without-gopls ()
  "Saving a Go buffer must not fail when gopls is not connected."
  (should (systemhalted-test/hook-contains-p
           'go-ts-mode-hook #'systemhalted/go-setup-format-on-save))
  (should (fboundp 'systemhalted/go-before-save))
  (with-temp-buffer
    (should-not (systemhalted/go-before-save))))

(ert-deftest systemhalted-test/rust-save-hook-is-installed-and-safe ()
  "Rust buffers format on save, and saving works without rust-analyzer."
  (with-temp-buffer
    (rust-mode)
    (should (memq #'systemhalted/rust-setup-format-on-save rust-mode-hook))
    (should (memq #'systemhalted/rust-before-save before-save-hook))
    (should-not (systemhalted/rust-before-save))))

(ert-deftest systemhalted-test/auto-save-visited-is-scoped ()
  "Idle saves in place are on, but only for Eglot-managed Rust and Go buffers."
  (should (bound-and-true-p auto-save-visited-mode))
  (should (eq auto-save-visited-predicate #'systemhalted/auto-save-visited-p))
  (with-temp-buffer
    (fundamental-mode)
    (should-not (systemhalted/auto-save-visited-p)))
  (with-temp-buffer
    (rust-mode)
    (should-not (systemhalted/auto-save-visited-p))))

(ert-deftest systemhalted-test/eww-pdf-links-are-routed-explicitly ()
  "Direct PDF links should bypass HTML rendering and use the PDF opener."
  (should (fboundp 'systemhalted/browse-url-pdf))
  (should (equal eww-use-browse-url systemhalted/eww-use-browse-url-regexp))
  (should (string-match-p eww-use-browse-url "mailto:test@example.com"))
  (should (string-match-p eww-use-browse-url "https://example.com/paper.pdf"))
  (should (string-match-p eww-use-browse-url
                          "https://example.com/paper.PDF?download=1"))
  (let ((matches 0))
    (dolist (entry browse-url-handlers)
      (when (equal (car entry) systemhalted/pdf-url-regexp)
        (setq matches (1+ matches))
        (should (eq (cdr entry) #'systemhalted/browse-url-pdf))))
    (should (= matches 1))))

(ert-deftest systemhalted-test/pdf-mime-handler-is-registered-once ()
  "PDF MIME data should use the custom handler without duplicates."
  (should (fboundp 'systemhalted/view-pdf-mime))
  (let ((matches 0))
    (dolist (entry mailcap-user-mime-data)
      (when (equal entry '(systemhalted/view-pdf-mime "application/pdf"))
        (setq matches (1+ matches))))
    (should (= matches 1))))

(ert-deftest systemhalted-test/browse-url-pdf-downloads-before-opening ()
  "PDF URLs should be downloaded before the viewer is invoked."
  (let (downloaded opened)
    (cl-letf (((symbol-function 'systemhalted/pdf-temp-file)
               (lambda () "/tmp/systemhalted-eww-test.pdf"))
              ((symbol-function 'url-copy-file)
               (lambda (url file ok-if-already-exists)
                 (setq downloaded (list url file ok-if-already-exists))))
              ((symbol-function 'systemhalted/open-pdf-file)
               (lambda (file)
                 (setq opened file))))
      (systemhalted/browse-url-pdf "https://example.com/paper.pdf")
      (should (equal downloaded
                     '("https://example.com/paper.pdf"
                       "/tmp/systemhalted-eww-test.pdf"
                       t)))
      (should (equal opened "/tmp/systemhalted-eww-test.pdf")))))

(ert-deftest systemhalted-test/browse-url-pdf-expands-relative-eww-links ()
  "Relative PDF links from EWW pages should be expanded before download."
  (let ((eww-data '(:url "https://plai.org/"))
        downloaded)
    (cl-letf (((symbol-function 'systemhalted/pdf-temp-file)
               (lambda () "/tmp/systemhalted-eww-relative.pdf"))
              ((symbol-function 'url-copy-file)
               (lambda (url file ok-if-already-exists)
                 (setq downloaded (list url file ok-if-already-exists))))
              ((symbol-function 'systemhalted/open-pdf-file)
               (lambda (_file))))
      (systemhalted/browse-url-pdf "3/5/plai-v325.pdf")
      (should (equal downloaded
                     '("https://plai.org/3/5/plai-v325.pdf"
                       "/tmp/systemhalted-eww-relative.pdf"
                       t))))))

(ert-deftest systemhalted-test/pdftoppm-backend-is-configured-when-needed ()
  "DocView should use pdftoppm when Ghostscript and MuPDF are absent."
  (let ((doc-view-ghostscript-program "gs")
        (doc-view-pdfdraw-program "mudraw")
        (doc-view-pdf->png-converter-function
         #'doc-view-pdf->png-converter-ghostscript))
    (cl-letf (((symbol-function 'executable-find)
               (lambda (program)
                 (pcase program
                   ("gs" nil)
                   ("mudraw" nil)
                   ("pdftoppm" "/opt/homebrew/bin/pdftoppm")
                   (_ nil)))))
      (systemhalted/configure-doc-view-pdf-backend)
      (should (eq doc-view-pdf->png-converter-function
                  #'systemhalted/doc-view-pdf->png-converter-pdftoppm)))))

(ert-deftest systemhalted-test/doc-view-mode-p-recognizes-pdftoppm-backend ()
  "DocView availability checks should accept the custom pdftoppm backend."
  (let ((doc-view-ghostscript-program "gs")
        (doc-view-pdfdraw-program "mudraw"))
    (cl-letf (((symbol-function 'display-graphic-p)
               (lambda (&optional _frame) t))
              ((symbol-function 'image-type-available-p)
               (lambda (type) (eq type 'png)))
              ((symbol-function 'executable-find)
               (lambda (program)
                 (pcase program
                   ("gs" nil)
                   ("mudraw" nil)
                   ("pdftoppm" "/opt/homebrew/bin/pdftoppm")
                   (_ nil)))))
      (should (doc-view-mode-p 'pdf)))))

(ert-deftest systemhalted-test/doc-view-active-pages-falls-back-to-current-page ()
  "When DocView sees no visible active page, it should still prioritize the current page."
  (cl-letf (((symbol-function 'image-mode-window-get)
             (lambda (property &optional _window)
               (when (eq property 'page)
                 7))))
    (should (equal (systemhalted/doc-view-active-pages-advice (lambda () nil))
                   '(7)))))

(ert-deftest systemhalted-test/pdftoppm-converter-uses-doc-view-cache-names ()
  "The pdftoppm adapter should produce file names DocView expects."
  (let ((doc-view-resolution 150)
        started)
    (cl-letf (((symbol-function 'doc-view-start-process)
               (lambda (name program args callback)
                 (setq started (list name program args callback)))))
      (systemhalted/doc-view-pdf->png-converter-pdftoppm
       "/tmp/doc.pdf" "/tmp/page-3.png" 3 #'ignore)
      (should (equal (nth 0 started) "pdf->png"))
      (should (equal (nth 1 started) "pdftoppm"))
      (should (equal (nth 2 started)
                     '("-r" "150" "-png" "-f" "3" "-l" "3" "-singlefile"
                       "/tmp/doc.pdf" "/tmp/page-3"))))
    (cl-letf (((symbol-function 'doc-view-start-process)
               (lambda (name program args callback)
                 (setq started (list name program args callback)))))
      (systemhalted/doc-view-pdf->png-converter-pdftoppm
       "/tmp/doc.pdf" "/tmp/page-%d.png" nil #'ignore)
      (should (equal (nth 2 started)
                     '("-r" "150" "-png" "/tmp/doc.pdf" "/tmp/page"))))))

(ert-deftest systemhalted-test/pdftoppm-single-page-callback-refreshes-page-list ()
  "DocView's file list must be refreshed before the page callback runs."
  (let (started events)
    (cl-letf (((symbol-function 'doc-view-start-process)
               (lambda (_name _program _args callback)
                 (setq started callback)))
              ((symbol-function 'doc-view-display)
               (lambda (_buffer &optional _force) (push 'refresh events))))
      (systemhalted/doc-view-pdf->png-converter-pdftoppm
       "/tmp/doc.pdf" "/tmp/page-1.png" 1 (lambda () (push 'callback events)))
      (funcall started)
      (should (equal (nreverse events) '(refresh callback))))))

(ert-deftest systemhalted-test/doc-view-scrolling-continues-onto-next-page ()
  "Wheel scrolling past a page edge should advance to the next page."
  (require 'doc-view)
  (should (eq (default-value 'doc-view-continuous) t)))

(ert-deftest systemhalted-test/pdftoppm-whole-document-output-is-normalized ()
  "Whole-document pdftoppm output should be renamed to DocView's page names."
  (let ((dir (make-temp-file "systemhalted-pdftoppm" t)))
    (unwind-protect
        (let ((page1 (expand-file-name "page-001.png" dir))
              (page10 (expand-file-name "page-010.png" dir)))
          (write-region "" nil page1 nil 'silent)
          (write-region "" nil page10 nil 'silent)
          (systemhalted/normalize-pdftoppm-output-files
           (expand-file-name "page-%d.png" dir))
          (should (file-exists-p (expand-file-name "page-1.png" dir)))
          (should (file-exists-p (expand-file-name "page-10.png" dir)))
          (should-not (file-exists-p page1))
          (should-not (file-exists-p page10)))
      (delete-directory dir t))))

(ert-deftest systemhalted-test/open-pdf-file-falls-back-externally ()
  "When Emacs cannot render PDFs, the system opener should be used."
  (let (opened)
    (cl-letf (((symbol-function 'systemhalted/pdf-viewable-in-emacs-p)
               (lambda () nil))
              ((symbol-function 'systemhalted/open-file-externally)
               (lambda (file)
                 (setq opened file)
                 'external)))
      (should (eq (systemhalted/open-pdf-file "/tmp/test.pdf") 'external))
      (should (equal opened "/tmp/test.pdf")))))

(ert-deftest systemhalted-test/open-pdf-file-displays-before-doc-view ()
  "PDF buffers should be shown before DocView starts converting them."
  (let (calls)
    (cl-letf (((symbol-function 'systemhalted/pdf-viewable-in-emacs-p)
               (lambda () t))
              ((symbol-function 'find-file-noselect)
               (lambda (_file)
                 (get-buffer-create " *systemhalted-pdf*")))
              ((symbol-function 'pop-to-buffer-same-window)
               (lambda (_buffer)
                 (push 'pop calls)
                 (selected-window)))
              ((symbol-function 'doc-view-mode)
               (lambda ()
                 (push 'doc-view calls)))
              ((symbol-function 'set-buffer-modified-p)
               (lambda (&optional _arg)
                 (push 'clean calls))))
      (systemhalted/open-pdf-file "/tmp/test.pdf")
      (should (equal (nreverse calls) '(pop doc-view clean))))))

(ert-deftest systemhalted-test/show-pdf-buffer-in-emacs-handles-buffer-return ()
  "The display helper should tolerate `pop-to-buffer-same-window' returning a buffer."
  (let ((buffer (get-buffer-create " *systemhalted-pdf-display*"))
        calls)
    (cl-letf (((symbol-function 'pop-to-buffer-same-window)
               (lambda (_buffer)
                 (push 'pop calls)
                 buffer))
              ((symbol-function 'doc-view-mode)
               (lambda ()
                 (push 'doc-view calls)))
              ((symbol-function 'set-buffer-modified-p)
               (lambda (&optional _arg)
                 (push 'clean calls))))
      (systemhalted/show-pdf-buffer-in-emacs buffer)
      (should (equal (nreverse calls) '(pop doc-view clean))))))

(ert-deftest systemhalted-test/view-pdf-mime-delegates-through-temp-file ()
  "EWW PDF MIME handling should write a temp file and empty the source buffer."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert "PDFDATA")
    (let (opened written)
      (cl-letf (((symbol-function 'systemhalted/pdf-temp-file)
                 (lambda () "/tmp/eww-buffer.pdf"))
                ((symbol-function 'write-region)
                 (lambda (&rest args)
                   (setq written args)))
                ((symbol-function 'systemhalted/open-pdf-file)
                 (lambda (file)
                   (setq opened file))))
        (systemhalted/view-pdf-mime)
        (should written)
        (should (equal opened "/tmp/eww-buffer.pdf"))
        (should (= (buffer-size) 0))
        (should (= (point) (point-min)))))))

(ert-deftest systemhalted-test/config-commands-remain-bound ()
  "The literate config should remain directly reloadable and visitable."
  (should (fboundp 'systemhalted/config-reload))
  (should (fboundp 'systemhalted/config-visit))
  (should (eq (key-binding (kbd "C-c r")) #'systemhalted/config-reload))
  (should (eq (key-binding (kbd "C-c e")) #'systemhalted/config-visit)))

(ert-deftest systemhalted-test/emacs-lisp-blocks-declare-tangle-intent ()
  "Every Emacs Lisp source block must explicitly say whether it tangles.
This prevents a visually configured package from silently disappearing from
systemhalted.el because the block omitted its :tangle header argument."
  (with-temp-buffer
    (insert-file-contents systemhalted/config-file)
    (goto-char (point-min))
    (while (re-search-forward "^#\\+begin_src[ \t]+emacs-lisp\\(.*\\)$" nil t)
      (let ((arguments (match-string 1)))
        (should
         (string-match-p
          "[ \t]+:tangle[ \t]+\\(?:yes\\|no\\)\\(?:[ \t]\\|$\\)"
          arguments))))))

(ert-deftest systemhalted-test/generated-config-contains-core-packages ()
  "A tangle should contain the package forms that define the rewrite's core."
  (let ((generated
         (expand-file-name "systemhalted.el" systemhalted/config-directory)))
    (should (file-exists-p generated))
    (with-temp-buffer
      (insert-file-contents generated)
      (dolist (form '("(use-package vertico"
                      "(use-package marginalia"
                      "(use-package orderless"
                      "(use-package corfu"
                      "(use-package eglot"
                      "(use-package project"
                      "(use-package yasnippet"
                      "(use-package dashboard"
                      "(use-package ghostel"
                      "(use-package magit"
                      "(use-package wordwise"
                      "(use-package consult"))
        (goto-char (point-min))
        (should (search-forward form nil t))))))

(provide 'systemhalted-test)
;;; systemhalted-test.el ends here
