# frozen_string_literal: true

# LOCAL DEV ONLY — never deploy. Loaded ONLY via the gitignored symlink at
# config/initializers/ (created by dev-only-overrides/create_symlinks.sh on
# macOS). Fixes stale code / view-template reloading when the app runs in
# Docker on macOS.
#
# The core configures ActiveSupport::EventedFileUpdateChecker (listen gem /
# inotify). Docker Desktop's macOS bind mounts do not forward inotify events
# into the container, so the watcher never fires — and in Rails 7.1
# config.file_watcher also drives ActionView::CacheExpiry::ViewReloader, so
# edited views/partials keep being served from the compiled-template cache
# until the process restarts. The polling checker re-stats watched files on
# each request instead, which works fine across the bind mount.
#
# Timing: wagon config/initializers run before ActionView's after_initialize
# block and before the routes/code reloader finishers — the places that read
# config.file_watcher — so overriding it here takes effect everywhere.

# Fail-closed tripwire: if this ever reaches production, refuse to boot.
raise "local_dev_only_file_watcher_macos present in production!" if Rails.env.production?

if Rails.env.development?
  Rails.application.config.file_watcher = ActiveSupport::FileUpdateChecker
  puts "[hitobito_wsjrdp_2027] local override: polling file watcher enabled"
end
