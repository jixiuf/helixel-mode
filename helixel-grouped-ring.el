;;; helixel-grouped-ring.el --- Generic grouped-ring data structure  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

;; Author: jixiuf
;; Keywords: convenience

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; Pure data structure: ordered list of entries with two query axes —
;; visibility (skip entries the caller wants hidden) and grouping
;; (consecutive entries that should be treated as one navigation step).
;;
;; Both `;' cycling (history ring) and C-o/C-i (jump log) consume this
;; module.  Zero helixel dependencies; only requires `cl-lib'.
;;
;; The "ring" is stored as a plain list, NEWEST FIRST.  The caller
;; owns mutation (push / pop / cap) — this module only provides query
;; primitives parameterised by predicates:
;;
;;   visible-pred  : (entry) -> non-nil if entry counts
;;   same-group-p  : (a b)   -> non-nil if a and b belong to same group

;;; Code:

(require 'cl-lib)

;; ── Group navigation ──

(defun helixel-gr-group-start (list pos same-group-p)
  "Return the oldest (largest) index in LIST of the group containing POS.
SAME-GROUP-P is a predicate of two adjacent entries."
  (let ((len (length list)))
    (while (and (< (1+ pos) len)
                (funcall same-group-p
                         (nth pos list) (nth (1+ pos) list)))
      (cl-incf pos))
    pos))

(defun helixel-gr-group-newest (list pos same-group-p)
  "Return the newest (smallest) index in LIST of the group containing POS.
SAME-GROUP-P is a predicate of two adjacent entries."
  (let ((i pos))
    (while (and (> i 0)
                (funcall same-group-p
                         (nth i list) (nth (1- i) list)))
      (cl-decf i))
    i))

;; ── Visibility queries ──

(defun helixel-gr-visible-index (list pos visible-p)
  "Return index of first visible entry at or after POS in LIST, or nil.
VISIBLE-P is a predicate on entries."
  (cl-loop for i from pos below (length list)
           when (funcall visible-p (nth i list))
           return i))

(defun helixel-gr-visible-count (list visible-p)
  "Count entries in LIST for which VISIBLE-P returns non-nil."
  (cl-loop for a in list
           when (funcall visible-p a)
           count 1))

(defun helixel-gr-find (list pos direction visible-p)
  "Find next visible entry index from POS in DIRECTION (+1 or -1).
LIST is the ring, VISIBLE-P the visibility predicate.  Returns nil
if no further visible entry exists in that direction."
  (let ((len (length list)))
    (cl-loop for i from (+ pos direction) by direction
             while (if (> direction 0) (< i len) (>= i 0))
             when (funcall visible-p (nth i list))
             return i)))

(provide 'helixel-grouped-ring)
;;; helixel-grouped-ring.el ends here
