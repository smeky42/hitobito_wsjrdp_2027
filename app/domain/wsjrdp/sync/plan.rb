# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Sync
  # What a part would change, and what to look at first. The digest covers
  # both: writing plans again and goes ahead only when it is the same.
  class Plan
    ACTIONS = %w[create update restore remove].freeze
    # The levels of a notice, most urgent first: a warning needs a second
    # confirmation; an important hint and a hint do not.
    WARNING = "warning"
    IMPORTANT = "important"
    HINT = "hint"
    LEVELS = [WARNING, IMPORTANT, HINT].freeze

    # values: create -> {column => new}; update and restore -> {column =>
    # [old, new]}; remove -> {}. All plain JSON.
    # target: the model written ("MossUser", "Person"); target_column: the
    # jsonb column when values are keys inside it ("additional_info"), else
    # nil. ref: the key of the record this change belongs to in the same
    # part (a person's Moss fields -> the Moss user), nil for most.
    Change = Data.define(:action, :key, :label, :values, :target, :target_column, :ref) do
      def initialize(action:, key:, label:, values:, target: nil, target_column: nil, ref: nil) = super

      # Without the members that are not set, so older plans keep their digest.
      def to_h = super.compact
    end
    # items: {record key => text}, the records the notice is about.
    Warning = Data.define(:level, :code, :message, :items) do
      def keys = items.keys
    end

    attr_reader :changes, :warnings

    def initialize(changes: [], warnings: [])
      @changes = changes.sort_by { |change| [ACTIONS.index(change.action), change.key.to_s] }
      @warnings = warnings.sort_by.with_index { |notice, index| [LEVELS.index(notice.level) || LEVELS.size, index] }
    end

    def self.from_h(hash)
      hash = hash.to_h.stringify_keys
      new(changes: Array(hash["changes"]).map { |change| Change.new(**change.symbolize_keys.slice(*Change.members)) },
        warnings: Array(hash["warnings"]).map { |warning| warning_of(warning.stringify_keys) })
    end

    # A notice stored without items has its keys only; each key is its own text.
    def self.warning_of(hash)
      Warning.new(level: hash["level"], code: hash["code"], message: hash["message"],
        items: hash["items"] || Array(hash["keys"]).to_h { |key| [key, key] })
    end

    def warnings? = warnings.any? { |warning| warning.level == WARNING }

    def counts = changes.map(&:action).tally

    def to_h = {"changes" => changes.map(&:to_h), "warnings" => warnings.map(&:to_h)}.as_json

    # {change key => [notices about it]}, keys compared without case.
    def notices_by_key
      @notices_by_key ||= warnings.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |notice, by_key|
        notice.keys.each { |key| by_key[key.to_s.downcase] << notice }
      end
    end

    def digest = Digest::SHA256.hexdigest(JSON.generate(to_h))
  end
end
