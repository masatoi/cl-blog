(defpackage #:recurya/tests/web/i18n-catalog
  (:use #:cl #:rove)
  (:import-from #:recurya/web/i18n/core #:catalog-keys))
(in-package #:recurya/tests/web/i18n-catalog)

(defun missing-keys (from to)
  "FROM ロケールに在り TO ロケールに無いキー。"
  (set-difference (catalog-keys from) (catalog-keys to)))

(deftest en-ja-parity
  (testing "英語キーはすべて日本語に存在する"
    (let ((miss (missing-keys :en :ja)))
      (ok (null miss) (format nil "ja に欠落: ~S" miss))))
  (testing "日本語キーはすべて英語に存在する"
    (let ((miss (missing-keys :ja :en)))
      (ok (null miss) (format nil "en に欠落: ~S" miss)))))
