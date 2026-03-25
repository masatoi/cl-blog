# WardLisp MVP Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a working WardLisp evaluator with puzzle grading and bot simulation, accessible via web UI.

**Architecture:** Custom Lisp interpreter in Common Lisp (no cl:eval/cl:read). Single-process sandbox via whitelist-only builtins and fuel/cons/depth/output limits. HTMX-driven web UI on existing Ningle/Spinneret stack.

**Tech Stack:** SBCL, Ningle, Spinneret, HTMX, Rove (tests), PostgreSQL (existing, not used by WardLisp)

**Design Doc:** `docs/plans/2026-03-26-wardlisp-mvp-design.md`

**Key Conventions (from existing codebase):**
- Package names match file paths: `wardlisp/reader.lisp` → `recurya/wardlisp/reader`
- Tests use `deftest` + `testing` + `ok` (Rove)
- HTML templates export `render` function, use `spinneret:with-html-string`
- Routes use `make-dynamic-handler` for REPL hot-reload
- Response format: `(list status headers body-list)`
- HTMX: `:hx-post`, `:hx-target "#id"`, `:hx-swap "innerHTML"`

---

## Phase 1: WardLisp Evaluator Core

### Task 1: Types and Value Representation

**Files:**
- Create: `wardlisp/types.lisp`
- Test: `tests/wardlisp/types.lisp`

**Step 1: Write the failing test**

Create `tests/wardlisp/types.lisp`:

```lisp
;;;; tests/wardlisp/types.lisp --- Tests for WardLisp value types.

(defpackage #:recurya/tests/wardlisp/types
  (:use #:cl #:rove)
  (:import-from #:recurya/wardlisp/types
                #:wardlisp-number-p
                #:wardlisp-boolean-p
                #:wardlisp-symbol-p
                #:wardlisp-list-p
                #:wardlisp-nil-p
                #:wardlisp-closure-p
                #:wardlisp-true
                #:wardlisp-false
                #:wardlisp-nil
                #:make-closure
                #:closure-params
                #:closure-body
                #:closure-env
                #:wardlisp-equal
                #:wardlisp->string))

(in-package #:recurya/tests/wardlisp/types)

(deftest type-predicates
  (testing "numbers are recognized"
    (ok (wardlisp-number-p 42))
    (ok (wardlisp-number-p 3/4))
    (ok (not (wardlisp-number-p "hello"))))

  (testing "booleans are recognized"
    (ok (wardlisp-boolean-p wardlisp-true))
    (ok (wardlisp-boolean-p wardlisp-false))
    (ok (not (wardlisp-boolean-p 1))))

  (testing "symbols are keywords"
    (ok (wardlisp-symbol-p :up))
    (ok (wardlisp-symbol-p :foo))
    (ok (not (wardlisp-symbol-p 42))))

  (testing "nil value"
    (ok (wardlisp-nil-p wardlisp-nil))
    (ok (not (wardlisp-nil-p nil))))

  (testing "lists"
    (ok (wardlisp-list-p (cons 1 (cons 2 wardlisp-nil))))
    (ok (not (wardlisp-list-p 42)))))

(deftest closures
  (testing "closure creation and access"
    (let ((c (make-closure '("x") '((+ x 1)) nil)))
      (ok (wardlisp-closure-p c))
      (ok (equal (closure-params c) '("x")))
      (ok (equal (closure-body c) '((+ x 1)))))))

(deftest equality
  (testing "number equality"
    (ok (wardlisp-equal 42 42))
    (ok (not (wardlisp-equal 42 43))))

  (testing "boolean equality"
    (ok (wardlisp-equal wardlisp-true wardlisp-true))
    (ok (not (wardlisp-equal wardlisp-true wardlisp-false))))

  (testing "symbol equality"
    (ok (wardlisp-equal :up :up))
    (ok (not (wardlisp-equal :up :down))))

  (testing "list equality"
    (ok (wardlisp-equal (cons 1 (cons 2 wardlisp-nil))
                        (cons 1 (cons 2 wardlisp-nil))))))

(deftest display
  (testing "value display"
    (ok (string= (wardlisp->string 42) "42"))
    (ok (string= (wardlisp->string wardlisp-true) "#t"))
    (ok (string= (wardlisp->string wardlisp-false) "#f"))
    (ok (string= (wardlisp->string wardlisp-nil) "()"))
    (ok (string= (wardlisp->string :up) ":up"))))
```

**Step 2: Run test to verify it fails**

Run: `(asdf:test-system "recurya/tests/wardlisp/types")`
Expected: FAIL — package `recurya/wardlisp/types` does not exist

**Step 3: Write implementation**

Create `wardlisp/types.lisp`:

```lisp
;;;; wardlisp/types.lisp --- Value types for the WardLisp language.
;;;;
;;;; WardLisp values are represented using CL objects:
;;;; - Numbers: CL integer/rational
;;;; - Booleans: :true / :false (distinct from CL T/NIL)
;;;; - Symbols: CL keywords (:up, :down, etc.)
;;;; - Lists: CL cons cells terminated by :wnil
;;;; - Nil: :wnil (empty list)
;;;; - Closures: struct with params, body, env

(defpackage #:recurya/wardlisp/types
  (:use #:cl)
  (:export #:wardlisp-true
           #:wardlisp-false
           #:wardlisp-nil
           #:wardlisp-number-p
           #:wardlisp-boolean-p
           #:wardlisp-symbol-p
           #:wardlisp-list-p
           #:wardlisp-nil-p
           #:wardlisp-closure-p
           #:wardlisp-self-evaluating-p
           #:make-closure
           #:closure-params
           #:closure-body
           #:closure-env
           #:wardlisp-equal
           #:wardlisp->string
           #:wardlisp-truthy-p))

(in-package #:recurya/wardlisp/types)

;;; --- Constants ---

(defconstant wardlisp-true :true
  "WardLisp boolean true value.")

(defconstant wardlisp-false :false
  "WardLisp boolean false value.")

(defconstant wardlisp-nil :wnil
  "WardLisp nil / empty list value.")

;;; --- Closures ---

(defstruct (closure (:constructor %make-closure))
  "A WardLisp closure capturing lexical environment."
  (params nil :type list)
  (body nil :type list)
  (env nil))

(defun make-closure (params body env)
  "Create a WardLisp closure."
  (%make-closure :params params :body body :env env))

(defun wardlisp-closure-p (val)
  "Return T if VAL is a WardLisp closure."
  (closure-p val))

;;; --- Type Predicates ---

(defun wardlisp-number-p (val)
  "Return T if VAL is a WardLisp number."
  (numberp val))

(defun wardlisp-boolean-p (val)
  "Return T if VAL is a WardLisp boolean."
  (or (eq val wardlisp-true) (eq val wardlisp-false)))

(defun wardlisp-symbol-p (val)
  "Return T if VAL is a WardLisp symbol (keyword, not boolean/nil)."
  (and (keywordp val)
       (not (wardlisp-boolean-p val))
       (not (eq val wardlisp-nil))))

(defun wardlisp-nil-p (val)
  "Return T if VAL is WardLisp nil."
  (eq val wardlisp-nil))

(defun wardlisp-list-p (val)
  "Return T if VAL is a WardLisp list (cons cell or nil)."
  (or (wardlisp-nil-p val) (consp val)))

(defun wardlisp-self-evaluating-p (val)
  "Return T if VAL is self-evaluating (number, boolean, keyword)."
  (or (wardlisp-number-p val)
      (wardlisp-boolean-p val)
      (wardlisp-symbol-p val)))

(defun wardlisp-truthy-p (val)
  "Return T if VAL is truthy in WardLisp. Only #f is falsy."
  (not (eq val wardlisp-false)))

;;; --- Equality ---

(defun wardlisp-equal (a b)
  "Deep equality comparison for WardLisp values."
  (cond
    ((and (wardlisp-nil-p a) (wardlisp-nil-p b)) t)
    ((and (numberp a) (numberp b)) (= a b))
    ((and (keywordp a) (keywordp b)) (eq a b))
    ((and (consp a) (consp b))
     (and (wardlisp-equal (car a) (car b))
          (wardlisp-equal (cdr a) (cdr b))))
    ((and (closure-p a) (closure-p b)) (eq a b))
    (t nil)))

;;; --- Display ---

(defun wardlisp->string (val)
  "Convert a WardLisp value to its display string."
  (cond
    ((eq val wardlisp-true) "#t")
    ((eq val wardlisp-false) "#f")
    ((wardlisp-nil-p val) "()")
    ((numberp val) (format nil "~A" val))
    ((keywordp val) (format nil ":~(~A~)" val))
    ((consp val) (format nil "(~A)" (list-contents->string val)))
    ((closure-p val) "#<closure>")
    (t (format nil "~A" val))))

(defun list-contents->string (val)
  "Convert list contents to display string (without outer parens)."
  (cond
    ((wardlisp-nil-p val) "")
    ((not (consp (cdr val)))
     (if (wardlisp-nil-p (cdr val))
         (wardlisp->string (car val))
         (format nil "~A . ~A" (wardlisp->string (car val))
                 (wardlisp->string (cdr val)))))
    (t (format nil "~A ~A" (wardlisp->string (car val))
               (list-contents->string (cdr val))))))
```

