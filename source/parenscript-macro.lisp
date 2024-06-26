;;;; SPDX-FileCopyrightText: Atlas Engineer LLC
;;;; SPDX-License-Identifier: BSD-3-Clause

;; `uiop:define-package' instead of `nyxt:define-package' since it does not
;; depend on Nyxt.
(uiop:define-package :nyxt/parenscript
  (:nicknames :nyxt/ps)
  (:use :cl :parenscript)
  (:import-from :serapeum #:export-always))

(in-package :nyxt/parenscript)
(nyxt:use-nyxt-package-nicknames)

(export-always 'qs)
(defpsmacro qs (context selector)
  "Alias of context.querySelector()"
  `(chain ,context (query-selector ,selector)))

(export-always 'qsa)
(defpsmacro qsa (context selector)
  "Alias of context.querySelectorAll()"
  `(chain ,context (query-selector-all ,selector)))

(export-always 'qs-id)
(defpsmacro qs-id (context id)
  "Alias of context.getElementById()"
  `(chain ,context (get-element-by-id ,id)))

(export-always 'qs-nyxt-id)
(defpsmacro qs-nyxt-id (context id)
  "context.querySelector() tailored for Nyxt IDs."
  `(chain ,context (query-selector (stringify "[nyxt-identifier=\"" ,id "\"]"))))

(export-always 'rqs-nyxt-id)
(defpsmacro rqs-nyxt-id (context id)
  "Recursive version of `qs-nyxt-id` which goes through Shadow DOMs if there's
at least one."
  `(flet ((recursive-query-selector (context selector)
            (let ((node (qs context selector))
                  (shadow-roots (chain *array (from (qsa context "[nyxt-shadow-root]"))))
                  shadow-root)
              (do ((i 0 (1+ i)))
                  ((or node
                       (>= i (chain shadow-roots length))))
                (setf shadow-root (chain (elt shadow-roots i) shadow-root))
                (chain shadow-roots push (apply shadow-roots (chain *array (from (qsa shadow-root "[nyxt-shadow-root]")))))
                (setf node (qs shadow-root selector)))
              node)))
     (if (chain ,context (query-selector "[nyxt-shadow-root]"))
         (recursive-query-selector ,context (stringify "[nyxt-identifier=\"" ,id "\"]"))
         (qs-nyxt-id ,context ,id))))

(export-always 'active-element)
(defpsmacro active-element (context)
  "Shorthand for active element in CONTEXT."
  `(@ ,context active-element))

(defpsmacro get-caret ()
  `(let* ((element (active-element document))
          (tag-name (chain element tag-name)))
     (cond
      ((or (string= tag-name "INPUT") (string= tag-name "TEXTAREA"))
       (list (chain element selection-start) (chain element selection-end)))
      ((chain element is-content-editable)
       (let ((range (chain window (get-selection) (get-range-at 0))))
         (list (@ range start-offset) (@ range end-offset)))))))

(defpsmacro set-caret (element &optional start end)
  `(let* ((element ,element)
          (tag-name (chain element tag-name))
          (start ,start)
          (end ,end))
     (unless (active-element document)
       (chain element (focus)))
     (cond
       ((or (string= tag-name "INPUT")
            (string= tag-name "TEXTAREA"))
        (setf (chain element selection-start) (or start nil)
              (chain element selection-end) (or end start nil)))
       ((chain element is-content-editable)
        (let* ((selection (chain window (get-selection)))
               (range (chain document (create-range))))
          (when (and selection (chain selection (get-range-at 0)))
            (chain selection (remove-all-ranges)))
          (when start
            (chain range (set-start element start))
            (if end
                (chain range (set-end element end))
                (chain range (set-end element start)))
            (chain window (get-selection) (add-range range))))))))

(export-always 'insert-at)
(defpsmacro insert-at (tag input-text)
  "Insert text at a tag."
  `(let* ((element ,tag)
          (caret (get-caret))
          (origin (@ caret 0))
          (end (or (@ caret 1) origin))
          (tag-name (chain element tag-name)))
     (cond
       ((or (string= tag-name "INPUT")
            (string= tag-name "TEXTAREA"))
        (setf (chain element value)
              (+ (chain element value (substring 0 origin))
                 ,input-text
                 (chain element value
                        (substring end (chain element value length))))))
       ((chain element is-content-editable)
        ;; TODO: Implement caret movement, as in
        ;; https://stackoverflow.com/questions/6249095/how-to-set-the-caret-cursor-position-in-a-contenteditable-element-div
        (setf (chain element inner-text)
              (+ (chain element inner-text (substring 0 origin))
                 ,input-text
                 (chain element inner-text
                        (substring end
                                   (chain element inner-text length)))))))
     (set-caret
      (if (= origin end)
          (+ origin (chain ,input-text length))
          origin)
      (+ origin (chain ,input-text length)))))

(export-always 'element-editable-p)
(defpsmacro element-editable-p (element)
  "Whether ELEMENT is editable."
  `(let ((tag (chain ,element tag-name)))
     (if (or (and (string= tag "INPUT")
                  ;; The list of all input types:
                  ;; https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
                  (not (chain ([] "hidden" "checkbox" "button") (includes (chain ,element type))))
                  (not (chain ,element disabled)))
             (string= tag "TEXTAREA")
             (chain ,element is-content-editable))
         t f)))

(export-always 'element-drawable-p)
(defpsmacro element-drawable-p (element)
  "Whether ELEMENT is drawable."
  `(if (or (chain ,element offset-width)
           (chain ,element offset-height)
           (chain ,element (get-client-rects) length))
       t f))

(export-always 'element-in-view-port-p)
(defpsmacro element-in-view-port-p (element)
  "Whether ELEMENT is in viewport."
  `(let* ((rect (chain ,element (get-bounding-client-rect)))
          (computed-style (chain window (get-computed-style ,element))))
     (if (and (>= (chain rect top) 0)
              ;; a partially visible element is still visible
              (<= (chain rect top) (- (chain window inner-height) 1))
              (>= (chain rect left) 0)
              ;; a partially visible element is still visible
              (<= (chain rect left) (- (chain window inner-width) 1))
              ;; some elements have top=bottom=left=right
              (> (chain rect width) 3)
              (> (chain rect height) 3)
              (not (= (chain computed-style "visibility") "hidden"))
              (not (= (chain computed-style "display") "none")))
         t nil)))

(export-always 'element-overlapped-p)
(defpsmacro element-overlapped-p (element)
  "Whether ELEMENT is overlapped by another element."
  ;; Inspired by the algorithm from saka-key, see:
  ;; https://github.com/lusakasa/saka-key/blob/v1.26.3/src/modes/hints/client/findHints.js#L114
  `(let* ((rect (chain ,element (get-bounding-client-rect)))
          (computed-style (chain window (get-computed-style ,element)))
          (coord-truncation-offset 2)
          (radius (parse-float (chain computed-style border-top-left-radius)))
          (rounded-border-offset (ceiling (* radius (- 1 (sin (/ pi 4))))))
          (offset (max coord-truncation-offset rounded-border-offset))
          (el (chain ,element (get-root-node) (element-from-point (+ (chain rect left) offset)
                                                                  (+ (chain rect top) offset)))))
     (if (or (>= offset (chain rect width))
             (>= offset (chain rect height)))
         t
         (progn (loop while (and el (not (eq el element)))
                      do (setf el (if (instanceof (chain el parent-node) *shadow-root)
                                      (chain el parent-node host)
                                      (chain el parent-node))))
                (null el)))))

(export-always 'element-invisible-p)
(defpsmacro element-invisible-p (element)
  "Whether ELEMENT is invisible."
  `(or (= (@ ,element offset-height)
          0)
       (= (chain window (get-computed-style ,element) "visibility")
          "hidden")))

(export-always 'add-class-nyxt-id)
(defpsmacro add-class-nyxt-id (id class)
  "element.classList.add(class) tailored for Nyxt IDs."
  `(let ((element (nyxt/ps:qs-nyxt-id document (ps:lisp ,id))))
     (ps:chain element class-list (add ,class))))

(export-always 'remove-class-nyxt-id)
(defpsmacro remove-class-nyxt-id (id class)
  "element.classList.remove(class) tailored for Nyxt IDs."
  `(let ((element (nyxt/ps:qs-nyxt-id document (ps:lisp ,id))))
     (ps:chain element class-list (remove ,class))))

(export-always 'rqsa)
(defpsmacro rqsa (context selector)
  "Recursive version of context.querySelectorAll() which goes through
Shadow DOMs if there's at least one."
  `(flet ((recursive-query-selector-all (context selector)
            (ps:let ((tree-walker (ps:chain document (create-tree-walker context (ps:@ *Node +element_node+))))
                     (results (array)))
              (ps:loop while (ps:chain tree-walker (next-node))
                 do (when (ps:chain tree-walker current-node (matches selector))
                      (ps:chain results (push (ps:@ tree-walker current-node))))
                    (let ((shadow-root (ps:@ tree-walker current-node shadow-root)))
                      (when shadow-root
                        (ps:chain *array prototype push (apply results (recursive-query-selector-all shadow-root selector))))))
              results)))
     (if (chain ,context (query-selector "[nyxt-shadow-root]"))
         (recursive-query-selector-all ,context ,selector)
         (qsa ,context ,selector))))
