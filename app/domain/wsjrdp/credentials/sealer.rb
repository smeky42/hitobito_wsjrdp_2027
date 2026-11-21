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
  # Seals the fields of one version of one account and opens them again
  # (doc/wsjrdp/credentials.md, "Sealing"). The whole cryptography is two
  # calls into Rails:
  #
  #   encryptor = ActiveSupport::MessageEncryptor.new(key_bytes, cipher: "aes-256-gcm", serializer: JSON)
  #   text   = encryptor.encrypt_and_sign(fields, purpose: "credential/<stage>/<kind>/<account_key>")
  #   fields = encryptor.decrypt_and_verify(text, purpose: "credential/<stage>/<kind>/<account_key>")
  #
  # The purpose lies inside the sealed text and is authenticated with it, so
  # a text opens only for the stage, kind and account it was sealed for. The
  # stored form is named SCHEME; the golden-vector spec
  # (spec/domain/wsjrdp/credentials/golden_vector_spec.rb) holds texts that
  # must keep opening.
  #
  #   text   = Wsjrdp::Credentials::Sealer.seal(fields, key: keys.active!, stage:, kind:, account_key:)
  #   fields = Wsjrdp::Credentials::Sealer.unseal(text, key:, stage:, kind:, account_key:)
  #
  # Opening (.unseal; not "open", which a slip would turn into Kernel#open)
  # never raises for the text: a wrong key, a changed text, another purpose
  # or something that is no sealed text at all is nil -- "cannot be opened
  # here". Neither the text nor the fields ever reach a message.
  #
  # Both directions take the same shape of fields (.fields_problem): a plain
  # Hash of String names, json_class excepted, to String, Integer, true,
  # false or nil. .seal refuses anything else; .unseal answers nil for a
  # text that opens to anything else (sealed by other code with the same
  # key), so a wrongly shaped result never reaches a consumer. What .unseal
  # cannot stop is JSON.load building an object while it parses -- that
  # needs the key, and is why seal refuses the name json_class.
  #
  # A caller hands .seal the values of Wsjrdp::Credentials::Kind#cast, never
  # request parameters: a Hash subclass such as
  # ActiveSupport::HashWithIndifferentAccess is refused.
  #
  # Which of Rails' two envelope spellings a new text gets depends on
  # ActiveSupport::Messages::Metadata.use_message_serializer_for_metadata
  # (on in the app through load_defaults 7.1); both are read either way.
  class Sealer
    SCHEME = "rails-me-v1"
    CIPHER = "aes-256-gcm"
    # serializer: JSON makes Rails read a text with JSON.load, which (json
    # 2.x, create_additions) takes a hash with this key for an object to
    # build: the stored value names a class that is looked up. With most
    # values such a text no longer opens, with a few it still does; either
    # way a stored value would steer the reader, so no field may have it.
    JSON_CREATE_ID = JSON.create_id.dup.freeze

    # A purpose part outside its grammar, a key that is none, fields that are
    # not a plain flat hash of string names and JSON scalars.
    class Refused < Error; end

    class << self
      def purpose(stage:, kind:, account_key:)
        raise Refused, "the stage is not of a-z and 0-9" unless Wsjrdp::Credentials.stage?(stage)
        unless Wsjrdp::Credentials.name?(kind)
          raise Refused, "the kind is not lower-case snake of at most #{NAME_LENGTH} characters"
        end
        unless Wsjrdp::Credentials.name?(account_key)
          raise Refused, "the account key is not lower-case snake of at most #{NAME_LENGTH} characters"
        end

        "credential/#{stage}/#{kind}/#{account_key}"
      end

      # The sealed text of fields (a hash of string names to strings,
      # integers, true, false or nil), sealed with key (a
      # Wsjrdp::Credentials::Keys::Key) for one account.
      def seal(fields, key:, stage:, kind:, account_key:)
        purpose = purpose(stage: stage, kind: kind, account_key: account_key)
        check_fields!(fields)
        encryptor(key).encrypt_and_sign(fields, purpose: purpose)
      end

      # The fields of text, or nil when it cannot be opened here with key
      # (nil too when there is no key), or when it opens to anything .seal
      # would have refused.
      def unseal(text, key:, stage:, kind:, account_key:)
        purpose = purpose(stage: stage, kind: kind, account_key: account_key)
        return nil if key.nil? || !text.is_a?(String)

        fields = encryptor(key).decrypt_and_verify(text, purpose: purpose)
        fields_problem(fields) ? nil : fields
      rescue ActiveSupport::MessageEncryptor::InvalidMessage
        nil
      end

      # Why fields are not what a sealed text may hold; nil when they are.
      # The one rule of .seal and .unseal. Names a field only by
      # Wsjrdp::Credentials.shown_name, never a value.
      def fields_problem(fields)
        return "the fields are not a plain Hash" unless fields.instance_of?(Hash)
        return "a field name is not a string" unless fields.keys.all? { |name| Wsjrdp::Credentials.text?(name) }

        fields.each do |name, value|
          shown = Wsjrdp::Credentials.shown_name(name)
          return "field #{shown}: the name is reserved (#{JSON_CREATE_ID})" if name == JSON_CREATE_ID
          return "field #{shown}: not a string, integer, boolean or nil" unless scalar?(value)
          return "field #{shown}: not valid text" if value.is_a?(String) && !value.valid_encoding?
        end
        nil
      end

      private

      def encryptor(key)
        raise NoKeyError, "no key to seal with" if key.nil?
        raise Refused, "the key is not a #{Keys::Key.name}" unless key.is_a?(Keys::Key)
        raise Refused, "the key is not #{Keys::KEY_BYTES} bytes" unless key.bytes.bytesize == Keys::KEY_BYTES

        ActiveSupport::MessageEncryptor.new(key.bytes, cipher: CIPHER, serializer: JSON)
      end

      def check_fields!(fields)
        problem = fields_problem(fields)
        raise Refused, problem if problem
      end

      def scalar?(value)
        value.nil? || value == true || value == false || value.is_a?(String) || value.is_a?(Integer)
      end
    end
  end
end
