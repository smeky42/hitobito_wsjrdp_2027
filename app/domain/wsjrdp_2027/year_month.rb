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

    def [](index)
      case index
      when :year, "year", 0, -2
        year
      when :month, "month", 1, -1
        month
      end
    end

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
  end
end
