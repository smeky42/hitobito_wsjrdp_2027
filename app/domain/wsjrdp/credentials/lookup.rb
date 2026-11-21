# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Credentials
  # Asks its sources in order (doc/wsjrdp/credentials.md, "The lookup").
  # The first source that names an account answers for it as a whole, even
  # without a usable version; the others are not asked. A source is any
  # object with
  #
  #   answer(kind, account_key) # => an Answer, or nil when it does not name the account
  #
  # Nothing is remembered between calls.
  class Lookup
    # The state of a usable version, in every source.
    USABLE = :active

    # candidates: the usable Credentials, newest first; states: state =>
    # count of the versions found.
    Answer = Data.define(:source, :stage, :candidates, :states) do
      def initialize(source:, stage:, candidates:, states:)
        super(source: source, stage: stage, candidates: candidates.dup.freeze, states: states.dup.freeze)
      end

      # From examinations in the order of the choice, each with #state and
      # #credential: those in the usable state are the candidates.
      def self.of(source:, stage:, examinations:)
        new(source: source, stage: stage, states: examinations.map(&:state).tally,
          candidates: examinations.select { |examination| examination.state == USABLE }.map(&:credential))
      end

      def found = states.values.sum
    end

    attr_reader :sources

    def initialize(sources)
      @sources = sources.dup.freeze
      freeze
    end

    def candidates(kind, account_key) = answer(kind, account_key).candidates

    def fetch(kind, account_key)
      found = answer(kind, account_key)
      found.candidates.first || raise(NoCredentialError, failure_message(kind, account_key, found))
    end

    def answer(kind, account_key)
      kind = name!(kind, "kind")
      account_key = account_key!(account_key)
      sources.each do |source|
        found = source.answer(kind, account_key)
        return found if found
      end
      Answer.new(source: nil, stage: nil, candidates: [], states: {})
    end

    def inspect = "#<#{self.class.name} sources=#{sources.map { |source| source.class.name }.join(",")}>"
    alias_method :to_s, :inspect

    private

    # Anything but a name is a programming error.
    def name!(value, what)
      text = Wsjrdp::Credentials.name_of(value)
      return text if Wsjrdp::Credentials.name?(text)

      raise ArgumentError, "the #{what} is not lower-case snake of at most #{NAME_LENGTH} characters"
    end

    # Folded to lower case and NFC first, as it is stored.
    def account_key!(value)
      key = Wsjrdp::Credentials.account_key_of(value)
      return key if Wsjrdp::Credentials.account_key?(key)

      raise ArgumentError, "the account key is not of #{ACCOUNT_KEY_RULE}"
    end

    def failure_message(kind, account_key, found)
      where = found.stage ? " in stage #{Wsjrdp::Credentials.shown_stage(found.stage)}" : ""
      "#{kind}/#{account_key}: no usable version#{where} (#{failure_reason(found)})"
    end

    def failure_reason(found)
      return "no source names the account" if found.source.nil?
      return "#{found.source}: no version" if found.found.zero?

      states = found.states.sort_by { |state, _count| state.to_s }.map { |state, count| "#{state} #{count}" }
      "#{found.source}: #{found.found} #{(found.found == 1) ? "version" : "versions"}, none usable: #{states.join(", ")}"
    end
  end
end
