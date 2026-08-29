;;; -*- lexical-binding: t; coding: utf-8; -*-

;;
;; EXAMPLE CONFIGURATION -- Ruby / Rails / hitobito
;;
;; Working copy from one developer's setup, kept here so the next
;; person does not have to reinvent it.  See README.md in this
;; directory for the project-side setup (setup-ruby-lsp.sh) and for
;; what each package buys you.
;;
;; Requires use-package.  Packages come from MELPA: envrc, haml-mode,
;; rspec-mode, inf-ruby, projectile-rails, lsp-mode.

;; envrc: apply the direnv (.envrc) environment buffer-locally.  This
;; makes rbenv, GEM_HOME/PATH and the RAILS_DB_* variables visible to
;; lsp-mode (which needs to find `ruby-lsp'), rspec-mode and
;; M-x compile.  Without it Emacs sees none of the project setup.
(use-package envrc
  :if (executable-find "direnv")
  :hook (after-init . envrc-global-mode))

(defun my/ruby-mode-hook ()
  (eldoc-mode)
  (whitespace-mode t)
  (setq show-trailing-whitespace t)
  (lsp-deferred))

(use-package ruby-mode :ensure nil
  ;; hitobito Wagonfiles are Ruby; ruby-mode is remapped to
  ;; ruby-ts-mode via `treesit-enabled-modes' (see example-treesit.el)
  :mode "Wagonfile\\(\\.[a-z]+\\)?\\'"
  :hook ((ruby-mode ruby-ts-mode) . my/ruby-mode-hook))

;; HAML, the hitobito view language.  No LSP and no tree-sitter
;; grammar exist for HAML; embedded Ruby is still checked by RuboCop
;; through ruby-lsp when the file is a .rb partial.
(use-package haml-mode
  :mode "\\.haml\\'")

;; RSpec: activates itself in ruby(-ts)-mode buffers via its autoloads.
;; C-c , v (verify file), C-c , s (example at point), C-c , t (toggle
;; spec/target), C-c , r (rerun), C-c , f (rerun failures).
;; Runs `bundle exec rspec' from the repo of the visited file, i.e. on
;; the host against the containerized postgres.
(use-package rspec-mode
  :functions rspec-install-snippets
  :custom
  (rspec-use-spring-when-possible nil "No spring on the host")
  :config
  (with-eval-after-load 'yasnippet
    (rspec-install-snippets)))

;; Ruby REPL: M-x inf-ruby-console-auto in the core repo for a rails
;; console; `hit rails attach' in a terminal attaches to pry in Docker
(use-package inf-ruby
  :hook ((ruby-mode ruby-ts-mode) . inf-ruby-minor-mode))

;; Rails navigation on top of projectile (C-c r ...); mainly useful in
;; the hitobito core repo (the wagon has no config/environment.rb)
(use-package projectile-rails
  :hook (after-init . projectile-rails-global-mode))

(provide 'example-ruby)
