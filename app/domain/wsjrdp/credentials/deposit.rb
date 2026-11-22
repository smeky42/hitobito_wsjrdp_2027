# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Credentials
  # Makes a new version for this instance's own stage
  # (doc/wsjrdp/credentials.md, "The write paths"); gives a WriteResult.
  #
  #   Wsjrdp::Credentials::Deposit.call(kind: "moss_api", account_key: "default",
  #     values: {"client_id" => "...", "client_secret" => "..."}, name: "key of May",
  #     valid_from: Time.utc(2027, 5, 1), expires_at: Time.utc(2027, 11, 1), author: current_person)
  #
  # Each secret field is sealed by itself with the active key; the row names
  # that key even without a secret field, so depositing always needs a key
  # (NoKeyError). A further field (one the kind does not have) is sealed
  # when secret_further_fields names it, else kept plain.
  class Deposit
    def self.call(**) = new(**).call

    def initialize(kind:, account_key:, values:, name: nil, comment: nil, valid_from: nil, expires_at: nil,
      author: nil, secret_further_fields: [], keys: Keys.current, kinds: Kinds.current)
      raise ArgumentError, "the values are not a hash" unless values.nil? || values.is_a?(Hash)

      WsjrdpCredential.check_instants!(valid_from: valid_from, expires_at: expires_at)
      @kind_name = Wsjrdp::Credentials.name_of(kind)
      @account_key = Wsjrdp::Credentials.account_key_of(account_key)
      @values = values
      @secret_further_fields = Array(secret_further_fields).map { |field| Wsjrdp::Credentials.name_of(field) }
      # Not name.presence: blank? raises for a text of invalid encoding,
      # which the model refuses with a code instead.
      @attributes = {name: (name == "") ? nil : name, comment: comment, valid_from: valid_from,
                     expires_at: expires_at, author: author}
      @keys = keys
      @kinds = kinds
    end

    def call
      key = @keys.active!
      kind = @kinds[@kind_name]
      cast = kind&.cast(@values, stage: @keys.stage)
      record = build(kind, cast, key)
      record.valid?
      errors = WriteResult.problems_of(record)
      field_errors = cast ? cast.errors : []
      warnings = cast ? cast.warnings : []
      return WriteResult.new(field_errors: field_errors, errors: errors, warnings: warnings) if (errors + field_errors).any?

      record.save!
      WriteResult.new(record: record, warnings: warnings)
    end

    private

    def build(kind, cast, key)
      record = WsjrdpCredential.new(kind: @kind_name.to_s, account_key: @account_key.to_s, stage: @keys.stage,
        scheme: Sealer::SCHEME, encryption_key_fingerprint: key.fingerprint, encryption_key_label: @keys.label,
        **@attributes)
      record.kinds_registry = @kinds
      return record unless cast&.valid? && Wsjrdp::Credentials.account_key?(@account_key)

      cast.values.each do |name, value|
        secret = kind.field(name)&.secret? || (!kind.field?(name) && @secret_further_fields.include?(name))
        record.write_field(name, value, secret: secret, key: key)
      end
      record
    end
  end
end
