(defpackage #:recurya/tests/web/i18n-render
  (:use #:cl #:rove)
  (:import-from #:recurya/web/i18n/core #:*locale*))
(in-package #:recurya/tests/web/i18n-render)

(defmacro with-render-context ((&key (locale :en)) &body body)
  "Bind *locale* and a fake ningle session so render fns that emit CSRF work
outside a real HTTP request."
  `(let ((*locale* ,locale)
         (ningle/context:*session* (make-hash-table :test 'eq)))
     ,@body))

(deftest layout-header-localized
  (testing "英語ロケール: 英語ナビ"
    (let ((*locale* :en))
      (let ((html (recurya/web/ui/layout:header nil)))
        (ok (search "Notebooks" html))
        (ok (search "Login" html))
        (ng (search "未ログイン" html)))))
  (testing "日本語ロケール: 日本語ナビ"
    (let ((*locale* :ja))
      (let ((html (recurya/web/ui/layout:header nil)))
        (ok (search "ノートブック" html))
        (ok (search "ログイン" html)))))
  (testing "ログイン済み日本語: メニュー訳"
    (let ((*locale* :ja))
      (let ((html (recurya/web/ui/layout:header
                   (list :name "太郎" :email "t@example.com"))))
        (ok (search "アカウント設定" html))
        (ok (search "ログアウト" html))))))

(deftest account-page-localized
  (let ((user (list :email "t@example.com" :name "太郎"
                    :language "ja" :timezone "Asia/Tokyo")))
    (testing "日本語ロケールで日本語ラベル"
      (with-render-context (:locale :ja)
        (let ((html (recurya/web/ui/account:render :user user)))
          (ok (search "地域設定" html))
          (ok (search "変更を保存" html))
          (ok (search "危険な操作" html)))))
    (testing "言語ドロップダウンは available-locales のみ（fr は出ない）"
      (with-render-context (:locale :en)
        (let ((html (recurya/web/ui/account:render :user user)))
          (ok (search "English" html))
          (ok (search "日本語" html))
          (ng (search "Français" html)))))))
