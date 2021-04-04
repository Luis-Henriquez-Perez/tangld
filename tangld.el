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

(require 'ob-tangle)
(require 'ob-extended-tangle)
(require 'ob-load-namespaced-libraries)
(require 'ob-text-var-expansion)
(require 'ob-var-table)

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

(defcustom tangld-confirm-on-eval nil
  "If non-nil, emacs will ask before evaluating code in source blocks"
  :group 'tangld
  :type '(choice
          (const :tag "Don't ask" nil)
          (const :tag "Ask" t)))

(defcustom tangld-add-src-return-link-comments t
  "Add a link to the source code block in the output"
  :group 'tangld
  :type 'boolean)

(defcustom tangld-inhibit-init-if-exists t
  "Do not overwrite and existing project with tangld-init"
  :group 'tangld
  :type 'boolean)

(defcustom tangld-add-project-lib-dir-on-init t
  "Add the lib directory of the project to the tangld-babel-library-dirs
during init"
  :group 'tangld
  :type 'boolean)

(defcustom tangld-init-vc-on-init-p t
  "Non-nil means a version control system is initialized when starting a new tangld project."
  :group 'tangld
  :type 'boolean)

(defcustom tangld-cache-org-babel-library-p t
  "Non-nil means cache the org babel library."
  :group 'tangld
  :type 'boolean)

(defcustom tangld-use-cached-library-p t
  "Non-nil means use the cache if it exists."
  :group 'tangld
  :type 'boolean)

(defcustom tangld-config-file "config.org"
  "File where config details are written."
  :group 'tangld
  :type 'string)

(defcustom tangld-prebuild-hook nil
  "Hook run before `tangld-build' is called."
  :group 'tangld
  :type 'hook)

(defcustom tangld-postbuild-hook nil
  "Hook run after `tangld-build' is called."
  :group 'tangld
  :type 'hook)

(defcustom tangld-preinstall-hook nil
  "Hook run before `tangld-install' is called."
  :group 'tangld
  :type 'hook)

(defcustom tangld-postinstall-hook nil
  "Hook run after `tangld-install' is called."
  :group 'tangld
  :type 'hook)

(defcustom tangld-verbose-p nil
  "Whether tangled should display many messages."
  :group 'tangld
  :type 'boolean)

;;;; Helpers

;; These helpers are to help me develop this project quickly.

(defvar tangld-db-file (let-alist tangld-project-dirs (f-join .root .build "db"))
  "File where modification dates are kept.")

(defvar tangld-cache-file  (let-alist tangld-project-dirs (f-join .root .build "cache"))
  "File where the library of babel will be cached.")

(defmacro tangld--ignore (&rest _)
  "Do nothing."
  nil)

(defun tangld--message (format-string &rest args)
  "Display message if `tangld-verbose-p' is non-nil."
  (when tangld-verbose-p (message message args)))

(defun tangld--async-tangle (file target)
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

(defun tangld--db-entry (file)
  "Return last recorded time a file as modified or nil if there is none."
  ;; Until we determine what this file is going to contain.
  '(0 0 0 0))

(defun tangld--db-record-entry-date (file date)
  (message "Record %S as date when %s was modified.")
  nil)

;; It is far more useful to have access to the full paths than the components.
(defun tangld--expanded-project-dir-paths ()
  "Return `tangld-project-dirs' with values all expanded."
  (let ((expanded nil)
	(root (alist-get 'root tangld-project-dirs)))
    (dolist (it tangld-project-dirs)
      (let ((name (car it)) (val (cdr it)))
	(push (cons name (expand-file-name val root)) expanded)))
    expanded))

;;;; Initialization - tangld-init

(defun tangld-init ()
  "Setup a new tangld project"
  (interactive)
  (let-alist (tangld--expanded-project-dir-paths tangld-project-dirs)
    (cond ((not (f-exists-p .root)) nil)
	  (tangld-inhibit-init-if-exists
	   (error (format "Aborted init in %s" .root)))
	  ((y-or-n-p (format "WARNING: this will overwrite your project in %s continue?" .root))
	   (f-delete .root t))
	  (t
	   (tangld--message "overwriting %S" .root)))

    ;; either it's a new directory or the old one was deleted
    (tangld--message "creating directories in %s" .root)
    (mapc #'f-mkdir (mapcar #'cdr (tangld--expanded-project-dir-paths tangld-project-dirs)))

    ;; add the lib directory to the list of babel libraries
    (when tangld-add-project-lib-dir-on-init
      (add-to-list 'tangld-babel-library-dirs .lib))

    ;; initialize the version control (git init)
    (when tangld-init-vc-on-init
      (tangld-init--init-vc .root))
    (tangld--message "initialized new tangld project in %s" .root)))

(defun tangld-init--init-vc (&optional vc-root-dir)
  "Initialize the project using magit."
  (let-alist tangld-project-dirs
    (or vc-root-dir (setq vc-root-dir .root))
    (tangld--message "initializing git repo in %s" vc-root-dir)
    (if (featurep 'magit)
	(magit-call-git "init" (magit-convert-filename-for-git (expand-file-name vc-root-dir)))
      (message "Magit package not found"))))

;;;; Configuration - tangld-config

(defun tangld-config (&optional type)
  "Configure tangld. 

Set the source and target directories, Gather system information, and store for
the build step to use. If TYPE is specified store as options for a specific
build type i.e. OS specific, shell options alternate install directory, etc."
  (interactive)
  ;; The user sets options such as cache use, source and target dirs, etc.
  ;; write those to a project specific configuration location so that build
  ;; can use them as it's config when run.

  ;; environmental details
  ;; (list system-type system-name user-full-name)
  (tangld--message "environment details: %s %s %s" system-type system-name user-full-name)

  ;; tangld options
  (tangld--message "tangled-options: %s %s %s" "uh" "don't" "know?")
  ;; language, tangle options, exclusions, overrides,

  ;; build-options
  ;; staging area, copy, link, move, symlink manager
  (tangld--message "staging area: %s, " "don't know")

  ;; write-config
  (let-alist tangld-project-dirs
    (let ((config-file (f-join .root .lib tangld-config-file)))
      (tangld--ignore (f-write config-file))
      (tangld--message "Build options saved to '%s'" config-file))))

;;;; Build - tangld-build

(defun tangld-build (&optional force)
  "Tangle org-mode files in the source dir.

By default, build will only tangle files that have changed since last run."
  (interactive "P")
  ;; - read the config for options pertaining to this build
  (tangld--message "Read config options...")
  ;; config options
  ;; - run the pre-build hooks if any
  (tangld--message "Run `tangld-prebuild-hooks'.")
  (run-hooks 'tangld-prebuild-hooks)

  ;; - load the library-of-babel.
  ;;   - if the user says the cache can be used and there is one
  ;;     - load the cache file.
  ;;   - otherwise
  ;;     - load the library with our org-lib files
  (tangld--message "Load library of babel...")
  (if (and tangld-use-cached-library-p (file-exists-p tangld-cache-file))
      (progn (tangld--message "loading cache file...")
	     (load-file tangld-cache-file))
    (tangld--message "loading org-lib files...")
    ;; TODO
    )

  (when (tangld-cache-org-babel-library-p)
    (tangld-message "store library in cache")
    ;; TODO
    )

  (when (file-exists-p tangld-db-file)
    (message "load db file")
    (load-file tangld-db-file))
  
  (let-alist (tangld--expanded-project-dirs)
    (let ((files (directory-files-recursively .source ".")))
      (unless files (tangld--message "Nothing todo, no files."))
      (dolist (file files)
	(when (or force (file-newer-than-file-p target file))
	  (cl-case tangld-install-type
	    (stage
	     (tangld--async-tangle-file file .build))
	    (link
	     (tangld--async-tangle-file file .install)
	     (f-symlink file target))
	    (stow
	     (tangld--async-tangle-file file .install)
	     ;; TODO: look up stow commands to do this.
	     )
	    (direct
	     (tangld--async-tangle-file file (f-relative it (f-full "~/"))))
	    (nil
	     (tangld--async-tangle-file .install))
	    (t
	     (error "Unknown link type '%S'" type))))
	(tangld--db-record-entry-date file new-mod-date))))
  
  ;; run the post-build hooks if any
  (run-hooks 'tangld-postbuild-hooks))

;;;; Install - tangld-install

(defun tangld-install ()
  "Organize target directories, files and libraries on this system. 

The build step tangles org files into their source, the install step moves them
to their target location."
  (interactive)
  (run-hooks 'tangld-pre-install-hook)
  ;; read the config for options pertaining to the install
  ;; for each file in the build directory
  ;;   identify the install type for this file
  (tangld--ignore
   (let ((files))
     (dolist (file files)
       (f-move from to))))
  (run-hooks 'tangld-post-install-hook))

;;;; Clean - tangld-clean

(defun tangld-clean ()
  "Remove any files or settings created by the build phase."
  (interactive)
  (tangld--message "Remove the cache")
  (when (f-exists-p tangld-cache-file) (f-delete tangld-cache-file))
  (tangld--message "Remove the db")
  (when (f-exists-p tangld-db-file) (f-delete tangld-db-file)))

;;;; Check - tangld-check

(defun tangld-check ()
  "Run tests"
  (interactive)
  ;; The tangld interactive functions we want to test are full of side-effects
  ;; like creating files, and directories. It easier and safer to test these
  ;; commands if they'd only return values instead of creating/deleting files and
  ;; directories. Therefore, I use advices to.

  ;; This should probably be done.
  )

;;; tangld.el ends here
