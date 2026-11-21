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
  class VersionForm
    include Undumpable

    UTC = "utc"
    APP_ZONE = "app"
    ZONES = [UTC, APP_ZONE].freeze
    INSTANTS = %w[valid_from expires_at].freeze

    attr_reader :kind, :name, :comment, :public_texts, :instant_texts, :instant_zones, :errors

    # An empty form; public_values fill the public fields, e.g. from the
    # version in use.
    def self.blank(kind, public_values: {}, name: "")
      texts = kind.public_field_names.to_h { |name| [name, text_of(public_values[name])] }
      new(kind: kind, name: name, public_texts: with_defaults(kind, texts.compact, kind.public_field_names))
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
      new(kind: kind, name: record.name.to_s, comment: record.comment.to_s, public_texts: texts, secret_texts: secret_texts,
        instant_texts: INSTANTS.to_h { |attribute| [attribute, instant_text(record.public_send(attribute))] })
    end

    # params: the sent form; base: the form as it was shown. What the
    # request leaves out keeps the text of base.
    def self.submitted(kind:, params:, base:)
      params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      params = params.stringify_keys
      fields = hash_of(params["fields"])
      secrets = hash_of(params["secret"])
      instants = INSTANTS.to_h { |attribute| [attribute, string(params[attribute])] }
      new(kind: kind, name: string(params["name"]) || base.name, comment: string(params["comment"]) || base.comment,
        public_texts: kind ? kind.public_field_names.to_h { |name| [name, string(fields[name]) || base.public_text(name)] } : {},
        secret_texts: kind ? kind.secret_field_names.to_h { |name| [name, string(secrets[name]) || base.secret_text(name)] } : {},
        instant_texts: instants.to_h { |attribute, text| [attribute, text || base.instant_texts[attribute]] },
        instant_zones: instants.to_h { |attribute, text| [attribute, zone_of(text && params["#{attribute}_zone"])] },
        base: base)
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

    private_class_method :string, :hash_of, :zone_of, :with_defaults

    def initialize(kind:, name: "", comment: "", public_texts: {}, secret_texts: {}, instant_texts: {},
      instant_zones: {}, base: nil)
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
      freeze
    end

    def public_text(name) = public_texts[name].to_s

    # The text of a secret field: the current value in the edit form, or
    # what was sent.
    def secret_text(name) = @secret_texts[name].to_s

    # Every field as typed, for Deposit (which checks them).
    def all_values
      values = public_texts.merge(@secret_texts)
      kind ? kind.field_names.to_h { |name| [name, values[name].to_s] } : {}
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
      values
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

    def read_instant(attribute)
      zone = (instant_zones[attribute] == APP_ZONE) ? Time.zone : nil
      Wsjrdp::InstantInput.parse(instant_texts[attribute], zone: zone)
    rescue Wsjrdp::InstantInput::Invalid
      @errors << Kind::Problem.new(attribute, :not_an_instant)
      nil
    end
  end
end
