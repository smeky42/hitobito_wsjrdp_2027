# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Credentials
  # The blueprint of a credential, one entry of
  # config/wsjrdp_credential_kinds.yml (Wsjrdp::Credentials::Kinds): its
  # fields in order, which of them are secret, the field shown as an
  # account's name in lists, and the default lead times of an expiry
  # reminder.
  #
  # #cast turns a set of values -- strings from a form or a variable, or
  # typed from YAML -- into the values of a version:
  #
  #   result = kind.cast({"smtp_host" => "mail.example.org", "smtp_port" => "587"}, stage: "production")
  #   result.valid?    # => false: mail_from is required
  #   result.errors    # => [#<data Problem field="mail_from", code=:required>]
  #
  # A field the kind does not have is an error; nil and "" count as not set;
  # a field that is not set gets its default; a required field that is still
  # not set is an error. Errors and warnings name the field and a code, never
  # a value.
  class Kind
    # One error or warning: a field's name and a code.
    Problem = Data.define(:field, :code) do
      def to_s = "#{field}: #{code}"
    end

    # The cast values (only the fields that are set, in the kind's order), the
    # errors and the warnings. A plain class, not a Data: a Data would hand
    # its values out through to_h, deconstruct_keys and ActiveSupport's
    # as_json. inspect, to_s, pp, as_json and to_json show field names and
    # codes only; Marshal and YAML refuse.
    class Result
      include Undumpable

      attr_reader :values, :errors, :warnings

      def initialize(values:, errors:, warnings:)
        @values = values.freeze
        @errors = errors.freeze
        @warnings = warnings.freeze
        freeze
      end

      def valid? = errors.empty?

      def inspect
        "#<#{self.class.name} fields=#{values.keys.join(",")} errors=#{errors.join(", ")} " \
          "warnings=#{warnings.join(", ")}>"
      end
      alias_method :to_s, :inspect

      def as_json(*)
        {"fields" => values.keys, "errors" => errors.map { |problem| problem_json(problem) },
         "warnings" => warnings.map { |problem| problem_json(problem) }}
      end

      private

      def problem_json(problem) = {"field" => problem.field, "code" => problem.code.to_s}
    end

    attr_reader :name, :fields, :title_field, :remind_days_before

    def initialize(name:, fields:, title_field: nil, remind_days_before: [])
      @name = name
      @fields = fields.dup.freeze
      @fields_by_name = fields.to_h { |field| [field.name, field] }.freeze
      @title_field = title_field
      @remind_days_before = remind_days_before.dup.freeze
      freeze
    end

    # The field of that name, or nil.
    def field(name) = @fields_by_name[name.to_s]

    def field?(name) = @fields_by_name.key?(name.to_s)

    def field_names = fields.map(&:name)

    def secret_field_names = fields.select(&:secret?).map(&:name)

    def public_field_names = fields.reject(&:secret?).map(&:name)

    def cast(values, stage:)
      raise ArgumentError, "the values are not a hash" unless values.nil? || values.is_a?(Hash)

      errors = []
      given = cast_given(values || {}, errors)
      fill_defaults(given, errors)
      values = fields.filter_map { |field| [field.name, given[field.name]] if given.key?(field.name) }.to_h
      warnings = fields.filter_map do |field|
        code = values.key?(field.name) && field.warning(values[field.name], stage: stage)
        Problem.new(field.name, code) if code
      end
      Result.new(values: values, errors: errors, warnings: warnings)
    end

    def inspect = "#<#{self.class.name} #{name} fields=#{field_names.join(",")}>"
    alias_method :to_s, :inspect

    private

    def cast_given(values, errors)
      values.each_with_object({}) do |(key, value), given|
        name = key.is_a?(Symbol) ? key.to_s : key
        field = Wsjrdp::Credentials.text?(name) ? field(name) : nil
        next errors << Problem.new(Wsjrdp::Credentials.shown_name(name), :unknown) unless field
        next if value.nil? || value == ""

        cast, code = field.cast(value)
        code ? errors << Problem.new(name, code) : given[name] = cast
      end
    end

    def fill_defaults(given, errors)
      fields.each do |field|
        next if given.key?(field.name) || errors.any? { |problem| problem.field == field.name }

        if !field.default.nil?
          given[field.name] = field.default
        elsif field.required?
          errors << Problem.new(field.name, :required)
        end
      end
    end
  end
end
