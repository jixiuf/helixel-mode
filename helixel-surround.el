;;; helixel-surround.el --- Surround operations  -*- lexical-binding: t; -*-

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
;; Surround operations for Helixel.
;;
;; Keybindings (under `helixel-textobj-map', i.e. `m' prefix):
;;   ms  — helixel-surround-add     — wrap selection with delimiter pair
;;   mt  — helixel-surround-add-tag — wrap selection with XML tag
;;   md  — helixel-surround-delete  — delete surrounding delimiters
;;   mr  — helixel-surround-replace — replace surrounding delimiter pair
;;
;; `ms' reads a character and looks it up first in
;; `helixel-surround-block-alist' (per-mode string pairs like
;; #+begin_src/#+end_src), then in `helixel--surround-pairs' (char pairs
;; like () [] {} <> and quotes).  Block pairs get newlines around the
;; content.  `mt' reads a tag name string.
;;
;; `md' and `mr' read the delimiter info from `helixel--pending-sel'
;; (set by the textobj selection command like mi(, ma[, mi t, mi c).
;; No extra input needed for `md' — just select a text object then press `md'.
;; `mr' prompts per type:
;;   pair/quote: read-char
;;   tag:        read-string "Tag: "
;;   block/regex: read-char (looks up block-alist + char-pairs)
;;
;; After `ms' or `mr', the new region stays selected and
;; `helixel--pending-sel' is updated so `md' and `mr' chain immediately.

;;; Code:

