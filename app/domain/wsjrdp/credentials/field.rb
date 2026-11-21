# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "uri"

module Wsjrdp::Credentials
  # One field of a kind (config/wsjrdp_credential_kinds.yml): its name, its
  # type, whether it is required or secret, its default and, for an enum,
  # its values. Casts one value that is set; Wsjrdp::Credentials::Kind#cast
  # does the rest (unset values, defaults, required fields).
  #
  # The types and what a value becomes:
  #
  # - string: a String, as given;
  # - email: a String of the form of an address;
  # - integer: an Integer, from an Integer or from decimal digits with an
  #   optional sign ("587");
  # - boolean: true or false, from true/false or "true"/"false"/"1"/"0";
  # - enum: a String, one of the field's values;
  # - url: a String, an absolute http or https URL with a host and without
  #   user info. One that is not https is a warning in production
  #   (#warning), never an error.
  #
  # Nothing is stripped: " 587" is no integer. A String of invalid encoding
  # is no value of any type (not_valid_text). A cast answers an error code,
  # never the value.
  class Field
    TYPES = %w[email string integer enum boolean url].freeze
    INTEGER_FORMAT = /\A[+-]?\d+\z/
    BOOLEANS = {true => true, false => false, "true" => true, "false" => false, "1" => true, "0" => false}.freeze

    attr_reader :name, :type, :default, :values

    def initialize(name:, type:, required: false, secret: false, default: nil, values: nil)
      @name = name
      @type = type
      @required = required
      @secret = secret
      @values = values&.dup&.freeze
      @default = default
      freeze
    end

    def required? = @required

    def secret? = @secret

    # [cast value, nil] or [nil, error code] for a value that is set. A
    # String of invalid encoding is not_valid_text for every type.
    def cast(value)
      return failure(:not_valid_text) if value.is_a?(String) && !value.valid_encoding?

      case type
      when "string" then value.is_a?(String) ? ok(value) : failure(:not_a_string)
      when "email" then cast_email(value)
      when "integer" then cast_integer(value)
      when "boolean" then BOOLEANS.key?(value) ? ok(BOOLEANS[value]) : failure(:not_a_boolean)
      when "enum" then values.include?(value) ? ok(value) : failure(:not_in_values)
      when "url" then cast_url(value)
      else raise ArgumentError, "unknown type #{type}"
      end
    end

    # The warning code for a cast value in stage, or nil.
    def warning(value, stage:)
      return nil unless type == "url" && stage == PRODUCTION

      URI.parse(value).scheme.casecmp?("https") ? nil : :not_https
    end

    def inspect = "#<#{self.class.name} #{name} #{type}#{" secret" if secret?}#{" required" if required?}>"
    alias_method :to_s, :inspect

    private

    def ok(value) = [value, nil]

    def failure(code) = [nil, code]

    def cast_email(value)
      return failure(:not_a_string) unless value.is_a?(String)

      URI::MailTo::EMAIL_REGEXP.match?(value) ? ok(value) : failure(:not_an_email)
    end

    def cast_integer(value)
      return ok(value) if value.is_a?(Integer)
      return failure(:not_an_integer) unless value.is_a?(String) && INTEGER_FORMAT.match?(value)

      ok(Integer(value, 10))
    end

    def cast_url(value)
      return failure(:not_a_string) unless value.is_a?(String)

      uri = URI.parse(value)
      valid = uri.is_a?(URI::HTTP) && uri.absolute? && !uri.host.to_s.empty? && uri.userinfo.nil?
      valid ? ok(value) : failure(:not_a_url)
    rescue URI::InvalidURIError
      failure(:not_a_url)
    end
  end
end
