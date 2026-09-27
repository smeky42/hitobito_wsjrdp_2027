# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # An API key's token is shown once, in the answer to the request that makes
  # it. The token is 50 random characters and never holds a ":".
  #
  # The token column holds one of three forms, chosen as the token is made
  # (token_kind):
  # - "hmac" -- "hmac-sha256:<hex>": the HMAC-SHA256 of the token with a secret
  #   of HITOBITO_SERVICE_TOKEN_HMAC_KEYS (Wsjrdp2027::ServiceTokenHmacKeys),
  #   the active one of this stage. The stage column names the stage, the
  #   hmac_secret_key_fingerprint column the secret. It works only in its stage and
  #   only where its secret is accepted, so a production token does not work
  #   in a development copy of the database and a development token does not
  #   work in production.
  # - "sha256" -- "sha256:<hex>": the SHA-256 of the token; works in every
  #   stage.
  # - "plain" -- the token itself, as the core stores it; works in every stage
  #   and can be read by anyone who reads the table.
  # A fourth kind, "adopt", stores the HMAC token hash of a token made in
  # another stage (adopted_stage, adopted_token), e.g. a development token
  # registered in production: it comes back with the next production dump
  # and works in development. The fingerprint of its secret may be given
  # (adopted_fingerprint); else its first use there fills it in.
  #
  # API keys are made in the root group (layer); only an admin manages them,
  # and shows and deletes those of other layers (Wsjrdp2027::ServiceTokenAbility).
  #
  # An acting person (acting_person_id) makes the token act within that
  # person's rights too (Wsjrdp2027::ActingPersonTokenAbility). Only an admin
  # sets or changes it.
  #
  # The scopes (scopes, Wsjrdp2027::ServiceTokenScopes) name what the API key
  # reaches. The bases of the core areas mirror the core's boolean columns:
  # the columns lead where they change (the core's form), the scopes lead
  # where only they change (a script). An extra sets its base with it, and
  # works only with an acting person (effective_scopes). The finance scopes
  # give the substitute person their finance permissions; only an admin
  # changes them (Wsjrdp2027::TokenAbility).
  #
  # "Token neu erzeugen" keeps an HMAC token an HMAC token and a "sha256"
  # token a "sha256" one; a plain token may stay plain or become "sha256" or
  # "hmac" (regenerate_kinds).
  module ServiceToken
    extend ActiveSupport::Concern

    DIGEST_PREFIX = "sha256:"
    HMAC_PREFIX = "#{ServiceTokenHmacKeys::SCHEME}:".freeze
    # An HMAC token hash, as another stage made it.
    HMAC_FORMAT = /\A#{ServiceTokenHmacKeys::SCHEME}:\h{64}\z/
    TOKEN_KINDS = %w[hmac sha256 plain adopt].freeze

    prepended do
      include WsjrdpSchemaValidationHelper

      # additional_info and scopes are NOT NULL with {} and [] as defaults, and
      # validates_by_schema (core) requires presence of every NOT NULL column
      # -- which {} and [] fail. Nil stays refused by normalising it.
      remove_schema_validations :additional_info, only: :presence
      remove_schema_validations :scopes, only: :presence
      before_validation { self.additional_info ||= {} }
      before_validation :normalize_scopes
      validate :scopes_known
      validate :finance_scopes_assignable

      # The key itself: set on the object that made it, nil on every object
      # read from the database.
      attr_reader :plain_token
      # How the token of an API key being made is stored (TOKEN_KINDS; "hmac"
      # when blank), and the stage, token hash and (optional) secret
      # fingerprint adopted for "adopt".
      attr_accessor :token_kind, :adopted_stage, :adopted_token, :adopted_fingerprint
      # The person who sets acting_person_id (the controller's
      # current_person); nil outside a request, where no check applies.
      attr_accessor :acting_person_assigner

      belongs_to :acting_person, class_name: "Person", optional: true
      validate :acting_person_assignable, if: :will_save_change_to_acting_person_id?

      validates :token_kind, inclusion: {in: TOKEN_KINDS}, allow_blank: true, on: :create
      validate :token_made
      validate :layer_is_root_group, if: :will_save_change_to_layer_group_id?
    end

    class_methods do
      def hmac_keys = ServiceTokenHmacKeys.current

      def digest_token(plain_token)
        "#{DIGEST_PREFIX}#{OpenSSL::Digest::SHA256.hexdigest(plain_token.to_s)}"
      end

      # :hmac, :sha256 or :plain -- the form a value of the token column has.
      def token_scheme(value)
        value = value.to_s
        if value.start_with?(HMAC_PREFIX) then :hmac
        elsif value.start_with?(DIGEST_PREFIX) then :sha256
        else
          :plain
        end
      end

      # Whether person may set a token's acting person: an admin, a role with
      # the admin permission.
      def acting_person_admin?(person) = person&.groups_with_permission(:admin).present?

      # Whether a value of the token column is a hash, not a key.
      def hashed_token?(value) = token_scheme(value) != :plain

      # The API key whose token is plain_token, in any of the three forms --
      # the HMAC form only of this stage and with a secret accepted here. Nil
      # for a blank token and for anything with a ":", a stored value
      # included. An HMAC token with a fingerprint matches only with that
      # secret; one without (adopted) gets the fingerprint of the secret that
      # matched.
      def find_by_plain_token(plain_token)
        return nil if plain_token.blank? || !plain_token.is_a?(String) || plain_token.include?(":")

        keys = hmac_keys
        hmac = keys.keys.to_h { |key| [key.digest(plain_token), key] }
        found = where(token: hmac.keys, stage: keys.stage)
          .or(where(token: [digest_token(plain_token), plain_token]))
          .first
        key = found && hmac[found.token]
        return nil if key && found.hmac_secret_key_fingerprint.present? && found.hmac_secret_key_fingerprint != key.fingerprint

        found.update_column(:hmac_secret_key_fingerprint, key.fingerprint) if key && found.hmac_secret_key_fingerprint.blank?
        found
      end
    end

    # Sets the scopes a script names, the core areas' columns following them
    # (normalize_scopes).
    def scopes=(value)
      @scopes_set_directly = true
      super
    end

    # The scopes beyond the core's columns -- finance and the extras -- as the
    # wagon's form sends them; they replace the stored ones of that kind.
    def wagon_scopes=(value)
      @wagon_scopes = Array(value).map(&:to_s).compact_blank
    end

    def wagon_scopes = scopes - ServiceTokenScopes::CORE_AREAS

    # The scopes that work: the extras only with an acting person.
    def effective_scopes
      acting_person_id ? scopes : scopes.reject { |scope| ServiceTokenScopes.extra?(scope) }
    end

    # Whether the API key may :log the core area (people, groups, events).
    def log_scope?(area)
      scope = ServiceTokenScopes.log_scope(area)
      scope.present? && effective_scopes.include?(scope)
    end

    # Drops the extras, stored and sent by the form, which work only with an
    # acting person.
    def drop_extra_scopes
      extra = ->(scope) { ServiceTokenScopes.extra?(scope) }
      @wagon_scopes = @wagon_scopes.reject(&extra) if @wagon_scopes
      self[:scopes] = scopes.reject(&extra)
    end

    # The finance permissions the effective finance scopes give, ascending.
    def finance_permissions
      held = effective_scopes.filter_map { |scope| ServiceTokenScopes::FINANCE_PERMISSIONS[scope] }
      FinanceAccess::FINANCE_TIERS & held
    end

    # The highest finance permission held, the cap of the substitute person's
    # and of an acting person's finance tier (Wsjrdp2027::FinanceCap).
    def finance_cap = finance_permissions.last || FinanceCap::NONE

    # The core's substitute person, with the finance permissions of the
    # scopes on its role (Wsjrdp2027::TokenAbility).
    def dynamic_user
      super.tap do |person|
        role = person.roles.first
        role.permissions = role.permissions + finance_permissions
      end
    end

    # The core's ability of the substitute person, capped at its highest
    # finance permission: that counts as picked, so the manage tier applies
    # too (Wsjrdp2027::FinanceCap).
    def dynamic_user_ability
      @dynamic_user_ability ||= ::Ability.new(dynamic_user, max_finance_permission: finance_cap)
    end

    # The kinds "Token neu erzeugen" may give this token: a plain token plain,
    # "sha256" or "hmac", a "sha256" token "sha256" or "hmac", an HMAC token
    # "hmac" -- "hmac" only where this stage has a secret. An HMAC token of
    # another stage gets its new key there.
    def regenerate_kinds
      hmac = self.class.hmac_keys.active ? %w[hmac] : []
      case self.class.token_scheme(token)
      when :plain then %w[plain sha256] + hmac
      when :sha256 then %w[sha256] + hmac
      else
        (token_reach == :other_stage) ? [] : hmac
      end
    end

    # Replaces the token with a new one of kind (regenerate_kinds; the first
    # by default); the old token stops working at once. An "hmac" token uses
    # the active secret. The new token is plain_token until this object is
    # gone. Raises ActiveRecord::RecordInvalid when the kind is not allowed or
    # no token can be made.
    def regenerate_token!(kind = nil)
      kind = kind.presence || regenerate_kinds.first
      unless regenerate_kinds.include?(kind)
        errors.add(:base, :regenerate_kind_refused)
        raise ActiveRecord::RecordInvalid, self
      end

      make_token(kind)
      save!
    end

    # Where this API key's token works: :here, :other_stage, :key_missing
    # (its stage, but a secret not accepted here) or :key_unknown (its stage,
    # adopted and not used yet, so its secret is not known); :everywhere for
    # the forms bound to no stage.
    def token_reach
      return :everywhere unless self.class.token_scheme(token) == :hmac

      keys = self.class.hmac_keys
      if stage != keys.stage then :other_stage
      elsif hmac_secret_key_fingerprint.blank? then :key_unknown
      elsif keys.accepted?(hmac_secret_key_fingerprint) then :here
      else
        :key_missing
      end
    end

    private

    # The core's before_validation on create.
    def generate_token!
      make_token(token_kind.presence || "hmac")
    end

    # An "hmac" token uses the active secret and records the stage and the
    # secret's fingerprint; the other kinds are bound to no stage.
    # Devise.friendly_token draws from the URL-safe Base64 alphabet
    # (A-Z, a-z, 0-9, "-", "_"), so a token never holds a ":"; the check keeps
    # it so should that alphabet change.
    def make_token(kind)
      @token_error = nil
      return adopt_value if kind == "adopt"
      return unless TOKEN_KINDS.include?(kind)

      key = self.class.hmac_keys.active if kind == "hmac"
      return @token_error = [:base, :hmac_key_missing] if kind == "hmac" && key.nil?

      loop do
        plain_token = Devise.friendly_token(50)
        next if plain_token.include?(":")

        stored = stored_value(kind, plain_token, key)
        next if self.class.exists?(token: stored)

        @plain_token = plain_token
        self.token = stored
        self.stage = key&.stage
        self.hmac_secret_key_fingerprint = key&.fingerprint
        break
      end
    end

    def stored_value(kind, plain_token, key)
      case kind
      when "hmac" then key.digest(plain_token)
      when "sha256" then self.class.digest_token(plain_token)
      else plain_token
      end
    end

    def adopt_value
      adopt_stage = adopted_stage.to_s.strip
      value = adopted_token.to_s.strip.downcase
      error = adopt_stage_error(adopt_stage)
      return @token_error = [:adopted_stage, error] if error
      return @token_error = [:adopted_token, :adopt_format] unless HMAC_FORMAT.match?(value)

      fingerprint = adopted_fingerprint.to_s.strip.presence
      if fingerprint && !ServiceTokenHmacKeys::FINGERPRINT_FORMAT.match?(fingerprint)
        return @token_error = [:adopted_fingerprint, :adopt_fingerprint_format]
      end

      @plain_token = nil
      self.token = value
      self.stage = adopt_stage
      self.hmac_secret_key_fingerprint = fingerprint
    end

    def adopt_stage_error(adopt_stage)
      if adopt_stage.empty? then :blank
      elsif !ServiceTokenHmacKeys::STAGE_FORMAT.match?(adopt_stage) then :adopt_stage_format
      elsif adopt_stage == ServiceTokenHmacKeys::PRODUCTION then :adopt_production
      elsif adopt_stage == self.class.hmac_keys.stage then :adopt_own_stage
      end
    end

    # The wagon's form's scopes replace the stored ones beyond the core
    # columns; an extra adds its base; then the core areas and their columns
    # agree -- the columns lead unless only the scopes were set.
    def normalize_scopes
      list = Array(scopes).map(&:to_s).compact_blank
      list = (list & ServiceTokenScopes::CORE_AREAS) + @wagon_scopes if @wagon_scopes
      list |= list.select { |scope| ServiceTokenScopes.extra?(scope) }.map { |scope| ServiceTokenScopes.base_of(scope) }

      columns_changed = ServiceTokenScopes::CORE_AREAS.any? { |area| will_save_change_to_attribute?(area) }
      ServiceTokenScopes::CORE_AREAS.each do |area|
        if @scopes_set_directly && !columns_changed
          self[area] = list.include?(area)
        elsif list.include?(ServiceTokenScopes.log_scope(area).to_s)
          self[area] = true
        end
      end
      list = (list - ServiceTokenScopes::CORE_AREAS) + ServiceTokenScopes::CORE_AREAS.select { |area| self[area] }
      self[:scopes] = ServiceTokenScopes.ordered(list) + (list - ServiceTokenScopes::ALL)
      @scopes_set_directly = false
      @wagon_scopes = nil
    end

    def scopes_known
      unknown = scopes.reject { |scope| ServiceTokenScopes.known?(scope) }
      errors.add(:scopes, :unknown_scope, scopes: unknown.join(", ")) if unknown.any?
    end

    # Only an admin changes the finance scopes, as only an admin hands out a
    # finance role.
    def finance_scopes_assignable
      return if acting_person_assigner.nil? || self.class.acting_person_admin?(acting_person_assigner)

      finance = ->(list) { Array(list).select { |scope| ServiceTokenScopes.finance?(scope) }.sort }
      return if finance.call(scopes) == finance.call(scopes_in_database)

      errors.add(:scopes, :finance_not_assignable)
    end

    def acting_person_assignable
      return errors.add(:acting_person_id, :acting_person_missing) if acting_person_id && acting_person.nil?
      return if acting_person_assigner.nil? || self.class.acting_person_admin?(acting_person_assigner)

      errors.add(:acting_person_id, :acting_person_not_assignable)
    end

    # An API key is made in the root group (Group.root) and stays there: the
    # check runs when the layer is set or changed, so an API key of another
    # layer -- which admins show and delete (Wsjrdp2027::ServiceTokenAbility)
    # -- still saves its last access. A missing layer is left to the core's
    # presence check.
    def layer_is_root_group
      return if layer_group_id.nil? || layer_group_id == ::Group.root&.id

      errors.add(:layer, :not_root)
    end

    # A key that could not be made names its reason instead of the core's
    # "can't be blank" on the token.
    def token_made
      return unless @token_error

      errors.delete(:token)
      attribute, error = @token_error
      errors.add(attribute, error, stage: self.class.hmac_keys.stage)
    end
  end
end
