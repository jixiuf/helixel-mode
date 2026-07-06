;;; ert-summary.el --- AI-friendly ERT batch reporter  -*- lexical-binding: t; -*-

;; Usage: emacs --batch -l ert-summary.el -l test-files.el \
;;        --eval "(ert-run-tests-batch-summary 't)"

;;; Code:

(require 'ert)

(defun ert-run-tests-batch-summary (&optional selector)
  "Run ERT tests with SELECTOR, printing only failures and a summary line.
All `message' output is suppressed during the run.
Exits with code 1 if any test fails unexpectedly."
  (let ((inhibit-message t)
        (start-time (float-time)))
    (ert-run-tests
     (or selector 't)
     (lambda (event-type &rest rest)
       (pcase event-type
         ('run-started
          (let ((stats (car rest)))
            (princ (format "Running %d tests...\n"
                           (ert-stats-total stats)))))
         ('test-ended
          (let* ((test-def (cadr rest))
                 (result (ert-test-most-recent-result test-def)))
            (when (eq (type-of result) 'ert-test-failed)
              (let ((name (ert-test-name test-def))
                    (cond (ert-test-failed-condition result)))
                (princ (format "FAIL  %s\n" name))
                (when cond
                  (princ (format "      %s\n" cond)))))))
         ('run-ended
          (let* ((stats (car rest))
                 (total (ert-stats-total stats))
                 (unexp (ert-stats-completed-unexpected stats))
                 (passed (- total unexp))
                 (elapsed (- (float-time) start-time)))
            (if (> unexp 0)
                (princ (format "\nFAIL: %d/%d passed, %d failed (%.1fs)\n"
                               passed total unexp elapsed))
              (princ (format "OK:   %d/%d passed (%.1fs)\n"
                             passed total elapsed)))
            (when (> unexp 0)
              (kill-emacs 1)))))))))

(provide 'ert-summary)
;;; ert-summary.el ends here