(require 'cl-lib)
(require 'helixel-core)
(require 'helixel-ring)                 ; helixel--tracking-open, live-edit-set
(require 'helixel-repeat)               ; for helixel--record-action
(require 'helixel-textobj)

(defvar helixel--surround-pairs)
(defvar helixel-textobj-after-select-functions)
(defvar helixel-textobj-inner-map)
(defvar helixel-textobj-outer-map)

(defvar helixel--pending-surround-op nil
  "If non-nil, a thunk to execute after the next textobj selection.
Bound by `helixel-surround-delete' / `helixel-surround-replace' when
the selection lacks surround info.  Cleared after execution.")

;; ============================================================================
;; Block alist — per-mode string-based surround pairs
;; ============================================================================

(defcustom helixel-surround-block-alist
  '((org-mode
     (?s . ("#+begin_src " . "#+end_src"))
     (?e . ("#+begin_example " . "#+end_example"))
     (?q . ("#+begin_quote " . "#+end_quote"))
     (?c . ("#+begin_center " . "#+end_center"))
     (?v . ("#+begin_verse " . "#+end_verse")))
    (markdown-mode
     (?` . ("```" . "```")))
    (gfm-mode
     (?` . ("```" . "```"))))
  "Alist mapping major modes to block surround pairs.
Each entry is (MODE (CHAR . (OPEN-STRING . CLOSE-STRING)) ...)."
  :type '(alist :key-type symbol
                :value-type
                (repeat (cons (character :tag "Key")
                              (cons (string :tag "Open")
                                    (string :tag "Close")))))
  :group 'helixel)

;; ============================================================================
;; Prompt helpers
;; ============================================================================

(defun helixel--surround-available-keys ()
  "Return a list of strings describing available surround keys."
  (let* ((seen nil)
         (result nil))
    (dolist (e helixel--surround-pairs)
      (let ((key (car e)))
        (when (and (characterp key)
                   (memq key '(?\( ?\[ ?\{ ?\< ?\" ?\' ?\`)))
          (let ((key-str (format "%c" key)))
            (unless (member key-str seen)
              (push key-str seen)
              (push (concat (propertize key-str 'face 'font-lock-keyword-face)
                            (format ":%c" (cdr e)))
                    result))))))
    (when-let* ((mode-entry (cl-find-if
                             (lambda (e) (derived-mode-p (car e)))
                             helixel-surround-block-alist)))
      (dolist (e (cdr mode-entry))
        (let* ((key (car e))
               (label (car (split-string (cadr e))))
               (label (replace-regexp-in-string "\\`#\\+begin_" "" label))
               (label (replace-regexp-in-string "\\`#\\+end_" "" label)))
          (push (concat (propertize (format "%c" key)
                                     'face 'font-lock-keyword-face)
                            (format ":%s" label))
                result))))
    (nreverse result)))

(defun helixel--surround-prompt (prefix)
  "Format prompt showing available surround keys for PREFIX."
  (let ((keys (helixel--surround-available-keys)))
    (format "%s %s"
            (propertize prefix 'face 'font-lock-type-face)
            (string-join keys " "))))

;; ============================================================================
;; Lookup helpers
;; ============================================================================

(defun helixel--surround-block-lookup (char)
  "Look up CHAR in `helixel-surround-block-alist' for current mode.
Returns (OPEN-STRING . CLOSE-STRING) or nil."
  (let ((mode-entries (cl-find-if (lambda (e) (derived-mode-p (car e)))
                                  helixel-surround-block-alist)))
    (when-let* ((entry (and mode-entries (assoc char (cdr mode-entries)))))
      (cdr entry))))

(defun helixel--surround-lookup (char)
  "Look up CHAR in block alist then in char-pairs.
Returns (OPEN . CLOSE) where each is a char or string, or nil."
  (or (helixel--surround-block-lookup char)
      (assoc char helixel--surround-pairs)))

(defun helixel--surround-lookup-delimiter (char)
  "Look up CHAR and return a helixel-delimiter plist, or nil."
  (if-let* ((block (helixel--surround-block-lookup char)))
      (helixel--make-block-delimiter (car block) (cdr block))
    (when-let* ((pair (assoc char helixel--surround-pairs)))
      (helixel--make-pair-delimiter (car pair) (cdr pair)))))

;; ============================================================================
;; Core: surround-add (wrap region)
;; ============================================================================

(defun helixel--surround-add (open close)
  "Wrap the active region with OPEN and CLOSE."
  (let ((beg (region-beginning))
        (end (region-end))
        (block-p (and (not (characterp open)) (not (characterp close))))
        (open-len (if (characterp open) 1 (length open)))
        (close-len (if (characterp close) 1 (length close))))
    (goto-char end)
    (when block-p (insert "\n"))
    (insert close)
    (goto-char beg)
    (insert open)
    (when block-p (insert "\n"))
    (push-mark beg nil t)
    (goto-char (+ end open-len close-len (if block-p 2 0)))))

(defun helixel--surround-add-tag (tag-name)
  "Wrap the active region with XML TAG-NAME."
  (let* ((beg (region-beginning))
         (end (region-end))
         (open-tag (format "<%s>" tag-name))
         (close-tag (format "</%s>" tag-name))
         (nl-before (not (eq (char-before end) ?\n)))
         (nl-after (not (eq (char-after beg) ?\n))))
    (goto-char end)
    (when nl-before (insert "\n"))
    (insert close-tag)
    (goto-char beg)
    (insert open-tag)
    (when nl-after (insert "\n"))
    (push-mark beg nil t)
    (goto-char (+ end (length open-tag) (length close-tag)
                  (if nl-before 1 0) (if nl-after 1 0)))))

;; ============================================================================
;; Core: surround-delete (unified)
;; ============================================================================

(defun helixel--surround-delete-delimiter (d)
  "Delete the delimiters described by D.
Returns position where point should be placed after deletion."
  (pcase-let* ((`(,ob ,oe ,cb ,ce)
                (helixel-delimiter-bounds-flat d)))
    (when (helixel-delimiter-nl-p d)
      (pcase-let ((`(,oe2 . ,cb2) (helixel--strip-adjacent-newlines oe cb)))
        (setq oe oe2 cb cb2)))
    (delete-region cb ce)
    (delete-region ob oe)
    ob))

;; ============================================================================
;; Core: surround-replace helpers
;; ============================================================================

(defun helixel--surround-replace-pair (d new-open new-close)
  "Replace delimiters of D with NEW-OPEN and NEW-CLOSE."
  (pcase-let* ((`(,ob ,oe ,cb ,ce)
                (helixel-delimiter-bounds-flat d)))
    (delete-region cb ce)
    (delete-region ob oe)
    (goto-char ob)
    (insert new-open)
    (let ((close-pos (+ cb
                        (- (if (characterp new-open)
                               1
                             (length new-open))
                           (- oe ob)))))
      (goto-char close-pos)
      (insert new-close)
      (push-mark ob nil t)
      (goto-char (+ close-pos
                     (if (characterp new-close)
                         1
                       (length new-close)))))))

(defun helixel--surround-replace-generic (d)
  "Replace delimiters described by D by prompting for new delimiter.
Reads character, looks up new delimiter, deletes old, adds new.
The prompt shows the old delimiter being replaced."
  (let* ((old-type (helixel-delimiter-type d))
         (old-label (pcase old-type
                      ('pair (format "%c" (helixel-delimiter-open d)))
                      (_ (symbol-name old-type))))
         (prompt (format "replace %s ->" old-label))
         (new-char (read-char (helixel--surround-prompt prompt)))
         (new-d (helixel--surround-lookup-delimiter new-char)))
    (unless new-d
      (user-error "Unknown surround delimiter: %c" new-char))
    (helixel--surround-delete-delimiter d)
    (helixel--surround-add (helixel-delimiter-open new-d)
                          (helixel-delimiter-close new-d))
    (helixel--tracking-open 'edit 'surround-replace)
    (helixel--record-action 'surround-replace :new-char new-char)
     (helixel--sel-push
          (helixel-sel-create
           'surround `(:delimiter ,new-d)
           (lambda (_) nil)  ; surround recreate is a no-op
           (lambda (c)
             (if-let* ((d (helixel-sel-surround-delimiter c)))
                 (format "@%s" (helixel-delimiter-type d))
               "surround"))))))

(defun helixel--surround-replace-tag (new-tag-name d)
  "Replace surrounding XML tags with NEW-TAG-NAME.
D is the tag delimiter plist used to locate the tags."
  (pcase-let* ((`(,ob ,oe ,cb ,ce)
                (helixel-delimiter-bounds-flat d))
               (open-tag (format "<%s>" new-tag-name))
               (close-tag (format "</%s>" new-tag-name))
               (nl-after-open (eq (char-after oe) ?\n))
               (nl-before-close (and (> cb 1) (eq (char-before cb) ?\n))))
    (delete-region cb ce)
    (delete-region ob oe)
    (goto-char ob)
    (insert open-tag)
    (unless nl-after-open (insert "\n"))
    (let ((close-pos (+ cb
                        (- (length open-tag) (- oe ob))
                        (if nl-after-open 0 1))))
      (goto-char close-pos)
      (unless nl-before-close (insert "\n"))
      (insert close-tag)
      (push-mark ob nil t)
      (goto-char (+ close-pos
                     (if nl-before-close 0 1)
                     (length close-tag))))))

;; ============================================================================
;; Interactive commands
;; ============================================================================

(defun helixel-surround-add ()
  "Surround the active selection with a delimiter pair."
  (interactive)
  (helixel-with-command helixel-surround-add
    (unless (use-region-p)
      (user-error "No active selection to surround"))
    (let* ((char (read-char (helixel--surround-prompt "surround add:")))
           (pair (helixel--surround-lookup char))
           (open (car pair))
           (close (cdr pair))
           (is-block (not (characterp open))))
      (unless pair
        (user-error "Unknown surround delimiter: %c" char))
      (helixel--surround-add open close)
      (helixel--tracking-open 'edit 'surround-add)
      (helixel--record-action 'surround-add :char char)
      (helixel--sel-push
       (helixel-sel-create
        'surround `(:delimiter ,(if is-block
                                    (helixel--make-block-delimiter open close)
                                  (helixel--make-pair-delimiter open close)))
        (lambda (_) nil)
        (lambda (c)
          (if-let* ((d (helixel-sel-surround-delimiter c)))
              (format "@%s" (helixel-delimiter-type d))
            "surround"))))
      (setq deactivate-mark nil))))

(defun helixel-surround-add-tag ()
  "Surround the active selection with an XML tag."
  (interactive)
  (helixel-with-command helixel-surround-add-tag
    (unless (use-region-p)
      (user-error "No active selection to surround"))
    (let ((tag (read-string "Tag: ")))
      (helixel--surround-add-tag tag)
      (helixel--tracking-open 'edit 'surround-add)
      (helixel--record-action 'surround-add-tag :tag tag)
      (helixel--sel-push
       (helixel-sel-create
        'surround `(:delimiter ,(helixel--make-tag-delimiter))
        (lambda (_) nil)
        (lambda (c)
          (if-let* ((d (helixel-sel-surround-delimiter c)))
              (format "@%s" (helixel-delimiter-type d))
            "surround"))))
      (setq deactivate-mark nil))))

(defun helixel--surround-prompt-target (cmd prefix)
  "Activate transient textobj map to collect a surround target for CMD.
PREFIX is the key-prefix label (\"md\" / \"mr\") used in the prompt
and cancel message.  Sets `helixel--pending-surround-op' to CMD so
the textobj's after-select hook re-invokes CMD once a target is picked."
  (setq helixel--pending-surround-op cmd)
  (let ((map (make-sparse-keymap))
        (done nil))
    (set-keymap-parent map helixel-textobj-inner-map)
    (define-key map "a" helixel-textobj-outer-map)
    (set-transient-map
     map
     (lambda () (prog1 (not done) (setq done t)))
     (lambda ()
       (when helixel--pending-surround-op
         (setq helixel--pending-surround-op nil)
         (message "%s: no matching target found, cancelled" prefix)))
     (format "%s: select target (( [ { \" ')" prefix))))

(defun helixel-surround-delete ()
  "Delete surrounding delimiters of the current selection.
Uses `helixel--pending-sel' to determine the delimiter type.
When the selection lacks surround info, activates textobj keys
so the user can select a target with one keypress."
  (interactive)
  (helixel-with-command helixel-surround-delete
    (let ((sel-ctx helixel--pending-sel)
          d)
      (if (and sel-ctx (setq d (helixel-sel-surround-delimiter sel-ctx)))
          (progn
            (when (use-region-p)
              (goto-char (/ (+ (region-beginning) (region-end)) 2)))
            (let ((pos (helixel--surround-delete-delimiter d)))
              (goto-char pos)
              (helixel--tracking-open 'edit 'surround-delete)
              (helixel--record-action 'surround-delete)))
        (helixel--surround-prompt-target #'helixel-surround-delete "md")))))

(defun helixel-surround-replace ()
  "Replace surrounding delimiters.
Reads `helixel--pending-sel' for delimiter type.
Prompts per type: tag `read-string', all others `read-char'.
When the selection lacks surround info, activates textobj keys
so the user can select a target with one keypress."
  (interactive)
  (helixel-with-command helixel-surround-replace
    (let ((sel-ctx helixel--pending-sel)
          d)
      (if (and sel-ctx (setq d (helixel-sel-surround-delimiter sel-ctx)))
          (let ((type (helixel-delimiter-type d)))
            (pcase type
              ('tag
               (let ((new-tag (read-string "Tag: ")))
                 (when (use-region-p)
                   (goto-char (/ (+ (region-beginning) (region-end)) 2)))
                 (helixel--surround-replace-tag new-tag d)
                 (helixel--tracking-open 'edit 'surround-replace)
                 (helixel--record-action 'surround-replace :tag new-tag
                                       :surround-type 'tag)
                 (helixel--sel-push
                  (helixel-sel-create
                   'surround `(:delimiter ,(helixel--make-tag-delimiter))
                   (lambda (_) nil)
                   (lambda (c)
                     (if-let* ((d2 (helixel-sel-surround-delimiter c)))
                         (format "@%s" (helixel-delimiter-type d2))
                       "surround"))))))
              (_ (helixel--surround-replace-generic d)))
            (setq deactivate-mark nil))
        (helixel--surround-prompt-target #'helixel-surround-replace "mr")))))

;; ============================================================================
;; Selection-descriptor method
;; ============================================================================

;; ---------------------------------------------------------------------------
;; Edit-op runners (registry consumers — see `helixel-register-op')

(helixel-register-op surround-add
  :display (lambda (tx)
             (let ((c (helixel-tx-char tx)))
               (if c (format "ms[%c]" c) "ms")))
  :moves-point-p nil
  :runner (lambda (tx)
            (when-let* ((char (helixel-tx-char tx))
                        (pair (helixel--surround-lookup char)))
              (helixel--surround-add (car pair) (cdr pair)))))

(helixel-register-op surround-add-tag
  :display (lambda (tx)
             (let ((tag (helixel-action-payload-get tx :tag)))
               (if tag (format "mt[%s]" tag) "mt")))
  :moves-point-p nil
  :runner (lambda (tx)
            (helixel--surround-add-tag
             (helixel-action-payload-get tx :tag))))

(helixel-register-op surround-delete :display "md"
  :runner (lambda (tx)
            (when-let* ((d (helixel-sel-surround-delimiter
                           (helixel-action-sel tx))))
              (goto-char (helixel--surround-delete-delimiter d)))))

(helixel-register-op surround-replace
  :display (lambda (tx)
             (let* ((p (helixel-action-payload tx))
                    (label (or (plist-get p :tag)
                               (when-let* ((c (plist-get p :new-char)))
                                 (string c)))))
               (if label (format "mr[%s]" label) "mr")))
  :runner (lambda (tx)
            (let* ((sel-ctx (helixel-action-sel tx))
                   (d (helixel-sel-surround-delimiter sel-ctx))
                   (type (and d (helixel-delimiter-type d)))
                   (new-char (helixel-action-payload-get tx :new-char))
                   (tag (helixel-action-payload-get tx :tag)))
              (when d
                (pcase type
                  ('tag
                   (when tag (helixel--surround-replace-tag tag d)))
                  (_
                   (when new-char
                     (when-let* ((pair (helixel--surround-lookup new-char)))
                       (helixel--surround-delete-delimiter d)
                       (helixel--surround-add (car pair) (cdr pair))))))))))

;; ============================================================================
;; Pending surround op — auto-retry after textobj selection
;; ============================================================================

(defun helixel--surround-execute-pending ()
  "Execute pending surround op if a textobj with surround info was selected.
Clears `helixel--pending-surround-op' regardless."
  (when helixel--pending-surround-op
    (let ((op helixel--pending-surround-op))
      (setq helixel--pending-surround-op nil)
      (when (and helixel--pending-sel
                 (helixel-sel-surround-delimiter
                  helixel--pending-sel))
        (funcall op)))))

(helixel-register-kind surround
  :ctx-schema '(:required (:delimiter) :optional ())
  :recreate #'ignore
  :advance  nil
  :display  (lambda (ctx)
              (if-let* ((d (helixel-sel-surround-delimiter ctx)))
                  (format "@%s" (helixel-delimiter-type d))
                "surround")))

(add-hook 'helixel-textobj-after-select-functions
          #'helixel--surround-execute-pending)

(provide 'helixel-surround)
;;; helixel-surround.el ends here
