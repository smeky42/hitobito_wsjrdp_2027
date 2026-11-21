# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Credentials
  # One credential as a consumer gets it: the values of one version of one
  # account, with the kind, the account key, the stage and the fingerprint
  # of the key it was opened with.
  #
  #   credential[:smtp_host]           # a public field
  #   credential.secret(:smtp_password) # a secret field
  #
  # [] refuses a secret field and #secret a public one, so that a secret is
  # only ever read on purpose; an unknown field is an error for both. A field
  # of the kind that is not set is nil.
  #
  # No value ever shows: inspect, to_s, pp, as_json and to_json give the kind,
  # the account key, the stage, the names of the fields that are set and the
  # key's fingerprint; Marshal and YAML refuse.
  class Credential
    include Undumpable

    # A field the kind does not have.
    class UnknownField < Error; end

    # A secret field asked for with [], or a public one with #secret.
    class WrongAccess < Error; end

    attr_reader :kind, :account_key, :stage, :key_fingerprint

    def initialize(kind:, account_key:, stage:, values:, key_fingerprint:)
      unless Wsjrdp::Credentials.name?(account_key)
        raise ArgumentError, "the account key is not lower-case snake of at most #{NAME_LENGTH} characters"
      end
      raise ArgumentError, "the stage is not of a-z and 0-9" unless Wsjrdp::Credentials.stage?(stage)

      @kind = kind
      @account_key = account_key
      @stage = stage
      @key_fingerprint = key_fingerprint
      @values = check_values(values)
      freeze
    end

    def kind_name = kind.name

    # The names of the fields that are set, in the kind's order.
    def field_names = @values.keys

    # A public field.
    def [](name)
      field = field!(name)
      if field.secret?
        raise WrongAccess, "#{kind_name}.#{field.name} is a secret field; read it with #secret(:#{field.name})"
      end

      @values[field.name]
    end

    # A secret field.
    def secret(name)
      field = field!(name)
      unless field.secret?
        raise WrongAccess, "#{kind_name}.#{field.name} is not a secret field; read it with [:#{field.name}]"
      end

      @values[field.name]
    end

    def inspect
      "#<#{self.class.name} #{kind_name}/#{account_key} stage=#{stage} " \
        "fields=#{field_names.join(",")} key=#{key_fingerprint}>"
    end
    alias_method :to_s, :inspect

    def as_json(*)
      {"kind" => kind_name, "account_key" => account_key, "stage" => stage,
       "fields" => field_names, "key_fingerprint" => key_fingerprint}
    end

    private

    def field!(name)
      field = Wsjrdp::Credentials.text?(name.to_s) ? kind.field(name) : nil
      field || raise(UnknownField, "#{kind_name} has no field #{Wsjrdp::Credentials.shown_name(name)}")
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
