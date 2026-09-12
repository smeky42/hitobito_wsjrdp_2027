# frozen_string_literal: true

# LOCAL DEV ONLY — never deploy. Loaded ONLY via the gitignored symlink at
# config/initializers/ (created by dev-only-overrides/create_symlinks.sh).
# Shortens the wait before the admin tab's "Imitieren" button can be pressed,
# so the impersonation flow can be walked through quickly. Without this
# override the wait is WsjrdpAdminTabHelper::DEFAULT_IMPERSONATE_DELAY_MS, and
# nothing a request carries can change it.

# Fail-closed tripwire: if this ever reaches production, refuse to boot.
raise "local_dev_only_impersonate_delay present in production!" if Rails.env.production?

# Linking this file in is itself the wish for a shorter wait, so it shortens
# the wait on its own; the settings file only fine-tunes it.
LOCAL_DEV_ONLY_IMPERSONATE_DELAY_MS = 1000

if Rails.env.development?
  # Milliseconds to wait, 0 leaving the button ready at once. Comes from the
  # optional, gitignored wagon settings file -- read once at boot, so restart
  # after changing it:
  #
  #   # <wagon>/config/dev_only_settings.local.yml
  #   dev_only:
  #     impersonate_delay:
  #       milliseconds: 0
  #
  # Without the file (or the key) it is the second above. NOTE: resolve the
  # path via the engine root, NOT via __dir__ -- __dir__ canonicalizes the
  # path and therefore follows the config/initializers symlink back into
  # dev-only-overrides/.
  settings_path =
    HitobitoWsjrdp2027::Wagon.root.join("config", "dev_only_settings.local.yml")
  dev_only_settings =
    File.exist?(settings_path) ? (YAML.safe_load_file(settings_path) || {}) : {}
  configured_ms = dev_only_settings.dig("dev_only", "impersonate_delay", "milliseconds")

  # config.x survives a code reload, unlike anything set on the helper itself.
  Rails.application.config.x.wsjrdp_impersonate_delay_ms =
    configured_ms.nil? ? LOCAL_DEV_ONLY_IMPERSONATE_DELAY_MS : Integer(configured_ms)
end
