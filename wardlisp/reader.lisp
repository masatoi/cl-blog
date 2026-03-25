;;;; wardlisp/reader.lisp --- Custom S-expression reader for WardLisp.
;;;;
;;;; SECURITY: This reader does NOT use cl:read. It is a hand-written
;;;; recursive descent parser that only recognizes WardLisp syntax.
;;;; This prevents reader-macro injection attacks.

(defpackage #:recurya/wardlisp/reader
  (:use #:cl)
  (:import-from #:recurya/wardlisp/types
                #:wardlisp-true
                #:wardlisp-false
                #:wardlisp-nil)
  (:export #:wardlisp-read
           #:wardlisp-read-all
           #:wardlisp-read-error))

(in-package #:recurya/wardlisp/reader)

(define-condition wardlisp-read-error (error)
  ((message :initarg :message :reader wardlisp-read-error-message)
   (position :initarg :position :reader wardlisp-read-error-position
             :initform nil))
  (:report (lambda (c s)
             (format s "Read error~@[ at position ~D~]: ~A"
                     (wardlisp-read-error-position c)
                     (wardlisp-read-error-message c)))))

;;; --- Reader State ---

(defstruct reader-state
  "Mutable reader state: input string and current position."
  (input "" :type string)
  (pos 0 :type fixnum))

(defun peek-char* (rs)
  "Peek at current character, or NIL if at end."
  (when (< (reader-state-pos rs) (length (reader-state-input rs)))
    (char (reader-state-input rs) (reader-state-pos rs))))

(defun read-char* (rs)
  "Read current character and advance position."
  (let ((ch (peek-char* rs)))
    (when ch (incf (reader-state-pos rs)))
    ch))

(defun at-end-p (rs)
  "Return T if at end of input."
  (>= (reader-state-pos rs) (length (reader-state-input rs))))

(defun read-error (rs message)
  "Signal a read error at current position."
  (error 'wardlisp-read-error
         :message message
         :position (reader-state-pos rs)))

;;; --- Whitespace and Comments ---

(defun whitespace-p (ch)
  "Return T if CH is whitespace."
  (member ch '(#\Space #\Tab #\Newline #\Return)))

(defun skip-whitespace-and-comments (rs)
  "Skip whitespace and ;-comments."
  (loop
    (cond
      ((at-end-p rs) (return))
      ((whitespace-p (peek-char* rs)) (read-char* rs))
      ((char= (peek-char* rs) #\;)
       (loop until (or (at-end-p rs)
                       (char= (peek-char* rs) #\Newline))
             do (read-char* rs)))
      (t (return)))))

;;; --- Token Reading ---

(defun delimiter-p (ch)
  "Return T if CH is a delimiter (ends a token)."
  (or (null ch) (whitespace-p ch)
      (member ch '(#\( #\) #\' #\;))))

(defun read-token (rs)
  "Read a token string (atom) from input."
  (let ((start (reader-state-pos rs)))
    (loop until (delimiter-p (peek-char* rs))
          do (read-char* rs))
    (subseq (reader-state-input rs) start (reader-state-pos rs))))

(defun parse-atom (token rs)
  "Parse a token string into a WardLisp value."
  (declare (ignore rs))
  (cond
    ((string= token "#t") wardlisp-true)
    ((string= token "#f") wardlisp-false)
    ((and (>= (length token) 2) (char= (char token 0) #\:))
     (intern (string-upcase (subseq token 1)) :keyword))
    ((token-number-p token) (parse-integer-or-rational token))
    (t token)))

(defun token-number-p (token)
  "Return T if TOKEN looks like a number."
  (and (plusp (length token))
       (let ((start (if (char= (char token 0) #\-) 1 0)))
         (and (< start (length token))
              (every #'digit-char-p (subseq token start))))))

(defun parse-integer-or-rational (token)
  "Parse TOKEN as integer."
  (parse-integer token))

;;; --- Core Reader ---

(defun read-expr (rs)
  "Read one WardLisp expression."
  (skip-whitespace-and-comments rs)
  (when (at-end-p rs)
    (read-error rs "Unexpected end of input"))
  (let ((ch (peek-char* rs)))
    (cond
      ((char= ch #\() (read-list rs))
      ((char= ch #\') (read-quote rs))
      ((char= ch #\)) (read-error rs "Unexpected ')'"))
      (t (let ((token (read-token rs)))
           (when (zerop (length token))
             (read-error rs "Empty token"))
           (parse-atom token rs))))))

(defun read-list (rs)
  "Read a list expression: ( expr* )"
  (read-char* rs) ; consume (
  (skip-whitespace-and-comments rs)
  (if (and (not (at-end-p rs)) (char= (peek-char* rs) #\)))
      (progn (read-char* rs) wardlisp-nil)
      (read-list-elements rs)))

(defun read-list-elements (rs)
  "Read list elements until closing paren."
  (let ((elements nil))
    (loop
      (skip-whitespace-and-comments rs)
      (when (at-end-p rs)
        (read-error rs "Unclosed parenthesis"))
      (when (char= (peek-char* rs) #\))
        (read-char* rs)
        (return (list-to-wardlisp (nreverse elements))))
      (push (read-expr rs) elements))))

(defun list-to-wardlisp (elements)
  "Convert CL list to WardLisp list (cons cells terminated by :wnil)."
  (if (null elements)
      wardlisp-nil
      (cons (car elements) (list-to-wardlisp (cdr elements)))))

(defun read-quote (rs)
  "Read 'expr as (quote expr)."
  (read-char* rs) ; consume '
  (let ((expr (read-expr rs)))
    (cons "quote" (cons expr wardlisp-nil))))

;;; --- Public API ---

(defun wardlisp-read (string)
  "Read one WardLisp expression from STRING."
  (let ((rs (make-reader-state :input string)))
    (let ((result (read-expr rs)))
      (skip-whitespace-and-comments rs)
      result)))

(defun wardlisp-read-all (string)
  "Read all WardLisp expressions from STRING. Returns CL list of forms."
  (let ((rs (make-reader-state :input string))
        (forms nil))
    (loop
      (skip-whitespace-and-comments rs)
      (when (at-end-p rs) (return (nreverse forms)))
      (push (read-expr rs) forms))))
