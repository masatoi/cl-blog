;;;; web/ui/styles.lisp --- Shared CSS design tokens and component styles.
;;;;
;;;; All CSS is defined as Lisp string parameters and concatenated at
;;;; render time by common-styles / page-styles.  No external CSS files
;;;; are used; styles are inlined into each page via <style> tags.

(defpackage #:recurya/web/ui/styles
  (:use #:cl)
  (:export #:*color-vars*
           #:*base-styles*
           #:*button-styles*
           #:*message-styles*
           #:*form-styles*
           #:*table-styles*
           #:*modal-styles*
           #:*card-styles*
           #:*status-pill-styles*
           #:common-styles
           #:page-styles
           #:auth-page-styles))

(in-package #:recurya/web/ui/styles)

;;; ---------------------------------------------------------------------------
;;; Color Palette (CSS Custom Properties)
;;; ---------------------------------------------------------------------------

(defparameter *color-vars*
  ":root {
  /* Primary colors */
  --color-bg-dark: #0f172a;
  --color-bg-light: #f8fafc;
  --color-primary: #0ea5e9;
  --color-primary-hover: #0284c7;
  --color-accent: #38bdf8;

  /* Text colors */
  --color-text-dark: #0f172a;
  --color-text-light: #f8fafc;
  --color-text-muted: #64748b;
  --color-text-secondary: #475569;
  --color-text-faint: #94a3b8;

  /* Status colors */
  --color-success-bg: #dcfce7;
  --color-success-text: #166534;
  --color-error-bg: #fee2e2;
  --color-error-text: #b91c1c;
  --color-error: #ef4444;
  --color-error-hover: #dc2626;
  --color-warning-bg: #fef3c7;
  --color-warning-text: #b45309;
  --color-info-bg: #e0f2fe;
  --color-info-text: #0369a1;

  /* Border & UI colors */
  --color-border: #cbd5f5;
  --color-border-light: #e2e8f0;
  --color-secondary-bg: #e2e8f0;
  --color-secondary-hover: #cbd5f5;

  /* Shadows */
  --shadow-card: 0 24px 60px rgba(15,23,42,0.28);
  --shadow-modal: 0 32px 80px rgba(15,23,42,0.35);
}")

;;; ---------------------------------------------------------------------------
;;; Base Styles
;;; ---------------------------------------------------------------------------

(defparameter *base-styles*
  "body {
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  margin: 0;
  background: var(--color-bg-dark);
  color: var(--color-text-dark);
  line-height: 1.5;
}

main {
  max-width: 1080px;
  margin: 0 auto;
  padding: 3rem 1.5rem 4rem;
}

h1, h2, h3 {
  margin-top: 0;
  letter-spacing: -0.02em;
}

.muted {
  color: var(--color-text-muted);
}

a {
  color: var(--color-primary);
  text-decoration: none;
  font-weight: 600;
}

a:hover {
  color: var(--color-accent);
  text-decoration: underline;
}

code {
  font-family: 'SF Mono', Monaco, Consolas, monospace;
  font-size: 0.9em;
}")

;;; ---------------------------------------------------------------------------
;;; Card Styles
;;; ---------------------------------------------------------------------------

(defparameter *card-styles*
  ".card {
  background: var(--color-bg-light);
  border-radius: 16px;
  box-shadow: var(--shadow-card);
  padding: 2rem 2.25rem;
  margin-bottom: 2rem;
}")

;;; ---------------------------------------------------------------------------
;;; Button Styles
;;; ---------------------------------------------------------------------------

(defparameter *button-styles*
  ".button-primary,
.btn-primary {
  padding: 0.75rem 1.5rem;
  border: none;
  border-radius: 999px;
  background: var(--color-primary);
  color: #fff;
  font-weight: 600;
  cursor: pointer;
  transition: background 0.15s ease;
}

.button-primary:hover,
.btn-primary:hover {
  background: var(--color-primary-hover);
}

.button-secondary,
.btn-secondary {
  padding: 0.75rem 1.5rem;
  border: none;
  border-radius: 999px;
  background: var(--color-secondary-bg);
  color: var(--color-text-dark);
  font-weight: 600;
  cursor: pointer;
  transition: background 0.15s ease;
}

.button-secondary:hover,
.btn-secondary:hover {
  background: var(--color-secondary-hover);
}

.button-danger,
.btn-danger {
  padding: 0.75rem 1.5rem;
  border: none;
  border-radius: 999px;
  background: var(--color-error);
  color: #fff;
  font-weight: 600;
  cursor: pointer;
  transition: background 0.15s ease;
}

.button-danger:hover,
.btn-danger:hover {
  background: var(--color-error-hover);
}

/* Small button variant */
.btn-sm {
  padding: 0.5rem 1rem;
  font-size: 0.9rem;
}")

;;; ---------------------------------------------------------------------------
;;; Message/Alert Styles
;;; ---------------------------------------------------------------------------

(defparameter *message-styles*
  ".message {
  margin-bottom: 1.5rem;
  padding: 1rem 1.25rem;
  border-radius: 12px;
  font-weight: 500;
}

.message.success {
  background: var(--color-success-bg);
  color: var(--color-success-text);
}

.message.error {
  background: var(--color-error-bg);
  color: var(--color-error-text);
}")

;;; ---------------------------------------------------------------------------
;;; Form Styles
;;; ---------------------------------------------------------------------------

(defparameter *form-styles*
  "label {
  font-weight: 600;
  color: var(--color-text-dark);
}

input[type='text'],
input[type='email'],
input[type='password'],
input[type='number'],
select,
textarea {
  padding: 0.75rem 1rem;
  border: 1px solid var(--color-border);
  border-radius: 10px;
  font-size: 1rem;
  font-family: inherit;
  background: #fff;
}

input[type='text']:focus,
input[type='email']:focus,
input[type='password']:focus,
input[type='number']:focus,
select:focus,
textarea:focus {
  outline: 2px solid var(--color-accent);
  outline-offset: 2px;
  border-color: var(--color-accent);
}

input[readonly] {
  background: var(--color-secondary-bg);
  color: var(--color-text-secondary);
}

input[type='file'] {
  padding: 0.75rem;
  border-radius: 12px;
  border: 1px dashed var(--color-accent);
  background: var(--color-info-bg);
  cursor: pointer;
}")

;;; ---------------------------------------------------------------------------
;;; Table Styles
;;; ---------------------------------------------------------------------------

(defparameter *table-styles*
  "table {
  width: 100%;
  border-collapse: collapse;
  margin-top: 1rem;
}

th, td {
  text-align: left;
  padding: 0.75rem 0.5rem;
  border-bottom: 1px solid var(--color-border-light);
  vertical-align: top;
}

th {
  color: var(--color-text-secondary);
  text-transform: uppercase;
  font-size: 0.75rem;
  letter-spacing: 0.08em;
}

tbody tr:hover {
  background: #eef2ff;
}

.inline-metric {
  display: block;
  color: var(--color-text-faint);
  font-size: 0.78rem;
  margin-top: 0.25rem;
}")

;;; ---------------------------------------------------------------------------
;;; Modal Styles
;;; ---------------------------------------------------------------------------

(defparameter *modal-styles*
  ".modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(15, 23, 42, 0.55);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 140;
  padding: 1.5rem;
}

.modal-card {
  background: #fff;
  color: var(--color-text-dark);
  border-radius: 16px;
  max-width: 480px;
  width: 100%;
  padding: 2rem;
  box-shadow: var(--shadow-modal);
}

.modal-card h3 {
  margin-top: 0;
  margin-bottom: 0.75rem;
}

.modal-card p {
  margin: 0;
  color: var(--color-text-secondary);
  line-height: 1.45;
}

.modal-actions {
  display: flex;
  justify-content: flex-end;
  gap: 0.75rem;
  margin-top: 1.75rem;
}")

;;; ---------------------------------------------------------------------------
;;; Status Pill Styles
;;; ---------------------------------------------------------------------------

(defparameter *status-pill-styles*
  ".status-pill {
  display: inline-flex;
  align-items: center;
  padding: 0.2rem 0.6rem;
  border-radius: 999px;
  font-size: 0.72rem;
  font-weight: 600;
}

.status-pill[data-status='queued'],
.status-pill[data-status='pending'] {
  background: var(--color-info-bg);
  color: var(--color-info-text);
}

.status-pill[data-status='running'] {
  background: var(--color-warning-bg);
  color: var(--color-warning-text);
}

.status-pill[data-status='succeeded'],
.status-pill[data-status='completed'] {
  background: var(--color-success-bg);
  color: var(--color-success-text);
}

.status-pill[data-status='failed'] {
  background: var(--color-error-bg);
  color: var(--color-error-text);
}

.status-pill[data-status='cancelled'] {
  background: var(--color-secondary-bg);
  color: var(--color-text-secondary);
}")



;;; ---------------------------------------------------------------------------
;;; Pagination Styles
;;; ---------------------------------------------------------------------------

(defparameter *pagination-styles*
  ".pagination {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 1rem;
  margin-top: 1.5rem;
  padding-top: 1.5rem;
  border-top: 1px solid var(--color-border-light);
}

.pagination-info {
  color: var(--color-text-muted);
  font-size: 0.9rem;
}

.pagination-nav {
  display: flex;
  gap: 0.5rem;
}

.pagination-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
  padding: 0.5rem 1rem;
  border: 1px solid var(--color-border);
  border-radius: 8px;
  background: #fff;
  color: var(--color-text-dark);
  font-weight: 500;
  font-size: 0.9rem;
  text-decoration: none;
  cursor: pointer;
  transition: all 0.15s ease;
}

.pagination-btn:hover {
  background: var(--color-secondary-bg);
  border-color: var(--color-primary);
  text-decoration: none;
}

.pagination-btn.disabled {
  opacity: 0.5;
  cursor: not-allowed;
  pointer-events: none;
}")
;;; ---------------------------------------------------------------------------
;;; Utility Functions
;;; ---------------------------------------------------------------------------

(defun common-styles ()
  "Return all common styles concatenated for authenticated pages."
  (concatenate 'string
               *color-vars*
               *base-styles*
               *card-styles*
               *button-styles*
               *message-styles*
               *form-styles*
               *table-styles*
               *modal-styles*
               *status-pill-styles*
               *pagination-styles*))

(defun page-styles (&rest additional-styles)
  "Return common styles plus any additional page-specific styles."
  (apply #'concatenate 'string
         (common-styles)
         additional-styles))

;;; ---------------------------------------------------------------------------
;;; Auth Page Styles (Login/Signup)
;;; ---------------------------------------------------------------------------

(defparameter *auth-container-styles*
  ".auth-container {
  max-width: 420px;
  margin: 6rem auto;
  padding: 3rem;
  background: var(--color-bg-light);
  border-radius: 18px;
  box-shadow: var(--shadow-modal);
}

.auth-container h1 {
  margin-top: 0;
  color: var(--color-text-dark);
  letter-spacing: -0.02em;
}

.auth-container form {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.auth-container .app-name {
  color: var(--color-text-muted);
  margin-bottom: 1.5rem;
  font-size: 0.95rem;
}

.auth-container .error {
  background: var(--color-error-bg);
  color: var(--color-error-text);
  padding: 0.75rem 1rem;
  border-radius: 10px;
  margin-bottom: 1rem;
}")

(defun auth-page-styles (&rest additional-styles)
  "Return styles for authentication pages (login, signup)."
  (apply #'concatenate 'string
         *color-vars*
         *base-styles*
         *button-styles*
         *form-styles*
         *auth-container-styles*
         additional-styles))
