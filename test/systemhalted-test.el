;;; systemhalted-test.el --- Configuration regression tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'org)

(ert-deftest systemhalted/package-install-refreshes-and-retries-once ()
  (let ((calls 0)
        (refreshes 0)
        (systemhalted/package-install--refreshing nil)
        (descriptor
         (package-desc-create :name 'demo
                              :version '(1 0)
                              :summary "demo"
                              :reqs nil
                              :kind 'tar
                              :archive "melpa"))
        seen)
    (cl-letf (((symbol-function 'package-refresh-contents)
               (lambda () (setq refreshes (1+ refreshes)))))
      (should
       (eq 'installed
           (systemhalted/package-install--with-refresh
            (lambda (package &rest _args)
              (setq calls (1+ calls)
                    seen package)
              (if (= calls 1)
                  (error "stale archive")
                'installed))
            descriptor)))
      (should (= calls 2))
      (should (= refreshes 1))
      (should (eq seen 'demo)))))

(ert-deftest systemhalted/package-install-propagates-second-failure ()
  (let ((calls 0)
        (refreshes 0)
        (systemhalted/package-install--refreshing nil))
    (cl-letf (((symbol-function 'package-refresh-contents)
               (lambda () (setq refreshes (1+ refreshes)))))
      (should-error
       (systemhalted/package-install--with-refresh
        (lambda (&rest _args)
          (setq calls (1+ calls))
          (error "still broken"))
        'demo))
      (should (= calls 2))
      (should (= refreshes 1)))))

(ert-deftest systemhalted/config-asserts-recorded-use-package-errors ()
  (let ((systemhalted/use-package-errors '("broken package")))
    (should-error (systemhalted/config--assert-no-package-errors))))

(ert-deftest systemhalted/org-destination-validation ()
  (dolist (valid '("00-inbox" "20-personal/home" "30-learning/new section"))
    (should (equal valid (systemhalted/org--validate-destination valid))))
  (dolist (invalid '("" "/tmp" "../outside" "00-inbox/.."
                     "00-inbox/.hidden" "00-inbox/a/b"
                     "unknown/section" "20-personal/foo-attachments"
                     "20-personal/foo(Attachments)"))
    (should-error (systemhalted/org--validate-destination invalid)
                  :type 'user-error)))

(ert-deftest systemhalted/org-unique-file-respects-attachment-collisions ()
  (let ((dir (make-temp-file "organicely-unique-" t)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "note-attachments" dir))
          (should
           (string-suffix-p
            "note-2.org"
            (systemhalted/org-unique-file dir "note"))))
      (delete-directory dir t))))

(ert-deftest systemhalted/refile-rolls-back-when-attachments-fail ()
  (let* ((root (make-temp-file "organicely-refile-" t))
         (org-directory (file-name-as-directory root))
         (source-dir (expand-file-name "00-inbox" root))
         (target-dir (expand-file-name "20-personal/home" root))
         (source (expand-file-name "note.org" source-dir))
         (source-attachments
          (expand-file-name "note-attachments" source-dir))
         (target (expand-file-name "note.org" target-dir))
         (original-rename (symbol-function 'rename-file))
         buffer
         (rename-count 0))
    (unwind-protect
        (progn
          (make-directory source-attachments t)
          (make-directory target-dir t)
          (with-temp-file source
            (insert "#+TITLE: Note\n"))
          (setq buffer (find-file-noselect source))
          (with-current-buffer buffer
            (cl-letf (((symbol-function 'completing-read)
                       (lambda (&rest _args) "20-personal/home"))
                      ((symbol-function 'rename-file)
                       (lambda (&rest args)
                         (setq rename-count (1+ rename-count))
                         (if (= rename-count 2)
                             (error "attachment move failed")
                           (apply original-rename args)))))
              (should-error (systemhalted/refile-note)))
            (should (equal buffer-file-name source)))
          (should (file-exists-p source))
          (should (file-directory-p source-attachments))
          (should-not (file-exists-p target)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest systemhalted/project-discovery-skips-directory-symlinks ()
  (let* ((root (make-temp-file "project-discovery-" t))
         (child (expand-file-name "child" root))
         (loop (expand-file-name "loop" root))
         (checks 0))
    (unwind-protect
        (progn
          (make-directory child)
          (make-symbolic-link root loop)
          (cl-letf (((symbol-function 'projectile-project-p)
                     (lambda (_dir)
                       (setq checks (1+ checks))
                       nil)))
            (systemhalted/discover-projects root))
          (should (< checks 5)))
      (delete-directory root t))))

(ert-deftest systemhalted/project-discovery-tolerates-unreadable-directories ()
  (let ((root (make-temp-file "project-unreadable-" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'directory-files)
                   (lambda (&rest _args)
                     (signal 'file-error '("permission denied"))))
                  ((symbol-function 'message) #'ignore))
          (should-not (systemhalted/discover-projects root)))
      (delete-directory root t))))

(ert-deftest systemhalted/org-buffers-default-links-to-eww ()
  (with-temp-buffer
    (org-mode)
    (should (local-variable-p 'browse-url-browser-function))
    (should (eq browse-url-browser-function #'eww-browse-url)))
  (should-not (eq (default-value 'browse-url-browser-function)
                  #'eww-browse-url)))

(ert-deftest systemhalted/org-open-in-system-browser-uses-secondary ()
  (let (opened)
    (with-temp-buffer
      (org-mode)
      (insert "[[https://example.com/page]]")
      (goto-char 3)
      (let ((browse-url-secondary-browser-function
             (lambda (url &rest _args) (setq opened url))))
        (systemhalted/org-open-in-system-browser)))
    (should (equal opened "https://example.com/page"))))

(ert-deftest systemhalted/lombok-selects-newest-main-jar-semantically ()
  (let ((jars '("/cache/1.18.9/lombok-1.18.9.jar"
                "/cache/1.18.42/lombok-1.18.42-sources.jar"
                "/cache/1.18.42/lombok-1.18.42.jar"
                "/cache/1.18.50/lombok-1.18.50-javadoc.jar")))
    (cl-letf (((symbol-function 'file-expand-wildcards)
               (lambda (&rest _args) jars)))
      (should
       (equal "/cache/1.18.42/lombok-1.18.42.jar"
              (systemhalted/lombok-jar-path))))))

(provide 'systemhalted-test)
;;; systemhalted-test.el ends here
