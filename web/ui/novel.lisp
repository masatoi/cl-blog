;;;; web/ui/novel.lisp --- Novel player view (renders beats, click-to-advance).
(defpackage #:recurya/web/ui/novel
  (:use #:cl)
  (:import-from #:spinneret #:with-html-string)
  (:import-from #:recurya/utils/common #:json->string)
  (:import-from #:recurya/web/i18n/core #:tr)
  (:export #:render-player))

(in-package #:recurya/web/ui/novel)

(defun %beats->json (beats)
  "Serialize BEATS (list of plists) to a JSON array string for the client."
  (json->string
   (mapcar (lambda (b)
             (let ((h (make-hash-table :test 'equal)))
               (setf (gethash "type" h) (string-downcase (symbol-name (getf b :type)))
                     (gethash "speaker" h) (or (getf b :speaker) "")
                     (gethash "text" h) (or (getf b :text) "")
                     (gethash "bg" h) (or (getf b :bg) ""))
               h))
           beats)))

(defun render-player (&key title beats (id "main"))
  "Render a novel player. BEATS is a list of beat plists. ID makes the DOM ids
and the player JS unique, so several players can coexist on one page (e.g.
inline scene cells). Clicking anywhere in the player advances to the next beat."
  (let* ((root-id (format nil "novel-~A" id))
         (bg-id (format nil "novel-bg-~A" id))
         (sp-id (format nil "novel-speaker-~A" id))
         (tx-id (format nil "novel-text-~A" id))
         (next-id (format nil "novel-next-~A" id))
         (js (format nil "(function(){
  var root=document.getElementById('~A');
  if(!root) return;
  var beats=JSON.parse(root.getAttribute('data-beats')||'[]');
  var i=-1;
  var bg=document.getElementById('~A');
  var sp=document.getElementById('~A');
  var tx=document.getElementById('~A');
  function show(n){var b=beats[n]; if(!b){tx.textContent=root.getAttribute('data-end-label')||'— おわり —'; sp.textContent=''; return;}
    bg.setAttribute('data-bg', b.bg||'');
    sp.textContent=(b.type==='say')?(b.speaker||''):'';
    tx.textContent=b.text||'';}
  function next(){ if(i<beats.length-1){i++; show(i);} }
  root.addEventListener('click',next);
  next();
})();" root-id bg-id sp-id tx-id)))
    (with-html-string
      (:div :class "novel-player" :id root-id
            :data-beats (%beats->json beats)
            :data-end-label (tr :novel.end)
        (:div :class "novel-bg" :id bg-id)
        (:div :class "novel-box"
          (:div :class "novel-speaker" :id sp-id)
          (:div :class "novel-text" :id tx-id)
          (:button :type "button" :class "novel-next" :id next-id "▶"))
        (:noscript (:p title))
        (:script :type "text/javascript" (:raw js))))))
