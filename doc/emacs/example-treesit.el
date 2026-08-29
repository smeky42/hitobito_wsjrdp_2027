;;; -*- lexical-binding: t; coding: utf-8; -*-

;;
;; EXAMPLE CONFIGURATION -- tree-sitter
;;
;; Companion to example-ruby.el in this directory: it is what turns ruby-mode
;; into ruby-ts-mode.  Optional -- the LSP setup works without it, you
;; just get the older font-lock and no structural navigation.
;;
;; Written for Emacs 31, but degrades gracefully: everything that only
;; exists in Emacs 31 is guarded by feature detection, so Emacs 29/30
;; get the equivalent (manual) setup and an Emacs built without
;; tree-sitter skips the block entirely.

(when (and (fboundp 'treesit-available-p)
           (treesit-available-p)
           (require 'treesit nil t))

  ;; Keep grammar binaries separate per Emacs major version.  Each
  ;; Emacs build links its own libtree-sitter and therefore supports a
  ;; specific grammar ABI range (Emacs 31: 13-15, see
  ;; `treesit-library-abi-version').  Sharing one directory across
  ;; versions means rebuilding for the new Emacs can break the old
  ;; one.  ~/.emacs.d/tree-sitter is still searched afterwards (it is
  ;; the built-in default).
  ;;
  ;; Since Emacs 31 this is also where the grammar auto-installer puts
  ;; newly built grammars (first entry wins); on Emacs 29/30 pass the
  ;; directory to `treesit-install-language-grammar' explicitly.
  (add-to-list 'treesit-extra-load-path
               (expand-file-name (format "tree-sitter-%d" emacs-major-version)
                                 "~/.cache/emacs/"))

  ;; Where grammars are built from when one is missing.  Plain (LANG
  ;; URL) entries work in every Emacs since 29; the :commit keyword to
  ;; pin a revision requires Emacs 31.
  (setopt treesit-language-source-alist
          '((ruby "https://github.com/tree-sitter/tree-sitter-ruby")))

  (if (boundp 'treesit-enabled-modes)
      ;; Emacs 31+: enabling a *-ts-mode here maintains
      ;; `major-mode-remap-alist' and cooperates with
      ;; `treesit-auto-install-grammar' (default `ask'), i.e. a missing
      ;; grammar is offered for installation instead of erroring out.
      (setopt treesit-enabled-modes '(ruby-ts-mode))

    ;; Emacs 29/30: no auto-install and no `treesit-enabled-modes', so
    ;; do the remap by hand -- and only when the grammar really loads,
    ;; because an unconditional remap turns every .rb file into an
    ;; error when the grammar is missing.
    (when (and (fboundp 'ruby-ts-mode)
               (treesit-language-available-p 'ruby))
      (add-to-list 'major-mode-remap-alist '(ruby-mode . ruby-ts-mode)))))

;; expreg: expand-region successor that grows the selection along
;; tree-sitter syntax nodes
(use-package expreg
  :bind (("C-=" . expreg-expand)
         ("C-+" . expreg-contract)))

(provide 'example-treesit)
