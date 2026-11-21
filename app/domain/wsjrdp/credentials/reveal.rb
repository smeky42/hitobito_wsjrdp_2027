# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Credentials
  # Shows an admin the value of one hidden field of one version, on the
  # account's page (doc/wsjrdp/credentials.md, "The pages").
  #
  #   reveal = Wsjrdp::Credentials::Reveal.new(report, source: "database", id: 12, field: "client_secret")
  #   reveal.value     # or Reveal::Refused
  #
  # A database version must belong to this stage and be readable here.
  # Only hidden fields are revealed; the page shows all others anyway.
  class Reveal
    include Undumpable

    # Why a value is not shown, as a code.
    class Refused < Error
      attr_reader :code

      def initialize(code)
        @code = code
        super("not revealed: #{code}")
      end
    end

    # The on/off switch of the feature: the pages offer the reveal button
    # and the controller answers only while this is true.
    def self.enabled? = true

    # Whether a field is shown hidden: a secret field, an encrypted field,
    # and any field the kind does not know (it may be a removed secret).
    def self.masked?(name, kind:, record: nil)
      field = kind&.field(name)
      field.nil? || field.secret? || record&.sealed?(name) || false
    end

    attr_reader :version, :field

    def initialize(report, source:, field:, id: nil, position: nil, keys: Keys.current)
      @report = report
      @field = Wsjrdp::Credentials.name?(field) ? field : nil
      @keys = keys
      @version = report.versions.find do |version|
        version.source == source && (version.record ? version.id == id : version.position == position)
      end
      freeze
    end

    def value
      raise Refused.new(:disabled) unless self.class.enabled?
      raise Refused.new(:not_found) unless version && field

      version.record ? database_value : override_value
    end

    def inspect = "#<#{self.class.name} #{version.inspect} field=#{field}>"
    alias_method :to_s, :inspect

    def as_json(*) = {"version" => version&.as_json, "field" => field}

    private

    def kind = Kinds.current[@report.kind]

    def database_value
      row = version.record
      raise Refused.new(:other_stage) unless row.stage == @keys.stage
      raise Refused.new(:not_masked) unless self.class.masked?(field, kind: kind, record: row)

      values = row.field_values(keys: @keys)
      raise Refused.new(:not_opening) unless values
      raise Refused.new(:not_set) unless values.key?(field)

      values[field]
    end

    def override_value
      credential = version.credential
      raise Refused.new(:kind_mismatch) unless credential
      raise Refused.new(:not_masked) unless self.class.masked?(field, kind: credential.kind)
      raise Refused.new(:not_set) unless credential.field_names.include?(field)

      credential.secret(field)
    end
  end
end
