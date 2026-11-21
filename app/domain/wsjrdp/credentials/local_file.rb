# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "psych"

module Wsjrdp::Credentials
  # The git-ignored local file config/wsjrdp_credentials.local.yml
  # (doc/wsjrdp/credentials.md, "The local file"): the instance's keys and
  # label, and an override of credentials.
  #
  # Production never reads it, nor does the Rails environment test. A file
  # for another stage, production included, is skipped with a warning.
  # Anything else that is not understood raises ConfigurationError, naming
  # the place in the file, never a value.
  class LocalFile
    include Override::Source
    include Undumpable

    SOURCE = "config/wsjrdp_credentials.local.yml"
    PATH = File.expand_path("../../../../#{SOURCE}", __dir__)
    NAME = "file"

    # What became of the file.
    READ = :read
    ABSENT = :absent
    OTHER_STAGE = :other_stage
    NOT_READ_PRODUCTION = :not_read_production
    NOT_READ_TEST = :not_read_test

    TOP_KEYS = %w[stage keys label credentials].freeze
    ACCOUNT_KEYS = %w[versions].freeze

    # Turns YAML into Hashes, Arrays and Strings only: no object of any
    # class, no alias, no tag but the standard ones for text, a mapping and a
    # list (!!str, !, !!map, !!seq), no key twice, one document.
    # Every scalar is the text as written, quoted or not, so that a value
    # means the same either way (YAML 1.1 would read 0465 as octal, yes as
    # true, 2027-05-19 as a Date); only an empty plain value, null and ~ are
    # nil.
    module Yaml
      # The message names a line, never a value.
      class Refused < StandardError; end

      TAGS = {Psych::Nodes::Scalar => [nil, "!", "tag:yaml.org,2002:str"],
              Psych::Nodes::Mapping => [nil, "tag:yaml.org,2002:map"],
              Psych::Nodes::Sequence => [nil, "tag:yaml.org,2002:seq"]}.freeze
      NULLS = ["", "null", "~"].freeze
      # Far more than the file's shape needs; refused before deep recursion.
      MAX_DEPTH = 32

      module_function

      def load(text)
        documents = Psych.parse_stream(text).children
        raise Refused, "holds more than one document" if documents.size > 1

        documents.empty? ? nil : convert(documents.first.root, 1)
      rescue Psych::SyntaxError => e
        raise Refused, "is not YAML (line #{e.line}, column #{e.column})"
      end

      def convert(node, depth)
        line = "line #{node.start_line + 1}"
        raise Refused, "#{line}: nested deeper than #{MAX_DEPTH} levels" if depth > MAX_DEPTH
        raise Refused, "#{line}: holds an alias" if node.is_a?(Psych::Nodes::Alias)
        raise Refused, "#{line}: holds a tag" unless TAGS.fetch(node.class).include?(node.tag)

        case node
        when Psych::Nodes::Scalar then (node.tag || node.quoted || !NULLS.include?(node.value)) ? node.value : nil
        when Psych::Nodes::Sequence then node.children.map { |child| convert(child, depth + 1) }
        else
          node.children.each_slice(2).with_object({}) do |(key_node, value_node), hash|
            key_line = "line #{key_node.start_line + 1}"
            raise Refused, "#{key_line}: a key that is not a value" unless key_node.is_a?(Psych::Nodes::Scalar)

            key = convert(key_node, depth + 1)
            raise Refused, "#{key_line}: a key given twice" if hash.key?(key)

            hash[key] = convert(value_node, depth + 1)
          end
        end
      end
    end

    class << self
      # The file at path as the boot takes it: not opened in production nor
      # in the Rails environment test (test: true).
      def for_instance(path, stage:, kinds:, test:, source: SOURCE)
        status = if !File.exist?(path) then ABSENT
        elsif stage == PRODUCTION then NOT_READ_PRODUCTION
        elsif test then NOT_READ_TEST
        end
        return new(nil, stage: stage, kinds: kinds, source: source, status: status) if status

        begin
          text = File.binread(path)
        rescue SystemCallError => e
          raise ConfigurationError, "#{source} (stage #{Wsjrdp::Credentials.shown_stage(stage)}): cannot be read " \
            "(#{e.class.name})"
        end
        new(text, stage: stage, kinds: kinds, source: source)
      end
    end

    attr_reader :stage, :status, :file_stage, :source, :accounts, :key_entries, :label

    # text: the file's content; nil with any status but READ.
    def initialize(text, stage:, kinds:, source: SOURCE, status: READ)
      raise ArgumentError, "production never reads the local file" if stage == PRODUCTION && status == READ

      @stage = stage
      @kinds = kinds
      @source = source
      @status = status
      @accounts = {}
      parse(text) if status == READ
      @accounts.freeze
      @key_entries.freeze
      freeze
    end

    def source_name = NAME

    def read? = status == READ

    def keys? = !key_entries.nil?

    # How Wsjrdp::Credentials::Keys names these keys and this label.
    def keys_source = "#{source} keys"

    def label_source = "#{source} label"

    def summary
      case status
      when READ
        names = shown_account_names
        "#{source}: stage #{shown_stage}, #{keys? ? "keys given" : "no keys"}, " \
          "#{names.empty? ? "no override" : "overriding #{names.join(", ")}"}"
      when ABSENT then "#{source}: none"
      when OTHER_STAGE
        "#{source}: the file is for #{shown_file_stage}, this is #{shown_stage}; not read: no key and no credential " \
          "is taken from it"
      when NOT_READ_PRODUCTION then "#{source}: lies here, but is not read in production"
      when NOT_READ_TEST then "#{source}: lies here, but is not read in the Rails environment test"
      end
    end

    def log_summary(logger)
      logger.warn("#{source}: its label is not used, the file gives no keys") if read? && label && !keys?
      case status
      when OTHER_STAGE, NOT_READ_PRODUCTION then logger.warn(summary)
      when ABSENT then logger.debug(summary)
      else logger.info(summary)
      end
      self
    end

    def inspect
      "#<#{self.class.name} #{status} stage=#{shown_stage} accounts=#{shown_account_names.join(",")}>"
    end
    alias_method :to_s, :inspect

    def as_json(*)
      {"source" => source, "status" => status.to_s, "stage" => shown_stage, "file_stage" => shown_file_stage,
       "keys" => keys?, "accounts" => shown_account_names}
    end

    # nil when the file was not read that far.
    def shown_file_stage = file_stage && Wsjrdp::Credentials.shown_stage(file_stage, placeholder: "another stage")

    private

    attr_reader :kinds

    def shown_stage = Wsjrdp::Credentials.shown_stage(stage)

    def shown(name) = Wsjrdp::Credentials.shown_name(name)

    def problem(path, message)
      raise ConfigurationError, "#{source} (stage #{shown_stage}): #{path}: #{message}"
    end

    def unknown_keys(data, known, path)
      (data.keys - known).each { |key| problem(path, "unknown key #{shown(key)}") }
    end

    def parse(text)
      text = text.to_s.b.force_encoding(Encoding::UTF_8)
      problem("(file)", "is not valid UTF-8") unless text.valid_encoding?
      data = begin
        Yaml.load(text)
      rescue Yaml::Refused => e
        problem("(file)", e.message)
      end
      problem("(file)", "is empty; it needs at least its stage") if data.nil?
      problem("(top level)", "is not a mapping") unless data.is_a?(Hash)
      return unless own_stage?(data["stage"])

      unknown_keys(data, TOP_KEYS, "(top level)")
      read_keys(data["keys"])
      read_label(data)
      read_credentials(data["credentials"])
    end

    # A file for another stage is not read any further.
    def own_stage?(file_stage)
      problem("stage", "is missing") if file_stage.nil?
      problem("stage", "is not of a-z and 0-9") unless Wsjrdp::Credentials.stage?(file_stage)

      @file_stage = file_stage
      @status = OTHER_STAGE unless file_stage == stage
      file_stage == stage
    end

    def read_keys(entries)
      return if entries.nil? || entries == []
      problem("keys", "is not a list of texts") unless entries.is_a?(Array) && entries.all?(String)

      @key_entries = entries
    end

    def read_label(data)
      label = data["label"]
      problem("label", "is not a text") unless label.nil? || label.is_a?(String)

      @label = label
    end

    def read_credentials(credentials)
      return if credentials.nil?
      problem("credentials", "is not a mapping") unless credentials.is_a?(Hash)

      credentials.each do |kind_name, accounts|
        path = "credentials.#{shown(kind_name)}"
        unless Wsjrdp::Credentials.name?(kind_name)
          problem(path, "the kind is not lower-case snake of at most #{NAME_LENGTH} characters")
        end
        kind = kinds[kind_name]
        problem(path, "no kind #{kind_name} in #{kinds.source}") unless kind
        problem(path, "is not a mapping") unless accounts.is_a?(Hash)

        accounts.each do |given, spec|
          account_key = Wsjrdp::Credentials.account_key_of(given)
          read_account(kind, account_key, spec, "#{path}.#{Wsjrdp::Credentials.shown_account_key(account_key)}")
        end
      end
    end

    # account_key: folded to lower case and NFC; two keys that fold to the
    # same are one account given twice.
    def read_account(kind, account_key, spec, path)
      unless Wsjrdp::Credentials.account_key?(account_key)
        problem(path, "the account key is not of #{ACCOUNT_KEY_RULE}")
      end
      problem(path, "the account is given twice (keys are folded to lower case)") if @accounts.key?([kind.name, account_key])
      problem(path, "is not a mapping") unless spec.is_a?(Hash)
      unknown_keys(spec, ACCOUNT_KEYS, path)
      list = spec["versions"]
      problem("#{path}.versions", "is not a list of at least one version") unless list.is_a?(Array) && list.any?

      versions = list.each.with_index(1).map do |raw, position|
        version_path = "#{path}.versions[#{position}]"
        problem(version_path, "is not a mapping") unless raw.is_a?(Hash)

        Override.read_version(raw, kind: kind, position: position) do |key, message|
          problem(key ? "#{version_path}.#{key}" : version_path, message)
        end
      end
      @accounts[[kind.name, account_key]] = Override::Account.new(kind: kind, account_key: account_key,
        versions: versions, order: order_of(versions, "#{path}.versions"))
    end

    # Half an order is none: created_at by every version or by none.
    def order_of(versions, path)
      stated = versions.count(&:created_at)
      return Override::BY_LIST if stated.zero?
      return Override::BY_CREATED_AT if stated == versions.size

      problem(path, "created_at is stated by some versions only; state it for every version or for none")
    end
  end
end
