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
;; Every edit transaction has a repeat strategy: two functions
;; (advance, execute) that abstract how to move to the next target
;; and how to apply the edit.  The strategy pattern collapses the
;; previous 30-branch cond in `helixel-repeat-edit' into a clean
;; three-way dispatch (all-buffer / all-remaining / n-times).
;;
;; A repeat strategy is a pair (ADVANCE-FN . EXECUTE-FN):
;;   ADVANCE-FN: () → non-nil if advance succeeded, moves point.
;;               Returns nil at buffer edge or when no more targets.
;;   EXECUTE-FN: () → nil, executes the edit at the current position.
;;
;; The strategy is computed from the transaction (tx) by
;; `helixel--repeat-strategy', which dispatches on the operator
;; (chain vs non-chain) and selection kind (line, search, etc.).
;;
;; Modules defining new selection kinds embed :advance in the
;; `helixel-sel' struct at sel-create time, or add entries to
;; `helixel-repeat-advance-alist' as a compatibility fallback.

;;; Code:

(require 'helixel-data)
(require 'helixel-repeat)

;; ═══════════════════════════════════════════════════════════════════════
;; Prefix parsing
;; ═══════════════════════════════════════════════════════════════════════

(cl-defstruct helixel-repeat-prefix
  "Decoded dot-repeat prefix argument."
  mode      ;; :all-buffer | :all-dir | :n-times
  n         ;; integer count (≥1)
  reverse-p ;; boolean
  raw)      ;; original raw-prefix

(defun helixel--decode-repeat-prefix (raw-prefix)
  "Parse RAW-PREFIX into a `helixel-repeat-prefix' struct.
RAW-PREFIX is the value of `current-prefix-arg' in `helixel-repeat-edit'.

Semantics:
  \\[universal-argument] .         -> :all-buffer, forward
  \\[universal-argument] - .       -> :all-buffer, reverse
  0 .           → :all-dir, forward
  - .           → :n-times 1 (caller flips direction permanently, like N)
  -3 .          → :n-times 3 (caller flips direction permanently)
  3 .           → :n-times 3, forward
  \[universal-argument] -3 .      → :n-times 3, reverse (one-time; has C-u)
  \[universal-argument] 3 .       → :all-buffer + n=3 (treated as :all-buffer)

Note: Bare '-' (raw-prefix is the symbol \\='-) is detected by the caller
\(`helixel-repeat-edit') to permanently flip the direction in the stored
transaction, analogous to how `N' flips `helixel--repeat-dir' for search."
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
;; Strategy lookup
;; ═══════════════════════════════════════════════════════════════════════
;;
;; Returns a `helixel-repeat-action' for the given transaction.
;; The same strategy builder works for both chain and non-chain ops:
;; - Non-chain: reads sel from `helixel-edit-sel', advance tag from op registry
;; - Chain: reads sel from `helixel-edit-sel' (set from init-ctx at
;;   record time), advance tag derived from sel kind (op registry
;;   has nil for chain)

(defun helixel--repeat-strategy (tx &optional reverse-p)
  "Return a `helixel-repeat-action' for TX, optionally in REVERSE-P direction.
Works for both chain and non-chain transactions."
  (helixel--nonchain-strategy tx reverse-p))

(defun helixel--nonchain-strategy (tx &optional reverse-p)
  "Return a `helixel-repeat-action' for TX (chain or non-chain).
REVERSE-P flips the direction for search/line selections."
  (let* ((sel (helixel-edit-sel tx))
         (chain-p (eq (helixel-edit-op tx) 'chain))
         (kind (and sel (helixel-sel-get-kind sel)))
         (entry-kind (and sel (eq kind 'search)
                         (helixel-sel-search-entry-kind sel)))
         ;; Read advance from sel struct (embedded at sel-create time).
         ;; Fall back to alist for backward-compat (tests, third-party).
         (adv-fn (when sel
                   (or (helixel-sel-advance sel)
                       (cdr (assq kind helixel-repeat-advance-alist)))))
         (adv-tag (or (helixel-edit-op-advance (helixel-edit-op tx))
                      (and chain-p (and sel (helixel-sel-get-kind sel))))))
    ;; For reverse: flip the direction in the sel ctx for search/line
    (when (and reverse-p sel (memq kind '(search line)))
      (let ((current-dir (if (eq kind 'search)
                             (helixel-sel-search-dir sel)
                           (helixel-sel-line-dir sel))))
        (setq sel (helixel-sel-update-ctx sel :dir
                                          (helixel--flip-dir current-dir)))))
    (make-helixel-repeat-action
     :position-fn
     ;; Unified advance: 3 branches, kind-agnostic.
     ;; Branch 1: has advance-fn + advance-tag (non-entry-kind).
     ;;   The advance fn does everything — positions cursor AND
     ;;   creates the selection region.
     ;; Branch 2: any sel kind, no separate advance → recreate
     ;;   function handles both positioning and region creation.
     ;;   Catches errors to stop iteration at buffer edge.
     ;; Branch 3: no sel → one-shot (chain kmacro or no-op).
     (let ((called nil))
       (lambda ()
         (cond
          ;; Branch 1: non-chain, explicit advance function.
          ;; "Separate" adv-fns (line, search) only position cursor;
          ;; the strategy calls recreate to create the region.
          ;; "Inline" adv-fns (movement, textobj, find-char)
          ;; inherently create the region as part of their
          ;; positioning — skip the extra recreate to avoid
          ;; double-moving.  The :inline-advance flag in ctx
          ;; drives this distinction.
          ((and adv-fn adv-tag (not chain-p) (not entry-kind))
           (let ((tmp-tx (copy-helixel-edit tx)))
             (setf (helixel-edit-sel tmp-tx) sel)
             (when (funcall adv-fn tmp-tx adv-tag)
               (unless (helixel-sel-movement-inline-advance-p sel)
                 (helixel--recreate-selection sel))
               t)))

          ;; Branch 2: any sel → recreate handles everything.
          ;; Covers search (chain + non-chain), line, rect,
          ;; movement, textobj, insert-*, etc.
          (sel
           (if chain-p
               ;; Chain: use adv-fn for cursor positioning,
               ;; then replay kmacro keys.
               (when adv-fn
                 (let ((tmp-tx (copy-helixel-edit tx)))
                   (setf (helixel-edit-sel tmp-tx) sel)
                   (when (funcall adv-fn tmp-tx adv-tag)
                     (when (eq kind 'line) (end-of-line))
                     (when-let* ((move-keys (plist-get
                                              (helixel-edit-payload tx)
                                              :chain-move-keys)))
                       (execute-kbd-macro move-keys))
                     t)))
             ;; Non-chain: call recreate; error = no more targets.
             (condition-case nil
                 (progn (helixel--recreate-selection sel) t)
               (error nil))))

          ;; Branch 3: no sel — one-shot (chain kmacro or no-op).
          (t
           (if (eq (helixel-edit-op tx) 'chain)
               (unless called
                 (setq called t)
                 (when-let* ((move-keys (plist-get
                                          (helixel-edit-payload tx)
                                          :chain-move-keys)))
                   (execute-kbd-macro move-keys))
                 t)
             t)))))
     :execute-fn
     (lambda ()
       (helixel--execute-edit tx)))))

;; ═══════════════════════════════════════════════════════════════════════
;; Generic repeat loops
;; ═══════════════════════════════════════════════════════════════════════

(defun helixel--repeat-all-buffer (advance-fn execute-fn prefix)
  "Use ADVANCE-FN and EXECUTE-FN over entire buffer.
Starts from point-min or point-max depending on PREFIX direction."
  (save-excursion
    (goto-char (if (helixel-repeat-prefix-reverse-p prefix)
                   (point-max)
                 (point-min)))
    (let ((cnt 0))
      (while (funcall advance-fn)
        (cl-incf cnt)
        (funcall execute-fn))
      (helixel--repeat-echo cnt))))

(defun helixel--repeat-all-remaining (advance-fn execute-fn)
  "Use ADVANCE-FN and EXECUTE-FN over all remaining targets.
Direction is determined by the advance function."
  (let ((cnt 0))
    (while (funcall advance-fn)
      (cl-incf cnt)
      (funcall execute-fn))
    (helixel--repeat-echo cnt)))

(defun helixel--repeat-n (advance-fn execute-fn n)
  "Use ADVANCE-FN and EXECUTE-FN N times from current position.
Errors propagate to caller's `condition-case'."
  (dotimes (_ n)
    (unless (funcall advance-fn)
      (user-error "No more targets for dot-repeat"))
    (funcall execute-fn))
  (helixel--repeat-echo n))

;; ═══════════════════════════════════════════════════════════════════
;; RepeatAction — unified repeat descriptor (new, incremental adoption)
;; ═══════════════════════════════════════════════════════════════════

(cl-defstruct helixel-repeat-action
  "Self-contained repeat descriptor.
POSITION-FN: () → (BEG . END) or nil.  Find next target bounds.
EXECUTE-FN:  () → nil.  Apply edit at current position."
  (position-fn nil :read-only t)
  (execute-fn  nil :read-only t))

(defun helixel--repeat-all-remaining-action (action)
  "Repeat ACTION over all remaining targets.
Errors propagate to caller's `condition-case'."
  (let ((cnt 0)
        (pos-fn (helixel-repeat-action-position-fn action))
        (exec-fn (helixel-repeat-action-execute-fn action)))
    (while (funcall pos-fn)
      (cl-incf cnt)
      (funcall exec-fn))
    (helixel--repeat-echo cnt)))

(defun helixel--repeat-all-buffer-action (action prefix)
  "Repeat ACTION over entire buffer, using PREFIX for direction."
  (helixel--repeat-all-buffer
   (helixel-repeat-action-position-fn action)
   (helixel-repeat-action-execute-fn action)
   prefix))

(defun helixel--repeat-n-action (action n)
  "Repeat ACTION N times."
  (helixel--repeat-n
   (helixel-repeat-action-position-fn action)
   (helixel-repeat-action-execute-fn action)
   n))

;; ═══════════════════════════════════════════════════════════════════
;; Preview loops — position-fn only, no execute-fn (for `,`)
;; ═══════════════════════════════════════════════════════════════════

(defun helixel--repeat-all-remaining-preview (action)
  "Preview ACTION over all remaining targets (position-fn only).
Errors propagate to caller's `condition-case'."
  (let ((cnt 0)
        (pos-fn (helixel-repeat-action-position-fn action)))
    (while (funcall pos-fn)
      (cl-incf cnt))
    (helixel--repeat-echo cnt)))

(defun helixel--repeat-all-buffer-preview (action prefix)
  "Preview ACTION over entire buffer using PREFIX to determine direction."
  (goto-char (if (helixel-repeat-prefix-reverse-p prefix)
                 (point-max)
               (point-min)))
  (let ((cnt 0)
        (pos-fn (helixel-repeat-action-position-fn action)))
    (while (funcall pos-fn)
      (cl-incf cnt))
    (helixel--repeat-echo cnt)))

(defun helixel--repeat-n-preview (action n)
  "Preview ACTION N times.
Errors propagate to caller's `condition-case'."
  (let ((pos-fn (helixel-repeat-action-position-fn action)))
    (dotimes (_ n)
      (unless (funcall pos-fn)
        (user-error "No more targets for dot-repeat")))
    (helixel--repeat-echo n)))

(defun helixel--repeat-preview (action prefix)
  "Preview ACTION based on PREFIX mode (position-fn only, no execute-fn)."
  (pcase (helixel-repeat-prefix-mode prefix)
    (:all-buffer
     (helixel--repeat-all-buffer-preview action prefix))
    (:all-dir
     (helixel--repeat-all-remaining-preview action))
    (:n-times
     (helixel--repeat-n-preview action (helixel-repeat-prefix-n prefix)))))

(provide 'helixel-repeat-strategy)
;;; helixel-repeat-strategy.el ends here
