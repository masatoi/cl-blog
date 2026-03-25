;;;; web/ui/wardlisp-home.lisp --- WardLisp puzzle listing page.

(defpackage #:recurya/web/ui/wardlisp-home
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:recurya/game/puzzle
                #:puzzle-id
                #:puzzle-title
                #:puzzle-description
                #:puzzle-difficulty)
  (:export #:render))

(in-package #:recurya/web/ui/wardlisp-home)

(defparameter *styles*
  "body { font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
         margin: 0; background: #0f172a; color: #e2e8f0; line-height: 1.6; }
main { max-width: 760px; margin: 0 auto; padding: 3rem 1.5rem; }
h1 { font-size: 2rem; letter-spacing: -0.03em; text-align: center;
     color: #f8fafc; margin-bottom: 0.5rem; }
.subtitle { text-align: center; color: #94a3b8; margin-bottom: 2.5rem; }
.puzzle-list { list-style: none; padding: 0; display: flex; flex-direction: column; gap: 1rem; }
.puzzle-card { background: #1e293b; border-radius: 12px; padding: 1.5rem;
               text-decoration: none; color: #e2e8f0; display: block;
               border: 1px solid #334155; transition: border-color 0.15s; }
.puzzle-card:hover { border-color: #38bdf8; }
.puzzle-card__title { font-size: 1.15rem; font-weight: 700; margin: 0 0 0.5rem;
                      font-family: monospace; color: #38bdf8; }
.puzzle-card__desc { color: #94a3b8; font-size: 0.95rem; margin: 0; }
.puzzle-card__diff { display: inline-block; background: #334155; color: #94a3b8;
                     padding: 0.2rem 0.6rem; border-radius: 999px; font-size: 0.8rem;
                     margin-top: 0.75rem; }")

(defun difficulty-label (n)
  (cond ((<= n 1) "Easy")
        ((= n 2) "Medium")
        (t "Hard")))

(defun render (puzzles)
  "Render the WardLisp home page with puzzle listing."
  (with-html-string
    (:doctype)
    (:html
     (:head (:meta :charset "utf-8")
      (:meta :name "viewport" :content "width=device-width, initial-scale=1")
      (:title "WardLisp - Puzzles")
      (:style (:raw *styles*)))
     (:body
      (:main
       (:h1 "WardLisp Puzzles")
       (:p :class "subtitle" "Learn Lisp by solving puzzles")
       (:ul :class "puzzle-list"
        (dolist (p puzzles)
          (:li
           (:a :class "puzzle-card"
               :href (format nil "/wardlisp/puzzle/~(~A~)" (puzzle-id p))
            (:h2 :class "puzzle-card__title"
                 (format nil "(~A)" (puzzle-title p)))
            (:p :class "puzzle-card__desc" (puzzle-description p))
            (:span :class "puzzle-card__diff"
                   (difficulty-label (puzzle-difficulty p))))))))))))
