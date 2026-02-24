# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  YearMonth = Data.define(:year, :month) do
    include Comparable

    alias_method :to_ary, :deconstruct

    def [](index)
      case index
      when :year, "year", 0, -2
        year
      when :month, "month", 1, -1
        month
      end
    end

    def first = year

    def last = month

    def <=>(other)
      return unless other.is_a?(self.class)
      [year, month] <=> [other.year, other.month]
    end

    def distance_in_months_to(other)
      (other.month - month) + (other.year - year) * 12
    end

    def year_month_i
      year * 100 + month
    end

    def to_time_with_zone(day: 1)
      Time.zone.local(year, month, day)
    end
  end
end
