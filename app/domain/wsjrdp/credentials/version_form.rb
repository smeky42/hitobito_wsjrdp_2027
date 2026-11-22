# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Credentials
  # The form of a version (doc/wsjrdp/credentials.md, "The pages"): what
  # it shows, and what a sent form hands to Deposit or Change.
  #
  #   form = VersionForm.of(row, kind: kind, secret_values: opened)  # to edit a version
  #   submitted = VersionForm.submitted(kind: kind, params: params[:credential], base: form)
  #   Change.call(record: row, values: submitted.changed_values, **submitted.changed_attributes)
  #
  # Values become a plain Hash of Strings, never request parameters. The
  # edit form never shows an encrypted public field. A field counts as
  # changed only if it differs from what the form showed; an emptied
  # secret field is removed. Times are in UTC or in the app's time zone.
  #
  # Further fields (fields the kind does not have) are rows of the form.
  # An existing field keeps its name and stays public or encrypted; only a
  # new row can be set to encrypted. An encrypted one is filled in like a
  # secret field.
  class VersionForm
    include Undumpable

    # One row of further fields. was: the existing field it shows, nil for
    # a new row; sealed: the field is encrypted; seal: a new row to be
    # encrypted. It may hold a secret, so it shows its name only.
    FurtherRow = Data.define(:index, :name, :was, :value, :sealed, :seal, :removed) do
      include Undumpable

      def new? = was.nil?

      def secret? = sealed || seal

      def inspect = "#<#{self.class.name} #{index} #{Wsjrdp::Credentials.shown_name(name)}>"
      alias_method :to_s, :inspect

      def as_json(*) = {"index" => index, "name" => Wsjrdp::Credentials.shown_name(name)}
    end

    UTC = "utc"
    APP_ZONE = "app"
    ZONES = [UTC, APP_ZONE].freeze
    INSTANTS = %w[valid_from expires_at].freeze

    attr_reader :kind, :name, :comment, :public_texts, :instant_texts, :instant_zones, :errors,
      :further_rows, :further_problems

    # An empty form; public_values and further_values fill the public
    # fields, e.g. from the version in use.
    def self.blank(kind, public_values: {}, further_values: {}, name: "")
      texts = kind.public_field_names.to_h { |name| [name, text_of(public_values[name])] }
      rows = further_values.sort.each_with_index.map do |(field, value), index|
        FurtherRow.new(index: index.to_s, name: field, was: nil, value: text_of(value).to_s, sealed: false, seal: false,
          removed: false)
      end
      new(kind: kind, name: name, public_texts: with_defaults(kind, texts.compact, kind.public_field_names),
        further_rows: rows)
    end

    # An enum or boolean field without a value shows its default; the base
    # of a change shows it too, so a form left alone does not write it.
    def self.with_defaults(kind, texts, names)
      kind.fields.each_with_object(texts.dup) do |field, filled|
        next unless names.include?(field.name) && %w[enum boolean].include?(field.type) && !field.default.nil?

        filled[field.name] ||= text_of(field.default)
      end
    end

    # The form to edit a version. An encrypted public field is not shown.
    # secret_values: the decrypted values to fill the secret fields;
    # nil leaves them empty.
    def self.of(record, kind:, secret_values: nil)
      plain = record.plain_values
      names = kind ? kind.public_field_names.reject { |name| record.sealed?(name) } : []
      texts = names.to_h { |name| [name, text_of(plain[name])] }.compact
      texts = with_defaults(kind, texts, names) if kind
      secret_texts = (kind && secret_values) ? kind.secret_field_names.to_h { |name| [name, text_of(secret_values[name]).to_s] } : {}
      rows = further_rows_of(record, kind, secret_values)
      new(kind: kind, name: record.name.to_s, comment: record.comment.to_s, public_texts: texts, secret_texts: secret_texts,
        instant_texts: INSTANTS.to_h { |attribute| [attribute, instant_text(record.public_send(attribute))] },
        further_rows: rows, further_secrets: rows.select(&:sealed).to_h { |row| [row.index, row.value] })
    end

    # The further fields of a version, by name; an encrypted one gets its
    # value only from secret_values.
    def self.further_rows_of(record, kind, secret_values)
      return [] unless kind

      names = (record.plain_values.keys | record.sealed_texts.keys).select { |name| kind.further_name_problem(name).nil? }
      names.sort.each_with_index.map do |name, index|
        sealed = record.sealed?(name)
        value = sealed ? secret_values&.dig(name) : record.plain_values[name]
        FurtherRow.new(index: index.to_s, name: name, was: name, value: text_of(value).to_s, sealed: sealed, seal: false,
          removed: false)
      end
    end

    # params: the sent form; base: the form as it was shown. What the
    # request leaves out keeps the text of base.
    def self.submitted(kind:, params:, base:)
      params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      params = params.stringify_keys
      fields = hash_of(params["fields"])
      secrets = hash_of(params["secret"])
      instants = INSTANTS.to_h { |attribute| [attribute, string(params[attribute])] }
      rows, further_secrets = submitted_further(kind, params, base)
      new(kind: kind, further_rows: rows, further_secrets: further_secrets, name: string(params["name"]) || base.name, comment: string(params["comment"]) || base.comment,
        public_texts: kind ? kind.public_field_names.to_h { |name| [name, string(fields[name]) || base.public_text(name)] } : {},
        secret_texts: kind ? kind.secret_field_names.to_h { |name| [name, string(secrets[name]) || base.secret_text(name)] } : {},
        instant_texts: instants.to_h { |attribute, text| [attribute, text || base.instant_texts[attribute]] },
        instant_zones: instants.to_h { |attribute, text| [attribute, zone_of(text && params["#{attribute}_zone"])] },
        base: base)
    end

    # The rows as sent, then the base's rows the request leaves out; and the
    # secret texts by row index.
    def self.submitted_further(kind, params, base)
      return [[], {}] unless kind

      secrets = hash_of(params["further_secret"])
      sent = hash_of(params["further"]).select { |index, _row| /\A\d{1,4}\z/.match?(index) }
      sent = sent.sort_by { |index, _row| index.to_i }
      texts = {}
      rows = sent.filter_map do |index, raw|
        raw = hash_of(raw)
        secret = string(secrets[index])
        base_row = base.further_row(string(raw["was"]))
        row = base_row ? sent_existing(base_row, raw, index) : sent_new(raw, index, secret || "")
        # An encrypted row the request leaves out keeps the text it showed.
        texts[index] = secret || (row.new? ? "" : row.value) if row&.secret?
        row
      end
      shown = rows.filter_map(&:was)
      last = rows.map { |row| row.index.to_i }.max || -1
      left_out = base.further_rows.reject { |row| shown.include?(row.was) }.each_with_index.map do |row, offset|
        row.with(index: (last + 1 + offset).to_s)
      end
      left_out.each { |row| texts[row.index] = row.value if row.sealed }
      [rows + left_out, texts]
    end

    def self.sent_existing(base_row, raw, index)
      value = base_row.sealed ? base_row.value : string(raw["value"]) || base_row.value
      base_row.with(index: index, value: value, removed: raw["remove"] == "1")
    end

    # nil for a row left empty.
    def self.sent_new(raw, index, secret)
      name = string(raw["name"])&.strip || ""
      seal = raw["seal"] == "1"
      value = seal ? "" : string(raw["value"]) || ""
      return nil if name.empty? && value.empty? && secret.empty?

      FurtherRow.new(index: index, name: name, was: nil, value: value, sealed: false, seal: seal, removed: false)
    end

    def self.zone_of(value) = ZONES.include?(value) ? value : UTC

    def self.text_of(value) = value&.to_s

    # As the date picker shows it: seconds only when there are some.
    def self.instant_text(time)
      return "" unless time

      time = time.getutc
      time.strftime((time.sec.zero? && time.subsec.zero?) ? "%Y-%m-%dT%H:%M" : "%Y-%m-%dT%H:%M:%S")
    end

    def self.string(value) = value.is_a?(String) ? value : nil

    def self.hash_of(value)
      value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
      value.is_a?(Hash) ? value.stringify_keys : {}
    end

    private_class_method :string, :hash_of, :zone_of, :with_defaults, :further_rows_of, :submitted_further,
      :sent_existing, :sent_new

    def initialize(kind:, name: "", comment: "", public_texts: {}, secret_texts: {}, instant_texts: {},
      instant_zones: {}, further_rows: [], further_secrets: {}, base: nil)
      @kind = kind
      @name = name
      @comment = comment
      @public_texts = public_texts.freeze
      @secret_texts = secret_texts.freeze
      @instant_texts = INSTANTS.to_h { |attribute| [attribute, instant_texts[attribute].to_s] }.freeze
      @instant_zones = INSTANTS.to_h { |attribute| [attribute, instant_zones[attribute] || UTC] }.freeze
      @base = base
      @errors = []
      @instants = INSTANTS.to_h { |attribute| [attribute, read_instant(attribute)] }
      @errors.freeze
      @further_rows = further_rows.freeze
      @further_secrets = further_secrets.transform_values { |text| text.dup.freeze }.freeze
      @further_problems = check_further_rows.freeze
      freeze
    end

    def public_text(name) = public_texts[name].to_s

    # The text of a secret field: the current value in the edit form, or
    # what was sent.
    def secret_text(name) = @secret_texts[name].to_s

    # The row of a further field that exists, by its name.
    def further_row(name) = name && further_rows.find { |row| row.was == name }

    # The codes of a row's problems.
    def further_problems_of(row) = further_problems.select { |problem| problem.field == row.index }.map(&:code)

    # The text of a secret row, as secret_text.
    def further_secret_text(row) = @further_secrets[row.index].to_s

    # The further fields to encrypt: new rows marked as encrypted.
    def secret_further_fields = valid_further_rows.select(&:seal).map(&:name)

    # Every field as typed, for Deposit (which checks them).
    def all_values
      values = public_texts.merge(@secret_texts)
      return {} unless kind

      fields = kind.field_names.to_h { |name| [name, values[name].to_s] }
      valid_further_rows.each { |row| fields[row.name] = further_text(row) }
      fields
    end

    # The dates as Times; nil if not given or invalid.
    def instants = INSTANTS.to_h { |attribute| [attribute.to_sym, @instants[attribute]] }

    # For Change: the fields that differ from the form shown; an emptied
    # secret field as nil. secrets: false leaves the secret fields out.
    def changed_values(secrets: true)
      values = public_texts.reject { |name, text| @base && text == @base.public_text(name) }
      return values unless secrets

      @secret_texts.each do |name, text|
        next if text == (@base ? @base.secret_text(name) : "")

        values[name] = text.empty? ? nil : text
      end
      values.merge(changed_further_values(secrets))
    end

    # For Change: name, comment, and the dates that differ from the form
    # shown.
    def changed_attributes
      attributes = {name: name, comment: comment}
      INSTANTS.each do |attribute|
        next if @base && instant_texts[attribute] == @base.instant_texts[attribute] && instant_zones[attribute] == UTC

        attributes[attribute.to_sym] = @instants[attribute]
      end
      attributes
    end

    def inspect = "#<#{self.class.name} #{kind&.name} errors=#{errors.join(", ")}>"
    alias_method :to_s, :inspect

    def as_json(*) = {"kind" => kind&.name, "errors" => errors.map(&:as_json)}

    private

    # The rows without a problem.
    def valid_further_rows
      further_rows.reject { |row| further_problems.any? { |problem| problem.field == row.index } }
    end

    def further_text(row) = row.secret? ? further_secret_text(row) : row.value

    # {name => text, or nil to remove} of the rows touched: new, removed,
    # or changed (emptied removes). secrets: false leaves out every secret
    # row.
    def changed_further_values(secrets)
      valid_further_rows.each_with_object({}) do |row, values|
        next if row.secret? && !secrets

        base = @base&.further_row(row.was)
        if row.new? then values[row.name] = further_text(row)
        elsif row.removed then values[row.name] = nil
        elsif base.nil? || further_text(row) != base.value then values[row.name] = further_text(row).presence
        end
      end
    end

    # The problems of the new rows, by row index: a missing, invalid,
    # reserved or duplicate name, or no value.
    def check_further_rows
      return [] unless kind

      taken = further_rows.reject(&:new?).map(&:was)
      further_rows.select(&:new?).filter_map do |row|
        code = if row.name.empty? then :name_missing
        elsif (problem = kind.further_name_problem(row.name)) then problem
        elsif taken.include?(row.name) then :duplicate
        elsif further_text(row).empty? then :value_missing
        end
        taken << row.name
        code && Kind::Problem.new(row.index, code)
      end
    end

    def read_instant(attribute)
      zone = (instant_zones[attribute] == APP_ZONE) ? Time.zone : nil
      Wsjrdp::InstantInput.parse(instant_texts[attribute], zone: zone)
    rescue Wsjrdp::InstantInput::Invalid
      @errors << Kind::Problem.new(attribute, :not_an_instant)
      nil
    end
  end
end
