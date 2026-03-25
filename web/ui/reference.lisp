;;;; web/ui/reference.lisp --- WardLisp language reference page.

(defpackage #:recurya/web/ui/reference
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:export #:render))

(in-package #:recurya/web/ui/reference)

(defparameter *styles*
  "body { font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
         margin: 0; background: #0f172a; color: #e2e8f0; line-height: 1.6; }
main { max-width: 800px; margin: 0 auto; padding: 2rem 1.5rem 4rem; }
a { color: #38bdf8; }
h1 { font-size: 1.8rem; color: #f8fafc; text-align: center; margin-bottom: 0.5rem; }
.subtitle { text-align: center; color: #94a3b8; margin-bottom: 2.5rem; }
h2 { font-size: 1.25rem; color: #38bdf8; border-bottom: 1px solid #334155;
     padding-bottom: 0.5rem; margin-top: 2.5rem; }
h3 { font-size: 1rem; color: #94a3b8; margin-top: 1.5rem; }
.breadcrumb { color: #64748b; font-size: 0.9rem; margin-bottom: 1.5rem; }
.breadcrumb a { color: #38bdf8; text-decoration: none; }
code { font-family: 'SF Mono', 'Fira Code', monospace; background: #1e293b;
       padding: 0.15rem 0.4rem; border-radius: 4px; font-size: 0.9rem; color: #e2e8f0; }
pre { background: #1e293b; border-radius: 8px; padding: 1rem; overflow-x: auto;
      font-family: 'SF Mono', 'Fira Code', monospace; font-size: 0.9rem;
      line-height: 1.5; border: 1px solid #334155; }
pre code { background: none; padding: 0; }
.entry { margin-bottom: 1rem; }
.entry-sig { font-family: monospace; font-weight: 700; color: #38bdf8; }
.entry-desc { color: #94a3b8; font-size: 0.95rem; margin-left: 1rem; }
table { width: 100%; border-collapse: collapse; margin: 1rem 0; }
th, td { text-align: left; padding: 0.5rem 0.75rem; border-bottom: 1px solid #334155; }
th { color: #94a3b8; font-weight: 600; font-size: 0.85rem; text-transform: uppercase; }
td code { font-size: 0.85rem; }
.limit-table td:first-child { font-weight: 600; color: #fbbf24; }")

(defun render ()
  "Render the WardLisp language reference page."
  (with-html-string
    (:doctype)
    (:html
     (:head (:meta :charset "utf-8")
      (:meta :name "viewport" :content "width=device-width, initial-scale=1")
      (:title "WardLisp Reference")
      (:style (:raw *styles*)))
     (:body
      (:main
       (:div :class "breadcrumb"
        (:a :href "/wardlisp/" "WardLisp") " / Reference")
       (:h1 "WardLisp Reference")
       (:p :class "subtitle" "A safe, restricted Lisp dialect for learning")

       ;; Types
       (:h2 "Types")
       (:table
        (:tr (:th "Type") (:th "Examples") (:th "Notes"))
        (:tr (:td "Integer") (:td (:code "42") ", " (:code "-7") ", " (:code "0")) (:td "Whole numbers"))
        (:tr (:td "Boolean") (:td (:code "#t") ", " (:code "#f")) (:td "True and false"))
        (:tr (:td "Keyword") (:td (:code ":up") ", " (:code ":foo")) (:td "Colon-prefixed symbols"))
        (:tr (:td "List") (:td (:code "'(1 2 3)")) (:td "Cons cells ending in nil"))
        (:tr (:td "Nil") (:td (:code "'()")) (:td "Empty list / false-ish"))
        (:tr (:td "Function") (:td (:code "(lambda (x) x)")) (:td "Closures with lexical scope")))

       ;; Special Forms
       (:h2 "Special Forms")
       (:div :class "entry"
        (:div :class "entry-sig" "(define name expr)")
        (:div :class "entry-desc" "Bind a value to a name in the current scope."))
       (:div :class "entry"
        (:div :class "entry-sig" "(define (name params...) body...)")
        (:div :class "entry-desc" "Shorthand for defining a function."))
       (:div :class "entry"
        (:div :class "entry-sig" "(lambda (params...) body...)")
        (:div :class "entry-desc" "Create an anonymous function (closure)."))
       (:div :class "entry"
        (:div :class "entry-sig" "(if test then else)")
        (:div :class "entry-desc" "Conditional. Only #f and '() are falsy."))
       (:div :class "entry"
        (:div :class "entry-sig" "(let ((var val) ...) body...)")
        (:div :class "entry-desc" "Local bindings evaluated in order."))
       (:div :class "entry"
        (:div :class "entry-sig" "(begin expr...)")
        (:div :class "entry-desc" "Evaluate expressions in sequence, return last."))
       (:div :class "entry"
        (:div :class "entry-sig" "(quote expr) or 'expr")
        (:div :class "entry-desc" "Return expression unevaluated."))
       (:div :class "entry"
        (:div :class "entry-sig" "(and expr...)")
        (:div :class "entry-desc" "Short-circuit logical AND."))
       (:div :class "entry"
        (:div :class "entry-sig" "(or expr...)")
        (:div :class "entry-desc" "Short-circuit logical OR."))

       ;; Arithmetic
       (:h2 "Built-in Functions")
       (:h3 "Arithmetic")
       (:pre (:code "(+ 1 2 3)    ; => 6
(- 10 3)      ; => 7
(* 2 3 4)     ; => 24
(/ 10 2)      ; => 5
(mod 7 3)     ; => 1
(abs -5)      ; => 5"))

       ;; Comparison
       (:h3 "Comparison")
       (:pre (:code "(= 3 3)      ; => #t
(< 1 2)       ; => #t
(> 5 3)       ; => #t
(<= 3 3)      ; => #t
(>= 4 4)      ; => #t
(equal? x y)  ; deep equality
(not #f)      ; => #t"))

       ;; Lists
       (:h3 "List Operations")
       (:pre (:code "(cons 1 '(2 3))      ; => (1 2 3)
(car '(1 2 3))        ; => 1
(cdr '(1 2 3))        ; => (2 3)
(list 1 2 3)          ; => (1 2 3)
(null? '())           ; => #t
(pair? '(1 2))        ; => #t
(length '(1 2 3))     ; => 3
(append '(1 2) '(3))  ; => (1 2 3)"))

       ;; Type Predicates
       (:h3 "Type Predicates")
       (:pre (:code "(number? 42)    ; => #t
(boolean? #t)   ; => #t
(symbol? :up)   ; => #t
(list? '(1))    ; => #t"))

       ;; Utility
       (:h3 "Utility")
       (:pre (:code "(alist-ref :key '((:key . val) (:other . 2)))  ; => val"))

       ;; Resource Limits
       (:h2 "Resource Limits")
       (:p "All executions are sandboxed with these limits:")
       (:table :class "limit-table"
        (:tr (:th "Resource") (:th "Limit") (:th "Description"))
        (:tr (:td "Fuel") (:td "10,000 steps") (:td "Maximum evaluation steps"))
        (:tr (:td "Cons") (:td "5,000 cells") (:td "Maximum list allocations"))
        (:tr (:td "Depth") (:td "100 levels") (:td "Maximum recursion depth"))
        (:tr (:td "Output") (:td "4,096 bytes") (:td "Maximum printed output")))

       ;; Examples
       (:h2 "Examples")
       (:h3 "Recursive function")
       (:pre (:code "(define (factorial n)
  (if (= n 0) 1
      (* n (factorial (- n 1)))))
(factorial 10)  ; => 3628800"))

       (:h3 "Higher-order function")
       (:pre (:code "(define (map f lst)
  (if (null? lst) '()
      (cons (f (car lst))
            (map f (cdr lst)))))
(map (lambda (x) (* x x)) '(1 2 3 4))  ; => (1 4 9 16)"))

       (:h3 "Working with alists")
       (:pre (:code "(define state '((:pos . (3 4)) (:score . 5)))
(alist-ref :pos state)    ; => (3 4)
(alist-ref :score state)  ; => 5")))))))
