# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "json"
require "yaml"

module Wsjrdp::Credentials
  # The kind registry: config/wsjrdp_credential_kinds.yml, committed, without
  # any secret (doc/wsjrdp/credentials.md, "Kinds"). Each entry is a
  # Wsjrdp::Credentials::Kind.
  #
  #   kinds:
  #     <kind>:
  #       title_field: <field>            # optional
  #       remind_days_before: [30, 14, 3] # optional
  #       fields:
  #         <field>: {type: <type>, required: true, secret: true, default: ..., values: [...]}
  #
  # The registry is read strictly: anything it does not understand (an
  # unknown key, a name outside the grammar, an unknown type, a reserved
  # field name, a default that does not fit or sits on a secret field, ...)
  # raises RegistryError, which names the place. The file is committed, so
  # a broken one is a bug in every stage, production included.
  class Kinds
    include Enumerable

    PATH = File.expand_path("../../../../config/wsjrdp_credential_kinds.yml", __dir__)
    SOURCE = "config/wsjrdp_credential_kinds.yml"
    # The names a variable or a file states beside a version's fields, and,
    # as a precaution, json_class: opening reads with JSON.load, which would
    # build an object from a hash with that key.
    RESERVED_FIELD_NAMES = (%w[name created_at valid_from expires_at] + [JSON.create_id]).freeze
    TOP_KEYS = %w[kinds].freeze
    KIND_KEYS = %w[title_field remind_days_before fields].freeze
    FIELD_KEYS = %w[type required secret default values].freeze

    class RegistryError < Error; end

    # A kind the registry does not have.
    class UnknownKind < Error; end

    class << self
      # The registry of the wagon, read once.
      def current = @current ||= load

      def reset! = @current = nil

      def load(path = PATH, source: (path == PATH) ? SOURCE : path)
        data = YAML.safe_load_file(path)
        new(data, source: source)
      rescue Psych::Exception, SystemCallError => e
        raise RegistryError, "#{source}: cannot be read (#{e.class.name}: #{e.message})"
      end
    end

    attr_reader :source

    def initialize(data, source: SOURCE)
      @source = source
      @errors = []
      @kinds = build(data).freeze
      raise RegistryError, "#{source}: #{@errors.join("; ")}" if @errors.any?

      freeze
    end

    # The kind of that name, or nil.
    def [](name) = @kinds[name.to_s]

    # The kind of that name, or UnknownKind.
    def fetch(name)
      self[name] || raise(UnknownKind, "#{source}: no kind #{Wsjrdp::Credentials.shown_name(name)}")
    end

    def names = @kinds.keys

    def each(&) = @kinds.each_value(&)

    def inspect = "#<#{self.class.name} #{names.join(",")}>"
    alias_method :to_s, :inspect

    private

    # Records an error and answers nil, so that `next error(...)` inside a
    # filter_map never keeps anything in the list.
    def error(path, message)
      @errors << "#{path}: #{message}"
      nil
    end

    # Why name is no name (Wsjrdp::Credentials.name?).
    def name_problem(name)
      if Wsjrdp::Credentials.text?(name) && NAME_FORMAT.match?(name)
        "the name is longer than #{NAME_LENGTH} characters"
      else
        "the name is not lower-case snake"
      end
    end

    # Why name cannot be a field's name; nil when it can.
    def field_name_problem(name)
      return name_problem(name) unless Wsjrdp::Credentials.name?(name)

      "the name is reserved" if RESERVED_FIELD_NAMES.include?(name)
    end

    def mapping?(value, path)
      return true if value.is_a?(Hash)

      error(path, "is not a mapping")
      false
    end

    def unknown_keys(hash, allowed, path)
      (hash.keys - allowed).each { |key| error(path, "unknown key #{key.to_s.inspect}") }
    end

    def build(data)
      return {} unless mapping?(data, "(top level)")

      unknown_keys(data, TOP_KEYS, "(top level)")
      kinds = data["kinds"]
      return {} unless mapping?(kinds, "kinds")

      error("kinds", "is empty") if kinds.empty?
      kinds.each_with_object({}) do |(name, spec), result|
        path = "kinds.#{name}"
        unless Wsjrdp::Credentials.name?(name)
          error(path, name_problem(name))
          next
        end
        next unless mapping?(spec, path)

        kind = build_kind(name, spec, path)
        result[name] = kind if kind
      end
    end

    def build_kind(name, spec, path)
      count = @errors.size
      unknown_keys(spec, KIND_KEYS, path)
      fields = build_fields(spec["fields"], "#{path}.fields")
      check_title_field(spec, fields, path)
      check_remind_days_before(spec, path)
      return nil if @errors.size > count

      Kind.new(name: name, fields: fields, title_field: spec["title_field"],
        remind_days_before: spec["remind_days_before"] || [])
    end

    def build_fields(spec, path)
      if spec.nil?
        error(path, "is missing")
        return []
      end
      return [] unless mapping?(spec, path)

      error(path, "is empty") if spec.empty?
      spec.filter_map do |name, field_spec|
        field_path = "#{path}.#{name}"
        problem = field_name_problem(name)
        if problem
          error(field_path, problem)
          next
        end
        next unless mapping?(field_spec, field_path)

        build_field(name, field_spec, field_path)
      end
    end

    def build_field(name, spec, path)
      count = @errors.size
      unknown_keys(spec, FIELD_KEYS, path)
      type = spec["type"]
      error("#{path}.type", "is not one of #{Field::TYPES.join(", ")}") unless Field::TYPES.include?(type)
      %w[required secret].each do |flag|
        error("#{path}.#{flag}", "is not true or false") unless [nil, true, false].include?(spec[flag])
      end
      options = {name: name, type: type, required: spec["required"] == true, secret: spec["secret"] == true,
                 values: check_values(spec, type, path)}
      return nil if @errors.size > count

      default = check_default(Field.new(**options), spec["default"], path)
      return nil if @errors.size > count

      Field.new(**options, default: default)
    end

    def check_values(spec, type, path)
      values = spec["values"]
      if type != "enum"
        error("#{path}.values", "only an enum has values") if spec.key?("values")
      elsif !values.is_a?(Array) || values.empty? || !values.all? { |value| value.is_a?(String) && !value.empty? }
        error("#{path}.values", "is not a list of texts")
      elsif values.uniq.size != values.size
        error("#{path}.values", "names a value twice")
      else
        return values
      end
      nil
    end

    # The default cast for its field; nil when there is none. A secret field
    # has none: the file is committed.
    def check_default(field, default, path)
      return nil if default.nil?
      if field.secret?
        error("#{path}.default", "a secret field has no default")
        return nil
      end

      cast, code = field.cast(default)
      error("#{path}.default", "is no value of the field (#{code})") if code
      cast
    end

    def check_title_field(spec, fields, path)
      return unless spec.key?("title_field")

      title = spec["title_field"]
      field = fields.find { |candidate| candidate.name == title }
      if field.nil?
        error("#{path}.title_field", "is not a field of the kind")
      elsif field.secret?
        error("#{path}.title_field", "is a secret field")
      end
    end

    def check_remind_days_before(spec, path)
      return unless spec.key?("remind_days_before")

      days = spec["remind_days_before"]
      return if days.is_a?(Array) && days.all? { |day| day.is_a?(Integer) && day.positive? }

      error("#{path}.remind_days_before", "is not a list of positive integers")
    end
  end
end
