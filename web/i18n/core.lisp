(defpackage #:recurya/web/i18n/core
  (:use #:cl)
  (:export #:*locale* #:*default-locale* #:*catalogs*
           #:register-message #:defcatalog
           #:tr #:available-locales #:normalize-locale
           #:known-key-p #:catalog-keys #:with-locale #:bind-locale))

(in-package #:recurya/web/i18n/core)

(defvar *default-locale* :en
  "対応言語が無い/非対応時のフォールバック言語。")

(defvar *locale* :en
  "現在のリクエストのロケール。BIND-LOCALE が束縛する。")

(defparameter *catalogs* (make-hash-table :test 'eq)
  "locale(keyword) -> (hash-table: key(keyword) -> template(string))。")

(defun %catalog (locale)
  "LOCALE のメッセージ表を返す（無ければ作る）。"
  (or (gethash locale *catalogs*)
      (setf (gethash locale *catalogs*) (make-hash-table :test 'eq))))

(defun register-message (locale key template)
  "LOCALE の KEY に TEMPLATE(string) を登録する。"
  (check-type key keyword)
  (check-type template string)
  (setf (gethash key (%catalog locale)) template)
  key)

(defmacro defcatalog (locale &body pairs)
  "LOCALE に複数メッセージを登録する。各 PAIR は (KEY TEMPLATE)。"
  `(progn
     ,@(loop for (key template) in pairs
             collect `(register-message ,locale ,key ,template))
     ,locale))

(defun available-locales ()
  "登録済みロケールのキーワード一覧。"
  (loop for k being the hash-keys of *catalogs* collect k))

(defun catalog-keys (locale)
  "LOCALE に登録済みのメッセージキー一覧。"
  (let ((cat (gethash locale *catalogs*)))
    (when cat (loop for k being the hash-keys of cat collect k))))

(defun known-key-p (key &optional (locale *locale*))
  "KEY が LOCALE か既定ロケールのカタログに存在すれば真。"
  (flet ((in (loc) (let ((c (gethash loc *catalogs*)))
                     (and c (nth-value 1 (gethash key c))))))
    (or (in locale) (in *default-locale*))))

(defun normalize-locale (designator)
  "DESIGNATOR (\"ja\" / :ja / nil) を対応ロケールキーワードに正規化する。
非対応/空/nil は *DEFAULT-LOCALE* を返す。ユーザー入力文字列から新しい
キーワードを intern しない（登録済みロケールとの文字列比較のみ）。"
  (cond
    ((and (keywordp designator) (gethash designator *catalogs*))
     designator)
    ((stringp designator)
     (or (find designator (available-locales)
               :key #'symbol-name :test #'string-equal)
         *default-locale*))
    (t *default-locale*)))

(defun %lookup (key locale)
  (let ((cat (gethash locale *catalogs*)))
    (when cat (gethash key cat))))

(defun tr (key &rest format-args)
  "KEY を *LOCALE* -> *DEFAULT-LOCALE* -> 可視マーカー の順に引き、
テンプレートに (apply #'format nil template format-args) を適用して返す。"
  (let ((template (or (%lookup key *locale*) (%lookup key *default-locale*))))
    (if template
        (apply #'format nil template format-args)
        (progn
          (warn "i18n: missing message key ~S (locale ~S)" key *locale*)
          (format nil "⟦~A⟧" key)))))

(defmacro with-locale ((locale) &body body)
  "*LOCALE* を (normalize-locale LOCALE) に束縛して BODY を評価。"
  `(let ((*locale* (normalize-locale ,locale))) ,@body))

(defun bind-locale (app)
  "Lack ミドルウェア: セッションユーザーの :language から *LOCALE* を束縛して
下流 APP を呼ぶ。:session の後段で使うこと。"
  (lambda (env)
    (let* ((session (getf env :lack.session))
           (user (and session (gethash :user session)))
           (lang (and user (getf user :language))))
      (let ((*locale* (normalize-locale lang)))
        (funcall app env)))))
