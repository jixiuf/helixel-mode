;;; helixel-repeat-strategy.el --- Repeat strategy engine -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

;; Author: jixiuf
;; Keywords: convenience

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;;; Commentary:
;;
;; Repeat strategy engine: the `helixel-repeat-strategy' struct, the
;; default strategy builder, the dispatcher (`helixel--build-strategy')
;; that delegates to op-registered builders, and the generic
;; advance / apply / preview loops invoked by `.' and `,'.
;;
;; Pure code — knows nothing about specific kinds beyond what the
;; kind registry exposes.  Per-kind line / search / textobj behaviour
;; lives in the kind registry slots `:all-buffer-fn', `:all-dir-fn'.
;;

;;; Code:

(require 'cl-lib)
(require 'helixel-core)

(defvar helixel--repeat-permanent-flip)     ; helixel-repeat.el

;; ── Struct ──

(cl-defstruct helixel-repeat-strategy
  "Self-contained repeat strategy.
ADVANCE:      fn(edit) → t|nil — move to next target, create region.
APPLY:        fn(edit) → nil   — execute edit at current position.
RESET:        fn(edit) → nil   — return to start position (all-buffer).
ALL-BUFFER-FN: fn(edit prefix) → nil — custom all-buffer scan.
ALL-DIR-FN:    fn(edit) → nil — custom all-dir scan, or nil.
  When non-nil, `helixel--repeat-all-dir' delegates to this
  instead of the generic advance/apply loop."
  (advance nil :read-only t)
  (apply   nil :read-only t)
  (reset   nil :read-only t)
  (all-buffer-fn nil :read-only t)
  (all-dir-fn nil :read-only t))

;; ── Direction flip ──

(defun helixel--maybe-flip-dir-edit (edit reverse-p)
  "Return EDIT with :dir flipped per the sel kind's :flip-dir-fn.
When REVERSE-P or `helixel--repeat-permanent-flip' is non-nil and
the selection kind has a `:flip-dir-fn' registered, build a copy
of EDIT whose sel has been flipped by that function.  Otherwise
return EDIT unchanged."
  (let* ((sel (helixel-event-sel edit))
         (kind (and sel (helixel-sel-kind sel)))
         (flip-fn (and kind (helixel--kind-flip-dir-fn kind)))
         (effective-reverse (or reverse-p helixel--repeat-permanent-flip)))
    (if (and effective-reverse sel flip-fn)
        (let* ((reversed-sel (funcall flip-fn sel))
               (new-edit (helixel-event-copy edit)))
          (setf (helixel-event-sel new-edit) reversed-sel)
          new-edit)
      edit)))

;; ── Strategy builder dispatcher ──

(defun helixel--build-strategy (edit &optional reverse-p)
  "Return a `helixel-repeat-strategy' for EDIT.
If the operator has a :strategy-builder in the op registry, use it.
Otherwise fall back to `helixel--default-strategy-builder'.
If REVERSE-P is non-nil, flip :dir in the selection ctx
for line/search kinds."
  (let* ((op (helixel-event-op edit))
         (custom-builder (helixel--op-strategy-builder op)))
    (if custom-builder
        (funcall custom-builder edit reverse-p)
      (helixel--default-strategy-builder edit reverse-p))))

;; ── Default builder ──

(defun helixel--default-strategy-builder (edit &optional reverse-p)
  "Build a default repeat strategy for EDIT.
If REVERSE-P is non-nil, flip :dir for line/search kinds.
Looks up the advance function from the kind registry.
When the operator has no :repeat-advance tag, the advance
just recreates the selection at the current position
\(no actual advancing — e.g. kill auto-moves point)."
  (let* ((sel (helixel-event-sel edit))
         (kind (and sel (helixel-sel-kind sel)))
         (op (helixel-event-op edit))
         (adv-tag (helixel--op-advance op))
         (effective-edit (helixel--maybe-flip-dir-edit edit reverse-p))
         (advance-fn
          (cond
           ;; Advance tag present: use the kind's advance function
           ((and adv-tag (helixel--kind-advance kind))
            (helixel--kind-advance kind))
           ;; No advance tag (e.g. kill): just recreate at point
           ;; Catches errors = no more targets at buffer edge
           (t
            (lambda (ed)
              (condition-case nil
                  (progn
                    (helixel-sel-call-recreate
                     (helixel-event-sel ed))
                    t)
                (error nil)))))))
    (make-helixel-repeat-strategy
     :advance (lambda (_ed) (funcall advance-fn effective-edit))
     :apply   (lambda (_ed) (helixel--execute-edit effective-edit))
     :reset   (lambda (_ed)
                (when-let* ((m (car (helixel-event-mark-region
                                       effective-edit))))
                  (goto-char (marker-position m))))
     :all-buffer-fn (helixel--kind-all-buffer-fn kind)
     :all-dir-fn (helixel--kind-all-dir-fn kind))))

;; ── Generic repeat loops ──

(defun helixel--repeat-all-buffer (strategy edit prefix)
  "Use STRATEGY over the entire buffer from EDIT.
If STRATEGY has a custom `all-buffer-fn', delegate to it.
Otherwise: reset to start, then advance+apply from point-min
\(or point-max if PREFIX is reverse)."
  (if-let* ((custom-fn (helixel-repeat-strategy-all-buffer-fn strategy)))
      (funcall custom-fn edit prefix)
    (funcall (helixel-repeat-strategy-reset strategy) edit)
    (save-excursion
      (goto-char (if (helixel-repeat-prefix-reverse-p prefix)
                     (point-max)
                   (point-min)))
      (let ((cnt 0))
        (while (funcall (helixel-repeat-strategy-advance strategy) edit)
          (cl-incf cnt)
          (funcall (helixel-repeat-strategy-apply strategy) edit))
        (helixel--repeat-echo cnt)))))

(defun helixel--repeat-all-dir (strategy edit)
  "Use STRATEGY on EDIT over all remaining targets from current position.
If STRATEGY has a custom `all-dir-fn', delegate to it."
  (if-let* ((custom-fn (helixel-repeat-strategy-all-dir-fn strategy)))
      (funcall custom-fn edit)
    (let ((cnt 0))
      (while (funcall (helixel-repeat-strategy-advance strategy) edit)
        (cl-incf cnt)
        (funcall (helixel-repeat-strategy-apply strategy) edit))
      (helixel--repeat-echo cnt))))

(defun helixel--repeat-n (strategy edit n)
  "Use STRATEGY on EDIT N times from current position."
  (dotimes (_ n)
    (unless (funcall (helixel-repeat-strategy-advance strategy) edit)
      (user-error "No more targets for dot-repeat"))
    (funcall (helixel-repeat-strategy-apply strategy) edit))
  (helixel--repeat-echo n))

(defun helixel--repeat-preview (strategy edit mode n &optional reverse-p)
  "Preview STRATEGY over EDIT — advance only, no apply.
MODE is :all-buffer, :all-dir, or :n-times.
N is the repeat count for :n-times mode.
When REVERSE-P is non-nil, for :all-buffer start from `point-max'
instead of `point-min' so backward scans work correctly.
For :all-dir and :n-times, the direction is already flipped in
the strategy via `helixel--build-strategy'."
  (pcase mode
    (:all-buffer
     (funcall (helixel-repeat-strategy-reset strategy) edit)
     (goto-char (if reverse-p (point-max) (point-min)))
     (let ((cnt 0))
       (while (funcall (helixel-repeat-strategy-advance strategy) edit)
         (cl-incf cnt))
       (helixel--repeat-echo cnt)))
    (:all-dir
     (let ((cnt 0))
       (while (funcall (helixel-repeat-strategy-advance strategy) edit)
         (cl-incf cnt))
       (helixel--repeat-echo cnt)))
    (:n-times
     (dotimes (_ n)
       (unless (funcall (helixel-repeat-strategy-advance strategy) edit)
         (user-error "No more targets for dot-repeat")))
     (helixel--repeat-echo n))))

(provide 'helixel-repeat-strategy)
;;; helixel-repeat-strategy.el ends here
