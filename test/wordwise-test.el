;;; wordwise-test.el --- Tests for Wordwise -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'savehist)

(defvar systemhalted/wordwise-test-cache nil)

(defmacro systemhalted/wordwise-test--with-state (&rest body)
  "Run BODY with isolated Wordwise cache and request state."
  (declare (indent 0) (debug t))
  `(let ((systemhalted/wordwise-cache (make-hash-table :test #'equal))
         (systemhalted/wordwise--process nil)
         (systemhalted/wordwise--connection-ready nil)
         (systemhalted/wordwise--wire-data "")
         (systemhalted/wordwise--queue nil)
         (systemhalted/wordwise--pending (make-hash-table :test #'equal))
         (systemhalted/wordwise--current-word nil)
         (systemhalted/wordwise--response "")
         (systemhalted/wordwise--request-timer nil)
         (systemhalted/wordwise--retry-timer nil)
         (systemhalted/wordwise--retry-at nil)
         (systemhalted/wordwise--failure-cache
          (make-hash-table :test #'equal))
         (systemhalted/wordwise--failure-retry-timer nil)
         (systemhalted/wordwise--last-network-error nil))
     (unwind-protect
         (progn ,@body)
       (dolist (timer (list systemhalted/wordwise--request-timer
                            systemhalted/wordwise--retry-timer
                            systemhalted/wordwise--failure-retry-timer))
         (when (timerp timer)
           (cancel-timer timer)))
       (when (processp systemhalted/wordwise--process)
         (set-process-sentinel systemhalted/wordwise--process #'ignore)
         (when (process-live-p systemhalted/wordwise--process)
           (delete-process systemhalted/wordwise--process))))))

(ert-deftest systemhalted/wordwise-response-status-waits-for-terminal-line ()
  (should-not
   (systemhalted/wordwise--response-status
    "150 1 definitions retrieved\r\n151 word db description\r\n"))
  (should
   (eq 'complete
       (systemhalted/wordwise--response-status
        "150 1 definitions retrieved\r\n.\r\n250 ok\r\n")))
  (should
   (eq 'missing
       (systemhalted/wordwise--response-status "552 no match\r\n")))
  (should
   (eq 'error
       (systemhalted/wordwise--response-status "550 invalid database\r\n"))))

(ert-deftest systemhalted/wordwise-definition-from-response-extracts-first-sense ()
  (should
   (equal
    "Having keen insight."
    (systemhalted/wordwise--definition-from-response
     (concat "150 1 definitions retrieved\r\n"
             "151 perspicacious db description\r\n"
             "  1. Having keen insight.\r\n"
             ".\r\n250 ok\r\n")))))

(ert-deftest systemhalted/wordwise-queue-deduplicates-words-and-buffers ()
  (systemhalted/wordwise-test--with-state
    (let ((first (generate-new-buffer " *wordwise-first*"))
          (second (generate-new-buffer " *wordwise-second*")))
      (unwind-protect
          (cl-letf (((symbol-function 'systemhalted/wordwise--pump) #'ignore))
            (systemhalted/wordwise--queue-word "perspicacious" first)
            (systemhalted/wordwise--queue-word "perspicacious" first)
            (systemhalted/wordwise--queue-word "perspicacious" second)
            (should (equal systemhalted/wordwise--queue '("perspicacious")))
            (should (= 2 (length (gethash "perspicacious"
                                         systemhalted/wordwise--pending))))
            (puthash "cached" "already known" systemhalted/wordwise-cache)
            (systemhalted/wordwise--queue-word "cached" first)
            (should (equal systemhalted/wordwise--queue '("perspicacious"))))
        (kill-buffer first)
        (kill-buffer second)))))

(ert-deftest systemhalted/wordwise-filter-handles-chunked-success ()
  (systemhalted/wordwise-test--with-state
    (let ((proc (make-pipe-process :name "wordwise-test" :noquery t)))
      (unwind-protect
          (progn
            (setq systemhalted/wordwise--process proc
                  systemhalted/wordwise--connection-ready t
                  systemhalted/wordwise--current-word "perspicacious")
            (puthash "perspicacious" (list (current-buffer))
                     systemhalted/wordwise--pending)
            (cl-letf (((symbol-function 'systemhalted/wordwise--pump) #'ignore)
                      ((symbol-function 'systemhalted/wordwise--schedule-scan)
                       #'ignore))
              (systemhalted/wordwise--process-filter
               proc
               (concat "150 1 definitions retrieved\r\n"
                       "151 perspicacious db description\r\n"
                       "  1. Having keen insight.\r\n"))
              (should (equal systemhalted/wordwise--current-word
                             "perspicacious"))
              (systemhalted/wordwise--process-filter proc ".\r\n250 ok\r\n")
              (should-not systemhalted/wordwise--current-word)
              (should (equal (gethash "perspicacious"
                                      systemhalted/wordwise-cache)
                             "Having keen insight."))))
        (when (process-live-p proc)
          (delete-process proc))))))

(ert-deftest systemhalted/wordwise-completion-persists-missing-separately ()
  (systemhalted/wordwise-test--with-state
    (setq systemhalted/wordwise--current-word "neologism")
    (puthash "neologism" (list (current-buffer))
             systemhalted/wordwise--pending)
    (cl-letf (((symbol-function 'systemhalted/wordwise--pump) #'ignore)
              ((symbol-function 'systemhalted/wordwise--schedule-scan) #'ignore))
      (systemhalted/wordwise--complete-current 'missing))
    (should (eq 'missing (gethash "neologism" systemhalted/wordwise-cache)))
    (should (eq 'miss (gethash "neologism"
                               systemhalted/wordwise--pending 'miss)))))

(ert-deftest systemhalted/wordwise-scan-queues-cold-and-renders-warm-words ()
  (systemhalted/wordwise-test--with-state
    (with-temp-buffer
      (fundamental-mode)
      (insert "perspicacious")
      (let ((systemhalted/wordwise-allowed-modes '(fundamental-mode))
            (systemhalted/wordwise-common-words
             (make-hash-table :test #'equal))
            (font-lock-defaults nil)
            queued
            rendered)
        (cl-letf (((symbol-function 'systemhalted/wordwise--in-prose-p)
                   (lambda (_pos) t))
                  ((symbol-function 'systemhalted/wordwise--queue-word)
                   (lambda (word _buffer) (push word queued)))
                  ((symbol-function 'systemhalted/wordwise--make-overlay)
                   (lambda (_beg _end hint &optional _window)
                     (push hint rendered))))
          (systemhalted/wordwise--scan-region (point-min) (point-max))
          (should (equal queued '("perspicacious")))
          (should-not rendered)
          (setq queued nil)
          (puthash "perspicacious" "Having keen insight."
                   systemhalted/wordwise-cache)
          (systemhalted/wordwise--scan-region (point-min) (point-max))
          (should-not queued)
          (should (equal rendered '("Having keen insight."))))))))

(ert-deftest systemhalted/wordwise-scroll-hook-only-schedules-work ()
  (let ((buf (generate-new-buffer " *wordwise-scroll*"))
        scheduled)
    (unwind-protect
        (save-window-excursion
          (switch-to-buffer buf)
          (setq-local systemhalted/wordwise-mode t)
          (cl-letf (((symbol-function 'systemhalted/wordwise--schedule-scan)
                     (lambda (buffer &optional _delay)
                       (setq scheduled buffer)))
                    ((symbol-function 'window-end)
                     (lambda (&rest _args)
                       (ert-fail "scroll hook read window-end during redisplay"))))
            (systemhalted/wordwise--on-scroll (selected-window) nil)
            (should (eq scheduled buf))))
      (kill-buffer buf))))

(ert-deftest systemhalted/wordwise-cache-round-trips-through-savehist ()
  (let ((test-file (make-temp-file "wordwise-savehist-test-"))
        (systemhalted/wordwise-test-cache
         (let ((table (make-hash-table :test #'equal)))
           (puthash "perspicacious" "Having keen insight." table)
           (puthash "unlisted" 'missing table)
           table)))
    (unwind-protect
        (let ((savehist-file test-file)
              (savehist-additional-variables
               '(systemhalted/wordwise-test-cache)))
          (savehist-save)
          (setq systemhalted/wordwise-test-cache nil)
          (load test-file nil t t)
          (should (hash-table-p systemhalted/wordwise-test-cache))
          (should (equal "Having keen insight."
                         (gethash "perspicacious"
                                  systemhalted/wordwise-test-cache)))
          (should (eq 'missing
                      (gethash "unlisted"
                               systemhalted/wordwise-test-cache))))
      (delete-file test-file))))

(ert-deftest systemhalted/wordwise-completion-advances-the-queue ()
  (systemhalted/wordwise-test--with-state
    (let ((proc (make-pipe-process :name "wordwise-pump-test" :noquery t))
          sent)
      (unwind-protect
          (progn
            (setq systemhalted/wordwise--process proc
                  systemhalted/wordwise--connection-ready t
                  systemhalted/wordwise--current-word "first"
                  systemhalted/wordwise--queue '("second"))
            (puthash "first" (list (current-buffer))
                     systemhalted/wordwise--pending)
            (puthash "second" (list (current-buffer))
                     systemhalted/wordwise--pending)
            (cl-letf (((symbol-function 'systemhalted/wordwise--schedule-scan)
                       #'ignore)
                      ((symbol-function 'process-send-string)
                       (lambda (_process string) (setq sent string)))
                      ((symbol-function 'run-at-time)
                       (lambda (&rest _args) nil)))
              (systemhalted/wordwise--complete-current "first definition")
              (should (equal systemhalted/wordwise--current-word "second"))
              (should (equal sent "DEFINE * second\r\n"))
              (should (equal (gethash "first" systemhalted/wordwise-cache)
                             "first definition"))))
        (when (process-live-p proc)
          (delete-process proc))))))

(ert-deftest systemhalted/wordwise-timeout-requeues-and-backs-off ()
  (systemhalted/wordwise-test--with-state
    (let (retry-scheduled)
      (setq systemhalted/wordwise--current-word "perspicacious")
      (puthash "perspicacious" (list (current-buffer))
               systemhalted/wordwise--pending)
      (cl-letf (((symbol-function 'systemhalted/wordwise--close-process)
                 #'ignore)
                ((symbol-function 'systemhalted/wordwise--schedule-network-retry)
                 (lambda () (setq retry-scheduled t)))
                ((symbol-function 'message) #'ignore))
        (systemhalted/wordwise--request-timed-out "perspicacious"))
      (should-not systemhalted/wordwise--current-word)
      (should (equal systemhalted/wordwise--queue '("perspicacious")))
      (should (> systemhalted/wordwise--retry-at (float-time)))
      (should retry-scheduled))))

(provide 'wordwise-test)
;;; wordwise-test.el ends here
