;;; tangld-install.el --- literate config development environment -*- lexical-binding: t; -*-
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

(defcustom tangld-pre-install-hook nil
  "Hook run before `tangld-install' is called."
  :group 'tangld
  :type 'hook)

(defcustom tangld-post-install-hook nil
  "Hook run after `tangld-install' is called."
  :group 'tangld
  :type 'hook)

(defcustom tangld-install-type 'link
  "How to install dotfiles on to the system."
  :group 'tangld
  :type 'symbol
  :set #'tangld--update-install-fn)

(defcustom tangld-install-fn #'tangld--install-link
  "Function used to install file to."
  :group 'tangld
  :type 'symbol
  :set #'tangld--update-install-type)

(defun tangld--update-install-fn () nil)

(defun tangld--update-install-type () nil)

(defun tangld--install (file)
  "Apply appropriate install action based on `tangld-install-type'."
  (funcall tangld-install-fn file))

(defun tangld--install-direct (file)
  "Move FILE from build-dir to system-dir."
  (let ((target (funcall tangld-build-target-fn file)))
    (unless (f-exists-p (f-parent target))
      (mkdir (f-parent target) t))
    (f-move file target)
    (tangld--message "move %s -> %s" (f-abbrev file) (f-abbrev target))))

(defun tangld--install-link (file)
  "Symlink FILE to system-dir."
  (let ((target (funcall tangld-build-target-fn file)))
    (unless (f-symlink-p file)
      (f-symlink file target)
      (tangld--message "symlink %s -> %s" (f-abbrev file) (f-abbrev target)))))

(defun tangld--install-stow (file)
  "Use stow to symlink file."
  (tangld--message "Not yet implemented."))

;;;###autoload
(defun tangld-install ()
  "Symlink files in dotfiles directory to system directory."
  (interactive)
  (run-hooks 'tangld-pre-install-hook)
  (let ((build-dir (alist-get 'build tangld-project-dirs))
	(files (directory-files-recursively build-dir ".")))
    (mapc #'tangld--install files))
  (run-hooks 'tangld-post-install-hook))

(provide 'tangld-install)
