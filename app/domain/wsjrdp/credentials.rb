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
# app/domain/wsjrdp/credentials/.
#
#   moss = Wsjrdp::Credentials.fetch(:moss_api, "default")
#   moss[:client_id]
#   moss.secret(:client_secret)
module Wsjrdp::Credentials
  PRODUCTION = "production"
  STAGE_FORMAT = /\A[a-z0-9]+\z/
  # A kind or a field name. No double underscore, so that each maps to
  # exactly one part of a variable name.
  NAME_FORMAT = /\A[a-z][a-z0-9]*(?:_[a-z0-9]+)*\z/
  NAME_LENGTH = 48

  # An account key (doc/wsjrdp/credentials.md, "Names"): lower-case or
  # caseless letters of any script and the digits 0-9, joined by single
  # characters of _ @ , . + - (none at the start or the end, never two in a
  # row), at most 64 characters, in Unicode NFC. foo@worldscoutjamboree.de
  # is one, so is every name.
  ACCOUNT_KEY_LENGTH = 64
  # The Hangul fillers are letters (Lo) that show as nothing.
  ACCOUNT_KEY_LETTER = /[\p{Ll}\p{Lo}&&[^\u115F\u1160\u3164\uFFA0]]/
  ACCOUNT_KEY_RULE = "lower-case letters and digits, joined by single characters of _ @ , . + -, " \
    "at most #{ACCOUNT_KEY_LENGTH} characters"
  ACCOUNT_KEY_FORMAT = /\A(?:#{ACCOUNT_KEY_LETTER}|[0-9])+(?:[_@,.+-](?:#{ACCOUNT_KEY_LETTER}|[0-9])+)*\z/

  # The category of the store's entries in the Hitobito log; the wagon
  # registers it.
  LOG_CATEGORY = "credentials"

  # The root of every error of the store. No message names a value.
  class Error < StandardError; end

  # The keys, the variables or the local file are not understood. Stops
  # every stage but production at boot.
  class ConfigurationError < Error; end

  # Sealing was asked for, but the instance has no key.
  class NoKeyError < Error; end

  # No version of an account is usable here (.fetch).
  class NoCredentialError < Error; end

  # A message repeats a name only when it is valid, and a stage only when
  # it is short (64 hex digits are a valid stage). Anything else may be a
  # secret typed in the wrong place, so a message shows a placeholder.
  SHOWN_STAGE_LENGTH = 32
  NOT_A_NAME = "(not a name)"
  NOT_A_STAGE = "(not a stage)"

  def self.stage?(value) = text?(value) && STAGE_FORMAT.match?(value)

  def self.name?(value) = text?(value) && value.length <= NAME_LENGTH && NAME_FORMAT.match?(value)

  # Only the normalized form is a key (.account_key_of).
  def self.account_key?(value)
    text?(value) && value.length <= ACCOUNT_KEY_LENGTH && ACCOUNT_KEY_FORMAT.match?(value) &&
      value.unicode_normalized?(:nfc)
  end

  # A key as it is stored and looked up: lower case (Unicode's full case
  # mapping) in NFC. Anything that is no text is handed back as given, for
  # the checks to judge.
  def self.account_key_of(value)
    text = name_of(value)
    return text unless text?(text)

    text.encode(Encoding::UTF_8).unicode_normalize(:nfc).downcase.unicode_normalize(:nfc)
  end

  # The newest usable version of an account here, or NoCredentialError.
  def self.fetch(kind, account_key) = lookup.fetch(kind, account_key)

  # The usable versions, newest first: what .fetch gives, then fallbacks.
  def self.candidates(kind, account_key) = lookup.candidates(kind, account_key)

  # The variables, the local file (both read at boot), then the database.
  def self.lookup = Lookup.new([*Overrides.current.sources, DatabaseSource.new])

  # A value the initializer captured behind a lambda, or a plain value a
  # spec sets.
  def self.captured(value) = value.respond_to?(:call) ? value.call : value

  # Valid text: valid UTF-8 without a NUL (a String of another encoding only
  # when it is plain ASCII). Anything else would make a comparison raise,
  # be transcoded silently, or reach PostgreSQL, whose error quotes it.
  def self.text?(value)
    value.is_a?(String) && (value.encoding == Encoding::UTF_8 || value.ascii_only?) && value.valid_encoding? &&
      !value.include?("\u0000")
  end

  # A Symbol as its String; anything else as given, for the checks to judge.
  def self.name_of(value) = value.is_a?(Symbol) ? value.to_s : value

  def self.shown_name(value, placeholder: NOT_A_NAME)
    text = name_of(value)
    name?(text) ? text : placeholder
  end

  # An account key is repeated only when it is one, as a name is.
  def self.shown_account_key(value, placeholder: NOT_A_NAME)
    text = name_of(value)
    account_key?(text) ? text : placeholder
  end

  def self.shown_stage(value, placeholder: NOT_A_STAGE)
    (stage?(value) && value.length <= SHOWN_STAGE_LENGTH) ? value : placeholder
  end

  # For an object that holds a key or a value: Marshal and YAML would dump
  # every instance variable, so they refuse. The class defines inspect and
  # as_json itself.
  module Undumpable
    def marshal_dump = raise(TypeError, "#{self.class.name} cannot be dumped")

    def _dump(_level) = raise(TypeError, "#{self.class.name} cannot be dumped")

    def encode_with(_coder) = raise(TypeError, "#{self.class.name} cannot be dumped")

    def to_json(*args) = as_json.to_json(*args)

    def pretty_print(printer) = printer.text(inspect)
  end
end
