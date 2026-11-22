# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Credentials
  # One credential as a consumer gets it: the values of one version.
  #
  #   credential[:smtp_host]            # a public field
  #   credential.secret(:smtp_password) # a secret field
  #
  # [] refuses a secret field and #secret a public one, so that a secret is
  # only read on purpose. A further field (one the kind does not have) is
  # read the same way: [] when public, #secret when sealed. Any other name
  # raises UnknownField. No value and no version name ever shows in
  # inspect, as_json or a dump. A credential from an override has no
  # version_id and no key_fingerprint, and its further fields are public.
  class Credential
    include Undumpable

    class UnknownField < Error; end

    # A secret field asked for with [], or a public one with #secret.
    class WrongAccess < Error; end

    attr_reader :kind, :account_key, :stage, :key_fingerprint, :version_name, :version_id

    # secret_further_fields: the further fields that are sealed.
    def initialize(kind:, account_key:, stage:, values:, key_fingerprint:, version_name: nil, version_id: nil,
      secret_further_fields: [])
      unless Wsjrdp::Credentials.account_key?(account_key)
        raise ArgumentError, "the account key is not of #{ACCOUNT_KEY_RULE}"
      end
      raise ArgumentError, "the stage is not of a-z and 0-9" unless Wsjrdp::Credentials.stage?(stage)
      raise ArgumentError, "the version name is not a String" unless version_name.nil? || version_name.is_a?(String)
      raise ArgumentError, "the version id is not an Integer" unless version_id.nil? || version_id.is_a?(Integer)

      @kind = kind
      @account_key = account_key
      @stage = stage
      @key_fingerprint = key_fingerprint
      @version_name = version_name&.dup&.freeze
      @version_id = version_id
      @values = check_values(values)
      @secret_further_fields = check_secret_further_fields(secret_further_fields)
      freeze
    end

    def kind_name = kind.name

    # The fields that are set: the kind's in its order, then the further
    # ones by name.
    def field_names = @values.keys

    # The further fields that are set, by name.
    def further_field_names = @values.keys.reject { |name| kind.field?(name) }

    # Whether a field is read with #secret: a secret field of the kind, or
    # a sealed further field.
    def secret_field?(name)
      name = Wsjrdp::Credentials.name_of(name)
      kind.field(name)&.secret? || @secret_further_fields.include?(name)
    end

    def [](name)
      name = name!(name)
      if secret_field?(name)
        raise WrongAccess, "#{kind_name}.#{name} is a secret field; read it with #secret(:#{name})"
      end

      @values[name]
    end

    def secret(name)
      name = name!(name)
      raise WrongAccess, "#{kind_name}.#{name} is not a secret field; read it with [:#{name}]" unless secret_field?(name)

      @values[name]
    end

    def inspect
      "#<#{self.class.name} #{kind_name}/#{account_key} stage=#{Wsjrdp::Credentials.shown_stage(stage)} " \
        "fields=#{field_names.join(",")}#{" key=#{key_fingerprint}" if key_fingerprint}" \
        "#{" version=#{version_id}" if version_id}>"
    end
    alias_method :to_s, :inspect

    def as_json(*)
      json = {"kind" => kind_name, "account_key" => account_key, "stage" => Wsjrdp::Credentials.shown_stage(stage),
              "fields" => field_names, "key_fingerprint" => key_fingerprint}
      version_id ? json.merge("version_id" => version_id) : json
    end

    private

    # The name as a String, when it is a field of the kind or a further
    # field of this version.
    def name!(name)
      name = Wsjrdp::Credentials.name_of(name)
      return name if Wsjrdp::Credentials.text?(name) && (kind.field?(name) || @values.key?(name))

      raise UnknownField, "#{kind_name} has no field #{Wsjrdp::Credentials.shown_name(name)}"
    end

    def check_values(values)
      raise ArgumentError, "the values are not a hash" unless values.is_a?(Hash)

      given = values.transform_keys { |name| Wsjrdp::Credentials.name_of(name) }
      wrong = given.keys.reject do |name|
        Wsjrdp::Credentials.text?(name) && (kind.field?(name) || kind.further_name_problem(name).nil?)
      end
      if wrong.any?
        raise ArgumentError, "#{kind_name} has no field #{wrong.map { |name| Wsjrdp::Credentials.shown_name(name) }.join(", ")}"
      end

      names = kind.field_names.select { |name| given.key?(name) } + (given.keys - kind.field_names).sort
      names.filter_map do |name|
        value = given[name]
        next if value.nil?

        [name, value.is_a?(String) ? value.dup.freeze : value]
      end.to_h.freeze
    end

    def check_secret_further_fields(names)
      names = Array(names).map { |name| Wsjrdp::Credentials.name_of(name) }
      unless names.all? { |name| @values.key?(name) && !kind.field?(name) }
        raise ArgumentError, "a secret further field is not a further field that is set"
      end

      names.uniq.freeze
    end
  end
end
