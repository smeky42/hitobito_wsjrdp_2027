# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Sync
  # How many rows of content tables a step wrote: inserted, updated, deleted
  # and soft_deleted (marked as gone, e.g. moss_removed_at). Kept in the
  # stats of a part and of a run under "modified_rows", so that further
  # figures can join it later.
  class Stats
    KEY = "modified_rows"
    KEYS = %w[inserted updated deleted soft_deleted].freeze

    # The modified rows of a stats column.
    def self.of(stats) = new(stats.to_h[KEY])

    def self.sum(all) = all.each_with_object(new) { |stats, sum| sum.merge!(stats) }

    def initialize(counts = {})
      @counts = KEYS.to_h { |key| [key, counts.to_h[key].to_i] }
    end

    def [](key) = @counts.fetch(key)

    def total = @counts.values.sum

    def any? = total.positive?

    def add(key, count)
      @counts.fetch(key)
      @counts[key] += count
      self
    end

    def merge!(other)
      other.to_h.each { |key, count| add(key, count) }
      self
    end

    def to_h = @counts.dup

    # The stats column: {"modified_rows" => {...}}.
    def to_stats = {KEY => to_h}
  end
end
