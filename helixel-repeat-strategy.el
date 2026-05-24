;;; helixel-repeat-strategy.el --- Repeat strategy protocol -*- lexical-binding: t; -*-

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

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Repeat strategy protocol for helixel-mode dot-repeat (`.`).
;;
;; Every edit transaction has a repeat strategy: three functions
;; (advance, apply, reset) that abstract how to:
;;   - advance: move to the next target and create the selection region
;;   - apply:   execute the edit at the current position
;;   - reset:   return to the starting position (for all-buffer scans)
;;
;; The strategy is computed by `helixel--build-strategy', which
;; dispatches on the operator's :strategy-builder (e.g. chain) or
;; falls back to the default builder based on the selection kind.
;;
;; Modules define advance functions and register them in the
;; kind registry (`helixel-register-kind') so the default builder
;; can look them up without kind-specific cond branches.

;;; Code:

(require 'cl-lib)
(require 'helixel-data)

(defvar helixel--repeat-permanent-flip)
(declare-function helixel--repeat-echo "helixel-repeat")
(declare-function helixel--execute-edit "helixel-repeat")
(declare-function helixel--flip-dir "helixel-repeat")

;; ═══════════════════════════════════════════════════════════════════════
;; Prefix parsing
;; ═══════════════════════════════════════════════════════════════════════

(cl-defstruct helixel-repeat-prefix
  "Decoded dot-repeat prefix argument."
  mode      ;; :all-buffer | :all-dir | :n-times
  n         ;; integer count (>= 1)
  reverse-p ;; boolean
  raw)      ;; original raw-prefix

(defun helixel--decode-repeat-prefix (raw-prefix)
  "Parse RAW-PREFIX into a `helixel-repeat-prefix' struct.

Semantics:
  \\[universal-argument] .    → :all-buffer, forward
  \\[universal-argument] - .  → :all-buffer, reverse
  0 .           → :all-dir, forward
  - .           → :n-times 1 (caller flips direction permanently)
  -3 .          → :n-times 3 (caller flips direction permanently)
  3 .           → :n-times 3, forward
  \\[universal-argument] -3 . → :n-times 3, reverse (one-time)
  \\[universal-argument] 3 .  → :all-buffer (n=3 ignored)

Bare '-' (raw-prefix = symbol \\='-) is detected by the caller
to permanently flip the stored direction (like N for search)."
  (let* ((all-buffer-p (consp raw-prefix))
         (all-dir-p (and (integerp raw-prefix) (eql raw-prefix 0)))
         (n (cond ((not raw-prefix) 1)
                  ((consp raw-prefix)
                   (abs (prefix-numeric-value raw-prefix)))
                  ((integerp raw-prefix) (abs raw-prefix))
                  (t 1)))
         (reverse-p (and (consp raw-prefix)
                        (< (prefix-numeric-value raw-prefix) 0)))
         (mode (cond (all-buffer-p :all-buffer)
                     (all-dir-p    :all-dir)
                     (t            :n-times))))
    (make-helixel-repeat-prefix
     :mode mode :n n :reverse-p reverse-p :raw raw-prefix)))


;; ═══════════════════════════════════════════════════════════════════════
;; Repeat strategy struct
;; ═══════════════════════════════════════════════════════════════════════

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


;; ═══════════════════════════════════════════════════════════════════════
;; Strategy builder — dispatches on op
;; ═══════════════════════════════════════════════════════════════════════

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


;; ═══════════════════════════════════════════════════════════════════════
;; Default strategy builder — selection-kind driven
;; ═══════════════════════════════════════════════════════════════════════

(defun helixel--default-strategy-builder (edit &optional reverse-p)
  "Build a default repeat strategy for EDIT.
If REVERSE-P is non-nil, flip :dir for line/search kinds.
Looks up the advance function from the kind registry.
When the operator has no :repeat-advance tag, the advance
just recreates the selection at the current position
\(no actual advancing — e.g. kill auto-moves point)."
  (let* ((sel (helixel-event-sel edit))
         (kind (and sel (helixel-sel-get-kind sel)))
         (op (helixel-event-op edit))
         (adv-tag (helixel--op-advance op))
         ;; Permanent flip (via `-.'): checked alongside one-time reverse-p
         (effective-reverse (or reverse-p helixel--repeat-permanent-flip))
         (reversed-edit
          ;; When effective-reverse: create edit copy with flipped :dir
          (when (and effective-reverse (memq kind '(line search)))
            (let* ((orig-sel (helixel-event-sel edit))
                   (current-dir (if (eq kind 'search)
                                    (helixel-sel-search-dir orig-sel)
                                  (helixel-sel-line-dir orig-sel)))
                   (reversed-sel (helixel-sel-update-ctx
                                  orig-sel :dir
                                  (helixel--flip-dir current-dir)))
                   (new-edit (helixel--copy-tx edit)))
              (setf (helixel-event-sel new-edit) reversed-sel)
              new-edit)))
         (effective-edit (or reversed-edit edit))
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
                (when-let* ((m (helixel-event-marker effective-edit)))
                  (goto-char (marker-position m))))
     :all-buffer-fn (helixel--kind-all-buffer-fn kind)
     :all-dir-fn (helixel--kind-all-dir-fn kind))))


;; ═══════════════════════════════════════════════════════════════════════
;; Generic repeat loops
;; ═══════════════════════════════════════════════════════════════════════

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

(defun helixel--repeat-preview (strategy edit mode n)
  "Preview STRATEGY over EDIT — advance only, no apply.
MODE is :all-buffer, :all-dir, or :n-times.
N is the repeat count for :n-times mode."
  (pcase mode
    (:all-buffer
     (funcall (helixel-repeat-strategy-reset strategy) edit)
     (goto-char (point-min))
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
