# frozen_string_literal: true

# LOCAL DEV ONLY — never deploy. Loaded ONLY via the gitignored symlink at
# config/initializers/ (created by dev-only-overrides/create_symlinks.sh).
# Disables login on :3000 for requests without a token; the dev person comes
# from the optional, gitignored config/dev_only_settings.local.yml (default:
# person 1).

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
  # Without the file (or the key) the default is person 1.
  #
  # After changing the id: restart AND sign out once ("Abmelden"). The
  # configured person is only the fallback for "nobody signed in" (see
  # current_person below) -- a person the browser holds in its warden session
  # keeps winning, and remember_for below keeps that session alive for good.
  # Such a session is easy to pick up without noticing: ending an
  # impersonation signs the ORIGIN person in for real, and the origin was the
  # previously simulated person.
  #
  # NOTE: resolve the path via the engine root, NOT via __dir__ -- __dir__
  # canonicalizes the path and therefore follows the config/initializers
  # symlink back into dev-only-overrides/.
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
    # The flip side: whoever is signed in shadows the configured person until
    # you sign out (see the note at the settings file above).
    #
    # (Q3) Requests that carry a token -- a service token (X-Token header or
    # token param) or an OAuth access token (Bearer header or access_token
    # param) -- are left to Hitobito's own sign-in: authenticate_person! runs
    # for them and signs the token in, and no dev person stands in, so
    # current_ability is the token's (TokenAbility / DoorkeeperTokenAbility)
    # exactly as in production. A request without a token keeps the bypass. A
    # person the request's session holds still wins, so a token is tested from
    # a client without the browser's cookies (curl, the scripts).
    ApplicationController.class_eval do
      def wsjrdp_token_request?
        request.authorization.to_s.start_with?("Bearer ") ||
          request.headers["X-Token"].present? ||
          params[:access_token].present? || params[:token].present?
      end

      # Run the authenticate_person! before_action for token requests only.
      def authenticate? = wsjrdp_token_request?

      def current_person
        @current_person ||= warden.user(:person) ||
          (wsjrdp_token_request? ? nil : Person.find(WSJRDP_LOGIN_BYPASS_PERSON_ID))
      end
    end
  end
end
