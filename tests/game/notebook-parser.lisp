;;;; tests/game/notebook-parser.lisp --- Tests for notebook-parser package.

(defpackage #:recurya/tests/game/notebook-parser
  (:use #:cl #:rove)
  (:import-from #:recurya/game/notebook-parser
                #:parse-notebook-body
                #:cells->body-md
                #:render-cell-prose-html)
  (:import-from #:recurya/game/notebook
                #:make-cell
                #:cell-id
                #:cell-kind
                #:cell-body
                #:cell-description
                #:cell-test-cases
                #:cell-gated-p))

(in-package #:recurya/tests/game/notebook-parser)

(deftest single-prose-cell
  (let ((body "===prose===
Lispは式を評価する言語です。"))
    (multiple-value-bind (cells errors) (parse-notebook-body body)
      (ok (null errors))
      (ok (= 1 (length cells)))
      (let ((c (first cells)))
        (ok (eq :prose (cell-kind c)))
        (ok (search "Lispは式を評価する言語です。" (cell-body c)))
        (ok (stringp (cell-id c)))))))

(deftest single-eval-cell
  (let ((body "===eval===
(+ 137 349)"))
    (multiple-value-bind (cells errors) (parse-notebook-body body)
      (ok (null errors))
      (ok (= 1 (length cells)))
      (ok (eq :code-eval (cell-kind (first cells))))
      (ok (search "(+ 137 349)" (cell-body (first cells)))))))

(deftest prose-then-eval
  (let ((body "===prose===
Hello.

===eval===
(+ 1 2)"))
    (multiple-value-bind (cells errors) (parse-notebook-body body)
      (ok (null errors))
      (ok (= 2 (length cells)))
      (ok (eq :prose      (cell-kind (first cells))))
      (ok (eq :code-eval  (cell-kind (second cells)))))))

(deftest single-exercise-with-expect
  (let ((body "===exercise: 三項の和===
; ここに式を書く

===expect: 三項の和===
508"))
    (multiple-value-bind (cells errors) (parse-notebook-body body)
      (ok (null errors))
      (ok (= 1 (length cells)))
      (let ((c (first cells)))
        (ok (eq :code-exercise (cell-kind c)))
        (ok (string= "三項の和" (cell-description c)))
        (ok (= 1 (length (cell-test-cases c))))))))

(deftest single-solution-cell
  (let ((body "===solution: my-square===
(define (my-square x) (* x x))"))
    (multiple-value-bind (cells errors) (parse-notebook-body body)
      (ok (null errors))
      (ok (= 1 (length cells)))
      (let ((c (first cells)))
        (ok (eq :code-solution (cell-kind c)))
        (ok (string= "my-square" (cell-description c)))
        (ok (search "(* x x)" (cell-body c)))))))

(deftest exercise-with-input-output-expect
  (let ((body "===exercise: zero?===
(define (zero? x) ???)

===expect===
input: (zero? 0)
output: t

===expect===
input: (zero? 5)
output: nil"))
    (multiple-value-bind (cells errors) (parse-notebook-body body)
      (ok (null errors))
      (ok (= 2 (length (cell-test-cases (first cells))))))))

(deftest expect-without-prior-exercise
  (let ((body "===expect===
1"))
    (multiple-value-bind (cells errors) (parse-notebook-body body)
      (declare (ignore cells))
      (ok (find-if (lambda (e) (search "expect" (getf e :message)))
                   errors)))))

(deftest exercise-missing-description
  (let ((body "===exercise===
(foo)"))
    (multiple-value-bind (cells errors) (parse-notebook-body body)
      (declare (ignore cells))
      (ok errors))))

(deftest unknown-header
  (let ((body "===banana===
peel"))
    (multiple-value-bind (cells errors) (parse-notebook-body body)
      (declare (ignore cells))
      (ok errors))))

(deftest empty-body-zero-cells
  (multiple-value-bind (cells errors) (parse-notebook-body "")
    (declare (ignore cells))
    (ok (find-if (lambda (e) (search "no cell" (getf e :message)))
                 errors))))

(deftest preserves-cell-id-on-match
  (let* ((body "===prose===
Hello.")
         (existing (list (make-cell :id "STABLE-ID" :kind :prose
                                    :body "Hello." :description ""))))
    (multiple-value-bind (cells errors) (parse-notebook-body body existing)
      (ok (null errors))
      (ok (string= "STABLE-ID" (cell-id (first cells)))))))

(deftest assigns-new-uuid-when-no-match
  (let ((body "===prose===
Different."))
    (multiple-value-bind (cells errors) (parse-notebook-body body)
      (declare (ignore errors))
      (ok (stringp (cell-id (first cells))))
      (ok (not (string= "STABLE-ID" (cell-id (first cells))))))))

(deftest roundtrip-prose
  (let ((body "===prose===
Hello world."))
    (let* ((cells1 (parse-notebook-body body))
           (md     (cells->body-md cells1))
           (cells2 (parse-notebook-body md)))
      (ok (= (length cells1) (length cells2)))
      (ok (string= (cell-body (first cells1)) (cell-body (first cells2)))))))

(deftest roundtrip-mixed
  (let* ((body "===prose===
Intro.

===eval===
(+ 1 2)

===exercise: sum===
; ?

===expect: sum===
3")
         (cells1 (parse-notebook-body body))
         (md     (cells->body-md cells1))
         (cells2 (parse-notebook-body md)))
    (ok (= (length cells1) (length cells2)))
    (loop for c1 in cells1 for c2 in cells2 do
          (ok (eq      (cell-kind c1) (cell-kind c2)))
          (ok (string= (cell-body c1) (cell-body c2))))))

(deftest roundtrip-with-solution
  (let* ((body "===exercise: square===
(define (square x) ???)

===expect: square===
4

===solution: square===
(define (square x) (* x x))")
         (cells1 (parse-notebook-body body))
         (md     (cells->body-md cells1))
         (cells2 (parse-notebook-body md)))
    (ok (= (length cells1) (length cells2)))
    (loop for c1 in cells1 for c2 in cells2 do
          (ok (eq      (cell-kind c1) (cell-kind c2)))
          (ok (string= (cell-body c1) (cell-body c2))))))

(deftest preserves-solution-cell-id
  (let* ((body "===solution: foo===
(define foo 1)")
         (existing (list (make-cell :id "STABLE-SOL" :kind :code-solution
                                    :body "(define foo 1)"
                                    :description "foo"))))
    (multiple-value-bind (cells errors) (parse-notebook-body body existing)
      (ok (null errors))
      (ok (string= "STABLE-SOL" (cell-id (first cells)))))))

(deftest renders-markdown-bold-and-strips-script
  (let ((html (render-cell-prose-html "**bold**

<script>x</script>")))
    (ok (search "<strong>bold</strong>" html))
    (ng (search "<script" html))))

(deftest scene-cell-roundtrip
  (let* ((body "===scene===
(list (list 'say \"アリス\" \"やあ\"))")
         (cells (parse-notebook-body body)))
    (ok (= 1 (length cells)))
    (ok (eq :scene (cell-kind (first cells))))
    (ok (search "(list 'say" (cell-body (first cells))))
    ;; render back and re-parse: kind/body stable
    (let* ((md (cells->body-md cells))
           (cells2 (parse-notebook-body md)))
      (ok (eq :scene (cell-kind (first cells2))))
      (ok (string= (cell-body (first cells)) (cell-body (first cells2)))))))

(deftest parse-solution-locked-sets-gated
  (testing "===solution-locked: desc=== yields a gated code-solution cell"
    (let* ((body (format nil "===solution-locked: ans===~%(define x 1)"))
           (cells (parse-notebook-body body))
           (c (first cells)))
      (ok (eq :code-solution (cell-kind c)))
      (ok (eq t (cell-gated-p c)))
      (ok (string= "ans" (cell-description c)))
      (ok (string= "(define x 1)" (cell-body c))))))

(deftest parse-solution-plain-is-not-gated
  (testing "===solution: desc=== yields a non-gated code-solution cell"
    (let* ((body (format nil "===solution: ans===~%(define x 1)"))
           (c (first (parse-notebook-body body))))
      (ok (eq :code-solution (cell-kind c)))
      (ok (null (cell-gated-p c))))))

(deftest gated-does-not-leak-across-cells
  (testing "gated resets at cell boundaries: only the -locked solution is gated"
    (let* ((body (format nil "===exercise: q===~%; ?~%~%===expect===~%1~%~%===solution-locked: a===~%(A)~%~%===solution: b===~%(B)~%~%===prose===~%after"))
           (cells (parse-notebook-body body))
           (sol-locked (find-if (lambda (c) (and (eq :code-solution (cell-kind c))
                                                 (string= "a" (cell-description c))))
                                cells))
           (sol-plain (find-if (lambda (c) (and (eq :code-solution (cell-kind c))
                                                (string= "b" (cell-description c))))
                               cells))
           (prose (find :prose cells :key #'cell-kind))
           (exercise (find :code-exercise cells :key #'cell-kind)))
      (ok (eq t (cell-gated-p sol-locked)) "locked solution is gated")
      (ok (null (cell-gated-p sol-plain)) "plain solution after is not gated (no forward leak)")
      (ok (null (cell-gated-p prose)) "prose after is not gated")
      (ok (null (cell-gated-p exercise)) "exercise before is not gated"))))

(deftest cells->body-md-writes-solution-locked
  (testing "a gated solution serializes with the -locked header"
    (let ((cells (list (make-cell :kind :code-solution :description "ans"
                                  :body "(define x 1)" :gated-p t))))
      (ok (string= (format nil "===solution-locked: ans===~%(define x 1)")
                   (cells->body-md cells))))))

(deftest cells->body-md-writes-plain-solution
  (testing "a non-gated solution serializes with the plain header"
    (let ((cells (list (make-cell :kind :code-solution :description "ans"
                                  :body "(define x 1)" :gated-p nil))))
      (ok (string= (format nil "===solution: ans===~%(define x 1)")
                   (cells->body-md cells))))))

(deftest solution-gated-round-trips
  (testing "parse -> serialize -> parse preserves gated for both variants"
    (let* ((body (format nil "===exercise: q===~%; ?~%~%===expect===~%1~%~%===solution-locked: a===~%(+ 1 0)~%~%===solution: b===~%(+ 2 0)"))
           (cells (parse-notebook-body body))
           (round (parse-notebook-body (cells->body-md cells)))
           (sol-locked (find-if (lambda (c) (and (eq :code-solution (cell-kind c))
                                                 (string= "a" (cell-description c))))
                                round))
           (sol-plain (find-if (lambda (c) (and (eq :code-solution (cell-kind c))
                                                (string= "b" (cell-description c))))
                               round)))
      (ok (eq t (cell-gated-p sol-locked)) "gated solution stays gated")
      (ok sol-plain "plain solution present")
      (ok (null (cell-gated-p sol-plain)) "plain solution stays non-gated"))))

(deftest solution-empty-description-parses-and-round-trips
  (testing "a solution with an empty description (===solution: ===) parses and
round-trips; its description is optional (unlike an exercise's)"
    ;; plain solution, empty description
    (let ((c (first (parse-notebook-body (format nil "===solution: ===~%(x)")))))
      (ok (eq :code-solution (cell-kind c)))
      (ok (null (cell-gated-p c)))
      (ok (string= "" (or (cell-description c) "")))
      (ok (string= "(x)" (cell-body c)))
      ;; round-trip: serialize the empty-desc solution and reparse
      (let ((c2 (first (parse-notebook-body (cells->body-md (list c))))))
        (ok (eq :code-solution (cell-kind c2)))
        (ok (string= "" (or (cell-description c2) "")))))
    ;; locked solution, empty description
    (let ((c (first (parse-notebook-body (format nil "===solution-locked: ===~%(y)")))))
      (ok (eq :code-solution (cell-kind c)))
      (ok (eq t (cell-gated-p c)))
      (ok (string= "" (or (cell-description c) ""))))))

(deftest parse-exercise-new-form-splits-desc-and-code
  (testing "===exercise===/===code=== splits a multi-line description from code"
    (let ((c (first (parse-notebook-body
                     (format nil "===exercise===~%line1~%line2~%===code===~%(fill)~%~%===expect===~%3")))))
      (ok (eq :code-exercise (cell-kind c)))
      (ok (string= (format nil "line1~%line2") (cell-description c)))
      (ok (string= "(fill)" (cell-body c)))
      (ok (= 1 (length (cell-test-cases c)))))))

(deftest parse-exercise-old-form-still-works
  (testing "the old ===exercise: desc=== header form still parses (backward compat)"
    (let ((c (first (parse-notebook-body
                     (format nil "===exercise: sum===~%(fill)~%~%===expect===~%3")))))
      (ok (eq :code-exercise (cell-kind c)))
      (ok (string= "sum" (cell-description c)))
      (ok (string= "(fill)" (cell-body c))))))

(deftest parse-exercise-empty-desc-allowed-with-code
  (testing "bare ===exercise=== + ===code=== with an empty description is allowed"
    (let ((c (first (parse-notebook-body
                     (format nil "===exercise===~%===code===~%(fill)")))))
      (ok (eq :code-exercise (cell-kind c)))
      (ok (string= "" (cell-description c)))
      (ok (string= "(fill)" (cell-body c))))))

(deftest parse-exercise-malformed-emits-errors
  (testing "malformed exercise forms emit validation errors"
    (flet ((errs (body)
             (multiple-value-bind (cells e) (parse-notebook-body body)
               (declare (ignore cells)) e)))
      (ok (some (lambda (e) (search "requires a description" (getf e :message)))
                (errs (format nil "===exercise===~%(fill)"))))
      (ok (some (lambda (e) (search "already set" (getf e :message)))
                (errs (format nil "===exercise: d===~%desc~%===code===~%(fill)"))))
      (ok (some (lambda (e) (search "only valid inside an exercise" (getf e :message)))
                (errs (format nil "===prose===~%hi~%~%===code===~%x")))))))

(deftest exercise-multiline-desc-serializes-and-round-trips
  (testing "an exercise serializes to the ===exercise===/===code=== block form and round-trips"
    (let* ((cells (list (make-cell :kind :code-exercise
                                   :description (format nil "para1~%~%para2")
                                   :body "(fill)"
                                   :test-cases (list (recurya/game/puzzle:make-test-case
                                                       :input "" :expected "3"
                                                       :description "")))))
           (md (cells->body-md cells)))
      (ok (search "===exercise===" md))
      (ok (search "===code===" md))
      (ng (search "===exercise: " md) "no old-style header desc")
      (let ((c2 (first (parse-notebook-body md))))
        (ok (string= (format nil "para1~%~%para2") (cell-description c2)))
        (ok (string= "(fill)" (cell-body c2)))
        (ok (= 1 (length (cell-test-cases c2))))))))
