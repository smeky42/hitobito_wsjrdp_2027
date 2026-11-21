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
  # only read on purpose. No value and no version name ever shows in
  # inspect, as_json or a dump.
  class Credential
    include Undumpable

    class UnknownField < Error; end

    # A secret field asked for with [], or a public one with #secret.
    class WrongAccess < Error; end

    attr_reader :kind, :account_key, :stage, :key_fingerprint, :version_name, :version_id

    def initialize(kind:, account_key:, stage:, values:, key_fingerprint:, version_name: nil, version_id: nil)
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
      freeze
    end

    def kind_name = kind.name

    # The fields that are set, in the kind's order.
    def field_names = @values.keys

    def [](name)
      field = field!(name)
      if field.secret?
        raise WrongAccess, "#{kind_name}.#{field.name} is a secret field; read it with #secret(:#{field.name})"
      end

      @values[field.name]
    end

    def secret(name)
      field = field!(name)
      unless field.secret?
        raise WrongAccess, "#{kind_name}.#{field.name} is not a secret field; read it with [:#{field.name}]"
      end

      @values[field.name]
    end

    def inspect
      "#<#{self.class.name} #{kind_name}/#{account_key} stage=#{Wsjrdp::Credentials.shown_stage(stage)} " \
        "fields=#{field_names.join(",")} key=#{key_fingerprint}#{" version=#{version_id}" if version_id}>"
    end
    alias_method :to_s, :inspect

    def as_json(*)
      json = {"kind" => kind_name, "account_key" => account_key, "stage" => Wsjrdp::Credentials.shown_stage(stage),
              "fields" => field_names, "key_fingerprint" => key_fingerprint}
      version_id ? json.merge("version_id" => version_id) : json
    end

    private

    def field!(name)
      kind.field(name) || raise(UnknownField, "#{kind_name} has no field #{Wsjrdp::Credentials.shown_name(name)}")
    end

    def check_values(values)
      raise ArgumentError, "the values are not a hash" unless values.is_a?(Hash)

      given = values.transform_keys(&:to_s)
      unknown = given.keys.reject { |name| Wsjrdp::Credentials.text?(name) && kind.field?(name) }
      if unknown.any?
        raise ArgumentError, "#{kind_name} has no field #{unknown.map { |name| Wsjrdp::Credentials.shown_name(name) }.join(", ")}"
      end

      kind.fields.filter_map do |field|
        value = given[field.name]
        next if value.nil?

        [field.name, value.is_a?(String) ? value.dup.freeze : value]
      end.to_h.freeze
    end
  end
end
