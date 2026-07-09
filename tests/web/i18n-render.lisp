(defpackage #:recurya/tests/web/i18n-render
  (:use #:cl #:rove)
  (:import-from #:recurya/web/i18n/core #:*locale*))
(in-package #:recurya/tests/web/i18n-render)

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
