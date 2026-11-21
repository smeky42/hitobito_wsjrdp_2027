# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "json"
require "active_support"
require "active_support/message_encryptor"

module Wsjrdp::Credentials
  # Seals the value of one secret field of one version and opens it again
  # (doc/wsjrdp/credentials.md, "Sealing"): two calls into Rails'
  # ActiveSupport::MessageEncryptor (AES-256-GCM, JSON), with the purpose
  # credential/<stage>/<kind>/<account_key>/<field>, so a text opens only
  # for the field it was sealed for.
  #
  #   text  = Wsjrdp::Credentials::Sealer.seal(value, key: keys.active!, stage:, kind:, account_key:, field:)
  #   value = Wsjrdp::Credentials::Sealer.unseal(text, key:, stage:, kind:, account_key:, field:)
  #
  # A value is a String of valid text, an Integer, true or false. .unseal
  # never raises for the text: whatever does not open is nil, and nil is
  # never a value. The golden-vector spec holds texts that must keep
  # opening; never repair it by making new texts.
  class Sealer
    # The stored form.
    SCHEME = "rails-me-v1"
    CIPHER = "aes-256-gcm"
    # The content is always {"value" => value}: it does not depend on how
    # Rails serialises a bare scalar, and never holds json_class.
    CONTENT_NAME = "value"

    class Refused < Error; end

    class << self
      def purpose(stage:, kind:, account_key:, field:)
        raise Refused, "the stage is not of a-z and 0-9" unless Wsjrdp::Credentials.stage?(stage)
        {"kind" => kind, "field" => field}.each do |what, part|
          next if Wsjrdp::Credentials.name?(part)

          raise Refused, "the #{what} is not lower-case snake of at most #{NAME_LENGTH} characters"
        end
        # No "/" in any part, so the purpose reads one way only.
        raise Refused, "the account key is not of #{ACCOUNT_KEY_RULE}" unless Wsjrdp::Credentials.account_key?(account_key)

        "credential/#{stage}/#{kind}/#{account_key}/#{field}"
      end

      def seal(value, key:, stage:, kind:, account_key:, field:)
        purpose = purpose(stage: stage, kind: kind, account_key: account_key, field: field)
        problem = value_problem(value)
        raise Refused, "field #{field}: #{problem}" if problem

        encryptor(key).encrypt_and_sign({CONTENT_NAME => value}, purpose: purpose)
      end

      # Named unseal, not open: a slip would call Kernel#open.
      def unseal(text, key:, stage:, kind:, account_key:, field:)
        purpose = purpose(stage: stage, kind: kind, account_key: account_key, field: field)
        return nil if key.nil? || !text.is_a?(String)

        content = encryptor(key).decrypt_and_verify(text, purpose: purpose)
        content_value(content)
      rescue ActiveSupport::MessageEncryptor::InvalidMessage
        nil
      end

      # nil when the value can be sealed.
      def value_problem(value)
        return "not a string, integer or boolean" unless scalar?(value)

        "not valid text" if value.is_a?(String) && !Wsjrdp::Credentials.text?(value)
      end

      private

      def encryptor(key)
        raise NoKeyError, "no key to seal with" if key.nil?
        raise Refused, "the key is not a #{Keys::Key.name}" unless key.is_a?(Keys::Key)
        raise Refused, "the key is not #{Keys::KEY_BYTES} bytes" unless key.bytes.bytesize == Keys::KEY_BYTES

        ActiveSupport::MessageEncryptor.new(key.bytes, cipher: CIPHER, serializer: JSON)
      end

      def content_value(content)
        return nil unless content.instance_of?(Hash) && content.keys == [CONTENT_NAME]

        value = content[CONTENT_NAME]
        value_problem(value) ? nil : value
      end

      def scalar?(value)
        value == true || value == false || value.is_a?(String) || value.is_a?(Integer)
      end
    end
  end
end
