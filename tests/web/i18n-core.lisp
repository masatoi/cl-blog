(defpackage #:recurya/tests/web/i18n-core
  (:use #:cl #:rove)
  (:import-from #:recurya/web/i18n/core
                #:*locale* #:*default-locale* #:*catalogs*
                #:register-message #:defcatalog #:tr
                #:available-locales #:normalize-locale
                #:known-key-p #:with-locale #:bind-locale))
(in-package #:recurya/tests/web/i18n-core)

;; テスト専用の隔離カタログを使う（本番カタログに依存しない）
(defmacro with-fresh-catalogs (&body body)
  `(let ((*catalogs* (make-hash-table :test 'eq))
         (*default-locale* :en)
         (*locale* :en))
     ,@body))

(deftest tr-lookup-and-fallback
  (with-fresh-catalogs
    (defcatalog :en (:greet "Hello, ~A") (:only-en "EN only"))
    (defcatalog :ja (:greet "こんにちは、~A さん"))
    (testing "現在ロケールで引く"
      (let ((*locale* :ja))
        (ok (string= (tr :greet "太郎") "こんにちは、太郎 さん"))))
    (testing "既定ロケールへフォールバック"
      (let ((*locale* :ja))
        (ok (string= (tr :only-en) "EN only"))))
    (testing "未定義キーは可視マーカー"
      (let ((*locale* :en))
        (handler-bind ((warning #'muffle-warning))
          (ok (search "⟦" (tr :missing))))))))

(deftest normalize-locale-rules
  (with-fresh-catalogs
    (defcatalog :en (:x "x"))
    (defcatalog :ja (:x "x"))
    (testing "対応する文字列/キーワードはそのまま"
      (ok (eq (normalize-locale "ja") :ja))
      (ok (eq (normalize-locale :en) :en)))
    (testing "非対応/空/nil は既定ロケール"
      (ok (eq (normalize-locale "fr") :en))
      (ok (eq (normalize-locale "") :en))
      (ok (eq (normalize-locale nil) :en)))
    (testing "未対応文字列で新しいキーワードを intern しない"
      (ok (eq (normalize-locale "totally-unknown-xyz") :en))
      (ok (null (find-symbol "TOTALLY-UNKNOWN-XYZ" :keyword))))))

(deftest bind-locale-from-session
  (with-fresh-catalogs
    (defcatalog :en (:x "x")) (defcatalog :ja (:x "x"))
    (labels ((mk-env (lang)
               (let ((sess (make-hash-table :test 'eq)))
                 (when lang
                   (setf (gethash :user sess) (list :id "1" :language lang)))
                 (list :lack.session sess)))
             (probe (env)
               (funcall (bind-locale (lambda (e) (declare (ignore e)) *locale*))
                        env)))
      (testing "ユーザー言語が束縛される"
        (ok (eq (probe (mk-env "ja")) :ja)))
      (testing "匿名は既定ロケール"
        (ok (eq (probe (list :lack.session (make-hash-table :test 'eq))) :en)))
      (testing "非対応言語は既定ロケール"
        (ok (eq (probe (mk-env "fr")) :en))))))
