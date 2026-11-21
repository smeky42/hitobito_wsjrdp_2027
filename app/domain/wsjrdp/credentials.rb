# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The credential store (doc/wsjrdp/credentials.md): passwords and API keys
# of the services the app talks to, sealed with a key of the instance's
# stage. This file holds the names every part shares; the parts live in
# app/domain/wsjrdp/credentials/:
#
# - Keys: the instance's encryption keys (HITOBITO_CREDENTIAL_KEYS);
# - Sealer: the two calls into ActiveSupport::MessageEncryptor;
# - Kinds: the registry of config/wsjrdp_credential_kinds.yml, and the
#   casting of a set of values for a kind;
# - Credential: the value object a consumer gets.
#
# Nothing reads a credential yet: there is no table and no lookup.
module Wsjrdp::Credentials
  PRODUCTION = "production"
  # A stage: as for the HMAC keys of the service tokens.
  STAGE_FORMAT = /\A[a-z0-9]+\z/
  # A kind, an account key, a field name: lower-case snake without a double
  # underscore, so that each maps to exactly one part of a variable name,
  # and at most NAME_LENGTH characters (.name? is the one definition).
  NAME_FORMAT = /\A[a-z][a-z0-9]*(?:_[a-z0-9]+)*\z/
  NAME_LENGTH = 48

  # The root of every error of the store. No message names a value.
  class Error < StandardError; end

  # Sealing was asked for, but the instance has no key.
  class NoKeyError < Error; end

  # A message repeats a name only when it is valid (.name?, so every legal
  # name can be repeated), and a stage only when it is at most
  # SHOWN_STAGE_LENGTH characters: 64 hex digits are a valid stage. Anything
  # else may be a value put in the wrong place (a secret typed where a stage
  # or a field name belongs), so a message shows a placeholder instead.
  SHOWN_STAGE_LENGTH = 32
  NOT_A_NAME = "(not a name)"
  NOT_A_STAGE = "(not a stage)"

  def self.stage?(value) = text?(value) && STAGE_FORMAT.match?(value)

  # A kind, an account key or a field name: the grammar, at most
  # NAME_LENGTH characters.
  def self.name?(value) = text?(value) && value.length <= NAME_LENGTH && NAME_FORMAT.match?(value)

  # A String of valid encoding; regular expressions raise on any other.
  def self.text?(value) = value.is_a?(String) && value.valid_encoding?

  # value as a message may show it: a valid name, else placeholder.
  def self.shown_name(value, placeholder: NOT_A_NAME)
    text = value.is_a?(Symbol) ? value.to_s : value
    name?(text) ? text : placeholder
  end

  # value as a message may show it: a stage of at most SHOWN_STAGE_LENGTH
  # characters, else placeholder.
  def self.shown_stage(value, placeholder: NOT_A_STAGE)
    (stage?(value) && value.length <= SHOWN_STAGE_LENGTH) ? value : placeholder
  end

  # Refuses what Marshal and YAML would otherwise write out of an object
  # that holds a key or a value: both dump every instance variable. Mixed
  # into Keys::Key and Credential, which define inspect and as_json
  # themselves.
  module Undumpable
    def marshal_dump = raise(TypeError, "#{self.class.name} cannot be dumped")

    def _dump(_level) = raise(TypeError, "#{self.class.name} cannot be dumped")

    def encode_with(_coder) = raise(TypeError, "#{self.class.name} cannot be dumped")

    def to_json(*args) = as_json.to_json(*args)

    def pretty_print(printer) = printer.text(inspect)
  end
end
