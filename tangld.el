;;; tangld.el --- literate config development environment -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2021 Timothy Aldrich

;; Author: Timothy Aldrich <timothy.r.aldrich@gmail.com>
;; Version: 0.0.1
;; Package-Requires: ((org) (notifications) (f) (s))
;; Keywords: tools processes
;; URL: https://github.com/aldrichtr/tangld

;;; Commentary:
;; A Literate Programming Environment for configuration files and scripts

;; tangld is an Emacs package that provides 'dotfiles management' features
;; using Literate Programming paradigms.  Using org-mode files with source
;; blocks and the tangle functionality, Emacs can be used as an IDE to
;; document, build, and install configuration files, scripts and other
;; files on a system.  More details are available in the README.org file.

;;; Code:

(require 'f)
(require 'async)

(require 'ob-tangle)
(require 'ob-extended-tangle)
(require 'ob-load-namespaced-libraries)
(require 'ob-text-var-expansion)
(require 'ob-var-table)

(require 'tangld-init)
(require 'tangld-build)
(require 'tangld-clean)

;;;; Constants

(defconst tangld--load-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory that yasnippet was loaded from.")

(defconst tangld--installed-lib-dir
  (expand-file-name "lib" tangld--load-dir))

(defconst tangld--default-user-lib-dir
  (expand-file-name "tangld-lib" user-emacs-directory))

;;;; Global settings

(defgroup tangld nil
  "Literate Config Manager"
  :prefix "tangld-")

(defcustom tangld-babel-library-dirs (list tangld--default-user-lib-dir)
  "List of top-level tangld library directories.

Each element, a string or a symbol whose value is a string,
designates a top-level directory where org-mode files can be found.

Elements appearing earlier in the list override later elements"
  :group 'tangld
  :type '(choice (directory :tag "Single directory")
                 (repeat :tag "List of directories"
                         (choice (directory) (variable)))))

(defcustom tangld-project-dirs
  '((root    . "~/.tangld")
    (lib     . "lib")
    (build   . "build")
    (source  . "src")
    (install . "dotfiles")
    (system  . "~"))
  "A list of default project directory names"
  :group 'tangld
  :type '(alist :value-type (group string )))

(defcustom tangld-add-src-return-link-comments t
  "Add a link to the source code block in the output"
  :group 'tangld
  :type 'boolean)

(defcustom tangld-inhibit-init-if-exists t
  "Do not overwrite and existing project with tangld-init"
  :group 'tangld
  :type 'boolean)

(defcustom tangld-init-vc-on-init-p t
  "Non-nil means a version control system is initialized when starting a new tangld project."
  :group 'tangld
  :type 'boolean)

(defcustom tangld-verbose-p nil
  "Whether tangled should display many messages."
  :group 'tangld
  :type 'boolean)

(defcustom tangld-install-type 'link
  ""
  :group 'tangld
  :type 'symbol)

(defcustom tangld-lazy-tangle-p t
  "Only tangle when necessary.
That is, when the target file either does not exist or is older than the source file."
  :group 'tangld
  :type 'boolean)

(defun tangld--target-file (file source-dir target-dir)
  "Return the tangle target of link-type based on FILE."
  (f-expand (f-relative file source-dir) target-dir))

(defun tangld-default-build-fn (file source-dir target-dir)
  "Build FILE from SOURCE to TARGET."
  (let-alist nil
    ;; ((target (f-expand (f-relative file source-dir) target-dir)))
    (cond ((file-ext-p file "org")
	   (tangld--tangle file target tangld--lazy-tangle-p))
	  (t
	   (f-symlink file target)))))

(defun tangld--message (format-string &rest args)
  "Display message if `tangld-verbose-p' is non-nil."
  (when tangld-verbose-p (message (format "[tangld] %s" (format format-string args)))))

;; Tangling is really slow. Doing so with multiple files that are likely to be
;; big will take too much time and it is unacceptable to ask the user to wait.
;; Instead, we tangle asynchronously.
(defun tangld--async-tangle-file (file target)
  "Asynchronously tangle FILE to TARGET."
  (async-start `(lambda ()
		  (require 'org)
		  (require 'ob-tangle)
		  (let ((org-babel-confirm-evaluate nil)
			(gc-cons-threshold most-positive-fixnum)
			(org-babel-default-header-args '((:tangle . "yes") (:results . "silent"))))
		    (list (ignore-errors (org-babel-tangle-file ,file ,target))
			  ,file
			  ,target)))
	       (lambda (result)
		 (cl-destructuring-bind (outcome file target) result
		   (message "%s in tangling %s to %s" (if outcome "Succeded" "Failed") file target)))))

(defun tangld--tangle (file target &optional force)
  "Tangle FILE into PROJECT-DIR.
Only tangles if target file either does not exist or is older than FILE. If
FORCE is enabled, tangle no matter what."
  (when (or force (not (f-exists-p target)) (file-newer-than-file-p file target))
    (tangld--message "tangling %s -> %s")
    (tangld--async-tangle-file file target)))

;; It is far more useful to have access to the full paths than the components.
(defun tangld--expanded-project-dir-paths ()
  "Return `tangld-project-dirs' with values all expanded."
  (let ((expanded nil)
	(root (alist-get 'root tangld-project-dirs)))
    (dolist (it tangld-project-dirs)
      (let ((name (car it)) (val (cdr it)))
	(push (cons name (expand-file-name val root)) expanded)))
    expanded))

(provide 'tangld)

;;; tangld.el ends here