**Step 4: Run test to verify it passes**

Run: `(asdf:test-system "recurya/tests/wardlisp/types")`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add wardlisp/types.lisp tests/wardlisp/types.lisp
git commit -m "feat(wardlisp): add value type definitions and predicates"
```

---

### Task 2: Lexical Environment

**Files:**
- Create: `wardlisp/environment.lisp`
- Test: `tests/wardlisp/environment.lisp`

**Step 1: Write the failing test**

Create `tests/wardlisp/environment.lisp`:

```lisp
;;;; tests/wardlisp/environment.lisp --- Tests for WardLisp lexical environment.

(defpackage #:recurya/tests/wardlisp/environment
  (:use #:cl #:rove)
  (:import-from #:recurya/wardlisp/environment
                #:make-env
                #:env-lookup
                #:env-extend
                #:env-define!))

(in-package #:recurya/tests/wardlisp/environment)

(deftest lookup
  (testing "lookup finds variable in current frame"
    (let ((env (env-extend (make-env) '(("x" . 42)))))
      (ok (= 42 (env-lookup env "x")))))

  (testing "lookup finds variable in outer frame"
    (let* ((outer (env-extend (make-env) '(("x" . 10))))
           (inner (env-extend outer '(("y" . 20)))))
      (ok (= 10 (env-lookup inner "x")))))

  (testing "inner shadows outer"
    (let* ((outer (env-extend (make-env) '(("x" . 10))))
           (inner (env-extend outer '(("x" . 99)))))
      (ok (= 99 (env-lookup inner "x")))))

  (testing "unbound variable signals error"
    (let ((env (make-env)))
      (ok (signals (error) (env-lookup env "z"))))))

(deftest define
  (testing "define adds to current frame"
    (let ((env (env-extend (make-env) nil)))
      (env-define! env "x" 42)
      (ok (= 42 (env-lookup env "x")))))

  (testing "define overwrites in current frame"
    (let ((env (env-extend (make-env) '(("x" . 1)))))
      (env-define! env "x" 2)
      (ok (= 2 (env-lookup env "x"))))))
```

**Step 2: Run test — Expected: FAIL**

**Step 3: Write implementation**

Create `wardlisp/environment.lisp`:

```lisp
;;;; wardlisp/environment.lisp --- Lexical environment for WardLisp.
;;;;
;;;; Environments are represented as a list of frames (alist stack).
;;;; Each frame is an alist of (name-string . value) pairs.
;;;; Lookup walks from innermost to outermost frame.

(defpackage #:recurya/wardlisp/environment
  (:use #:cl)
  (:export #:make-env
           #:env-lookup
           #:env-extend
           #:env-define!))

(in-package #:recurya/wardlisp/environment)

(defun make-env ()
  "Create an empty environment (no frames)."
  nil)

(defun env-extend (env bindings)
  "Extend ENV with a new frame containing BINDINGS (alist of name.value pairs)."
  (cons (copy-alist bindings) env))

(defun env-lookup (env name)
  "Look up NAME in ENV. Signals error if unbound."
  (dolist (frame env)
    (let ((pair (assoc name frame :test #'string=)))
      (when pair (return-from env-lookup (cdr pair)))))
  (error "Unbound variable: ~A" name))

(defun env-define! (env name value)
  "Define NAME in the innermost frame of ENV."
  (when (null env)
    (error "Cannot define in empty environment"))
  (let* ((frame (car env))
         (pair (assoc name frame :test #'string=)))
    (if pair
        (setf (cdr pair) value)
        (setf (car env) (acons name value frame))))
  value)
```

**Step 4: Run test — Expected: All PASS**

**Step 5: Commit**

```bash
git add wardlisp/environment.lisp tests/wardlisp/environment.lisp
git commit -m "feat(wardlisp): add lexical environment with lookup and define"
```

---

### Task 3: Custom S-Expression Reader

**Files:**
- Create: `wardlisp/reader.lisp`
- Test: `tests/wardlisp/reader.lisp`

**Step 1: Write the failing test**

Create `tests/wardlisp/reader.lisp`:

```lisp
;;;; tests/wardlisp/reader.lisp --- Tests for WardLisp S-expression reader.

(defpackage #:recurya/tests/wardlisp/reader
  (:use #:cl #:rove)
  (:import-from #:recurya/wardlisp/types
                #:wardlisp-true
                #:wardlisp-false
                #:wardlisp-nil
                #:wardlisp-equal)
  (:import-from #:recurya/wardlisp/reader
                #:wardlisp-read
                #:wardlisp-read-all
                #:wardlisp-read-error))

(in-package #:recurya/tests/wardlisp/reader)

(deftest read-atoms
  (testing "integers"
    (ok (= 42 (wardlisp-read "42")))
    (ok (= -7 (wardlisp-read "-7")))
    (ok (= 0 (wardlisp-read "0"))))

  (testing "booleans"
    (ok (eq wardlisp-true (wardlisp-read "#t")))
    (ok (eq wardlisp-false (wardlisp-read "#f"))))

  (testing "symbols become variable names (strings)"
    (ok (string= "foo" (wardlisp-read "foo")))
    (ok (string= "+" (wardlisp-read "+")))
    (ok (string= "null?" (wardlisp-read "null?"))))

  (testing "keywords"
    (ok (eq :up (wardlisp-read ":up")))
    (ok (eq :down (wardlisp-read ":down")))))

(deftest read-lists
  (testing "empty list"
    (ok (eq wardlisp-nil (wardlisp-read "()"))))

  (testing "simple list"
    (let ((result (wardlisp-read "(1 2 3)")))
      (ok (= 1 (car result)))
      (ok (= 3 (car (cdr (cdr result)))))))

  (testing "nested list"
    (let ((result (wardlisp-read "(+ (* 2 3) 1)")))
      (ok (string= "+" (car result)))))

  (testing "quote shorthand"
    (let ((result (wardlisp-read "'(1 2)")))
      (ok (string= "quote" (car result))))))

(deftest read-multiple
  (testing "read-all parses multiple forms"
    (let ((forms (wardlisp-read-all "(define x 1) (+ x 2)")))
      (ok (= 2 (length forms))))))

(deftest read-errors
  (testing "unclosed paren"
    (ok (signals wardlisp-read-error (wardlisp-read "(1 2"))))

  (testing "unexpected close paren"
    (ok (signals wardlisp-read-error (wardlisp-read ")"))))

  (testing "empty input"
    (ok (signals wardlisp-read-error (wardlisp-read "")))))

(deftest read-whitespace-and-comments
  (testing "skips whitespace"
    (ok (= 42 (wardlisp-read "  42  "))))

  (testing "skips line comments"
    (ok (= 42 (wardlisp-read ";; hello\n42")))))
```

**Step 2: Run test — Expected: FAIL**

**Step 3: Write implementation**

Create `wardlisp/reader.lisp`:

```lisp
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
```

**Step 4: Run test — Expected: All PASS**

**Step 5: Commit**

```bash
git add wardlisp/reader.lisp tests/wardlisp/reader.lisp
git commit -m "feat(wardlisp): add custom S-expression reader (no cl:read)"
```

---

### Task 4: Built-in Functions

**Files:**
- Create: `wardlisp/builtins.lisp`
- Test: `tests/wardlisp/builtins.lisp`

**Step 1: Write the failing test**

Create `tests/wardlisp/builtins.lisp`:

```lisp
;;;; tests/wardlisp/builtins.lisp --- Tests for WardLisp built-in functions.

(defpackage #:recurya/tests/wardlisp/builtins
  (:use #:cl #:rove)
  (:import-from #:recurya/wardlisp/types
                #:wardlisp-true
                #:wardlisp-false
                #:wardlisp-nil)
  (:import-from #:recurya/wardlisp/builtins
                #:lookup-builtin
                #:builtin-names))

(in-package #:recurya/tests/wardlisp/builtins)

(deftest builtin-registry
  (testing "known builtins are found"
    (ok (functionp (lookup-builtin "+")))
    (ok (functionp (lookup-builtin "cons")))
    (ok (functionp (lookup-builtin "null?"))))

  (testing "unknown names return nil"
    (ok (null (lookup-builtin "eval")))
    (ok (null (lookup-builtin "system")))))

(deftest arithmetic
  (testing "addition"
    (ok (= 5 (funcall (lookup-builtin "+") '(2 3)))))

  (testing "subtraction"
    (ok (= 3 (funcall (lookup-builtin "-") '(5 2)))))

  (testing "multiplication"
    (ok (= 12 (funcall (lookup-builtin "*") '(3 4)))))

  (testing "division"
    (ok (= 5 (funcall (lookup-builtin "/") '(10 2)))))

  (testing "modulo"
    (ok (= 1 (funcall (lookup-builtin "mod") '(7 3))))))

(deftest comparison
  (testing "equal"
    (ok (eq wardlisp-true (funcall (lookup-builtin "=") '(3 3))))
    (ok (eq wardlisp-false (funcall (lookup-builtin "=") '(3 4)))))

  (testing "less than"
    (ok (eq wardlisp-true (funcall (lookup-builtin "<") '(1 2))))
    (ok (eq wardlisp-false (funcall (lookup-builtin "<") '(2 1))))))

(deftest list-ops
  (testing "cons"
    (let ((result (funcall (lookup-builtin "cons") (list 1 wardlisp-nil))))
      (ok (= 1 (car result)))
      (ok (eq wardlisp-nil (cdr result)))))

  (testing "car and cdr"
    (let ((pair (cons 1 (cons 2 wardlisp-nil))))
      (ok (= 1 (funcall (lookup-builtin "car") (list pair))))
      (ok (= 2 (car (funcall (lookup-builtin "cdr") (list pair)))))))

  (testing "null?"
    (ok (eq wardlisp-true (funcall (lookup-builtin "null?") (list wardlisp-nil))))
    (ok (eq wardlisp-false (funcall (lookup-builtin "null?") (list 42)))))

  (testing "list"
    (let ((result (funcall (lookup-builtin "list") '(1 2 3))))
      (ok (= 1 (car result)))
      (ok (= 3 (car (cdr (cdr result)))))))

  (testing "length"
    (let ((lst (cons 1 (cons 2 (cons 3 wardlisp-nil)))))
      (ok (= 3 (funcall (lookup-builtin "length") (list lst))))))

  (testing "pair?"
    (ok (eq wardlisp-true (funcall (lookup-builtin "pair?") (list (cons 1 2)))))
    (ok (eq wardlisp-false (funcall (lookup-builtin "pair?") (list 42))))))

(deftest type-predicates
  (testing "number?"
    (ok (eq wardlisp-true (funcall (lookup-builtin "number?") '(42))))
    (ok (eq wardlisp-false (funcall (lookup-builtin "number?") (list :up)))))

  (testing "boolean?"
    (ok (eq wardlisp-true (funcall (lookup-builtin "boolean?") (list wardlisp-true))))
    (ok (eq wardlisp-false (funcall (lookup-builtin "boolean?") '(1))))))

(deftest utility
  (testing "alist-ref"
    (let ((alist (cons (cons :x 10) (cons (cons :y 20) wardlisp-nil))))
      (ok (= 10 (funcall (lookup-builtin "alist-ref") (list :x alist)))))))
```

**Step 2: Run test — Expected: FAIL**

**Step 3: Write implementation**

Create `wardlisp/builtins.lisp`:

```lisp
;;;; wardlisp/builtins.lisp --- Whitelisted built-in functions for WardLisp.
;;;;
;;;; SECURITY: Only these functions are accessible from user code.
;;;; No CL function is callable unless explicitly registered here.

(defpackage #:recurya/wardlisp/builtins
  (:use #:cl)
  (:import-from #:recurya/wardlisp/types
                #:wardlisp-true
                #:wardlisp-false
                #:wardlisp-nil
                #:wardlisp-nil-p
                #:wardlisp-number-p
                #:wardlisp-boolean-p
                #:wardlisp-symbol-p
                #:wardlisp-list-p
                #:wardlisp-equal)
  (:export #:lookup-builtin
           #:builtin-names
           #:make-print-builtin))

(in-package #:recurya/wardlisp/builtins)

(defvar *builtins* (make-hash-table :test 'equal)
  "Registry of built-in functions. Maps name string to function.")

(defmacro defbuiltin (name params &body body)
  "Define a built-in function. PARAMS is the WardLisp arg list name."
  `(setf (gethash ,name *builtins*)
         (lambda (,params) ,@body)))

;;; --- Arithmetic ---

(defbuiltin "+" (args) (apply #'+ args))
(defbuiltin "-" (args) (apply #'- args))
(defbuiltin "*" (args) (apply #'* args))
(defbuiltin "/" (args) (apply #'/ args))
(defbuiltin "mod" (args) (mod (first args) (second args)))
(defbuiltin "abs" (args) (abs (first args)))

;;; --- Comparison ---

(defun bool (val) (if val wardlisp-true wardlisp-false))

(defbuiltin "=" (args) (bool (= (first args) (second args))))
(defbuiltin "<" (args) (bool (< (first args) (second args))))
(defbuiltin ">" (args) (bool (> (first args) (second args))))
(defbuiltin "<=" (args) (bool (<= (first args) (second args))))
(defbuiltin ">=" (args) (bool (>= (first args) (second args))))
(defbuiltin "equal?" (args) (bool (wardlisp-equal (first args) (second args))))

;;; --- Logic ---

(defbuiltin "not" (args)
  (if (eq (first args) wardlisp-false) wardlisp-true wardlisp-false))

;;; --- List Operations ---

(defbuiltin "cons" (args) (cons (first args) (second args)))
(defbuiltin "car" (args) (car (first args)))
(defbuiltin "cdr" (args) (cdr (first args)))

(defbuiltin "list" (args)
  (if (null args)
      wardlisp-nil
      (reduce (lambda (a b) (cons a b))
              args :from-end t :initial-value wardlisp-nil)))

(defbuiltin "null?" (args) (bool (wardlisp-nil-p (first args))))
(defbuiltin "pair?" (args) (bool (consp (first args))))

(defbuiltin "length" (args)
  (labels ((len (lst acc)
             (if (wardlisp-nil-p lst) acc
                 (len (cdr lst) (1+ acc)))))
    (len (first args) 0)))

(defbuiltin "append" (args)
  (labels ((app (a b)
             (if (wardlisp-nil-p a) b
                 (cons (car a) (app (cdr a) b)))))
    (app (first args) (second args))))

;;; --- Type Predicates ---

(defbuiltin "number?" (args) (bool (wardlisp-number-p (first args))))
(defbuiltin "boolean?" (args) (bool (wardlisp-boolean-p (first args))))
(defbuiltin "symbol?" (args) (bool (wardlisp-symbol-p (first args))))
(defbuiltin "list?" (args) (bool (wardlisp-list-p (first args))))

;;; --- Utility ---

(defbuiltin "alist-ref" (args)
  (let ((key (first args))
        (alist (second args)))
    (labels ((find-key (lst)
               (cond
                 ((wardlisp-nil-p lst) wardlisp-nil)
                 ((wardlisp-equal key (car (car lst))) (cdr (car lst)))
                 (t (find-key (cdr lst))))))
      (find-key alist))))

;;; --- Print (created per-execution with output limit) ---

(defun make-print-builtin (state limits)
  "Create a print builtin that respects output limits.
STATE and LIMITS are from the evaluator's execution context."
  (declare (ignore state limits))
  ;; Will be wired up in evaluator task
  (lambda (args)
    (declare (ignore args))
    wardlisp-nil))

;;; --- Public API ---

(defun lookup-builtin (name)
  "Look up a built-in function by name. Returns function or NIL."
  (gethash name *builtins*))

(defun builtin-names ()
  "Return list of all built-in function names."
  (let ((names nil))
    (maphash (lambda (k v) (declare (ignore v)) (push k names)) *builtins*)
    (sort names #'string<)))
```

**Step 4: Run test — Expected: All PASS**

**Step 5: Commit**

```bash
git add wardlisp/builtins.lisp tests/wardlisp/builtins.lisp
git commit -m "feat(wardlisp): add whitelisted built-in functions"
```

---

### Task 5: Core Evaluator with Resource Limits

**Files:**
- Create: `wardlisp/evaluator.lisp`
- Test: `tests/wardlisp/evaluator.lisp`

**Step 1: Write the failing test**

Create `tests/wardlisp/evaluator.lisp`:

```lisp
;;;; tests/wardlisp/evaluator.lisp --- Tests for WardLisp evaluator.

(defpackage #:recurya/tests/wardlisp/evaluator
  (:use #:cl #:rove)
  (:import-from #:recurya/wardlisp/types
                #:wardlisp-true
                #:wardlisp-false
                #:wardlisp-nil
                #:wardlisp-nil-p
                #:wardlisp-equal
                #:wardlisp->string)
  (:import-from #:recurya/wardlisp/evaluator
                #:eval-program
                #:make-execution-limits
                #:execution-result-value
                #:execution-result-fuel-used
                #:execution-result-cons-used
                #:execution-result-output
                #:execution-result-error
                #:fuel-exhausted
                #:cons-limit-exceeded
                #:depth-limit-exceeded))

(in-package #:recurya/tests/wardlisp/evaluator)

;;; Helper
(defun run (code &key (fuel 10000) (max-cons 5000) (max-depth 100))
  "Run WardLisp code and return the result value."
  (let ((result (eval-program code
                  :limits (make-execution-limits
                            :fuel fuel :max-cons max-cons
                            :max-depth max-depth))))
    (execution-result-value result)))

(defun run-result (code &key (fuel 10000) (max-cons 5000) (max-depth 100))
  "Run WardLisp code and return the full result struct."
  (eval-program code
    :limits (make-execution-limits
              :fuel fuel :max-cons max-cons :max-depth max-depth)))

(deftest self-evaluating
  (testing "numbers"
    (ok (= 42 (run "42"))))

  (testing "booleans"
    (ok (eq wardlisp-true (run "#t")))
    (ok (eq wardlisp-false (run "#f"))))

  (testing "keywords"
    (ok (eq :up (run ":up")))))

(deftest arithmetic
  (testing "basic ops"
    (ok (= 5 (run "(+ 2 3)")))
    (ok (= 6 (run "(* 2 3)")))
    (ok (= 10 (run "(+ 1 2 3 4)")))))

(deftest special-forms
  (testing "if true branch"
    (ok (= 1 (run "(if #t 1 2)"))))

  (testing "if false branch"
    (ok (= 2 (run "(if #f 1 2)"))))

  (testing "let binding"
    (ok (= 3 (run "(let ((x 1) (y 2)) (+ x y))"))))

  (testing "define and use"
    (ok (= 42 (run "(define x 42) x"))))

  (testing "begin returns last"
    (ok (= 3 (run "(begin 1 2 3)"))))

  (testing "quote"
    (ok (wardlisp-equal (run "'(1 2 3)")
                        (run "(list 1 2 3)")))))

(deftest lambda-and-closure
  (testing "lambda application"
    (ok (= 5 (run "((lambda (x) (+ x 2)) 3)"))))

  (testing "closure captures environment"
    (ok (= 10 (run "(define add5 (lambda (x) (+ x 5))) (add5 5)"))))

  (testing "higher-order function"
    (ok (= 9 (run "(define apply-twice (lambda (f x) (f (f x))))
                    (define inc (lambda (x) (+ x 1)))
                    (apply-twice inc 7)")))))

(deftest recursion
  (testing "factorial"
    (ok (= 120 (run "(define fact (lambda (n)
                        (if (= n 0) 1 (* n (fact (- n 1))))))
                      (fact 5)"))))

  (testing "list operations"
    (ok (= 6 (run "(define sum (lambda (lst)
                      (if (null? lst) 0
                          (+ (car lst) (sum (cdr lst))))))
                    (sum '(1 2 3))")))))

(deftest and-or
  (testing "and short-circuits"
    (ok (eq wardlisp-false (run "(and #f (/ 1 0))"))))

  (testing "or short-circuits"
    (ok (eq wardlisp-true (run "(or #t (/ 1 0))")))))

(deftest fuel-limit
  (testing "fuel exhaustion"
    (let ((result (run-result "(define loop (lambda () (loop))) (loop)" :fuel 50)))
      (ok (execution-result-error result))
      (ok (search "fuel" (string-downcase (execution-result-error result)))))))

(deftest depth-limit
  (testing "depth exhaustion"
    (let ((result (run-result "(define deep (lambda (n) (deep (+ n 1)))) (deep 0)"
                              :max-depth 10)))
      (ok (execution-result-error result))
      (ok (search "depth" (string-downcase (execution-result-error result)))))))

(deftest cons-limit
  (testing "cons exhaustion"
    (let ((result (run-result
                    "(define make-list (lambda (n)
                       (if (= n 0) '() (cons n (make-list (- n 1))))))
                     (make-list 10000)"
                    :max-cons 50)))
      (ok (execution-result-error result))
      (ok (search "cons" (string-downcase (execution-result-error result)))))))

(deftest metrics-tracking
  (testing "fuel usage is tracked"
    (let ((result (run-result "(+ 1 2)")))
      (ok (> (execution-result-fuel-used result) 0)))))

(deftest error-handling
  (testing "unbound variable"
    (let ((result (run-result "undefined-var")))
      (ok (execution-result-error result))))

  (testing "type error in arithmetic"
    (let ((result (run-result "(+ 1 #t)")))
      (ok (execution-result-error result)))))

(deftest deterministic
  (testing "same input produces same result"
    (let ((code "(define fact (lambda (n) (if (= n 0) 1 (* n (fact (- n 1)))))) (fact 10)"))
      (ok (= (run code) (run code) (run code))))))
```

**Step 2: Run test — Expected: FAIL**

**Step 3: Write implementation**

Create `wardlisp/evaluator.lisp`:

```lisp
;;;; wardlisp/evaluator.lisp --- Core evaluator for WardLisp with resource limits.
;;;;
;;;; SECURITY: This evaluator does NOT use cl:eval. It is a tree-walking
;;;; interpreter that only evaluates WardLisp forms. All resource limits
;;;; (fuel, cons, depth, output) are enforced inside the evaluator.

(defpackage #:recurya/wardlisp/evaluator
  (:use #:cl)
  (:import-from #:recurya/wardlisp/types
                #:wardlisp-true
                #:wardlisp-false
                #:wardlisp-nil
                #:wardlisp-nil-p
                #:wardlisp-number-p
                #:wardlisp-boolean-p
                #:wardlisp-symbol-p
                #:wardlisp-closure-p
                #:wardlisp-self-evaluating-p
                #:wardlisp-truthy-p
                #:make-closure
                #:closure-params
                #:closure-body
                #:closure-env
                #:wardlisp->string)
  (:import-from #:recurya/wardlisp/environment
                #:make-env
                #:env-lookup
                #:env-extend
                #:env-define!)
  (:import-from #:recurya/wardlisp/reader
                #:wardlisp-read-all)
  (:import-from #:recurya/wardlisp/builtins
                #:lookup-builtin)
  (:export #:eval-program
           #:make-execution-limits
           #:execution-limits-fuel
           #:execution-limits-max-cons
           #:execution-limits-max-depth
           #:execution-limits-max-output
           #:execution-result
           #:execution-result-value
           #:execution-result-fuel-used
           #:execution-result-cons-used
           #:execution-result-depth-reached
           #:execution-result-output
           #:execution-result-error
           ;; Conditions
           #:wardlisp-runtime-error
           #:fuel-exhausted
           #:cons-limit-exceeded
           #:depth-limit-exceeded
           #:output-limit-exceeded))

(in-package #:recurya/wardlisp/evaluator)

;;; --- Resource Limits ---

(defstruct execution-limits
  "Resource limits for a WardLisp execution."
  (fuel 10000 :type fixnum)
  (max-cons 5000 :type fixnum)
  (max-depth 100 :type fixnum)
  (max-output 4096 :type fixnum))

;;; --- Execution State (mutable, per-execution) ---

(defstruct execution-state
  "Mutable execution state tracking resource usage."
  (fuel-used 0 :type fixnum)
  (cons-used 0 :type fixnum)
  (max-depth-reached 0 :type fixnum)
  (current-depth 0 :type fixnum)
  (output-stream (make-string-output-stream))
  (output-used 0 :type fixnum))

;;; --- Result ---

(defstruct execution-result
  "Result of a WardLisp program execution."
  value
  (fuel-used 0 :type fixnum)
  (cons-used 0 :type fixnum)
  (depth-reached 0 :type fixnum)
  (output "" :type string)
  (error nil))

;;; --- Conditions ---

(define-condition wardlisp-runtime-error (error)
  ((message :initarg :message :reader wardlisp-runtime-error-message))
  (:report (lambda (c s)
             (format s "~A" (wardlisp-runtime-error-message c)))))

(define-condition fuel-exhausted (wardlisp-runtime-error) ()
  (:default-initargs :message "Fuel exhausted: program took too many steps"))

(define-condition cons-limit-exceeded (wardlisp-runtime-error) ()
  (:default-initargs :message "Cons limit exceeded: too many list allocations"))

(define-condition depth-limit-exceeded (wardlisp-runtime-error) ()
  (:default-initargs :message "Depth limit exceeded: recursion too deep"))

(define-condition output-limit-exceeded (wardlisp-runtime-error) ()
  (:default-initargs :message "Output limit exceeded: too much printed output"))

;;; --- Limit Checking ---

(defun check-fuel! (state limits)
  "Consume one fuel unit. Signal if exhausted."
  (incf (execution-state-fuel-used state))
  (when (> (execution-state-fuel-used state) (execution-limits-fuel limits))
    (error 'fuel-exhausted)))

(defun check-cons! (state limits)
  "Record one cons allocation. Signal if exceeded."
  (incf (execution-state-cons-used state))
  (when (> (execution-state-cons-used state) (execution-limits-max-cons limits))
    (error 'cons-limit-exceeded)))

(defun check-depth! (state limits)
  "Check current depth. Signal if exceeded."
  (when (> (execution-state-current-depth state) (execution-limits-max-depth limits))
    (error 'depth-limit-exceeded))
  (when (> (execution-state-current-depth state)
           (execution-state-max-depth-reached state))
    (setf (execution-state-max-depth-reached state)
          (execution-state-current-depth state))))

;;; --- Core Evaluator ---

(defun eval-expr (expr env state limits)
  "Evaluate a single WardLisp expression."
  (check-fuel! state limits)
  (cond
    ;; Self-evaluating: numbers, booleans, keywords
    ((wardlisp-self-evaluating-p expr) expr)

    ;; Variable lookup (strings are variable names)
    ((stringp expr)
     (let ((builtin (lookup-builtin expr)))
       (if builtin
           builtin
           (env-lookup env expr))))

    ;; Special forms and application (must be a cons)
    ((consp expr)
     (let ((head (car expr)))
       (cond
         ((string= head "quote") (car (cdr expr)))
         ((string= head "if") (eval-if expr env state limits))
         ((string= head "let") (eval-let expr env state limits))
         ((string= head "lambda") (eval-lambda expr env))
         ((string= head "define") (eval-define expr env state limits))
         ((string= head "begin") (eval-begin (cdr expr) env state limits))
         ((string= head "and") (eval-and (cdr expr) env state limits))
         ((string= head "or") (eval-or (cdr expr) env state limits))
         (t (eval-application expr env state limits)))))

    ;; WardLisp nil is self-evaluating
    ((wardlisp-nil-p expr) expr)

    (t (error 'wardlisp-runtime-error
              :message (format nil "Cannot evaluate: ~A" expr)))))

;;; --- Special Forms ---

(defun eval-if (expr env state limits)
  "(if test then else)"
  (let ((test-val (eval-expr (second* expr) env state limits)))
    (if (wardlisp-truthy-p test-val)
        (eval-expr (third* expr) env state limits)
        (if (fourth* expr)
            (eval-expr (fourth* expr) env state limits)
            wardlisp-nil))))

(defun eval-let (expr env state limits)
  "(let ((var val) ...) body...)"
  (let* ((bindings-form (second* expr))
         (body (cddr* expr))
         (bindings (mapcar
                    (lambda (b)
                      (cons (car-of b)
                            (eval-expr (second-of b) env state limits)))
                    (wardlisp-list->cl-list bindings-form))))
    (let ((new-env (env-extend env bindings)))
      (eval-body body new-env state limits))))

(defun eval-lambda (expr env)
  "(lambda (params...) body...)"
  (let ((params (mapcar #'identity
                        (wardlisp-list->cl-list (second* expr))))
        (body (cddr* expr)))
    (make-closure params (wardlisp-list->cl-list body) env)))

(defun eval-define (expr env state limits)
  "(define name expr) or (define (name params...) body...)"
  (let ((target (second* expr)))
    (if (consp target)
        ;; (define (f x y) body...) => sugar for (define f (lambda (x y) body...))
        (let* ((name (car target))
               (params (wardlisp-list->cl-list (cdr target)))
               (body (cddr* expr))
               (closure (make-closure params (wardlisp-list->cl-list body) env)))
          (env-define! env name closure)
          closure)
        ;; (define name expr)
        (let ((value (eval-expr (third* expr) env state limits)))
          (env-define! env target value)
          value))))

(defun eval-begin (exprs env state limits)
  "(begin expr...)"
  (eval-body (wardlisp-list->cl-list exprs) env state limits))

(defun eval-and (exprs env state limits)
  "(and expr...) - short-circuit"
  (let ((result wardlisp-true))
    (dolist (e (wardlisp-list->cl-list exprs) result)
      (setf result (eval-expr e env state limits))
      (unless (wardlisp-truthy-p result)
        (return wardlisp-false)))))

(defun eval-or (exprs env state limits)
  "(or expr...) - short-circuit"
  (dolist (e (wardlisp-list->cl-list exprs) wardlisp-false)
    (let ((val (eval-expr e env state limits)))
      (when (wardlisp-truthy-p val)
        (return val)))))

;;; --- Function Application ---

(defun eval-application (expr env state limits)
  "Evaluate a function application: (func arg...)"
  (let ((func (eval-expr (car expr) env state limits))
        (args (mapcar (lambda (a) (eval-expr a env state limits))
                      (wardlisp-list->cl-list (cdr expr)))))
    (cond
      ;; Built-in function (CL function from builtins registry)
      ((functionp func)
       (handler-case (funcall func args)
         (error (e)
           (error 'wardlisp-runtime-error
                  :message (format nil "Built-in error: ~A" e)))))

      ;; WardLisp closure
      ((wardlisp-closure-p func)
       (let ((params (closure-params func))
             (body (closure-body func))
             (closure-env (closure-env func)))
         (unless (= (length params) (length args))
           (error 'wardlisp-runtime-error
                  :message (format nil "Expected ~D arguments, got ~D"
                                   (length params) (length args))))
         (let ((bindings (mapcar #'cons params args))
               (new-depth (1+ (execution-state-current-depth state))))
           (setf (execution-state-current-depth state) new-depth)
           (check-depth! state limits)
           (unwind-protect
                (let ((new-env (env-extend closure-env bindings)))
                  (eval-body body new-env state limits))
             (decf (execution-state-current-depth state))))))

      (t (error 'wardlisp-runtime-error
                :message (format nil "Not a function: ~A"
                                 (wardlisp->string func)))))))

;;; --- Helpers ---

(defun eval-body (forms env state limits)
  "Evaluate a list of forms, returning the last value."
  (let ((result wardlisp-nil))
    (dolist (form forms result)
      (setf result (eval-expr form env state limits)))))

(defun wardlisp-list->cl-list (wl)
  "Convert a WardLisp list to a CL list."
  (if (wardlisp-nil-p wl)
      nil
      (cons (car wl) (wardlisp-list->cl-list (cdr wl)))))

;; Safe accessors for cons-based WardLisp forms
(defun second* (expr) (car (cdr expr)))
(defun third* (expr) (car (cdr (cdr expr))))
(defun fourth* (expr) (car (cdr (cdr (cdr expr)))))
(defun cddr* (expr) (cdr (cdr expr)))
(defun car-of (b) (if (consp b) (car b) b))
(defun second-of (b) (if (consp b) (car (cdr b)) wardlisp-nil))

;;; --- Public API ---

(defun eval-program (source &key (limits (make-execution-limits)))
  "Evaluate a WardLisp program string. Returns an execution-result struct.
Never signals — all errors are captured in the result."
  (let ((state (make-execution-state))
        (env (env-extend (make-env) nil)))
    (handler-case
        (let* ((forms (wardlisp-read-all source))
               (value (eval-body forms env state limits)))
          (make-execution-result
           :value value
           :fuel-used (execution-state-fuel-used state)
           :cons-used (execution-state-cons-used state)
           :depth-reached (execution-state-max-depth-reached state)
           :output (get-output-stream-string
                    (execution-state-output-stream state))))
      (error (e)
        (make-execution-result
         :value wardlisp-nil
         :fuel-used (execution-state-fuel-used state)
         :cons-used (execution-state-cons-used state)
         :depth-reached (execution-state-max-depth-reached state)
         :output (get-output-stream-string
                  (execution-state-output-stream state))
         :error (format nil "~A" e))))))
```

**Step 4: Run test — Expected: All PASS**

**Step 5: Commit**

```bash
git add wardlisp/evaluator.lisp tests/wardlisp/evaluator.lisp
git commit -m "feat(wardlisp): add core evaluator with fuel/cons/depth limits"
```

---

### Task 6: Register WardLisp in ASDF + Integration Test

**Files:**
- Modify: `recurya.asd`

**Step 1: Add WardLisp systems to recurya.asd**

Add these to the main system's `:depends-on`:
```lisp
;; WardLisp language
"recurya/wardlisp/types"
"recurya/wardlisp/environment"
"recurya/wardlisp/reader"
"recurya/wardlisp/builtins"
"recurya/wardlisp/evaluator"
```

Add these to the test system's `:depends-on`:
```lisp
"recurya/tests/wardlisp/types"
"recurya/tests/wardlisp/environment"
"recurya/tests/wardlisp/reader"
"recurya/tests/wardlisp/builtins"
"recurya/tests/wardlisp/evaluator"
```

**Step 2: Load and run all tests**

```lisp
(asdf:load-system "recurya" :force t)
(asdf:test-system "recurya/tests")
```

Expected: All WardLisp tests + existing tests PASS

**Step 3: Integration smoke test via REPL**

```lisp
(recurya/wardlisp/evaluator:eval-program
  "(define fact (lambda (n) (if (= n 0) 1 (* n (fact (- n 1)))))) (fact 10)"
  :limits (recurya/wardlisp/evaluator:make-execution-limits :fuel 1000))
```

Expected: result-value = 3628800, fuel-used > 0, no error

**Step 4: Commit**

```bash
git add recurya.asd
git commit -m "feat(wardlisp): register wardlisp modules in ASDF system"
```

---

## Phase 2: Puzzle System + Web UI

### Task 7: Puzzle Data Structures and Grading Logic

**Files:**
- Create: `game/puzzle.lisp`
- Test: `tests/game/puzzle.lisp`

**Step 1: Write the failing test**

Create `tests/game/puzzle.lisp`:

```lisp
;;;; tests/game/puzzle.lisp --- Tests for puzzle grading system.

(defpackage #:recurya/tests/game/puzzle
  (:use #:cl #:rove)
  (:import-from #:recurya/wardlisp/types
                #:wardlisp-true
                #:wardlisp-false)
  (:import-from #:recurya/game/puzzle
                #:make-puzzle
                #:make-test-case
                #:run-puzzle
                #:puzzle-result-passed
                #:puzzle-result-failed
                #:puzzle-result-total
                #:puzzle-result-test-results
                #:puzzle-result-error
                #:test-result-passed-p
                #:test-result-expected
                #:test-result-actual))

(in-package #:recurya/tests/game/puzzle)

(defun make-simple-puzzle ()
  "A trivial puzzle: define (double x) that returns x*2."
  (make-puzzle
   :id :double
   :title "double"
   :description "Write (double x) that returns x * 2"
   :signature "(double x)"
   :test-cases (list
                (make-test-case :input "(double 3)" :expected 6
                                :description "double 3")
                (make-test-case :input "(double 0)" :expected 0
                                :description "double 0")
                (make-test-case :input "(double -5)" :expected -10
                                :description "double negative"))))

(deftest grading-correct-solution
  (testing "correct solution passes all tests"
    (let ((result (run-puzzle (make-simple-puzzle)
                              "(define (double x) (* x 2))")))
      (ok (= 3 (puzzle-result-passed result)))
      (ok (= 0 (puzzle-result-failed result)))
      (ok (null (puzzle-result-error result))))))

(deftest grading-wrong-solution
  (testing "wrong solution fails some tests"
    (let ((result (run-puzzle (make-simple-puzzle)
                              "(define (double x) (+ x x x))")))
      ;; (+ x x x) = 3x, not 2x for most values
      ;; actually (+ 3 3 3) = 9, not 6
      (ok (> (puzzle-result-failed result) 0)))))

(deftest grading-syntax-error
  (testing "syntax error is captured"
    (let ((result (run-puzzle (make-simple-puzzle) "(define double")))
      (ok (puzzle-result-error result)))))

(deftest grading-fuel-exhaustion
  (testing "infinite loop is caught"
    (let ((result (run-puzzle (make-simple-puzzle)
                              "(define (double x) (double x))")))
      (ok (puzzle-result-error result)))))

(deftest grading-metrics
  (testing "test results include actual values"
    (let* ((result (run-puzzle (make-simple-puzzle)
                               "(define (double x) (* x 2))"))
           (first-test (first (puzzle-result-test-results result))))
      (ok (test-result-passed-p first-test))
      (ok (= 6 (test-result-actual first-test))))))
```

**Step 2: Run test — Expected: FAIL**

**Step 3: Write implementation**

Create `game/puzzle.lisp`:

```lisp
;;;; game/puzzle.lisp --- Puzzle definition and grading system.
;;;;
;;;; Puzzles are defined as structs with test cases. The grading flow:
;;;; 1. Eval user code to register function definitions
;;;; 2. Run each test case in the same environment
;;;; 3. Compare results with expected values
;;;; 4. Collect metrics and return structured results

(defpackage #:recurya/game/puzzle
  (:use #:cl)
  (:import-from #:recurya/wardlisp/evaluator
                #:eval-program
                #:make-execution-limits
                #:execution-result-value
                #:execution-result-fuel-used
                #:execution-result-cons-used
                #:execution-result-depth-reached
                #:execution-result-output
                #:execution-result-error)
  (:import-from #:recurya/wardlisp/types
                #:wardlisp-equal
                #:wardlisp->string)
  (:export #:puzzle
           #:make-puzzle
           #:puzzle-id
           #:puzzle-title
           #:puzzle-description
           #:puzzle-signature
           #:puzzle-hint
           #:puzzle-test-cases
           #:puzzle-difficulty
           #:make-test-case
           #:test-case-input
           #:test-case-expected
           #:test-case-description
           #:run-puzzle
           #:puzzle-result
           #:puzzle-result-passed
           #:puzzle-result-failed
           #:puzzle-result-total
           #:puzzle-result-test-results
           #:puzzle-result-fuel-used
           #:puzzle-result-cons-used
           #:puzzle-result-depth-reached
           #:puzzle-result-error
           #:test-result
           #:test-result-passed-p
           #:test-result-expected
           #:test-result-actual
           #:test-result-description
           #:test-result-error))

(in-package #:recurya/game/puzzle)

;;; --- Data Structures ---

(defstruct puzzle
  "A WardLisp puzzle definition."
  (id nil :type keyword)
  (title "" :type string)
  (description "" :type string)
  (signature "" :type string)
  (hint nil)
  (test-cases nil :type list)
  (difficulty 1 :type fixnum))

(defstruct test-case
  "A single test case for a puzzle."
  (input "" :type string)
  (expected nil)
  (description "" :type string))

;;; --- Results ---

(defstruct test-result
  "Result of running one test case."
  (passed-p nil :type boolean)
  (expected nil)
  (actual nil)
  (description "" :type string)
  (error nil))

(defstruct puzzle-result
  "Aggregate result of grading a puzzle."
  (passed 0 :type fixnum)
  (failed 0 :type fixnum)
  (total 0 :type fixnum)
  (test-results nil :type list)
  (fuel-used 0 :type fixnum)
  (cons-used 0 :type fixnum)
  (depth-reached 0 :type fixnum)
  (error nil))

;;; --- Grading ---

(defparameter *puzzle-limits*
  (make-execution-limits :fuel 10000 :max-cons 5000 :max-depth 100 :max-output 4096)
  "Default resource limits for puzzle execution.")

(defun run-puzzle (puzzle user-code)
  "Grade user code against puzzle test cases. Returns a puzzle-result."
  (let ((test-results nil)
        (total-fuel 0)
        (total-cons 0)
        (max-depth 0))
    ;; First, try to evaluate the user code alone (define functions)
    ;; Then run each test case with the definitions prepended
    (dolist (tc (puzzle-test-cases puzzle))
      (let* ((full-code (format nil "~A~%~A" user-code (test-case-input tc)))
             (result (eval-program full-code :limits *puzzle-limits*)))
        (incf total-fuel (execution-result-fuel-used result))
        (incf total-cons (execution-result-cons-used result))
        (setf max-depth (max max-depth (execution-result-depth-reached result)))
        (if (execution-result-error result)
            (push (make-test-result
                   :passed-p nil
                   :expected (test-case-expected tc)
                   :actual nil
                   :description (test-case-description tc)
                   :error (execution-result-error result))
                  test-results)
            (let ((passed (wardlisp-equal
                           (execution-result-value result)
                           (test-case-expected tc))))
              (push (make-test-result
                     :passed-p passed
                     :expected (test-case-expected tc)
                     :actual (execution-result-value result)
                     :description (test-case-description tc))
                    test-results)))))
    (let ((results (nreverse test-results)))
      (make-puzzle-result
       :passed (count-if #'test-result-passed-p results)
       :failed (count-if-not #'test-result-passed-p results)
       :total (length results)
       :test-results results
       :fuel-used total-fuel
       :cons-used total-cons
       :depth-reached max-depth))))
```

**Step 4: Run test — Expected: All PASS**

**Step 5: Commit**

```bash
git add game/puzzle.lisp tests/game/puzzle.lisp
git commit -m "feat(game): add puzzle grading system"
```

---

### Task 8: Define 5 Puzzles

**Files:**
- Create: `game/puzzles/adjacent.lisp`
- Create: `game/puzzles/contains.lisp`
- Create: `game/puzzles/nearest-point.lisp`
- Create: `game/puzzles/safe-moves.lisp`
- Create: `game/puzzles/choose-action.lisp`
- Create: `game/puzzles/registry.lisp`

Each puzzle file defines one puzzle struct with test cases. The registry provides `get-puzzle` and `all-puzzles`.

**Step 1: Create registry + first 3 puzzles**

Create `game/puzzles/registry.lisp` — a central registry exporting `get-puzzle` and `all-puzzles` that returns puzzle structs by id.

Create puzzle files. Each exports a function `make-<name>-puzzle` returning a puzzle struct.

Example for `game/puzzles/adjacent.lisp`:
```lisp
(defpackage #:recurya/game/puzzles/adjacent
  (:use #:cl)
  (:import-from #:recurya/wardlisp/types #:wardlisp-true #:wardlisp-false)
  (:import-from #:recurya/game/puzzle #:make-puzzle #:make-test-case)
  (:export #:make-adjacent-puzzle))

(in-package #:recurya/game/puzzles/adjacent)

(defun make-adjacent-puzzle ()
  (make-puzzle
   :id :adjacent
   :title "adjacent?"
   :description "Write (adjacent? p1 p2) that returns #t if two (row col) points
are horizontally or vertically adjacent (Manhattan distance = 1)."
   :signature "(adjacent? p1 p2)"
   :hint "Use abs and arithmetic on car/cdr of each point."
   :difficulty 1
   :test-cases
   (list
    (make-test-case :input "(adjacent? '(0 0) '(0 1))" :expected wardlisp-true
                    :description "horizontal neighbor")
    (make-test-case :input "(adjacent? '(0 0) '(1 0))" :expected wardlisp-true
                    :description "vertical neighbor")
    (make-test-case :input "(adjacent? '(0 0) '(1 1))" :expected wardlisp-false
                    :description "diagonal is not adjacent")
    (make-test-case :input "(adjacent? '(0 0) '(0 0))" :expected wardlisp-false
                    :description "same point is not adjacent")
    (make-test-case :input "(adjacent? '(3 4) '(3 5))" :expected wardlisp-true
                    :description "non-origin adjacent"))))
```

Follow same pattern for contains, nearest-point. Puzzles 4-5 (safe-moves, choose-action) use arena state — create after Task 11 (arena).

**Step 2: Run tests via REPL — verify puzzles load and grade**

**Step 3: Commit**

```bash
git add game/puzzles/
git commit -m "feat(game): add puzzle definitions (adjacent, contains, nearest-point)"
```

---

### Task 9: WardLisp Web Routes (Puzzle)

**Files:**
- Create: `web/routes-wardlisp.lisp`

**Step 1: Create route handlers**

Create `web/routes-wardlisp.lisp` following the existing route pattern from `web/routes.lisp`:
- `wardlisp-home-handler` — GET `/wardlisp/`
- `puzzle-page-handler` — GET `/wardlisp/puzzle/:id`
- `puzzle-run-handler` — POST `/wardlisp/puzzle/:id/run` (returns HTMX fragment)
- `setup-wardlisp-routes` — registers all WardLisp routes on the app
- Uses `make-dynamic-handler` wrapper for REPL hot-reload

Key handler: `puzzle-run-handler`:
```lisp
(defun puzzle-run-handler (params)
  "Handle POST /wardlisp/puzzle/:id/run - execute and grade user code."
  (let* ((id (intern (string-upcase (get-path-param params :id)) :keyword))
         (code (get-param params "code"))
         (puzzle (get-puzzle id)))
    (if puzzle
        (let ((result (run-puzzle puzzle code)))
          (html-response
           (recurya/web/ui/puzzle:render-result result)))
        (html-response "<div class=\"error\">Puzzle not found</div>"
                       :status 404))))
```

**Step 2: Wire into app.lisp**

Add call to `setup-wardlisp-routes` in `make-recurya-app` or `setup-routes`.

**Step 3: Commit**

```bash
git add web/routes-wardlisp.lisp
git commit -m "feat(web): add WardLisp puzzle routes"
```

---

### Task 10: Puzzle UI Templates

**Files:**
- Create: `web/ui/wardlisp-home.lisp`
- Create: `web/ui/puzzle.lisp`
- Create: `web/ui/wardlisp-styles.lisp`

**Step 1: Create templates**

`web/ui/puzzle.lisp` exports:
- `render` — full puzzle page with editor + test cases
- `render-result` — HTMX fragment for the result panel

Uses existing patterns: `spinneret:with-html-string`, page-shell from layout, HTMX attrs.

The code editor is a `<textarea>` with monospace font. The run button uses `hx-post` targeting `#result-panel`.

**Step 2: Test in browser**

Start app, navigate to `/wardlisp/`, click puzzle, write code, click Run.

**Step 3: Commit**

```bash
git add web/ui/wardlisp-home.lisp web/ui/puzzle.lisp web/ui/wardlisp-styles.lisp
git commit -m "feat(web): add puzzle UI templates with HTMX execution"
```

---

### Task 10b: Update ASDF for Phase 2

**Files:**
- Modify: `recurya.asd`

Add all new game and web modules to the ASDF system definition.

```bash
git add recurya.asd
git commit -m "feat: register puzzle system and UI modules in ASDF"
```

---

## Phase 3: Arena System

### Task 11: Arena State and Simulator

**Files:**
- Create: `game/arena.lisp`
- Create: `game/scenario.lisp`
- Test: `tests/game/arena.lisp`

**Step 1: Write failing tests for arena**

Test cases:
- Movement: bot moves up/down/left/right correctly
- Wall collision: bot stays in place
- Boundary: bot stays in bounds
- Pickup: score increments, resource removed
- Full simulation: 20 turns complete
- Determinism: same code → same result
- Enemy logic: greedy bot moves toward resource

**Step 2: Implement `game/arena.lisp`**

Core functions:
- `make-arena-state` — initial state from scenario
- `state->wardlisp-alist` — convert CL state to WardLisp alist
- `apply-action` — apply one action, return new state
- `enemy-decide-action` — greedy nearest-resource logic
- `simulate-arena` — run 20 turns, return all frames

**Step 3: Implement `game/scenario.lisp`**

- `default-scenario` — 7x7 grid with walls, resources, positions

**Step 4: Run tests — Expected: All PASS**

**Step 5: Commit**

```bash
git add game/arena.lisp game/scenario.lisp tests/game/arena.lisp
git commit -m "feat(game): add arena simulator with 7x7 grid"
```

---

### Task 12: Arena Web Routes + UI

**Files:**
- Modify: `web/routes-wardlisp.lisp` (add arena routes)
- Create: `web/ui/arena.lisp`

**Step 1: Add arena routes**

- `arena-page-handler` — GET `/wardlisp/arena`
- `arena-run-handler` — POST `/wardlisp/arena/run` (returns all frames as HTMX fragment)

**Step 2: Create arena UI template**

`web/ui/arena.lisp` exports:
- `render` — full arena page with editor + empty grid
- `render-result` — HTMX fragment with all 20 frames (hidden divs), turn controls, log, score

Grid rendering: HTML `<table>` with cells styled by content (wall=dark, resource=diamond, bot=circle, enemy=cross).

Turn stepping: minimal JS (`<script>` inline) toggling `hidden` attribute on `.frame` divs.

**Step 3: Test in browser**

**Step 4: Commit**

```bash
git add web/routes-wardlisp.lisp web/ui/arena.lisp
git commit -m "feat(web): add arena UI with grid visualization"
```

---

### Task 13: Arena-Dependent Puzzles (4-5)

**Files:**
- Create: `game/puzzles/safe-moves.lisp`
- Create: `game/puzzles/choose-action.lisp`
- Modify: `game/puzzles/registry.lisp` (register puzzles 4-5)

Now that arena state structure is defined, create puzzles 4-5 that use it as input.

**Step 1: Define puzzles with arena state test cases**

**Step 2: Register in registry**

**Step 3: Commit**

```bash
git add game/puzzles/safe-moves.lisp game/puzzles/choose-action.lisp game/puzzles/registry.lisp
git commit -m "feat(game): add arena-dependent puzzles (safe-moves, choose-action)"
```

---

### Task 13b: Update ASDF for Phase 3

Add all arena modules to ASDF.

```bash
git add recurya.asd
git commit -m "feat: register arena system modules in ASDF"
```

---

## Phase 4: Polish + Validation

### Task 14: Language Reference Page

**Files:**
- Create: `web/ui/reference.lisp`
- Modify: `web/routes-wardlisp.lisp` (add GET /wardlisp/reference)

Document all special forms, built-in functions, types, and resource limits.
Include code examples for each function.

```bash
git commit -m "feat(web): add WardLisp language reference page"
```

---

### Task 15: Error Message Improvements

**Files:**
- Modify: `wardlisp/evaluator.lisp`
- Modify: `wardlisp/reader.lisp`

Improve error messages to include:
- Line/position information from reader
- Clear explanation of what went wrong
- Suggestion for common mistakes

```bash
git commit -m "fix(wardlisp): improve error messages with position info"
```

---

### Task 16: Print Builtin with Output Limits

**Files:**
- Modify: `wardlisp/builtins.lisp`
- Modify: `wardlisp/evaluator.lisp`
- Add tests for output limit

Wire `make-print-builtin` into the evaluator so `(print x)` writes to the execution state's output stream with limit checking.

```bash
git commit -m "feat(wardlisp): wire print builtin with output limit"
```

---

### Task 17: Cons Tracking in Evaluator

**Files:**
- Modify: `wardlisp/evaluator.lisp`
- Modify: `wardlisp/builtins.lisp`

Add `check-cons!` calls wherever new cons cells are created:
- `cons` builtin
- `list` builtin
- `append` builtin
- `list-to-wardlisp` in reader

```bash
git commit -m "feat(wardlisp): add cons allocation tracking"
```

---

### Task 18: Determinism + Isolation Verification Tests

**Files:**
- Create: `tests/wardlisp/integration.lisp`

Test:
- Same program + same input → identical result (run 10 times)
- Error in one execution doesn't affect next execution
- Resource limits reset between executions

```bash
git commit -m "test(wardlisp): add determinism and isolation verification"
```

---

### Task 19: Final ASDF Update + Full Test Suite

**Files:**
- Modify: `recurya.asd`
- Modify: `tests/all.lisp`

Register all new test modules. Run full suite.

```bash
(asdf:test-system "recurya/tests")
```

Expected: ALL tests PASS (existing blog tests + all WardLisp tests).

```bash
git commit -m "feat: complete WardLisp MVP - all tests passing"
```

---

## Task Dependency Graph

```
Phase 1 (sequential):
  Task 1 (types) → Task 2 (env) → Task 3 (reader) → Task 4 (builtins) → Task 5 (evaluator) → Task 6 (ASDF)

Phase 2 (after Phase 1):
  Task 7 (puzzle logic) → Task 8 (puzzle definitions) → Task 9 (routes) → Task 10 (UI) → Task 10b (ASDF)

Phase 3 (after Phase 2):
  Task 11 (arena) → Task 12 (arena UI) → Task 13 (puzzles 4-5) → Task 13b (ASDF)

Phase 4 (after Phase 3):
  Tasks 14-18 (parallel) → Task 19 (final)
```

## Summary

| Phase | Tasks | Estimated Commits |
|-------|-------|-------------------|
| 1: Evaluator | 6 tasks | 6 commits |
| 2: Puzzles + UI | 5 tasks | 5 commits |
| 3: Arena | 4 tasks | 4 commits |
| 4: Polish | 6 tasks | 6 commits |
| **Total** | **21 tasks** | **21 commits** |
