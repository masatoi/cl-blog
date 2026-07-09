(defpackage #:recurya/tests/web/i18n-core
  (:use #:cl #:rove)
  (:import-from #:recurya/web/i18n/core
                #:*locale* #:*default-locale* #:*catalogs*
                #:register-message #:defcatalog #:tr
                #:available-locales #:normalize-locale
                #:known-key-p #:catalog-keys #:with-locale #:bind-locale))

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
          (ok (search "⟦" (tr :missing))))))
    (testing "テンプレートと引数の不一致でクラッシュしない"
      (let ((*locale* :en))
        (handler-bind ((warning #'muffle-warning))
          (ok (search "⟦" (tr :greet))))))))

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

(deftest catalog-introspection
  (with-fresh-catalogs
    (defcatalog :en (:a "A") (:b "B"))
    (defcatalog :ja (:a "あ"))
    (testing "available-locales / catalog-keys"
      (ok (null (set-exclusive-or (available-locales) '(:en :ja))))
      (ok (null (set-exclusive-or (catalog-keys :en) '(:a :b))))
      (ok (null (set-exclusive-or (catalog-keys :ja) '(:a)))))
    (testing "known-key-p は指定ロケール or 既定ロケールで判定"
      (let ((*locale* :ja))
        (ok (known-key-p :a))
        (ok (known-key-p :b))
        (ng (known-key-p :missing))))
    (testing "register-message は型を検査する"
      (ok (handler-case (progn (register-message :en "not-a-keyword" "x") nil)
            (type-error () t)))
      (ok (handler-case (progn (register-message :en :k 42) nil)
            (type-error () t))))
    (testing "with-locale は正規化して束縛する"
      (with-locale ("ja") (ok (eq *locale* :ja)))
      (with-locale ("fr") (ok (eq *locale* :en))))))
