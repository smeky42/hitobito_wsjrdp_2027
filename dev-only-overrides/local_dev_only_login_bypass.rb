# frozen_string_literal: true

# LOCAL DEV ONLY — never deploy. Loaded ONLY via the gitignored symlink at
# config/initializers/ (created by dev-only-overrides/create_symlinks.sh).
# Disables login on :3000; the dev person comes from the optional, gitignored
# config/dev_only_settings.local.yml (default: person 1).

# Fail-closed tripwire: if this ever reaches production, refuse to boot.
raise "local_dev_only_login_bypass present in production!" if Rails.env.production?

if Rails.env.development?
  # The person to act as (people.id) comes from the optional, gitignored
  # wagon settings file -- read once at boot, so restart after changing it:
  #
  #   # <wagon>/config/dev_only_settings.local.yml
  #   dev_only:
  #     login_bypass:
  #       current_user_person_id: 42
  #
  # Without the file (or the key) the default is person 1. NOTE: resolve the
  # path via the engine root, NOT via __dir__ -- __dir__ canonicalizes the
  # path and therefore follows the config/initializers symlink back into
  # dev-only-overrides/.
  settings_path =
    HitobitoWsjrdp2027::Wagon.root.join("config", "dev_only_settings.local.yml")
  dev_only_settings =
    File.exist?(settings_path) ? (YAML.safe_load_file(settings_path) || {}) : {}
  configured_id = dev_only_settings.dig("dev_only", "login_bypass", "current_user_person_id")
  WSJRDP_LOGIN_BYPASS_PERSON_ID = configured_id.nil? ? 1 : Integer(configured_id)

  Rails.application.config.to_prepare do
    # (Q1) never expire a remembered login
    Devise.remember_for = 200.years
    Devise.timeout_in = 200.years        # belt-and-suspenders; timeoutable is already off

    # (Q2) don't require a login — fall back to the configured dev person when
    # nobody is signed in. The warden session stays authoritative so
    # sign_in-based features (impersonation!) keep working: "Imitieren" signs
    # the target person in, and we must NOT override that with the fixed person.
    ApplicationController.class_eval do
      def authenticate? = false            # skip the authenticate_person! before_action

      def current_person
        @current_person ||= warden.user(:person) || Person.find(WSJRDP_LOGIN_BYPASS_PERSON_ID)
      end
    end
  end
end
