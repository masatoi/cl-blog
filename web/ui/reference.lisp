;;;; web/ui/reference.lisp --- WardLisp language reference page.

(defpackage #:recurya/web/ui/reference
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:recurya/web/i18n/core
                #:tr)
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
      (:title (tr :wardlisp.reference.page_title))
      (:style (:raw *styles*)))
     (:body
      (:main
       (:div :class "breadcrumb"
        (:a :href "/wardlisp/" "WardLisp") (tr :wardlisp.reference.breadcrumb_reference))
       (:h1 (tr :wardlisp.reference.heading))
       (:p :class "subtitle" (tr :wardlisp.reference.subtitle))

       ;; Types
       (:h2 (tr :wardlisp.reference.section_types))
       (:table
        (:tr (:th (tr :wardlisp.reference.types_col_type)) (:th (tr :wardlisp.reference.types_col_examples)) (:th (tr :wardlisp.reference.types_col_notes)))
        (:tr (:td (tr :wardlisp.reference.type_integer)) (:td (:code "42") ", " (:code "-7") ", " (:code "0")) (:td (tr :wardlisp.reference.type_integer_note)))
        (:tr (:td (tr :wardlisp.reference.type_float)) (:td (:code "3.14") ", " (:code "-0.5") ", " (:code "1e3")) (:td (tr :wardlisp.reference.type_float_note)))
        (:tr (:td (tr :wardlisp.reference.type_boolean)) (:td (:code "t") ", " (:code "nil")) (:td (tr :wardlisp.reference.type_boolean_note)))
        (:tr (:td (tr :wardlisp.reference.type_symbol)) (:td (:code "'up") ", " (:code "'foo")) (:td (tr :wardlisp.reference.type_symbol_note)))
        (:tr (:td (tr :wardlisp.reference.type_pair)) (:td (:code "(cons 1 2)") " => " (:code "(1 . 2)")) (:td (tr :wardlisp.reference.type_pair_note)))
        (:tr (:td (tr :wardlisp.reference.type_list)) (:td (:code "'(1 2 3)")) (:td (tr :wardlisp.reference.type_list_note)))
        (:tr (:td (tr :wardlisp.reference.type_nil)) (:td (:code "nil")) (:td (tr :wardlisp.reference.type_nil_note)))
        (:tr (:td (tr :wardlisp.reference.type_function)) (:td (:code "(lambda (x) x)")) (:td (tr :wardlisp.reference.type_function_note))))

       ;; Special Forms
       (:h2 (tr :wardlisp.reference.section_special_forms))
       (:div :class "entry"
        (:div :class "entry-sig" "(define name expr)")
        (:div :class "entry-desc" (tr :wardlisp.reference.sf_define_desc)))
       (:div :class "entry"
        (:div :class "entry-sig" "(define (name params...) body...)")
        (:div :class "entry-desc" (tr :wardlisp.reference.sf_define_fn_desc)))
       (:div :class "entry"
        (:div :class "entry-sig" "(lambda (params...) body...)")
        (:div :class "entry-desc" (tr :wardlisp.reference.sf_lambda_desc)))
       (:div :class "entry"
        (:div :class "entry-sig" "(if test then else)")
        (:div :class "entry-desc" (tr :wardlisp.reference.sf_if_desc)))
       (:div :class "entry"
        (:div :class "entry-sig" "(let ((var val) ...) body...)")
        (:div :class "entry-desc" (tr :wardlisp.reference.sf_let_desc)))
       (:div :class "entry"
        (:div :class "entry-sig" "(let* ((var val) ...) body...)")
        (:div :class "entry-desc" (tr :wardlisp.reference.sf_letstar_desc)))
       (:div :class "entry"
        (:div :class "entry-sig" "(begin expr...)")
        (:div :class "entry-desc" (tr :wardlisp.reference.sf_begin_desc)))
       (:div :class "entry"
        (:div :class "entry-sig" "(quote expr) or 'expr")
        (:div :class "entry-desc" (tr :wardlisp.reference.sf_quote_desc)))
       (:div :class "entry"
        (:div :class "entry-sig" "(and expr...)")
        (:div :class "entry-desc" (tr :wardlisp.reference.sf_and_desc)))
       (:div :class "entry"
        (:div :class "entry-sig" "(or expr...)")
        (:div :class "entry-desc" (tr :wardlisp.reference.sf_or_desc)))
       (:div :class "entry"
        (:div :class "entry-sig" "(cond (test expr...) ...)")
        (:div :class "entry-desc" (tr :wardlisp.reference.sf_cond_desc)))
       (:div :class "entry"
        (:div :class "entry-sig" "(apply func args-list)")
        (:div :class "entry-desc" (tr :wardlisp.reference.sf_apply_desc)))

       ;; Arithmetic
       (:h2 (tr :wardlisp.reference.section_builtins))
       (:h3 (tr :wardlisp.reference.subsection_arithmetic))
       (:pre (:code "(+ 1 2 3)       ; => 6
(- 10 3)         ; => 7
(* 2 3 4)        ; => 24
(/ 6 3)          ; => 2   (exact: integer)
(/ 7 2)          ; => 3.5 (inexact: float)
(quotient 10 3)  ; => 3   (integer division)
(mod 7 3)        ; => 1"))

       ;; Comparison
       (:h3 (tr :wardlisp.reference.subsection_comparison))
       (:pre (:code "(= 3 3)      ; => t
(< 1 2)       ; => t
(> 5 3)       ; => t
(<= 3 3)      ; => t
(>= 4 4)      ; => t"))

       ;; Lists
       (:h3 (tr :wardlisp.reference.subsection_list_operations))
       (:pre (:code "(cons 1 '(2 3))      ; => (1 2 3)
(cons 1 2)            ; => (1 . 2)
(car '(1 2 3))        ; => 1
(cdr '(1 2 3))        ; => (2 3)
(list 1 2 3)          ; => (1 2 3)
(null? '())           ; => t
(atom? 42)            ; => t  (non-pair)
(length '(1 2 3))     ; => 3
(append '(1 2) '(3))  ; => (1 2 3)"))

       ;; Type Predicates
       (:h3 (tr :wardlisp.reference.subsection_type_predicates))
       (:pre (:code "(null? x)       ; => t if x is nil
(atom? x)       ; => t if x is not a pair
(integer? 42)   ; => t
(number? 3.14)  ; => t  (integer or float)
(not nil)       ; => t
(eq? x y)       ; shallow equality
(equal? x y)    ; deep structural equality"))

       ;; Utility
       (:h3 (tr :wardlisp.reference.subsection_utility))
       (:pre (:code "(print 42)      ; prints to output, returns value"))

       ;; Resource Limits
       (:h2 (tr :wardlisp.reference.section_resource_limits))
       (:p (tr :wardlisp.reference.limits_intro))
       (:table :class "limit-table"
        (:tr (:th (tr :wardlisp.reference.limits_col_resource)) (:th (tr :wardlisp.reference.limits_col_limit)) (:th (tr :wardlisp.reference.limits_col_description)))
        (:tr (:td (tr :wardlisp.reference.limit_fuel)) (:td (tr :wardlisp.reference.limit_fuel_value)) (:td (tr :wardlisp.reference.limit_fuel_desc)))
        (:tr (:td (tr :wardlisp.reference.limit_cons)) (:td (tr :wardlisp.reference.limit_cons_value)) (:td (tr :wardlisp.reference.limit_cons_desc)))
        (:tr (:td (tr :wardlisp.reference.limit_depth)) (:td (tr :wardlisp.reference.limit_depth_value)) (:td (tr :wardlisp.reference.limit_depth_desc)))
        (:tr (:td (tr :wardlisp.reference.limit_output)) (:td (tr :wardlisp.reference.limit_output_value)) (:td (tr :wardlisp.reference.limit_output_desc)))
        (:tr (:td (tr :wardlisp.reference.limit_timeout)) (:td (tr :wardlisp.reference.limit_timeout_value)) (:td (tr :wardlisp.reference.limit_timeout_desc))))

       ;; Examples
       (:h2 (tr :wardlisp.reference.section_examples))
       (:h3 (tr :wardlisp.reference.example_recursive))
       (:pre (:code "(define (factorial n)
  (if (= n 0) 1
      (* n (factorial (- n 1)))))
(factorial 10)  ; => 3628800"))

       (:h3 (tr :wardlisp.reference.example_higher_order))
       (:pre (:code "(define (map f lst)
  (if (null? lst) '()
      (cons (f (car lst))
            (map f (cdr lst)))))
(map (lambda (x) (* x x)) '(1 2 3 4))  ; => (1 4 9 16)"))

       (:h3 (tr :wardlisp.reference.example_alists))
       (:pre (:code ";; Define your own alist-ref helper:
(define (alist-ref key alist)
  (cond ((null? alist) nil)
        ((equal? key (car (car alist))) (car (cdr (car alist))))
        (t (alist-ref key (cdr alist)))))

(define state '((pos (3 4)) (score 5)))
(alist-ref 'pos state)    ; => (3 4)
(alist-ref 'score state)  ; => 5")))))))
