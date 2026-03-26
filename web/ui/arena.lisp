;;;; web/ui/arena.lisp --- Arena page with grid visualization.

(defpackage #:recurya/web/ui/arena
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:recurya/game/arena
                #:arena-state-grid
                #:arena-state-bot-pos
                #:arena-state-enemy-pos
                #:arena-state-bot-score
                #:arena-state-enemy-score
                #:arena-state-turn
                #:grid-ref
                #:arena-result-frames
                #:arena-result-bot-score
                #:arena-result-enemy-score
                #:arena-result-fuel-used
                #:arena-result-error)
  (:export #:render
           #:render-result))

(in-package #:recurya/web/ui/arena)

(defparameter *styles*
  "body { font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
         margin: 0; background: #0f172a; color: #e2e8f0; line-height: 1.6; }
main { max-width: 960px; margin: 0 auto; padding: 2rem 1.5rem; }
a { color: #38bdf8; }
h1 { font-size: 1.5rem; color: #f8fafc; }
.breadcrumb { color: #64748b; font-size: 0.9rem; margin-bottom: 1rem; }
.breadcrumb a { color: #38bdf8; text-decoration: none; }
.arena-desc { color: #94a3b8; margin-bottom: 1.5rem; }
.editor-area { display: flex; flex-direction: column; gap: 0.75rem; margin-bottom: 1.5rem; }
.editor-area textarea { width: 100%; min-height: 180px; font-family: 'SF Mono', 'Fira Code', monospace;
                        font-size: 0.95rem; background: #1e293b; color: #e2e8f0;
                        border: 1px solid #334155; border-radius: 8px; padding: 1rem;
                        resize: vertical; line-height: 1.5; tab-size: 2; }
.editor-area textarea:focus { outline: 2px solid #38bdf8; border-color: #38bdf8; }
.btn-run { background: #2563eb; color: #fff; border: none; padding: 0.65rem 1.5rem;
           border-radius: 8px; font-weight: 600; cursor: pointer; font-size: 0.95rem; }
.btn-run:hover { background: #1d4ed8; }
.btn-run.htmx-request { opacity: 0.7; cursor: wait; }
#arena-panel { min-height: 2rem; }
.arena-grid { border-collapse: collapse; margin: 1rem auto; }
.arena-grid td { width: 42px; height: 42px; text-align: center; vertical-align: middle;
                 border: 1px solid #334155; font-size: 1.2rem; }
.cell-empty { background: #1e293b; }
.cell-wall { background: #475569; }
.cell-resource { background: #1e293b; }
.cell-bot { background: #1e3a5f; }
.cell-enemy { background: #3f1e1e; }
.cell-both { background: #3f2e1e; }
.frame { display: none; }
.frame.active { display: block; }
.turn-controls { text-align: center; margin: 1rem 0; display: flex; gap: 0.5rem;
                 justify-content: center; align-items: center; }
.turn-controls button { background: #334155; color: #e2e8f0; border: none;
                        padding: 0.5rem 1rem; border-radius: 6px; cursor: pointer;
                        font-size: 0.9rem; }
.turn-controls button:hover { background: #475569; }
.turn-info { color: #94a3b8; font-size: 0.9rem; min-width: 100px; text-align: center; }
.scores { display: flex; gap: 2rem; justify-content: center; margin: 1rem 0;
          font-size: 1.05rem; font-weight: 600; }
.score-bot { color: #38bdf8; }
.score-enemy { color: #f87171; }
.result-error { color: #f87171; background: #2d1b1b; padding: 0.75rem 1rem;
                border-radius: 8px; font-family: monospace; font-size: 0.9rem;
                margin-bottom: 1rem; white-space: pre-wrap; }
.metrics { color: #64748b; font-size: 0.85rem; text-align: center; margin-top: 0.5rem; }")

(defun cell-class (grid row col bot-pos enemy-pos)
  "Determine CSS class for a grid cell."
  (let ((is-bot (and (= row (car bot-pos)) (= col (cdr bot-pos))))
        (is-enemy (and (= row (car enemy-pos)) (= col (cdr enemy-pos))))
        (cell-type (grid-ref grid row col)))
    (cond
      ((and is-bot is-enemy) "cell-both")
      (is-bot "cell-bot")
      (is-enemy "cell-enemy")
      ((eq cell-type :wall) "cell-wall")
      ((eq cell-type :resource) "cell-resource")
      (t "cell-empty"))))

(defun cell-content (grid row col bot-pos enemy-pos)
  "Determine display content for a grid cell."
  (let ((is-bot (and (= row (car bot-pos)) (= col (cdr bot-pos))))
        (is-enemy (and (= row (car enemy-pos)) (= col (cdr enemy-pos))))
        (cell-type (grid-ref grid row col)))
    (cond
      ((and is-bot is-enemy) "&#x2694;")  ; crossed swords
      (is-bot "&#x1F916;")                ; robot
      (is-enemy "&#x1F47E;")              ; alien
      ((eq cell-type :wall) "&#x2588;")   ; block
      ((eq cell-type :resource) "&#x1F48E;") ; gem
      (t ""))))

(defun render-grid (state)
  "Render a single arena state as an HTML table."
  (let ((grid (arena-state-grid state))
        (bot (arena-state-bot-pos state))
        (enemy (arena-state-enemy-pos state)))
    (with-html-string
      (:table :class "arena-grid"
       (dotimes (r 7)
         (:tr
          (dotimes (c 7)
            (:td :class (cell-class grid r c bot enemy)
                 (:raw (cell-content grid r c bot enemy))))))))))

(defun render ()
  "Render the full arena page."
  (with-html-string
    (:doctype)
    (:html
     (:head (:meta :charset "utf-8")
      (:meta :name "viewport" :content "width=device-width, initial-scale=1")
      (:title "WardLisp Arena")
      (:script :src "https://unpkg.com/htmx.org@2.0.4"
       :integrity "sha384-HGfztofotfshcF7+8n44JQL2oJmowVChPTg48S+jvZoztPfvwD79OC/LTtG6dMp+"
       :crossorigin "anonymous")
      (:style (:raw *styles*)))
     (:body
      (:main
       (:div :class "breadcrumb"
        (:a :href "/wardlisp/" "WardLisp") " / Arena")
       (:h1 "Bot Arena")
       (:p :class "arena-desc"
        "Write a (decide-action state) function that returns an action symbol: "
        "'up, 'down, 'left, 'right, 'wait, or 'pickup. "
        "Compete against a greedy enemy bot to collect resources on a 7x7 grid over 20 turns.")
       (:form :class "editor-area"
        (:textarea :name "code" :placeholder "Write your decide-action function..."
                   :autofocus t :spellcheck "false"
                   "(define (decide-action state)
  ; state is an alist with keys:
  ;   my-pos, enemy-pos, my-score, enemy-score, turn, max-turns
  ; Return: 'up, 'down, 'left, 'right, 'wait, or 'pickup
  'right)")
        (:button :class "btn-run" :type "button"
                 :hx-post "/wardlisp/arena/run"
                 :hx-include "closest form"
                 :hx-target "#arena-panel"
                 :hx-swap "innerHTML"
                 "Run Simulation"))
       (:div :id "arena-panel"))))))

(defun render-result (result)
  "Render the arena result as an HTMX fragment with all frames."
  (let ((frames (arena-result-frames result))
        (error-msg (arena-result-error result)))
    (with-html-string
      (:div
       (when error-msg
         (:div :class "result-error" error-msg))
       ;; Scores
       (:div :class "scores"
        (:span :class "score-bot"
               (format nil "Bot: ~D" (arena-result-bot-score result)))
        (:span :class "score-enemy"
               (format nil "Enemy: ~D" (arena-result-enemy-score result))))
       ;; Turn controls
       (:div :class "turn-controls"
        (:button :onclick "prevFrame()" "&lt; Prev")
        (:span :class "turn-info" :id "turn-display" "Turn 0")
        (:button :onclick "nextFrame()" "Next &gt;")
        (:button :onclick "playFrames()" "Play"))
       ;; Frames (hidden, toggled by JS)
       (loop for frame in frames
             for i from 0
             do (:div :class (if (zerop i) "frame active" "frame")
                      :data-frame (format nil "~D" i)
                 (:raw (render-grid frame))))
       ;; Metrics
       (:div :class "metrics"
        (format nil "Total fuel: ~D | Frames: ~D"
                (arena-result-fuel-used result)
                (length frames)))
       ;; Minimal JS for frame stepping
       (:script (:raw
        (format nil "
var currentFrame = 0;
var totalFrames = ~D;
var playing = false;
var playTimer = null;
function showFrame(n) {
  document.querySelectorAll('.frame').forEach(function(f) { f.classList.remove('active'); });
  var f = document.querySelector('[data-frame=\"' + n + '\"]');
  if (f) f.classList.add('active');
  document.getElementById('turn-display').textContent = 'Turn ' + n;
}
function nextFrame() {
  if (currentFrame < totalFrames - 1) { currentFrame++; showFrame(currentFrame); }
}
function prevFrame() {
  if (currentFrame > 0) { currentFrame--; showFrame(currentFrame); }
}
function playFrames() {
  if (playing) { clearInterval(playTimer); playing = false; return; }
  playing = true;
  currentFrame = 0; showFrame(0);
  playTimer = setInterval(function() {
    if (currentFrame >= totalFrames - 1) { clearInterval(playTimer); playing = false; return; }
    currentFrame++; showFrame(currentFrame);
  }, 500);
}" (length frames))))))))
